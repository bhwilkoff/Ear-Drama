"""The defects in the text a listener reads: series names and episode titles (audit 2026-10-31).

    python3 tools/text_defects.py out/publish/ear-drama.sqlite [--examples 10] [--json]

One classifier, imported by the audit and by `tests/test_display_text.py`. It reads only
the words on screen, never a catalog's contents, so it is a measuring stick and not a
list of known bad rows. A class names a habit of the uploaders' file names; none of
them says a name is wrong in fact, only that it reads as the file it came from.

Series name classes
  S_DATED      the name is a date or number ("1959 10", "19411207 part")
  S_LOWER      no capital letter at all ("standbyformars", "power-records")
  S_RUNTOGETHER one token with a hump or a trailing number ("CaseClosed3", "RRSciFi2", "Remote-HarryJames")
  S_COLLECTION an uploader's grab bag ("Singles & Doubles Collection", "Old-Time Radio Collection")

Episode title classes
  T_LEADNUM    a leading code, zero-padded number, run of numbers or date ("01 ", "EP001 ", "8 01 02 13 ", "47-03-21 ")
  T_RUNTOGETHER a word of 12+ letters, or a lowercase-to-capital hump inside a word ("EdnaWolfeWants")
  T_RIPTAG     OTR / mp3 / kbps / VBR / "old time radio" left in the title
  T_CODE       square or curly brackets, an empty pair, a bracket holding only a code
  T_DOUBLED    doubled punctuation ("--", ",,", "- -", "..") but not an ellipsis
  T_CASE       no lowercase letter (a shout) or no capital letter
  T_EMPTY      no title, or one that is only placeholders ("xx xx xx")
"""
import json
import re
import sqlite3
import sys

SERIES_CLASSES = ("S_DATED", "S_LOWER", "S_RUNTOGETHER", "S_COLLECTION")
TITLE_CLASSES = ("T_LEADNUM", "T_RUNTOGETHER", "T_RIPTAG", "T_CODE", "T_DOUBLED", "T_CASE", "T_EMPTY")

_COLLECTION = re.compile(r"\b(collections?|singles?\s*(?:&|and)\s*doubles|miscellaneous|misc|assorted|"
                         r"old[- ]?time[- ]?radio(?:\s+shows?)?|otrr|odds\s*(?:&|and)\s*ends|various)\b", re.I)
_HUMP = re.compile(r"[a-z][A-Z]")
_MC = re.compile(r"(?:^|\b)(?:Mc|Mac|De|La|Le|Di|Van|Von|O)[A-Z]")
_TRAILING_N = re.compile(r"[A-Za-z]\d+$")

_LEAD_CODE = re.compile(r"^\s*(?:(?:EP?\.?|#)\s?\d+[a-z]?(?:[\s.:;,)\-]+|$))", re.I)
_LEAD_PADDED = re.compile(r"^\s*0\d*[a-z]?[\s.:;,)\-]+(?=\S)")
_LEAD_GROUPS = re.compile(r"^\s*\d+(?:[\s.\-]\d+)+\.?[\s.:;)\-]+(?=[^\W\d_])")
_LEAD_DATE = re.compile(r"^\s*\d{2,4}[-./]\d{1,2}[-./]\d{1,2}(?:\b|x)")
_LEAD_GLUED = re.compile(r"^\s*\d{1,3}(?=[A-Z][a-z])")
_RIP = re.compile(r"(?<![A-Za-z])(?:otr|mp3|kbps|vbr|128k|64k|old[ -]?time[ -]?radio)(?![A-Za-z])|\b\d{2,3}\s?kb(?:ps)?\b", re.I)
_BRACKET = re.compile(r"[\[\]{}]|\(\s*\)")
_CODE_PAREN = re.compile(r"\(\s*(?:[A-Z]{1,3}\d+|\d{1,3}\s?kbps?|\d{4}[-.]\d{2}[-.]\d{2})\s*\)")
_DOUBLED = re.compile(r"--|__|,,|;;|::|!!(?!!)|\?\?|(?<!\.)\.\.(?!\.)|-\s-(?!-)|\s[,;:.]\s")
_LONG = re.compile(r"[^\W\d_]{12,}")
_PLACEHOLDER = re.compile(r"^[\sxX\-._#\d]*$")


def _alpha(s):
    return re.sub(r"[^A-Za-z]", "", s)


def series_defects(name, key=None):
    """The classes a shown series name falls in (a list, empty when clean). `key` lets a LibriVox
    project keep the title its reader gave it ("Shakespeare Monologues Collection vol. 4")."""
    out = []
    n = (name or "").strip()
    if not n:
        return out
    toks = n.split()
    if not re.search(r"[^\W\d_]", n) or (re.fullmatch(r"\d+", toks[0]) and (
            len(toks[0]) >= 6 or (len(toks) > 1 and re.fullmatch(r"\d{1,2}|xx", toks[1], re.I)))):
        out.append("S_DATED")
    if re.search(r"[A-Za-z]", n) and n == n.lower():
        out.append("S_LOWER")
    if len(toks) == 1 or re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)+", n):
        core = n
        if (_HUMP.search(core) and not _MC.search(core) and re.search(r"[a-z]", core) and len(core) >= 8) or (
                _TRAILING_N.search(core) and re.search(r"[a-z]", core) and not core.isupper()):
            out.append("S_RUNTOGETHER")
    if _COLLECTION.search(n) and not (key or "").startswith("librivox"):
        out.append("S_COLLECTION")
    return out


_HUMP_TOKEN = re.compile(r"[A-Za-z]*[a-z][A-Z][A-Za-z]*")


def _runtogether(t):
    """A token with two humps, or one hump between halves of four letters or more, or a lowercase
    token of 18+ letters; "McGee", "MacArthur" and "iPhone" are names, not words run together."""
    for tok in re.findall(r"[A-Za-z]+", t):
        if re.fullmatch(r"(?:Mc|Mac|De|La|Le|Di|Van|Von|O)[A-Z][a-z]+", tok):
            continue
        if len(_HUMP.findall(tok)) >= 2:
            return True
        m = re.fullmatch(r"([A-Za-z]*[a-z])([A-Z][a-z]+)", tok)
        if m and len(m.group(1)) >= 4 and len(m.group(2)) >= 4:
            return True
        if tok == tok.lower() and len(tok) >= 18:
            return True
    return False


def title_defects(title, series=None):
    """The classes a shown episode title falls in."""
    out = []
    t = (title or "").strip()
    if not t or not re.search(r"[^\W\d_]", t) or _PLACEHOLDER.match(t):
        return ["T_EMPTY"]
    if _LEAD_CODE.match(t) or _LEAD_PADDED.match(t) or _LEAD_GROUPS.match(t) or _LEAD_DATE.match(t) or _LEAD_GLUED.match(t):
        out.append("T_LEADNUM")
    if _runtogether(t):
        out.append("T_RUNTOGETHER")
    if _RIP.search(t):
        out.append("T_RIPTAG")
    if _BRACKET.search(t) or _CODE_PAREN.search(t):
        out.append("T_CODE")
    if _DOUBLED.search(t):
        out.append("T_DOUBLED")
    letters = _alpha(t)
    if len(letters) >= 4 and (letters == letters.upper() or letters == letters.lower()):
        out.append("T_CASE")
    return out


def audit(path):
    """{'series': {class: [(key, name, episodes, downloads)]}, 'titles': {class: [(id, title, series name, downloads)]}}"""
    d = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    dl = dict(d.execute("SELECT archive_id, downloads FROM items"))
    sdl = {}
    snames = {}
    out = {"series": {c: [] for c in SERIES_CLASSES + ("CLEAN",)}, "titles": {c: [] for c in TITLE_CLASSES + ("CLEAN",)},
           "totals": {}}
    nser = 0
    for key, name, eps, downloads in d.execute("SELECT key, name, episodes, downloads FROM series"):
        snames[key] = name
        sdl[key] = downloads or 0
        nser += 1
        for c in series_defects(name, key) or ["CLEAN"]:
            out["series"][c].append((key, name, eps, downloads or 0))
    first = {}
    for eid, aid in d.execute("SELECT episode_id, archive_id FROM recordings WHERE rank = 0"):
        first[eid] = aid
    nep = 0
    for eid, sk, title in d.execute("SELECT id, series_key, title FROM episodes"):
        nep += 1
        w = dl.get(first.get(eid), 0)
        for c in title_defects(title, snames.get(sk)) or ["CLEAN"]:
            out["titles"][c].append((eid, title, snames.get(sk), w))
    out["totals"] = {"series": nser, "episodes": nep}
    return out


def report(res, examples=10):
    lines = []
    tot = res["totals"]
    for kind, label, n in (("series", "series", tot["series"]), ("titles", "episodes", tot["episodes"])):
        lines.append(f"{kind}: {n} {label}")
        for c, rows in res[kind].items():
            dls = sum(r[-1] for r in rows)
            lines.append(f"  {c:14} {len(rows):7} {dls:14}")
            if c != "CLEAN":
                for r in sorted(rows, key=lambda r: -r[-1])[:examples]:
                    lines.append(f"      {r[0]!r}: {r[1]!r}")
    return "\n".join(lines)


if __name__ == "__main__":
    args = sys.argv[1:]
    ex = int(args[args.index("--examples") + 1]) if "--examples" in args else 3
    res = audit(args[0])
    if "--json" in args:
        print(json.dumps({k: ({c: len(v) for c, v in res[k].items()} if k != "totals" else res[k]) for k in res}))
    else:
        print(report(res, ex))
