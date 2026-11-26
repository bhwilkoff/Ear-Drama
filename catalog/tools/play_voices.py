"""Which register of stand-in voice suits each part of a play: "high", "low", or nothing (catalog DECISIONS 049, B30).

The owner, 2026-11-26: "for the play along, the voices that are chosen for a given role should match the gender of the
character (i.e, higher voices for the female roles and lower voices for the male roles)." This casts the device voices
only: a person reads any part, and nothing on screen says what a part is. A part is marked only from the play's own print,
and left unmarked when the print says nothing or contradicts itself (precision first: a woman's part read by a man's voice
is worse than a part cast as today):

- the role's own name: a title or a word that names a woman or a man ("MRS. ALVING", "LADY", "KING", "FIRST WITCH",
  "THE KING'S DAUGHTER": the words after the last possessive and before "OF"); a child ("BOY", "GIRL", "CHILD") is high;
- the play's list of persons: the words printed after the role's name ("NORA, his wife", "ROMEO, son to Montague"), the
  first word of its first clause that names one, never a word after a preposition or a possessive ("servant to the
  Countess" is no evidence); a heading over names ("MEN", "Ladies") or a brace beside them ("ILSE ) Children");
- the stage directions, weighed: inside the part's own speech, a direction naming nobody that opens "He"/"She" or says
  "himself"/"herself"; in a direction that names the part before anyone else, "himself"/"herself", "he"/"she", "his"/"her"
  before a word, up to the next person named; "He"/"She" opening the sentence after one that names only the part;
- only when none of those speaks: the actor's title in a first-night cast ("Miss Marion Terry"), unless the play casts a
  woman as a man somewhere; the role's given name in a table derived from the 1990 US Census name frequencies (public
  domain; at least 97% one sex, less every name that is also an English word: "ROSE", "WILL").

A crowd or a pair ("ALL", "BOTH", "VOICES", "PAUL AND LUCY") and a voice alone ("A VOICE") are never marked. When two
kinds of evidence disagree, the part is unmarked.
"""
import json
import os
import re
import unicodedata

HIGH, LOW = "high", "low"
HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = os.path.join(HERE, "..", "plays", "given-name-registers.json")

# Words of a role's own name. Plural forms name a group of one sex, which is evidence too ("WOMEN" sing high).
HIGH_WORDS = frozenset("""
MRS MISS MS MME MADAME MADAM MLLE MADEMOISELLE MESDAMES DAME LADY LADIES QUEEN QUEENS PRINCESS PRINCESSES DUCHESS
COUNTESS BARONESS MARCHIONESS VISCOUNTESS EMPRESS TSARINA CZARINA SULTANA INFANTA ABBESS PRIORESS NUN NUNS
MOTHER MOTHERS GRANDMOTHER GRANNY GRANDMA MAMMA MAMA AUNT AUNTIE SISTER SISTERS DAUGHTER DAUGHTERS NIECE WIFE WIVES
WIDOW WOMAN WOMEN GIRL GIRLS MAID MAIDS MAIDEN MAIDENS MAIDSERVANT HOUSEMAID CHAMBERMAID MILKMAID BARMAID LASS LASSES
WENCH DAMSEL BRIDE BRIDESMAID MISTRESS HOSTESS LANDLADY ACTRESS WAITRESS GOVERNESS SHEPHERDESS GODDESS PRIESTESS
PROPHETESS SORCERESS ENCHANTRESS SEERESS POETESS HEIRESS HEROINE MATRON SPINSTER WITCH WITCHES NYMPH NYMPHS
SIGNORA SIGNORINA DONNA DOÑA SEÑORA SENORA SEÑORITA SENORITA FRAU FRÄULEIN FRAULEIN MÈRE SOEUR
""".split())
LOW_WORDS = frozenset("""
MR MESSRS SIR LORD LORDS KING KINGS PRINCE PRINCES DUKE DUKES EARL COUNT BARON MARQUIS MARQUESS VISCOUNT EMPEROR TSAR
CZAR KAISER SULTAN SHAH PASHA RAJAH MAHARAJAH SHEIK SHEIKH KHAN
FATHER FATHERS GRANDFATHER GRANDPA PAPA UNCLE BROTHER BROTHERS SON SONS NEPHEW HUSBAND WIDOWER MAN MEN GENTLEMAN
GENTLEMEN NOBLEMAN NOBLEMEN KNIGHT KNIGHTS SQUIRE MASTER FELLOW LAD LADS BACHELOR BRIDEGROOM FOOTMAN BUTLER VALET
MANSERVANT WAITER LANDLORD HOST
FRIAR FRIARS MONK MONKS ABBOT ABBÉ ABBE BISHOP ARCHBISHOP CARDINAL POPE PRIEST PRIESTS PARSON VICAR CURATE RECTOR
REVEREND REV DEACON RABBI CHAPLAIN
COLONEL GENERAL MAJOR SERGEANT SERJEANT CORPORAL ADMIRAL
MONSIEUR MESSIEURS HERR SIGNOR SIGNIOR SIGNORE SEÑOR SENOR DON DOM PÈRE FRA
""".split())
CHILD_WORDS = frozenset("BOY BOYS CHILD CHILDREN".split())
# A group or a pair: never one voice of one kind.
GROUP_WORDS = frozenset("""ALL BOTH OMNES SEVERAL OTHERS CROWD PEOPLE MOB EVERYBODY EVERYONE TOGETHER CHORUS VOICES
SOLDIERS SERVANTS ATTENDANTS GUESTS GUARDS CITIZENS PLEBEIANS SENATORS COURTIERS FRIENDS NEIGHBOURS NEIGHBORS
SPIRITS FAIRIES ANGELS DEVILS SAILORS PIRATES CONSPIRATORS LOVERS TWO THREE FOUR""".split())
JOINERS = re.compile(r"\b(?:AND|OR|WITH)\b|&|/")
VOICE_ALONE = re.compile(r"^(?:A |AN |THE |ANOTHER |FIRST |SECOND |THIRD |FOURTH |\d\w* )?(?:\w+ )?VOICE\b(?! OF\b)")

# A word of a list of persons that names the one it follows ("his wife"). Lower case; words after a preposition or a
# possessive name someone else.
DESC_HIGH = frozenset(w.lower() for w in HIGH_WORDS) | {"stepmother", "stepdaughter", "granddaughter", "fiancee",
    "sweetheart", "dressmaker", "milliner", "laundress", "seamstress", "duenna", "lady's-maid", "maid-servant",
    "serving-maid", "serving-woman", "waiting-woman", "waiting-maid", "gentlewoman", "kinswoman", "washerwoman",
    "charwoman", "flower-girl", "schoolgirl", "dona", "senora", "senorita", "fraulein", "mere"}
DESC_LOW = frozenset(w.lower() for w in LOW_WORDS) | {"stepfather", "stepson", "grandson", "suitor", "serving-man",
    "servingman", "kinsman", "schoolboy", "chairman", "clergyman", "fisherman", "huntsman", "boatman", "workman",
    "policeman", "watchman", "coachman", "postman", "countryman", "townsman", "tradesman", "alderman", "yeoman",
    "shepherd", "abbe", "senor", "pere"}
DESC_CHILD = {"boy", "boys", "child", "children", "baby", "infant"}
# Words that may be either in a description, or that name the person served ("master"), or an actor's title.
DESC_SKIP = {"master", "host", "fellow", "general", "major", "don", "count", "mr", "mrs", "miss", "ms", "messrs",
             "madame", "mme", "mlle", "signor", "signora", "herr", "frau"}
PREPS = {"to", "of", "with", "by", "for", "from", "at", "unto", "under", "in", "on", "loves", "loved", "loving", "serving",
         "attending", "and", "than", "like", "as", "whose", "who", "formerly", "former", "or",
         "afterwards", "disguised", "later", "becomes"}
MEN_HEAD = re.compile(r"^\W*(?:MEN|MALES?|GENTLEMEN|MALE (?:CHARACTERS|PARTS|ROLES))\W*$", re.I)
WOMEN_HEAD = re.compile(r"^\W*(?:WOMEN|FEMALES?|LADIES|FEMALE (?:CHARACTERS|PARTS|ROLES))\W*$", re.I)
CASTHEAD = re.compile(r"^\W*(?:THE\s+)?(?:CAST(?: OF CHARACTERS)?|PERSONS|CHARACTERS|DRAMATIS\s+PERSON(?:AE|Æ)|"
                      r"PERSONS OF THE (?:PLAY|DRAMA|COMEDY|TRAGEDY)|PERSONS IN THE PLAY|PERSONS REPRESENTED(?: IN THE PLAY)?|"
                      r"CHARACTERS IN THE PLAY|PERSONAGES|INTERLOCUTORS|NAMES OF THE ACTORS)(?:\s+(?:IN|OF)\s+[^a-z]{1,40})?\W*$", re.I)
CAST_REACH = 90


def fold(s):
    s = (s or "").replace("’", "'").replace("‘", "'")
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()


def head_tokens(name):
    """The words a name is about: after its last possessive ("THE KING'S DAUGHTER" is a daughter), before "OF" ("WIFE OF
    HANS" is a wife), and for "VOICE OF X", X's."""
    up = (name or "").upper().replace("’", "'")
    if "'S " in up:
        up = up.rsplit("'S ", 1)[1]
    words = re.findall(r"[A-ZÀ-ÞÉÈÑ]+", up)
    if words[:1] == ["VOICE"] and "OF" in words:
        return words[words.index("OF") + 1:]
    return words[:words.index("OF")] if "OF" in words[1:] else words


def grouped(name):
    """True for a crowd, a pair, or a voice that is nobody in particular."""
    up = (name or "").upper().replace("’", "'")
    words = re.findall(r"[A-ZÀ-ÞÉÈÑ]+", up)
    if JOINERS.search(up) or any(w in GROUP_WORDS for w in words):
        return True
    return bool(VOICE_ALONE.match(re.sub(r"^\W+", "", up))) and "OF" not in words


def from_name(name):
    """The register the role's own name says, or None."""
    found = set()
    for w in head_tokens(name):
        if w in HIGH_WORDS or w in CHILD_WORDS:
            found.add(HIGH)
        elif w in LOW_WORDS:
            found.add(LOW)
    return found.pop() if len(found) == 1 else None


ACTOR = re.compile(r"(?:\.{2,}|\s{2,}|\||_|^|[,;]\s*)\s*_?(?P<t>Mr|Mrs|Miss|Mme|Madame|Mlle|Mademoiselle|Signor|Signora|"
                   r"Herr|Frau|MR|MRS|MISS)\b\.?_?\s+_?[A-Z]")
CLAUSE_END = re.compile(r"(?<=[a-z]{3})\.(?:\s|$)|;|:|\s{3,}|\.{2,}|\|")


def split_actor(desc):
    """(the description, the actor's title or None): "a Master of a Vessel. | Mr. Freeman." -> (..., "Mr")."""
    m = ACTOR.search(desc or "")
    if not m:
        return desc or "", None
    return desc[:m.start()], m.group("t")


def from_description(desc):
    """The first word of a list of persons' description that names who the role is ("his wife", "Helmer's wife": high).
    The description ends at its first clause; a word after a preposition is someone else ("servant to the Countess")."""
    desc = re.sub(r"^\s+[A-Z][A-Z'\-]+(?:\s+[A-Z][A-Z'\-]+)*(?=\s*[:,.|—])", "", fold(desc or ""))  # "MARY DALLAS: | A country girl"
    desc = CLAUSE_END.split(re.sub(r"^[\s.,:;_\-—–|)}\]]+", "", desc), 1)[0]
    words = re.findall(r"[a-z][a-z'\-]*", desc.lower().replace("’", "'")[:160])
    skip = False
    for w in words:
        if w.endswith("'s") or w.endswith("s'"):
            continue  # "Helmer's wife": the possessor is someone else, the noun after it is the role
        if w in PREPS:
            skip = True
            continue
        if w in ("a", "an", "the", "young", "old", "little", "elder", "younger", "eldest", "youngest", "first", "second"):
            continue
        if skip:
            # the noun after a preposition is someone else's; a phrase may start again after it
            if w in DESC_HIGH or w in DESC_LOW or w in DESC_CHILD:
                skip = False
            continue
        if w in DESC_SKIP:
            continue
        if w in DESC_HIGH or w in DESC_CHILD:
            return HIGH
        if w in DESC_LOW:
            return LOW
    return None


def from_actor(title):
    if not title:
        return None
    return HIGH if title.lower() in ("mrs", "miss", "mme", "madame", "mlle", "mademoiselle", "signora", "frau") else LOW


BRACE = re.compile(r"\s[)}\]]\s*(?P<label>[^)}\]]*)$")


def cast_list(text):
    """The lines of every list of persons in the text, each with what its group says: [(line, register or None)]. A group
    is a brace beside the names ("ILSE ) Children"), or a heading over them ("MEN", "Ladies") in a list that heads both
    (a list printing "WOMEN." among its names has a chorus of women, not a heading)."""
    lines = (text or "").split("\n")
    out = []
    for i, l in enumerate(lines):
        if not CASTHEAD.match(l.strip()):
            continue
        head, block, heads, here = None, [], set(), []

        def close():
            label = next((m.group("label").strip() for _, m in block if m and m.group("label").strip()), "")
            reg = from_description(label) if label and not ACTOR.search(label) else None
            here.extend((s, reg, head) for s, _ in block)
            block.clear()

        for l2 in lines[i + 1:i + 1 + CAST_REACH]:
            s = l2.strip()
            if not s:
                close()
                continue
            if MEN_HEAD.match(s) or WOMEN_HEAD.match(s):
                close()
                head = LOW if MEN_HEAD.match(s) else HIGH
                heads.add(head)
                continue
            if re.match(r"^\W*(?:ACT|SCENE|PROLOGUE|INDUCTION)\b", s, re.I) and s.upper() == s:
                break
            m = BRACE.search(s)
            if block and bool(m) != bool(block[-1][1]):
                close()
            block.append((s, m))
        close()
        out.extend((s, reg or (h if len(heads) == 2 else None)) for s, reg, h in here)
    return out


TITLES = "MRS?|MISS|MS|SIR|LADY|LORD|DR|MME|MLLE|M|DON|DONNA|DONA|MADAME|MONSIEUR|SIGNOR|SIGNORA|FRAU|HERR|CAPTAIN|CAPT|COL|COLONEL"
GIVEN = r"(?:(?!AND\b)[A-Z][A-Z'\-]*\.?\s+){0,2}?"


def _patterns(role):
    """How a list of persons may print the role's name: as labeled, after the role's own title and given names
    ("MRS. HELEN ALVING" for "MRS. ALVING"), or, for a label with no title, after given names and a title ("TORVALD
    HELMER" for "HELMER", "MR. DARCY" for "DARCY")."""
    up = fold(role).upper().strip(" ._")
    words = [w for w in re.findall(r"[A-Z'\-]+", up) if w.strip("'-")]
    if len(" ".join(words)) < 3:
        return []
    titles = [w for w in words if re.fullmatch(TITLES, w)]
    plain = [w for w in words if w not in titles]
    out = [r"(?:(?:THE|A|AN)\s+)?" + r"\.?\s+".join(map(re.escape, words))]
    if titles and plain:
        out.append(r"\.?\s+".join(map(re.escape, titles)) + r"\.?\s+" + GIVEN + r"\s+".join(map(re.escape, plain)))
    elif not titles:
        out.append(r"(?:(?P<title>" + TITLES + r")\.?\s+)?" + GIVEN + r"\s+".join(map(re.escape, plain)))
    return out


def entry_for(role, rows):
    """The list-of-persons row for a role: (row, the words after its name, the title the row adds or None), or (None,
    None, None). A label that is the start of one printed name ("CLER" for "CLERIMONT") finds that row when no other row
    starts so. A label two rows could be ("TJAELDE" beside "HENNING TJAELDE" and "MRS. TJAELDE") finds none."""
    pats = _patterns(role)
    hits = []
    for row in rows:
        flat = fold(row[0]).upper().replace("_", " ").replace("+", " ").replace("’", "'")
        flat = re.sub(r"^\W+", "", flat)
        for v in pats:
            m = re.match(v + r"(?P<end>[A-Z'\-]*)\b(?P<rest>.*)$", flat)
            if m:
                rest = m.group("rest")
                title = m.groupdict().get("title")
                hits.append((bool(m.group("end")), row, row[0][len(row[0]) - len(rest):] if rest else "", title))
                break
    whole = [h for h in hits if not h[0]]
    pick = whole or (hits if len({h[1][0] for h in hits}) == 1 else [])
    if not pick or len({h[1][0] for h in pick}) > 1 and len({from_name(h[3] or "") for h in pick}) > 1:
        return None, None, None
    return pick[0][1], pick[0][2], pick[0][3]


STAGE_WORDS = frozenset("""ENTER ENTERS EXIT EXITS EXEUNT RE REENTER RE-ENTER MANET MANENT OMNES SCENE ACT CURTAIN
I II III IV V R L C U D E LC RC UC DC UR UL DR DL AND THE A AN HE SHE HIS HER HIM THEY IT TO OF IN ON AT
BUT THEN AS WITH FROM ASIDE ALONE TOGETHER SLOWLY QUICKLY END""".split())
# Word edges that ignore the underscores of italics ("_She bows_").
B, E = r"(?<![A-Za-z])", r"(?![A-Za-z])"
PERSON_NOUNS = re.compile(B + r"(?:man|men|woman|women|girl|girls|boy|boys|child|children|lady|ladies|gentleman|gentlemen|"
                          r"maid|servant|servants|wife|husband|mother|father|son|daughter|sister|brother|stranger|someone|"
                          r"somebody|others|another|figure|people|crowd|each other|they|them|their)" + E, re.I)
REFLEXIVE = re.compile(B + r"(himself|herself)" + E, re.I)
SUBJECT = re.compile(B + r"(he|she)" + E + r"(?!['’])", re.I)
NOT_POSSESSED = "to and with in at by from for the a an as that again out up down away off back so all on over into round or " \
                "is was if when while till until then go alone".split()
POSSESSIVE = re.compile(B + r"(his|her)" + E + r"[\s_]+(?!(?:" + "|".join(NOT_POSSESSED) + r")" + E + r")(?-i:[a-z])", re.I)
OPENING = re.compile(r"^[\W_]*(he|she)" + E + r"(?!['’])", re.I)
PRONOUN_BEFORE = re.compile(B + r"(?:he|she|they|his|her|their|himself|herself|him|them)" + E, re.I)
SELF_TALK = re.compile(B + r"to (?:him|her)self" + E, re.I)
OTHER_PRONOUN = {HIGH: re.compile(B + r"(?:him|his|he|himself)" + E, re.I), LOW: re.compile(B + r"(?:her|she|herself)" + E, re.I)}


def _cap_pattern(name):
    words = [w for w in re.findall(r"[A-Za-zÀ-ÿ'’\-]+", name) if w.strip("'’-")]
    if not words:
        return None
    parts = [f"(?:{re.escape(w.upper())}|{re.escape(w.capitalize())})" for w in words]
    return re.compile(r"(?<![A-Za-zÀ-ÿ])" + r"\W{1,3}".join(parts) + r"(?![A-Za-zÀ-ÿ])")


class Names:
    """Every role's name as a direction prints it (in capitals or capitalized), longest first, so "MRS. TJAELDE" is not
    "TJAELDE"; and the other capitalized words a direction holds, which may be someone else."""

    def __init__(self, roles, aliases=None):
        self.aliases = aliases or {}
        names = {}
        for r in roles:
            for a in [r] + list((aliases or {}).get(r, [])):
                p = _cap_pattern(a)
                if p and len(re.sub(r"\W", "", a)) >= 2:
                    names[a] = (r, p)
        self.order = sorted(names.items(), key=lambda kv: -len(kv[0]))
        self.seen = {}

    def find(self, text):
        """[(start, end, role or None)]: the role names in `text`, and the other capitalized words not opening a sentence."""
        if text not in self.seen:
            self.seen[text] = self._find(text)
        return self.seen[text]

    def _find(self, text):
        taken, found = [], []
        for a, (r, p) in self.order:
            for m in p.finditer(text):
                if any(m.start() < e and s < m.end() for s, e in taken):
                    continue
                taken.append((m.start(), m.end()))
                found.append((m.start(), m.end(), r))
        for m in re.finditer(r"(?<![A-Za-zÀ-ÿ'’])([A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]+)", text):
            if any(m.start() < e and s < m.end() for s, e in taken):
                continue
            w = m.group(1).upper().strip("'’-")
            if w in STAGE_WORDS or len(w) < 2:
                continue
            before = text[:m.start()].rstrip(" _*[(")
            if not before or before[-1] in ".!?:;—-\n" or re.search(r"(?:Enter|Exit|Exeunt|Re-enter)\W*$", before):
                continue
            found.append((m.start(), m.end(), None))
        return sorted(found)


def _subject(sentence, role, names):
    """The end of the part's name when the sentence is about the part (its name opens it, after at most a few words that
    are not a phrase of their own, before anyone else and any pronoun, and not as an owner: "Mary's photograph"); else
    None."""
    found = names.find(sentence)
    mine = [f for f in found if f[2] == role]
    if not mine:
        return None
    start, at = mine[0][0], mine[0][1]
    before = sentence[:start]
    if any(f[0] < at and f[2] != role for f in found) or PRONOUN_BEFORE.search(before):
        return None  # someone else is named first, or is the subject: the sentence is about them
    if re.match(r"['’]s\b", sentence[at:at + 3], re.I):
        return None  # "picks up Mary's photograph. He looks at it"
    lead = re.sub(r"(?i)\b(?:enter|enters|re-?enter|then|now|meanwhile|presently|suddenly)\b", "", before)
    words = re.findall(r"[A-Za-z]+", lead)
    if len(words) > 3 or any(w.lower().endswith("ing") or w.lower() in ("without", "after", "before", "to", "at", "with", "behind",
                                                                         "towards", "toward", "upon", "on", "of", "by", "for", "up") for w in words):
        return None  # "Without seeing NORAH, he rings": the part is not the one the sentence is about
    return at


def _votes_in(sentence, role, names):
    """Votes for `role` in one sentence of a direction: [(register, weight)]."""
    at = _subject(sentence, role, names)
    if at is None:
        return []
    found = names.find(sentence)
    rest = sentence[at:]
    later = [f[0] - at for f in found if f[0] >= at and f[2] != role]
    stop = min(later) if later else len(rest)
    pn = PERSON_NOUNS.search(rest)
    stop = min(stop, pn.start()) if pn else stop
    span = rest[:stop]
    out = []
    for rx, w in ((REFLEXIVE, 3), (SUBJECT, 2), (POSSESSIVE, POSSESSIVE_WEIGHT)):
        for m in rx.finditer(span):
            out.append((HIGH if m.group(1).lower() in ("herself", "she", "her") else LOW, w))
    return out


SENTENCE_END = re.compile(r"([.;!?][\"”’'_\])]*)\s+|\s+—\s+|\n\s*\n")


ABBREVIATION = re.compile(r"(?:^|[^A-Za-z])(?:MRS?|MS|DR|ST|MME|MLLE|CAPT|COL|GEN|REV|PROF|LT|SGT|MESSRS|[A-Z])$", re.I)


def sentences(text):
    """The sentences of a direction; "MRS. TJAELDE" is not two."""
    def cut(m):
        if m.group(1) and m.group(1)[0] == "." and ABBREVIATION.search(text[:m.start()]):
            return m.group(0)
        return (m.group(1) or "") + "\0"
    return [x for x in SENTENCE_END.sub(cut, text).split("\0") if x.strip()]


def from_directions(role, lines, names):
    """(high, low) weights from the stage directions. A direction inside the part's own speech that names nobody and opens
    "He" or "She", or says "himself"/"herself", is the speaker's (3); in any direction that names the part before anyone
    else, up to the next person: "himself"/"herself" (3), "he"/"she" (2), "his"/"her" before a word (1); "He"/"She"
    opening the sentence after one that names the part and no one else (2)."""
    hi = lo = 0

    def add(votes):
        nonlocal hi, lo
        for reg, w in votes:
            if reg == HIGH:
                hi += w
            else:
                lo += w

    for l in lines:
        texts = []
        if l["kind"] == "speech":
            for p in l.get("parts", []):
                d = p.get("direction")
                if not d:
                    continue
                if l.get("role") == role and not names.find(d) and not PERSON_NOUNS.search(d):
                    r, o = REFLEXIVE.search(d), OPENING.match(d)
                    m = r or o
                    reg = m and (HIGH if m.group(1).lower() in ("she", "herself") else LOW)
                    # "He comes towards her" inside her speech is someone else coming to the speaker; "She goes." inside
                    # his is the one he spoke to, as often as not
                    if m and not OTHER_PRONOUN[reg].search(d):
                        add([(reg, 3 if r and SELF_TALK.search(d) else 1)])
                        continue
                texts.append(d)
        elif l["kind"] == "direction":
            texts.append(l.get("source") or "")
        for t in texts:
            sents = sentences(t)
            for k, sent in enumerate(sents):
                add(_votes_in(sent, role, names))
                if k and OPENING.match(sent):
                    prev = names.find(sents[k - 1])
                    if prev and all(f[2] == role for f in prev) and _subject(sents[k - 1], role, names) is not None \
                            and not PERSON_NOUNS.search(sents[k - 1]) and not PRONOUN_BEFORE.search(sents[k - 1]):
                        add([(HIGH if OPENING.match(sent).group(1).lower() == "she" else LOW, 2)])
    return hi, lo


MIN_VOTES = int(os.environ.get("MIN_VOTES", 2))
POSSESSIVE_WEIGHT = int(os.environ.get("POSSESSIVE_WEIGHT", 1))


def weigh(hi, lo, least=None):
    """A register when the votes agree (at least `least`, the other side at most a sixth of it), "conflict" when both
    sides are strong, else None."""
    least = least or MIN_VOTES
    if hi >= least and hi >= 6 * lo:
        return HIGH
    if lo >= least and lo >= 6 * hi:
        return LOW
    if hi >= 3 and lo >= 3:
        return "conflict"
    return None


ADDRESS_LOW = "Mr|Mister|Sir|Lord|Monsieur|Herr|Signor|Signior|Señor|Senor|Don|Master|Captain|Colonel|Father|Brother|Uncle"
ADDRESS_HIGH = "Mrs|Missis|Missus|Miss|Lady|Madam|Madame|Mme|Mlle|Mademoiselle|Signora|Señora|Senora|Donna|Doña|Frau|Mistress|" \
               "Mother|Sister|Aunt|Dame"


def from_address(role, entry):
    """(high, low): how often the play calls the role's name with a title ("Mr. Darcy", "Lady Bracknell"), counted only
    when no other role carries that name ("TJAELDE" beside "MRS. TJAELDE" is a family)."""
    words = [w for w in head_tokens(role) if len(w) >= 3 and w not in HIGH_WORDS | LOW_WORDS | CHILD_WORDS
             | {"THE", "AND", "YOUNG", "OLD", "LITTLE", "FIRST", "SECOND", "THIRD"}]
    if not words:
        return 0, 0
    word = words[-1]
    if any(word in re.findall(r"[A-ZÀ-ÞÉÈÑ]+", r["name"].upper()) for r in entry["roles"] if r["name"] != role):
        return 0, 0
    pat = re.compile(B + r"(" + ADDRESS_LOW + "|" + ADDRESS_HIGH + r")\.?\s+(?:[A-Z][a-z]+\s+)?(?:" + re.escape(word)
                     + "|" + re.escape(word.capitalize()) + ")" + E)
    low = re.compile(r"^(?:" + ADDRESS_LOW + r")$")
    given = re.compile(r"(?<![A-Za-z])([A-Z][a-z]{2,})[\s+_]+(?:" + re.escape(word) + "|" + re.escape(word.capitalize()) + ")" + E)
    hi = lo = 0
    firsts = set()
    for l in entry["lines"]:
        text = " ".join(p.get("say") or p.get("direction") or "" for p in l.get("parts", [])) if l["kind"] == "speech" else (l.get("source") or "")
        for m in pat.finditer(text):
            if low.match(m.group(1)):
                lo += 1
            else:
                hi += 1
        firsts.update(g for g in given.findall(text) if not re.fullmatch(ADDRESS_LOW + "|" + ADDRESS_HIGH + "|The|And|To|Of", g))
    # "Sarah Tapp" and "Nathaniel Tapp": a family's name says nothing of one of them
    return (0, 0) if len(firsts) > 1 else (hi, lo)


_names_table = None


def given_names():
    global _names_table
    if _names_table is None:
        with open(NAMES, encoding="utf-8") as f:
            d = json.load(f)
        _names_table = {**{n: HIGH for n in d["high"]}, **{n: LOW for n in d["low"]}}
    return _names_table


def from_given_name(role):
    words = [w for w in re.findall(r"[A-Z]+", fold(role).upper()) if w not in ("THE", "A", "AN", "YOUNG", "OLD", "LITTLE")]
    if not words or len(words) > 3:
        return None
    return given_names().get(words[0])


STRONG = ("name", "list", "list_group", "directions", "address")


def evidence(role, entry, rows, names, actors_trusted=True):
    """What each kind of evidence says of one role: {kind: register} (only kinds that speak)."""
    if grouped(role):
        return {"group": None}
    out = {}
    printed = (names.aliases.get(role) or [role])[0]  # "SERGEANT" for the label "SER"
    n = from_name(role) or from_name(printed.upper())
    if n:
        out["name"] = n
    row, rest, lead = entry_for(role, rows)
    actor = None
    if row:
        if row[1]:
            out["list_group"] = row[1]
        desc, title = split_actor(rest or "")
        said = {x for x in (from_description(desc), from_name(lead or "")) if x}
        if said:
            out["list"] = said.pop() if len(said) == 1 else "conflict"
        actor = from_actor(title)
    w = weigh(*from_directions(role, entry["lines"], names))
    if w:
        out["directions"] = w
    a = weigh(*from_address(role, entry), least=2)
    if a in (HIGH, LOW):  # "Lady Bracknell" 34 times and her absent "Lord Bracknell" 6: a mixed count says nothing
        out["address"] = a
    if not any(k in out for k in STRONG):
        if actor and actors_trusted:
            out["actor"] = actor
        g = from_given_name(role) or from_given_name(printed)
        if g:
            out["given_name"] = g
    return out


def decide(ev):
    if "group" in ev or "conflict" in ev.values():
        return None
    strong = {v for k, v in ev.items() if k in STRONG and v}
    if strong:
        return strong.pop() if len(strong) == 1 else None
    weak = {v for v in ev.values() if v}
    return weak.pop() if len(weak) == 1 else None


def play_text(text):
    import script_parse as P
    return P.gutenberg_body(text) if P.GUT_START.search(text or "") else (text or "")


def aliases(roles, rows):
    """A cut label's printed name ("CLER" for "CLERIMONT"), from the list of persons."""
    out = {}
    for r in roles:
        row, _, _ = entry_for(r, rows)
        if not row:
            continue
        flat = re.sub(r"^\W+", "", row[0].replace("_", " ").replace("+", " "))
        m = re.match(r"([A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]+)", flat)
        if m and len(m.group(1)) > len(r) and m.group(1).upper().startswith(r.upper().strip(". ")):
            out[r] = [m.group(1)]
    return out


def setting(entry, text):
    """What `evidence` needs of one play: (the list-of-persons rows, the names)."""
    rows = cast_list(play_text(text))
    roles = [r["name"] for r in entry["roles"]]
    return rows, Names(roles, aliases(roles, rows))


def evidences(entry, text):
    """{role: evidence} for one play. A play that casts an actress as a man ("ALADDIN ..... Miss Vesta") anywhere, or an
    actor as a woman, lets no actor's title speak."""
    rows, names = setting(entry, text)
    roles = [r["name"] for r in entry["roles"]]
    evs = {r: evidence(r, entry, rows, names) for r in roles}
    for r in roles:
        row, rest, _ = entry_for(r, rows)
        strong = {v for k, v in evs[r].items() if k in STRONG and v}
        title = split_actor(rest or "")[1] if row else None
        if title and len(strong) == 1 and from_actor(title) not in strong:
            return {r: evidence(r, entry, rows, names, actors_trusted=False) for r in roles}
    return evs


def registers(entry, text):
    """{role name: "high" | "low"} for the roles of one play the evidence settles."""
    return {r: reg for r, ev in evidences(entry, text).items() if (reg := decide(ev))}


# Words a census counts as given names that a play prints as something else: Santa Claus is not a woman.
NOT_GIVEN = ("SANTA", "SANTO", "SAN", "SANTOS")


def derive(female, male, words, share=0.97, floor=0.002):
    """The given-name table from the 1990 Census files (name, percent, cumulative, rank) and a word list: a name at least
    `share` one sex by frequency, at least `floor` percent of that sex, and not an English word."""
    def read(path):
        out = {}
        for line in open(path, encoding="ascii"):
            f = line.split()
            if len(f) >= 2:
                out[f[0]] = float(f[1])
        return out
    fem, mal = read(female), read(male)
    common = {w.strip() for w in open(words, encoding="utf-8", errors="ignore") if w.strip() and w.strip().islower()}
    common |= {w.lower() for w in NOT_GIVEN}
    high, low = [], []
    for n in sorted(set(fem) | set(mal)):
        f, m = fem.get(n, 0.0), mal.get(n, 0.0)
        if n.lower() in common or len(n) < 3:
            continue
        if f >= floor and f / (f + m) >= share:
            high.append(n)
        elif m >= floor and m / (f + m) >= share:
            low.append(n)
    return high, low


def annotate(entry, text):
    """The entry with each settled role's `register`. No line, id or revision changes."""
    regs = registers(entry, text)
    roles = [{**{k: v for k, v in r.items() if k != "register"}, **({"register": regs[r["name"]]} if r["name"] in regs else {})}
             for r in entry["roles"]]
    return {**entry, "roles": roles}


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 5 and sys.argv[1] == "derive":
        high, low = derive(*sys.argv[2:5])
        doc = {"source": "US Census Bureau, 1990 Census name files dist.female.first and dist.male.first (public domain, "
                         "https://www2.census.gov/topics/genealogy/1990surnames/)",
               "rule": "a name at least 97% one sex by frequency and at least 0.002% of that sex; less every lower-case word of "
                       "/usr/share/dict/words (an English word: ROSE, WILL), play_voices.NOT_GIVEN (SANTA: Santa Claus) and names under "
                       "three letters",
               "made_by": "python3 catalog/tools/play_voices.py derive dist.female.first dist.male.first /usr/share/dict/words",
               "use": "weak evidence only, when no other evidence speaks (play_voices.from_given_name)",
               "high": high, "low": low}
        with open(NAMES, "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=0, ensure_ascii=False)
            f.write("\n")
        print(len(high), len(low))
