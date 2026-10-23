"""Turn a radio script or a stage play into roles and lines, never rewriting a word.

Built from the research prototypes (catalog/prototypes/scripts/radio_parse.py and
stage_parse.py, research 08b §2). A parse PROPOSES attributions for a person to
accept: it never fills a gap, modernizes a line, or writes a cast description
(08b §4; no AI-written copy). Every part of a line is an exact slice of the
source block (whitespace aside), so the words of the parts, in order, are the
words of the source less its brackets and the speaker's label.

A line is
    {"id": "L0007", "kind": "speech"|"sound"|"music"|"direction",
     "role": "FIBBER" | None, "source": "<the block as printed>",
     "parts": [{"say": ...}, {"direction": ...}, {"mic": ...}, {"sound": ...}]}
Stage directions are kept apart from speech (their own parts or lines) so the
people casting a stage play can decide how to read them for radio (Decision 059).

A text is a STUB, and not a script, when it is under 500 words or is a page of
links with no dialogue (measured 2026-10-22 on all 1,028 cached GRW texts: 39 too
short, such as "Information Coming Soon...", and 25 link pages, such as "PDF
files on Old Time Radio Researchers Group website"). A long text in which no
dialogue is found is a parse FAILURE (format_unrecognized), not a stub: one is the
Campbell Playhouse "Rebecca" with its line breaks lost. Neither is ever cast.

    python3 tools/script_parse.py measure     # the 50 GRW + 20 Gutenberg sample
"""
import collections
import glob
import html
import json
import os
import random
import re
import statistics
import sys

MIN_WORDS = 500
MIN_SPEECHES = 20
CASTABLE_LINES = 5
CLEAN_UNCLASSIFIED = 0.05

# ---- radio conventions (08b §2.1) ----------------------------------------------------------------
CUE_TAGS = {
    "music": r"MUSIC|THEME|ORCH(?:ESTRA)?|ORGAN|BAND|QUARTET|SONG|BRIDGE|STING",
    "sound": r"SOUND(?:\s*(?:EFFECTS?|FX))?|SFX|F/?X|EFFECTS?|SOUND\s*EFFECT|SOUND\s*PATTERN|BIZ|BUSINESS|APPLAUSE|NOISE",
}
CUE = re.compile(r"^\(?\s*(%s)\s*[:;.\-]\s*(.*)$" % "|".join(f"(?P<{k}>{v})" for k, v in CUE_TAGS.items()), re.I)
R_ROLE = re.compile(r"^\[?(?P<role>(?:\d+(?:ST|ND|RD|TH|st|nd|rd|th)\.?\s+)?[A-ZÀ-Þ][A-Za-zÀ-ÿ0-9.'&/\- ]{0,38}?)\]?"
                    r"\s*(?:\((?P<paren>[^)]{0,60})\))?\s*[:;]\s*(?P<text>.*)$")
R_ROLE_SPACED = re.compile(r"^(?P<role>[A-ZÀ-Þ][A-ZÀ-Þ0-9.'&\- ]{1,30}?)(?:\s*\((?P<paren>[^)]{0,60})\))?\s{3,}(?P<text>\S.*)$")
NOTROLE = re.compile(r"^(DATE|CAST|NOTE|PRODUCTION|SCENE|ACT|PAGE|PROGRAM|WRITER|DIRECTOR|SPONSOR|TITLE|SERIES|"
                     r"SOURCE|TRANSCRIBED|THANKS|https?)$", re.I)
SOUNDROLE = re.compile(r"\b(DOOR|KNOCK|PHONE|TELEPHONE|CROWD|APPLAUSE|LAUGH\w*|SCENE \d+|COMMERCIAL|BACKGROUND|"
                       r"VIBRAPHONE|GONG|BELL|SIREN|GUN\w*|SHOTS?|WIND|RAIN|THUNDER|FOOTSTEPS|CREDITS|AD LIBS?|"
                       r"SIGNOFF|ECHO|FILTER|CLOCK|CAR|TRAIN|PLANE|ENGINE|HORN|WHISTLE)\b")
MIC = re.compile(r"^\s*_?(in|off|on mike|off mike|coming in|going off|fading(?: in| out| off)?|fade(?: in| out)?|"
                 r"filter|close|distant|backing off|offstage|off stage)\b", re.I)
SOUNDWORD = re.compile(r"\b(knock\w*|sound|door|crowd|noise|bell|shot|thunder|wind|music|bugle|drum|cheer\w*|"
                       r"footsteps|horse|hoof\w*|crash|ring\w*|whistle|applause|laughter)\b", re.I)

# ---- stage conventions (08b §2.4) ----------------------------------------------------------------
CAP = r"[A-ZÀ-Þ][A-ZÀ-Þ0-9.'’\- ]{0,40}?"
S_ROLE_OWN = re.compile(r"^_?(?P<role>%s)_?\.?\s*(?P<d>\[[^\]]*\]|\(_[^)]*_\)|\([^)]*\))?\s*$" % CAP)
S_ROLE_COLON = re.compile(r"^_?(?P<role>%s)_?\s*:\s*(?P<text>.+)$" % CAP, re.S)
S_ROLE_INLINE = re.compile(r"^_?(?P<role>%s)_?\.\s+(?P<text>\S.+)$" % CAP, re.S)
CASTHEAD = re.compile(r"^_?(CAST|CAST OF CHARACTERS|PERSONS|CHARACTERS|DRAMATIS PERSON(?:AE|Æ)|THE PERSONS OF THE PLAY|"
                      r"PERSONS IN THE PLAY|PERSONS REPRESENTED|CHARACTERS IN THE PLAY)_?\.?:?\s*$", re.I)
HEADING = re.compile(r"^_?(ACT|SCENE|CURTAIN|END|THE END|PERSONS|CHARACTERS|DRAMATIS|FIRST ACT|SECOND ACT|THIRD ACT|"
                     r"FOURTH ACT|FIFTH ACT|PROLOGUE|EPILOGUE|PLAYS|CONTENTS|PREFACE|INTRODUCTION|NOTE|FOOTNOTES?|"
                     r"TRANSCRIBER|ILLUSTRATIONS?|CHAPTER|BOOK|PART|APPENDIX|INDEX|FINIS)\b", re.I)
# Mixed-case labels ("Ham.", "_Clap._", "Roberts:"), accepted only when the same label
# opens 3 or more lines of the text, so a prose sentence starting "Then." is not a role.
LABEL_MIXED = re.compile(r"^\s*_?(?P<role>[A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]{0,20}(?:\s+[A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]{0,20}){0,2})_?"
                         r"\s*[.:;]_?\s+(?P<text>\S.*)$", re.S)
NOT_LABEL = {"Enter", "Exit", "Exeunt", "Re-enter", "Manet", "Flourish", "Sennet", "Alarum", "Mr", "Mrs", "Dr",
             "St", "Mme", "Mlle", "Scene", "Act", "Note", "The", "A", "I", "O", "Oh", "Yes", "No", "Well", "Then"}
ENTRANCE = re.compile(r"^\s*_?(Enter|Re-?enter|Exit|Exeunt|Manet|Flourish|Sennet|Alarums?|A march|Sound|Trumpets|"
                      r"Thunder|Curtain|Scene|Act)\b", re.I)
DIR_SPAN = re.compile(r"\[[^\]]*\]|\([^)]*\)|(?<![A-Za-z0-9])_[^_\n]+_(?![A-Za-z0-9])")


def clean_html(raw):
    t = raw.replace("\r", "")
    if re.search(r"<(p|br|div|b)\b", t, re.I):
        t = re.sub(r"<br\s*/?>", "\n", t, flags=re.I)
        t = re.sub(r"</p>", "\n\n", t, flags=re.I)
        t = re.sub(r"<[^>]+>", "", t)
    return html.unescape(t)


def gutenberg_body(raw):
    t = raw.replace("\r", "")
    a = re.search(r"\*\*\* ?START OF TH(?:E|IS) PROJECT GUTENBERG[^\n]*\n", t)
    b = re.search(r"\*\*\* ?END OF TH(?:E|IS) PROJECT GUTENBERG", t)
    return t[a.end() if a else 0: b.start() if b else len(t)]


def split_parts(text):
    """Speech text -> parts, each an exact slice of `text`. Bracketed or italic spans are
    directions (mic words become `mic`, effect words `sound`); everything else is `say`."""
    parts, pos = [], 0
    for m in DIR_SPAN.finditer(text):
        say = text[pos:m.start()].strip()
        if say:
            parts.append({"say": say})
        inner = m.group(0)[1:-1].strip(" _")
        if inner:
            kind = "mic" if MIC.match(inner) else "sound" if (SOUNDWORD.search(inner) and m.group(0)[0] == "[") \
                else "direction"
            parts.append({kind: inner})
        pos = m.end()
    tail = text[pos:].strip()
    if tail:
        parts.append({"say": tail})
    return parts


def _role(r):
    return re.sub(r"\s+", " ", r.replace("’", "'").strip(" ._[]")).upper()


# ---- radio ---------------------------------------------------------------------------------------

def _radio_blocks(text):
    out = []
    for para in re.split(r"\n\s*\n", text):
        cur = None
        for l in (x.strip() for x in para.split("\n")):
            if not l:
                continue
            if cur is not None and not (R_ROLE.match(l) or R_ROLE_SPACED.match(l) or CUE.match(l)):
                cur += " " + l
            else:
                if cur is not None:
                    out.append(cur)
                cur = l
        if cur is not None:
            out.append(cur)
    return out


def _radio_items(text):
    bs = _radio_blocks(text)
    start = 0
    for i, b in enumerate(bs[:6]):
        if b.startswith("Date:"):
            start = i + 1
            m = re.match(r"Date:\s*(?:[A-Z][a-z]{2} \d{1,2} \d{4}|Date Unknown|circa \d{4}s|\d{4})(.+)$", b)
            if m:
                bs.insert(i + 1, m.group(1).strip())
    seq, merged, k = bs[start:], [], 0
    bare = re.compile(r"^[A-ZÀ-Þ][A-ZÀ-Þ.'\- ]{1,24}$")
    # a label printed on its own line is a role when it recurs (3+ times) or follows a speech
    recurring = {b for b, n in collections.Counter(seq).items() if n >= 3 and bare.match(b)}
    while k < len(seq):
        b = seq[k]
        if (bare.match(b) and len(b.split()) <= 3 and k + 1 < len(seq) and not R_ROLE.match(seq[k + 1])
                and not CUE.match(seq[k + 1]) and not SOUNDROLE.search(b) and not bare.match(seq[k + 1])
                and (b in recurring or any(R_ROLE.match(x) for x in seq[max(0, k - 6):k]))):
            merged.append((b, seq[k + 1]))
            k += 2
            continue
        merged.append((None, b))
        k += 1
    items, incast = [], False
    for label, b in merged:
        if re.match(r"^(CAST|CAST OF CHARACTERS|CHARACTERS|DRAMATIS PERSONAE)\s*:?\s*$", b, re.I):
            incast = True
            items.append({"kind": "cast", "source": b})
            continue
        if incast and not label and len(b) <= 80 and not (CUE.match(b) or R_ROLE.match(b)):
            items.append({"kind": "cast", "source": b})
            continue
        incast = False
        if label:
            items.append({"kind": "speech", "role": _role(label), "source": label + "\n" + b, "text": b})
            continue
        m = CUE.match(b)
        if m:
            items.append({"kind": next(k for k in CUE_TAGS if m.group(k)), "source": b})
            continue
        m = R_ROLE.match(b) or R_ROLE_SPACED.match(b)
        if m and not NOTROLE.match(m.group("role").strip()) and len(m.group("role").split()) <= 5:
            role = _role(m.group("role"))
            if SOUNDROLE.search(role):
                items.append({"kind": "sound", "source": b})
                continue
            text = b[m.start("text"):]
            lead = [{"direction": m.group("paren").strip()}] if m.group("paren") else []
            if lead and MIC.match(lead[0]["direction"]):
                lead = [{"mic": lead[0]["direction"]}]
            items.append({"kind": "speech", "role": role, "source": b, "text": text, "lead": lead})
            continue
        if re.match(r"^\(.*\)$", b, re.S):
            items.append({"kind": "direction", "source": b})
            continue
        if re.search(r"[A-Z]{2}", b) and not re.search(r"[a-z]", b):
            # a capitals line that is not a role: an unlabeled cue or a scene heading
            items.append({"kind": "sound" if SOUNDROLE.search(b) or SOUNDWORD.search(b) else "direction",
                          "source": b})
            continue
        items.append({"kind": "other", "source": b})
    return items


# ---- stage ---------------------------------------------------------------------------------------

def frequent_labels(text):
    counts = collections.Counter()
    for line in text.split("\n"):
        m = LABEL_MIXED.match(line)
        if m and m.group("role") not in NOT_LABEL and not HEADING.match(m.group("role")):
            counts[m.group("role")] += 1
    return {k for k, n in counts.items() if n >= 3}


def _stage_paras(text, labels):
    """Blank-line paragraphs, split again where a line opens with a known label or an
    entrance. An entrance inside a speech stands alone, and the verse after it is marked
    as that speech continuing (Folio-style texts print them so)."""
    out = []
    for p in re.split(r"\n\s*\n", text):
        cur, cont = [], False
        for line in p.split("\n"):
            m = LABEL_MIXED.match(line)
            if cur and m and m.group("role") in labels:
                out.append(("\n".join(cur), cont))
                cur, cont = [], False
            elif cur and ENTRANCE.match(line):
                out.append(("\n".join(cur), cont))
                out.append((line, False))
                cur, cont = [], True
                continue
            cur.append(line)
        out.append(("\n".join(cur), cont))
    return [(x.strip(), c) for x, c in out if x.strip()]


def _stage_items(text):
    labels = frequent_labels(text)
    paras = _stage_paras(text, labels)
    items, pending, pending_src, incast, casts, last_role = [], None, None, False, 0, None
    for p, cont in paras:
        if items and items[-1]["kind"] in ("speech", "heading", "cast"):
            last_role = items[-1].get("role")
        lines = p.split("\n")
        first = lines[0].strip()
        if CASTHEAD.match(first):
            incast, casts, pending = True, casts + 1, None
            items.append({"kind": "cast", "source": p})
            continue
        if incast:
            lab = LABEL_MIXED.match(first)
            speaks = (lab and lab.group("role") in labels) or S_ROLE_COLON.match(first) or ENTRANCE.match(first) \
                or re.match(r"^_?SCENE\b", first, re.I)
            if all(len(l.strip()) < 70 for l in lines) and not speaks:
                items.append({"kind": "cast", "source": p})
                continue
            incast = False
        if HEADING.match(first) and len(lines) <= 3 and first.upper() == first:
            items.append({"kind": "heading", "source": p})
            pending = None
            continue
        m = S_ROLE_OWN.match(first)
        if m and len(m.group("role").split()) <= 4 and not HEADING.match(m.group("role")):
            rest = "\n".join(l.strip() for l in lines[1:]).strip()
            lead = [{"direction": m.group("d").strip("[]() _")}] if m.group("d") else []
            if rest:
                items.append({"kind": "speech", "role": _role(m.group("role")), "source": p, "text": rest, "lead": lead})
                pending = None
            else:
                pending, pending_src = (_role(m.group("role")), lead), p
            continue
        joined = " ".join(l.strip() for l in lines)
        m = LABEL_MIXED.match(joined)
        if m and m.group("role") in labels:
            items.append({"kind": "speech", "role": _role(m.group("role")), "source": p, "text": m.group("text")})
            pending = None
            continue
        m = S_ROLE_COLON.match(joined) or S_ROLE_INLINE.match(joined)
        if m and len(m.group("role").split()) <= 4 and not HEADING.match(m.group("role")) \
                and m.group("role").strip(" ._").upper() == m.group("role").strip(" ._"):
            items.append({"kind": "speech", "role": _role(m.group("role")), "source": p, "text": m.group("text")})
            pending = None
            continue
        if pending and re.match(r"^_?(SCENE|PLACE|TIME)\b", joined):
            pending = None
        if pending:
            items.append({"kind": "speech", "role": pending[0], "source": pending_src + "\n" + p, "text": joined,
                          "lead": pending[1]})
            pending = None
            continue
        if re.match(r"^[\[(_]", joined) or ENTRANCE.match(joined):
            items.append({"kind": "direction", "source": p})
            continue
        if cont and last_role:
            items.append({"kind": "speech", "role": last_role, "source": p, "text": joined, "continues": True})
            continue
        if items and items[-1]["kind"] == "speech":
            items[-1]["source"] += "\n\n" + p
            items[-1]["text"] += "\n" + joined
            items[-1]["continued"] = items[-1].get("continued", 0) + 1
            continue
        items.append({"kind": "other", "source": p})
    return items, casts


# ---- the shared model ----------------------------------------------------------------------------

def stub_check(text, items=None):
    words = len(text.split())
    links = len(re.findall(r"https?://", text))
    if words < MIN_WORDS:
        return "link_page" if links else "too_short"
    if items is not None:
        speeches = sum(1 for i in items if i["kind"] == "speech")
        if speeches < MIN_SPEECHES:
            return "link_page" if links and words < 2000 else "format_unrecognized"
    return None


def parse(raw, kind):
    """kind: "radio" (a broadcast script) or "stage" (a Gutenberg play text)."""
    text = clean_html(raw) if kind == "radio" else gutenberg_body(raw)
    stub = stub_check(text)
    casts = 0
    if stub:
        return {"status": "stub", "stub_kind": stub, "words": len(text.split())}
    if kind == "radio":
        items = _radio_items(text)
    else:
        items, casts = _stage_items(text)
    stub = stub_check(text, items)
    if stub == "format_unrecognized":
        return {"status": "failed", "issues": [stub], "words": len(text.split())}
    if stub:
        return {"status": "stub", "stub_kind": stub, "words": len(text.split())}
    lines, roles, unclassified = [], collections.OrderedDict(), []
    for it in items:
        if it["kind"] in ("cast", "heading"):
            continue
        if it["kind"] == "other":
            unclassified.append(it["source"])
            continue
        lid = f"L{len(lines) + 1:04d}"
        if it["kind"] == "speech":
            parts = (it.get("lead") or []) + split_parts(it["text"])
            r = roles.setdefault(it["role"], {"name": it["role"], "lines": 0, "words": 0})
            r["lines"] += 1
            r["words"] += sum(len(p["say"].split()) for p in parts if "say" in p)
            lines.append({"id": lid, "kind": "speech", "role": it["role"], "source": it["source"], "parts": parts})
        else:
            lines.append({"id": lid, "kind": it["kind"], "role": None, "source": it["source"]})
    blocks = len(lines) + len(unclassified)
    castable = [r for r in roles.values() if r["lines"] >= CASTABLE_LINES]
    big = [r["name"] for r in castable]
    aliases = [r["name"] for r in roles.values() if r["lines"] <= 2 and any(
        r["name"] != b and (b.startswith(r["name"]) or r["name"].startswith(b)) for b in big)]
    issues = []
    share = len(unclassified) / max(1, blocks)
    if share > CLEAN_UNCLASSIFIED:
        issues.append("unclassified_over_5pct")
    if len(castable) < 2:
        issues.append("fewer_than_two_castable_roles")
    if casts > 1:
        issues.append("several_plays_in_one_text")
    if aliases:
        issues.append("possible_aliases")
    clean = not any(i in issues for i in ("unclassified_over_5pct", "fewer_than_two_castable_roles",
                                          "several_plays_in_one_text"))
    return {"status": "parsed", "clean": clean, "issues": issues, "roles": list(roles.values()),
            "castable_roles": len(castable), "lines": lines, "unclassified": unclassified,
            "unclassified_share": round(share, 3), "aliases": aliases, "words": len(text.split())}


# ---- the measurement -----------------------------------------------------------------------------

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "..", ".cache")


def _summary(results):
    parsed = [r for r in results if r["status"] == "parsed"]
    fail = collections.Counter()
    for r in results:
        if r["status"] == "stub":
            fail["stub:" + r["stub_kind"]] += 1
        elif r["status"] == "failed":
            fail.update(r["issues"])
        else:
            fail.update(i for i in r["issues"])
    med = lambda xs: statistics.median(xs) if xs else None
    return {"sample": len(results), "stubs": sum(r["status"] == "stub" for r in results),
            "failed": sum(r["status"] == "failed" for r in results), "parsed": len(parsed),
            "clean": sum(r["clean"] for r in parsed),
            "roles_median": med([len(r["roles"]) for r in parsed]),
            "castable_roles_median": med([r["castable_roles"] for r in parsed]),
            "castable_roles_range": [min((r["castable_roles"] for r in parsed), default=None),
                                     max((r["castable_roles"] for r in parsed), default=None)],
            "speeches_median": med([sum(1 for l in r["lines"] if l["kind"] == "speech") for r in parsed]),
            "unclassified_share_median": med([r["unclassified_share"] for r in parsed]),
            "failure_kinds": dict(fail)}


def measure():
    grw = sorted(glob.glob(os.path.join(CACHE, "grw", "text", "*.txt")))
    sample = random.Random(20261022).sample(grw, 50)
    rows = []
    for f in sample:
        r = parse(open(f, encoding="utf-8", errors="replace").read(), "radio")
        rows.append({"id": os.path.basename(f)[:-4], **{k: r.get(k) for k in ("status", "stub_kind", "clean", "issues",
                                                                               "castable_roles", "unclassified_share",
                                                                               "words")},
                     "roles": len(r.get("roles") or [])})
        r["_id"] = rows[-1]["id"]
        rows[-1]["_r"] = r
    plays = sorted(glob.glob(os.path.join(CACHE, "gutenberg", "text", "*.txt")))
    prow = []
    for f in plays:
        r = parse(open(f, encoding="utf-8", errors="replace").read(), "stage")
        prow.append({"id": "gut-" + os.path.basename(f)[:-4], "_r": r})
    out = {"grw": _summary([x["_r"] for x in rows]), "gutenberg": _summary([x["_r"] for x in prow]),
           "grw_rows": [{k: v for k, v in x.items() if k != "_r"} for x in rows],
           "gutenberg_rows": [{"id": x["id"], "status": x["_r"]["status"], "stub_kind": x["_r"].get("stub_kind"),
                               "clean": x["_r"].get("clean"), "issues": x["_r"].get("issues"),
                               "roles": len(x["_r"].get("roles") or []), "castable_roles": x["_r"].get("castable_roles"),
                               "unclassified_share": x["_r"].get("unclassified_share"), "words": x["_r"].get("words")}
                              for x in prow]}
    json.dump(out, sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    if sys.argv[1:] == ["measure"]:
        measure()
    elif len(sys.argv) == 3:
        r = parse(open(sys.argv[2], encoding="utf-8", errors="replace").read(), sys.argv[1])
        json.dump(r, sys.stdout, indent=1, ensure_ascii=False)
        print()
    else:
        raise SystemExit("usage: script_parse.py measure | script_parse.py radio|stage FILE")
