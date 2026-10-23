"""Measure playback loudness (EBU R128) for a sample of served episodes, streamed from archive.org.

    python3 tools/measure_loudness.py                       # 200-episode stratified sample
    python3 tools/measure_loudness.py --n 400 --workers 2
    python3 tools/measure_loudness.py --report             # summarize what is measured

Research 04 §8.2: only the measurement is used. ffmpeg's `ebur128=peak=true`
reads the default copy straight from its URL (nothing is saved or re-encoded),
and each result is cached in .cache/loudness.json so a re-run measures only what
is new. The client computes gain = target - I, clamped so TP + gain <= -1 dBTP.
The sample is chosen by a stable hash of the episode id within strata of decade,
rights, and series, so a re-run measures the same episodes.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import sqlite3
import statistics
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import ia_lib as ia
from ffmpeg_limits import ffmpeg_cmd

CACHE = os.path.join(ia.CACHE, "loudness.json")
UA = "EarDrama/0.1 (+https://eardrama.org; loudness measurement)"
SUMMARY = {"I": re.compile(r"I:\s+(-?[\d.]+|-inf) LUFS"), "LRA": re.compile(r"LRA:\s+([\d.]+) LU"),
           "TP": re.compile(r"Peak:\s+(-?[\d.]+|-inf) dBFS")}


def stable(s):
    return int(hashlib.sha1(s.encode()).hexdigest()[:12], 16)


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


def measure(item):
    cmd = ffmpeg_cmd() + ["-nostats", "-hide_banner", "-user_agent", UA, "-i", item["url"],
                          "-map", "0:a:0", "-af", "ebur128=peak=true", "-f", "null", "-"]
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return {"id": item["id"], "url": item["url"], "stratum": item["stratum"], "error": "timeout after 600 s"}
    tail = p.stderr[p.stderr.rfind("Summary:"):] if "Summary:" in p.stderr else ""
    out = {"id": item["id"], "url": item["url"], "stratum": item["stratum"], "seconds": round(time.time() - t0, 1),
           "tool": "ffmpeg ebur128=peak=true", "measuredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if p.returncode or not tail:
        out["error"] = (p.stderr.strip().splitlines() or ["no output"])[-1][:200]
        return out
    for k, rx in SUMMARY.items():
        m = rx.search(tail)
        out[k] = float(m.group(1)) if m and m.group(1) != "-inf" else None
    return out


def report(cache, target):
    ok = [r for r in cache.values() if r.get("I") is not None]
    bad = [r for r in cache.values() if "error" in r]
    if not ok:
        return {"measured": 0, "errors": len(bad)}
    I = sorted(r["I"] for r in ok)
    gains = [min(target - r["I"], -1 - r["TP"]) if r.get("TP") is not None else target - r["I"] for r in ok]
    q = lambda xs, p: xs[min(len(xs) - 1, int(p * len(xs)))]
    return {"measured": len(ok), "errors": len(bad), "target": target,
            "I_median": round(statistics.median(I), 2), "I_p10": q(I, .1), "I_p90": q(I, .9),
            "I_min": I[0], "I_max": I[-1],
            "share_cut": round(sum(1 for g in gains if g < 0) / len(gains), 3),
            "share_boost_over_6dB": round(sum(1 for g in gains if g > 6) / len(gains), 3),
            "peak_limited": sum(1 for r, g in zip(ok, gains) if g < target - r["I"] - 0.05),
            "seconds_median": statistics.median(r["seconds"] for r in ok)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(ia.OUT, "publish", "ear-drama.sqlite"))
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--target", type=float, default=-18.0)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    if not a.report:
        todo = [it for it in sample(a.db, a.n) if it["id"] not in cache or "error" in cache[it["id"]]]
        print(f"{len(todo)} to measure", flush=True)
        with concurrent.futures.ThreadPoolExecutor(a.workers) as ex:
            for i, r in enumerate(ex.map(measure, todo), 1):
                cache[r["id"]] = r
                if i % 10 == 0 or i == len(todo):
                    ia.write_json(CACHE, cache)
                    print(f"{i}/{len(todo)} last I={r.get('I')} err={r.get('error', '')[:60]}", flush=True)
    rep = report(cache, a.target)
    print(json.dumps(rep, indent=1))
    if not a.report and rep["measured"] == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
