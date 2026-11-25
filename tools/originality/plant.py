"""Planted copies for the self-test: the disguises of R4-9 section 2.3, made from raw text.

A disguise changes words only through tables printed here; seeded, so a run repeats.
"""
import random
import re

NEW_NAMES = ["Corwin", "Delphine", "Osric", "Marisol", "Tobias", "Wren", "Anselm", "Ginevra", "Pike", "Lorcan", "Sunniva",
             "Basil", "Ottoline", "Fitch", "Ramona", "Gideon", "Perpetua", "Quill", "Isolde", "Barnaby"]
# Hand-made synonyms (a person swapping words), about one word in four of ordinary speech.
# Hand-made synonyms (a person swapping words), about one word in four of ordinary speech.
SYN = dict(x.split(":") for x in """good:fine great:grand big:large little:small old:aged young:youthful man:fellow woman:lady
boy:lad girl:lass house:home room:chamber door:doorway night:evening day:afternoon time:moment thing:matter things:matters
people:folks friend:pal friends:pals father:dad mother:mom money:cash work:labor place:spot world:earth life:existence love:adore
hate:despise think:believe know:realize see:notice look:glance come:arrive go:leave went:left take:grab give:hand make:create
made:created say:state said:stated tell:inform told:informed ask:question speak:talk talk:chat hear:catch heard:caught want:wish
need:require like:enjoy help:aid find:locate found:located keep:hold let:allow put:set run:hurry walk:stroll stand:rise
sit:rest eat:dine drink:sip sleep:doze die:perish dead:gone kill:murder fight:battle begin:start stop:quit end:finish
always:forever never:hardly now:presently then:afterward soon:shortly here:nearby there:yonder very:quite much:plenty many:several
more:further well:nicely only:merely just:simply still:yet again:anew perhaps:possibly indeed:truly sure:certain true:real
right:correct wrong:mistaken bad:awful happy:glad sad:blue poor:needy rich:wealthy beautiful:lovely strange:odd afraid:scared
brave:bold dear:darling fool:idiot king:ruler lord:master lady:madam sir:mister child:kid children:kids wife:spouse husband:spouse
son:heir daughter:girl brother:sibling sister:sibling heart:soul head:skull hand:palm hands:palms eye:gaze eyes:gaze face:visage
voice:tone word:term words:terms name:title story:tale letter:note question:query answer:reply reason:cause trouble:bother
fear:dread hope:trust wish:desire mind:brain think:suppose thought:supposed believe:trust feel:sense felt:sensed seem:appear
seems:appears must:should shall:will will:shall can:could may:might cannot:couldn't what:whatever why:how before:until
after:following because:since if:should but:yet and:plus with:alongside without:lacking about:concerning into:inside
over:above under:below between:among every:each all:entire some:certain any:whichever nothing:naught something:anything
way:manner road:path town:village city:metropolis country:nation war:conflict ship:boat sea:ocean water:liquid fire:flame
morning:dawn tonight:later today:now tomorrow:soon year:season years:seasons hour:while minute:second""".split())


CONF = {"rn": "m", "m": "rn", "l": "1", "e": "c", "h": "b", "o": "0", "u": "n", "n": "u", "t": "f", "i": "l", "a": "o", "s": "5"}
COMMON = set("the and but for with that this what when where who why how his her him she they them their there then than "
             "not you your are was were has have had will would could should shall may might can one all any some "
             "act scene first second third man woman lord lady sir mrs miss enter exit exeunt".split())


def swap(text, table, rate, rng):
    def f(m):
        w = m.group(0)
        t = table.get(w.lower())
        if t is None or rng.random() > rate:
            return w
        return t.capitalize() if w[0].isupper() else t
    return re.sub(r"[A-Za-z][A-Za-z']*", f, text)


def rename(text, rng, n=12):
    """The n most said capitalized words that are not common words get new names."""
    count = {}
    for w in re.findall(r"\b[A-Z][a-z]{2,}\b", text):
        if w.lower() not in COMMON:
            count[w] = count.get(w, 0) + 1
    top = sorted(count, key=lambda w: (-count[w], w))[:n]
    table = {w.lower(): NEW_NAMES[i % len(NEW_NAMES)] for i, w in enumerate(top)}
    return swap(text, table, 1.0, rng)


def synonyms(text, rng, rate=1.0):
    return swap(text, SYN, rate, rng)


def ocr(text, rate, rng):
    """`rate` of letters misread; half as often a space lost or a word broken at a line end."""
    out = []
    for ch in text:
        r = rng.random()
        if ch in CONF and r < rate:
            out.append(CONF[ch])
        elif ch == " " and r < rate / 2:
            out.append("")
        elif ch.isalpha() and r > 1 - rate / 4:
            out.append(ch + "-\n")
        else:
            out.append(ch)
    return "".join(out)


def window(text, share, rng):
    """About `share` of the words, as whole lines in a row."""
    lines = text.split("\n")
    total = sum(len(x.split()) for x in lines)
    i = rng.randrange(max(1, int(len(lines) * (1 - share))))
    out, got = [], 0
    while i < len(lines) and got < total * share:
        out.append(lines[i])
        got += len(lines[i].split())
        i += 1
    return "\n".join(out)


def shuffled(text, rng, n=None):
    ws = text.split()
    rng.shuffle(ws)
    return " ".join(ws[:n] if n else ws)


def passage_in_filler(text, filler_words, rng, inside=2000, run=150):
    ws = text.split()
    i = rng.randrange(max(1, len(ws) * 2 // 3))
    p = " ".join(ws[i:i + run])
    fill = filler_words[:]
    rng.shuffle(fill)
    half = (inside - run) // 2
    return " ".join(fill[:half]) + " " + p + " " + " ".join(fill[half:2 * half])


def plants(text, filler_text, seed):
    """(class, text) of each disguise of one play; filler_text is another play's words, for the passage."""
    rng = random.Random(seed)
    yield "verbatim", text
    yield "renamed_characters", rename(text, rng)
    yield "ocr_3pct_letters", ocr(text, 0.03, rng)
    yield "synonyms_all", synonyms(text, rng)
    yield "one_act_third", window(text, 1 / 3, rng)
    yield "passage_150_words_in_2000", passage_in_filler(text, filler_text.split(), rng)
