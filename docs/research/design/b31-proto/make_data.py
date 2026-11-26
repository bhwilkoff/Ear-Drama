#!/usr/bin/env python3
"""B31 mock data: real rows for the frames, written to data.js beside this file.

    python3 docs/research/design/b31-proto/make_data.py FACETS.json ART.json

FACETS.json is derive_facets.py --out, ART.json is measure_play_art.py --out. Reads the play library
(catalog/out/plays-library) for characters, scenes and line hits. Every word on a frame comes from these rows;
nothing is written for the mock except the controls' own labels.
"""
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
LIB = os.path.join(ROOT, "catalog", "out", "plays-library")
facets = json.load(open(sys.argv[1]))
art = json.load(open(sys.argv[2]))
idx = {r["id"]: r for r in json.load(open(os.path.join(LIB, "index.json")))["plays"]}

FEATURED = ["gut-3544", "gut-4023", "gut-3790", "gut-59432-101", "gut-8500-3", "gut-7700", "gut-1521", "gut-78131",
            "gut-59421", "gut-68576", "gut-65920-109", "gut-31-101"]
# Local copies of the pictures (b31-proto/img), only for pictures play_art or the book's own HTML would serve.
IMG = {"gut-3544": "img/howhelied-title.jpg", "gut-4023": "img/candida-1924.jpg", "gut-3790": "img/majorbarbara.jpg",
       "gut-8500-3": "img/strindberg.jpg", "gut-7700": "img/lysistrata-title.jpg",
       "gut-59421": "img/chushingura-front.jpg", "gut-68576": "img/poorjack-cover.jpg"}
BOOK = {"gut-59421", "gut-68576"}   # from the Gutenberg book's own illustrations (not yet harvested)


def display_author(r):
    a = r.get("authors") or []
    return ", ".join(a[:2]) + (" and others" if len(a) > 2 else "")


def row(pid):
    f, r = facets[pid], idx[pid]
    p = art.get(pid, {}).get("picture")
    pic = None
    if pid in IMG:
        kind = "book" if pid in BOOK else p["kind"] if p else None
        pic = {"src": IMG[pid], "kind": kind}
    b, d = f.get("born"), f.get("died")
    years = None
    if b is not None and d is not None:
        years = f"{-b}-{-d} BCE" if d < 0 else f"{-b} BCE-{d}" if b < 0 else f"{b}-{d}"
    return {"id": pid, "title": r["title"], "author": display_author(r), "surname": (r["authors"][0].split()[-1] if r.get("authors") else f.get("author")),
            "voices": r["voices"], "minutes": r["minutes"], "cast": r["cast"], "form": f["form"], "hue": f["formHue"],
            "era": f["era"], "years": years, "oneAct": f["oneAct"], "balance": f["balance"], "pic": pic,
            "opening": r.get("opening")}


def pick(pred, n=8, sort=None):
    ks = [k for k in facets if pred(facets[k])]
    ks.sort(key=sort or (lambda k: (facets[k]["voices"], facets[k]["minutes"], facets[k]["title"])))
    return ks, ks[:n]


V = facets
collections_out = []
for title, rule, pred in [
    ("Plays for two voices", "voices 2", lambda v: v["voices"] == 2),
    ("Ten minutes or less", "about 10 minutes or less", lambda v: v["minutes"] <= 10),
    ("One Act Plays", "Gutenberg bookshelf", lambda v: "One Act Plays" in v["shelves"]),
    ("Ensemble pieces", "no part over a quarter of the lines", lambda v: v["balance"] == "ensemble" and v["voices"] <= 10),
    ("A star part", "one part speaks half the lines", lambda v: v["balance"] == "lead"),
    ("Christmas plays", "Library of Congress subject", lambda v: any(s.startswith("Christmas plays") for s in v["subjects"])),
    ("Ireland", "Library of Congress subject", lambda v: "Ireland -- Drama" in v["subjects"]),
    ("Nobel Prizes in Literature", "Gutenberg bookshelf", lambda v: "Nobel Prizes in Literature" in v["shelves"]),
]:
    by_name = (lambda k: facets[k]["title"].lower().lstrip("the ").lstrip("a "))
    allk, first = pick(pred, 20, None if "minutes" in rule else by_name)
    collections_out.append({"title": title, "rule": rule, "count": len(allk), "plays": first})

need = set(FEATURED)
for c in collections_out:
    need.update(c["plays"])
grid_k = sorted(facets, key=lambda k: (facets[k]["voices"], facets[k]["minutes"], facets[k]["title"]))[:40]
need.update(grid_k)

counts = {
    "voices": collections.Counter("1-2" if v["voices"] <= 2 else "3-4" if v["voices"] <= 4 else "5-6" if v["voices"] <= 6
                                  else "7-10" if v["voices"] <= 10 else "11+" for v in V.values()),
    "length": collections.Counter("Up to 10 min" if v["minutes"] <= 10 else "10-20 min" if v["minutes"] <= 20 else
                                  "20-40 min" if v["minutes"] <= 40 else "40-90 min" if v["minutes"] <= 90 else "Longer"
                                  for v in V.values()),
    "form": collections.Counter((v["form"] or "unnamed") for v in V.values()),
    "era": collections.Counter((v["era"] or "undated") for v in V.values()),
    "balance": collections.Counter(v["balance"] for v in V.values()),
    "total": len(V),
}

# Scenes for two voices, from the printed headings: a few real ones.
scenes = []
for pid in sorted(facets, key=lambda k: facets[k]["title"]):
    for s in facets[pid]["scenes"]:
        if s["voices"] == 2 and 2 <= s["minutes"] <= 6 and len(scenes) < 8 and not any(x["id"] == pid for x in scenes):
            script = json.load(open(os.path.join(LIB, idx[pid]["path"])))["scripts"][0]
            ids = [l["id"] for l in script["lines"]]
            a = ids.index(s["line"])
            roles = []
            for l in script["lines"][a:]:
                if l.get("kind") == "speech" and l.get("role") not in roles:
                    roles.append(l["role"])
                if len(roles) == 2:
                    break
            head = re.split(r"[.:;,\u2014-]", s["heading"] or "")[0].strip().title()
            scenes.append({"id": pid, "play": idx[pid]["title"], "heading": head, "minutes": s["minutes"],
                           "parts": [x.title() for x in roles]})
            need.add(pid)

# Search: a character name and a remembered line, found in the real scripts.
def find_line(words, limit=4):
    hits = []
    for pid, r in idx.items():
        script = json.load(open(os.path.join(LIB, r["path"])))["scripts"][0]
        for l in script["lines"]:
            if l.get("kind") != "speech":
                continue
            t = " ".join(p.get("say") or "" for p in l.get("parts") or [])
            if re.search(r"\b" + r"\W+".join(words) + r"\b", t, re.I):   # the words in order: a remembered phrase ranks before scattered words
                m = re.search(words[0], t, re.I)
                a = max(0, m.start() - 40)
                hits.append({"id": pid, "play": r["title"], "role": l["role"].title(),
                             "text": ("…" if a else "") + " ".join(t[a:a + 120].split()) + "…"})
                break
        if len(hits) >= limit:
            break
    for h in hits:
        need.add(h["id"])
    return hits


chars = []
for pid, r in idx.items():
    script = json.load(open(os.path.join(LIB, r["path"])))["scripts"][0]
    for ro in script["roles"]:
        if re.match(r"^candida\b", ro["name"], re.I):
            chars.append({"id": pid, "play": r["title"], "role": ro["name"].title(), "lines": ro["lines"]})
            need.add(pid)
search = {"q1": "candida", "chars": chars[:4], "q2": "quality of mercy", "lines": find_line(["quality", "of", "mercy"])}

plays = {k: row(k) for k in sorted(need)}
for k in FEATURED:
    script = json.load(open(os.path.join(LIB, idx[k]["path"])))["scripts"][0]
    plays[k]["roles"] = [ro["name"].title() for ro in sorted(script["roles"], key=lambda ro: -ro["lines"])][:7]
out = {"plays": plays, "featured": FEATURED, "collections": collections_out, "grid": grid_k, "counts": counts,
       "scenes": scenes, "search": search}
with open(os.path.join(HERE, "data.js"), "w") as f:
    f.write("// Generated by make_data.py from the real play library (2026-11-26). Do not edit.\nwindow.B31 = ")
    json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    f.write(";\n")
print("plays", len(plays), "collections", [(c["title"], c["count"]) for c in collections_out])
print("scenes", len(scenes), "chars", len(chars), "lines", len(search["lines"]))
print(json.dumps(counts))
