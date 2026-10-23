"""The loudness batch (tools/measure_loudness.py --batch) and its cache rules.

    python3 tests/test_loudness.py

Nothing here touches the network: measurements come from a fake. Each rule has
a broken control. Rules: batch order is a stable hash, independent of the
database's row order, and successive batches walk on without repeating; the
cache only grows; implausible results are kept as `suspect` and never usable;
a shrunken cache is refused, by function and by the CLI the workflow calls.
"""
import os
import sqlite3
import subprocess
import sys
import tempfile
import time

TOOLS = os.path.join(os.path.dirname(__file__), "..", "tools")
sys.path.insert(0, TOOLS)
import measure_loudness as L

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def db(path, ids, reverse=False):
    d = sqlite3.connect(path)
    d.executescript("CREATE TABLE episodes (id TEXT PRIMARY KEY); "
                    "CREATE TABLE recordings (episode_id TEXT, rank INTEGER, url TEXT)")
    for eid in (reversed(ids) if reverse else ids):
        d.execute("INSERT INTO episodes VALUES (?)", (eid,))
        d.execute("INSERT INTO recordings VALUES (?, 0, ?)", (eid, f"https://archive.org/download/x/{eid}.mp3"))
        d.execute("INSERT INTO recordings VALUES (?, 1, ?)", (eid, f"https://archive.org/download/y/{eid}.mp3"))
    d.commit()
    d.close()


def fake(values):
    """A measure_fn returning canned results by id: a dict of fields, or 'transient'/'error'."""
    def m(item, deadline):
        v = values.get(item["id"], {"I": -19.0, "TP": -1.5})
        base = {"id": item["id"], "url": item["url"], "measuredAt": L.now_iso()}
        if v == "transient":
            return {**base, "error": "Server returned 503 Service Unavailable", "transient": True}
        if v == "error":
            return {**base, "error": "Server returned 404 Not Found"}
        r = {**base, **v}
        why = L.suspect_reason(r)
        if why:
            r["suspect"] = why
        return r
    return m


IDS = [f"series{i % 7}|19{40 + i % 20}-01-{1 + i % 28:02d}" for i in range(60)]
IDS = sorted(set(IDS))

# --- implausible results ----------------------------------------------------------
check("suspect: the sample's +9.1 LUFS", bool(L.suspect_reason({"I": 9.1, "TP": 54.0})), True)
check("suspect: the sample's -70 LUFS", bool(L.suspect_reason({"I": -70.0, "TP": 0.0})), True)
check("suspect: a true peak above +6", bool(L.suspect_reason({"I": -13.9, "TP": 6.7})), True)
check("suspect: silence (-inf parsed as None)", bool(L.suspect_reason({"I": None, "TP": None})), True)
check("control: an ordinary episode is not suspect", L.suspect_reason({"I": -19.0, "TP": -1.3}), None)
check("control: the edges are plausible", L.suspect_reason({"I": -45.0, "TP": 6.0}), None)
ok = {"url": "u", "I": -19.0, "TP": -1.3, "measuredAt": "2026-10-22T00:00:00Z"}
check("usable: a clean measurement of this copy", L.usable(ok, "u"), True)
check("control: a flagged row is not usable", L.usable({**ok, "suspect": "by hand"}, "u"), False)
check("control: implausible values are not usable even unflagged", L.usable({**ok, "I": 9.1}, "u"), False)
check("control: another copy's measurement is not usable", L.usable(ok, "v"), False)
check("control: an error is not usable", L.usable({**ok, "error": "x"}, "u"), False)

# --- stable order, additive progression -------------------------------------------
with tempfile.TemporaryDirectory() as tmp:
    a, b = os.path.join(tmp, "a.sqlite"), os.path.join(tmp, "b.sqlite")
    db(a, IDS)
    db(b, IDS, reverse=True)
    ca, cb = L.candidates(a), L.candidates(b)
    check("order: independent of the database's row order", [c["id"] for c in ca], [c["id"] for c in cb])
    check("control: the order is not the id order", [c["id"] for c in ca] != sorted(IDS), True)
    check("order: the default copy is the one measured", ca[0]["url"].startswith("https://archive.org/download/x/"), True)
    series = {c["id"].split("|")[0] for c in ca[:10]}
    check("order: one batch spreads across series", len(series) >= 4, True)

    path = os.path.join(tmp, "cache.json.gz")
    cache = {"zz|prior": {"id": "zz|prior", "url": "old", "I": -20.0, "TP": -2.0, "measuredAt": "2026-10-01T00:00:00Z"}}
    L.save(path, cache)
    first, due1 = L.plan(ca, cache, 10, 14)
    got = L.run_batch(first, cache, path, 2, None, fake({}))
    check("batch: ten measured", got["ok"], 10)
    second, due2 = L.plan(ca, cache, 10, 14)
    check("batch: the next batch is the next ten in order", [c["id"] for c in second],
          [c["id"] for c in ca[10:20]])
    check("control: no id is measured twice", set(c["id"] for c in first) & set(c["id"] for c in second), set())
    check("batch: due shrinks by what was measured", due1 - due2, 10)
    on_disk = L.load(path)
    check("batch: the cache on disk keeps the prior result", "zz|prior" in on_disk, True)
    check("batch: the cache on disk holds the batch", len(on_disk), 11)

    # Transient errors are not recorded; permanent ones are, with a retry window; suspects are kept.
    vals = {second[0]["id"]: "transient", second[1]["id"]: "error", second[2]["id"]: {"I": 9.1, "TP": 54.0}}
    got = L.run_batch(second, cache, path, 2, None, fake(vals))
    check("batch: counts", (got["ok"], got["suspect"], got["errors"], got["transient"]), (7, 1, 1, 1))
    check("control: a transient failure leaves the item unmarked", second[0]["id"] in cache, False)
    check("batch: a permanent failure is recorded with its reason", cache[second[1]["id"]]["error"],
          "Server returned 404 Not Found")
    check("batch: a suspect result is kept as evidence", cache[second[2]["id"]].get("suspect", "")[:5], "I 9.1")
    third, _ = L.plan(ca, cache, 3, 14)
    check("retry: the transient one comes back first; the error waits", [c["id"] for c in third],
          [second[0]["id"], ca[20]["id"], ca[21]["id"]])
    later, _ = L.plan(ca, cache, 2, 14, now=time.time() + 15 * 86400)
    check("retry: past the window the error is due again", [c["id"] for c in later],
          [second[0]["id"], second[1]["id"]])
    check("control: a suspect is not re-measured", second[2]["id"] in [c["id"] for c in L.plan(ca, cache, 99, 14,
          now=time.time() + 99 * 86400)[0]], False)

    # A new default copy is measured again; an error on it never erases the old measurement.
    moved = [{**c, "url": c["url"] + "?v2"} if c["id"] == first[0]["id"] else c for c in ca]
    check("url change: the new default copy is due", first[0]["id"] in [c["id"] for c in L.plan(moved, cache, 999, 14)[0]], True)
    old = dict(cache[first[0]["id"]])
    err = {"id": old["id"], "url": old["url"] + "?v2", "error": "Server returned 404 Not Found",
           "measuredAt": "2999-01-01T00:00:00Z"}
    kept = L.merge_entry(old, err)
    check("merge: an error never replaces a measurement", (kept["I"], kept["url"]), (old["I"], old["url"]))
    check("merge: the attempt is remembered", kept["lastAttempt"]["url"], old["url"] + "?v2")
    check("url change: the failed new copy waits its window", L.due(kept, old["url"] + "?v2", time.time(), 14), False)
    newer = {**old, "url": old["url"] + "?v2", "I": -22.0, "measuredAt": "2999-01-01T00:00:00Z"}
    check("merge: a newer measurement replaces an older one", L.merge_entry(old, newer)["I"], -22.0)
    check("control: an older measurement does not", L.merge_entry(newer, old)["I"], -22.0)

    # Breaker: twenty consecutive failures stop the batch.
    rest, _ = L.plan(ca, {}, 60, 14)
    got = L.run_batch(rest, {}, os.path.join(tmp, "b.json"), 1, None, fake({c["id"]: "error" for c in rest}))
    check("breaker: trips", got["breaker"], True)
    check("breaker: stops starting new copies", got["errors"], L.BREAKER)
    check("verdict: all failed", L.verdict(rest, got), "all_failed")
    check("verdict: nothing due is idle", L.verdict([], got), "idle")
    check("control: one success is a measured run",
          L.verdict(rest, {**got, "ok": 1}), "measured")

    # --- the shrink guard --------------------------------------------------------
    full = L.load(path)
    smaller = dict(full)
    smaller.pop(next(iter(smaller)))
    check("guard: growth and equality pass", (L.guard(full, full), L.guard(smaller, full)), ([], []))
    check("guard: a dropped id is refused", bool(L.guard(full, smaller)), True)
    demoted = {**full, first[3]["id"]: {"id": first[3]["id"], "url": "u", "error": "x", "measuredAt": "z"}}
    check("guard: a measurement turned into an error is refused", bool(L.guard(full, demoted)), True)
    check("guard: the empty first run passes", L.guard({}, full), [])
    merged = L.merge(full, demoted)
    check("merge: merging an error over a measurement keeps the measurement", L.guard(full, merged), [])

    small_p, full_p = os.path.join(tmp, "small.json.gz"), os.path.join(tmp, "full.json.gz")
    L.save(small_p, smaller)
    L.save(full_p, full)
    cli = lambda *args: subprocess.run([sys.executable, os.path.join(TOOLS, "measure_loudness.py"), *args],
                                       capture_output=True, text=True).returncode
    check("cli: --guard refuses a shrunken cache", cli("--guard", full_p, small_p), 1)
    check("control: cli --guard passes growth", cli("--guard", small_p, full_p), 0)
    out_p = os.path.join(tmp, "merged.json.gz")
    check("cli: --merge runs", cli("--merge", small_p, full_p, "--out", out_p), 0)
    check("cli: --merge is the union", set(L.load(out_p)), set(full))

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
