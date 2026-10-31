"""Network spellings (tools/networks.py): the alias table on fixture rows, and a guard over the projection.

    python3 tests/test_networks.py
    PROJECTION=path/to/ear-drama.sqlite python3 tests/test_networks.py

The guard reads the projection (out/publish/ear-drama.sqlite, or PROJECTION) when present: no
network string within edit distance 2 of another unless the pair is listed in DISTINCT. Seen to FAIL
(2026-10-30) over catalog-2026-10-30's projection before the alias table: Bllue, Bue, .Blue,
Mutaul-Don Lee, Mutrual, NBC Paciic, NBCPacific and others.
"""
import json
import os
import sqlite3
import sys
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import networks as N
import enrich_db as E

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# Typos and spacing/punctuation variants fold to their network.
for raw, want in [
    ("Bllue", "Blue"), ("Bue", "Blue"), (".Blue", "Blue"), ("Mutrual", "Mutual"), ("Mutul", "Mutual"),
    ("Mutaul-Don Lee", "Mutual-Don Lee"), (".Mutual-Don Lee", "Mutual-Don Lee"),
    ("Mutual-Don-Lee", "Mutual-Don Lee"), ("Mutual-Don lee", "Mutual-Don Lee"),
    ("Mutual Don-Lee", "Mutual-Don Lee"), ("NBC Paciic", "NBC Pacific"), ("NBCPacific", "NBC Pacific"),
    ("(NBC", "NBC"), (".NBC", "NBC"), ("NBC radio", "NBC"), ("  Mutual ", "Mutual"), ("ABC (Blue)", "ABC Blue"), ("possible Blue", None), ("Blue or Mutual", None),
    ("The Michigan Radio", "Michigan Radio"), ("ABC-Blue", "ABC Blue"),
]:
    check("alias " + raw, N.canonical_network(raw), want)

# Distinct networks are never merged, and an unknown name passes through.
for real in ["Blue", "ABC Blue", "NBC Blue", "NBC Red", "NBC Pacific", "ABC Pacific", "CBS Pacific",
             "Mutual", "Mutual-Don Lee", "Mutual Pacific", "ABC", "NBC", "CBS", "CBC", "CBCF", "BBC", "AFRS", "AFRTS",
             "Don Lee Network", "Springbok"]:
    check("distinct " + real, N.canonical_network(real), real)
check("empty", N.canonical_network("  "), None)
check("none", N.canonical_network(None), None)
check("every alias lands on a canonical name", [v for v in N.ALIASES.values() if v in N.ALIASES], [])
check("DISTINCT never lists an alias", [p for p in N.DISTINCT if any(n in N.ALIASES for n in p)], [])

# The one parse point: Goldin SOURCE text and OTRR run histories both fold.
check("parse_source typo", E.parse_source("Mutaul-Don Lee net, KHJ")[0], "Mutual-Don Lee")
check("parse_source NBC Blue is Blue", E.parse_source("NBC Blue net, WJZ")[0], "Blue")
check("parse_source Red", E.parse_source("Red net")[0], "NBC Red")

# The guard itself: a fixture with typos fails it, the folded fixture passes it.
rows = {"Blue": 1388, "Mutual": 5857, "Mutual-Don Lee": 754, "NBC Pacific": 5, "NBC": 12042, "ABC": 4909}
check("guard passes distinct names", N.near_misses(rows), [])
typos = dict(rows, Bllue=1, Mutrual=1, **{"Mutaul-Don Lee": 1, "NBC Paciic": 1})
check("guard catches typos", sorted(N.near_misses(typos)),
      [("Bllue", "Blue"), ("Mutaul-Don Lee", "Mutual-Don Lee"), ("Mutrual", "Mutual"), ("NBC Paciic", "NBC Pacific")])
check("canonical folding clears the guard", N.near_misses(
    collections.Counter({N.canonical_network(k): 1 for k in typos})), [])

# The guard over the projection.
real = os.environ.get("PROJECTION") or os.path.join(HERE, "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    d = sqlite3.connect(real)
    counts = collections.Counter()
    for n, c in d.execute("SELECT network, COUNT(*) FROM episodes WHERE network IS NOT NULL GROUP BY 1"):
        counts[n] += c
    for (j,) in d.execute("SELECT networks FROM series WHERE networks IS NOT NULL"):
        for n in json.loads(j):
            counts[n] += 0
    check("projection: every network is its canonical spelling",
          sorted(n for n in counts if N.canonical_network(n) != n), [])
    check("projection: no network within edit distance 2 of another unless listed distinct",
          sorted(N.near_misses(counts)), [])
    print(f"  projection: {len(counts)} distinct network strings")
elif os.environ.get("PROJECTION"):
    check("the projection named by PROJECTION exists", False, True)
else:
    print("  SKIP  projection guard: out/publish/ear-drama.sqlite not built")

print(f"{ran - failed}/{ran} checks passed")
sys.exit(1 if failed else 0)
