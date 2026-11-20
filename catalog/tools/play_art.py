"""The pictures a play carries in the library index (contract section 3.3c, Round 3 V2 H7).

    play_art.pictures(play_id)  ->  {"titlePage": art or None, "authorArt": art or None, "picture": art or None}

Reads only caches (harvest_art_v2.py --phase plays and pages; no network), and judges every candidate
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


def load():
    plays = _rj(os.path.join(DIR, "plays.json.gz"), {})
    files = dict(_rj(os.path.join(DIR, "files.json.gz"), {}))
    people = _rj(os.path.join(CACHE, "people_wd", "files.json.gz"), {})
    for k, v in people.items():
        files.setdefault(k, v)
    return {"plays": plays, "files": files, "live": _rj(os.path.join(DIR, "liveness.json.gz"), {})}


def pictures(play_id, ctx):
    split = re.match(r"^gut-[0-9]+-[0-9]+$", play_id)   # a play cut from a volume: the volume's author, never its work or edition
    rec = ctx["plays"].get(re.sub(r"-[0-9]+$", "", play_id) if split else play_id)
    out = {"titlePage": None, "authorArt": None, "picture": None}
    if not rec:
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
    lead = AP.pick_play([(k, v) for k, v in (("work", work), ("titlePage", out["titlePage"]),
                                             ("author", out["authorArt"])) if v])
    out["picture"] = dict(lead[1], kind=lead[0]) if lead else None
    return out


def attach(rows, ctx=None):
    """Add titlePage, authorArt and picture to each library index row that has one (absent otherwise)."""
    ctx = ctx or load()
    if not ctx["plays"]:
        return rows
    for r in rows:
        p = pictures(r["id"], ctx)
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
