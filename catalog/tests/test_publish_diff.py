"""The publish guard and diff (tools/publish_diff.py), each rule with its broken control.

    python3 tests/test_publish_diff.py
"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import zlib

TOOL = os.path.join(os.path.dirname(__file__), "..", "tools", "publish_diff.py")
ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def run(*args):
    p = subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True)
    return p.returncode, p.stdout


def manifest(path, episodes, clean, clean_only=False):
    with open(path, "w") as f:
        json.dump({"generatedAt": "t", "cleanOnly": clean_only, "counts": {"episodes": episodes, "clean": clean},
                   "bytes": {"sqlite": episodes * 1000, "zz": episodes * 200}}, f)
    return path


def db(path, ids, aliases=(), states=None, deflate=False):
    raw = path + ".raw" if deflate else path
    c = sqlite3.connect(raw)
    c.execute("CREATE TABLE episodes (id TEXT, state TEXT, rec_bucket TEXT)")
    c.execute("CREATE TABLE episode_aliases (old_id TEXT, new_id TEXT)")
    c.executemany("INSERT INTO episodes VALUES (?,?,?)",
                  [(i, (states or {}).get(i, ("keep_clean", "rec_gov_work"))[0],
                    (states or {}).get(i, ("keep_clean", "rec_gov_work"))[1]) for i in ids])
    c.executemany("INSERT INTO episode_aliases VALUES (?,?)", aliases)
    c.commit()
    c.close()
    if deflate:
        z = zlib.compressobj(9, zlib.DEFLATED, -15)
        with open(raw, "rb") as f, open(path, "wb") as o:
            o.write(z.compress(f.read()) + z.flush())
    return path


with tempfile.TemporaryDirectory() as t:
    old = manifest(os.path.join(t, "old.json"), 1000, 100)
    rc, out = run("--new-manifest", old, "--old-manifest", os.path.join(t, "absent.json"), "--max-shrink", "0.02")
    check("a first run passes", rc, 0)
    check("a first run says so", "First publish" in out, True)
    rc, _ = run("--new-manifest", os.path.join(t, "absent.json"))
    check("control: no new manifest is a run that built nothing", rc, 1)

    ok = manifest(os.path.join(t, "ok.json"), 985, 100)
    rc, out = run("--old-manifest", old, "--new-manifest", ok, "--max-shrink", "0.02")
    check("a shrink inside the floor passes", rc, 0)
    check("counts per state are printed", "| unclaimed | 900 | 885 | -15 |" in out, True)
    check("bytes are printed", "| zz | 200,000 | 197,000 | -3,000 |" in out, True)

    bad = manifest(os.path.join(t, "bad.json"), 900, 100)
    rc, out = run("--old-manifest", old, "--new-manifest", bad, "--max-shrink", "0.02")
    check("control: a shrink past the floor is refused", rc, 1)
    rc, out = run("--old-manifest", old, "--new-manifest", bad, "--max-shrink", "0.02", "--reason", "takedown")
    check("a recorded reason lets it through", rc, 0)
    check("the reason is on the record", "Recorded reason: takedown" in out, True)
    rc, _ = run("--old-manifest", old, "--new-manifest", bad)
    check("no floor given, nothing judged", rc, 0)

    gate = manifest(os.path.join(t, "gate.json"), 100, 100, clean_only=True)
    rc, out = run("--old-manifest", old, "--new-manifest", gate, "--max-shrink", "0.02")
    check("the public-web gate closing is reported, not judged", (rc, "gate changed" in out), (0, True))

    summary = os.path.join(t, "summary.md")
    run("--old-manifest", old, "--new-manifest", ok, "--summary", summary)
    check("the summary file gets the same Markdown", "what this publish changes" in open(summary).read(), True)

    o = db(os.path.join(t, "old.sqlite.zz"), ["a", "b", "c", "d"], deflate=True)
    n = db(os.path.join(t, "new.sqlite"), ["a", "b2", "e"], aliases=[("b", "b2")])
    r = db(os.path.join(t, "research.sqlite"), ["a", "b2", "c", "e"],
           states={"c": ("hide_claim", "rec_takedown")})
    rc, out = run("--old-manifest", old, "--new-manifest", ok, "--old-db", o, "--new-db", n, "--research", r)
    check("ids: aliased, hidden, and unexplained are told apart",
          "2 added, 3 removed (1 aliased to a new id, 1 now hidden by the audit, 1 gone without either)" in out, True)
    check("a hidden id names its state", "c (hide_claim: rec_takedown)" in out, True)
    check("control: an id gone without alias or hide is a warning", "::warning::1 episode ids left" in out, True)
    rc, out = run("--old-manifest", old, "--new-manifest", ok, "--old-db", o, "--new-db", n)
    check("without the research database, removals are not judged", "not judged" in out, True)

    restored = db(os.path.join(t, "restored.sqlite"), [str(i) for i in range(20)])
    full = db(os.path.join(t, "full.sqlite"), [str(i) for i in range(19)])
    half = db(os.path.join(t, "half.sqlite"), [str(i) for i in range(10)],
              states={str(i): ("hide_claim", "x") for i in range(5)})
    rc, out = run("--new-manifest", ok, "--old-research", restored, "--research", full, "--research-floor", "0.10")
    check("a rebuild near the restored snapshot passes, first publish or not", rc, 0)
    check("rights states are printed", "| keep_clean | 20 | 19 | -1 |" in out, True)
    rc, out = run("--new-manifest", ok, "--old-research", restored, "--research", half, "--research-floor", "0.10")
    check("control: a rebuild that serves far fewer than the snapshot is refused", rc, 1)
    rc, out = run("--new-manifest", ok, "--old-research", restored, "--research", half, "--research-floor", "0.10",
                  "--reason", "new rule")
    check("a recorded reason lets the rebuild through", rc, 0)

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
