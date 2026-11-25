"""R4-9: the tables from measure.py's output. python3 report.py <out.json> [run words] [share]"""
import collections
import json
import statistics
import sys

d = json.load(open(sys.argv[1]))
RUN = int(sys.argv[2]) if len(sys.argv) > 2 else 40
SHARE = float(sys.argv[3]) if len(sys.argv) > 3 else 0.02
by = collections.OrderedDict()
for r in d["rows"]:
    by.setdefault((r["group"], r["class"]), []).append(r)


def q(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))]


def held(r):
    return r["run"] >= RUN or (r["covered"] >= SHARE and r["copied"] >= RUN)


print(json.dumps(d["index"]))
print(f"held: a run of {RUN}+ words, or {SHARE:.0%} of the script (and {RUN} words) copied from one work")
for (g, c), rows in by.items():
    n = len(rows)
    run, cov = [r["run"] for r in rows], [r["covered"] for r in rows]
    ch = [r["changed"] for r in rows if r.get("changed") not in (None, 1)]
    print(f"{g:9s} {c:32s} n={n:3d} held={sum(map(held, rows)):3d}  run p10/50/90/max {q(run, .1)}/{q(run, .5)}/{q(run, .9)}/{max(run)}"
          f"  share p10/50/90/max {q(cov, .1):.3f}/{q(cov, .5):.3f}/{q(cov, .9):.3f}/{max(cov):.3f}"
          + (f"  words changed {statistics.median(ch):.2f}" if ch else "")
          + (f"  right source {sum(bool(r.get('found_source')) for r in rows)}" if g == "plant" else ""))
