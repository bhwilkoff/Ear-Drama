"""The play library's title audit (BACKLOG-LOOP B31 C4, catalog DECISIONS 050): a title is the key of every surface
that finds a play (a tile, a search hit, a collection), so a row whose title is not the name of a play is held, and a
play whose record names no author is credited from the catalog's own words.

    not_a_play(title, record)          -> the evidence a kept row is not a play under that title, or None
    hold_not_plays(entries, records, report, protect)   -> the entries kept; the rest listed in report["_held"]
    credit_attributed(entries, catalog)                 -> entries whose record names no author, credited

One rule, three readings of the same fact (the title shown is not a play's name):
  a credit line     the title is a volume's editor or translator line ("Edited by Havelock Ellis", "Thomas Dekker
                    Edited", "Translated by Mrs. Bernard Shaw", "Partly Translated From", "By the Same Writer");
  a periodical      the title is an issue of a periodical ("The Glebe 1913/12 (Vol. 1, No. 3)");
  a prose book      the record is on none of Gutenberg's drama shelves and on its essays shelf (Wilde's
                    "Intentions": dialogues about art, filed by Gutenberg as essays).
A bundled play (the apps' offline floor) is never held. Nothing here repairs a title: a held row is listed in
held.json with its evidence, for an editor.
"""
import re

CREDIT_LINE = re.compile(r"^(?:(?:partly )?(?:edited|translated)\b|by the same writer\b|with an introduction\b)|\b(?:edited|translated)$", re.I)
PERIODICAL_ISSUE = re.compile(r"\bVol\.?\s*\d+\s*,\s*No\.?\s*\d+|\b(?:1[6-9]|20)\d\d/(?:0[1-9]|1[0-2])\b", re.I)
DRAMA_SHELF = re.compile(r"Plays|Drama|Opera|Theat", re.I)
ESSAY_SHELF = re.compile(r"\bEssays\b", re.I)


def not_a_play(title, record=None):
    """The evidence that this title is not a play's name, or None."""
    t = (title or "").strip()
    if CREDIT_LINE.search(t):
        return f"the title is a credit line: {t!r}"
    if PERIODICAL_ISSUE.search(t):
        return f"the title is an issue of a periodical: {t!r}"
    shelves = (record or {}).get("shelves") or []
    if shelves and not any(DRAMA_SHELF.search(s) for s in shelves) and any(ESSAY_SHELF.search(s) for s in shelves):
        return f"Gutenberg shelves it as prose, on no drama shelf: {'; '.join(shelves)[:120]!r}"
    return None


def book_id(pid):
    return "-".join(pid.split("-")[:2])


def hold_not_plays(entries, records, report, protect=()):
    """Entries whose title is a play's name; each other is added to report["_held"]["held"] as title_not_a_play."""
    kept, held = [], []
    for e in entries:
        why = None if e["id"] in protect else not_a_play(e["title"], records.get(book_id(e["id"])))
        if why:
            held.append({"id": e["id"], "title": e["title"], "why": "title_not_a_play", "evidence": why})
        else:
            kept.append(e)
    if held and report is not None:
        report["clean"] = len(kept)
        report.setdefault("failures", {})["title_not_a_play"] = len(held)
        report["failures"] = dict(sorted(report["failures"].items()))
        ledger = report.setdefault("_held", {}).setdefault("held", [])
        ledger += held
        ledger.sort(key=lambda r: r["id"])
    return kept


# The catalog's own credit for a record whose RDF names no author: the person it marks "Dubious author" (an
# attribution, so the row says so) or "Librettist" (a libretto's words are the librettist's).
CREDITS = (("Dubious author", True), ("Librettist", False))
PERSON = re.compile(r"^(?P<name>.+?)(?:,\s*(?P<born>\d{1,4})\??\s*(?P<bbce>BCE)?\s*-\s*(?P<died>\d{1,4})?\??\s*(?P<dbce>BCE)?)?\s*\[(?P<role>[^\]]+)\]$")


def catalog_credits(authors_field):
    """[(person dict, attributed)] from a pg_catalog.csv Authors field, for the roles in CREDITS, in its order."""
    out = []
    for part in (authors_field or "").split(";"):
        m = PERSON.match(part.strip())
        if not m:
            continue
        for role, attributed in CREDITS:
            if m.group("role").strip().lower() == role.lower():
                born = int(m.group("born")) * (-1 if m.group("bbce") else 1) if m.group("born") else None
                died = int(m.group("died")) * (-1 if m.group("dbce") else 1) if m.group("died") else None
                out.append(({"name": m.group("name").strip(), "born": born, "died": died}, attributed))
    return out


def credit_attributed(entries, catalog):
    """Entries whose record names no author take the catalog's credit (catalog: {"gut-N": pg_catalog row}). Rights were
    judged on the record as it was and are not judged again: the credit is display only. A dubious author is marked
    `attributed: true` on the script's author and on the index row, so a client can say "attributed to"."""
    import build_castable_scripts as B
    out = []
    for e in entries:
        if not any(a.get("name") for a in e.get("authors") or []):
            got = catalog_credits((catalog.get(book_id(e["id"])) or {}).get("Authors"))
            if got:
                e = {**e, "authors": [{"name": p["name"], "display": B.author_display(p["name"]), "born": p["born"],
                                       "died": p["died"], **({"attributed": True} if att else {})} for p, att in got]}
        out.append(e)
    return out
