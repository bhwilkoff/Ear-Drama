"""Italic words inside a speech that are spoken, not stage directions (catalog DECISIONS 048, BACKLOG-LOOP B28).

`script_parse.split_parts` reads an italic span with no bracket as a direction unless it is short, inside a sentence and
not a stage word. What that leaves out is drawn as stage business and never spoken: "be _yourself_." and "_Somebody's_ sent
me a ring". But real directions print the same way in other plays ("_aside_", "_rising_", "UMANSKI _and_ ANDERS _rise_"), so
a span becomes speech only on evidence that it is part of a sentence being said, and stays a direction otherwise (`why`):

- a closed-class word or two (a pronoun, an auxiliary, a question word, "not", "never": no direction is made of them alone)
  joined to a word of the speech on at least one side;
- words the ones before them cannot end without ("a hundred _dollars_.", "the court of _Savoy_", "Mr. _Dodge_, that");
- a name called or named inside a sentence ("_Alexis_, speak", "our dear _Lucy_."), and words inside quotation marks;
- in a play that brackets its directions and prints no stage business in bare italics (`Convention`): a short span inside a
  sentence, a word that opens one that goes on in lower case ("_Suppose_ he came"), and words that exclaim or ask ("_Veto!_").

Never a span in or beside a bracket, a stage word ("aside", "rising", "to him"), a speaker's label, a word beside a name in
capitals, a span that ends its own sentence as a label or a note does ("Ld. H.", "Colman 1768"), a line that is mostly italic
(stage business with the names in roman, a song), or six words and more outside quotation marks. What no rule settles stays a
direction: a direction read aloud is as wrong as a word left out.

The words are carried as the parser's own emphasis is: a `say` part of its own, its index in the line's `em`, so every offset
into the line's printed words stays; only where the print sets the italics against a letter ("_I_'ll") is the word one part,
with its printed marks ("_I_'ll"), which every reader draws and no voice says. Run after `play_corrections.apply` (whose
revisions are read against the play as the roles left it) and before `play_punctuation.mend`. A line nothing is found in is
the same object; ids, roles and order never move, and no word but a direction's is added to what is said.
"""
import re

import play_corrections as PC
import script_parse as P

MAX_WORDS = 5
MAX_QUOTED = 12
# No direction is one of these words alone.
CLOSED = frozenset("""i me my mine myself you your yours yourself yourselves thou thee thy thine thyself he him his himself she her hers
herself it its itself we us our ours ourselves they them their theirs themselves one who whom whose what which why how where when
somebody someone something anybody anyone anything everybody everyone everything nobody nothing this that these those
am is are was were be been do does did done have has had can could will would shall should may might must ought
don't doesn't didn't isn't aren't wasn't weren't haven't hasn't hadn't can't couldn't won't wouldn't shan't shouldn't mustn't ain't
i'm i'll i've i'd you're you'll you've you'd he's he'll he'd she's she'll she'd it's it'll that's that'll we're we'll we've we'd
they're they'll they've they'd there's who's what's where's let's
not never ever very such too so if yes
own same other many much more most some any every""".split())
JOINING = frozenset("and or but nor the a an of in on at by for from as than upon".split())
# What a sentence cannot end on: the words after it are its own.
NEEDS_MORE = frozenset("""a an the my your his her its our their thy mine thine this that these those some any no every each such what which whose
of in to for from by with at on upon into unto against between without through about than as like very so too more most quite
rather be is are was were am being been not and or nor but if an' o' th' mr mrs ms miss dr st messrs sir madam lady lord
i've you've have has had i'm you're he's she's it's they're we're don't didn't doesn't can't won't shall should will would
could can must may might i you he she we they who""".split())
DETERMINER = frozenset("a an the my your his her our their thy this that these those some any no every each such of mr mrs ms miss dr st".split())
STAGE_NOUNS = frozenset("""curtain exit exeunt omnes chorus song air music pause silence noise shout alarum alarums flourish hautboys trumpets drums
recitative duet trio quartet dance dances within without severally apart door bell thunder offstage letter reads sings both all
whispers whisper starts retires retire enters follows following kneel kneels kneeling bows curtsies embracing gestures hums whistles coughs hic
l r c lh rh uc dc business tableau picture scene act encore dinner supper bis crash bang knock knocks ring rings""".split())
ABBREVIATION = re.compile(r"\b(?:Mr|Mrs|Ms|Dr|St|Messrs|Mlle|Mme|Mons)\.$")
SENTENCE_END = re.compile(r"[.!?][\s\"'’”)\]]*$")
BRACKET = re.compile(r"[\[\](){}]")
ENTERS = re.compile(r"^\W*(?:re-?enter|enters?|exit|exeunt|manet)\b", re.I)
LABEL_LIKE = re.compile(r"\w\.\s+\w|\d|\w\.$")
NOTE_NEAR = re.compile(r"\b[Ee]d\. ?\d|\bll?\. ?\d|\bp\. ?\d|\]\s*$")
QUOTE_OPENS = re.compile(r"(?:^|[\s(—-])\"$|[“‘]$")
QUOTE_CLOSES = re.compile(r"[.,;:!?]?[\"”’](?![a-z])")


def words(s):
    return re.findall(r"[^\W\d_]+(?:['’\-][^\W\d_]+)*['’]?", s)


def key(w):
    return w.lower().replace("’", "'").strip("'")


def _plain(name):
    return re.sub(r"[^\w ]+", "", name.upper()).strip()


def _closed(inner):
    ws = words(inner)
    return 1 <= len(ws) <= 3 and all(key(w) in CLOSED or key(w).removesuffix("'s") in CLOSED for w in ws)


def _caps(token):
    """A name printed in capitals ("REGINALD", "(UMANSKI"), never "I" or "I'll"."""
    w = re.sub(r"^\W+|\W+$", "", token)
    return len(w) > 2 and w == w.upper() and bool(re.fullmatch(r"[^\W\d_]+(?:['’.\-][^\W\d_]+)*", w)) and key(w) not in ("i'll", "i'm", "i've", "i'd")


def stage_words(inner):
    """The span reads as stage business: a stage word, a participle, a manner ("sharply", "more cordial than ever")."""
    ws = words(inner)
    if not ws or _closed(inner):
        return False
    return P._directional(" ".join(w.replace("’", "'") for w in ws)) or ENTERS.match(inner) is not None \
        or any(key(w).endswith("ly") and len(w) > 4 or key(w) in STAGE_NOUNS for w in ws)


def _bracket_open(parts, k):
    before = " ".join(p["say"] for p in parts[:k] if "say" in p)
    return before.count("[") > before.count("]") or before.count("{") > before.count("}") or before.rstrip().endswith("(")


def _mostly_italic(parts):
    it = sum(len(words(p["direction"])) for p in parts if isinstance(p.get("direction"), P.Italic))
    return it >= 8 and it > sum(len(words(p["say"])) for p in parts if "say" in p)


class Convention:
    """How a play prints its stage business: in brackets, or in bare italics."""

    def __init__(self, entry):
        bracketed = business = plain = 0
        self.roles = set()
        for line in entry["lines"]:
            if line["kind"] != "speech":
                continue
            self.roles.add(_plain(line["role"]))
            plain += len(line.get("em") or ())
            for k, part in enumerate(line["parts"]):
                d = part.get("direction")
                if d is None:
                    continue
                if not isinstance(d, P.Italic) or BRACKET.search(d) or _bracket_open(line["parts"], k):
                    bracketed += 1
                elif stage_words(d) or len(words(d)) > MAX_WORDS or LABEL_LIKE.search(d):
                    business += 1
                else:
                    plain += 1
        self.emphasis = bracketed >= 10 and business <= 0.1 * (plain + business)

    def is_label(self, inner):
        u = _plain(inner)
        return any(r == u or len(u) >= 2 and r.startswith(u) for r in self.roles) or bool(re.search(r"\b(?:omnes|all|both)\b", inner, re.I))


def why(conv, parts, k):
    """The evidence that part `k` is spoken, or None."""
    d = parts[k]["direction"]
    if not isinstance(d, P.Italic) or BRACKET.search(d) or _bracket_open(parts, k) or _mostly_italic(parts):
        return None
    ws = words(d)
    prev = parts[k - 1]["say"].strip() if k and "say" in parts[k - 1] else ""
    after = parts[k + 1]["say"].strip() if k + 1 < len(parts) and "say" in parts[k + 1] else ""
    if not ws or NOTE_NEAR.search(prev[-40:]) or re.match(r"[\])]", after):
        return None
    if QUOTE_OPENS.search(prev) and QUOTE_CLOSES.match(after) and len(ws) <= MAX_QUOTED and not stage_words(d):
        return "words in quotation marks"
    if len(ws) > MAX_WORDS or not words(prev) and (prev or not after):
        return None  # too long, alone, or between two spans of one direction ("_showily dressed_, _flamboyant_")
    if any(map(_caps, prev.split()[-4:] + after.split()[:2])) and not _caps(d):
        return None
    # "Enter RASNI, _with his_ Kings _and_ Lords _in sackcloth_": inside stage business that is still going on
    for part in reversed(parts[:k]):
        if "say" in part:
            if re.search(r"[.!?]", part["say"]):
                break
        elif ENTERS.match(next(iter(part.values()))):
            return None
    closed, last = _closed(d), (prev.split() or [""])[-1]
    opens = not prev or bool(SENTENCE_END.search(prev)) and not ABBREVIATION.search(prev)
    if LABEL_LIKE.search(d) and not (closed and re.fullmatch(r"[^.\d]+\.", d) and prev and not opens):
        return None
    if opens and prev[-1:] in ("\"", "”"):
        return None  # a play of quoted speeches tells its business in the prose between them
    upper = d.lstrip("\"'“‘—-")[:1].isupper()
    runs_on = bool(re.match(r"[a-zà-ÿ]|I\b", after))
    stopped = bool(re.match(r"[,;:?!.’'\"”…—⸺\-]", after))
    exclaims = d[-1] in "!?"
    if not opens and conv.is_label(d) and not (stopped or runs_on):
        return None
    if closed:
        if opens:
            if upper and (runs_on or re.match(r"[,?!;’'—\-]", after) or exclaims and after):
                return "closed word opens a sentence"
            return "closed word after an exclamation" if not upper and prev and (runs_on or re.match(r"[,?!]", after)) else None
        if runs_on or stopped or exclaims or not after or d.endswith("."):
            return "closed word inside a sentence"
        return "closed word before a name, in a play that brackets its directions" if conv.emphasis else None
    lead = key((words(last) or [""])[-1]) if not re.search(r"[,;:—\-…]$|\.\.$", last) else ""
    if len(ws) == 1 and key(ws[0]) in JOINING and not opens:
        return "joining word inside a sentence" if conv.emphasis and runs_on and not last[:1].isupper() else None
    if stage_words(d):
        if conv.emphasis and not opens and lead in DETERMINER and len(ws) == 1 and (runs_on or stopped) and key(ws[0]) not in STAGE_NOUNS:
            return "a stage word after its article, in a play that brackets its directions"
        return None
    if conv.emphasis and exclaims and upper and not conv.is_label(d):
        return "words that exclaim or ask, in a play that brackets its directions"
    if opens:
        if not upper or not d[-1].isalpha() or conv.is_label(d) and not after.startswith(","):
            return None
        if len(ws) <= 2 and re.match(r", ?[a-z]", after):
            return "a name called, or a word set off, at the head of a sentence"
        if conv.emphasis and len(ws) <= 3 and re.match(r", ?\w|; ?[a-z]", after):
            return "a word set off, in a play that brackets its directions"
        return "a word that opens a sentence going on in lower case" if conv.emphasis and len(ws) <= 2 and runs_on else None
    if not (runs_on or stopped or exclaims and not after):
        if conv.emphasis and lead in DETERMINER and len(ws) <= 2 and not conv.is_label(d) and re.match(r"[A-ZÀ-Þ]", after):
            return "between an article and a name, in a play that brackets its directions"
        return None
    if lead in NEEDS_MORE or ABBREVIATION.search(prev):
        return "what the words before it cannot end without"
    if conv.emphasis and len(ws) <= 3:
        return "inside a sentence, in a play that brackets its directions"
    if len(ws) <= 2 and all(w[0].isupper() for w in ws) and d[-1].isalpha() and re.search(r"[\w'’]$", last):
        return "a name inside a sentence"
    return None


def mend_line(conv, line):
    """The line with its spoken italics said, or the line itself when there are none."""
    parts = line["parts"]
    found = {k for k, p in enumerate(parts) if "direction" in p and why(conv, parts, k)}
    if not found:
        return line
    em_old = set(line.get("em") or ())
    out, em, glue = [], [], False
    for k, p in enumerate(parts):
        if k in found:
            d = p["direction"]
            before = k and "say" in parts[k - 1] and k - 1 not in em_old and d.sides[0] == parts[k - 1]["say"][-1:] \
                and re.search(r"[^\W\d_]['’\-]?$", parts[k - 1]["say"])
            after = k + 1 < len(parts) and "say" in parts[k + 1] and k + 1 not in em_old and d.sides[1] == parts[k + 1]["say"][:1] \
                and re.match(r"['’\-]?[^\W\d_]", parts[k + 1]["say"])
            if before:
                out[-1] = {"say": f"{out[-1]['say']}_{d}_"}
            elif after:
                out.append({"say": f"_{d}_"})
            else:
                out.append({"say": str(d)})
                em.append(len(out) - 1)
            glue = bool(after)
            continue
        if glue:
            out[-1] = {"say": out[-1]["say"] + p["say"]}
        else:
            out.append(p)
            if k in em_old:
                em.append(len(out) - 1)
        glue = False
    new = {k: v for k, v in line.items() if k != "em"}
    new["parts"] = out
    if em:
        new["em"] = em
    return new


def mend(entry):
    """The entry with its spoken italics said, or the entry itself when it has none."""
    if not any(isinstance(p.get("direction"), P.Italic) for l in entry["lines"] if l["kind"] == "speech" for p in l["parts"]):
        return entry
    conv = Convention(entry)
    lines = [mend_line(conv, l) if l["kind"] == "speech" else l for l in entry["lines"]]
    if all(a is b for a, b in zip(lines, entry["lines"])):
        return entry
    return {**entry, "revision": PC._revision(lines), "lines": lines, "roles": PC._roles(lines)}
