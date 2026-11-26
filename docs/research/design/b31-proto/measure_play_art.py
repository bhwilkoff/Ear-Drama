#!/usr/bin/env python3
"""B31 dry run: what pictures the play library WOULD carry if play_art.attach read the real caches.

    python3 docs/research/design/b31-proto/measure_play_art.py INDEX.json [--out rows.json]

Reads catalog/.cache (art_v2, people_wd, loc, commons: restore them from the dated catalog Release's
harvest-cache.tar.xz) and the plain-text Gutenberg cache (illustration markers). No network: the one
fallback that could fetch (enrich_people_art.page_text) only reads caches. Writes nothing to the catalog.
"""
import collections
import gzip
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "catalog", "tools"))
import play_art  # noqa: E402

idx = json.load(open(sys.argv[1]))
rows = [dict(r) for r in idx["plays"]]
ctx = play_art.load()
print("cache: plays.json.gz records", len(ctx["plays"]), "files", len(ctx["files"]), "ftp titles", len(ctx["ftp"]))

play_art.attach(rows, ctx)
n = len(rows)
book = lambda pid: re.sub(r"-[0-9]+$", "", pid) if re.match(r"^gut-[0-9]+-[0-9]+$", pid) else pid
in_cache = sum(1 for r in rows if book(r["id"]) in ctx["plays"])
c = collections.Counter()
lead = collections.Counter()
for r in rows:
    for k in ("titlePage", "production", "authorArt", "picture"):
        if r.get(k):
            c[k] += 1
    if r.get("picture"):
        lead[r["picture"]["kind"]] += 1
print(f"library rows {n}; book id in plays.json.gz {in_cache} ({in_cache / n:.0%})")
for k in ("picture", "titlePage", "production", "authorArt"):
    print(f"  {k:10s} {c[k]:5d}  {c[k] / n:.1%}")
print("  lead kinds:", dict(lead))
work_level = sum(1 for r in rows if r.get("picture") and r["picture"]["kind"] in ("work", "production", "titlePage"))
print(f"  work-level lead (work, production, title page): {work_level} {work_level / n:.1%}")

# A distinct-picture test: how many plays share their lead image with another play.
by_url = collections.Counter(r["picture"]["url"] for r in rows if r.get("picture"))
shared = sum(v for v in by_url.values() if v > 1)
print(f"  plays whose lead picture is shared with another play: {shared}; top: {by_url.most_common(3)}")

# Illustrations inside the book: Gutenberg's plain text marks each plate "[Illustration".
text_dir = os.path.join(ROOT, "catalog", ".cache", "gutenberg", "text")
ill = {}
for r in rows:
    gid = book(r["id"]).split("-")[1]
    p = os.path.join(text_dir, gid + ".txt")
    if gid not in ill and os.path.exists(p):
        t = open(p, encoding="utf-8", errors="replace").read()
        ill[gid] = len(re.findall(r"\[Illustration", t))
books = len(ill)
with_ill = [g for g, k in ill.items() if k]
rows_ill = sum(1 for r in rows if ill.get(book(r["id"]).split("-")[1]))
print(f"books with a text {books}; with at least one [Illustration] marker {len(with_ill)} ({len(with_ill) / max(books, 1):.0%});"
      f" library rows from those books {rows_ill} ({rows_ill / n:.0%})")
no_pic_ill = sum(1 for r in rows if not r.get("picture") and ill.get(book(r["id"]).split("-")[1]))
print(f"  rows with no picture whose book has an illustration marker: {no_pic_ill}")
if "--out" in sys.argv:
    out = sys.argv[sys.argv.index("--out") + 1]
    json.dump({r["id"]: {k: r.get(k) for k in ("titlePage", "production", "authorArt", "picture")} | {"ill": ill.get(book(r["id"]).split("-")[1], 0)}
               for r in rows}, open(out, "w"))
    print("wrote", out)
