"""How a play is found (BACKLOG-LOOP B31 C3, design `docs/research/design/B31-finding-a-play.md` sections 2.3 and 3,
catalog DECISIONS 050): the facets each library row carries, the scenes for two to four voices, the collections, the
characters and the words said, all computed once here from the record and the script and never by a client.

    facet_row(row, entry, record)       the row with form, era, life, oneAct, balance, subjects, locc, scenes ...
    facets_meta(rows)                   index["facets"]: each facet's values, bounds and counts
    write_finding(out, rows, entries)   collections.json, characters.json, search/said/<p>.json beside index.json

Every value is a rule a person can be shown, never a judgment:
  form      the first form heading in the book's LCSH Subjects, else in the Gutenberg title ("...: A Comedy in Three
            Acts"); never from a Bookshelf (Gutenberg's "Opera" shelf holds Riders to the Sea). A title that names two
            forms names none ("Comprising Drama, Comedy, and Farce"). A play cut from a volume never takes the
            volume's title (it names the volume's contents), and takes a subject's form only when the volume's
            subjects name that one form and no other and the volume's title is not a collection's ("Original Plays":
            Gilbert's volume is filed under "Operas -- Librettos", and Engaged is a comedy).
  era       the playwright's working years (born + 25 to died, at most born + 70), from the record's author dates,
            on seven fixed cells; LoCC PA (Greek and Latin literature) is Antiquity when undated.
  balance   the largest part's share of the spoken lines: ensemble at most a quarter, lead at least half with
            three or more parts.
  scenes    a printed section with 2 to 4 speaking parts and 1 to 12 minutes.
"""
import collections
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

WORDS_PER_MINUTE = 150
# (form, the board hue it borrows (WEB-DESIGN 6.4r), pattern). The first match wins.
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
HUE = {k: h for k, h, _ in FORMS}
ONE_ACT = re.compile(r"one[- ]act|in one act|\ba play in one\b", re.I)
ERAS = [("Antiquity", -800, 499), ("Medieval", 500, 1499), ("1500s", 1500, 1599), ("1600s", 1600, 1699),
        ("1700s", 1700, 1799), ("1800s", 1800, 1899), ("1900-1930", 1900, 1930)]
VOICES = [[2, 2], [3, 4], [5, 6], [7, 10], [11, None]]
MINUTES = [[0, 10], [11, 20], [21, 40], [41, 90], [91, None]]
ENSEMBLE, LEAD = 0.25, 0.5
FOLD_UNDER = 5             # a facet value with fewer plays is shown under "Not named" (design 3.1)
SCENE_VOICES, SCENE_MINUTES, SCENES_KEPT = (2, 4), (1, 12), 6
LOCC = re.compile(r"^[A-Z]{1,2}$")
TRANSLATED = re.compile(r"Translations into English")


def subjects_of(record):
    """The record's LCSH headings (the RDF lists the LoCC class among them: that is `locc`)."""
    return [s for s in (record or {}).get("subjects") or [] if not LOCC.match(s)]


def _hits(text):
    return [(k, h) for k, h, pat in FORMS if re.search(pat, text or "", re.I)]


COLLECTION_TITLE = re.compile(r"\b(?:Plays|Dramas|Works|Collection|Volume|Vol\.|Series|Comedies|Tragedies|Farces|Pieces|Reader)\b|"
                              r"\band other\b|\[", re.I)


def form_of(subjects, title, split=False, play_title=None):
    """(form, source) or (None, None). subjects: the record's headings; title: the Gutenberg title; a play cut from a
    volume (split) reads its own printed title (play_title), never the volume's, and a subject only when the volume's
    subjects name one form and its title is not a collection's."""
    hits = [h for s in subjects for h in _hits(s)]
    if hits and (not split or len({k for k, _ in hits}) == 1 and not COLLECTION_TITLE.search(title or "")):
        return hits[0][0], "subject"
    t_hits = _hits(play_title if split else title)
    if len({h for _k, h in t_hits}) > 1:
        return None, None   # an anthology's title names no one play's form
    if t_hits:
        return t_hits[0][0], "title"
    return None, None


def playwright(record):
    """(born, died) of the first author with a date (translators are a separate list, never the playwright)."""
    for a in (record or {}).get("authors") or []:
        if a.get("role", "author") == "author" and (a.get("born") is not None or a.get("died") is not None):
            return a.get("born"), a.get("died")
    return None, None


def era_of(born, died):
    if born is None and died is None:
        return None
    lo = born + 25 if born is not None else died - 45
    hi = min(died, born + 70) if born is not None and died is not None else died if died is not None else born + 70
    mid = (lo + hi) // 2
    for name, a, z in ERAS:
        if a <= mid <= z:
            return name
    return "1900-1930" if mid > 1930 else "Antiquity"


def balance_of(cast):
    """ensemble: no part over a quarter of the spoken lines; lead (a star part): one part of three or more speaks at
    least half of them (in a two-hander one part always has half: that is not a star part); else mixed."""
    spoken = sorted((n for n in cast or [] if n > 0), reverse=True)
    if not spoken:
        return None
    share = spoken[0] / sum(spoken)
    if share <= ENSEMBLE:
        return "ensemble"
    return "lead" if share >= LEAD and len(spoken) >= 3 else "mixed"


def topics(subjects):
    """The topic of each "X -- Drama" heading (its first part), once each, in the record's order."""
    out = []
    for s in subjects:
        parts = [p.strip() for p in s.split(" -- ")]
        if len(parts) >= 2 and parts[-1] == "Drama" and parts[0] not in out:
            out.append(parts[0])
    return out


def heading_of(source):
    """A printed section heading as a scene card shows it: cut at its first punctuation, italic marks dropped, and
    cased like a title when printed in capitals ("SCENE III.--_OUTSIDE..._" is "Scene III")."""
    import build_castable_scripts as B
    h = re.split(r"[.,;:!?()\[\]—–]|--|-\s", (source or "").replace("_", ""), maxsplit=1)[0].strip()
    if not h:
        return None
    if h.upper() == h:
        import build_play_library as L
        h = L.good_case(B.cased_title(h))
    return h


def scenes_of(entry, wpm=WORDS_PER_MINUTE):
    """Each printed section with 2 to 4 speaking parts and 1 to 12 minutes, in text order, at most six:
    {line, heading, voices, minutes, parts} with parts largest first (the order a cast sheet reads)."""
    lines = entry.get("lines") or []
    pos = {l["id"]: i for i, l in enumerate(lines)}
    secs = [s for s in entry.get("sections") or [] if s.get("line") in pos]
    out = []
    for i, s in enumerate(secs):
        a = pos[s["line"]]
        z = pos[secs[i + 1]["line"]] if i + 1 < len(secs) else len(lines)
        parts, words = collections.Counter(), 0
        for l in lines[a:z]:
            if l.get("kind") == "speech" and l.get("role"):
                parts[l["role"]] += 1
                words += sum(len((p.get("say") or "").split()) for p in l.get("parts") or [])
        minutes = round(words / wpm)
        heading = heading_of(s.get("source"))
        if heading and SCENE_VOICES[0] <= len(parts) <= SCENE_VOICES[1] and SCENE_MINUTES[0] <= minutes <= SCENE_MINUTES[1]:
            out.append({"line": s["line"], "heading": heading, "voices": len(parts), "minutes": minutes,
                        "parts": [r for r, _n in sorted(parts.items(), key=lambda kv: (-kv[1], kv[0]))]})
        if len(out) == SCENES_KEPT:
            break
    return out


def facet_row(row, entry, record=None, catalog_row=None):
    """The index row with its finding facets, each absent when unknown (contract 4.1)."""
    split = bool(re.fullmatch(r"gut-\d+-\d+", row["id"]))
    subjects = subjects_of(record)
    title = (record or {}).get("title") or row["title"]
    form, src = form_of(subjects, title, split, row["title"])
    if form:
        row["form"], row["formSource"], row["hue"] = form, src, HUE[form]
    born, died = playwright(record)
    if born is None and died is None:
        named = [a for a in entry.get("authors") or [] if a.get("born") is not None or a.get("died") is not None]
        if named:
            born, died = named[0].get("born"), named[0].get("died")
    locc = next((s for s in (record or {}).get("subjects") or [] if LOCC.match(s)), None) or \
        (re.match(r"[A-Z]{1,2}", ((catalog_row or {}).get("LoCC") or "").strip()) or [None])[0]
    era = era_of(born, died) or ("Antiquity" if locc == "PA" else None)
    if era:
        row["era"] = era
    if born is not None or died is not None:
        row["life"] = {k: v for k, v in (("born", born), ("died", died)) if v is not None}
    shelves = (record or {}).get("shelves") or []
    if ONE_ACT.search(" ".join(subjects + shelves + [title])):
        row["oneAct"] = True
    b = balance_of(row.get("cast"))
    if b:
        row["balance"] = b
    t = topics(subjects)
    if t:
        row["subjects"] = t
    if locc:
        row["locc"] = locc
    if any(TRANSLATED.search(s) for s in subjects):
        row["translated"] = True
    if any(a.get("attributed") for a in entry.get("authors") or []):
        row["attributed"] = True
    sc = scenes_of(entry)
    if sc:
        row["scenes"] = sc
    return row


def keep_subjects(rows):
    """Topics on five or more plays: what Filters offers; a row keeps only those."""
    n = collections.Counter(t for r in rows for t in r.get("subjects") or [])
    keep = {t for t, c in n.items() if c >= FOLD_UNDER}
    for r in rows:
        if "subjects" in r:
            r["subjects"] = [t for t in r["subjects"] if t in keep]
            if not r["subjects"]:
                del r["subjects"]
    return rows


def _bin(value, bounds):
    return next(i for i, (lo, hi) in enumerate(bounds) if value >= lo and (hi is None or value <= hi))


def facets_meta(rows):
    """Each facet's values with their counts over all rows, for pickers that never offer an empty choice."""
    forms = collections.Counter(r.get("form") for r in rows)
    shown = [k for k, _h, _p in FORMS if forms[k] >= FOLD_UNDER]
    eras = collections.Counter(r.get("era") for r in rows)
    subj = collections.Counter(t for r in rows for t in r.get("subjects") or [])
    loccs = collections.Counter(r.get("locc") for r in rows if r.get("locc"))
    vb = collections.Counter(_bin(r["voices"], VOICES) for r in rows)
    mb = collections.Counter(_bin(r["minutes"], MINUTES) for r in rows)
    bal = collections.Counter(r.get("balance") for r in rows if r.get("balance"))
    return {
        "voices": [{"min": lo, "max": hi, "count": vb[i]} for i, (lo, hi) in enumerate(VOICES)],
        "minutes": [{"min": lo, "max": hi, "count": mb[i]} for i, (lo, hi) in enumerate(MINUTES)],
        "form": [{"value": k, "hue": HUE[k], "count": forms[k]} for k in shown]
                + [{"value": None, "count": sum(c for k, c in forms.items() if k not in shown)}],
        "era": [{"value": name, "count": eras[name]} for name, _a, _z in ERAS] + [{"value": None, "count": eras[None]}],
        "balance": [{"value": k, "count": bal[k]} for k in ("ensemble", "mixed", "lead")],
        "subjects": [{"value": t, "count": c} for t, c in sorted(subj.items(), key=lambda kv: (-kv[1], kv[0]))],
        "locc": [{"value": k, "count": c} for k, c in sorted(loccs.items(), key=lambda kv: (-kv[1], kv[0]))],
        "oneAct": sum(1 for r in rows if r.get("oneAct")),
        "translated": sum(1 for r in rows if r.get("translated")),
        "scenes": {str(n): sum(1 for r in rows if any(s["voices"] == n for s in r.get("scenes") or []))
                   for n in range(SCENE_VOICES[0], SCENE_VOICES[1] + 1)},
        "foldUnder": FOLD_UNDER,
    }


# ---------------------------------------------------------------- collections (design 3.2)

EDITOR_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plays", "collections.json")
EDITOR_MIN_PLAYS = 3
AUTHOR_MIN_PLAYS = 5


def _az(rows):
    return [r["id"] for r in sorted(rows, key=lambda r: (r["sort_name"], r["id"]))]


def _short(rows):
    return [r["id"] for r in sorted(rows, key=lambda r: (r["minutes"], r["sort_name"], r["id"]))]


def data_collections(rows, records):
    """The collections the catalog computes, each with the rule that fills it as its heading. A to Z, or shortest first
    for a length rule. No popularity, ever."""
    rec = lambda r: records.get("-".join(r["id"].split("-")[:2])) or {}
    shelf = lambda r, name: name in (rec(r).get("shelves") or [])
    christmas = lambda r: any(re.search(r"\bChristmas\b", x) for x in subjects_of(rec(r)) + (rec(r).get("shelves") or []))
    rules = [
        ("two-voices", "Plays for two voices", "voices = 2", lambda r: r["voices"] == 2, _az),
        ("ten-minutes", "Ten minutes or less", "minutes <= 10", lambda r: r["minutes"] <= 10, _short),
        ("one-act", "One Act Plays", "Gutenberg bookshelf: One Act Plays", lambda r: shelf(r, "One Act Plays"), _az),
        ("ensemble", "Ensemble pieces", "balance = ensemble and voices <= 10",
         lambda r: r.get("balance") == "ensemble" and r["voices"] <= 10, _az),
        ("star-part", "A star part", "balance = lead", lambda r: r.get("balance") == "lead", _az),
        ("christmas", "Christmas plays", "a subject or bookshelf names Christmas", christmas, _az),
        ("ireland", "Ireland", "subject: Ireland -- Drama", lambda r: "Ireland" in (r.get("subjects") or []), _az),
        ("nobel", "Nobel Prizes in Literature", "Gutenberg bookshelf: Nobel Prizes in Literature",
         lambda r: shelf(r, "Nobel Prizes in Literature"), _az),
    ]
    out = []
    for cid, title, rule, test, order in rules:
        got = [r for r in rows if test(r)]
        if got:
            out.append({"id": cid, "title": title, "rule": rule, "count": len(got), "plays": order(got)})
    by = collections.defaultdict(list)
    for r in rows:
        if r["authors"]:
            by[r["authors"][0]].append(r)
    for name in sorted(by, key=lambda n: (n.split()[-1].lower() if n.split() else "", n)):
        if len(by[name]) >= AUTHOR_MIN_PLAYS:
            slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
            out.append({"id": f"author-{slug}", "title": name, "rule": f"author = {name}", "count": len(by[name]),
                        "plays": _az(by[name]), "kind": "author"})
    return out


def editor_collections(rows, editor):
    """The editor's collections (catalog/plays/collections.json), each {id, title, by, note?, plays, added, season?}.
    A play id that does not resolve is an error (the editor must mend the list); a collection with fewer than three
    playable plays is not published."""
    ids = {r["id"] for r in rows}
    out = []
    for c in editor.get("collections") or []:
        for k in ("id", "title", "by", "plays", "added"):
            if not c.get(k):
                raise ValueError(f"editor collection {c.get('id')!r} has no {k}")
        missing = [p for p in c["plays"] if p not in ids]
        if missing:
            raise ValueError(f"editor collection {c['id']!r} names plays not in the library: {missing}")
        if len(c["plays"]) >= EDITOR_MIN_PLAYS:
            out.append({k: c[k] for k in ("id", "title", "by", "note", "plays", "added", "season") if k in c}
                       | {"count": len(c["plays"])})
    return out


def collections_doc(rows, records, editor):
    return {"format": 1, "editor": editor_collections(rows, editor), "data": data_collections(rows, records)}


# ---------------------------------------------------------------- characters and the words said (design 3.3)

def characters_doc(rows, entries):
    """{format, names: {NAME: [[play number, lines], ...]}}: each speaking part's printed name (whitespace folded,
    in capitals) and the plays it speaks in, a play number being its place in index.json's plays."""
    num = {r["id"]: i for i, r in enumerate(rows)}
    names = collections.defaultdict(list)
    for e in entries:
        if e["id"] not in num:
            continue
        for role in e["roles"]:
            if role.get("lines", 0) >= 1:
                key = re.sub(r"\s+", " ", role["name"]).strip().upper()
                if key:
                    names[key].append([num[e["id"]], role["lines"]])
    return {"format": 1, "names": {k: sorted(v) for k, v in sorted(names.items())}}


SAID_MIN_WORD = 3


def said_shards(rows, entries):
    """{shard: {word: delta-coded play numbers}} over every spoken word of three letters or more, tokenized and filed as
    the web projection's search/said is (build_web_projection.tokens, term_file). Never the text; no line ids."""
    import build_web_projection as W
    num = {r["id"]: i for i, r in enumerate(rows)}
    said = collections.defaultdict(list)
    for e in sorted(entries, key=lambda e: num.get(e["id"], -1)):
        if e["id"] not in num:
            continue
        words = set()
        for l in e["lines"]:
            if l.get("kind") == "speech":
                for p in l.get("parts") or []:
                    words.update(w for w in W.tokens(p.get("say")) if len(w) >= SAID_MIN_WORD)
        for w in words:
            said[w].append(num[e["id"]])
    shards = collections.defaultdict(dict)
    for w in sorted(said):
        ns = said[w]
        shards[W.term_file(w)][w] = [ns[0]] + [b - a for a, b in zip(ns, ns[1:])]
    return shards


def write_finding(out, rows, entries, records, editor=None):
    """collections.json, characters.json and search/said/<p>.json beside index.json; returns their sizes."""
    editor = editor if editor is not None else json.load(open(EDITOR_FILE, encoding="utf-8"))
    dump = lambda path, obj: (os.makedirs(os.path.dirname(path), exist_ok=True),
                              open(path, "w", encoding="utf-8").write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n"))
    dump(os.path.join(out, "collections.json"), collections_doc(rows, records, editor))
    dump(os.path.join(out, "characters.json"), characters_doc(rows, entries))
    shutil.rmtree(os.path.join(out, "search"), ignore_errors=True)
    for name, words in sorted(said_shards(rows, entries).items()):
        dump(os.path.join(out, "search", "said", f"{name}.json"), words)
