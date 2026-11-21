"""The pictures a play carries in the library index (contract section 3.3c, Round 3 V2 H7).

    play_art.pictures(play_id)  ->  {"titlePage": art or None, "authorArt": art or None, "picture": art or None}

Reads only caches (harvest_art_v2.py --phase plays and pages, harvest_loc_photos.py --phase ftp; no network), and judges every candidate
with art_policy again: the work's image and the author's portrait under the portrait license classes
(`play_image_served`), the edition's title page under the age rule (`edition_served` already judged it at
harvest; a leaf with no scan-data title page was never kept). An art object is
{url, width, height, credit, evidence, face, source, tie}: the same facts as an `art` row, as an object
because the library index is objects, not arrays. A file a liveness check found gone is dropped and the
next one leads (H9).
"""
import gzip
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE  # noqa: E402
import art_policy as AP  # noqa: E402

DIR = os.path.join(CACHE, "art_v2")


def _rj(path, default):
    if not os.path.exists(path):
        return default
    with gzip.open(path, "rt", encoding="utf-8") as f:
        return json.load(f)


def _page(f):
    import enrich_series_art as ESA
    return ESA._page(f)


def _facts(fn, files):
    import enrich_people_art as P
    fv = dict(files.get(fn) or files.get(fn.replace(" ", "_")) or {})
    page = _page(fn.replace("_", " "))
    if page is not None:   # classed again from the page, so a rule change needs no re-harvest
        fv["class"], fv["template"], _ = P.license_class(page)
        fv.update(P.file_facts(page))
    return fv


def page_url(e):
    return f"https://archive.org/download/{e['id']}/page/n{e['leaf']}_w800.jpg"


def _art(file, fv, source, tie):
    cls = fv["class"]
    return {"url": AP.image_url(file), "width": fv.get("width"), "height": fv.get("height"),
            "credit": AP.credit(cls, fv.get("template"), fv.get("author")), "evidence": AP.evidence_url(file),
            "face": AP.face_text(fv.get("face")), "source": source, "tie": tie}


def _best(files_list, files, died=None, live=None, of_the_work=None):
    rows = []
    for fn in files_list:
        if of_the_work and not of_the_work(fn):
            continue
        fv = _facts(fn, files)
        if AP.alive(live, fn.replace("_", " ")) and AP.is_picture(fn) and AP.play_image_served(
                fv.get("class"), fv.get("author"), fv.get("width"), fv.get("height"), bool(fv.get("own_work")),
                fv.get("date_field"), died):
            rows.append((AP.PREFER[fv["class"]], fn.replace("_", " "), fv))
    if not rows:
        return None
    _p, fn, fv = min(rows, key=lambda r: (r[0], r[1]))
    return fn, fv


def _ftp_index():
    """{play-title words: [Library of Congress record]} over the Federal Theatre Project records (Decision 040 V3).
    The rights class is read again from the record's own words, so a rule change needs no re-harvest."""
    import photo_match as M
    path = os.path.join(CACHE, "loc", "records.json.gz")
    out = {}
    for rec in _rj(path, {}).values():
        owners = " ".join(str(x) for x in list(rec.get("contributors") or []) + list(rec.get("partof") or []))
        if not AP.FTP.search(owners + " " + (rec.get("title") or "")) or not rec.get("online"):
            continue
        creator = " | ".join(map(str, (rec.get("contributors") or []) + (rec.get("partof") or []) + [rec.get("call_number") or ""]))
        rec = dict(rec, rights_class=M.rights_class(rec.get("rights"), creator)[0])
        summary = rec.get("summary") if isinstance(rec.get("summary"), str) else " ".join(rec.get("summary") or [])
        for t in AP.ftp_titles(rec.get("title"), summary, rec.get("description")):
            out.setdefault(tuple(AP._title_words(t)), []).append(rec)
    return out


def production(title, ctx, live=None, authors=None):
    """The one Federal Theatre Project picture of this play's production, or None (art_policy.ftp_play_served)."""
    rows = []
    for rec in ctx.get("ftp", {}).get(tuple(AP._title_words(AP.play_title(title))), []):
        summary = rec.get("summary") if isinstance(rec.get("summary"), str) else " ".join(rec.get("summary") or [])
        if AP.ftp_play_served(rec["rights_class"], True, rec.get("contributors"), rec.get("partof"), rec.get("title"),
                              summary, rec.get("description"), title, None, None, authors) \
                and AP.alive(live, rec["image_largest"]):
            poster = "poster" in (rec.get("description") or "").lower()
            rows.append((poster, rec["id"], rec))
    if not rows:
        return None
    _p, _i, rec = min(rows, key=lambda r: (r[0], r[1]))
    return {"url": rec["image_largest"], "width": None, "height": None, "credit": None, "evidence": rec["url"],
            "face": None, "source": "loc:federal-theatre-project", "tie": "title"}


def load():
    plays = _rj(os.path.join(DIR, "plays.json.gz"), {})
    files = dict(_rj(os.path.join(DIR, "files.json.gz"), {}))
    people = _rj(os.path.join(CACHE, "people_wd", "files.json.gz"), {})
    for k, v in people.items():
        files.setdefault(k, v)
    return {"plays": plays, "files": files, "live": _rj(os.path.join(DIR, "liveness.json.gz"), {}), "ftp": _ftp_index()}


def pictures(play_id, ctx, title=None, authors=None):
    split = re.match(r"^gut-[0-9]+-[0-9]+$", play_id)   # a play cut from a volume: the volume's author, never its work or edition
    rec = ctx["plays"].get(re.sub(r"-[0-9]+$", "", play_id) if split else play_id)
    out = {"titlePage": None, "authorArt": None, "picture": None}
    if not rec:
        prod = production(title, ctx, ctx["live"], authors) if title else None
        out["picture"] = dict(prod, kind="production") if prod else None
        return out
    files, live = ctx["files"], ctx["live"]
    work = None
    w = None if split else rec.get("work")
    if w:
        surnames = sorted({AP.surname_of(n) for n in rec.get("authors") or ()})
        title = AP.play_title(rec.get("title"))
        got = _best(w.get("files") or [], files, None, live, lambda fn: AP.work_image_is_of_the_work(fn, title, surnames))
        if got:
            work = _art(got[0], got[1], "wikidata:work", "work+author")
    e = None if split or rec.get("edition_v") != 2 else rec.get("edition")   # v2: a title leaf two records agree on
    if e and e.get("id") and AP.alive(live, page_url(e)):
        h = round(800 * e["height"] / e["width"]) if e.get("width") else None
        out["titlePage"] = {"url": page_url(e), "width": 800 if h else None, "height": h, "credit": None,
                            "evidence": f"https://archive.org/details/{e['id']}", "face": None,
                            "source": "archive.org", "tie": "edition+surname"}
    a = rec.get("author")
    if a:
        got = _best(a.get("files") or [], files, a.get("died"), live)
        if got:
            out["authorArt"] = _art(got[0], got[1], "wikidata:P18", a.get("basis") or "name+dated person")
    prod = production(title or rec.get("title"), ctx, live, authors or rec.get("authors"))
    lead = AP.pick_play([(k, v) for k, v in (("work", work), ("production", prod), ("titlePage", out["titlePage"]),
                                             ("author", out["authorArt"])) if v])
    out["picture"] = dict(lead[1], kind=lead[0]) if lead else None
    return out


def attach(rows, ctx=None):
    """Add titlePage, authorArt and picture to each library index row that has one (absent otherwise)."""
    ctx = ctx or load()
    if not ctx["plays"]:
        return rows
    for r in rows:
        p = pictures(r["id"], ctx, r.get("title"), r.get("authors"))
        for k, v in p.items():
            if v:
                r[k] = v
    return rows


def served_files(ctx=None):
    """Every Commons file a play's pictures may carry, for the faces phase."""
    ctx = ctx or load()
    out = set()
    for pid in ctx["plays"]:
        p = pictures(pid, ctx)
        for k in ("authorArt",):
            if p[k]:
                out.add(urllib.parse.unquote(p[k]["evidence"].rsplit("File:", 1)[-1]).replace("_", " "))
    return sorted(out)


def liveness_files(ctx=None):
    """What H9 checks for the plays: every Commons file a work or an author record offers that passes
    `play_image_served`'s class and size tests, and each edition's title-page image URL."""
    ctx = ctx or load()
    out = set()
    for rec in ctx["plays"].values():
        for key in ("work", "author"):
            for fn in (rec.get(key) or {}).get("files") or []:
                fv = _facts(fn, ctx["files"])
                if AP.is_picture(fn) and AP.play_image_served(fv.get("class"), fv.get("author"), fv.get("width"),
                                                              fv.get("height"), True):
                    out.add(fn.replace("_", " "))
        e = rec.get("edition") or {}
        if rec.get("edition_v") == 2 and e.get("id"):
            out.add(page_url(e))
    return sorted(out)

