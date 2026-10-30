"""Two builds from one cache under different hash seeds must publish the same projection.

    python3 tools/check_build_determinism.py [seedA seedB]      # default 1 and 2

CI pins PYTHONHASHSEED=0, which hid every place a build followed the iteration order of a set
(two local builds differed by about 400 credit rows and 74 network rows). This runs the whole
chain (build_db, enrich_db, enrich_external, enrich_people_art, enrich_photo_archives,
build_projection) once per seed over the same .cache, then compares every table of the two
projections, ignoring only `meta` (its generatedAt). Exits non-zero, naming the table, when
they differ. About ten minutes: not in run_all.sh. It overwrites out/radio-catalog.sqlite.
"""
import os
import shutil
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STEPS = ("build_db", "enrich_db", "enrich_external", "enrich_people_art", "enrich_photo_archives")


def build(seed, dest):
    env = dict(os.environ, PYTHONHASHSEED=str(seed))
    for step in STEPS:
        subprocess.run([sys.executable, os.path.join(HERE, step + ".py")], cwd=ROOT, env=env, check=True,
                       stdout=subprocess.DEVNULL)
    shutil.rmtree(dest, ignore_errors=True)
    subprocess.run([sys.executable, os.path.join(HERE, "build_projection.py"), "--out", dest], cwd=ROOT, env=env,
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return os.path.join(dest, "ear-drama.sqlite")


def differences(a, b):
    """{table: rows only in one side (a, b)} over every ordinary table but meta and the FTS shadows."""
    c = sqlite3.connect(a)
    c.execute("ATTACH ? AS b", (b,))
    out = {}
    for (t,) in c.execute("SELECT name FROM main.sqlite_master WHERE type = 'table' AND name != 'meta' "
                          "AND name NOT LIKE 'episodes_fts%'").fetchall():
        only_a = c.execute(f"SELECT COUNT(*) FROM (SELECT * FROM main.{t} EXCEPT SELECT * FROM b.{t})").fetchone()[0]
        only_b = c.execute(f"SELECT COUNT(*) FROM (SELECT * FROM b.{t} EXCEPT SELECT * FROM main.{t})").fetchone()[0]
        if only_a or only_b:
            out[t] = (only_a, only_b)
    return out


def main():
    seeds = sys.argv[1:3] or ["1", "2"]
    work = os.path.join(ROOT, "out", "determinism")
    first = build(seeds[0], os.path.join(work, "a"))
    second = build(seeds[1], os.path.join(work, "b"))
    diff = differences(first, second)
    if diff:
        for t, (x, y) in sorted(diff.items()):
            print(f"DIFFERS {t}: {x} rows only under seed {seeds[0]}, {y} only under {seeds[1]}")
        sys.exit(1)
    print(f"identical projections under PYTHONHASHSEED={seeds[0]} and {seeds[1]}")


if __name__ == "__main__":
    main()
