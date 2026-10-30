"""Episode titles and series names as people read them, cleaned of the file names they came from.

Imported by every builder, never copied. Conservative on purpose: a title that
already reads as words is returned unchanged, and only these upload habits are
undone (MEASURED 2026-10-22 over 104,028 served titles: 2,883 with track digits
glued to a word, 2,048 run together with no spaces, 181 ending in a file
extension, 99 with underscores):

  "001 Frankenstein 1931.mp3"        -> "Frankenstein 1931"
  "Carolyn_Day_Detective_-_Audition_1" -> "Carolyn Day Detective - Audition 1"
  "01CbsNews-LinkletterHouseParty"    -> "Cbs News-Linkletter House Party"
  "EdnaWolfeWantsToGetNancyFowler"    -> "Edna Wolfe Wants To Get Nancy Fowler"

  "NBC-Story-Behind-The-Headlines---Appeasement-Marches-On"
      -> "NBC Story Behind The Headlines - Appeasement Marches On"
(no spaces and three or more hyphen-joined words; "Twenty-Two" stays).

Then the numbering, codes and durations an upload put in front of or around the
words (D3, 2026-10-30), each only when words remain:

  "EP001 TARZANSFIRSTBIRTHDAY"  -> "Tarzans First Birthday"   (with the catalog's words)
  "0005 -The Babe Ruth Collection -Harry The Hat -32-22 -14m42s" -> "Harry The Hat"
  "8 01 02 13 The Jack Benny Program Jack's 40th Birthday Again" -> "Jack's 40th Birthday Again"
  "01 The Hobbit"               -> "The Hobbit"

  * a leading episode code (EP001, Ep 221, #257), a leading zero-padded number
    ("01 ", "031 - "), or a leading run of two or more numbers ("8 01 02 13");
  * a duration ("14m42s") anywhere, and a " - " part that is only numbers ("32-22", "4115");
  * the series' own name at the start or as a " - " part, when the name is two
    words or more and words follow it;
  * a title with no lowercase letter is set in the case the catalog's own titles
    write each word in ("OTR", "XXXI", "Perry's"), else capitalized;
  * a run-together word is split only when every piece is a word the catalog's
    titles use on its own and exactly one fewest-piece split exists.

`Words` is that vocabulary, built once from every title and name. Without it no
case is changed and nothing is split. A spaced leading number without a zero
stays ("77 Sunset Strip" is a title), "McGee" and "MacArthur" stay whole, and
nothing is ever added: every word out is a word the raw title spelled.
"""
import re

EXT = re.compile(r"\.(mp3|ogg|m4a|flac|wav)$", re.I)
GLUED_TRACK = re.compile(r"^\d{1,3}(?=[A-Z][a-z])")
HUMP = re.compile(r"(?<=[a-z])(?=[A-Z])")
HYPHEN_RUN = re.compile(r"-+")
MC = re.compile(r"\b(Ma?c) ([A-Z])")

SEP = r"[\s.:;,)\-]"
LEAD_CODE = re.compile(r"^(?:EP?\.?|#)\s?\d+[a-z]?(?:" + SEP + r"+|$)", re.I)
LEAD_PADDED = re.compile(r"^0\d*[a-z]?(?:" + SEP + r"+)", re.I)
LEAD_GROUPS = re.compile(r"^\d+(?:[\s.\-]\d+)+\.?[\s.:;)\-]+(?!\d)")   # never into "20,000"
DURATION = re.compile(r"(?:^|(?<=[\s\-]))\d{1,3}m\d{2}s\b")
# A " - " part that is a code: digits joined by hyphens ("32-22"), x placeholders ("xxxx"); a lone
# number only as the first part (a track number), never later ("Friar Tuck - 33" is chapter 33).
CODE_PART = re.compile(r"^\d+(?:-\d+)+$|^x+$", re.I)
LONE_NUMBER = re.compile(r"^\d+$")
NUMBERED = re.compile(r"^(?:EP?\.?|#)?\s?\d", re.I)
SMALL = {"a", "an", "the", "and", "or", "nor", "but", "of", "at", "in", "on", "to", "for", "by", "with", "from", "as"}
PART = re.compile(r"\s+-+\s*|\s*-+\s+")
LETTER = re.compile(r"[^\W\d_]")
WORD = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)*")
MIN_SPLIT = 10         # a run-together word is at least this long ("CORSICAN" and "REVELATOR" are words)
MIN_PIECE = 3
# The two-letter words a split may use; any other piece is three letters or more ("SUMMERWEEN" is
# not "summer we en").
SHORT = {"an", "as", "at", "be", "by", "do", "go", "he", "in", "is", "it", "me", "my", "no", "of", "on", "or",
         "so", "to", "up", "us", "we"}
MIN_USES = 3           # a piece is a word of the catalog's when this many titles spell it on its own


def _words(t):
    words = re.findall(r"[^\W_]+", t)
    return len(words) >= 3 and sum(1 for w in words if re.search(r"[^\W\d_]", w)) >= 2


def clean(raw):
    """The 2026-10-22 rules: extension, underscores, hyphen runs, glued track digits, humps."""
    t = EXT.sub("", raw.strip())
    if "_" in t:
        t = re.sub(r"_+", " ", t)
    spaceless = " " not in t
    if spaceless and "-" in t and _words(t):
        t = HYPHEN_RUN.sub(lambda m: " - " if len(m.group()) >= 3 else " ", t)
    t = GLUED_TRACK.sub("", t)
    if spaceless and len(HUMP.findall(t)) >= 2:
        t = MC.sub(r"\1\2", HUMP.sub(" ", t))
    return re.sub(r"\s{2,}", " ", t).strip()


def _fold(s):
    s = re.sub(r"[^\w\s]", " ", s.casefold())
    s = re.sub(r"^(the|a|an)\s+", "", s.strip())
    return re.sub(r"\s+", " ", s).strip()


class Words:
    """The catalog's own vocabulary: how often each word is spelled on its own (between spaces)
    across distinct titles and names, and the case the mixed-case ones write it in."""

    def __init__(self, texts):
        self.uses, forms = {}, {}
        for t in sorted(set(x for x in texts if x)):
            if " " not in t.strip():
                continue
            mixed = re.search(r"[a-z]", t) is not None
            found = WORD.findall(t)
            for w in set(found):
                k = w.casefold()
                self.uses[k] = self.uses.get(k, 0) + 1
            if mixed:   # a title's first word is capitalized whatever it is, so it says nothing
                for w in set(found[1:]):
                    forms.setdefault(w.casefold(), {}).setdefault(w, 0)
                    forms[w.casefold()][w] += 1
        self.case = {k: min(f.items(), key=lambda x: (-x[1], x[0]))[0] for k, f in forms.items()}

    def known(self, w):
        return self.uses.get(w.casefold(), 0) >= MIN_USES

    def piece(self, s):
        """A word a split may use: known, three letters or more (or a SHORT word), and never an
        acronym ("COR", "ISA": the catalog writes it in capitals)."""
        if not self.known(s) or (len(s) < MIN_PIECE and s not in SHORT):
            return False
        form = self.case.get(s)
        return not (form and len(form) > 1 and form.isupper())

    def split(self, w):
        """The one fewest-piece split of a run-together word into known words, or None."""
        s = w.casefold()
        n = len(s)
        best = [None] * (n + 1)   # (pieces, ways, split) for s[:i]
        best[0] = (0, 1, [])
        for i in range(1, n + 1):
            for j in range(max(0, i - 24), i - 1):
                piece = s[j:i]
                if best[j] is None or not self.piece(piece):
                    continue
                k, ways, parts = best[j]
                cand = (k + 1, ways, parts + [s[j:i]])
                if best[i] is None or cand[0] < best[i][0]:
                    best[i] = cand
                elif cand[0] == best[i][0]:
                    best[i] = (best[i][0], best[i][1] + ways, best[i][2])
        if best[n] is None or best[n][1] != 1 or best[n][0] < 2:
            return None
        parts = best[n][2]
        if any(len(x) < MIN_PIECE and len(y) < MIN_PIECE for x, y in zip(parts, parts[1:])):
            return None   # "POSTTOASTIES" is not "post to as ties": two short words in a row prove nothing
        return parts

    def cased(self, w, first):
        k = w.casefold()
        out = k if k in SMALL else self.case.get(k) or (w[:1].upper() + w[1:].lower())
        return out[:1].upper() + out[1:] if first else out


def _strip_codes(t, series):
    """Numbering, codes, durations and the series' own name, when words remain."""
    def keep(new):
        return new if LETTER.search(new or "") else None

    t = keep(DURATION.sub("", t).strip(" -")) or t
    for rule in (LEAD_CODE, LEAD_GROUPS, LEAD_PADDED):
        while True:
            new = keep(rule.sub("", t, count=1).strip(" -"))
            if not new or new == t:
                break
            t = new
    parts = PART.split(t)
    if len(parts) > 1:
        words = [p for i, p in enumerate(parts)
                 if not (CODE_PART.match(p.strip()) or (i == 0 and LONE_NUMBER.match(p.strip())))]
        name = _fold(series) if series and len(_fold(series).split()) >= 2 else None
        if name and len(words) > 1:
            words = [p for p in words if _fold(p) != name] or words
        if words and len(words) < len(parts):
            t = " - ".join(p.strip() for p in words)
    if series and len(_fold(series).split()) >= 2:
        name = _fold(series)
        m = re.match(r"^((?:the|a|an)\s+)?" + r"\W+".join(map(re.escape, name.split())) + r"(?=\s*[:\-])", t, re.I)
        rest = t[m.end():].lstrip(" :-") if m else ""
        if m and rest and LETTER.match(rest) and not rest[0].islower():
            t = rest
    return re.sub(r"\s{2,}", " ", t).strip()


def _recase(t, words):
    """An all-capitals title in the catalog's own case, its run-together words split when proved."""
    first = True

    def piece(m):
        nonlocal first
        w = m.group()
        parts = words.split(w) if len(w) >= MIN_SPLIT and not words.known(w) else None
        got = " ".join(words.cased(p, first and i == 0) for i, p in enumerate(parts or [w]))
        first = False
        return got

    return WORD.sub(piece, t)


def display_title(raw, series=None, words=None):
    """The title a person reads. series: the series' name (its own name is not repeated);
    words: the catalog's `Words` (without it, no case changes and nothing is split)."""
    if not raw:
        return raw
    t = clean(raw)
    t = _strip_codes(t, series)
    if words is not None and LETTER.search(t) and not re.search(r"[a-z]", t):
        t = _recase(t, words)
    return t or raw.strip()


def display_name(raw, words=None):
    """A series name as a person reads it: the same rules, with no series to drop."""
    return display_title(raw, None, words)


def _order(rows, shown):
    """The series' episodes in the order a client lists them (the web's `oldest_first`, Android's
    OLDEST_FIRST): date, number, then the title, casefolded and as written."""
    def key(r, binary):
        eid, air, num = r
        t = shown[eid] or ""
        return (air is None, air or "", num is None, num if num is not None else 0, t if binary else t.casefold(), eid)
    return [[r[0] for r in sorted(rows, key=lambda r: key(r, b))] for b in (False, True)]


def series_titles(episodes, series_name, words):
    """{episode id: display title} for one series' episodes [(id, air_date, num, raw title)]. The
    D3 rules apply only where they keep the order a client lists the episodes in: a reading's
    "03 - Mrs. Hudson" is what puts it third when it has no date and no number, so a series whose
    order would change with a leading number dropped keeps the 2026-10-22 rules (`clean`). An
    order that was only alphabetical ("Vanishing Point - Azure Blue") carries nothing to keep."""
    old = {e: clean(t) if t else t for e, _a, _n, t in episodes}
    new = {e: display_title(t, series_name, words) for e, _a, _n, t in episodes}
    rows = [(e, a, n) for e, a, n, _t in episodes]
    if _order(rows, new) == _order(rows, old):
        return new
    numbered = any(old[e] and NUMBERED.match(old[e]) and not NUMBERED.match(new[e] or "") for e in old)
    return old if numbered else new
