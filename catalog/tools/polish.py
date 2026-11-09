"""The last pass over every text a listener reads (P-8, owner 2026-10-31: no raw uploads on screen).

Imported by build_projection.py, never copied. Each rule undoes one upload habit and adds nothing: every word out is
a word the source spelled, apart from the dictionary contractions in CONTRACTIONS and the small-word case. A text
that still carries a habit after this pass is unreadable (`readable`) and is composed from data or withheld.

  polish_title / polish_name   episode titles, `aka`, arc titles, series names
  polish_role                  a credit's role: (role, character), or the role withheld
  polish_person                a person's name: a doubled first capital ("JOhnny") set right
  recording_label              the clean name of the item a copy comes from, or None
"""
import re

import field_defects as FD
import text_defects as TD

SMALL = ("of", "the", "and", "or", "in", "on", "to", "for", "at", "by", "with", "from", "an")

CONTRACTIONS = {"dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "isnt": "isn't", "wasnt": "wasn't",
                "arent": "aren't", "werent": "weren't", "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't",
                "couldnt": "couldn't", "wouldnt": "wouldn't", "shouldnt": "shouldn't", "thats": "that's",
                "whats": "what's", "theres": "there's", "wheres": "where's", "youre": "you're", "theyre": "they're",
                "youve": "you've", "weve": "we've", "theyve": "they've", "youll": "you'll", "theyll": "they'll",
                "cant": "can't", "ive": "I've", "im": "I'm"}
# "Lets" is a verb elsewhere ("Mother Lets Go"), so it is a contraction only as the first word of a title or part.
LEAD_CONTRACTIONS = {"lets": "let's"}

_CP1252 = "cp1252"
_NOTE_WORDS = r"modified|edited|fixed|rip|ripped|vbr|mono|stereo|network|afrts|afrs|afrts-fen|rerun|off-air copy|off air copy|hq|copy|remastered|restored"
_DROP_GROUP = re.compile(
    r"\s*[\[\({]\s*(?:[bpm]0[0-9a-z]{6}|" + _NOTE_WORDS + r"|hq@[\d-]+|\d{2,3}\s?kbps?)\s*[\]\)}]", re.I)
# A number or short code in square or curly brackets is a shelf or track code; in parentheses it is the source's own number.
_DROP_CODE = re.compile(
    r"\s*[\[{]\s*(?:\d{1,4}|\d+\s*[-/of]+\s*\d+|[A-Za-z]{1,4}\s?\d{1,4}|#?\d+of\d+|[A-Za-z]+\s*[-:]?\s*#\d+of\d+)\s*[\]}]")
_INVERTED = re.compile(r"^(?P<head>.+?),\s+(?P<art>The|An|A)(?P<tail>\s*(?:[-\u2013(].*|,\s*episode.*)?)$")
_BAD_BRACKET = re.compile(r"\s*\{[A-Za-z]+\)|\s*\([A-Za-z]+\}")
_GLUED_CODE = re.compile(r"^(?:aud|trk|track|tk|cd|disc|prog|file|rec|sc|nr)\d{1,3}\s+(?=\S)", re.I)
_EP_OF = re.compile(r"\s*[-,]?\s*\bEp\.?\s?(\d+)\s?of\s?(\d+)\b", re.I)
_EP_TAIL = re.compile(r"\s*-\s*Ep\.?\s?(\d+)\s*$", re.I)
_A_GLUE = re.compile(r"\bA([A-Z][a-z]{2,})\b")
_TRAIL = re.compile(r"(?:\s*[-–,:;/]+)+\s*$")
_LEAD = re.compile(r"^\s*[-–,:;/]+\s*")
_UPLOAD_TAIL = re.compile(
    r"(?:\s+|-)(?:alt\.?\s*source|alternate\s+source|ver\.?\s?\d+|v\d+(?![\w.])|copy\s?\d*(?=$)|re-?issue|re-?mastered)\s*$",
    re.I)
_CAPS_TAIL = re.compile(r"\s+(?:ALT\s+SOURCE|REMASTERED|RE-?ISSUE|COPY|DUPE)\s*$")
_COUNT_TAIL = re.compile(r"\s+\(?(?:over\s+)?\d[\d,]*\+?\s*(?:eps?|episodes?|shows?)\)?\s*$", re.I)
_COUNT_SUB = re.compile(r"\s*[-–:,]\s*(?:over\s+)?\d[\d,]*\+?\s+(?:episodes?|shows?|eps)\b.*$", re.I)
_PAREN_NOTE = re.compile(r"\s*[\(\[]\s*(?:hq|off-air copy|off air copy|copy|alt(?:ernate)? (?:source|version)|"
                         r"remaster(?:ed)?|better quality)\s*[\)\]]", re.I)
_QUOTE_MOJI = re.compile("â[\u0080-\u009f€™œ“”˜‹›‘’]+")
_SPLIT_TOKENS = re.compile(r"(\W+)")


def fix_encoding(t):
    """The text with a mis-decoded UTF-8 run set right, or None when characters were lost beyond repair."""
    if t is None:
        return None
    if re.search("[ÂÃâ][\u0080-¿ŒœŠšŸŽžˆ˜–-›€™]", t):
        for _ in range(3):
            for enc in (_CP1252, "latin-1"):
                try:
                    t2 = t.encode(enc).decode("utf-8")
                except (UnicodeEncodeError, UnicodeDecodeError):
                    continue
                t = t2
                break
            else:
                break
        t = _QUOTE_MOJI.sub("'", t)
    t = re.sub(r"(?<=[A-Za-z])\?{2,3}(?=s\b|t\b|re\b|ll\b|ve\b|d\b|m\b)", "'", t)
    if "�" in t or re.search("[ÂÃâ][\u0080-¿]", t) or re.search(r"\?[À-ÿ]", t):
        return None
    return t


def small_words(t):
    """Lowercase the small words of a title-case title ("The Case Of The Doll" -> "The Case of the Doll")."""
    return FD.lower_small_words(t)


def _contractions(t):
    parts = _SPLIT_TOKENS.split(t)
    start = True
    for i, p in enumerate(parts):
        if re.match(r"[A-Za-z]+$", p):
            low = p.lower()
            new = CONTRACTIONS.get(low) or (LEAD_CONTRACTIONS.get(low) if start else None)
            if new and not (low in ("im", "ive") and not start):
                new = new.capitalize() if p[0].isupper() and not new.startswith("I") else new
                if p.isupper() and len(p) > 2:
                    new = new.upper()
                parts[i] = new
            start = False
        elif re.search(r"[:–—/?!.(]|\s-\s", p):
            start = True
    return "".join(parts)


# P-12 (catalog DECISIONS 033): markup a source left in its text ("<strong>01: Adam and Eve").
_MARKUP = re.compile(r"</?(?:strong|b|i|em|u|br|p|span|div|a|font)\b[^>]*>", re.I)


def _brackets(t):
    t = _DROP_GROUP.sub("", t)
    t = _DROP_CODE.sub("", t)
    t = _BAD_BRACKET.sub("", t)
    t = re.sub(r"(?<=\w)\[\d+\]", "", t)
    t = re.sub(r"\[([^\[\]]+)\]", r"(\1)", t)
    t = re.sub(r"\{([^{}]+)\}", r"(\1)", t)
    return t


def _clean(t, name=False):
    if t is None:
        return None
    t = fix_encoding(t)
    if t is None:
        return None
    t = _MARKUP.sub("", t)
    t = _brackets(t)
    t = _PAREN_NOTE.sub("", t)
    t = _GLUED_CODE.sub("", t)
    t = _EP_OF.sub(lambda m: "" if re.search(r"episode\s+0*%d\s+of\s+0*%d" % (int(m.group(1)), int(m.group(2))), t, re.I)
                   else ", episode %d of %d" % (int(m.group(1)), int(m.group(2))), t)
    m = _EP_TAIL.search(t)
    if m:
        t = t[:m.start()] + ", episode %d" % int(m.group(1))
    t = re.sub(r"(?<=[A-Za-z0-9\)])\s*--+\s*(?=[A-Za-z0-9\(])", " - ", t)
    t = _A_GLUE.sub(r"A \1", t)
    for _ in range(2):
        t = _UPLOAD_TAIL.sub("", t)
        t = _CAPS_TAIL.sub("", t)
    if name:
        t = _COUNT_TAIL.sub("", t)
        t = _COUNT_SUB.sub("", t)
    t = re.sub(r"\s{2,}", " ", t)
    t = _LEAD.sub("", t)
    t = _TRAIL.sub("", t)
    t = re.sub(r"\(\s*\)", "", t)
    return t.strip()


# P-10 (owner 2026-11-09): a small word glued to the next ("Battle WithThe Apes", "TheIdeal"), a recording-condition
# note ("Hippo clipped", "Army Life (end clipped)", "clippe" cut off), an uploader's "(Combines all dates)".
_GLUED_SMALL = re.compile(r"\b(The|With|And|Of|In|On|At|To|For|From)(?=(?:The|A|An|[A-Z][a-z]{2,})\b)")
_CLIPPED = re.compile(r"(?:\s*\((?:(?:start|end)\s+)?clipped\)|,?\s+(?:(?:start|end)\s+)?clipp(?:ed?)?)\s*$")
_CLIPPED_LEAD = re.compile(r"^clipped\s+(?=\S)")
_COMBINED_NOTE = re.compile(r"\s*\(\s*combines all dates\s*\)", re.I)


def polish_title(t):
    """The shown title with the upload habits undone, or None when nothing readable is left."""
    t = _clean(t)
    if not t:
        return None
    t = _COMBINED_NOTE.sub("", _CLIPPED_LEAD.sub("", _CLIPPED.sub("", t)))
    t = _GLUED_SMALL.sub(r"\1 ", t).strip()
    if not t:
        return None
    m = _INVERTED.match(t)
    if m and len(m.group("head").split()) >= 2:
        t = f"{m.group('art')} {m.group('head')}{m.group('tail')}"
    return small_words(_contractions(t))


def apostrophe_from(title, witnesses):
    """The title with the apostrophe an independent source spells ("Let's Call the Whole Thing Off"), when exactly one
    witness spells the same letters with one and is not shouted; else the title unchanged."""
    if not title or not witnesses or "'" in title or "’" in title:
        return title
    flat = lambda x: re.sub(r"[^a-z0-9]", "", x.casefold())
    good = {w.strip() for w in witnesses if re.search(r"\w['’]\w|s['’](?:\s|$)", w) and flat(w) == flat(title)
            and w != w.upper() and w != w.lower()}
    return small_words(good.pop()) if len(good) == 1 else title


def polish_name(n):
    n = _clean(n, name=True)
    if not n:
        return None
    return small_words(n)


_ROLE_OK = re.compile(r"^[a-z][a-z.&'/ -]*$")
_ROLE_AS = re.compile(r"^(?P<role>[^'\"]*?)[\s,;:-]*\b(?:billed\s+)?as\s+(?P<ch>.+)$")


def polish_role(role, character=None):
    """(role, character): the role as a word or two, a stage name that rode in the role set aside as the character,
    or role None (shown as cast) when what is left is a sentence or a note."""
    r = fix_encoding(role or "")
    if r is None:
        return None, character
    r = r.strip().strip("?").strip()
    r = r.replace("’", "'")
    if r.startswith("billed"):
        return None, character
    m = _ROLE_AS.match(r)
    if m:
        ch = polish_character(m.group("ch").strip(" '\"?!.")) or ""
        r = m.group("role").strip(" ,;:-")
        if ch and not character and re.search(r"[a-z]", ch) and len(ch.split()) <= 5:
            character = ch.title() if ch == ch.lower() else ch
        if r in ("billed", ""):
            r = ""
    r = r.split(":")[0].split(";")[0].strip(" ,;-?")
    r = re.sub(r"^\?+\s*", "", r)
    if (not r or len(r) > 30 or len(r.split()) > 3 or not _ROLE_OK.match(r) or re.fullmatch(r"(?:washington )?d\.?\s?c\.?", r)
            or "'" in r):
        return None, character
    return r, character


_MOJI_EDGE = re.compile("^[\u00c3\u00c2\u00e3\u00e2\u00a2\u0080-\u009f?\u20ac\u2122]+|[\u00c3\u00c2\u00e3\u00e2\u00a2\u0080-\u009f\u20ac\u2122]+$")


def polish_character(ch):
    """A character name whose quote marks arrived as broken characters ("\u00c3\u00a2??Old Nancy\u00e3\u00a2"), set right or trimmed."""
    if not ch:
        return ch
    got = fix_encoding(ch)
    got = _MOJI_EDGE.sub("", got if got is not None else ch)
    got = re.sub("[\u00c3\u00c2\u00e3\u00e2\u00a2\u0080-\u009f\u20ac\u2122]+\\??", "'", got).strip(" '\"")
    return got or None


def polish_person(name):
    n = (name or "").strip()
    n = re.sub(r"\b([A-Z])([A-Z])([a-z]{2,})\b", lambda m: m.group(1) + m.group(2).lower() + m.group(3), n)
    n = re.sub(r"\b([A-Z][a-z]{2,})([A-Z][a-z]{2,})\b", lambda m: m.group(1) + " " + m.group(2)
               if not re.match(r"(?:Mc|Mac|De|La|Le|Di|Van|Von|O)[A-Z]", m.group(0)) else m.group(0), n)
    return n


_ORG_NAME = re.compile(r"^(?P<name>[A-Z][\w.&' ,-]*?\b(?:Project|Archive|Archives|Society|Library|Researchers|Club|Foundation|"
                       r"Network|Productions?|Radio Theatre|Company|Collection|Group|Association)\b)\s*[-–:]\s+\S")
_COUNT_NAME = re.compile(r"\s*[-–:,(]?\s*(?:over\s+)?\d[\d,]*\+?\s+(?:full\s+)?(?:episodes?|eps|shows?|programs?|broadcasts?|recordings?|files?)\b.*$", re.I)
_LABEL_DATE = re.compile(r"\b\d{2}[\s.\-]\d{2}[\s.\-]\d{2}\b|\b\d{6,}\b|\b(?:19|20)\d\d[\s.\-]\d{1,2}[\s.\-]\d{1,2}\b|\b[A-Z]\d{3,}\b")
_LABEL_FAMILIES = (
    (re.compile(r"^OTRR_", re.I), "Old Time Radio Researchers"),
)


def recording_label(archive_id, title, episodes):
    """The clean name of the item a copy comes from, or None. Order: a family the identifier itself names (OTRR_ is
    the Old Time Radio Researchers' release series); else the item's own title, cleaned: the organization before a
    " - " ("Ron Bowser-John Dunning Project - Superman"), the title without an upload's episode count, its
    all-capital words set in case. A title that restates one broadcast (a date, a code, a file name) names the
    broadcast, not the source, so a copy that is its item's only broadcast has no label and the app says "Recording N"."""
    for rx, label in _LABEL_FAMILIES:
        if rx.match(archive_id or ""):
            return label
    t = fix_encoding(title or "")
    if not t or episodes < 2:
        return None
    t = t.strip()
    m = _ORG_NAME.match(t)
    if m:
        t = m.group("name")
    t = _COUNT_NAME.sub("", t)
    t = re.sub(r"\(\s*OTR\s*\)|\bOTR\b", "", t)
    t = " ".join(re.sub(r"(?<=[a-z])(?=[A-Z][a-z])", " ", w) if TD._runtogether(w) else w for w in t.split()).strip(" -–:,")
    t = _clean(t, name=True)
    if not t:
        return None
    t = re.sub(r"\b[A-Z]{5,}\b", lambda m: m.group(0).capitalize()
               if sum(c in "AEIOU" for c in m.group(0)) / len(m.group(0)) >= 0.3 else m.group(0), t)
    if re.search(r"Bowser.*Dunning Project", t):
        t = "Ron Bowser-John Dunning Project"
    t = small_words(t)
    if (len(t) > 60 or len(t) < 4 or _LABEL_DATE.search(t) or "_" in t or "\\" in t or re.search(r"\d{5,}", t)
            or FD.text_defects(t, "label")):
        return None
    return t


VARIANT_LABELS = {"afrs": "AFRS rebroadcast", "afrts": "AFRTS rebroadcast", "rehearsal": "Rehearsal",
                  "audition": "Audition"}
LONGER, KBPS_STEP = 0.10, 1.25


def _median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if len(xs) % 2 else (xs[len(xs) // 2 - 1] + xs[len(xs) // 2]) / 2


def _copy_facts(i, copies):
    """What tells copy i apart from the episode's other copies, most telling first: its variant, a partial copy,
    a clearly longer or shorter length, a clearly higher or lower bitrate, the year its item was uploaded.
    Each fact is read from the copy's own row; a fact every copy shares tells nothing."""
    me, others = copies[i], [c for j, c in enumerate(copies) if j != i]
    out = []
    v = (me.get("variant") or "").casefold()
    if v in VARIANT_LABELS and any((o.get("variant") or "").casefold() != v for o in others):
        out.append(VARIANT_LABELS[v])
    if me.get("partial") and not all(o.get("partial") for o in others):
        out.append("Partial copy")
    lens = [o["length_s"] for o in others if o.get("length_s")]
    if me.get("length_s") and lens:
        mid = _median(lens)
        if me["length_s"] >= mid * (1 + LONGER) and me["length_s"] - mid >= 60:
            out.append("Longer copy")
        elif me["length_s"] <= mid * (1 - LONGER) and mid - me["length_s"] >= 60 and "Partial copy" not in out:
            out.append("Shorter copy")
    rates = [o["kbps"] for o in others if o.get("kbps")]
    if me.get("kbps") and rates:
        if me["kbps"] >= max(rates) * KBPS_STEP:
            out.append(f"Higher quality ({me['kbps']} kbps)")
        elif me["kbps"] * KBPS_STEP <= min(rates):
            out.append(f"Lower quality ({me['kbps']} kbps)")
    year = str(me.get("uploaded") or "")[:4]
    if year.isdigit() and any(str(o.get("uploaded") or "")[:4] != year for o in others):
        out.append(f"Uploaded {year}")
    mins = round(me["length_s"] / 60) if me.get("length_s") else None
    if mins and all(o.get("length_s") and round(o["length_s"] / 60) != mins for o in others):
        out.append(f"{mins} min")
    return out


def _counts(labels):
    seen = {}
    for lab in labels:
        seen[lab] = seen.get(lab, 0) + 1
    return seen


def copy_labels(copies):
    """A label for every copy of an episode with more than one (owner 2026-11-09: no "Recording 2"): the copy's
    source name (recording_label) when no other copy shares it; else that name and the first fact that tells the
    copy apart (_copy_facts), or the fact alone. When the rows hold nothing that differs, the default copy is
    "Best copy" (the pipeline's rank, DECISIONS 007) and the rest "Another copy". `copies`: dicts with source,
    variant, partial, length_s, kbps, uploaded, in rank order. Never the identifier, never a word the rows do not
    support. A single copy keeps its source name or None."""
    if len(copies) < 2:
        return [c.get("source") for c in copies]
    facts = [_copy_facts(i, copies) for i in range(len(copies))]
    labels = [c.get("source") for c in copies]
    for _ in range(3):
        seen = _counts(labels)
        clash = [i for i, lab in enumerate(labels) if lab is None or seen[lab] > 1]
        if not clash or not any(facts[i] for i in clash):
            break
        for i in clash:
            if facts[i]:
                f = facts[i].pop(0)
                low = f[:1].lower() + f[1:] if f[1:2].islower() else f
                labels[i] = f if labels[i] is None else f"{labels[i]}, {low}"
    seen, kept, out = _counts(labels), set(), []
    for i, lab in enumerate(labels):
        if lab is not None and seen[lab] > 1 and lab not in kept:
            kept.add(lab)
        elif lab is None:
            lab = "Best copy" if i == 0 else "Another copy"
        elif seen[lab] > 1:
            lab = f"{lab}, another copy"
        out.append(lab)
    return out
