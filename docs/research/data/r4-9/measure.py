"""R4-9 measurement: planted copies and unrelated scripts against the index of fingerprint.py.

    python3 measure.py <cache dir> <transcripts.json.gz> <index dir> <out.json>

Writes features only (document ids, counts, shares), never a word of a text. Seeded, so a run repeats.
A planted copy is made from a parsed play's speech (catalog/tools/script_parse.py), as an own script's is:
no labels, no headings. A negative is a play already in the index, scored against every document that is
not the same work, author, or series ("leave one work out"), so it stands in for a script nobody has.
"""
import gzip
import json
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "catalog", "tools"))
import fingerprint as F       # noqa: E402
import script_parse as SP     # noqa: E402

CACHE, TRANS, IXD, OUT = sys.argv[1:5]
R = random.Random(20261124)
IX = F.Index(IXD)
PLAYS = {p["id"]: p for p in json.load(open(os.path.join(CACHE, "gutenberg", "plays.json")))["plays"]}
GRW = {g["id"]: g for g in json.load(open(os.path.join(CACHE, "grw", "scripts.json")))["scripts"]}
TRANSCRIPTS = json.load(gzip.open(TRANS))


def path(name):
    d, i = name.split("-", 1)
    return os.path.join(CACHE, {"gut": "gutenberg", "grw": "grw"}[d], "text", i + ".txt")


def parsed(name):
    p = SP.parse(F.read(path(name)), "stage" if name.startswith("gut") else "radio")
    if p.get("status") != "parsed" or not p.get("clean"):
        return None
    say = [" ".join(x["say"] for x in ln["parts"] if "say" in x) for ln in p["lines"] if ln["kind"] == "speech"]
    say = [s for s in say if s.strip()]
    return {"name": name, "lines": say, "roles": [r["name"] for r in p["roles"]], "words": sum(len(s.split()) for s in say)}


# ---- the disguises ------------------------------------------------------------------------------

NEW_NAMES = ["Corwin", "Delphine", "Osric", "Marisol", "Tobias", "Wren", "Anselm", "Ginevra", "Pike", "Lorcan", "Sunniva",
             "Basil", "Ottoline", "Fitch", "Ramona", "Gideon", "Perpetua", "Quill", "Isolde", "Barnaby"]
# Not the normalizer's table: what a person modernizing by hand changes, contractions and words alike.
MODERN = {"thou": "you", "thee": "you", "thy": "your", "thine": "yours", "ye": "you", "hath": "has", "doth": "does",
          "hast": "have", "dost": "do", "art": "are", "wilt": "will", "shalt": "shall", "ere": "before", "nay": "no",
          "aye": "yes", "ay": "yes", "o'er": "over", "ne'er": "never", "e'er": "ever", "'tis": "it's", "'twas": "it was",
          "prithee": "please", "wherefore": "why", "whither": "where", "hither": "here", "thither": "there",
          "methinks": "I think", "perchance": "maybe", "forsooth": "truly", "unto": "to", "upon": "on", "betwixt": "between",
          "oft": "often", "yon": "that", "yonder": "there", "hence": "away", "sirrah": "sir", "mine": "my", "morrow": "morning",
          "saith": "says", "quoth": "said", "albeit": "though", "whilst": "while", "amongst": "among", "naught": "nothing",
          "aught": "anything", "anon": "soon", "alas": "oh no", "fie": "shame", "marry": "well", "behold": "look"}
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


def swap(text, table, rate=1.0):
    n = [0, 0]

    def f(m):
        w = m.group(0)
        n[1] += 1
        t = table.get(w.lower())
        if t is None or R.random() > rate:
            return w
        n[0] += 1
        return t.capitalize() if w[0].isupper() else t
    return re.sub(r"'?[A-Za-z][A-Za-z']*", f, text), n[0] / max(1, n[1])


def rename(src):
    table, i = {}, 0
    for role in src["roles"]:
        for w in re.findall(r"[A-Za-z]{3,}", role):
            table.setdefault(w.lower(), NEW_NAMES[i % len(NEW_NAMES)])
            i += 1
    for w in ("the", "and", "first", "second", "third", "man", "woman", "voice", "lady", "lord", "mrs", "miss"):
        table.pop(w, None)
    return swap("\n".join(src["lines"]), table)


CONF = {"rn": "m", "m": "rn", "l": "1", "e": "c", "h": "b", "o": "0", "u": "n", "n": "u", "t": "f", "i": "l", "a": "o", "s": "5"}


def ocr(text, rate):
    """`rate` of letters misread; half as often a space lost or a word broken at a line end."""
    out = []
    for ch in text:
        r = R.random()
        if ch in CONF and r < rate:
            out.append(CONF[ch])
        elif ch == " " and r < rate / 2:
            out.append("")
        elif ch.isalpha() and r > 1 - rate / 4:
            out.append(ch + "-\n")
        else:
            out.append(ch)
    return "".join(out)


def filler(n):
    """n words with no run of five from anywhere: the words of a play, shuffled."""
    ws = FILL[:]
    R.shuffle(ws)
    return " ".join((ws * (1 + n // len(ws)))[:n])


def window(lines, share, start=None):
    total = sum(len(x.split()) for x in lines)
    i = R.randrange(max(1, int(len(lines) * (1 - share)))) if start is None else start
    out, got = [], 0
    while i < len(lines) and got < total * share:
        out.append(lines[i])
        got += len(lines[i].split())
        i += 1
    return out


def passage(lines, n):
    """About n words from the middle: whole lines, the last cut."""
    i = R.randrange(max(1, len(lines) * 2 // 3))
    ws = " ".join(lines[i:]).split()
    return " ".join(ws[:n]) if len(ws) >= n else " ".join(" ".join(lines).split()[-n:])


def plants(src):
    t = "\n".join(src["lines"])
    yield "verbatim", t, 1
    ex = "\n".join(window(src["lines"], 0.30))
    yield "excerpt_30_in_other_text", ex + "\n" + filler(int(len(ex.split()) * 7 / 3)), None
    yield "one_act_third", "\n".join(window(src["lines"], 1 / 3)), 1
    r, sh = rename(src)
    yield "renamed_characters", r, sh
    yield "ocr_1pct_letters", ocr(t, 0.01), None
    yield "ocr_3pct_letters", ocr(t, 0.03), None
    half = [x for x in src["lines"] if R.random() < 0.5]
    yield "half_the_lines_cut", "\n".join(half), None
    p, sh = swap(t, SYN)
    yield "synonyms_all", p, sh
    p, sh = swap(t, SYN, 0.5)
    yield "synonyms_half", p, sh
    a, _ = swap(t, MODERN)
    b, _ = rename({**src, "lines": a.split("\n")})
    c, sh = swap(b, SYN)
    yield "modern_renamed_synonyms", c, sh
    yield "passage_60_words_in_2000", filler(970) + " " + passage(src["lines"], 60) + " " + filler(970), None
    yield "passage_150_words_in_2000", filler(925) + " " + passage(src["lines"], 150) + " " + filler(925), None


def best(text, exclude=lambda n: False, want=None):
    n, res = IX.match(text, exclude=exclude)
    top = res[0] if res else {"doc": None, "hits": 0, "run": 0, "copied": 0, "covered": 0.0}
    out = {"words": n, "run": max((r["run"] for r in res), default=0), "copied": top["copied"],
           "covered": round(top["covered"], 4), "hits": top["hits"], "doc": top["doc"]}
    if want:
        out["found_source"] = any(r["doc"] == want and r["copied"] for r in res)
    return out


rows = []


def add(group, cls, src, feat, **kw):
    rows.append({"group": group, "class": cls, "src": src, **feat, **kw})


# ---- planted copies -----------------------------------------------------------------------------

names = [n for n in IX.names if n.startswith("gut-") and PLAYS.get(n)]
grws = [n for n in IX.names if n.startswith("grw-")]
R.shuffle(names)
R.shuffle(grws)


def take(pool, n, lo, hi):
    out = []
    for x in pool:
        s = parsed(x)
        if s and lo <= s["words"] <= hi:
            out.append(s)
        if len(out) == n:
            break
    return out


stage = take(names, 20, 2000, 40000)
radio = take(grws, 20, 1500, 12000)
FILL = " ".join(radio[0]["lines"] + stage[0]["lines"]).split()[:8000]
for s in stage + radio:
    for cls, text, share in plants(s):
        add("plant", cls, s["name"], best(text, want=s["name"]), changed=share)

old = [s for s in (parsed(n) for n in names[:400]) if s and 3000 <= s["words"] <= 40000
       and sum(len(re.findall(r"\b(?:thou|thee|thy|hath|doth)\b", x, re.I)) for x in s["lines"]) / s["words"] >= 0.01][:12]
for s in old:
    t, sh = swap("\n".join(s["lines"]), MODERN)
    add("plant", "modernized_spelling", s["name"], best(t, want=s["name"]), changed=sh)

# Real noise: archive.org's automatic transcript of a broadcast whose human script is in the index. The
# transcript itself is in the index too, so it (and every transcript) is left out.
q = json.load(open(os.path.join(CACHE, "transcript_quality.json")))
pairs = sorted(k for k, v in q.items() if v.get("script") and v.get("recall", 0) >= 0.3 and k in TRANSCRIPTS)
R.shuffle(pairs)
for k in pairs[:60]:
    sid = "grw-" + q[k]["script"]
    if sid in IX.names:
        add("plant", "real_transcript_vs_human_script", sid,
            best(TRANSCRIPTS[k]["text"], exclude=lambda n: n.startswith("tr-"), want=sid), changed=round(1 - q[k]["precision"], 3))

# ---- negatives ----------------------------------------------------------------------------------


def surnames(p):
    return {(a.get("name") or "").split(",")[0].lower() for a in (p.get("authors") or []) + (p.get("translators") or [])}


def key(t):
    return SP._title_key(re.split(r"[\n\r:;]", t)[0]) if t else ""


def not_the_same_gut(pid):
    me = PLAYS[pid]
    mine, ti = surnames(me) - {"", "various", "anonymous"}, key(me["title"])

    def ex(n):
        if not n.startswith("gut-"):
            return False
        o = PLAYS.get(n)
        return n == pid or not o or bool(surnames(o) & mine) or key(o["title"]) == ti or not surnames(o) - {"", "various", "anonymous"}
    return ex


def not_the_same_grw(sid):
    g = GRW[sid[4:]]
    tag = re.sub(r"[^a-z0-9]", "", g["series"].lower())

    def ex(n):
        if n.startswith("grw-"):
            o = GRW.get(n[4:])
            return not o or o["series"] == g["series"]
        return n.startswith("tr-") and (n[3:].split("|")[0][:8] == tag[:8] or (g["date"] and g["date"] in n))
    return ex


by_author = {}
for p in PLAYS.values():
    for n in surnames(p):
        by_author[n] = by_author.get(n, 0) + 1
# A new script is not quoted in a hundred books of criticism, so a negative is not by a much-collected author.
quiet = [n for n in names if surnames(PLAYS[n]) - {""} and max(by_author[x] for x in surnames(PLAYS[n])) <= 4]
neg_stage = take(quiet, 50, 1500, 60000)
neg_radio = take(grws[200:], 40, 1000, 12000)
for s in neg_stage:
    ex = not_the_same_gut(s["name"])
    t = "\n".join(s["lines"])
    add("negative", "unrelated_stage", s["name"], best(t, exclude=ex))
    add("negative", "unrelated_stage_800_words", s["name"], best(passage(s["lines"], 800), exclude=ex))
for s in neg_radio:
    add("negative", "unrelated_radio", s["name"], best("\n".join(s["lines"]), exclude=not_the_same_grw(s["name"])))
tk = sorted(k for k in TRANSCRIPTS if TRANSCRIPTS[k].get("text") and len(TRANSCRIPTS[k]["text"]) > 8000)
R.shuffle(tk)
for k in tk[:40]:
    ser, date = k.split("|")[0], k.split("|")[-1]
    add("negative", "unrelated_transcript", "tr-" + k,
        best(TRANSCRIPTS[k]["text"], exclude=lambda n: (n.startswith("tr-") and (n[3:].split("|")[0][:7] == ser[:7] or date in n))
             or (n.startswith("grw-") and (GRW.get(n[4:], {}).get("date") == date
                 or re.sub(r"[^a-z0-9]", "", GRW.get(n[4:], {}).get("series", "").lower())[:7] == ser[:7]))))

# The same story by another hand, and two translations of one play: (a, b), a scored against b alone.
PAIRS = [("other_author_same_story", "gut-811", "gut-14591"), ("other_author_same_story", "gut-811", "gut-3023"),
         ("other_author_same_story", "gut-24556", "gut-14591"), ("other_author_same_story", "gut-35451", "gut-46058"),
         ("other_author_same_story", "gut-5063", "gut-15850"), ("other_author_same_story", "gut-5201", "gut-56126"),
         ("other_author_same_story", "gut-10523", "gut-75270"), ("other_author_same_story", "gut-35837", "gut-76323"),
         ("other_author_same_story", "gut-1534", "gut-3329"), ("other_author_same_story", "gut-7700", "gut-77760"),
         ("other_author_same_story", "gut-1532", "gut-37446"), ("other_author_same_story", "gut-37422", "gut-24556"),
         ("two_translations", "gut-2542", "gut-15492"), ("two_translations", "gut-2467", "gut-8121"),
         ("two_translations", "gut-2027", "gut-28488"), ("two_translations", "gut-1254", "gut-41949"),
         ("two_translations", "gut-3023", "gut-14591"), ("two_translations", "gut-14460", "gut-14591"),
         ("two_translations", "gut-3023", "gut-14460"),
         ("retelling_that_borrows", "gut-37422", "gut-811"), ("retelling_that_borrows", "gut-811", "gut-37422")]
for cls, a, b in PAIRS:
    if a not in IX.names or b not in IX.names:
        continue
    t = F.strip_labels(F.gut_body(F.read(path(a))))
    add("pair", cls, a, best(t, exclude=lambda n: n != b), other=b)

# A radio script that adapts a play the index holds: the same title in both corpora.
gut_by_title = {}
for n in IX.names:
    if n in PLAYS:
        gut_by_title.setdefault(key(PLAYS[n]["title"]), n)
done = set()
for n in grws:
    t = key(GRW[n[4:]]["title"]) if n[4:] in GRW else ""
    if t in gut_by_title and len(t) >= 6 and t not in done:
        s = parsed(n)
        if s and s["words"] >= 1500:
            done.add(t)
            add("pair", "same_title_radio_and_stage", n, best("\n".join(s["lines"]), exclude=lambda x: x != gut_by_title[t]),
                other=gut_by_title[t])

json.dump({"index": {k: IX.meta[k] for k in ("k", "w", "norm", "stats", "seconds")}, "rows": rows}, open(OUT, "w"), indent=0)
print(len(rows), "rows")
