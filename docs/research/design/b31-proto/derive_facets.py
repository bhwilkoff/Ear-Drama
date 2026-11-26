#!/usr/bin/env python3
"""B31 prototype: the finding facets a library row would carry, derived from the record only.

    python3 docs/research/design/b31-proto/derive_facets.py [--out facets.json]

Reads catalog/out/plays-library (index.json and scripts/), catalog/.cache/gutenberg/pg_catalog.csv.gz.
Prints coverage per facet and writes one object per play. Research only: the build batch moves the rules
into catalog/tools (one module, golden-tested) and the library row; nothing reads this file.

Rules (each shown to a person as the rule, never a judgment):
  form     the first FORM rule matched in: LCSH Subjects, then the Gutenberg title's own subtitle
           ("...: A Comedy in Three Acts"), then Bookshelves. Unmatched = None (the neutral board).
  era      the playwright's active span: born + 25 .. died (or born + 70), from the Gutenberg Authors field;
           bucketed on the play dial (ERAS). A "[Translator]" or "[Editor]" is never the playwright.
  length   minutes from the index (words / wordsPerMinute).
  balance  lead share = largest part's lines / all spoken lines: "ensemble" <= 0.25, "lead" >= 0.5.
  scenes   per printed section (Act/Scene heading): speaking parts and minutes; a "scene for N" is a
           section with N speaking parts (2..4) and 1..12 minutes.
  verse    share of speech lines whose text keeps a line break inside one speech (the reader keeps verse
           breaks): >= 0.5 verse.
"""
import collections
import csv
import gzip
import io
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
LIB = os.path.join(ROOT, "catalog", "out", "plays-library")
PG = os.path.join(ROOT, "catalog", ".cache", "gutenberg", "pg_catalog.csv.gz")

# (form key, board hue it borrows, pattern). Order matters: the first match wins.
FORMS = [
    ("tragicomedy", "drama", r"\btragi-?comed"),
    ("farce", "comedy", r"\bfarces?\b|\bburlesques?\b|\bextravaganza"),
    ("comedy", "comedy", r"\bcomed(y|ies)\b|\bcomic\b|\bhumou?r"),
    ("tragedy", "drama", r"\btraged(y|ies)\b|\btragical\b"),
    ("history", "documentary", r"historical drama|\bchronicle play|\bhistory of king|\bhistorical play"),
    ("melodrama", "mystery", r"\bmelodrama|\bmystery and detective|\bdetective"),
    ("fantasy", "scifi", r"\bfairy|\bfantas(y|ies)\b|\bmasques?\b|\bpuppet"),
    ("religious", "serial", r"\bmoralit(y|ies)\b|\bmiracle plays?|\bmysteries and miracle|religious drama|\bbible\b.*\bdrama|\bnativity"),
    ("libretto", "news", r"\blibrett|\boperas?\b|\boperettas?\b"),
]
ONE_ACT = re.compile(r"one[- ]act|in one act|\ba play in one\b", re.I)
ERAS = [("Antiquity", -800, 499), ("Medieval", 500, 1499), ("1500s", 1500, 1599), ("1600s", 1600, 1699),
        ("1700s", 1700, 1799), ("1800s", 1800, 1899), ("1900-1930", 1900, 1930)]


def form_of(subjects, title, shelves):
    """Subjects, then the Gutenberg book's own title ("...: A Comedy", "Two Tragedies of Seneca"). Bookshelves
    are never a form: Gutenberg's "Opera" shelf holds Riders to the Sea, "Humour" is a reading list (dry run
    2026-11-26)."""
    for src, text in (("subject", subjects), ("title", title)):
        hits = [(key, hue) for key, hue, pat in FORMS if re.search(pat, text or "", re.I)]
        if src == "title" and len({h for _k, h in hits}) > 1:
            return None, None, None   # "Comprising Drama, Comedy, and Farce": an anthology's title names no one play's form
        if hits:
            return hits[0][0], hits[0][1], src
    return None, None, None


def playwright_years(authors_field):
    for a in (authors_field or "").split(";"):
        if re.search(r"\[(Translator|Editor|Illustrator|Contributor|Compiler|Commentator)", a, re.I):
            continue
        m = re.search(r"(\d{1,4})\??\s*(BCE?|B\.C\.)?\s*-\s*(\d{1,4})?\??\s*(BCE?)?", a)
        if m:
            b = int(m.group(1)) * (-1 if m.group(2) else 1)
            d = int(m.group(3)) * (-1 if (m.group(4) or (m.group(2) and m.group(3) and int(m.group(3)) < int(m.group(1)))) else 1) if m.group(3) else None
            return b, d, a.split(",")[0].strip()
    first = next((a for a in (authors_field or "").split(";") if not re.search(r"\[", a)), authors_field or "")
    return None, None, first.split(",")[0].strip() or None


def era_of(b, d):
    if b is None and d is None:
        return None, None
    lo = (b + 25) if b is not None else d - 45
    hi = min(d, b + 70) if (b is not None and d is not None) else (d if d is not None else b + 70)
    mid = (lo + hi) // 2
    for name, a, z in ERAS:
        if a <= mid <= z:
            return name, (lo, hi)
    return ("1900-1930" if mid > 1930 else "Antiquity"), (lo, hi)


def scenes(script):
    lines = script["lines"]
    pos = {l["id"]: i for i, l in enumerate(lines)}
    secs = [s for s in script.get("sections") or [] if s.get("line") in pos]
    out = []
    for i, s in enumerate(secs):
        a = pos[s["line"]]
        z = pos[secs[i + 1]["line"]] if i + 1 < len(secs) else len(lines)
        parts = collections.Counter()
        words = 0
        for l in lines[a:z]:
            if l.get("kind") == "speech" and l.get("role"):
                parts[l["role"]] += 1
                words += sum(len((p.get("say") or "").split()) for p in l.get("parts") or [])
        out.append({"heading": s.get("source"), "line": s["line"], "voices": len(parts), "words": words})
    return out


def verse_share(script):
    sp = [l for l in script["lines"] if l.get("kind") == "speech"]
    if not sp:
        return 0.0
    v = sum(1 for l in sp if any("\n" in (p.get("say") or "") for p in l.get("parts") or []))
    return v / len(sp)


def main():
    idx = json.load(open(os.path.join(LIB, "index.json")))
    wpm = idx.get("wordsPerMinute") or 150
    pg = {}
    with gzip.open(PG, "rt", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            pg[row["Text#"]] = row
    out = {}
    cov = collections.Counter()
    forms = collections.Counter()
    form_src = collections.Counter()
    eras = collections.Counter()
    scene_n = collections.Counter()
    for r in idx["plays"]:
        gid = r["id"].split("-")[1]
        row = pg.get(gid, {})
        title = row.get("Title") or r["title"]
        subjects, shelves = row.get("Subjects", ""), row.get("Bookshelves", "")
        split = r["id"].count("-") == 2   # a play cut from a volume: the volume's title names its contents, not this play's form
        form, hue, src = form_of(subjects, r["title"] if split else title, shelves)
        b, d, author = playwright_years(row.get("Authors"))
        era, span = era_of(b, d)
        if era is None and (row.get("LoCC") or "").startswith("PA"):
            era = "Antiquity"   # LoCC PA: Greek and Latin literature, the class number's own claim
        cast = [n for n in r.get("cast") or [] if n > 0]
        lead = (cast[0] / sum(cast)) if cast else None
        one_act = bool(ONE_ACT.search(" ".join([subjects, shelves, title]))) or None
        try:
            script = json.load(open(os.path.join(LIB, r["path"])))["scripts"][0]
            sc = scenes(script)
            vs = verse_share(script)
        except Exception:  # noqa: BLE001
            sc, vs = [], None
        for s in sc:
            s["minutes"] = round(s["words"] / wpm)
        fit = [s for s in sc if 2 <= s["voices"] <= 4 and 1 <= s["minutes"] <= 12]
        rec = {"title": r["title"], "author": author, "authors": r.get("authors"), "voices": r["voices"],
               "minutes": r["minutes"], "cast": cast, "lead": round(lead, 3) if lead else None,
               "balance": "ensemble" if lead is not None and lead <= 0.25 else "lead" if lead is not None and lead >= 0.5 else "mixed",
               "form": form, "formHue": hue, "formSource": src, "born": b, "died": d, "era": era, "span": span,
               "oneAct": one_act, "verse": round(vs, 2) if vs is not None else None, "sections": len(sc),
               "scenesFor": sorted({s["voices"] for s in fit}), "scenes": fit[:6],
               "locc": row.get("LoCC"), "translated": bool(re.search(r"Translations into English", subjects)),
               "subjects": [s.strip() for s in subjects.split(";") if s.strip()],
               "shelves": [s.strip() for s in shelves.split(";") if s.strip()],
               "collection": r.get("collection"), "gutTitle": title}
        out[r["id"]] = rec
        cov["form"] += bool(form)
        cov["era"] += bool(era)
        cov["sections>1"] += len(sc) > 1
        cov["scene for 2-4"] += bool(fit)
        cov["verse>=0.5"] += bool(vs and vs >= 0.5)
        cov["oneAct named"] += bool(one_act)
        forms[form] += 1
        form_src[src] += 1
        eras[era] += 1
        for n in rec["scenesFor"]:
            scene_n[n] += 1
    n = len(out)
    print(f"plays {n}")
    for k, v in cov.items():
        print(f"  {k:16s} {v:5d} {v / n:.1%}")
    print("  forms:", dict(forms.most_common()))
    print("  form source:", dict(form_src))
    print("  eras:", dict(eras.most_common()))
    print("  plays with a scene for N voices:", dict(sorted(scene_n.items())))
    total_scenes = sum(len(v["scenes"]) for v in out.values())
    print("  scenes listed (2-4 voices, 1-12 min, first six per play):", total_scenes)
    if "--out" in sys.argv:
        json.dump(out, open(sys.argv[sys.argv.index("--out") + 1], "w"), indent=0)


if __name__ == "__main__":
    main()
