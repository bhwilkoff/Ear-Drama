#!/usr/bin/env python3
"""Read what a take-down request names, and say whether the claim fits it
(catalog/DECISIONS.md 029; ported from Archive Watch's Decision 175).

Runs for ONE request at a time; it is never a catalog scan. A complete notice
removes the recording unless the evidence CONTRADICTS the claim; a contradiction
goes to the owner. A record that could not be read is not evidence of anything,
so it can never hold a removal back. Two things can contradict a claim:

  * The claim names only a word of the title. Notices are often matched on a
    word, not on the work.
  * The recording is old enough to be free of any recording right (Decision
    001's year), and nothing on its archive.org record says a modern layer was
    added.

A modern layer is what archive.org's own record admits to: a restoration or
remaster, a new narration, a music bed, a re-recording, a post-1971 date. That
is a work with its own rights, so it removes even when the claim names only a
word of the title.

The public list holds a date, a case number, a scope and a catalog key, never a
person: who asked is in the private case record (worker/src/takedown.js).
"""
import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
EDITORIAL = os.path.join(HERE, "..", "editorial", "takedowns.json")
DATA = "https://eardrama.org/data/"
UA = "EarDrama-takedown-check"


def pd_published_year(today=None):
    """Newest first-publication year freed by 17 U.S.C. 1401(a)(2)(B)(ii): 1925 in 2026."""
    return (today or datetime.date.today()).year - 101


# ── the public list ──────────────────────────────────────────────────────────

def load_list(path=None) -> dict:
    path = path or EDITORIAL
    return json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {"requests": {}}


def add_lines(entries, ref, date, path=None):
    """entries: [(scope, key)]. Only the date and case number, ever."""
    if not entries:
        return
    path = path or EDITORIAL
    raw = load_list(path)
    for scope, key in entries:
        raw.setdefault("requests", {}).setdefault(
            f"{scope}:{key}", {"date": date, "case": ref, "scope": scope, "key": key})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(raw, f, indent=2, ensure_ascii=False)
        f.write("\n")


# ── what a link points at ────────────────────────────────────────────────────

_LINK = re.compile(r"eardrama\.org/(?P<kind>series|episode)/(?P<id>[^/?#\s\"'<>]+)", re.I)


def targets(links: str) -> list:
    """Every `series/{key}` or `episode/{id}` a request names. A line that names
    nothing we can read comes back as {"unread": line}."""
    out, seen = [], set()
    for line in re.split(r"[\s,]+", links or ""):
        if not line:
            continue
        m = _LINK.search(line)
        if not m:
            out.append({"unread": line[:200]})
            continue
        t = (m.group("kind").lower(), urllib.parse.unquote(m.group("id")))
        if t not in seen:
            seen.add(t)
            out.append({"scope": t[0], "id": t[1]})
    return out


def _get(base, path):
    try:
        req = urllib.request.Request(base + path, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except Exception:
        return None


class Catalog:
    """What the site serves right now: the published web projection."""

    def __init__(self, fetch=None, base=DATA):
        self.get = fetch or (lambda p: _get(base, p))
        self.ids = self.get("index/aliases.json") or {}
        self.keys = self.get("index/series-aliases.json") or {}
        self._series = {}

    def series(self, key):
        key = self.keys.get(key, key)
        if key not in self._series:
            self._series[key] = self.get(f"series/{urllib.parse.quote(key)}.json")
        return key, self._series[key]

    def find(self, scope, ident):
        """{"scope","key","title","date","url","names"} if we serve it, else None.
        `key` is what the public list records; a forwarded id resolves first."""
        if scope == "series":
            key, page = self.series(ident)
            if not page:
                return None
            eps = page.get("episodes") or []
            f = page.get("fields") or []
            row = dict(zip(f, eps[0])) if eps else {}
            return {"scope": "series", "key": key, "title": page.get("name"), "names": [page.get("name")],
                    "date": row.get("date"), "url": row.get("url")}
        ident = self.ids.get(ident, ident)
        key, page = self.series(ident.split("|", 1)[0])
        if not page:
            return None
        f = page.get("fields") or []
        for e in page.get("episodes") or []:
            row = dict(zip(f, e))
            if row.get("id") == ident:
                return {"scope": "episode", "key": ident, "title": page.get("name"),
                        "names": [page.get("name"), row.get("title")],
                        "date": row.get("date"), "url": row.get("url")}
        return None


def archive_record(url):
    """archive.org's own metadata for the file's item, or None if it would not answer."""
    m = re.search(r"archive\.org/download/([^/]+)/", url or "")
    if not m:
        return None
    meta = "https://archive.org/metadata/" + m.group(1) + "/metadata"
    try:
        req = urllib.request.Request(meta, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r).get("result")
    except Exception:
        return None


# ── what the record says ─────────────────────────────────────────────────────

MODERN = re.compile(
    r"\b(re-?master(ed|ing)?|digitally (re-?master|restor)\w*|restor(ed|ation) (by|from)|noise (reduc|remov)\w*"
    r"|re-?record(ed|ing)|re-?creat(ed|ion)|new(ly)?[- ](narration|score|music|recording)"
    r"|(with|added|new) narrat\w+|narrated by|music bed|background music added|(?:\(c\)|copyright|©)\s*(19[7-9]\d|20\d\d))",
    re.I)


def read_record(rec) -> dict:
    """What the archive.org record says about a modern layer. `read` False means
    nothing was learned."""
    if not rec:
        return {"read": False}
    text = " ".join(str(rec.get(k) or "") for k in ("title", "description", "notes", "subject", "creator", "contributor"))
    if isinstance(rec.get("description"), list):
        text = " ".join(map(str, rec["description"])) + " " + text
    hit = MODERN.search(text)
    y = re.match(r"\s*(\d{4})", str(rec.get("date") or rec.get("year") or ""))
    return {"read": True, "layer": bool(hit), "modernDate": bool(y and int(y.group(1)) >= 1972)}


# ── does the claim fit ───────────────────────────────────────────────────────

def _words(s):
    return re.findall(r"[a-z0-9]+", (s or "").lower())


def name_fit(claimed: str, title: str) -> str:
    """same: the two name one work. partial: the claim is only some of the words
    of a longer title, a notice matched on a word. none: no words in common,
    which can be another name for it and proves nothing. unknown: no claim named."""
    c, t = _words(claimed), _words(title)
    if not c or not t:
        return "unknown"
    if "".join(c) == "".join(t) or set(t) <= set(c):
        return "same"
    return "partial" if set(c) & set(t) else "none"


def best_fit(claimed, names) -> str:
    fits = [name_fit(claimed, n) for n in names if n]
    for f in ("same", "partial", "none"):
        if f in fits:
            return f
    return "unknown"


def old_enough(date, today=None) -> bool:
    m = re.match(r"\s*(\d{4})", str(date or ""))
    return bool(m and 1880 < int(m.group(1)) <= pd_published_year(today))


def verdict(case: dict, item, ev: dict, today=None) -> dict:
    """{"action": remove|hold|none, "reason": ...}. Pure: the whole rule is here.
    `case` is {kind, complete, work}; `item` what we serve, or None."""
    if item is None:
        return {"action": "none", "reason": "not_served"}
    if case.get("kind") != "copyright":
        return {"action": "hold", "reason": "not_copyright"}
    if not case.get("complete"):
        return {"action": "hold", "reason": "incomplete_notice"}
    if ev.get("read") and (ev.get("layer") or ev.get("modernDate")):
        return {"action": "remove", "reason": "modern_layer"}
    fit = best_fit(case.get("work"), item.get("names") or [item.get("title")])
    if fit == "partial":
        return {"action": "hold", "reason": "title_word_only", "fit": fit}
    if ev.get("read") and old_enough(item.get("date"), today):
        return {"action": "hold", "reason": "old_recording", "fit": fit}
    return {"action": "remove", "reason": "complete_notice", "fit": fit}


if __name__ == "__main__":
    # A look at one link, for a person: takedown_check.py series|episode <id> [claimed work]
    cat = Catalog()
    item = cat.find(sys.argv[1], sys.argv[2])
    ev = read_record(archive_record((item or {}).get("url"))) if item else {"read": False}
    case = {"kind": "copyright", "complete": True, "work": " ".join(sys.argv[3:])}
    print(json.dumps({"item": item, "evidence": ev, "verdict": verdict(case, item, ev)}, indent=1))
