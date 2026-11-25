"""Read a stage play whose printed layout script_parse does not know (BACKLOG-LOOP B16, Decision 088.1).

script_parse.parse stays the first reader and is not changed by this one: a play it reads clean keeps every
line id and revision. Only a text it does not read clean comes here, and only a clean result is used.

How it reads (measured 2026-11-24 over the 1,721 rights-cleared Gutenberg texts):

1. A speaker's label is printed one way through a whole play. FAMILIES are the ways: the name alone on a line
   over its speech ("_Arb_." / "Mercadet" / "{Knox}" / "KING."), or opening the line, in capitals, in italics, between
   "=", "+" or braces, in mixed case, ended by a stop, a colon, a dash, a bracketed direction, or (for a name
   the cast list prints) a space. Each family is counted over the text and tried, most labels first.
2. A name is a speaker when it labels three or more lines in that family, or when the family itself is
   unmistakable and the name is printed in the cast list, in an entrance, or is a plain part ("SERVANT",
   "FIRST LORD", "ALL"). Nothing is guessed: what looks like a label and is not accepted is counted (`leaks`)
   and a play with too many is held, because an unread label hands its words to the wrong speaker.
3. A paragraph with no label after a stage direction is the same speaker going on, the printed convention. In a
   text that also prints directions as plain paragraphs ("LARRY stands still again."), such a paragraph is a
   continuation only when its words are plainly spoken; otherwise it is unclassified, and over 5% holds the play.
4. The play's window, the clean test, line ids and parts are script_parse's own (`assemble`); every part is an exact
   slice of the source. A page number, footnote mark or marginal line number is left out between two slices.

The clean gate is never loosened; `refuse` adds tests a first-reader play does not have to pass.
"""
import collections
import re

import script_parse as P

# ---- labels --------------------------------------------------------------------------------------------------
OPEN = {"_": "_", "=": "=", "+": r"\+", "{": r"\}"}
# A stop belongs to a name only after a title or an initial ("Mrs. Roberts", "K. Hen."); any other ends the label.
TITLE = r"(?:[Mm][Rr][Ss]?|[Mm][Ss]|[Dd][Rr]|[Ss][Tt]|[Cc][Aa][Pp][Tt]|[Cc][Oo][Ll]|[Gg][Ee][Nn]|[Ll][Tt]|[Pp][Rr][Oo][Ff]|[Rr][Ee][Vv]|M[Mm][Ee]|M[Ll]{2}[Ee]|Mlle|[A-ZÀ-Þ])\."
WORD = r"(?:%s(?=\s?[A-ZÀ-Þ])|[A-ZÀ-ÞŒ][A-Za-zÀ-ÿœŒ'’]*(?:-[A-Za-zÀ-ÿœŒ'’]+)*)" % TITLE
NUMBER = r"(?:\d{1,2}(?:st|nd|rd|th|d|ST|ND|RD|TH|D)?\.?\s?)"
NAME_MIXED = r"%s?%s(?:(?:\s|-)(?:%s|of|the|and|&|de|la|le|du|van|von|v\.|d'|to|in|with|\d{1,2}(?:st|nd|rd|th)?\.?)){0,5}" % (NUMBER, WORD, WORD)
NAME_MIXED = r"(?:(?:v\.|von|de|van|d')\s)?" + NAME_MIXED
CW = r"(?:%s(?=\s?[A-ZÀ-Þ](?![a-zà-ÿ]))|(?![IAO](?![A-ZÀ-Þ'’]))[A-ZÀ-ÞŒ][A-ZÀ-ÞŒ'’]*(?:-[A-ZÀ-ÞŒ'’]+)*(?![a-zà-ÿ]))" % TITLE
NAME_CAPS = (r"(?:%s|(?:First|Second|Third|Fourth|Fifth|Sixth|1st|2nd|2d|3rd|4th|Old|Young|Little|Sir|Lady|Lord|Mr\.?|Mrs\.?|Miss|Dr\.?|The|A|Mc|Mac|"
             r"St\.?|Capt\.?|Col\.?|M\.|Mme\.?|Mlle\.?|King|Queen|Prince|Princess|Duke)\s?)*%s(?:(?:\s|-)(?:%s|of|the|and|&|de|la|le|du|von|van|\d{1,2})){0,5}" % (NUMBER, CW, CW))
DIR = r"(?:_?\[[^\]\n]*\]_?|_?\([^)\n]*\)_?|_?\[[^\]]*\]_?|_?\([^)]*\)_?)"
# A verse or scene number printed before the label ("II:4:25     KING.", "|210| _Sir quin._").
PREFIX = r"(?:[IVXL]+:\d+:\d+\s+|\|\d+\|\s*|\d{1,4}\s{2,})?"

WRAPPED = {o: re.compile(r"^%s(?P<hon>(?:Mrs?|Sir|Lady|Lord|Dr|Miss|Old|Young|Capt|Don|Dona|Doña|The|First|Second|Third)\.?\s+)?%s(?P<name>%s)(?P<t1>[.:,;]?)(?P<din>\s*[(\[][^)\]]*[)\]])?[.,]?\s*%s"
                         r"(?P<t2>[.:,;]?)(?P<dash>\s?(?:--+|—|–))?(?P<rest>.*)$" % (PREFIX, re.escape(o), NAME_MIXED, c), re.S) for o, c in OPEN.items()}
CAPS = re.compile(r"^%s(?P<name>%s)(?P<t2>[.:;]?:?)(?P<dash>\s?(?:--+|—|–)\s?)?(?P<rest>.*)$" % (PREFIX, NAME_CAPS), re.S)
MIXED = re.compile(r"^%s(?P<name>%s?%s)(?P<t2>[.:;]?:?)(?P<dash>\s?(?:--+|—)\s?)?(?P<rest>.*)$" % (PREFIX, P.HONORIFIC, NAME_MIXED), re.S)
LEAD = re.compile(r"^\s*,?\s*(?P<d>%s)\s*(?P<after>[.:,]?\s?(?:--+|—)?)" % DIR, re.S)

ORDINAL = r"(?:FIRST|SECOND|THIRD|FOURTH|FIFTH|SIXTH|SEVENTH|ANOTHER|OTHER|OLD|YOUNG|LITTLE|1ST|2ND|2D|3RD|3D|4TH|[1-9]\.?|THE|A|AN|SOME|ALL|BOTH|SEVERAL|TWO|THREE|FOUR|MANY)"
PART = (r"(?:ALL|BOTH|OMNES|CHORUS|SEMI-?CHORUS|LEADER|SERVANTS?|MESSENGERS?|SOLDIERS?|OFFICERS?|LORDS?|LADY|LADIES|GENTLEM[AE]N|GENTLEWOM[AE]N|CITIZENS?|MAIDS?|"
        r"PAGES?|NURSE|GUARDS?|CAPTAIN|SAILORS?|PRIESTS?|HERALDS?|VOICES?|CHILD|CHILDREN|CROWD|BOYS?|GIRLS?|MAN|MEN|WOMAN|WOMEN|OLD MAN|KING|QUEEN|"
        r"PRINCE|PRINCESS|DUKE|DUCHESS|COUNT|COUNTESS|BARON|DOCTOR|WAITERS?|PORTERS?|CLERKS?|CONSTABLE|WATCH|WATCHM[AE]N|ATTENDANTS?|"
        r"SHEPHERDS?|PEASANTS?|MONKS?|NUNS?|ABBOT|ABBESS|BISHOP|CARDINAL|JUDGE|GHOST|SPIRITS?|ANGELS?|DEVILS?|FAIRY|FAIRIES|WITCH|WITCHES|MOTHER|FATHER|SON|"
        r"DAUGHTER|WIFE|HUSBAND|BROTHER|SISTER|LANDLORD|LANDLADY|HOST|HOSTESS|COOK|GARDENER|BEGGARS?|THIEF|THIEVES|MERCHANTS?|LAWYER|NOTARY|"
        r"SHERIFF|SERGEANT|CORPORAL|GENERAL|COLONEL|MAJOR|POSTMAN|POLICEM[AE]N|BUTLER|FOOTM[AE]N|VALET|LACKEYS?|SLAVES?|ECHO|PROLOGUE|EPILOGUE|"
        r"REST|OTHERS|GUESTS?|PEOPLE|MOB|STRANGER|PILGRIMS?|FRIAR|FOOL|CLOWN|JESTER|MINSTREL|PLAYERS?|MUSICIANS?|SENATORS?|TRIBUNE|SCHOLARS?|"
        r"STUDENTS?|TEACHER|MASTER|MISTRESS|PRISONER|GAOLER|JAILER|WARDER|EXECUTIONER|PIRATES?|SAVAGES?|INDIANS?|FISHERM[AE]N|HUNTSM[AE]N|HUNTERS?|NEIGHBOU?RS?)")
PLAIN_PART = re.compile(r"^(?:(?:%s\s+)*%s(?:\s+(?:%s|[1-9]|[IVX]+))?|(?:THE\s+)?(?:FIRST|SECOND|THIRD|FOURTH|FIFTH|SIXTH|ANOTHER|1ST|2ND|3RD|2D|3D|4TH))\.?$" % (ORDINAL, PART, PART))
# Words that open a line of prose or verse far more often than they name a speaker.
NEVER = frozenset("""act scene enter exit exeunt manet manent curtain song aside alone solus music pause silence note time place the a an and but
or if so now then there here this that these those what who why how when where which yes no oh ah o i you we he she it they my your his her
our their not nothing well come go good sir madam look see hark hush stop wait never always in on at to of for with from by as is are was were
do did does have has had will would shall should can could may might must let please thank thanks farewell adieu goodbye alas indeed perhaps
very quite ha hm h'm eh pshaw bah hello hullo hallo amen finis end thou thee ye nor yet till ere through while because since unto into upon like such than more most still such old young even contents preface introduction prologue epilogue dedication footnote footnotes
illustration transcriber chapter book volume page appendix index glossary argument persons characters dramatis cast costumes properties
re-enter reenter entrance exits flourish alarum alarums sennet tableau recitative air duet trio quartet finale dance interlude
everybody's both's yours mine ours yes'm""".split())
PUBLISHER = re.compile(r"\b(?:COMPANY|PRESS|PUBLISH\w*|LTD|LIMITED|LIBRARY|EDITIONS?|VOLUMES?|VOL|ILLUSTRATED|POETRY|POEMS|NOVELS?|WORKS|SAME AUTHOR|& CO|AND CO|AUTHOR OF|SPEECH|BROTHERS NEW|"
                       r"COPYRIGHT|PRICE|CENTS|NET|QUER(?:Y|IES)|POINTS?|TOPICS?|HINTS?)\b|^(?:PRINTED|BY)\b")
NOT_NAME = re.compile(r"^(?:PROLOGUE IN|PROLOGUE TO|FIRST PART|SECOND PART|LIST OF|WITH \w+ ILLUSTRATIONS|AS WRITTEN|TRANSCRIBER|LONDON$|NEW YORK$|BOSTON$|CHICAGO$|MELBOURNE$|PHILADELPHIA$|ACT|ACTUS|SCAENA|SCOENA|SCÆNA|SC[EÈ]NE|ACTE|JORNADA|ESCENA|AUFTRITT|AUFZUG|SZENE|AIR|SCENE|SCENA|END|THE END|CURTAIN|FINIS|EXIT|EXEUNT|RE-?ENTER|ENTER|MANET|PROLOGUE TO|SONG|AIR|DUET|TRIO|QUARTETT?E?|FINALE|RECIT(?:ATIVE)?|TABLEAU|"
                      r"COPYRIGHT|CONTENTS|PREFACE|INTRODUCTION|NOTES?|FOOTNOTES?|ILLUSTRATIONS?|CHAPTER|PART|BOOK|VOL(?:UME)?|APPENDIX|INDEX|TIME|PLACE|PERIOD|SYNOPSIS|"
                      r"COSTUMES?|PROPERTIES|SCENERY|CHARACTERS|PERSONS|PERSONAGES|DRAMATIS|CAST|STAGE|MUSIC|DANCE|CHORUS OF\b.*\bSINGING|VERSE|STROPHE|ANTISTROPHE|EPODE|"
                      r"ASIDE|ALOUD|PAUSE|SILENCE|LIGHTS?|SOUND|AT RISE|THE SAME|SETTING|DISCOVERED|LATER|NIGHT|MORNING|EVENING|FIRST ACT|SECOND ACT|THIRD ACT|THE LADY OR)\b"
                      r"|^(?:THE|A|AN|OR|BY|AND|OF|TO|IN|WITH|P|X|II|III|IV|VI|VII|VIII|IX)$", re.I)
CASTHEAD = re.compile(r"^[\W_]*(?:THE\s+)?(?:NAMES? OF (?:THE )?)?(?:CAST|DRAMATIS PERSON(?:AE|Æ|ARUM|NAE|S)|PERSONS?|PERSONAGES|CHARACTERS|ACTORS|THE ACTORS|PLAYERS|SPEAKERS|INTERLOCUTORS|PEOPLE)"
                      r"(?:['’]S?\s+NAMES)?(?:\s+(?:OF|IN|REPRESENTED|REPRESENTING|APPEARING|WHO|AND)\b[^.]{0,50})?[\W_]*$", re.I)


# A heading in capitals that names a place or a number, not a speaker.
PLACE = re.compile(r"^(?:A |AN |THE |IN |AT |ON |BEFORE |NEAR |OUTSIDE |INSIDE )?(?:\w+['’]?S? ){0,3}(?:ROOM|HALL|STREET|GARDEN|HOUSE|FOREST|WOOD|CASTLE|PALACE|CHAMBER|STUDY|"
                   r"CHURCH|PRISON|DUNGEON|CELLAR|KITCHEN|SQUARE|ROAD|FIELD|CAMP|TENT|GATE|NIGHT|DAY|MORNING|EVENING|NOON|INTERLUDE|BALLET|SONG|CHANT|HYMN|DANCE|LINENOTES|"
                   r"DIALOGUE|FOOTNOTE|LETTER|STANZA|[IVXLC]+)\b", re.I)


class Family:
    """One way of printing a speaker: wrap ('', '_', '=', '+', '{'), case ('caps'|'mixed'), own (on its own line)."""

    def __init__(self, wrap, case, own):
        self.wrap, self.case, self.own = wrap, case, own
        self.key = "%s%s_%s" % ({"": "", "_": "italic_", "=": "equals_", "+": "plus_", "{": "brace_"}[wrap], case, "own" if own else "inline")

    def match(self, line):
        """(name, lead direction or None, text, terminator) or None."""
        rx = WRAPPED[self.wrap] if self.wrap else CAPS if self.case == "caps" else MIXED
        m = rx.match(line)
        if not m:
            return None
        name = ((m.groupdict().get("hon") or "") + m.group("name")).strip()
        t = (m.groupdict().get("t1") or "") + (m.group("t2") or "") + ("-" if m.group("dash") else "")
        rest = m.group("rest")
        lead = None
        d = LEAD.match(rest) if not m.group("dash") else re.match(r"^\s*(?P<d>%s)(?P<after>)" % DIR, rest, re.S)
        if d:
            inner = d.group("d").strip("_").strip()[1:-1].strip()
            if not re.fullmatch(r"\W*\d*\W*", inner):
                lead = inner.strip()
                if lead.startswith("_") and lead.endswith("_") and "_" not in lead[1:-1]:
                    lead = lead[1:-1].strip()
                t += "d"
                rest = rest[d.end():]
        text = rest.strip()
        din = m.groupdict().get("din")
        if din and lead is None:
            lead, t = din.strip()[1:-1].strip(), t + "d"
        if self.own:
            return None if text.strip("._:") else (name, lead, "", t)
        if not text:
            # the label and its direction fill the line; the speech is below
            return (name, lead, "", t) if (t and t != ".") or self.wrap else None
        if not self.wrap:
            if not t:
                return (name, lead, text, " ") if rest[:1] == " " else None
            if t in (".", ":", ";") and not re.match(r"\s", rest):
                return None
            if t == ";":
                return None
        elif self.wrap == "_" and not t:
            if not re.match(r"\s+[\"“'‘(\[]?[A-ZÀ-Þ0-9_]", rest):
                return None
            return (name, lead, text, " ")
        return name, lead, text, t


class Space(Family):
    """A name the play lists, then a space ("Aug Oh, Mr. Trenchard"): one word, with a title or an initial."""

    def __init__(self):
        self.wrap, self.case, self.own, self.key = "", "mixed", False, "mixed_space"

    RX = re.compile(r"^(?P<name>(?:(?:Mrs?|Miss|Sir|Lady|Lord|Dr|Capt|Old|First|Second)\.? )?[A-Z][a-z'’]+(?: (?:& [A-Z][a-z]+|[A-Z](?= [A-Z\[(“\"'])))?) (?P<rest>(?P<d>\[[^\]]*\]\s*)?[A-Z“\"'‘0-9].*|\[[^\]]*$)", re.S)

    def match(self, line):
        m = self.RX.match(line)
        if not m:
            return None
        rest, lead = m.group("rest"), None
        d = re.match(r"^\[([^\]]*)\]\s*", rest)
        if d:
            lead, rest = d.group(1).strip("_ "), rest[d.end():]
        return m.group("name").strip(), lead, rest.strip(), "s" if lead is None else "sd"


FAMILIES = [Family(w, c, o) for w, c in (("", "caps"), ("_", "mixed"), ("=", "mixed"), ("+", "mixed"), ("{", "mixed"), ("", "mixed")) for o in (True, False)] + [Space()]


def norm(name):
    return re.sub(r"\s+", " ", name.replace("’", "'").replace("_", "").strip(" .,:;")).upper()


# ---- the text's names ----------------------------------------------------------------------------------------

def cast_names(paras):
    """Words the cast list prints as names (capitalized words that open an entry), upper-cased."""
    out, left = set(), 0
    for p in paras:
        lines = [l.strip() for l in p.split("\n") if l.strip()]
        if CASTHEAD.match(lines[0]) and len(lines[0].split()) <= 8:
            left = 12
            lines = lines[1:]
        elif left:
            left -= 1
            if re.match(r"^[\W_]*(?:ACT|SCENE|PROLOGUE)\b", lines[0], re.I):
                left = 0
        else:
            continue
        for l in lines:
            m = re.match(r"^[\W_]*(?:\d+\.?\s+)?((?:%s\s?){1,4})" % WORD, l)
            if m and len(l) < 120:
                out.update(norm(w) for w in m.group(1).split() if len(w.strip(".,")) > 1)
    return out


def entrance_names(text):
    out = set()
    for m in re.finditer(r"\b(?:Enter|Re-?enter|Exit|Exeunt|Entra)\b([^\n]*)", text):
        out.update(norm(w) for w in re.findall(r"\b[A-ZÀ-Þ][A-Za-zÀ-ÿ'’]{2,}", m.group(1)))
    return out


def lower_words(text):
    return collections.Counter(re.findall(r"(?<![A-Za-z'’])[a-zà-ÿ'’]{2,}", text))


# ---- paragraphs ----------------------------------------------------------------------------------------------

def paragraphs(body):
    return [p for p in (q.strip("\n") for q in re.split(r"\n[ \t]*\n", body)) if p.strip()]


def _bracket_open(p):
    """'[' or '(' when the paragraph opens a bracket its own text never closes."""
    s = p.lstrip(" _")
    if not s or s[0] not in "[(":
        return None
    o, c = s[0], {"[": "]", "(": ")"}[s[0]]
    return o if s.count(o) > s.count(c) else None


SPOKEN = re.compile(r"\b(?:I|I'm|I'll|I've|I'd|I’m|I’ll|I’ve|I’d|me|my|mine|myself|we|us|our|ours|you|your|yours|thou|thee|thy|thine|ye)\b", re.I)
FIRST_SECOND = re.compile(r"(?:\bI\b|\bI['’](?:m|ll|ve|d)\b|\b(?:me|my|mine|myself|we|us|our|you|your|yours|thou|thee|thy|thine|ye)\b)", re.I)
STAGE_OPEN = re.compile(r"^[\W_]*(?:Enter|Re-?enter|Exit|Exeunt|Manet|Flourish|Sennet|Alarums?|Curtain|The curtain|A pause|Pause|Silence|Tableau|Music|Thunder|Trumpets|"
                        r"Knock(?:ing|s)?\b|A knock|Bell|A bell|The bell|Scene|The scene|The same|Same scene|The stage|A (?:short|long|slight|brief|moment)|Lights|"
                        r"The lights|Slow curtain|Quick curtain|After a|There is a (?:knock|pause|silence)|As the curtain|At rise|"
                        r"Discovered|During (?:this|the))\b", re.I)
NARR_VERB = r"(?:is|are|was|comes?|goes|go|enters?|exits?|appears?|sits?|stands?|takes?|turns?|looks?|rises?|runs?|walks?|crosses|falls?|lies|kneels?|gives?|puts?|stops?|opens?|closes|shuts|picks?|throws|lays|laughs?|has|have|begins?|starts?|moves?|shakes?|nods?|bows?|retires?|leaves?|disappears?|returns?|remains?|holds|draws|pauses|drops|reads|sings?|dances?|whispers|smiles|hurries|rushes|advances?|approaches|follows?|wears?|carries)"


# Boilerplate the 1990s etexts print inside the play, act by act.
ETEXT = re.compile(r"WORLD LIBRARY|PROJECT GUTENBERG|ELECTRONIC VERSION|\bETEXT\b|Benedictine College|DISTRIBUTED SO LONG AS|MEMBERSHIP\.?>>", re.I)


class Text:
    def __init__(self, body, support=None):
        self.body = body
        self.paras = paragraphs(body)
        self.cast = cast_names(self.paras)
        self.entr = entrance_names(body)
        # an abbreviation that is also a small word ("OR." for Orestes, "AND." for Andrea), when the cast list gives the name
        self.short = {w for w in ("OR", "AND", "AN", "HER", "HE", "HIS", "IN", "TO", "MY", "NO", "SO", "AS", "AT", "ALE", "SIR")
                      if any(k.startswith(w) and len(k) > len(w) + 1 for k in self.cast | self.entr)
                      and len(re.findall(r"^\s*_?%s\." % w, body, re.M)) >= 5}
        self.low = lower_words(body)
        self.words = len(body.split())

    def supported(self, name):
        n = norm(name)
        words = [w.strip(".") for w in n.split()]
        if PLAIN_PART.match(n):
            return True
        known = self.cast | self.entr
        key = [w for w in words if w not in ("MR", "MRS", "MISS", "SIR", "LADY", "LORD", "THE", "OF", "AND", "DR", "FIRST", "SECOND", "THIRD", "A", "OLD", "YOUNG", "DON", "ST")]
        if not key:
            return False
        for w in key:
            w2 = w.replace("-", "")
            if w in known or w2 in known:
                continue
            if len(w2) >= 2 and any(k.startswith(w2) for k in known):
                continue
            return False
        return True

    def common_word(self, name):
        """A single word that the text prints more often in lower case than it could as a name."""
        w = norm(name).lower()
        return " " not in w and (w in NEVER or self.low[w] >= 3)


GROUP = re.compile(r"^(?:THE (?:TWO|THREE|FOUR|OTHER|OTHERS|REST|CROWD|MEN|WOMEN|WHOLE)|TWO|THREE|FOUR|BOTH|ALL|SEVERAL|SOME|OTHERS?|ANOTHER|FIRST|SECOND|THIRD|VOICES?)\b(?!.*\b(?:ACT|SCENE|PART|EDITION)\b)")


def bad_name(n, t=None):
    u = norm(n)
    if t is not None and u in t.short:
        return False
    if not re.search(r"[A-ZÀ-Þ]{2}", u.replace(" ", "")) and not re.fullmatch(r"[A-Z](?:\.? ?[A-Z])\.?|[A-Z]", u):
        return True
    return bool(NOT_NAME.match(u)) or bool(PUBLISHER.search(u)) or bool(P.ROMAN.match(u)) and len(u) > 3 or bool(re.fullmatch(r"[MDCLXVI]{4,}", u)) or u.endswith("'S") or u.lower() in NEVER or len(u.split()) > 6 or bool(P.ROMAN.match(u.replace(" ", ""))) and len(u) > 1 and u not in ("MIL", "LIL", "VI", "DI", "DIX") \
        or bool(P.HEADING_SPEAKER.match(u)) or len(u) > 44


def survey(t, fam):
    """Counter of names the family labels at paragraph starts, and at line starts inside paragraphs."""
    top, inner, strong, dotted = (collections.Counter() for _ in range(4))
    for p in t.paras:
        lines = p.split("\n")
        for k, l in enumerate(lines):
            s = l.strip()
            if not s or len(s) < 2:
                continue
            m = fam.match(s)
            if not m or bad_name(m[0], t):
                continue
            if fam.own and fam.case == "mixed" and not fam.wrap and len(lines) == 1 and len(t.paras) > 1 and m[0].split()[0] in ("The",) and len(m[0].split()) > 3:
                continue
            (top if k == 0 else inner)[norm(m[0])] += 1
            if m[3] not in (" ", ".", ""):
                strong[norm(m[0])] += 1
            if m[3][:1] == "." and k == 0:
                dotted[norm(m[0])] += 1
    return top, inner, strong, dotted


def speakers(t, fam):
    top, inner, strong, dotted = survey(t, fam)
    total = top + inner
    weak = not fam.wrap and fam.case == "mixed"
    ok = set()
    for n, c in total.items():
        sup = t.supported(n)
        if weak:
            if c >= 3 and (sup or (c >= 5 and not t.common_word(n))):
                if n.lower() in NEVER:
                    continue
                ok.add(n)
            elif sup and strong[n] and not t.common_word(n):
                ok.add(n)
            elif sup and fam.own and not t.common_word(n):
                ok.add(n)
            elif c and PLAIN_PART.match(n) and fam.own:
                ok.add(n)
        elif fam.wrap == "_":
            if (c >= 3 or strong[n] or dotted[n]) and (sup or not t.common_word(n)) and not P._directional(n.lower()):
                ok.add(n)
            elif sup or (dotted[n] or strong[n]) and GROUP.match(n) and not P._directional(n.lower()):
                ok.add(n)
        elif fam.wrap:
            ok.add(n)
        else:  # capitals
            if c >= 2 or sup or (fam.own and len(n.split()) <= 6 and not PLACE.match(n)) or strong[n]:
                ok.add(n)
            elif not fam.own and len(n.split()) <= 3 and len(n) >= 3:
                ok.add(n)
    if not weak and fam.key != "mixed_space" and sum(total.values()) >= 12:
        # someone the print labels only the other way (a part of shared verse lines)
        stop, sinner, sstrong, sdotted = survey(t, Family(fam.wrap, fam.case, not fam.own))
        for n, c in (stop + sinner).items():
            if n not in ok and (c >= 3 and t.supported(n) and (fam.wrap or not t.common_word(n) or PLAIN_PART.match(n)) or c >= 5 and fam.case == "caps") and (sstrong[n] or sdotted[n] >= 0.5 * c or not fam.own):
                ok.add(n)
                total[n] += c
                top[n] += stop[n]
                inner[n] += sinner[n]
    ok |= t.short & set(total)
    if not weak and fam.key != "mixed_space" and sum(total[n] for n in ok) >= 12:
        # a label printed as a label four times is a speaker, however common the word ("_And._" for Andrew, "ACTE.", "_Will._")
        for n, c in rejected(t, fam, ok).items():
            if n not in ("NO", "YES", "OLD", "OH", "AY", "WELL") and (not fam.own or t.supported(n)):
                ok.add(n)
                total[n] = max(total[n], c)
                top[n] = max(top[n], c)
    return ok, total, top, inner


def rejected(t, fam, ok):
    """Labels the family prints four times or more that are not speakers and not headings: a part nobody reads."""
    out = collections.Counter()
    for p in t.paras:
        s = p.split("\n")[0].strip()
        m = fam.match(s)
        if m and m[3] != " " and norm(m[0]) not in ok:
            n = norm(m[0])
            if re.search(r"[A-Z]{2}", n) and not P.HEADING.match(n) and not NOT_LABEL_HEAD.match(n) and len(n.split()) <= 4:
                out[n] += 1
    if not fam.wrap and fam.case == "mixed":
        return {n: c for n, c in out.items() if c >= 4 and (t.supported(n) and not t.common_word(n))}
    return {n: c for n, c in out.items() if c >= 4 and not P._directional(n.lower()) and n.lower() not in ("exit", "exeunt", "enter", "re-enter", "manet")}


NOT_LABEL_HEAD = re.compile(r"^(?:ACT|SCENE|SCÈNE|SCENA|SCOENA|SCÆNA|ACTUS|CURTAIN|SONG|AIR|DUET|TRIO|CHORUS|QUARTET\w*|FINALE|RECIT\w*|MUSIC|DANCE|NOTES?|FOOTNOTES?|END|FINIS|THE END|"
                            r"[IVXLC]+|EXIT|EXEUNT|ENTER|RE-?ENTER|SINGS|DANCES|ASIDE|GLEE|LINENOTES?|PAGE|LINE|P|L|LL|CF|SEE|IBID|STROPHE|ANTISTROPHE|EPODE|REFRAIN|VERSE|CATCH|THE SAME|"
                            r"BALLAD|HYMN|INTERLUDE|PROLOGUE|EPILOGUE|TABLEAU\w*|SYNOPSIS|TIME|PLACE|PERIOD|DIALOGUE|COPYRIGHT|ILLUSTRATION|TRANSCRIBER\W?S? NOTES?|CAST|CHARACTERS|PERSONS|DRAMATIS.*|"
                            r"MR|MRS|THE|A|AN|I|O|STANZA|PART|BOOK|CHAPTER|CONTENTS|.* NOTE)\b")


NOTES_HEAD = P.NOTES_HEAD
DROP = re.compile(r"(?<=\S)\(\d{1,3}\)|\[\s*(?:Pg|Page|p\.)\s*[\dxvil]+\s*\]|\{\d{1,4}\}|\[\d{1,4}\]|\[Footnote[^\]]*\]|\[Sidenote:[^\]]*\]|\[\s*Illustration[^\]]*\]|(?<=\S)[ \t]{3,}\[?\d{1,4}\]?[ \t]*(?=\n|$)")
OPEN_DIR = re.compile(r"\[[^\[\]]*\Z|\[[^\[\]\n]*(?=\n)")
VERSE_MAX = 62


def speech_text(lines):
    """Prose is run together; verse keeps its lines (script_parse does the same per label layout)."""
    ls = [l.strip() for l in lines]
    if len(ls) > 1:
        starts = sum(bool(re.match(r"[\"“'‘(\[_]*[A-ZÀ-Þ]", x)) for x in ls)
        if max(len(x) for x in ls) <= VERSE_MAX and starts >= 0.8 * len(ls):
            return "\n".join(ls)
    return " ".join(ls)


def parts_of(text):
    """Parts of a speech, each an exact slice: script_parse.split_parts over what is left between dropped marks, with a
    bracket the print never closes ("[_Exit_ KYRLE, _through window_, R.") read as the direction it opens."""
    out = []
    pos = 0
    pieces = []
    for m in DROP.finditer(text):
        pieces.append(text[pos:m.start()])
        pos = m.end()
    pieces.append(text[pos:])
    for piece in pieces:
        p = 0
        masked = re.sub(r"\[[^\[\]]*\]", lambda m: "\x00" * len(m.group(0)), piece)
        for m in OPEN_DIR.finditer(masked):
            out += _split(piece[p:m.start()])
            inner = piece[m.start() + 1:m.end()].strip().strip("_").strip()
            if inner:
                out.append({"direction": inner})
            p = m.end()
        out += _split(piece[p:])
    return out


def _split(s):
    if not s.strip():
        return []
    # a bracketed or italic span printed over a line break is one span
    s = re.sub(r"\[[^\]]*\]|\([^)]*\)|(?<![A-Za-z0-9])_[^_]{1,600}?_(?![A-Za-z0-9])", lambda m: m.group(0).replace("\n", " "), s)
    out = P.split_parts(s, italic=True)
    for k, part in enumerate(out):
        d = part.get("direction")
        if d:
            m = re.fullmatch(r"_?[(\[]\s*([^()\[\]]+?)\s*[)\]]_?", d)
            if m:
                d = part["direction"] = m.group(1)
        # "good _Mardonius_, thou know'st": a bare name in italics is the print's way of setting names, and is spoken
        if d and NAME_ONLY.match(d) and not P._directional(d) and ("_" + d + "_" in s or "_" + d in s) and d.strip(".,;:!?").split()[0].lower() not in NEVER:
            out[k] = {"say": d, "_em": True}
    clean = []
    for part in out:
        if "say" in part and re.search(r"[_=+\[\]{}]", part["say"]):
            # a mark the print left unpaired is not a word: the slices on each side of it
            clean += [{"say": x.strip(), **({"_em": True} if part.get("_em") else {})} for x in re.split(r"[_=+\[\]{}]+", part["say"]) if re.search(r"\w", x)]
        else:
            clean.append(part)
    return clean


NAME_ONLY = re.compile(r"^(?:(?:%s|of|the|de|la|and)\s?){1,4}(?:['’]s)?[.,;:!?]*$" % WORD)


def _italic_only(joined, names):
    """Whole paragraph of italics, bar names in capitals or known speakers ("_Enter_ HAMLET _and_ GHOST.")."""
    rest = re.sub(r"_[^_]+_", " ", joined)
    if rest == joined:
        return False
    words = [w for w in re.findall(r"[^\W\d_]+", rest)]
    if not words:
        return True
    # plain words outside the italics must be names; and italics must carry the sentence
    ital = sum(len(x.split()) for x in re.findall(r"_([^_]+)_", joined))
    return ital >= len(words) and all(w.upper() in names or w.upper() == w or w.lower() in ("and", "with", "the", "of", "mr", "mrs", "miss", "r", "l", "c") for w in words)


def _cast_lines(ls):
    """A cast list printed with no heading: every line opens with a name in capitals ("SYNORIX, _an ex-Tetrarch_.")."""
    return len(ls) >= 2 and all(re.match(r"^\W*(?:(?:The|A|An|His|Her|Mrs?\.|Dr\.)\s)?[A-ZÀ-Þ][A-ZÀ-Þ'’.\-]+\b", l.strip()) and len(l.strip()) < 80 for l in ls)


def _names_line(joined, names):
    """"CARLOS and DOMINGO." / "The QUEEN, DARNLEY, MURRAY, the MARIES, &c.": names only."""
    words = re.findall(r"[^\W\d_]+(?:['’][^\W\d_]+)?", joined)
    if not words or len(words) > 40:
        return False
    return all(w.upper() in names or w.lower() in ("and", "the", "with", "mr", "mrs", "miss", "c", "etc", "sir", "lord", "lady", "of", "to", "them", "then", "alone", "solus", "afterwards",
                                                  "both", "two", "three", "four", "others", "servants", "attendants", "soldiers", "officers", "former", "same", "people", "guards") for w in words) \
        and sum(w.upper() in names for w in words) >= 1


def parse_family(raw, title, fam):
    body = P.gutenberg_body(raw)
    t = Text(body)
    return read(raw, t, title, fam)


def read(raw, t, title, fam):
    ok, total, top, inner = speakers(t, fam)
    # the author on the title page is not a speaker
    authors = {norm(x) for x in re.findall(r"^Authors?:[ \t]*(.+)$", raw[:3000], re.M)}
    ok -= authors
    n_lab = sum(total[n] for n in ok)
    if n_lab < P.MIN_SPEECHES or len(ok) < 2:
        return None
    inner_share = sum(inner[n] for n in ok) / n_lab
    weak = not fam.wrap and fam.case == "mixed"
    space_ok = None
    names = {w for n in ok for w in n.split()} | t.cast

    names_ok = {w for n in ok for w in n.split()}
    sibling = None if fam.key == "mixed_space" else Family(fam.wrap, fam.case, not fam.own)
    same_para = sum(1 for p in t.paras if "\n" in p.strip() for m in [fam.match(p.split("\n")[0].strip())] if m and norm(m[0]) in ok)
    tight = same_para >= 0.7 * max(1, sum(top[n] for n in ok))
    if fam.own and fam.case == "caps":
        # a name seen once, alone on a line, unsupported: a heading unless the print sets every speech straight under its label
        for n in [n for n in ok if total[n] == 1 and not t.supported(n)]:
            if not tight or re.search(r"\b(?:AT|IN|ON|NEAR|FROM|WITH|FOR|PART|BY)\b", n) and not re.match(r"(?:A |ONE|VOICES?|SEVERAL|SOME|THE (?:MAN|WOMAN|GIRL|BOY|ONE))", n):
                ok.discard(n)

    def label(s, at_top):
        m = fam.match(s)
        if (not m or norm(m[0]) not in ok) and sibling:
            # the same label printed the other way ("LEAR.      There is no wise man", a verse line two speakers share)
            m = sibling.match(s)
            if m and (norm(m[0]) not in ok or total[norm(m[0])] < 3 or m[3] in (" ", "") and not sibling.own or weak):
                m = None
        if not m and fam.own and fam.case == "caps" and at_top and tight and s.upper() == s and len(s.split()) <= 8:
            # several speakers in one label: "HANS, AXEL, AND OTHERS" over their cry
            ws = [w for w in re.findall(r"[A-ZÀ-Þ'’-]+", s)]
            if len(ws) >= 2 and re.search(r",|\bAND\b", s) and all(w in names_ok or w in ("AND", "OTHERS", "THE", "ALL", "MANY", "REST", "MRS", "MR", "MEN", "WOMEN") for w in ws) and any(w in names_ok for w in ws):
                return (norm(s), None, "", ".")
        if not m:
            return None
        n = norm(m[0])
        if n not in ok:
            return None
        if m[3] == " " and not fam.own:
            # a name ended by a space alone is a label only when the whole text prints it so
            if not space_dominant or not t.supported(n):
                return None
        if not at_top:
            if weak and (inner_share < 0.3 or fam.own and inner_share < 0.15):
                return None
            if fam.own and not weak and inner_share < 0.05 and total[n] < 5 and not m[2]:
                return None
            if fam.wrap == "_" and inner_share < 0.15 and not (total[n] >= 3 and re.search(r"[:\-d]", m[3])):
                return None
        return (n,) + m[1:]

    def label_at(lines, k):
        """The label a line opens with, its direction read to the line its bracket closes on, and the lines that took."""
        s = lines[k].strip()
        m = fam.match(s)
        if m and norm(m[0]) in ok or not m and s[:1] not in "[(":
            o = re.search(r"[\[(]", s[:60])
            if o and s.count(o.group(0)) > s.count({"[": "]", "(": ")"}[o.group(0)]) and s[:o.start()].strip():
                c = {"[": "]", "(": ")"}[o.group(0)]
                for j in range(k + 1, min(len(lines), k + 9)):
                    s += " " + lines[j].strip()
                    if s.count(o.group(0)) <= s.count(c):
                        lead = label(s, k == 0)
                        if lead and lead[1]:
                            return lead, j - k + 1
                        break
        return label(lines[k].strip(), k == 0), 1

    spaces = sum(1 for p in t.paras for m in [fam.match(p.split("\n")[0].strip())] if m and norm(m[0]) in ok and m[3] == " ")
    tops = sum(top[n] for n in ok)
    space_dominant = not fam.own and spaces >= 0.6 * max(1, tops)

    # -- split paragraphs at labels, entrances and bracketed directions that stand on their own lines
    blocks = []  # (lines, label or None, at paragraph start)
    for p in t.paras:
        lines = [l for l in p.split("\n") if l.strip()]
        cur, lab, first = [], None, True
        depth = skip = 0
        for k, l in enumerate(lines):
            s = l.strip()
            if k < skip:
                continue
            m, used = label_at(lines, k) if depth <= 0 else (None, 1)
            if m:
                if cur:
                    blocks.append((cur, lab, first))
                    first = False
                cur, lab, skip = list(lines[k:k + used]), m + (used,), k + used
                if used > 1:
                    continue
            else:
                cur.append(l)
            depth += s.count("[") - s.count("]")
            rest = "\n".join(lines[k + 1:])
            close = rest.find("]")
            if depth < 0 or close < 0 or 0 <= rest.find("[") < close:
                depth = 0
        if cur:
            blocks.append((cur, lab, first))

    # a transcriber's list of changes quotes the play's own labels: the text ends where it begins
    for k in range(int(0.6 * len(blocks)), len(blocks)):
        if not blocks[k][1] and TRANSCRIBER.search(" ".join(blocks[k][0])[:200]):
            notes_from = k
            break
    else:
        notes_from = len(blocks)
    notes_from = min(notes_from, _closing(blocks))
    tail, blocks = blocks[notes_from:], blocks[:notes_from]

    # -- the play's window
    sp = [b[1][0] if b[1] else None for b in blocks]

    often = collections.Counter(x for x in sp if x)

    def run_at(i):
        if not sp[i] or often[sp[i]] < 2:
            return False
        # an own-line label and its speech may be two blocks
        w = [s for s in sp[i:i + 12] if s]
        c = collections.Counter(w)
        return len(w) >= 4 and sum(1 for v in c.values() if v >= 2) >= 1 and len(c) >= 2

    first = next((i for i in range(len(blocks)) if run_at(i)), None)
    if first is None:
        return None

    def mark(i):
        f, n = blocks[i][0][0].strip(), len(blocks[i][0])
        if blocks[i][1]:
            return False
        if CASTHEAD.match(f) and len(f.split()) <= 8 or P.ENTER_LINE.match(f):
            return True
        if re.match(r"^[\[(]?_?SCENE\s*(?:[:.]|[.—–-]{1,2})", f):
            return True
        return n <= 4 and bool(P.section_level(f)) and not re.search(r"\.{3,}|\s\d+$", f)

    start = next((i for i in range(max(0, first - P.START_REACH), first) if mark(i)), first)
    # a cast list that prints its names as labels do, then the first act or scene: the play speaks after that heading
    if any(CASTHEAD.match(blocks[i][0][0].strip()) for i in range(start, min(first + 4, len(blocks)))):
        for k in range(first + 1, min(first + 25, len(blocks))):
            if not blocks[k][1] and len(blocks[k][0]) <= 4 and (P.section_level(blocks[k][0][0].strip()) or re.match(r"^[\[(]?_?SCENE\b", blocks[k][0][0].strip())):
                if sum(1 for x in sp[first:k] if x) <= 25:
                    first = next((i for i in range(k, len(blocks)) if run_at(i)), first)
                break
    counts = collections.Counter(s for s in sp[start:] if s)
    # a cast list whose every name stands alone as a label does ("KING ALFRED." / "DANISH CHIEF." / "GOODWIFE."), and a title over an argument
    def alone(i):
        ls, lab, _ = blocks[i]
        txt = " ".join(x.strip() for x in ls)
        return len(ls) == 1 and (bool(lab) and not lab[2] and not lab[1] or txt.upper() == txt and len(txt.split()) <= 6 and bool(re.search(r"[A-Z]{2}", txt)))
    k = first
    for i in range(first, min(first + 30, len(blocks) - 1)):
        if alone(i) and alone(i + 1) and (blocks[i][1] or blocks[i + 1][1]):
            k = i + 2
        elif blocks[i][1] and alone(i) and re.match(r"^\W*(?:ARGUMENT|CHARACTERS|PERSONS|DRAMATIS|CAST|A (?:PLAY|COMEDY|TRAGEDY|FARCE|DRAMA))\b", blocks[i + 1][0][0].strip(), re.I):
            k = i + 2
    if k != first:
        nxt = next((i for i in range(k, len(blocks)) if run_at(i)), None)
        if nxt is not None and nxt <= k + 25:
            first = nxt
            start = min(start, first)
    # costume or character notes, each opening with a name in the label's own print, before the scene that opens the play
    for k in range(first + 1, min(first + 40, len(blocks))):
        if mark(k) or not blocks[k][1] and re.match(r"^[\W_]*(?:SCENE|ACT|THE SCENE|SCENERY|SETTING|AT RISE|CURTAIN RISES)\b", blocks[k][0][0].strip()):
            said_by = [x for x in sp[first:k] if x]
            if len(said_by) == len(set(said_by)) and len(said_by) >= 1:
                nxt = next((i for i in range(k, len(blocks)) if run_at(i)), None)
                if nxt is not None and nxt <= k + 25:
                    first = nxt
            break
    last = max((i for i in range(start, len(blocks)) if sp[i] and counts[sp[i]] >= 3), default=first)
    end = last + 1
    spoke_below = False
    tail_labels = 0
    while end < len(blocks):
        f = blocks[end][0][0].strip()
        if sp[end]:
            tail_labels += 1
            body = " ".join(x.strip() for x in blocks[end][0][1:]) or blocks[end][1][2] or (" ".join(blocks[end + 1][0]) if end + 1 < len(blocks) else "")
            if tail_labels > 3 or not re.search(r"[a-z]", body) or PRINTED.search(body) or not re.search(r"[.!?—-][\"”'’)\]_]*\s*$", body):
                break
        if P.END_HEAD.match(f):
            end += 1
            break
        if sp[end] is None and (P.SEPARATOR.match(f) or P.BACK_START.search(f) or re.match(r"^[\W_]*(?:NOTES?|FOOTNOTES?|APPENDIX|GLOSSARY|LINENOTES|ADVERTISEMENT)\b", f, re.I)
                                or (f.upper() == f and re.search(r"[A-ZÀ-Þ]{2}", f) and not (fam.own and end == last + 1))):
            break
        end += 1
        if end - last > 8:
            break

    items = [{"kind": "front", "source": "\n".join(x.strip() for x in b[0])} for b in blocks[:start]]
    # the last heading-like mark before the first speech: costume and property notes above it are not the play
    marks = [i for i in range(start, first) if mark(i)]
    lead_from = marks[-1] if marks else start
    incast, casts, pending, spoke, after_head, carry = False, 0, None, False, True, None
    leaks, plain, over = [], 0, False
    opens_at = max([i for i in range(start, first) if not blocks[i][1] and len(" ".join(blocks[i][0])) < 400
                    and TITLE_PAGE.search(" ".join(x.strip() for x in blocks[i][0]))
                    and not re.match(r"^[\W_]*(?:ACT|SCENE|TIME|PLACE)\b", blocks[i][0][0].strip(), re.I)], default=-1)
    # does this text print its directions as plain paragraphs?
    for ls, lab, _ in blocks[start:end]:
        if not lab and _plain_direction(" ".join(x.strip() for x in ls), names):
            plain += 1
    plain_dirs = plain >= 3
    i = start
    while i < end:
        ls, lab, at_top = blocks[i]
        over = over or i > last and bool(re.search(r"\bcurtain\b|\bTHE END\b|\bFINIS\b|\bend of\b", blocks[i - 1][0][-1], re.I))
        src = "\n".join(x.strip() for x in ls)
        f, joined = ls[0].strip(), " ".join(x.strip() for x in ls)
        if i > last and not lab and (over or PRINTED.search(joined) or re.match(r"^\W*(?:PROPERT(?:Y|IES)|PERSONAL PROPS|COSTUME PLOT)\b", joined)):
            over = True
            items.append({"kind": "back", "source": src})
            i += 1
            continue
        if not lab and re.match(r"^\s*\[\d{1,3}\]\s+\S", joined):
            items.append({"kind": "note", "source": src})
            i += 1
            continue
        if i <= opens_at and not lab and not (P.section_level(f) and len(ls) <= 2):
            items.append({"kind": "front", "source": src})
            i += 1
            continue
        if incast and not lab and i < first:
            if not (P.section_level(f) or P.ENTER_LINE.match(f) or re.match(r"^[\[(]?_?SCENE\b", f)):
                items.append({"kind": "cast" if len(joined) < 500 else "front", "source": src})
                i += 1
                continue
        incast = incast and i < first and not lab and False
        if not lab and CASTHEAD.match(f) and len(f.split()) <= 8 and (i <= first or len(ls) <= 2):
            casts += 1
            incast = i < first
            items.append({"kind": "cast", "source": src})
            i += 1
            continue
        if lab and i < first and not run_at(i):
            # a cast list that prints its names as labels do
            items.append({"kind": "cast", "source": src})
            i += 1
            continue
        if lab:
            name, lead, text, _, used = lab
            rest = ls[used:]
            lead_parts = [{"direction": lead}] if lead else []
            body = speech_text(([text] if text else []) + rest) if (text or rest) else ""
            carry = None
            if body.strip():
                items.append({"kind": "speech", "role": name, "source": src, "lead": lead_parts, "_text": body})
                pending, spoke, after_head = None, True, False
            else:
                if pending and items and items[-1].get("_label"):
                    # two labels in a row: the first spoke nothing
                    items[-1]["kind"] = "direction"
                pending = (name, lead_parts, src)
            i += 1
            continue
        if P.ILLUSTRATION_ONLY.fullmatch(src) or re.fullmatch(r"\W*(?:\[\s*(?:Pg|Page)[^\]]*\]|\{\d+\}|\d{1,4})\W*", joined):
            i += 1
            continue
        if joined.startswith("<<") or ETEXT.search(joined):
            items.append({"kind": "note", "source": src})
            i += 1
            continue
        if P.SEPARATOR.match(src):
            items.append({"kind": "heading", "source": src})
            i += 1
            continue
        m = SECTION_LEAD.match(joined) if P.section_level(f) and (len(ls) > 4 or len(joined) >= 200) else None
        if m:
            # "SCENE I.--A farm kitchen ..." running on: the heading, then its description
            items.append({"kind": "heading", "source": m.group(1)})
            items.append({"kind": "direction", "source": joined[m.end():].strip()})
            pending, after_head, carry = None, True, None
            i += 1
            continue
        if len(ls) <= 4 and (P.section_level(f) or (P.HEADING.match(f) and f.upper() == f) or P.LATIN_HEAD.match(f)) and len(joined) < 200:
            items.append({"kind": "heading", "source": src})
            pending, after_head, carry = None, True, None
            i += 1
            continue
        if VARIANT.search(joined) or NOTES_HEAD.match(joined) or P._is_note(joined, "\n".join("\n".join(b[0]) for b in blocks[max(0, i - 120):i])):
            items.append({"kind": "note", "source": src})
            i += 1
            continue
        # a direction whose bracket closes paragraphs later
        o = _bracket_open(joined)
        if o:
            c = {"[": "]", "(": ")"}[o]
            j, acc = i, joined
            while len(joined.split()) > 6 and j + 1 < end and j - i < 8 and acc.count(o) > acc.count(c) and not blocks[j + 1][1]:
                j += 1
                acc += " " + " ".join(x.strip() for x in blocks[j][0])
            if acc.count(o) <= acc.count(c) and j > i and re.search(r"(?<!\d)[\])]_?\.?$", acc.strip()):
                items.append({"kind": "direction", "source": "\n\n".join("\n".join(x.strip() for x in b[0]) for b in blocks[i:j + 1])})
                i = j + 1
                continue
        # a bracketed direction with speech after it in the same paragraph
        m = re.match(r"^_?(\[[^\]]*\]|\([^)]*\))_?[.]?\s*(?P<more>\S.*)$", joined, re.S) if joined[:2].lstrip("_")[:1] in "[(" else None
        if m and pending and re.search(r"[a-z]", m.group("more")):
            items.append({"kind": "speech", "role": pending[0], "source": pending[2] + "\n" + src, "lead": pending[1], "_text": speech_text(ls)})
            pending, spoke, after_head = None, True, False
            i += 1
            continue
        if re.match(r"^_?[\[(]", joined) and (not m or not spoke or after_head):
            items.append({"kind": "direction", "source": src})
            i += 1
            continue
        if pending is None and m and spoke and re.match(r"[A-ZÀ-Þ\"“'‘]", m.group("more")) and not _plain_direction(m.group("more"), names):
            role = next(x["role"] for x in reversed(items) if x["kind"] == "speech")
            items.append({"kind": "speech", "role": role, "source": src, "lead": [], "_text": speech_text(ls)})
            i += 1
            continue
        if re.match(r"^_?[\[(]", joined):
            items.append({"kind": "direction", "source": src})
            i += 1
            continue
        if P.ENTRANCE.match(joined) and not pending or _italic_only(joined, names) or (not pending and (STAGE_OPEN.match(joined) and not FIRST_SECOND.search(joined))):
            items.append({"kind": "direction", "source": src})
            i += 1
            continue
        if pending and re.match(r"^\W*(?:SCENE|PLACE|TIME|PERIOD|SETTING|Scene|Time|Place)\s?[:.—-]", joined):
            # a name over the scene is the last of a cast list, not its speaker
            items.append({"kind": "cast", "source": pending[2]})
            items.append({"kind": "direction", "source": src})
            pending = None
            i += 1
            continue
        if pending:
            items.append({"kind": "speech", "role": pending[0], "source": pending[2] + "\n" + src, "lead": pending[1], "_text": speech_text(ls)})
            pending, spoke, after_head = None, True, False
            i += 1
            continue
        if not spoke or after_head:
            if not spoke and (i < lead_from and len(joined) < 200 or _cast_lines(ls) or re.search(r"\S(?:\s{4,}|\s*\.{4,}\s*)\S", "\n".join(x.strip() for x in ls))):
                items.append({"kind": "cast", "source": src})
            elif _names_line(joined, names) or (joined.upper() == joined and len(joined.split()) <= 14):
                items.append({"kind": "direction", "source": src})
            elif not spoke and i < lead_from:
                items.append({"kind": "front" if len(joined) > 200 else "cast", "source": src})
            elif FIRST_SECOND.search(re.sub(r"[\"“][^\"”]*[\"”]", "", joined)) or len(ls) > 2 and max(len(x.strip()) for x in ls) <= 50:
                items.append({"kind": "other", "source": src})
            else:
                items.append({"kind": "direction", "source": src})
            i += 1
            continue
        if i > last and (over or PRINTED.search(joined) or items and items[-1]["kind"] == "direction"
                         or not re.search(r"[.!?—…-][\"'”’)\]_]*$", joined)):
            items.append({"kind": "back", "source": src})
            over = True
            i += 1
            continue
        # -- an unlabelled paragraph while someone is speaking
        if _names_line(joined, names) and len(joined.split()) > 1 or (joined.upper() == joined and re.search(r"[A-ZÀ-Þ]{3}", joined) and len(joined.split()) <= 14):
            if fam.own and fam.case == "caps" and joined.upper() == joined and not _names_line(joined, names) and len(joined.split()) <= 6 \
                    and not joined.rstrip().endswith(("!", "?")) and not bad_name(joined) and not PLACE.match(joined):
                leaks.append(joined)
            items.append({"kind": "direction", "source": src})
            i += 1
            continue
        if _plain_direction(joined, names):
            items.append({"kind": "direction", "source": src})
            i += 1
            continue
        if items and items[-1]["kind"] == "direction" and _other_voice(items, ok):
            items.append({"kind": "other", "source": src})
            i += 1
            continue
        lk = _looks_like_label(f, fam, t)
        m = WRAPPED_HEAD.match(joined) if fam.wrap == "_" else None
        if not lk and m and len(m.group(1).split()) <= 5 and not P._directional(re.sub(r"^\W+", "", m.group(1).lower())) and not FIRST_SECOND.search(m.group(1)):
            lk = True
        if lk:
            leaks.append(f)
        prev = items[-1] if items else None
        spoken = bool(FIRST_SECOND.search(joined)) or joined.rstrip("\"”'’ )").endswith(("?", "!")) or prev is not None and prev["kind"] == "speech" and not plain_dirs
        if plain_dirs and not spoken and not lk:
            items.append({"kind": "other", "source": src})
            i += 1
            continue
        if prev is not None and prev["kind"] == "speech":
            prev["source"] += "\n\n" + src
            prev["_text"] += "\n" + speech_text(ls)
        else:
            role = next(x["role"] for x in reversed(items) if x["kind"] == "speech")
            items.append({"kind": "speech", "role": role, "source": src, "lead": [], "_text": speech_text(ls), "resumes": True})
        i += 1
    items += [{"kind": "back", "source": "\n".join(x.strip() for x in b[0])} for b in blocks[end:]]
    items += [{"kind": "note", "source": "\n".join(x.strip() for x in b[0])} for b in tail]
    # labels inside speeches that were not read as labels
    for it in items:
        if it["kind"] == "speech":
            it["text"] = it.pop("_text")
            for l in it["text"].split("\n")[1:]:
                if _looks_like_label(l.strip(), fam, t) and not weak:
                    leaks.append(l.strip()[:60])
                else:
                    m = re.match(r"^((?:%s\s?){1,2})[.:]\s+[A-ZÀ-Þ]" % WORD, l.strip())
                    if m and norm(m.group(1)) in ok and norm(m.group(1)) != it["role"]:
                        leaks.append(l.strip()[:60])
            it["parts"] = it["lead"] + parts_of(it["text"])
            if any(re.match(r"^(?!SCENE|TIME|PLACE)[A-ZÀ-Þ][A-ZÀ-Þ'’. ]{2,30}\s?:\s", p.get("say", "")) for p in it["parts"]):
                leaks += ["a label in the words: " + it["text"][:30]] * 3
            tail = re.search(r"[.!?]\s+((?:[A-ZÀ-Þ][A-ZÀ-Þ.'’]+\s?){1,3})\W*$", it["text"])
            if tail and norm(tail.group(1)) in ok:
                leaks.append("ends on a label: " + tail.group(1))
            for part in it["parts"]:
                m = re.match(r"^(?:_)?((?:%s\s?){1,3})(?:[.:]_?\s+[A-ZÀ-Þ\"“]|\s*\()" % WORD, part.get("direction", ""))
                if m and norm(m.group(1)) in ok:
                    leaks.append("in a direction: " + part["direction"][:40])
            if not any("say" in p for p in it["parts"]):
                it["kind"] = "direction"
    said_first = next((it for it in items if it["kind"] == "speech"), None)
    if said_first and title and sum(it["kind"] == "speech" and it["role"] == said_first["role"] for it in items) == 1 and not t.supported(said_first["role"]) \
            and not re.search(r"PROLOGUE|CHORUS|VOICE", said_first["role"]) and len(said_first["role"].split()) == 1 and len(said_first["role"]) > 12:
        said_first["kind"] = "other"  # the play's own long title over its prologue, not a speaker
    _cast_at_the_front(items)
    _names_at_the_end(items)
    _preface(items)
    _same_name(items)
    r = P.assemble(raw, t.body, items, plays_in(blocks), "stage", title)
    if r.get("status") != "parsed":
        return r
    r["layout"] = fam.key
    r["leaks"] = leaks
    r["plain_directions"] = plain
    r["refused"] = refuse(r, items, fam)
    lost = rejected(t, fam, ok)
    if sibling:
        lost = {**rejected(t, sibling, ok), **lost}
    if lost:
        r["refused"].append("recurring_label_unread")
        r["leaks"] = r["leaks"] + [f"{n} ({c})" for n, c in lost.items()]
    if r["refused"]:
        r["clean"] = False
        r["issues"] = r["issues"] + r["refused"]
    return r


SECTION_LEAD = re.compile(r"^([\[(]?_?(?:(?:ACT|SCENE)\s+(?:[IVXLC]+|\d+|[A-Z]+)|(?:THE\s+)?[A-Z]+\s+(?:ACT|SCENE))_?(?:[.:]|(?=\s*(?:--|—))))_?\s*(?:--+|—)?\s*(?=\S)", re.I)
END_NOTES = re.compile(r"^[\W_]*(?:FOOTNOTES?|NOTES?(?: (?:ON|TO|BY|UPON)\b.*)?|ENDNOTES|TEXTUAL NOTES|PROPERTY PLOT.*|PROPERTY LIST|PROPERTIES|PERSONAL PROPS|COSTUME PLOT|LIGHT PLOT|ADVERTISEMENTS?|"
                       r"APPENDIX.*|GLOSSARY|BY THE SAME AUTHOR|PRESS OPINIONS?|OPINIONS OF THE PRESS|EXPLANATORY NOTES|CRITICAL NOTES|MUSIC)[\W_]*$", re.I)
CURTAIN_LINE = re.compile(r"^[\W_]*(?:(?:the\s+)?(?:(?:quick|slow|final|last)\s+)?curtain(?:\s+(?:falls|fall|descends))?|the curtain falls|finis|the end|end of (?:the )?play|\w+ ?curtain)[\W_]*$", re.I)


def _closing(blocks):
    """Where the play closes for good: notes, property plots and notices after the last curtain print the play's labels too."""
    n = len(blocks)
    labels = sum(1 for b in blocks if b[1])
    after = 0
    best = n
    section_after = False
    for k in range(n - 1, int(0.5 * n), -1):
        ls, lab, _ = blocks[k]
        f = ls[0].strip()
        if lab:
            after += 1
            continue
        if P.section_level(f) and len(ls) <= 4:
            section_after = True
        if section_after:
            break
        if END_NOTES.match(f) and len(ls) <= 2 and f.upper() == f:
            best = k
        elif len(ls) <= 2 and CURTAIN_LINE.match(" ".join(x.strip() for x in ls)) and after <= (0.2 if re.search(r"end|finis", f, re.I) else 0.06) * labels:
            best = k + 1
    return best


VOICE_VERB = re.compile(r"\b(?:s[iu]ngs?|singing|song|reads?|reading|speaks?|speaking|says|saying|cr(?:y|ies|ying)|calls?|calling|shouts?|shouting|voices?|chorus|"
                        r"recit\w+|announc\w+|whisper\w*|murmur\w*|exclaim\w*|repl(?:y|ies)|answers?|continues?|heard)\b", re.I)


# An italic head and its stop at the start of a paragraph, whatever words it holds ("_Zeb o' the mill_: ...").
WRAPPED_HEAD = re.compile(r"^_([A-ZÀ-Þ][^_]{1,40}?)[.:]?_(?:[.:]|\s?(?:--|—))\s*[A-ZÀ-Þ“\"‘']")


def _other_voice(items, ok):
    """The direction just before an unlabelled paragraph gives the voice to someone who is not the last speaker."""
    role = next((x["role"] for x in reversed(items) if x["kind"] == "speech"), None)
    d = items[-1]["source"]
    if not VOICE_VERB.search(d):
        return False
    said = {w.upper() for w in re.findall(r"\b[A-ZÀ-Þ][A-Za-zÀ-ÿ'’]+", d)}
    own = set((role or "").replace(".", "").split())
    others = {n for n in ok if n != role and set(n.replace(".", "").split()) & said - own - {"THE", "FIRST", "SECOND", "OLD", "MR", "MRS", "MISS", "SIR", "LADY", "ENTER"}}
    return bool(others) and not (own & said)


LATER_SCENE = re.compile(r"\bSC(?:ENE|ENA|[.])?\s*(?:[2-9]|1\d|II|III|IV|V|VI|VII|VIII|IX|X|2ND|3RD|TWO|THREE|FOUR|FIVE|SIX|SECOND|THIRD|FOURTH|FIFTH)\b", re.I)
PLAY_GAP = 10
SAME_CAST = 0.5


def plays_in(blocks):
    """How many plays the whole text opens, over every block and not only the window: cast lists or first acts with
    PLAY_GAP speeches between them, unless the same people speak on both sides of the mark (a contents page prints
    "ACT I" again, a cast is listed act by act, "ACT I. SCENE II." opens no play)."""
    best = 0
    for is_mark in (lambda f, n: bool(CASTHEAD.match(f)) and len(f.split()) <= 8,
                    lambda f, n: n <= 3 and bool(P.FIRST_ACT.match(f)) and len(f.split()) <= 8 and not LATER_SCENE.search(f)):
        segs, cur = [], None
        for ls, lab, _ in blocks:
            if lab:
                if cur is not None:
                    cur[lab[0]] += 1
            elif is_mark(ls[0].strip(), len(ls)):
                if cur is None or sum(cur.values()) >= PLAY_GAP:
                    cur = collections.Counter()
                    segs.append(cur)
        segs = [c for c in segs if sum(c.values()) >= PLAY_GAP]
        plays, before = 0, set()
        for c in segs:
            who = {r for r, k in c.items() if k >= 2}
            if plays and len(who & before) >= SAME_CAST * max(1, min(len(who), len(before))):
                before |= who
                continue
            plays += 1
            before = who
        best = max(best, plays)
    return best


CASTISH = re.compile(r"^\W*(?:(?:The|A|An|His|Her|Two|Three)\s)?(?:(?:[A-ZÀ-Þ][\w.'’-]*|of|from|the|and|in|to|a|von|de|di|la|v\.)\s?){1,6}(?:,[^.!?]{0,70}|\([^)]*\))?[.,;]?\W*$")


def _cast_at_the_front(items):
    """A cast list, an argument or a title line read as the first speeches of the play ("Herr Ebeling, a lawyer. / Frau von
    Yburg. / Margot, her daughter.") is the cast list."""
    seen = 0
    for it in items:
        if it["kind"] != "speech":
            continue
        seen += 1
        if seen > 6:
            return
        if _not_spoken(it):
            it["kind"] = "cast"
            seen -= 1


FINITE = re.compile(r"\b(?:is|are|was|were|am|be|been|has|have|had|do|does|did|will|would|shall|should|can|could|may|might|must|comes?|came|goes|went|says?|said|knows?|knew|"
                    r"makes?|made|takes?|took|sees?|saw|looks?|let|seems?|thinks?|gets?|got|gives?|gave|\w+n[’']t|[’'](?:s|ll|re|ve|d)\s\w+ing|calls?|keeps?|lies|stands?|brings?|tells?)\b", re.I)


def _names_at_the_end(items):
    """Names in capitals after the last words ("RUTH" / "CLAUS" over a page of music) are not speeches."""
    for it in [x for x in items if x["kind"] == "speech"][:-7:-1]:
        t = it["text"].strip()
        if t.upper() == t and re.search(r"[A-Z]{3}", t) and not re.search(r"[!?.]", t):
            it["kind"] = "back"
        else:
            return


def _not_spoken(it):
    rows = [r.strip() for r in it["text"].split("\n") if r.strip()]
    joined = " ".join(rows)
    if re.match(r"^\W*(?:ARGUMENT\b|Argument\b|A (?:Play|PLAY|Comedy|COMEDY|Tragedy|TRAGEDY|Farce|FARCE|Drama|DRAMA|Masque|MASQUE)\b|IN (?:ONE|TWO|THREE|FOUR|FIVE) ACTS?)", joined):
        return True
    if joined.upper() == joined and re.search(r"[A-Z]{2}", joined) and not re.search(r"[!?]", joined):
        return True
    if re.search(r"\S\s{4,}\S.*\S\s{4,}\S|\S\s*\|\s", it["source"], re.S) and not FIRST_SECOND.search(joined):
        return True
    if re.match(r"^\W*(?:(?:MISS|MRS?\.?|SIR|LADY|LORD|A|AN|THE|HIS|HER)\s)?[A-ZÀ-Þ][A-ZÀ-Þ'’.-]+(?:\s[A-ZÀ-Þ][A-ZÀ-Þ'’.-]+){0,3}\s*(?:[,(]|\.\s)", joined) and not FIRST_SECOND.search(joined):
        return True
    if re.match(r"^[a-z]", joined) and not re.search(r"(?:--|—|\.\.\.)", joined[:12]) and it.get("lead") == []:
        return True
    if not re.search(r"[.!?—…:;-][\"'”’)\]_]*$", joined) and len(rows) >= 2:
        return True
    if len(rows) >= 2 and sum(bool(CASTISH.match(r)) and not r.endswith(("!", "?")) for r in rows) >= 0.8 * len(rows) and not FIRST_SECOND.search(joined):
        return True
    if re.search(r"^\W*(?:TIME|PLACE|PERIOD|SCENE)\s?[:.]|\bFrontispiece\b|\bFacing page\b|\belapses?\b|\bbetween (?:the )?acts\b", joined) or re.match(r"^(?:Mr|Mrs|Miss|Messrs)\.? (?:[A-ZÀ-Þ][\w.'’-]*\s?){1,4}\W*$", joined) and len(rows) == 1:
        return True
    if len(joined.split()) <= 40 and re.match(r"^(?:An?|The|Her|His|Their|Daughter|Son|Wife|Brother|Sister|Friend|Servant|In love)\b[^!?]*$", joined) and not FIRST_SECOND.search(joined) and not FINITE.search(joined):
        return True  # "A Maid of Neilson's" / "An old woman of seventy, brisk, dignified": a character's description
    return len(rows) == 1 and bool(re.match(r"^(?:Old|Young|Dark|Dress|Dressed|Aged|A |An |The |Wears)[^!?]*(?:dress|gown|suit|costume|wears|coat|years|apron|hat|wig)\b", joined))


def _same_name(items):
    """"MR. PRAIS" and "PRAIS" are one speaker when the play prints no other title before that name."""
    count = collections.Counter(it["role"] for it in items if it["kind"] == "speech")
    by = collections.defaultdict(set)
    for r in count:
        m = re.match(r"^(MR|DR|CAPT|COL|THE)\.? (.+)$", r)
        if m:
            by[m.group(2)].add(r)
    ren = {}
    for base, forms in by.items():
        if base in count and len(forms) == 1 and not (PLAIN_PART.match(base) and not next(iter(forms)).startswith("THE ")):
            f = next(iter(forms))
            keep, drop = (f, base) if count[f] >= count[base] else (base, f)
            ren[drop] = keep
    for it in items:
        if it["kind"] == "speech":
            it["role"] = ren.get(it["role"], it["role"])


def _plain_direction(joined, names):
    """A stage direction printed as plain prose: it opens with a name the play prints and a present-tense verb, and speaks to no one."""
    bare = re.sub(r"[\"“][^\"”]*[\"”]|_[^_]*_|\([^)]*\)|\[[^\]]*\]", " ", joined)
    if FIRST_SECOND.search(bare) or "?" in bare:
        return False
    m = re.match(r"^\W*(?:The\s+|Two\s+|Both\s+)?((?:%s)(?:(?:,\s*|\s+and\s+|\s+)(?:the\s+)?(?:%s))*)\s+(?:\w+ly\s+|then\s+|now\s+|also\s+|still\s+|again\s+)?%s\b" % (WORD, WORD, NARR_VERB), bare)
    if m:
        ws = [w.strip(".,").upper() for w in re.findall(WORD, m.group(1))]
        return any(w in names for w in ws) or joined.startswith(("The ", "Both ", "Two "))
    return bool(re.match(r"^\W*(?:He|She|They|All|Both|Everyone|Everybody)\s+(?:\w+ly\s+|then\s+|all\s+)?%s\b" % NARR_VERB, bare)) and not bare.rstrip().endswith("!")


def _looks_like_label(s, fam, t):
    """A line that the family would read as a label, naming someone who is not an accepted speaker."""
    if fam.own:
        m = fam.match(s)
        if not m:
            return False
        if not fam.wrap and fam.case == "mixed":
            return bool(re.fullmatch(r"(?:%s\s?){1,3}[.:]?" % WORD, s)) and not bad_name(m[0]) and not t.common_word(m[0])
        return not bad_name(m[0])
    m = fam.match(s)
    if not m or bad_name(m[0]) or m[3] == " ":
        return False
    if not fam.wrap and fam.case == "mixed":
        # "Servant. My lord ...": a single capitalized word and a stop, not a common sentence opening
        return m[3] != "-" and len(m[0].split()) <= 3 and not t.common_word(m[0]) and (t.supported(m[0]) or m[3] == ":")
    if fam.wrap == "_":
        return t.supported(m[0]) or not t.common_word(m[0]) and m[3] in (".", ":", "-")
    return True


# A line of an editor's variant readings printed among the speeches ("p. 212, ll. 1-6. F] them.").
VARIANT = re.compile(r"^\W*(?:p\.\s*#?\d+#?|ll?\.\s*\d+)[,.]|\b[A-G](?:(?:, ?|--| and )[A-G])*\]\s|\btext reads\b|^\d+(?:[-–]\d+)?[.\]]\s.*\]\s")
# Publisher's lines and stage permissions printed between the cast and the curtain.
TITLE_PAGE = re.compile(r"copyright|all rights|\bpublish|\bpress\b|\bcompany\b|& co\b|macmillan|printed|amateurs?\b|professionals\b|permission|performance of|royalt|^\W*by\W+[A-Z]|author of|"
                        r"\b1[5-9]\d\d\b|new york|chicago|boston|\blondon\W*$|librett|entered according|dedicat|translation of this|\bprice\b|\bMC[MDCLXVI]+\b|same author|copies of this|transcriber", re.I)
PRINTED = re.compile(r"notes on (?:the )?text|\bprice,? \$?\d|\b\d+ cents\b|property plot|imprinted|^=[^=]+=|\bprinted (?:by|in|at)\b|\bpublishers?\b|\bpress\b.*\b(?:london|new york|edinburgh|cambridge|boston)\b|copyright|transcriber|end of (?:the )?(?:project|this)", re.I)
TRANSCRIBER = re.compile(r"transcriber|typographical errors|(?:following|these) (?:is a list of )?(?:corrections|changes|errors|errata)|\bwas changed to\b|” changed to “|\" changed to \"", re.I)
PREFACE = re.compile(r"^[\W_]*(?:(?:AUTHOR|TRANSLATOR|EDITOR|PUBLISHER)['’]?S?\s+)?(?:PREFACE|INTRODUCTION|INTRODUCTORY|FOREWORD|DEDICATION|TO THE READER|ARGUMENT|NOTES?|EPISTLE|APPENDIX|GLOSSARY|"
                     r"VOCABULARY|TRANSCRIBER|FOOTNOTES?|AFTERWORD|COMMENTARY|THE AUTHOR|ADVERTISEMENTS?)\b", re.I)


# A publisher's catalog bound in with the play.
PRICE = re.compile(r"\b(?:Price|Royalty)\b[^\n]{0,40}\d|\$\s?\d|\b\d+\s*(?:cents|cts?\b)|\bnet\b|\b\d+\s?[MF]\.|\d+ (?:males?|females?)|\bm\.,\s*\d+ ?f\.", re.I)


def _preface(items):
    """A preface or notes printed under their own heading with the play are not another play: they are set aside
    as notes (kept with their words, never lines) so that only unexplained set-aside words count against the play."""
    for kind in ("front", "back"):
        on = False
        priced = [it for it in items if it["kind"] == kind and PRICE.search(it["source"])]
        for it in items:
            if it["kind"] != kind:
                continue
            f = it["source"].split("\n")[0].strip()
            if PREFACE.match(f) and len(f.split()) <= 12 or len(priced) >= 3 and it is priced[0]:
                on = True
            if on:
                it["kind"] = "note"


ENGLISH = frozenset("the and of to you is that it in not my your his he me have be with for this".split())
OTHER = frozenset("der und ist nicht ich das ein mit zu que el los las por una para les est pas vous je et dans che il non della di".split())


def not_english(said):
    ws = re.findall(r"[a-zà-ÿ]+", said.lower())
    return bool(ws) and sum(w in ENGLISH for w in ws) < 0.10 * len(ws) and sum(w in OTHER for w in ws) > 0.06 * len(ws) \
        or bool(ws) and sum(w in OTHER for w in ws) > 0.03 * len(ws)


def _two_casts(speech):
    """Two plays read as one: some point where hardly anyone who speaks before it speaks after it."""
    seq = [l["role"] for l in speech]
    n = len(seq)
    count = collections.Counter(seq)
    big = {r for r, c in count.items() if c >= max(3, 0.01 * n)} - {"ALL", "BOTH", "VOICE", "CHORUS", "OMNES", "SERVANT", "MESSENGER"}
    if len(big) < 4 or n < 60:
        return False
    castable = [r for r, c in count.items() if c >= P.CASTABLE_LINES]
    where = collections.defaultdict(list)
    for i, r in enumerate(seq):
        where[r].append(i)
    local = [r for r in castable if where[r][-1] - where[r][0] < 0.2 * n]
    if len(castable) >= 8 and len(local) > 0.7 * len(castable):
        return True  # a reader of many short pieces
    first, last = {}, {}
    for i, r in enumerate(seq):
        first.setdefault(r, i)
        last[r] = i
    for cut in range(int(0.12 * n), int(0.88 * n)):
        a = {r for r in big if first[r] < cut}
        b = {r for r in big if last[r] >= cut}
        if len(a) >= 2 and len(b) >= 2 and not (a & b):
            return True
    return False


def unpaired(parsed):
    """Printed marks left among the spoken words of a first-reader play, more than a stray few."""
    speech = [l for l in parsed["lines"] if l["kind"] == "speech"]
    return sum(bool(re.search(r"[_=+\[\]{}|]", p.get("say", ""))) for l in speech for p in l["parts"]) > max(2, 0.005 * len(speech))


def foreign(parsed):
    return not_english(" ".join(p["say"] for l in parsed["lines"] if l["kind"] == "speech" for p in l["parts"] if "say" in p))


def _lost_words(line):
    """The parts of a speech hold fewer of its printed words than its label and dropped marks explain."""
    words = lambda x: len(re.findall(r"[^\W\d_]{2,}", x))
    src = DROP.sub(" ", line["source"])
    got = sum(words(next(iter(p.values()))) for p in line["parts"])
    return words(src) - got - 2 * words(line["role"]) > max(4, 0.1 * words(src))


def two_casts(parsed):
    return _two_casts([l for l in parsed["lines"] if l["kind"] == "speech"])


def refuse(r, items, fam):
    """Tests a second-reader play must also pass, named when it does not."""
    out = []
    speech = [l for l in r["lines"] if l["kind"] == "speech"]
    if len(r["leaks"]) > max(2, 0.007 * len(speech)):
        out.append("unread_labels")
    said = sum(len(p["say"].split()) for l in speech for p in l["parts"] if "say" in p)
    if not_english(" ".join(p["say"] for l in speech for p in l["parts"] if "say" in p)):
        out.append("not_english")
    if sum(bool(re.match(r"^[A-Z]\.\s+[A-Z“\"']", next((p["say"] for p in l["parts"] if "say" in p), ""))) for l in speech) >= 3:
        out.append("label_cut_short")  # "WID. D. Oh how much": the label is WID. D.
    if _two_casts(speech):
        out.append("two_casts")
    big = [x["name"] for x in r["roles"] if x["lines"] >= P.CASTABLE_LINES]
    if big and len({b[:2] for b in big}) < 2:
        out.append("one_speaker_under_many_names")
    if sum(bool(re.match(r"^[a-z]{2,10}[.:]\s+[A-Z]", x)) for l in speech for p in l["parts"] if "say" in p for x in p["say"].split("\n")[1:]) > 2:
        out.append("labels_in_small_letters")
    inside = sum(len(it["source"].split()) for it in items if it["kind"] not in ("front", "back", "note", "cast"))
    if said < 0.33 * max(1, inside):
        out.append("little_of_it_is_speech")
    said_all = [" ".join(p["say"] for p in l["parts"] if "say" in p) for l in speech]
    told = sum(bool(re.search(r"[\"“”]", x)) and len(re.sub(r"[\"“][^\"”]*[\"”]", "", x).split()) >= 4 and bool(re.match(r"^[\"“]|^[a-z]", x)) for x in said_all)
    if told > 0.25 * len(speech):
        out.append("told_not_spoken")  # a novel set as dialogue: "Yes," he said, and rose
    short = {}
    for l in r["lines"]:
        if l["kind"] == "speech" and _lost_words(l):
            short[l["id"]] = 1
    if len(short) > 0.01 * len(speech):
        out.append("words_lost")
    if sum("|" in p.get("say", "") for l in speech for p in l["parts"]) > 5:
        out.append("printed_in_columns")
    long = [l for l in speech if sum(len(p["say"].split()) for p in l["parts"] if "say" in p) > 600]
    if any(n > 2000 or n > 1000 and not any("\n" in p.get("say", "") for p in l["parts"]) for l in long
           for n in [sum(len(p["say"].split()) for p in l["parts"] if "say" in p)]):
        out.append("speeches_too_long")
    elif len(long) > max(1, 0.02 * len(speech)):
        out.append("speeches_too_long")
    if len(speech) < 15 or said < 300:
        out.append("too_little_is_said")
    notes = Text("\n\n".join(it["source"] for it in items if it["kind"] == "note" and not TRANSCRIBER.search(it["source"][:300]) and "changed" not in it["source"]))
    for f2 in FAMILIES:
        top = survey(notes, f2)[0]
        if sum(1 for c in top.values() if c >= 5) >= 2:
            out.append("speech_in_the_notes")
            break
    ones = sum(1 for x in r["roles"] if x["lines"] == 1)
    if ones > 0.5 * len(r["roles"]) and ones > 6 and len(speech) < 20 * ones:
        out.append("mostly_one_line_roles")
    return out


ORDER_MIN = 20


def parse(raw, title=None):
    """The best reading of a stage text over the layout families, or None. Clean first, then most speeches."""
    t = Text(P.gutenberg_body(raw))
    if t.words < P.MIN_WORDS:
        return None
    scored = []
    for fam in FAMILIES:
        ok, total, _, _ = speakers(t, fam)
        n = sum(total[x] for x in ok)
        if n >= ORDER_MIN:
            scored.append((n * (0.5 if not fam.wrap and fam.case == "mixed" else 1), fam))
    # a text whose labels are in capitals or marked is never read as mixed case: that reading passes over the labels it cannot see
    marked = max((n for n, f in scored if f.wrap or f.case == "caps"), default=0)
    scored = [(n, f) for n, f in scored if f.wrap or f.case == "caps" or 2 * n * 0.6 > marked]
    scored.sort(key=lambda x: -x[0])
    best = None
    for _, fam in scored[:4]:
        r = read(raw, t, title, fam)
        if not r or r.get("status") != "parsed":
            continue
        r["score"] = sum(1 for l in r["lines"] if l["kind"] == "speech")
        if r["clean"] and (best is None or not best["clean"] or r["score"] > 1.5 * best["score"]):
            best = r
        elif best is None or (not best["clean"] and r["score"] > best["score"]):
            best = r
    return best


# ---- a collected volume with a contents list -------------------------------------------------------------------

TITLE_REACH = 400
CONTENTS = re.compile(r"^[\W_]*(?:TABLE OF )?CONTENTS(?: OF [A-Z .]+)?[\W_]*$", re.I)
NOT_A_PLAY_TITLE = re.compile(r"^(?:(?:AUTHOR|EDITOR|PUBLISHER|TRANSLATOR)S? |TRANSLATED|GENERAL INTRO|ACKNOWLEDG|QUESTIONS|LIST OF|FIRST ACT|SECOND ACT|THIRD ACT|ACT I|OR THE$|THE$|BY |OR$|AND$|OF THE$|A TRAGEDY$|"
                              r"A COMEDY$|A PLAY$|TRAGEDY$|COMEDY$|DRAMAS?$|PLAYS?$|HISTORY|GENIUS$|EDITION$|SPANIARDS$|POETRY|ESSAY|LETTER|INTRODUCTION|PREFACE|FOREWORD|NOTES?|APPENDIX|GLOSSARY|INDEX|BIBLIOGRAPHY|ILLUSTRATIONS?|DEDICATION|ACT|SCENE|PAGE|PROLOGUE|EPILOGUE|"
                              r"BIOGRAPH|COSTUMES?|MUSIC|DRAMATIS|CHARACTERS|PERSONS|THE AUTHOR|TO THE|ADVERTISEMENT|ERRATA|CONTENTS|LIFE OF|MEMOIR|PART|VOL|BOOK|CHAPTER|POEMS|SONGS)", re.I)
BYLINE = re.compile(r"^[\W_]*(?:(?:[A-Za-z-]+\s){0,7})?(?:[Bb][Yy]|BY)_?[\s:]+_?(?P<who>(?:[A-ZÀ-Þ][A-Za-zÀ-ÿ'’.\-]*|de|von|van|du|la|of)(?:\s+(?:[A-ZÀ-Þ][A-Za-zÀ-ÿ'’.\-]*|de|von|van|du|la)){1,4})_?[\W_]*$")


def _key(x):
    x = re.sub(r"\[[^\]]*\]", "", x.replace("_", " ").replace("’", "'").replace("=", " "))
    x = re.sub(r"[.\s·•…]*\b(?:[ivxlc]+|\d+)\s*$", "", x.strip())
    x = re.sub(r"^\s*(?:[IVXLC]+|\d+)[.):]\s+", "", x)
    return re.sub(r"[^A-Z0-9 ]", "", re.sub(r"\s+", " ", x.upper().replace("&", "AND").replace("'", ""))).strip()


def contents(paras):
    """(entries in order as {key: printed}, index of the paragraph the list ends at)."""
    for i, p in enumerate(paras[:200]):
        lines = [l.strip() for l in p.split("\n") if l.strip()]
        if not CONTENTS.match(lines[0]):
            continue
        out, j, rows = collections.OrderedDict(), i, lines[1:]
        while j + 1 < len(paras) and j - i < 60:
            for l in rows:
                k = _key(re.sub(r"(?i)^(?:page|pages)$", "", l))
                if 1 <= len(k.split()) <= 12 and len(k) >= 3 and not NOT_A_PLAY_TITLE.match(k) and not l.strip(" _").startswith(("(", "[")) \
                        and k.split()[-1] not in ("THE", "OF", "AND", "OR", "A", "AN", "BY", "IN", "TO"):
                    printed = re.sub(r"[.\s·•…]*\b(?:[ivxlc]+|\d+)\s*$", "", l.replace("_", "").replace("=", "")).strip(" .,;")
                    printed = re.sub(r"^\s*(?:[IVXLC]+|\d+)[.):]\s+", "", printed)
                    out.setdefault(k, printed)
            nxt = [l.strip() for l in paras[j + 1].split("\n") if l.strip()]
            if any(len(l.split()) > 14 for l in nxt) or j > i and len(nxt) == 1 and _key(nxt[0]) in out and len(out) >= 2:
                break
            j += 1
            rows = nxt
            if CASTHEAD.match(nxt[0]) or P.section_level(nxt[0]):
                break
        return out, j
    return {}, 0


POEMS = re.compile(r"\bpo(?:ems?|etry|etical)\b", re.I)


def split_by_contents(raw, poems=False):
    """`poems`: a volume of verse, where only a piece with a cast list, a scene or an entrance is a play.
    [(n, title, byline or None, text)] for a volume whose contents list names plays that are each printed again over their text,
    n counting every listed title found in text order. [] when the list does not divide the volume."""
    paras = paragraphs(P.gutenberg_body(raw))
    entries, end = contents(paras)
    if len(entries) < 2:
        return []
    marks = []
    for i in range(end + 1, len(paras)):
        lines = [l.strip() for l in paras[i].split("\n") if l.strip()]
        if len(lines) > 4 or len(paras[i].split()) > 20:
            continue
        for k in (_key(" ".join(lines)), _key(lines[0])):
            if k in entries:
                if not marks or marks[-1][1] != k:
                    marks.append((i, k))
                break
    # a title printed again inside its own play or at its end is not another play
    seen, cuts = set(), []
    for i, k in marks:
        if k not in seen:
            seen.add(k)
            cuts.append((i, k))
    if len(cuts) < 2:
        return []
    out = []
    for x, (i, k) in enumerate(cuts):
        stop = cuts[x + 1][0] if x + 1 < len(cuts) else len(paras)
        seg = paras[i:stop]
        # the play must follow its title: an act, a scene, a cast list or an entrance within TITLE_REACH words
        words, opens = 0, False
        for p in seg[1:]:
            f = p.split("\n")[0].strip()
            if CASTHEAD.match(f) or P.section_level(f) or P.ENTER_LINE.match(f) or re.match(r"^[\W_]*(?:SCENE|PERSONS|CHARACTERS|TIME|PLACE)\b", f, re.I):
                opens = True
                break
            words += len(p.split())
            if words > TITLE_REACH:
                break
        if not opens and poems:
            continue
        if not opens and words > TITLE_REACH:
            # a short piece may open on its first speech; a preface does not
            if not any(f2.match(p.split("\n")[0].strip()) for p in seg[1:12] for f2 in FAMILIES[:3]):
                continue
        if _another_inside(seg):
            continue
        out.append((x + 1, entries[k], byline(seg), "\n\n".join(seg)))
    return out


def _another_inside(seg):
    """A title in capitals over a cast list or scene, after this play has spoken: a play the contents list did not name."""
    spoken = 0
    for i, p in enumerate(seg):
        f = p.split("\n")[0].strip()
        if re.match(r"^_?[A-Z][A-Za-z .'’]{1,30}_?[.:(\[—-]", f) and len(p.split()) > 3:
            spoken += 1
        f1 = f.strip(" _.=")
        if spoken >= 10 and len(p.split("\n")) <= 2 and 1 < len(f1.split()) <= 9 and f1.upper() == f1 and re.search(r"[A-Z]{3}", f1) and not P.HEADING.match(f1) \
                and not P.END_HEAD.match(f) and not P.section_level(f) and not PLAIN_PART.match(f1):
            for q in seg[i + 1:i + 4]:
                h = q.split("\n")[0].strip()
                if CASTHEAD.match(h) and len(h.split()) <= 8 or re.match(r"^\W*(?:FIRST SCENE|ACT (?:I|1|ONE)\b|SCENE (?:I|1|ONE)\b|TIME:|PLACE:|_?TIME_?\b)", h):
                    return True
    return False


def byline(paras):
    """The author a play prints under its own title, or None."""
    for p in paras[:8]:
        for l in p.split("\n"):
            l = l.strip()
            if len(l) > 90 or re.search(r"(?i)translat|adapted|music|illustrat|edited|copyright|dramatized|arranged|pictures", l):
                continue
            m = BYLINE.match(l)
            if m and len(l.split()) <= 12:
                who = m.group("who").replace("_", "").strip(" .,")
                return " ".join(w if w.lower() in ("de", "von", "van", "du", "la", "of") else w if not w.isupper() or len(w.strip(".")) <= 2 else
                                "-".join(q[:1] + q[1:].lower() for q in w.split("-")) for w in who.split())
        if CASTHEAD.match(p.split("\n")[0].strip()):
            break
    return None
