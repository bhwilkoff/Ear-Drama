"""What on-screen text must never look like, for every displayed catalog field (audit 2026-10-31, P-8).

    python3 tools/field_defects.py out/publish/ear-drama.sqlite [--examples 10]

`catalog/audits/2026-10-31-display-fields.md` lists the fields; `tests/test_display_fields.py` runs this over a
projection. It reads only the words on screen, never a catalog's contents. A class names a habit of the files
and uploaders the text came from; it does not say a name is wrong in fact.

  IDENT         an identifier: an underscore, or one token that mixes letters and digits ("TopSecret15")
  GLUED         words run together: "WMary", "EdnaWolfeWants", a letter-digit-letter run ("Aud01Show")
  RIPTAG        OTR / mp3 / kbps / VBR / "old time radio" left in the text
  COUNT         an upload's own count in a name ("48 Eps", "1254 Episodes of ...", "over 900 episodes")
  UPLOADER      an uploader's suffix: "ALT SOURCE", "copy", "v2", "remaster", "restored by"
  MOJIBAKE      a broken character encoding ("â", "???s", U+FFFD)
  CODE          brackets, or an upload code ("Aud01 ...", "[modified]", "[Network]")
  DOUBLED       doubled or dangling punctuation ("--", ",,", a trailing " -")
  SHOUT         no lowercase letter (or no capital) in a text of four letters or more
  SMALLWORDS    a title-case title that capitalizes its small words ("The Case Of The Kewpie Doll")
  LOWERROLE     (roles only) a role that is a sentence or note rather than a word or two
  FILE          a file extension or path
"""
import re
import sqlite3
import sys

import text_defects as TD

NOTES = ("pt", "ep", "eps", "vol", "no", "nr", "ch", "ft", "feat", "vs", "v", "episode", "episodes", "part", "chapter")
SMALL = ("of", "the", "and", "or", "in", "on", "to", "for", "at", "by", "with", "from", "an", "a")

_RIP_LABEL = re.compile(r"(?<![A-Za-z])(?:otr|mp3|kbps|vbr|128k|64k)(?![A-Za-z])|\b\d{2,3}\s?kb(?:ps)?\b", re.I)
_UNDERSCORE = re.compile(r"_")
_LETTER_DIGIT = re.compile(r"[A-Za-z]{2,}\d+[A-Za-z]+|[A-Za-z]+\d+[A-Za-z]{2,}")
_GLUED_CAPS = re.compile(r"\b(?!O[A-Z]|Mc|Mac)[A-Z]{2,3}[a-z]{3,}\b")
_MOJIBAKE = re.compile("[\u00c2\u00c3\u00e2][\u0080-\u00bf\u2018-\u203a\u20ac\u201a-\u2122\u0152\u0153\u0160\u0161\u0178\u017d\u017e]|"
                       r"\?\?\?|\ufffd|\u00e2\u20ac|[\u00c3\u00e3][\u00a2\u00a3\u00a4\u00a9]")
_COUNT = re.compile(r"(?<!\bseries )(?<!\bseason )(?<!\bvol )(?<!\bvolume )(?<!\btrack )(?<!\bdisc )(?<!\bpart )(?<!\bno )"
                    r"(?:^|[\s(\-\u2013:])(?:over\s+|about\s+)?\d[\d,]*\+?\s*(?:eps?|episodes?|shows?|programs?|programmes?|"
                    r"broadcasts?|recordings?|files?|mp3s?|tracks?)\b\.?\)?(?=\s*$|\s+of\b|\s*[\-\u2013:,])", re.I)
_UPLOADER = re.compile(r"(?:[\s(\[\-\u2013]|^)(?:alt\.?\s*source|alternate\s+source|v\d+(?:\.\d+)?|ver\.?\s*\d+|"
                       r"re-?mastered|re-?issue|dupe|duplicate|from\s+tape|best\s+quality|repack|"
                       r"restored\s+by\s+\w+|uploaded\s+by\s+\w+)\s*[)\]]?\s*$|\s[Cc]opy\s*$|[(\[]\s*(?:hq|copy|off-air copy)\s*[)\]]", re.I)
_FILE = re.compile(r"\.(?:mp3|ogg|m4a|flac|wav|zip|rar|ra|wma|mp4|pdf|txt)\b|[A-Za-z]:\\|/[A-Za-z0-9_]+/", re.I)
_UPLOAD_NOTE = re.compile(r"\[\s*(?:modified|edited|fixed|rip|ripped|vbr|mono|stereo|network|afrts|afrs|rerun|"
                          r"audio only|hq|hd|clean|copy)\s*\]", re.I)
_GLUED_CODE = re.compile(r"^(?:aud|trk|track|tk|cd|disc|prog|file|rec|sc|nr)\d{1,3}\b", re.I)
_DANGLING = re.compile(r"(?:\s[-–]\s*$|^\s*[-–]\s|--|,,|;;|\s,|\(\s*\)|\s-\s-\s)")
_ROLE_NOTE = re.compile(r"[:;?\"‘’]|\bas\b|\bborrowed\b|\bbilled\b")


def _alpha(s):
    return re.sub(r"[^A-Za-z]", "", s)


def lower_small_words(t):
    """A title-case title with its small words in lower case ("The Case Of The Doll" -> "The Case of the Doll"); a title
    in sentence case, a start of a part (after ":", " - ", "/", "(") and the last word are left as they are."""
    t = re.sub(r"(?<=-)(In|On|To|Of|The|And|For)(?=-)", lambda m: m.group(1).lower(), t)
    toks = re.split(r"(\s+)", t)
    words = [(i, re.sub(r"^[^A-Za-z]+|[^A-Za-z']+$", "", w)) for i, w in enumerate(toks) if w.strip() and re.search(r"[A-Za-z]", w)
             and not re.search(r"\d", w)]
    big = [w for _, w in words if w.lower() not in SMALL and w.lower() not in NOTES and w.lower() != "a"]
    if len(big) < 1 or not all(w[:1].isupper() for w in big):
        return t
    last = max((i for i, w in enumerate(toks) if w.strip()), default=-1)
    start = True
    out = list(toks)
    prev = ""
    for i, w in enumerate(toks):
        if not w.strip():
            continue
        before, prev = prev, w
        core = re.sub(r"^[^A-Za-z]+|[^A-Za-z']+$", "", w)
        if (core and core.lower() in SMALL and core[0].isupper() and not core.isupper() and not start and i != last
                and not re.search(r"\d", before)):
            out[i] = w.replace(core, core.lower(), 1)
        start = bool(re.search(r"[:/?!.\u2013\u2014]$|^[(\"]|^[-\u2013\u2014]$|^\(", w)) or w in ("-", "\u2013", "\u2014")
    return "".join(out)


def small_word_slips(t):
    return [] if lower_small_words(t) == t else [t]


def text_defects(text, kind="title", key=None):
    """The classes a displayed text falls in (a list). `kind`: title | name | role | label | person."""
    t = (text or "").strip()
    out = []
    if not t:
        return out
    toks = t.split()
    if _MOJIBAKE.search(t):
        out.append("MOJIBAKE")
    if _FILE.search(t):
        out.append("FILE")
    if _UNDERSCORE.search(t) or re.search(r"\b(?:Title|Track|Titel|Titre|Audiotrack)\d+\b", t) or (len(toks) == 1 and re.search(r"[A-Za-z]\d|\d[A-Za-z]", t) and re.search(r"[A-Za-z]{3}", t)
                                 and kind in ("title", "name", "label") and not t.isupper()):
        out.append("IDENT")
    if kind != "role" and (TD._runtogether(t) or _LETTER_DIGIT.search(t) or _GLUED_CAPS.search(t)):
        out.append("GLUED")
    if (_RIP_LABEL if kind in ("label", "name") else TD._RIP).search(t):
        out.append("RIPTAG")
    if kind in ("title", "name", "label") and _COUNT.search(t) and not re.search(r"\bpart\b", t, re.I):
        out.append("COUNT")
    if _UPLOADER.search(t):
        out.append("UPLOADER")
    if _UPLOAD_NOTE.search(t) or _GLUED_CODE.match(t) or re.search(r"[\[\]{}]", t):
        out.append("CODE")
    if _DANGLING.search(t):
        out.append("DOUBLED")
    letters = _alpha(t)
    if len(letters) >= 4 and kind in ("title", "name", "label") and (letters == letters.upper() or letters == letters.lower()):
        out.append("SHOUT")
    if kind in ("title", "name", "label") and small_word_slips(t):
        out.append("SMALLWORDS")
    if kind == "role" and (len(t) > 30 or _ROLE_NOTE.search(t)):
        out.append("LOWERROLE")
    return out


FIELDS = (
    ("series.name", "SELECT name FROM series", "name"),
    ("series.genre", "SELECT genre FROM series WHERE genre IS NOT NULL", "name"),
    ("series.networks", "SELECT j.value FROM series s, json_each(s.networks) j", "name"),
    ("episodes.title", "SELECT title FROM episodes", "title"),
    ("episodes.aka", "SELECT aka FROM episodes WHERE aka IS NOT NULL", "title"),
    ("episodes.network", "SELECT network FROM episodes WHERE network IS NOT NULL", "name"),
    ("episodes.sponsor", "SELECT sponsor FROM episodes WHERE sponsor IS NOT NULL", "name"),
    ("credits.role", "SELECT role FROM credits WHERE role IS NOT NULL", "role"),
    ("credits.character", "SELECT character FROM credits WHERE character IS NOT NULL", "person"),
    ("people.name", "SELECT name FROM people", "person"),
    ("voices.name", "SELECT name FROM voices", "person"),
    ("arcs.title", "SELECT title FROM arcs WHERE title IS NOT NULL", "title"),
    ("art.credit", "SELECT credit FROM art WHERE credit IS NOT NULL", "credit"),
    ("recordings.label", "SELECT label FROM recordings WHERE label IS NOT NULL", "label"),
)


def audit(path, fields=FIELDS):
    """{field: {class: [text, ...]}}, distinct texts only; a field the projection lacks is skipped."""
    d = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    out = {}
    for field, sql, kind in fields:
        try:
            texts = [r[0] for r in d.execute(sql)]
        except sqlite3.OperationalError:
            continue
        seen, res = set(), {}
        for t in texts:
            if t in seen:
                continue
            seen.add(t)
            for c in text_defects(t, kind):
                res.setdefault(c, []).append(t)
        out[field] = {"distinct": len(seen), "classes": res}
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    ex = int(args[args.index("--examples") + 1]) if "--examples" in args else 5
    for field, r in audit(args[0]).items():
        print(f"{field}: {r['distinct']} distinct")
        for c, rows in sorted(r["classes"].items()):
            print(f"  {c:11} {len(rows):6}  " + " | ".join(repr(x)[:60] for x in rows[:ex]))
