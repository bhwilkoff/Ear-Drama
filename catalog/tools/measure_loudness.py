"""Measure playback loudness (EBU R128) for served episodes, streamed from archive.org.

    python3 tools/measure_loudness.py                       # 200-episode stratified sample
    python3 tools/measure_loudness.py --n 400 --workers 2
    python3 tools/measure_loudness.py --report             # summarize what is measured
    python3 tools/measure_loudness.py --batch 1000 --cache C.json.gz --max-minutes 200 --summary S.json
    python3 tools/measure_loudness.py --merge FRESH RUN --out OUT.json.gz   # additive merge
    python3 tools/measure_loudness.py --guard OLD NEW                       # refuse a shrunken cache

Research 04 §8.2: only the measurement is used. ffmpeg's `ebur128=peak=true`
reads the default copy straight from its URL (nothing is saved or re-encoded),
and each result is cached in .cache/loudness.json so a re-run measures only what
is new. The client computes gain = target - I, clamped so TP + gain <= -1 dBTP
(Decision 061: the target lives in the clients, -21 LUFS).
The sample is chosen by a stable hash of the episode id within strata of decade,
rights, and series, so a re-run measures the same episodes.

`--batch N` is the whole-catalog mode (.github/workflows/catalog-loudness.yml):
the next N default copies not yet measured, in the order of a stable hash of
the episode id, so every batch spreads across series and decades. A copy
measured at its current URL is never measured again; a permanent error waits
--retry-days before a retry; a transient one (429, 5xx, a dropped connection)
is not recorded, so the next run tries it again. An implausible result is kept
with a `suspect` reason as evidence and never published: `usable` is the one
predicate, and build_projection.py imports it.
"""
import argparse
import calendar
import concurrent.futures
import gzip
import hashlib
import json
import os
import re
import sqlite3
import statistics
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import ia_lib as ia

CACHE = os.path.join(ia.CACHE, "loudness.json")
UA = "EarDrama/0.1 (+https://eardrama.org; loudness measurement)"
SUMMARY = {"I": re.compile(r"I:\s+(-?[\d.]+|-inf) LUFS"), "LRA": re.compile(r"LRA:\s+([\d.]+) LU"),
           "TP": re.compile(r"Peak:\s+(-?[\d.]+|-inf) dBFS")}
# Outside these a measurement is a broken file or a broken decode, not a loud or
# quiet show (the sample's +9.1 and -70 LUFS episodes, Decision 061).
I_MAX, I_MIN, TP_MAX = -5.0, -45.0, 6.0
ITEM_TIMEOUT = 600
TRANSIENT = re.compile(r"\b(429|5\d\d)\b|Too Many Requests|Connection (reset|refused|timed out)|"
                       r"Temporary failure|Network is unreachable|Could not resolve", re.I)
BREAKER = 20          # consecutive failures stop a batch: the host is refusing us, not the files


def stable(s):
    return int(hashlib.sha1(s.encode()).hexdigest()[:12], 16)


def now_iso(t=None):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def suspect_reason(r):
    """Why a measurement is implausible, or None. The values stay as evidence."""
    i, tp = r.get("I"), r.get("TP")
    if i is None:
        return "no integrated loudness (silent or undecodable)"
    if i > I_MAX:
        return f"I {i} LUFS above {I_MAX}"
    if i < I_MIN:
        return f"I {i} LUFS below {I_MIN}"
    if tp is None:
        return "no true peak"
    if tp > TP_MAX:
        return f"TP {tp} dBTP above +{TP_MAX}"
    return None


def usable(r, url=None):
    """A clean measurement of THIS copy: the only rows a projection may publish."""
    if not r or "error" in r or r.get("suspect") or suspect_reason(r):
        return False
    return url is None or r.get("url") == url


def has_measurement(r):
    return bool(r) and "error" not in r and "measuredAt" in r


def sample(db, n):
    """Round-robin across (decade, rights) strata, at most two per series, by stable hash."""
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = c.execute("SELECT e.id, e.series_key, substr(e.air_date, 1, 3), e.rights, r.url, r.length_s "
                     "FROM episodes e JOIN recordings r ON r.episode_id = e.id AND r.rank = 0 "
                     "WHERE r.length_s > 300").fetchall()
    strata = {}
    for eid, sk, dec, rights, url, length in rows:
        strata.setdefault((dec or "undated", rights), []).append((stable(eid), eid, sk, url, length))
    for v in strata.values():
        v.sort()
    picked, per_series = [], {}
    keys = sorted(strata)
    while len(picked) < n and any(strata[k] for k in keys):
        for k in keys:
            while strata[k]:
                _, eid, sk, url, length = strata[k].pop(0)
                if per_series.get(sk, 0) < 2:
                    per_series[sk] = per_series.get(sk, 0) + 1
                    picked.append({"id": eid, "url": url, "length_s": length, "stratum": f"{k[0]}0s/{k[1]}"})
                    break
            if len(picked) >= n:
                break
    return picked


def measure(item, deadline=None):
    """One copy, streamed. None when the run's budget leaves no room for it (not the item's fault)."""
    from ffmpeg_limits import ffmpeg_cmd
    timeout = ITEM_TIMEOUT
    if deadline is not None:
        timeout = min(ITEM_TIMEOUT, deadline - time.time())
        if timeout < 30:
            return None
    cmd = ffmpeg_cmd() + ["-nostats", "-hide_banner", "-user_agent", UA, "-i", item["url"],
                          "-map", "0:a:0", "-af", "ebur128=peak=true", "-f", "null", "-"]
    t0 = time.time()
    base = {"id": item["id"], "url": item["url"], "tool": "ffmpeg ebur128=peak=true", "measuredAt": now_iso()}
    if item.get("stratum"):
        base["stratum"] = item["stratum"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        if timeout < ITEM_TIMEOUT:
            return None            # the run's budget ran out mid-item; not recorded against it
        return {**base, "seconds": ITEM_TIMEOUT, "error": f"timeout after {ITEM_TIMEOUT} s"}
    tail = p.stderr[p.stderr.rfind("Summary:"):] if "Summary:" in p.stderr else ""
    out = {**base, "seconds": round(time.time() - t0, 1)}
    if p.returncode or not tail:
        out["error"] = (p.stderr.strip().splitlines() or ["no output"])[-1][:200]
        if TRANSIENT.search(p.stderr[-2000:]):
            out["transient"] = True
        return out
    for k, rx in SUMMARY.items():
        m = rx.search(tail)
        out[k] = float(m.group(1)) if m and m.group(1) != "-inf" else None
    why = suspect_reason(out)
    if why:
        out["suspect"] = why
    return out


def load(path):
    if not path or not os.path.exists(path):
        return {}
    with (gzip.open if path.endswith(".gz") else open)(path, "rt", encoding="utf-8") as f:
        return json.load(f)


def save(path, cache):
    ia.write_json(path, cache, gz=path.endswith(".gz"))


def attempted_at(r):
    """When this id was last tried, whatever came of it."""
    return max([r.get("measuredAt") or "", ((r.get("lastAttempt") or {}).get("at") or "")])


def merge_entry(old, new):
    """Additive: a measurement is never replaced by an error, only by a newer measurement."""
    if not old:
        return new
    if not new or new is old:
        return old
    newer = (new.get("measuredAt") or "") >= (old.get("measuredAt") or "")
    if "error" in new:
        if has_measurement(old):
            if (new.get("measuredAt") or "") > attempted_at(old):
                return {**old, "lastAttempt": {"url": new.get("url"), "at": new.get("measuredAt"),
                                               "error": new["error"]}}
            return old
        return new if newer else old
    if "error" in old:
        return new
    return new if newer else old


def merge(a, b):
    out = dict(a)
    for k, v in b.items():
        out[k] = merge_entry(out.get(k), v)
    return out


def tally(cache):
    return {"entries": len(cache), "measured": sum(1 for r in cache.values() if has_measurement(r)),
            "usable": sum(1 for r in cache.values() if usable(r)),
            "suspect": sum(1 for r in cache.values() if has_measurement(r) and not usable(r)),
            "errors": sum(1 for r in cache.values() if "error" in r)}


def guard(old, new):
    """Why `new` must not be published over `old` (empty list = it may)."""
    a, b = tally(old), tally(new)
    bad = [f"{k} {a[k]} -> {b[k]}" for k in ("entries", "measured") if b[k] < a[k]]
    lost = [k for k in old if k not in new]
    if lost:
        bad.append(f"{len(lost)} ids dropped (first: {lost[0]})")
    return bad


def candidates(db):
    """Every served episode's default copy, in stable-hash order."""
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = c.execute("SELECT e.id, r.url FROM episodes e "
                     "JOIN recordings r ON r.episode_id = e.id AND r.rank = 0").fetchall()
    c.close()
    return [{"id": eid, "url": url} for _, eid, url in sorted((stable(eid), eid, url) for eid, url in rows)]


def due(r, url, now, retry_days):
    """Should this copy be measured now?"""
    if not r:
        return True
    if has_measurement(r) and r.get("url") == url:
        return False
    tried = [(r.get("url"), r.get("measuredAt"))] + [((r.get("lastAttempt") or {}).get("url"),
                                                      (r.get("lastAttempt") or {}).get("at"))]
    for u, at in tried:
        if u == url and at and now - calendar.timegm(time.strptime(at, "%Y-%m-%dT%H:%M:%SZ")) < retry_days * 86400:
            return False
    return True


def plan(cands, cache, n, retry_days, now=None):
    """The next n copies due, and how many are due in all."""
    now = time.time() if now is None else now
    todo = [it for it in cands if due(cache.get(it["id"]), it["url"], now, retry_days)]
    return todo[:n], len(todo)


def run_batch(todo, cache, path, workers, deadline, measure_fn=measure):
    """Measure `todo`, saving additively as it goes. Returns this run's counts."""
    got = {"ok": 0, "suspect": 0, "errors": 0, "transient": 0, "not_started": 0, "breaker": False}
    state = {"consecutive": 0}
    lock = threading.Lock()

    def one(item):
        if got["breaker"]:
            return None
        r = measure_fn(item, deadline)
        if r is not None:
            with lock:
                state["consecutive"] = state["consecutive"] + 1 if "error" in r else 0
                if state["consecutive"] >= BREAKER:
                    got["breaker"] = True
        return r

    done = 0
    with concurrent.futures.ThreadPoolExecutor(workers) as ex:
        for r in ex.map(one, todo):
            if r is None:
                got["not_started"] += 1
                continue
            done += 1
            if "error" in r:
                if r.get("transient"):
                    got["transient"] += 1
                    continue
                got["errors"] += 1
            else:
                got["suspect" if r.get("suspect") else "ok"] += 1
            cache[r["id"]] = merge_entry(cache.get(r["id"]), r)
            if done % 25 == 0:
                save(path, cache)
                print(f"{done}/{len(todo)} last I={r.get('I')} err={r.get('error', '')[:60]}", flush=True)
    save(path, cache)
    return got


def verdict(todo, got):
    """idle: nothing was due. all_failed: something was due and nothing measured. measured otherwise."""
    if not todo:
        return "idle"
    if got["ok"] + got["suspect"] == 0:
        return "all_failed"
    return "measured"


def report(cache, target):
    ok = [r for r in cache.values() if usable(r)]
    bad = [r for r in cache.values() if "error" in r]
    sus = [r for r in cache.values() if has_measurement(r) and not usable(r)]
    if not ok:
        return {"measured": 0, "errors": len(bad), "suspect": len(sus)}
    I = sorted(r["I"] for r in ok)
    gains = [min(target - r["I"], -1 - r["TP"]) for r in ok]
    q = lambda xs, p: xs[min(len(xs) - 1, int(p * len(xs)))]
    return {"measured": len(ok), "errors": len(bad), "suspect": len(sus), "target": target,
            "I_median": round(statistics.median(I), 2), "I_p10": q(I, .1), "I_p90": q(I, .9),
            "I_min": I[0], "I_max": I[-1],
            "share_cut": round(sum(1 for g in gains if g < 0) / len(gains), 3),
            "share_boost_over_6dB": round(sum(1 for g in gains if g > 6) / len(gains), 3),
            "peak_limited": sum(1 for r, g in zip(ok, gains) if g < target - r["I"] - 0.05),
            "seconds_median": statistics.median(r["seconds"] for r in ok)}


def main():
    t_start = time.time()           # the budget runs from process start (docs/CI-FLEET.md §2)
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(ia.OUT, "publish", "ear-drama.sqlite"))
    ap.add_argument("--cache", default=CACHE, help=".json or .json.gz")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--batch", type=int, help="measure the next N unmeasured default copies")
    ap.add_argument("--max-minutes", type=float, help="stop starting new copies past this")
    ap.add_argument("--retry-days", type=float, default=14.0)
    ap.add_argument("--summary", help="write this run's counts and verdict as JSON")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--target", type=float, default=-21.0)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--merge", nargs=2, metavar=("FRESH", "RUN"))
    ap.add_argument("--out")
    ap.add_argument("--guard", nargs=2, metavar=("OLD", "NEW"))
    a = ap.parse_args()

    if a.guard:
        old, new = load(a.guard[0]), load(a.guard[1])
        bad = guard(old, new)
        print(f"guard: {tally(old)} -> {tally(new)}")
        if bad:
            raise SystemExit("refusing a shrunken loudness cache: " + "; ".join(bad))
        return
    if a.merge:
        if not a.out:
            raise SystemExit("--merge needs --out")
        fresh, run = load(a.merge[0]), load(a.merge[1])
        out = merge(fresh, run)
        save(a.out, out)
        print(f"merged: fresh {tally(fresh)} + run {tally(run)} -> {tally(out)}")
        return

    cache = load(a.cache)
    if a.batch is not None:
        deadline = t_start + a.max_minutes * 60 if a.max_minutes else None
        cands = candidates(a.db)
        todo, due_n = plan(cands, cache, a.batch, a.retry_days)
        print(f"{len(cands)} default copies; {due_n} due; measuring {len(todo)}", flush=True)
        got = run_batch(todo, cache, a.cache, a.workers, deadline)
        t = tally(cache)
        covered = sum(1 for it in cands if has_measurement(cache.get(it["id"]))
                      and cache[it["id"]].get("url") == it["url"])
        summary = {**got, "planned": len(todo), "due_after": due_n - got["ok"] - got["suspect"] - got["errors"],
                   "copies": len(cands), "covered": covered, "cache": t, "verdict": verdict(todo, got),
                   "minutes": round((time.time() - t_start) / 60, 1)}
        if a.summary:
            ia.write_json(a.summary, summary)
        print(f"[catalog-loudness] measured {got['ok']} ok, {got['suspect']} suspect, {got['errors']} errors, "
              f"{got['transient']} transient of {len(todo)} planned; {covered} of {len(cands)} default copies "
              f"measured; verdict {summary['verdict']}", flush=True)
        return

    if not a.report:
        todo = [it for it in sample(a.db, a.n) if it["id"] not in cache or "error" in cache[it["id"]]]
        print(f"{len(todo)} to measure", flush=True)
        run_batch(todo, cache, a.cache, a.workers, None)
    rep = report(cache, a.target)
    print(json.dumps(rep, indent=1))
    if not a.report and rep["measured"] == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
