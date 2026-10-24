"""Story arcs: the parts of one serial story, in order (docs/CATALOG-CONTRACT.md §3.3, research R3).

    python3 tools/arcs.py [--src out/publish/ear-drama.sqlite]   # measure: arcs found, covered, rejected, a sample

Decision 067: a serial plays to its arc's end and stops; the next arc is
offered, never started. An arc is derived only from what a title says, and only
when the evidence agrees with itself; any doubt leaves the episodes as single
episodes, which play one at a time (the rule before arcs existed):

- `titled-parts`: episodes of one series whose titles name the same story and a
  part ("The Molly K Matter - Ep 3", "Space Station of Danger, Part 2",
  "Chapter 4"). Kept only when the parts run 1..n with no gap and no part twice,
  n is at least 2 and never more than a stated "of N", and the dates, where
  known, rise with the part, no two neighbors more than MAX_GAP_DAYS apart.
- A bare "Episode 7" (or the series' own name and a number) numbers a series,
  not a story, and makes no arc.

Consecutive same-titled dated episodes without a part number are not arcs:
measured 2026-10-24 they are mostly one broadcast under two dates.
"""
import argparse
import datetime
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

MAX_GAP_DAYS = 45
METHOD = "titled-parts"
_KIND = {"part": "part", "pt": "part", "chapter": "chapter", "chap": "chapter", "ch": "chapter",
         "ep": "episode", "episode": "episode"}
_MARK = re.compile(r"(?i)(?<![a-z])(part|pt|chapter|chap|ch|episode|ep)\.?\s*#?\s*(\d{1,2})(?!\d)"
                   r"(?:\s*(?:of|/)\s*(\d{1,2})(?!\d))?")
_JUNK_HEAD = re.compile(r"(?i)^\s*(?:xx-xx|\d{2,4}[-/.]\d{2}(?:[-/.]\d{2,4})?)\s*[-:]\s*")
_SUBTITLE = re.compile(r"^\s*(?:[-:,]\s*\S.*)?$")


def _words(s):
    return " ".join(re.findall(r"[a-z0-9]+", (s or "").lower()))


def parse(title):
    """(stem, kind, part, of) when the title names one part of a story, else None.
    The stem is the story's words; a title with two part marks is ambiguous and is None."""
    if not title:
        return None
    t = _JUNK_HEAD.sub("", title)
    marks = list(_MARK.finditer(t))
    if len(marks) != 1:
        return None
    m = marks[0]
    rest = t[m.end():].strip()
    if rest.startswith(")"):
        rest = rest[1:].strip()
    if rest and not _SUBTITLE.match(rest):
        return None
    head = t[:m.start()].rstrip(" ,:-–—(")
    part = int(m.group(2))
    of = int(m.group(3)) if m.group(3) else None
    if part < 1 or (of is not None and (of < 2 or part > of)):
        return None
    return _words(head), _KIND[m.group(1).lower()], part, of


def _days(a, b):
    try:
        return (datetime.date.fromisoformat(b[:10]) - datetime.date.fromisoformat(a[:10])).days
    except (TypeError, ValueError):
        return None


def derive(rows, series_names=None):
    """rows: (episode id, series key, air_date, title) for served episodes.
    Returns (arcs, report). Each arc: {"id", "series", "title", "parts": [episode ids in order],
    "method"}; arcs are sorted by series, then by their first part's date and id."""
    series_names = series_names or {}
    groups = {}
    for eid, sk, air, title in rows:
        p = parse(title)
        if not p:
            continue
        stem, kind, part, of = p
        if kind == "episode" and (not stem or stem == _words(series_names.get(sk))):
            continue   # numbers the series, not a story
        groups.setdefault((sk, stem, kind), []).append((part, of, air if air and len(air) >= 10 else None, eid, title))
    report = {"candidates": len(groups), "single": 0, "repeated": 0, "gap": 0, "overCount": 0, "dates": 0}
    arcs = []
    for (sk, stem, kind), members in groups.items():
        members.sort(key=lambda m: (m[0], m[3]))
        parts = [m[0] for m in members]
        if len(members) < 2:
            report["single"] += 1
            continue
        if len(set(parts)) != len(parts):
            report["repeated"] += 1
            continue
        if parts != list(range(1, len(parts) + 1)):
            report["gap"] += 1
            continue
        stated = {m[1] for m in members if m[1] is not None}
        if len(stated) > 1 or (stated and len(parts) > min(stated)):
            report["overCount"] += 1
            continue
        dated = [m[2] for m in members if m[2]]
        steps = [_days(a, b) for a, b in zip(dated, dated[1:])]
        if any(d is None or d <= 0 or d > MAX_GAP_DAYS for d in steps):
            report["dates"] += 1
            continue
        first = members[0]
        arcs.append({"series": sk, "stem": stem, "kind": kind, "first": first[2] or "", "parts": [m[3] for m in members],
                     "title": _story_title(first[4]), "method": METHOD})
    arcs.sort(key=lambda a: (a["series"], a["first"] == "", a["first"], a["parts"][0]))
    out = []
    for a in arcs:
        out.append({"id": arc_id(a["series"], a["parts"][0]), "series": a["series"], "title": a["title"],
                    "parts": a["parts"], "method": a["method"]})
    report["arcs"] = len(out)
    report["episodes"] = sum(len(a["parts"]) for a in out)
    return out, report


def arc_id(series_key, first_part_id):
    """Stable while the first part's id is: the series and the first part's id."""
    return f"{series_key}|arc|{first_part_id.split('|', 1)[-1]}"


def _story_title(title):
    t = _JUNK_HEAD.sub("", title or "")
    m = _MARK.search(t)
    head = t[:m.start()].rstrip(" ,:-–—(") if m else t
    return head.strip() or None


def next_arcs(arcs, eligible=lambda first_id: True):
    """arc id -> the following arc's id in the same series (arcs already in order), skipping an
    arc whose first part `eligible` refuses (recommendAnd: the offer chooses for the listener)."""
    nxt = {}
    by_series = {}
    for a in arcs:
        by_series.setdefault(a["series"], []).append(a)
    for rows in by_series.values():
        for i, a in enumerate(rows):
            nxt[a["id"]] = next((b["id"] for b in rows[i + 1:] if eligible(b["parts"][0])), None)
    return nxt


def violations(arcs, served, order_key=None):
    """Every reason the arcs break the contract's guarantees (empty when they hold): each arc has at
    least two parts, every part is a served episode of the arc's series, no episode is in two arcs,
    no arc id repeats, and the parts' dates, where known, rise in order."""
    out = []
    seen, ids = {}, set()
    for a in arcs:
        if a["id"] in ids:
            out.append(f"arc id repeated: {a['id']}")
        ids.add(a["id"])
        if len(a["parts"]) < 2:
            out.append(f"{a['id']}: {len(a['parts'])} part")
        for eid in a["parts"]:
            if eid not in served:
                out.append(f"{a['id']}: {eid} is not served")
            elif served[eid][0] != a["series"]:
                out.append(f"{a['id']}: {eid} is another series' episode")
            if eid in seen:
                out.append(f"{eid} is in {seen[eid]} and {a['id']}")
            seen[eid] = a["id"]
        dates = [served[e][1] for e in a["parts"] if e in served and served[e][1]]
        if dates != sorted(dates) or len(set(dates)) != len(dates):
            out.append(f"{a['id']}: parts out of date order")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(ia.OUT, "publish", "ear-drama.sqlite"))
    ap.add_argument("--sample", type=int, default=10)
    a = ap.parse_args()
    s = sqlite3.connect(f"file:{a.src}?mode=ro", uri=True)
    names = dict(s.execute("SELECT key, name FROM series"))
    rows = list(s.execute("SELECT id, series_key, air_date, title FROM episodes"))
    arcs, report = derive(rows, names)
    served = {r[0]: (r[1], r[2]) for r in rows}
    report["violations"] = violations(arcs, served)
    report["seriesWithArcs"] = len({x["series"] for x in arcs})
    title = {r[0]: r[3] for r in rows}
    step = max(1, len(arcs) // max(1, a.sample))
    report["sample"] = [{"id": x["id"], "title": x["title"], "parts": [title[e] for e in x["parts"]]}
                        for x in arcs[::step][:a.sample]]
    print(json.dumps(report, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
