"""Mend the roles of a play already judged clean (catalog DECISIONS 044, BACKLOG-LOOP B16c).

Both readers decide whether a text is a play and which speaker said what; this pass runs after them, on a play that
is kept, over the items in text order. It finds what was read as a speaker and is not one, and puts the words back
where the print has them. It never moves an id, never invents a role, and never drops a word of a speech:

- a heading, a place, a time or a stage direction read as a speaker is a direction, its words kept;
- a title page, cast list, note, notice or publisher's list read as speech is set aside (`gone`: its id stays used);
- a word that opens a sentence ("Certainly. I must ...") read as a speaker goes back, with its words, to the speaker
  whose label stands over it in the text, or whose speech it broke;
- a speaker cut at a title or a particle ("MRS" over "BANGER. Thank you"), misprinted once, or joined to its first
  words ("BOHUN. I--") is the speaker the print names;
- a speech printed as "_2 Merch._ Sir, we saw 'em not." and read as a direction is that speaker's, as the print says;
- a labeled speech folded into the speech above it is a line of its own (`split`: the id above plus a letter).

What no rule here can settle is left as it was; plays/known-faults.json lists it, and an unpublished play is held
(build_play_library.READ_AND_HELD). Every rule was written against a play that showed the fault (tests/test_play_roles.py).
"""
import collections
import re

import script_parse as P

CASTABLE = P.CASTABLE_LINES


def refine(items, text, title=None, raw=""):
    r = Refiner(items, text, title, raw)
    for step in (r.boilerplate, r.notes, r.label_ends, r.tail, r.front, r.labels_in_directions, r.labels_in_lines, r.folded, r.capitals_in_lines, r.one_number_one_name, r.words_read_as_speakers,
                 r.cut_labels, r.songs, r.headings, r.italic_verse, r.short_names, r.misprints):
        step()
        r.count()
    return r.items


def squash(s):
    return re.sub(r"\s+", " ", s).strip()


class Refiner:
    def __init__(self, items, text, title, raw=""):
        self.items, self.title = items, title
        m = re.search(r"^Title:[ \t]*(.+)$", raw, re.M)
        self.title_key = P._title_key(m.group(1) if m else title or "")
        self.authors = {P._role(x) for x in re.findall(r"^Authors?:[ \t]*(.+)$", raw[:3000], re.M)}
        self.text = text
        self.second = any("parts" in it for it in items)
        self.count()

    # -- what the items say now
    def count(self):
        self.n = collections.Counter(it["role"] for it in self.speech())
        self.castable = {r for r, c in self.n.items() if c >= CASTABLE}

    def speech(self):
        return [it for it in self.items if it["kind"] == "speech" and not it.get("gone")]

    def live(self, it):
        return it["kind"] in ("speech", "direction", "sound", "music") and not it.get("gone")

    def set_text(self, it, text, lead=None):
        it["text"] = text
        if lead is not None:
            it["lead"] = lead
        if self.second:
            import play_layouts as PL
            it["parts"] = (it.get("lead") or []) + PL.parts_of(text)

    def to_direction(self, it):
        it["kind"] = "direction"
        it.pop("role", None)
        it.pop("parts", None)

    def prev(self, k, kinds=("speech",)):
        for j in range(k - 1, -1, -1):
            if self.items[j]["kind"] in kinds and not self.items[j].get("gone"):
                return j
        return None

    # -- 1. what the file says about itself, and an editor's notes
    def boilerplate(self):
        """The 1990s etexts print their license inside the play, act by act ("WITH PERMISSION. ELECTRONIC AND MACHINE
        READABLE COPIES MAY BE DISTRIBUTED ...", gut-1774)."""
        for it in self.items:
            if not self.live(it):
                continue
            if it["kind"] == "speech" and it["role"] in ("WITH PERMISSION", "COMMERCIALLY") and ETEXT_WORDS.search(it["text"]):
                it["gone"] = True
            elif it["kind"] == "direction" and (it["source"].lstrip().startswith("<<") or ETEXT_WORDS.search(it["source"])):
                it["gone"] = True
            elif it["kind"] == "speech" and ETEXT_WORDS.search(it["text"]):
                cut = re.search(r"\s*<<THIS ELECTRONIC VERSION.*\Z", it["text"], re.S)
                if cut and cut.start() > 0:
                    self.set_text(it, it["text"][:cut.start()])

    def notes(self):
        """A note printed between the lines ("[Footnote 3: censures: i.e. judgments.]", "[198] Old eds. ...") is the editor's.
        "[12]" opens a note only when that mark is printed on a word before it."""
        before, k = "", 0
        open_note = 0
        while k < len(self.items):
            it = self.items[k]
            src = it["source"]
            if open_note and self.live(it):
                it["gone"] = True
                open_note -= 1
                if "]" in src:
                    open_note = 0
            elif self.live(it) and it["kind"] == "direction" and (
                    NOTE_OPENS.match(src) or P.NOTE_MARK.match(src) and re.match(r"\s*\[\d", src) and P._is_note(src, before)):
                it["gone"] = True
                if NOTE_OPENS.match(src) and src.count("[") > src.count("]"):
                    closing = next((j for j in range(k + 1, min(k + 7, len(self.items))) if "]" in self.items[j]["source"]
                                    and self.items[j]["source"].count("]") > self.items[j]["source"].count("[")), None)
                    between = self.items[k + 1:closing + 1] if closing else []
                    open_note = closing - k if closing and not any(x["kind"] == "speech" and len(x["source"].split()) > 60 for x in between) else 0
            before = (before + "\n\n" + src)[-2 * P.NOTE_REACH:]
            k += 1
        # a play printed with its notes: "P. 3, l. 12, Beguiling.]--", "II. i. 51. Mr. Bullen says", "PROSE. l. 26."
        for k, it in enumerate(self.items):
            if it["kind"] == "speech" and not it.get("gone") and (
                    it["role"] in ("P", "PP") and re.match(r"\s*\d+\b", it["text"])
                    or ROMAN.match(it["role"]) and re.match(r"\s*[ivx]+\.\s+\d", it["text"])
                    or it["role"] in ("PROSE", "VERSE") and re.match(r"\s*(?:ll?|1)\.\s*\d", it["text"])
                    or self.n[it["role"]] <= 2 and re.search(r"\bAct [IVX]+\.? ?,? sc\.? [ivx]+\.?\W*$", squash(it["text"]))
                    or self.n[it["role"]] <= 4 and SIGNED.match(it["text"])
                    or self.n[it["role"]] == 1 and re.match(r"^(?:Boy|Girl|Man|Woman) of \d\d\. [^!?]*\b(?:suit|dress|costume|wig|gown)\b", squash(it["text"]))):
                it["gone"] = True
                it["_note"] = True
        # a direction between two such notes is a third ("_Jew of Malta_, IV. v. 6.")
        live = [k for k, it in enumerate(self.items) if it["kind"] in ("speech", "direction")]
        for a, b, c in zip(live, live[1:], live[2:]):
            if self.items[a].get("_note") and self.items[c].get("_note") and self.items[b]["kind"] == "direction":
                self.items[b]["gone"] = True
                self.items[b]["_note"] = True

        # "[430] Dyce's correction ...": notes numbered in order are notes wherever their marks are
        row = [(it, int(m.group(1))) for it in self.items if it["kind"] == "direction" for m in [re.match(r"^\s*\[(\d{1,3})\]\s*\S", it["source"])] if m]
        if len(row) >= 5 and sum(0 < b - a <= 3 for (_, a), (_, b) in zip(row, row[1:])) >= 0.8 * (len(row) - 1):
            for it, _ in row:
                it["gone"] = True
        # the notes printed together after the play, with what they quote
        at = [k for k, it in enumerate(self.items) if it.get("gone") and it["kind"] == "direction" and (NOTE_OPENS.match(it["source"]) or P.NOTE_MARK.match(it["source"]))]
        if at:
            rest = [it for it in self.items[at[0]:] if it["kind"] in ("speech", "direction")]
            if len(at) >= 8 and at[0] > 0.4 * len(self.items) and len(at) >= 0.7 * len(rest):
                for it in rest:
                    it["gone"] = True

    # -- 1b. a label the print ends after a stop inside it ("_Don. Louisa_.", "QU. ELIZ.", "MR. R. HASLAM."): its end was spoken,
    # and two speakers ("Don. Louisa", "Don. Clara") were one
    def label_ends(self):
        by = collections.defaultdict(list)
        for it in self.speech():
            by[it["role"]].append(it)
        for role, its in by.items():
            if len(its) < 3:
                continue
            at = [(it, m) for it in its for m in [LABEL_END.match(it["text"])] if m and not it.get("lead")]
            c = collections.Counter(m.group("end") for _, m in at)
            good = {e for e, k in c.items() if k >= 2 and e.strip("._").lower() not in NOT_AN_END}
            share = sum(c[e] for e in good) / len(its)
            marked = {e for e in good if "_" in e or e.strip("._").isupper() and len(e.strip("._")) <= 9}
            if not (marked and sum(c[e] for e in marked) >= 0.4 * len(its) and sum(c[e] for e in marked) >= 3 or good and share >= 0.8):
                continue
            for it, m in at:
                if m.group("end") not in good:
                    continue
                label = squash(it["source"].split("\n")[0])
                k = label.find(m.group("end"))
                whole = P._role(label[:k + len(m.group("end"))].replace("_", "")) if 0 < k < 40 else ""
                if not whole or not m.string[m.end():].strip():
                    continue
                it["role"] = whole.strip(" .")
                self.set_text(it, it["text"][m.end():].lstrip(" :_"))

    # -- 2. after the play: notes, music, costume plots, publisher's lists
    def tail(self):
        sp = [k for k, it in enumerate(self.items) if it["kind"] == "speech"]
        if len(sp) < 20:
            return
        end = self.items[sp[-1]]
        if not re.search(r"[a-z!?]", end["text"]) and len(end["text"].split()) >= 4 and not end.get("gone"):
            self.to_direction(end)  # "FRANY. YOKLE. GRANNY.": where they stand as the curtain falls
            sp = sp[:-1]
        notes = next((k for k, it in enumerate(self.items) if k > sp[int(0.95 * len(sp))] and it["kind"] == "direction" and re.fullmatch(r"[\W_]*(?:END)?NOTES[\W_]*", it["source"].strip())), None)
        if notes is not None and all(re.match(r"^[\W_]*\[", it["source"].strip()) or it["kind"] == "speech" for it in self.items[notes + 1:notes + 2]):
            for it in self.items[notes:]:
                if it["kind"] in ("speech", "direction"):
                    it["gone"] = True
            sp = [k for k in sp if k < notes]
        for x in range(len(sp) // 2, len(sp)):
            k = sp[x]
            it = self.items[k]
            late = x > 0.8 * len(sp)
            again = late and self.n[it["role"]] == 1 and self.title_key and len(self.title_key) > 6 and P._title_key(it["role"]) == self.title_key
            worn = x > 0.8 * len(sp) and COSTUMES_AFTER.match(squash(it["text"])) and len(sp) - x >= 3 and sum(bool(COSTUMES_AFTER.match(squash(self.items[j]["text"]))) for j in sp[x:]) >= 0.5 * (len(sp) - x) \
                and not any(YOU.search(o["text"]) or re.search(r"[!?]", o["text"]) for o in (self.items[j] for j in sp[x:]))
            if not (again or worn or late and (VARIANTS.match(squash(it["text"])) or VARIANT_IN.search(it["text"])) or TAIL_ROLE.match(it["role"]) and (self.n[it["role"]] < CASTABLE or it["role"] in ("VOL", "P", "PP", "T. S", "BY MR")) or PRICED.search(it["text"]) and self.n[it["role"]] < CASTABLE):
                continue
            # nobody the play casts goes on speaking, and no act or scene opens after it
            after = [self.items[j] for j in sp[x + 1:]]
            play = [o for o in after if o["role"] in self.castable and not TAIL_ROLE.match(o["role"]) and not PRICED.search(o["text"])]
            if not worn and len(play) > max(1, 0.02 * len(sp)) or any(o["kind"] == "heading" and P.section_level(o["source"]) and not PRICED.search(o["source"])
                                                         for o in self.items[k + 1:]) and len(after) > 12:
                continue
            for o in self.items[k:]:
                if self.live(o):
                    o["gone"] = True
            # the publisher's lines that led into it ("_Printed by_ BALLANTYNE", "_In preparation._")
            j = k - 1
            while j >= 0 and self.items[j]["kind"] != "speech":
                if self.items[j]["kind"] == "direction" and PUBLISHED.search(self.items[j]["source"]):
                    self.items[j]["gone"] = True
                elif self.items[j]["kind"] == "direction":
                    break
                j -= 1
            return

    # -- 3. before the play: title page, cast list and notes read as the first speeches
    def front(self):
        seen = cast = 0
        listed, taken, page = set(), [], set()
        for k, it in enumerate(self.items):
            if it["kind"] != "speech" or it.get("gone"):
                continue
            seen += 1
            if seen > FRONT_REACH or SPOKEN_BY.match(it["role"]):
                return
            role, said = it["role"], re.sub(r"^\W+", "", squash(re.sub(r"\[Illustration[^\]]*\]|_", "", it["text"])))
            n = self.n[role]
            if not re.search(r"\w", said):
                continue
            if re.match(r"^(?:The scene|SCENE|Scene)\b", said) and not re.search(r"[a-z]{3}", re.sub(r"\[[^\]]*\]|\([^)]*\)|_[^_]*_", "", it["text"])):
                self.to_direction(it)
                continue
            before = next((o for o in self.items[k - 1::-1] if self.live(o) or o["kind"] == "heading"), None) if k else None
            if NEVER_A_PART.match(role) and n <= 4:
                self.to_direction(it)
                continue
            if n == 1 and not self._is_part(role) and "PROLOGUE" not in role and before and re.match(r"^\W*(?:THE )?PROLOGUE\W*$", before["source"], re.I) and YOU.search(said):
                it["role"] = "PROLOGUE"
                credit = re.match(r"^(?:[A-Z][A-Z.,']* ){3,}[A-Z.,']+\s+(?=[A-Z][a-z])", it["text"])
                if credit:
                    it["lead"] = [{"direction": credit.group(0).strip()}]
                    self.set_text(it, it["text"][credit.end():], it["lead"])
                return
            if n <= 4 and FRONT_ROLE.match(role) or n <= 2 and (TITLE_PAGE.search(said) or re.search(r"\bcopies of this\b|\bPhillips & Co\b", said)) and len(said.split()) < 90 and not YOU.search(said) \
                    or n <= 2 and (role in self.authors or role in page) and not YOU.search(said) or n <= 3 and self.title_key and P._title_key(role) == self.title_key and n < CASTABLE and not YOU.search(said):
                it["gone"] = True
                page.add(role)
            elif n < CASTABLE and re.fullmatch(r"REV|DR|MR|MRS|CAPT|COL", role) and len(said.split()) <= 6 and not re.search(r"[!?]", said) or n == 1 and role == "TO" and said.startswith("THE RIGHT"):
                it["gone"] = True
            elif role in ("MEN", "WOMEN", "LADIES", "GENTLEMEN") and n < CASTABLE and not YOU.search(said) and not re.search(r"[!?]", said) and re.search(r", _?[A-Za-z]", squash(it["text"])) \
                    or cast and re.fullmatch(r"[\W_]*[(\[_][A-Z][^)\]_!?]{2,40}[)\]_][\W_]*", squash(it["text"])):
                it["gone"] = True
            elif n == 1 and SIGNED_LETTER.match(said):
                self.to_direction(it)
                continue
            elif n <= 2 and not self._is_part(role) and said.upper() == said and len(said.split()) >= 4 and not re.search(r"[!?]", said) and not YOU.search(said):
                it["gone"] = True  # a list of titles or players
            elif re.match(r"^to (?:her|him|them)\b", said) and len(said.split()) <= 6:
                self.to_direction(it)
                continue
            elif SUBTITLE.match(said) and not taken:
                it["gone"] = True
                continue
            elif n == 1 and P._title_key(said) == self.title_key and self.title_key or self._cast_entry(it, said) \
                    or cast >= 2 and not YOU.search(said) and not re.search(r"[!?]", said) and not it.get("lead") and re.search(r"\b\d\d\b", said):
                # a cast list names each part once: a second line is the part speaking, and the rows before were its first
                if role in listed:
                    for o in taken:
                        o.pop("gone")
                    return
                listed.add(role)
                taken.append(it)
                it["gone"] = True
                cast += 1
            elif n <= 2 and re.match(r"^A (?:\w+ )?(?:tragedy|comedy|farce|drama|play) in \w+ acts?\b", said, re.I):
                self.to_direction(it)
                continue
            else:
                return
            seen -= 1 if it.get("gone") else 0

    def _cast_entry(self, it, said):
        """"Daughter of James K. Gardner, President of ...", "a flute-player.", "Long white hair and beard, gray shirt, ..." """
        if YOU.search(said) or re.search(r"[!?]", said) or it.get("lead") and self.n[it["role"]] > 2:
            return False
        names = re.findall(r"\b[A-ZÀ-Þ]{4,}\b", re.sub(r"\b(?:DRAMATIS|SCENE|ACT)\b", "", it["text"]))
        if len(set(names)) >= 2 and not re.search(r"\b(?:is|are|was|were|has|have|had|says?|comes?|goes)\b", said) and len(said.split()) <= 60:
            return True  # two names in capitals and no verb: the rest of the list
        if re.match(r"^Footnote: Pronounced", said) or DRESSED.search(said) and len(said.split()) <= 70 and not re.match(r"^\W*\[", squash(it["text"])) and self.n[it["role"]] < 400:
            return True
        if ENTRY_SHAPES.search(said) or re.search(r"\.{5,}.*\.{5,}", squash(it["source"])) or re.search(r"\b(?:is a type of|characteristics)\b", said):
            return True
        if re.match(r"^_?[a-z]", squash(it["text"])) and len(said.split()) <= 40 and not it.get("lead"):
            return True
        return bool(CAST_ENTRY.match(said)) or bool(COSTUME.search(said)) and len(said.split()) <= 60

    # -- 4. speeches printed as "_2 Merch._ Sir, ..." that the first reader took for directions
    def labels_in_directions(self):
        shape = re.compile(r"^_(?P<name>(?:\d\w{0,2}\.? )?[A-ZÀ-Þ][^_()\[\]\n]{0,34}?)[.:]?(?P<din>\s*\([^)_]{1,80}\))?[.:]?_(?P<dout>\s*(?:\([^)]{1,200}\)_?|\[[^\]]{1,200}\]_?)|, [a-z][^:“\"_]{2,90}(?=: ?[“\"]))?[.:]?\s*(?P<text>(?=\S).+)$", re.S)
        labels = collections.Counter(P._role(m.group("name")) for it in self.items if it["kind"] == "direction" for m in [shape.match(it["source"].strip())] if m)
        # a play that prints its labels so: any name printed so is a label
        italic = sum(bool(re.match(r"^_[A-ZÀ-Þ][^_\n]{0,34}_?[.:(\[ ]", it["source"])) for it in self.speech()) >= 0.6 * max(1, len(self.speech()))
        found, maybe, bare_stop = [], [], collections.Counter()
        for k, it in enumerate(self.items):
            if it["kind"] != "direction" or it.get("gone"):
                continue
            src = it["source"].strip()
            m = shape.match(src)
            if not m or not re.search(r"[.:]_|_[.:]|[)\]]_?[.:]|: ?$", src[:len(src) - len(m.group("text"))]):
                if m and not m.group("dout"):
                    bare_stop[P._role(m.group("name"))] += 1
                    maybe.append((k, m.group("name").strip(" ."), m.group("text").strip()))
                continue
            name, said = m.group("name").strip(" ."), m.group("text").strip()
            if NOT_A_LABEL.match(name) and not (P._role(name) in FUNCTION and labels[P._role(name)] >= 5) or P._directional(name.lower()) \
                    or not re.match(r"[A-ZÀ-Þ\"“'‘’(\[_—–-]|\.\.\.", said) or len(name.split()) > 4:
                continue
            # "_There is a pause._ PETER _stops short_.", "_Cornets._ _Enter_ GONZAGO": business, nothing said
            spoken = re.sub(r"\[[^\]]*\]?|\([^)]*\)|_[^_]*_", " ", said)
            if not re.search(r"[A-Za-z]{2}|\bI\b", spoken) or re.match(r"^_?[A-ZÀ-Þ][A-ZÀ-Þ'’.-]+(?:\s+[A-ZÀ-Þ][A-ZÀ-Þ'’.-]+)*\s*[_\[(]", said) \
                    or re.match(r"^[\W_]*(?:Enter|Re-?enter|Exit|Exeunt)\b", said) or ACTION_LABEL.search(name) \
                    or WORN.search(said) and not YOU.search(said) and len(said.split()) < 60:
                continue
            d = re.match(r"^(.{2,}?),?\s+(within|without|aside|alone|entering|enters|outside|off)$", name)
            if d:
                name = d.group(1)
            found.append((k, name, said, " ".join(x.strip() for x in (m.group("din"), m.group("dout"), d and d.group(2)) if x)))
        # "_Madam_ No, that's a sailor's knot.": no stop, when the print labels five speeches so
        found += [(k, n, t, None) for k, n, t in maybe if bare_stop[P._role(n)] >= 5 and not NOT_A_LABEL.match(n) and not ACTION_LABEL.search(n) and re.match(r"[A-ZÀ-Þ“\"'‘(\[]", t)
                  and not re.match(r"^[A-Z]{2,}\b", t) and (YOU.search(t) or re.search(r"[!?]", t)) and n not in ("The", "Old", "Young", "A", "First", "Second") and not re.search(r"\[[A-Z][a-z]+ 1[67]\d\d", t)
                  and not re.match(r"^[A-Z][a-z]+[,.]?\s*[\[_(]", t)]
        if not found:
            return
        found.sort(key=lambda f: f[0])
        times = collections.Counter(P._role(n) for _, n, _, _ in found)
        first = next((k for k, it in enumerate(self.items) if it["kind"] == "speech"), 0)
        for k, name, said, din in found:
            role = self.as_role(name, times)
            if role is None and italic and k > first and (YOU.search(said) or re.search(r"[!?]", said)):
                role = P._role(name)
            if role is None or k < first and not (YOU.search(said) or re.search(r"[!?]", said)):
                continue
            it = self.items[k]
            it["kind"], it["role"] = "speech", role
            lead = [{"direction": din.strip(" ()[]_,")}] if din else []
            self.set_text(it, re.sub(r"^(?:--+|—)\s*", "", squash(said)), lead)
            it["lead"] = lead
            # the paragraph after it, which the first reader could not place, is the same speaker going on
            j = k + 1
            while j < len(self.items) and self.items[j]["kind"] == "other":
                o = self.items[j]
                it["source"] += "\n\n" + o["source"]
                self.set_text(it, it["text"] + "\n" + squash(o["source"]), it["lead"])
                o["kind"] = "note"
                j += 1

    def as_role(self, name, times=None):
        """The role a printed label names: itself, a role it shortens or lengthens, a plain or numbered part, or a name
        the print uses as a label more than once."""
        import play_layouts as PL
        r = P._role(name)
        if r in self.castable:
            return r
        if r in self.n and not any(x.startswith(r) for x in self.castable):
            return r
        near = [x for x in self.castable if x.startswith(r) or r.startswith(x) and len(x) >= 3]
        if len(near) == 1 and len(r) >= 2 and (" " not in r or r.startswith(near[0]) and len(near[0]) >= 4):
            return near[0]
        if PL.PLAIN_PART.match(r) or re.match(r"^\d\w{0,2}\.? [A-Z]", r) or PL.GROUP.match(r) or (times or {}).get(r, 0) >= 2:
            return r
        if r in self.names() or any(w in self.names() for w in r.split() if len(w) > 3) or any(n.startswith(r) and len(r) >= 3 for n in self.names()):
            return r
        return None

    def one_number_one_name(self):
        """"1 GEN" and "1 GENT" are one speaker of the print's First Gentleman: the label used most."""
        by = collections.defaultdict(list)
        for r in self.n:
            m = re.match(r"^(\d)\w{0,2}\.? ([A-Z]+)$", r)
            if m:
                by[m.group(1)].append((m.group(2), r))
        for rows in by.values():
            rows.sort(key=lambda x: len(x[0]))
            for x, (w, r) in enumerate(rows):
                longer = [b for a, b in rows[x + 1:] if a.startswith(w)]
                if longer and len(w) >= 2:
                    keep = max(longer + [r], key=lambda o: (not o.endswith("S") or self.n[o] > 1, len(o)))
                    for it in self.speech():
                        if it["role"] in longer + [r]:
                            it["role"] = keep

    def names(self):
        if not hasattr(self, "_names"):
            self._names = P._printed_names([it for it in self.items if not (it["kind"] == "direction" and re.match(r"^_[^_]+[.:]_", it["source"]))])
        return self._names

    def labels_in_lines(self):
        """A verse line that opens on an italic label and was read as the line above going on ("_Are._ Have you done sir.",
        360 of them in gut-45050)."""
        out = []
        shape = re.compile(r"(?:^|(?<=\s))_(?P<name>(?:\d\w{0,2}\.? )?[A-ZÀ-Þ][^_\n]{0,24})\._\s+(?=[A-ZÀ-Þ'’‘“\"(\[—-])")
        # two speakers share a verse line ("To serve your vast expences. _Are._ Am I then"): only in a text that prints five or more
        inside = sum(1 for it in self.speech() for m in shape.finditer(it["text"]) if m.start() and re.search(r"[.?!;:,)\]}—-]\s*$", it["text"][:m.start()])
                     and (P._role(m.group("name")) in self.n or any(x.startswith(P._role(m.group("name"))) for x in self.castable)))
        # a plain label run into the speech before it: at the start of a line after a sentence (three or more in the play),
        # or in capitals anywhere after one (ten or more: gut-7282-2 prints its short replies in one paragraph)
        plain = {}
        for r in self.castable:
            if len(r) >= 3 and not self._is_part(r) and r not in ("YES", "WELL", "SIR", "OLD"):
                plain[r] = r
                plain[r.title()] = r
        run = re.compile(r"(?:(?<=[.?!)\]\"'’”—-])\s+)(?P<name>%s)\.\s+(?=[A-ZÀ-Þ'’‘“\"(\[])" % "|".join(sorted(map(re.escape, plain), key=len, reverse=True))) if plain else None
        starts = lambda it, name: it["role"] not in ("MEN", "WOMEN") and re.search(r"(?<!Mr)(?<!Mrs)(?<!Dr)(?<!St)(?<!MR)(?<!MRS)(?<!DR)[.?!)\]\"'’”—-][ \t]*\n[ \t]*%s\.\s" % re.escape(name), it["source"])
        runs = [(it, m) for it in self.speech() for m in (run.finditer(it["text"]) if run else ()) if plain[m.group("name")] != it["role"]]
        at_lines = sum(bool(starts(it, m.group("name"))) for it, m in runs)
        in_caps = sum(m.group("name").isupper() for _, m in runs)
        for it in self.items:
            out.append(it)
            if it["kind"] != "speech" or it.get("gone"):
                continue
            cuts = []
            at_start = {m.group(1) for m in re.finditer(r"(?m)^[ \t]*(_[A-ZÀ-Þ\d][^_\n]{0,24}\._)(?=\s)", it["source"]) if m.start()}
            for m in shape.finditer(it["text"]):
                name = m.group("name")
                shared = inside >= 5 and re.search(r"[.?!;:,)\]}—-]\s*$", it["text"][:m.start()])
                if not m.start() or m.group(0).strip() not in at_start and not shared or NOT_A_LABEL.match(name) or P._directional(name.lower()):
                    continue
                r = P._role(name)
                if r not in self.castable:
                    near = [x for x in self.castable if len(r) >= 2 and " " not in r and x.startswith(r)]
                    r = near[0] if len(near) == 1 else r if r in self.n or re.match(r"^\d\w{0,2}\.? [A-Z]", r) else None
                hon = re.search(r"\b(Mrs?|Miss|Sir|Lady)\.?\s+$", it["text"][:m.start()])
                if hon and P._role(hon.group(1) + ". " + name) in self.n:
                    r = P._role(hon.group(1) + ". " + name)
                if r and r != it["role"] or cuts and r:
                    cuts.append((m, r))
            if not cuts and run:
                cuts = [(m, plain[m.group("name")]) for m in run.finditer(it["text"])
                        if in_caps >= 10 and m.group("name").isupper() and not re.search(r"\b(?:MRS?|DR|ST|MISS)\.?$", it["text"][:m.start()], re.I) or at_lines >= 3 and starts(it, m.group("name"))]
                if cuts and cuts[0][1] == it["role"]:
                    cuts = []
            if not cuts:
                continue
            text, src = it["text"], it["source"]
            label = [c[0].group(0).strip() for c in cuts]
            marks, pos = [], 1
            for l in label:
                f = re.search(re.escape(l), src[pos:])
                marks.append(pos + f.start() if f else len(src))
                pos = marks[-1] + 1
            before = [re.sub(r"\s+(?:Mrs?|Miss|Sir|Lady)\.?\s*$", "", text[a:b]).strip() for a, b in
                      zip([0] + [c[0].end() for c in cuts], [c[0].start() for c in cuts] + [len(text)])]
            self.set_text(it, before[0])
            it["source"] = src[:marks[0]].rstrip()
            for x, (m, r) in enumerate(cuts):
                new = {"kind": "speech", "role": r, "split": "new", "lead": [], "source": src[marks[x]:marks[x + 1] if x + 1 < len(cuts) else len(src)].strip()}
                self.set_text(new, before[x + 1])
                out.append(new)
        self.items = out

    # -- 5. a labeled speech folded into the speech above it
    def folded(self):
        out = []
        for it in self.items:
            out.append(it)
            if it["kind"] != "speech" or it.get("gone") or not it.get("continued") or self.second:
                continue
            rows = it["text"].split("\n")
            c = it["continued"]
            if c >= len(rows):
                continue
            srcs = it["source"].split("\n\n")
            if len(srcs) < c + 1:
                continue
            head, s_head, s_paras = rows[:-c], srcs[:-c], srcs[-c:]
            # (source, text) of each paragraph after the first, broken again where a line opens with a numbered label
            pieces = []
            for p in s_paras:
                cur = []
                for l in p.split("\n"):
                    if cur and (m := FOLDED.match(l.strip())) and m.group("num"):
                        pieces.append(cur)
                        cur = []
                    cur.append(l)
                pieces.append(cur)
            pieces = [("\n".join(x), " ".join(y.strip() for y in x)) for x in pieces]
            cuts = []
            for j, (_, t) in enumerate(pieces):
                own = FOLDED_OWN.match(t)
                if own and j + 1 < len(pieces) and not FOLDED_OWN.match(pieces[j + 1][1]):
                    cuts.append((j, own))
                elif (m := FOLDED.match(t)) and self.folded_role(m, it):
                    cuts.append((j, m))
            if not cuts:
                continue
            first = cuts[0][0]
            self.set_text(it, "\n".join(head + [t for _, t in pieces[:first]]))
            it["source"] = "\n\n".join(s_head + [s for s, _ in pieces[:first]])
            for x, (j, m) in enumerate(cuts):
                stop = cuts[x + 1][0] if x + 1 < len(cuts) else len(pieces)
                own = m.re is FOLDED_OWN
                said, lead = (pieces[j + 1][1] if own else m.group("text")), []
                if own and m.group("d"):
                    lead = [{"direction": m.group("d").strip("()[]_ ")}]
                d = None if own else re.match(r"^_?(\([^()]*\)|\[[^\[\]]*\])_?[.:]?\s*(?=\S|$)", said)
                if d:
                    said, lead = said[d.end():], [{"direction": d.group(1).strip("()[]_ ")}]
                out.append({"kind": "speech", "role": P._role(m.group("num")) if own else self.folded_role(m, it), "source": "\n\n".join(s for s, _ in pieces[j:stop]), "split": "new",
                            "lead": lead, "text": "\n".join(([said] if re.search(r"\w", said) else []) + [t for _, t in pieces[j + 1 + own:stop]])})
        self.items = out

    def capitals_in_lines(self):
        """"No more to see thee! ELECTRA. Nor thy breath ...": a part's own label, in capitals as every label of the play is,
        inside another's speech after a sentence has ended."""
        sp = [it for it in self.speech() if not it.get("gone")]
        if sum(printed_in_capitals(it) for it in sp) < 0.9 * max(1, len(sp)):
            return
        out = []
        for it in self.items:
            out.append(it)
            while it["kind"] == "speech" and not it.get("gone"):
                cut = next((m for m in CAPS_INSIDE.finditer(it["text"]) if self._label_inside(m, it)), None)
                if not cut:
                    break
                label = re.compile(r"(?<=[.!?”\"’\-—])\s+%s(?=\s)" % re.escape(cut.group("label")))
                where = label.search(it["source"])
                if not where or len(label.findall(it["source"])) != 1:
                    break
                new = {"kind": "speech", "role": P._role(cut.group("who")), "source": it["source"][where.start():].strip(), "split": "new", "lead": [], "text": it["text"][cut.end():]}
                it["source"] = it["source"][:where.start()]
                self.set_text(it, it["text"][:cut.start()], it.get("lead"))
                self.set_text(new, new["text"])
                out.append(new)
                it = new
        self.items = out

    def _label_inside(self, m, it):
        left, right, role = it["text"][:m.start()], it["text"][m.end():], P._role(m.group("who"))
        level = lambda t: t.count("(") - t.count(")") or t.count("[") - t.count("]") or t.count("_") % 2
        return role != it["role"] and self.n[role] >= 1 and not level(left) and not level(m.group(0)) and bool(re.search(r"[a-z]", left)) and bool(re.search(r"\b[a-z]+\b", right.split("\n\n")[0][:60])) \
            and not re.search(r"(?:\b(?:Mr|Mrs|Miss|Dr|Sir|St|Messrs)\.?|\b[A-Z][A-Z'’]+[.,]?)$", left.strip()) and not re.match(r"[A-Z][A-Z'’]+\b", right)

    def folded_role(self, m, it):
        name = m.group("num") or m.group("name")
        r = P._role(name)
        if m.group("num"):
            word = name.split()[-1]
            times = len(re.findall(r"(?m)^\s*_?%s\b" % re.escape(name), self.text))
            return r if not P.HEADING.match(name) and not P.section_level(name) and not HEADING_WORD.match(word) and (self._is_part(r) or r in self.n or times >= 2 or word.isupper() and len(word) > 1) else None
        if NOT_A_LABEL.match(name) or P._directional(name.lower()):
            return None
        if r in self.n and r != it["role"] and (m.group("i") or self.n[r] >= 3):
            return r
        if m.group("i"):
            near = [x for x in self.castable if x.startswith(r) and len(r) >= 2]
            return near[0] if len(near) == 1 and near[0] != it["role"] else None
        return None

    # -- 6. the first word of a sentence read as a speaker
    def words_read_as_speakers(self):
        caps = sum(self.n[it["role"]] > 0 and printed_in_capitals(it) for it in self.speech())
        mostly_caps = caps >= 0.7 * max(1, len(self.speech()))
        for k, it in enumerate(self.items):
            if it["kind"] != "speech" or it.get("gone") or it.get("split"):
                continue
            role = it["role"]
            m = re.match(r"^\s*(?P<word>[A-Z][A-Za-z'’\-]*(?: [A-Za-z'’\-]+){0,2})(?P<stop>[.;:,](?=\s)|--|—)", it["source"])
            if not m or m.group("word").isupper() and len(m.group("word")) > 1 and role not in WORDS:
                # printed as a label is printed: only a closed list of words may be taken from a speaker in capitals
                if not (role in LIST_LINES):
                    continue
            if not m or P._role(m.group("word")) != role:
                continue
            if role not in LIST_LINES and re.search(r"[A-ZÀ-Þ]{2}", m.group("word")):
                continue
            word = role.split()[0].lower().strip("'.")
            if role in ("SILENCE", "PAUSE") or role == "ME" and not it["text"][:1].islower():
                continue
            if not (role in WORDS or role in LIST_LINES or role.split()[0] in ("OF", "WHO") and role not in self.names()
                    or mostly_caps and role not in self.names() and not self._is_part(role) and self.lower(word) >= 3):
                continue
            who = self.speaker_over(k)
            if who is None or role in LIST_LINES and self.ends_a_sentence(k):
                continue
            it["role"] = who[0]
            self.set_text(it, m.group("word") + m.group("stop") + ("" if m.group("stop") in ("--", "—") else " ") + it["text"], who[1])
            it["lead"] = who[1]

    def ends_a_sentence(self, k):
        j = self.prev(k)
        return j is not None and bool(re.search(r"[.?!][\"'”’)\]_]*$", self.items[j]["text"].strip()))

    def _is_part(self, role):
        import play_layouts as PL
        return bool(PL.PLAIN_PART.match(role) or PL.GROUP.match(role))

    def lower(self, word):
        if not hasattr(self, "_low"):
            self._low = collections.Counter(re.findall(r"(?<![A-Za-z'’])[a-zà-ÿ'’\-]{2,}", self.text))
        return self._low[word]

    def speaker_over(self, k):
        """(role, lead) of the speaker the text prints over item k: the label alone above it, or the speech it broke."""
        hay = self.flat()
        needle = squash(self.items[k]["source"])[:60]
        j = self.prev(k, ("speech", "direction", "sound", "music", "heading", "cast"))
        tail = squash(self.items[j]["source"])[-50:] if j is not None else ""
        at = hay.find(tail + " " + needle) if tail else -1
        if at >= 0:
            # nothing stands between: the line broke the speech above it
            if self.items[j]["kind"] == "speech":
                return self.items[j]["role"], []
            return None
        for m in re.finditer(re.escape(needle), hay):
            before = hay[max(0, m.start() - 200):m.start()]
            a = before.rfind(tail[-25:]) if tail else -1
            if a < 0:
                continue
            gap = before[a + len(tail[-25:]):].strip()
            d = re.search(r"\s*(\([^()]*\)|\[[^\[\]]*\])[.:—-]*$", gap)
            role = P._role((gap[:d.start()] if d else gap).strip(" .:_—-"))
            if role in self.n:
                return role, ([{"direction": d.group(1).strip("()[] _")}] if d else [])
        return None

    def flat(self):
        if not hasattr(self, "_flat"):
            self._flat = squash(self.text)
        return self._flat

    # -- 7. a label cut at a title or a particle, or joined to its first words
    def cut_labels(self):
        out = []
        for it in self.items:
            out.append(it)
            if it["kind"] != "speech" or it.get("gone"):
                continue
            role, said = it["role"], it["text"]
            # "BOHUN. I--" alone on a line over "DOLLY (interrupting him). Oh, yes, you are"
            m = re.match(r"^(?P<who>[A-Z][A-Z' ]+?)\. (?P<words>(?:I|NO|YES|OH)\b.*)$", role)
            if m and m.group("who") in self.n:
                label = it["source"].strip().split("\n")[0].strip()
                words = label[len(m.group("who")) + 1:].strip(" _")
                got = P.S_ROLE_LEAD.match(squash(said)) or P.S_ROLE_INLINE.match(squash(said))
                who = P._role(got.group("role")) if got else None
                if who in self.n and who != role:
                    d = got.groupdict().get("d")
                    first = {"kind": "speech", "role": m.group("who"), "source": label, "text": words, "lead": [], "split": "new"}
                    out.insert(len(out) - 1, first)
                    it["role"] = who
                    self.set_text(it, got.group("text").strip(), [{"direction": d.strip("_()[] ")}] if d and d.strip("_()[] ") else [])
                    it["source"] = it["source"].split("\n", 1)[1].strip() if "\n" in it["source"] else it["source"]
                elif not got and said.strip() and not YOU.search(said):
                    out.insert(len(out) - 1, {"kind": "speech", "role": m.group("who"), "source": label, "text": words, "lead": [], "split": "new"})
                    it["source"] = it["source"].split("\n", 1)[1].strip() if "\n" in it["source"] else said
                    self.to_direction(it)
                elif not got and said.strip():
                    it["role"] = m.group("who")
                    self.set_text(it, words + " " + said)
                continue
            # "DEAR MR. TANNER: I am discharging ...", a letter read aloud
            if role.startswith("DEAR ") and self.n[role] == 1:
                j = next((x for x in range(len(out) - 2, -1, -1) if out[x]["kind"] == "speech"), None)
                if j is not None and out[j]["role"] in self.n:
                    it["role"] = out[j]["role"]
                    self.set_text(it, squash(it["source"]))
                    it["lead"] = []
                continue
            # "LADY CORINTHIA AND MRS" over "BANGER (rising). Thank you."; "DE BROC, ..., DE" over "MORVILLE (start up)."
            m = re.search(r"(?:^|\s)(MR|MRS|MISS|DR|ST|REV|DE|VON|OF)$", role)
            t = re.match(r"^_?(?P<name>[A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]+)(?P<end>_?[.:,]_?[:.]?|(?=\s*[(\[])|(?<=[A-Z]{3})(?=\s))\s*(?P<rest>(?=\S).*)$", said, re.S)
            if m and t and self.n[role] < 40:
                whole = role + (". " if m.group(1) in ("MR", "MRS", "DR", "ST", "REV") else " ") + t.group("name").upper()
                known = {w for r in self.n for w in r.replace(".", "").split()} | self.names()
                same = [o for o in self.items if o["kind"] == "speech" and o["role"] == role]
                if t.group("name").upper() in known and all(squash(o["text"]).lstrip("_").startswith(t.group("name")) for o in same) and not TAIL_ROLE.match(role) and not FRONT_ROLE.match(role):
                    d = re.match(r"^_?(\([^)]*\)|\[[^\]]*\])_?[.:]?\s*", t.group("rest"))
                    it["_whole"] = (whole, t.group("rest")[d.end():] if d else t.group("rest"), [{"direction": d.group(1).strip("()[]_ ")}] if d else [])
        for it in out:
            if "_whole" in it:
                role, said, lead = it.pop("_whole")
                it["role"] = role
                self.set_text(it, said, lead + [])
                it["lead"] = lead
        self.items = out

    # -- 8. headings, places, times and directions read as speakers
    def _describes_another(self, it):
        """"THOMAS" over "MISS HENEAGE _is a solidly built, narrow-minded woman ..._": a name in capitals, then in italics what
        that other person is or does, and not a word outside the italics."""
        text = it["text"].strip()
        m = re.match(r"^[\W_]*(?P<who>(?:[A-Z][A-Z'’.]+ )+|(?:[A-Z]\w+ ){1,2}(?=_(?:is|are|sits|stands|was|wears)\b))[\[_(]", text)
        if not m or it.get("lead") or P._role(m.group("who")) == it["role"]:
            return False
        bare = re.sub(r"\[[^\]]*\]|\([^)]*\)|_[^_]*_", " ", text)[len(m.group("who")):]
        return not re.search(r"[a-z]", bare) and not re.search(r"[!?]", text) and len(text.split()) >= 8 \
            and bool(re.search(r"\b(?:is|are|was|sits|stands|wears|tries|enters?|comes|goes|takes)\b", text.replace("_", " ")))

    def headings(self):
        inserts = []
        for k, it in enumerate(self.items):
            if it["kind"] != "speech" or it.get("gone"):
                continue
            role, said = it["role"], squash(it["text"])
            m = re.match(r"^(?P<d>[^\])]{0,12}[\])]_?)\s*(?P<rest>.*)$", said, re.S) if role in ("SIGNAL NO", "MELODY NO") else None
            if m:
                # "[_Trumpet / Signal No. 52._] Column right!": the direction the line above opened, then the speech going on
                j = self.prev(k)
                if m.group("rest") and j is not None:
                    it["role"], lead = self.items[j]["role"], [{"direction": "%s. %s" % (role.title(), m.group("d").strip("_[]() "))}]
                    self.set_text(it, m.group("rest"), lead)
                    it["lead"] = lead
                else:
                    self.to_direction(it)
                continue
            by = SPOKEN_BY.match(role)
            if by:
                self._spoken_by(k, it, by)
                continue
            m = re.match(r"^(?:MUSIC ACCOMPANIED\. )?(?P<who>.+?),? (?P<verb>SINGS|(?<=ALL )SING|WAKES|LINGERS|SPEAKS|GIVES TO THEE HIS SOUL)$", role)
            if m:
                who = m.group("who")
                real = who if who in self.n or who in COLLECTIVE else next(iter([r for r in self.n if who.startswith(r) and len(r) >= 3 and r != role]), who if who in self.names() else None)
                if m.group("verb").startswith("GIVES"):
                    j = self.prev(k)
                    if j is not None and self.items[j]["role"] == who:
                        it["role"] = who  # "Homo fuge ... FAUSTUS GIVES TO THEE HIS SOUL." is what he reads
                    continue
                if real:
                    it["role"] = real
                    self.set_text(it, it["text"], [{"direction": m.group("verb").lower()}] + (it.get("lead") or []))
                    it["lead"] = [{"direction": m.group("verb").lower()}]
                continue
            if self.n[role] == 1 and P._role(said) == role and P.HEADING.match(role):
                self.to_direction(it)
                continue
            if role in ("SILENCE", "PAUSE") and self.n[role] < CASTABLE and not YOU.search(said):
                self.to_direction(it)
                continue
            if k < 12 and it["text"].count("_") % 2 and it["text"].rstrip().endswith("_") and SETTING.search(said[:60]) and not YOU.search(said) and len(said.split()) <= 12:
                self.to_direction(it)
                continue
            if role == "NIGHT" and self.n[role] == 1 and SETTING.search(said[:200]) and len(said.split()) < 60:
                self.to_direction(it)
                continue
            if self._describes_another(it):
                self.to_direction(it)
                continue
            if role in self.castable and not NEVER_A_PART.match(role) and self.n[role] > 12:
                continue
            if "--" in role or PLACE_ROLE.match(role) and self.n[role] == 1 or re.match(r"^NO(?:\. \d+\w?)?$", role):
                got = P.S_ROLE_LEAD.match(said) or P.S_ROLE_INLINE.match(said)
                who = P._role(got.group("role")) if got else None
                if who in self.n and who != role:
                    d = got.groupdict().get("d")
                    head = squash(it["source"].strip().split("\n")[0]).strip(" .")
                    lead = [{"direction": role.title() if role.startswith("NO") else head}] + ([{"direction": d.strip("_()[] ")}] if d and d.strip("_()[] ") else [])
                    it["role"] = who
                    self.set_text(it, got.group("text").strip(), lead)
                    it["lead"] = lead
                    continue
                if role == "NO" and re.match(r"^\d+\w?\.", said):
                    self.to_direction(it)
                    continue
            if role.endswith(".--"):
                it["role"] = role = role[:-3].strip(" .")
            if role == "CHORAL HYMN" and "CHORUS" in self.n:
                it["role"] = "CHORUS"
                self.set_text(it, it["text"], [{"direction": "Choral hymn"}])
                it["lead"] = [{"direction": "Choral hymn"}]
                continue
            if role == "MORAL":
                j = self.prev(k, ("speech", "direction", "heading"))
                if j is not None and self.items[j]["kind"] == "speech" and self.items[j]["role"] in self.castable:
                    it["role"] = self.items[j]["role"]
                    self.set_text(it, it["text"], [{"direction": "Moral"}])
                    it["lead"] = [{"direction": "Moral"}]
                continue
            self._then = None
            if NEVER_A_PART.match(role) or self.is_set(k, it, said):
                if self._then:
                    # a setting and, on the same paragraph, the first speech
                    inserts.append((k + 1, {"kind": "speech", "role": self._then[0], "source": it["source"], "text": self._then[1], "lead": [{"direction": self._then[2]}] if self._then[2] else [], "split": "new"}))
                    cut = re.search(re.escape(self._then[1].split()[0]), it["source"][20:])
                    it["source"] = re.sub(r"[“\"]?%s[”\"]?[.:]?\s*$" % re.escape(self._then[0].title()), "", it["source"][:20 + cut.start()].rstrip(), flags=re.I).rstrip() if cut else it["source"]
                self.to_direction(it)
        for at, new in reversed(inserts):
            self.items.insert(at, new)

    def is_set(self, k, it, said):
        """The words under a name are a setting, an entrance or a heading, not a speech."""
        role = it["role"]
        if (self._is_part(role) and not (PLACE_ROLE.match(role) and role.startswith("ANOTHER")) or role in COLLECTIVE) and not said.startswith("_") and re.search(r"[A-Za-z]", re.sub(r"\[[^\]]*\]|\([^)]*\)|_[^_]*_", "", it["text"])):
            return False
        if ROMAN.match(role):
            if re.match(r"^[A-Z]{4,}(?: [A-Z]+)*\s?[—-]", said):
                return True
            if YOU.search(said) and self._is_verse(it):
                return False  # a stanza of a song ("IV. I go to the land where my father is gone")
            if self._all_italic(it["source"].strip().split(".", 1)[-1]) and len(it["source"].strip().split("\n")) >= 3 and not re.match(r"^[\W_]*[\[(]", said) or YOU.search(said) and not re.match(r"^[\W_]*[\[(_]", said) and len(said.split()) < 12:
                return False
            if re.search(r"\w", re.sub(r"\[[^\]]*\]|\([^)]*\)|_[^_]*_", "", it["text"])) and (self._is_verse(it) or re.match(r"^[\W_]*_", said)):
                named = [w for w in re.findall(r"\b[A-Z][A-Z]+\b", said[:120]) if w in self.n and not ROMAN.match(w)]
                if named and re.match(r"^[\W_]*_", said):
                    it["role"] = named[0]  # "III. _The_ CHORUS _crown the altars ..._ Ye gods, ..."
                return False
            m = re.match(r"^[\W_]*[\[_(].{4,400}?[\]_)]+\s+[“\"]?(?P<who>(?:[A-Z][A-Za-z]*\.? ?){1,3})[”\"]?(?:, (?P<how>[a-z][^:.\"“A-Z]{2,60}))?[.:]\s+(?P<text>\S.*)$", said, re.S)
            if m and P._role(m.group("who")) in self.n and not ROMAN.match(P._role(m.group("who"))):
                self._then = (P._role(m.group("who")), m.group("text"), m.group("how"))
            return True
        # a place named over its spot: "WARKWORTH. Before NORTHUMBERLAND'S Castle", "VENICE. A street.", "CARTHAGE. _Enter_ ASDRUBAL"
        if PLACE_NAMES.match(role) and len(said.split()) <= 14 and re.match(r"^[\W_]*(?:A|An|The|Another|Before|Near|Under|In|On|At|Enter|Plains?|Westminster|[A-Z]+ ?[A-Z]*['’]S)(?![A-Za-z])", said) and not re.search(r"[!?]", said) and not YOU.search(said):
            return True
        bare = squash(re.sub(r"\[[^\]]*\]|\([^)]*\)|_[^_]*_", " ", it["text"]))
        if self.n[role] > 4:
            return False
        # nothing said: every word is a direction, or names in capitals inside one
        if self.n[role] <= 2 and not self._named(role) and not re.search(r"[a-z]", bare) and len(said.split()) >= 3 and not re.search(r"[!?]", said) \
                and not self._is_part(role) and not SONG_ROLE.match(role) and SETTING.search(said) and not (self._printed_name(role) and not PLACE_ROLE.match(role)):
            return True
        # a running title, capitals only ("LITERARY TASTES" over "DUOLOGUE BETWEEN CATHERINE MORLAND AND ISABELLA THORPE.")
        if self.n[role] <= 2 and not self._is_part(role) and not re.search(r"[a-z!?]", said) and len(said.split()) >= 3 and not self._named(role) and not YOU.search(said):
            return True
        # names in capitals, positions, a running title: "FRANK. ADELAIDE. SIMON" over "R. L.", "A COMEDY" over "Act the First."
        if self.n[role] <= 2 and not self._is_part(role) and (re.match(r"^\W*(?:Curtain|Act the \w+)\W*$", said) or re.search(r"[.-]", role) and not re.search(r"[a-z!?]", bare)):
            return True
        # several names over an entrance: "THIBAUT, RAIMOND, JOHANNA" over "BERTRAND enters, a helmet in his hand."
        if re.search(r",|\. ", role) and re.match(r"^[A-Z]{3,}\b[^!?]*\b(?:enters?|discovered|comes?)\b", said) and not YOU.search(said):
            return True
        if self.n[role] == 1 and not bare and re.match(r"^[\W_]*_?[a-zA-Z]", said) and re.search(r"\b(?:comes? in|enters)\b", said) and it["text"].lstrip().startswith("_"):
            return True
        # a title once over the scene it opens ("BARBARA'S WEDDING" over "The Colonel is in the sitting-room of his country cottage")
        if self.n[role] == 1 and not self._is_part(role) and not self._printed_name(role) and NARRATED.search(said[:160]) and not YOU.search(said[:160]) and not re.search(r"[!?]", said[:160]):
            return True
        nxt = next((o for o in self.items[k + 1:] if self.live(o) or o["kind"] == "heading"), None)
        enters = nxt is not None and nxt["kind"] in ("direction", "heading")
        if not re.search(r"\w", re.sub(r"\[[^\]]*\]|\([^)]*\)|_[^_]*_", "", it["text"])) and (PLACE_ROLE.match(role) or not self._named(role) and OPENS_SCENE.match(said.lstrip("[(_ "))):
            return True
        if OPENS_SCENE.match(said.lstrip("[(_ ")) and not self._named(role) and (not self._printed_name(role) or PLACE_ROLE.match(role)):
            return True
        if PLACE_ROLE.match(role) and not re.search(r"(?<!WALLS) OF (?:THE )?[\w'’]+$", role) and not YOU.search(re.sub(r"\[[^\]]*\]|\([^)]*\)|_[^_]*_", "", it["text"])) and not re.search(r"[!?]|--|—$", said):
            return True
        return False

    def _named(self, role):
        ws = [w for w in re.findall(r"[A-ZÀ-Þ']+", role) if len(w) > 2 and w not in ("THE", "AND")]
        return bool(ws) and all(any(w in r.split() for r in self.castable) for w in ws)

    def _printed_name(self, role):
        """The print names this person somewhere besides the label (its cast list, an entrance)."""
        ws = [w for w in re.findall(r"[A-ZÀ-Þ'’]{3,}", role) if w not in ("THE", "AND", "MRS", "MISS", "SIR", "LADY")]
        return bool(ws) and all(w in self.names() for w in ws)

    def _is_verse(self, it):
        return "\n" in it["source"].strip() and len(it["source"].strip().split("\n")) >= 3 and max(len(x.strip()) for x in it["source"].split("\n")) <= 62 \
            and not re.match(r"^[\W_]*[\[(]", it["text"])

    def _spoken_by(self, k, it, by):
        """"PROLOGUE / SPOKEN BY MR. MARTIN" over the prologue: the print names the part (PROLOGUE, or Lady Teazle), and the
        actor who spoke it once is the print's note."""
        who = P._role(by.group("who"))
        role = who if who in self.n else None
        if role is None:
            hay = self.flat()
            at = hay.find(squash(it["source"])[:60])
            over = re.findall(r"\b(PROLOGUE|EPILOGUE|INDUCTION)\b", hay[max(0, at - 160):at + 5])
            role = over[-1] if over else None
        if role is None:
            return
        if re.match(r"^[\W_]*Enter\b", it["text"]):
            self.to_direction(it)
            return
        credit = squash(it["source"].strip().split("\n")[0]).strip(" _.")
        it["role"] = role
        said = re.sub(r"^(?:DR|MR|MRS)?\.? ?LANGHORNE\.\s*", "", it["text"]) if role == "PROLOGUE" else it["text"]
        self.set_text(it, said, [{"direction": credit}] + (it.get("lead") or []))
        it["lead"] = [{"direction": credit}]

    # -- 9. songs: the label names a form and often the singer ("AIR V.--PEDRILLO", "RECITATIVE--DR. DALY", "SONG. [Don Ant.]")
    def songs(self):
        k = 0
        while k < len(self.items):
            it = self.items[k]
            k += 1
            if it["kind"] != "speech" or it.get("gone"):
                continue
            m = SONG_ROLE.match(it["role"])
            if not m and STANZA.match(it["role"]) and self._is_verse(it):
                real = self._singer(k - 1) or self._chorus_over(k - 1)
                while real and k - 1 < len(self.items) and self.items[k - 1]["kind"] == "speech" and STANZA.match(self.items[k - 1].get("role", "")):
                    o = self.items[k - 1]
                    lead = [{"direction": o["role"]}]
                    o["role"] = real
                    self.set_text(o, o["text"], lead)
                    o["lead"] = lead
                    k += 1
                continue
            if not m:
                continue
            who, form = m.group("w"), m.group("form")
            real = None
            if who and not re.search(r"\bAND\b|^(?:MR|MRS|DR|LADY|SIR|MISS)\.?$", who):
                w = P._role(re.sub(r"^(?:DON|MR\.?) ", "", who)) if P._role(who) not in self.n else P._role(who)
                real = w if w in self.n else next(iter([r for r in self.castable if len(r) >= 3 and (who.startswith(r) or r.startswith(who) or len(r.split()[-1]) >= 3 and who.split()[-1].startswith(r.split()[-1]))]), None)
            if real is None and form.startswith(("AIR", "SONG")) and not who:
                first = re.match(r"^[\W_]*(?P<n>(?:[A-Z][a-z]+\.? ?){1,3})[._\])]+", it["text"])
                r = P._role(first.group("n")) if first else None
                if r in self.n:
                    real = r
                    self.set_text(it, it["text"][first.end():].lstrip(" .]_"))
            if real is None:
                if re.fullmatch(r"AIR [IVXLC]+", it["role"]) and len(it["text"].split()) <= 14 or re.match(r"^(?:Set by|LA GLOIRE)\b", it["text"]):
                    self.to_direction(it)
                continue
            it["role"] = real
            it["lead"] = [{"direction": re.sub(r" [IVXLC]+$", lambda x: x.group(0).upper(), form.title(), flags=re.I)}]
            text = it["text"]
            if self._all_italic(text):
                text = text.replace("_", "")
            self.set_text(it, text, it["lead"])
            # its later stanzas, printed in italics and so read as directions
            while k < len(self.items) and self.items[k]["kind"] == "direction" and self._all_italic(self.items[k]["source"]) \
                    and len(self.items[k]["source"].strip().split("\n")) >= 2:
                o = self.items[k]
                o["kind"], o["role"], o["lead"] = "speech", real, []
                self.set_text(o, "\n".join(x.strip().replace("_", "") for x in o["source"].strip().split("\n")), [])
                k += 1
            while k < len(self.items) and self.items[k]["kind"] == "speech" and ROMAN.match(self.items[k].get("role", "")):
                o = self.items[k]
                num = o["role"]
                o["role"] = real
                self.set_text(o, o["text"].replace("_", "") if self._all_italic(o["text"]) else o["text"], [{"direction": num}])
                o["lead"] = [{"direction": num}]
                k += 1

    def _chorus_over(self, k):
        """The label alone over an ode's first stanza ("CHORUS. / ODE. / I. 1.")."""
        hay, needle = self.flat(), squash(self.items[k]["source"])[:60]
        j = self.prev(k, ("speech", "direction", "heading"))
        tail = squash(self.items[j]["source"])[-25:] if j is not None else ""
        for m in re.finditer(re.escape(needle), hay):
            gap = hay[max(0, m.start() - 60):m.start()]
            a = gap.rfind(tail) if tail else -1
            g = re.match(r"^([A-Z]+)\.(?: ODE\.)?$", gap[a + len(tail):].strip()) if a >= 0 else None
            if g and not ROMAN.match(g.group(1)):
                return self.as_role(g.group(1))
        return None

    def _singer(self, k):
        """Who the print says sings the stanzas at k: "_Chispa sings._" above them, or "[Sings.]" ending the speech above."""
        for j in range(k - 1, max(-1, k - 4), -1):
            o = self.items[j]
            if o["kind"] == "direction":
                m = re.match(r"^[\W_]*((?:[A-Z][a-z]+\.? ?){1,2}) sings\W*$", squash(o["source"]))
                if m:
                    return self.as_role(m.group(1))
            elif o["kind"] == "speech" and SONG_ROLE.match(o["role"]) and not o.get("gone"):
                continue
            elif o["kind"] == "speech":
                return o["role"] if re.search(r"[\[(_]\s*_?Sings?\.?_?\s*[\])_]?[\s:—.-]*$", o["text"]) else None
        return None

    def _all_italic(self, src):
        rows = [x.strip() for x in src.strip().split("\n") if x.strip()]
        whole = squash(src)
        return bool(rows) and (all(re.fullmatch(r"_[^_]+_[.,;:!?]*", x) for x in rows) or not re.search(r"\w", re.sub(r"_[^_]+_", "", whole)))

    def italic_verse(self):
        """A labeled speech whose every line the print sets in italics (a song, an epilogue) was read as directions alone:
        two or more italic lines, or one that says "I" or "you", and no stage word at their head."""
        for it in self.speech():
            if it.get("split") == "new" or not self._all_italic(it["text"]) or re.search(r"[\[(]", it["text"]):
                continue
            spans = re.findall(r"_([^_]+)_", it["text"])
            rows = [x for s in spans for x in s.split("\n") if x.strip()]
            first = re.sub(r"^\W+", "", rows[0]) if rows else ""
            verse = len(rows) >= 3 or len(rows) == 2 and all(re.match(r"^\W*[A-Z]", x) for x in rows)
            if (verse or YOU.search(it["text"]) and len(it["text"].split()) >= 6) and not P._directional(first.lower()) and not OPENS_SCENE.match(first) \
                    and not re.search(r"\b(?:curtain|stage|exit|exeunt|enters?)\b", it["text"], re.I) and max(len(x) for x in rows) <= 70:
                self.set_text(it, it["text"].replace("_", ""))

    # -- 10. an abbreviation that is an English word ("AND", "BUT", "NOT", "ARE"), when the print gives the one name it shortens
    def short_names(self):
        pronouns = {"HE", "SHE", "HIM"} & set(self.n)
        for role in [r for r in self.n if r in FUNCTION and self.n[r] >= 2 and not (r == "HER" and pronouns)]:
            full = self.full_name(role)
            if full:
                for it in self.speech():
                    if it["role"] == role:
                        it["role"] = full

    def full_name(self, role):
        import play_layouts as PL
        spoken = [r for r in self.n if r.startswith(role) and " " not in r and len(r) >= len(role) + 2]
        if len(spoken) == 1 and role not in ("THE", "HER"):
            return spoken[0]
        for kinds in ((("cast",), ("cast", "front"), ("cast", "front", "direction")) if role != "HER" else (("cast", "front", "direction"),)):
            cands = collections.Counter()
            for it in self.items:
                if it["kind"] in kinds and not it.get("gone"):
                    for w in re.findall(r"\b[A-ZÀ-Þ][A-Za-zÀ-ÿ]{3,}\b", it["source"]):
                        if w.upper().startswith(role) and len(w) > len(role) and w.lower() not in PL.NEVER and w.lower() not in NOT_NAMES:
                            cands[w.upper()] += 1
            one = {re.sub(r"(?<=.{4})(?:E?S|['’]S)$", "", w) for w in cands}
            if len(one) == 1:
                return max(cands, key=lambda w: (cands[w], len(w)))
            if cands:
                # a name in the cast list is a name; a capitalized word of a direction may open its sentence
                real = {w for w in cands if self.lower(w.lower()) == 0}
                return next(iter(real)) if len(real) == 1 else None
        return None

    # -- 11. a label misprinted once or twice ("MEPHISTOPIIELES", "LADT UTTERWORD") that is one part's, and no one else's
    def misprints(self):
        for role in [r for r in self.n if self.n[r] <= 4 and len(r.replace(" ", "")) >= (4 if self.n[r] == 1 else 5) and r not in self.castable]:
            if any(role in x["source"].upper() for x in self.items if x["kind"] == "cast") or self._is_part(role) \
                    or any(w.startswith(role) and w != role for w in self.names()):
                continue
            near = [b for b in self.castable if (b[:1] == role[:1] or len(b) == len(role) and self.n[role] == 1 and b[1:] == role[1:]) and abs(len(b) - len(role)) <= 1 and 0 < distance(b, role) <= (2 if len(role) >= 9 else 1)]
            if len(near) != 1:
                continue
            b = near[0]
            if self._printed_elsewhere(role) and not (len(role) >= 12 and distance(b, role) <= 2 and self.n[b] >= 10 * self.n[role] and role not in self.names()) or self.n[b] < (10 if self.n[role] > 2 else 5) * self.n[role] or b.startswith(role) or role.startswith(b) or re.sub(r"\bMRS?\b|\bMISS\b", "", b) == re.sub(r"\bMRS?\b|\bMISS\b", "", role) or re.search(r"\d|\bII?\b|\b[A-Z]$", role):
                continue
            for it in self.speech():
                if it["role"] == role:
                    it["role"] = b

    def _printed_elsewhere(self, role):
        """The name is printed somewhere that is not its own label."""
        own = sum(1 for it in self.speech() if it["role"] == role)
        return len(re.findall(r"(?<![A-Za-z])%s(?![A-Za-z])" % re.escape(role), self.flat(), re.I)) > own


def printed_in_capitals(it):
    m = re.match(r"^[\W_]*([A-Za-zÀ-ÿ]+)", it["source"])
    return bool(m) and m.group(1).isupper() and len(m.group(1)) > 1


def distance(a, b):
    """Edits (a letter changed, dropped, added, or two changed places) between two names."""
    d = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(len(a) + 1):
        for j in range(len(b) + 1):
            if not i or not j:
                d[i][j] = i + j
                continue
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] != b[j - 1]))
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
    return d[-1][-1]


COLLECTIVE = P.COLLECTIVE
YOU = re.compile(r"(?<![.\w])I(?![.\w])|\b(?:I'm|I'll|I've|I’m|I’ll|I’ve|me|my|we|us|our|you|your|yours|thou|thee|thy|ye)\b", re.I)
ETEXT_WORDS = re.compile(r"WORLD LIBRARY|ELECTRONIC AND MACHINE READABLE|PROHIBITED COMMERCIAL DISTRIBUTION|<<THIS ELECTRONIC VERSION|CARNEGIE MELLON|"
                         r"etext, when displayed|etext is readily convertible|copy of the etext")
NOTE_OPENS = re.compile(r"^\W{0,2}\[?_?(?:Footnotes?|FOOTNOTES?|Transcriber['’]?s? Notes?|TRANSCRIBER['’]?S? NOTES?)\b", re.I)
TAIL_ROLE = re.compile(r"^(?:NOTES?(?: TO .*| ON .*)?|P|PP|VOL|T\. S|BY MR|UNIFORM EDITION OF|PRICE \d+ CENTS|READING CLUB.*|GEO\. M\. BAKER'S|.* ACTING PLAYS|.* MODERN PLAYS|.* SERIES|"
                       r"VOCABULARY|ABBREVIATIONS|EXERCISES IN .*|COSTUMES?|PAGEANT DIRECTIONS|MALE CHARACTERS|FEMALE CHARACTERS|LATEST ISSUES|.*\bCOMPANY|ORIGINAL CAST|POST-SCRIPTUM|"
                       r"BOOKS ON .*|GENERAL LITERATURE|.* LIBRARY|IRISH TRADITIONAL AIRS|MUSIC FOR LYRICS|W\. B\. YEATS|LONDON|AYOT ST|POPULAR ENTERTAINMENT BOOKS|HAND BOOKS|SPECIALTIES|"
                       r".*'S CURE FOR BALDNESS|APPARENT ANACHRONISMS|TEATRO DE ENSUEÑO|NEIGHBOURS 1920|KRINDLESYKE|THE WORKS OF .*|THE NOVELS OF .*|THE PLAYS OF .*)$")
PRICED = re.compile(r"\b(?:Cloth|Paper),? (?:Gilt|Ornamental|\$|\d+ cents)|\b\d{1,2}mo\b|\b8vo\b|\bcents each\b|\b\d+ ?cents\b.*\bPrice\b|\b\d+s\.? ?(?:\d+d\.?)? net\b|\bnet each\b|\[postage|"
                    r"\$\s?\d+[ .]\d\d|comedy in \d acts?, by|\b\d+ males?, \d+ female|\bvaudeville sketch in \d act\b|^Price \d+ Cents|\b(?:in|In) (?:One|Two|Three|Four|\d) Acts?\. (?:One|Two|Three|Four|Five|Six|Seven|Eight|Ten|Twelve) (?:Females|Males|Characters)|\b\d+ ?m\., \d+ ?f\. Time|\b\d+ ?m\. Time \d|PUBLISHERS? NEW YORK")
PUBLISHED = re.compile(r"\bPrinted by\b|\bPublish|\bPrice\b|\bcr\. 8vo\b|_?Also\b|In preparation|\bnovels?\b|Uniform|By the same author", re.I)
FRONT_REACH = 12
FRONT_ROLE = re.compile(r"^(?:WITH REMARKS|REMARKS|EDINBURGH|LONDON|NEW YORK|A PLAY|A COMEDY|A TRAGEDY|A FARCE|EXITS AND ENTRANCES|RELATIVE POSITIONS|STAGE DIRECTIONS|HINTS ON PRESENTATION|"
                        r"DESCRIPTION OF CHARACTERS|PROPERTIES|INCIDENTAL PROPERTIES|COSTUMES?|ACTORVM NOMINA|THE ACTORS['’]? NAMES|FOREWORD|.* --?A (?:FARCE|PLAY|COMEDY)|.*--A (?:FARCE|PLAY|COMEDY)|"
                        r"BOOKS AND LYRICS BY|MUSIC BY|A MUSICAL COMEDY|LADIES|GENTLEMEN|OTHER .* STUDENTS)$")
LABEL_END = re.compile(r"^(?P<end>[A-ZÀ-Þ][A-Za-zÀ-ÿ'’]{0,11}(?:\._|_\.?|\.))\s*")
NOT_AN_END = frozenset("mr mrs dr miss i o ay no yes oh sir madam never ready friend yessir pass anon death scwumptious well come what stop go".split())
SIGNED_LETTER = re.compile(r"^[A-Z][\w .,']{2,40},? (?:January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}")
SIGNED = re.compile(r"^[\W_]*(?:January|February|March|April|May|June|July|August|September|October|November|December),? \d{0,2},? ?1[5-9]\d\d[\W_]*$")
SPOKEN_BY = re.compile(r"^(?:SPOKEN|SPOKE|WRITTEN)(?: AND SPOKEN)? BY (?P<who>.+)$")
TITLE_PAGE = re.compile(r"^(?:WILLIAM HEINEMANN|Printed (?:by|for) |B[Yy] (?:M(?:RS|R|ISS)\.? )?[A-Z]+\b|by [A-Z][a-z]+ [A-Z]\. [A-Z]|By the same Author|In \w+ Acts|A COMEDY IN|This play was produced|First produced)|"
                        r"^(?:[A-Z][a-z]+\.? )+(?:[A-Z]{3,}[ .]+)+(?:[A-Z]\.? ?[A-Za-z. ]+?)(?:[A-Z]{3,}[ .]+)+[A-Z][a-z]|^(?:MRS? |MISS )?[A-Z]+ [A-Z. ]{3,}(?:MR|MISS|MRS)\.? [A-Z]+ ")
CAST_ENTRY = re.compile(r"^(?:(?:The|A|An|His|Her|Their)\s)?(?:[\w-]+ )?(?:daughter|son|wife|brother|sister|husband|uncle|aunt|mother|father|cousin|friend|servant|maid|butler|Chief of|King of|Queen of|Prince of|Alias|"
                        r"professor and|lawyer|a lawyer|cook|host)\b(?!.*\b(?:is|was|are|has|had)\b.*[.!?].*[.!?])|^(?:About \d\d\.|Their son, aged)", re.I)
ENTRY_SHAPES = re.compile(r"^\W{0,3}(?:First Dress|Act I\.|Property of|Seedy clothes|Alias\b|THE SLAVE GIRL)|\b\d\d years old\b|^(?:Their|His|Her) \w+, \d\d\b|^[A-Z]\w+['’]s (?:daughter|son|wife|labourer|servant)\b|"
                          r"^[A-Z]{3,}(?: [A-Z]{2,})*, (?:[(\[]|_?(?:a|an|the|his|her|daughter|son|wife|lover|servant|sister|brother)\b)|^\[?(?:Two Troops|two female)|^(?:Traveling|Smart|White|Red|Gray|Calico|Light|Dark|Old)\b[^.!?]*\b(?:suit|hat|wig|"
                          r"costume|pants|dress|gown|clothes)\b|\bevening dress\b|^[A-Z]{4,}, his (?:Son|Daughter|Wife)|^(?:His Hind|Tailor, Haberdasher|Rustics)", re.I)
DRESSED = re.compile(r"\b(?:Silk dress|velvet mantle|house dress|court suit|tights|sweaters?|Raincoat|black cloak|Black face|costume|blouse|doublet|trunks)\b|^Wearing\b|^In \w+ (?:sweaters?|dress|cloaks?)|^An? (?:\w+ ){0,4}(?:woman|lady|dame)[,.]|^Boy of \d\d|^Girl of \d\d")
SUBTITLE = re.compile(r"^(?:OR,? (?:THE|A)\b[A-Z' ,-]+|[A-Z][A-Z ]+, &c)\W*$")
COSTUME = re.compile(r"\b(?:wig|beard|belt|boots|shirt|overalls|breeches|stockings|cravat|apron|gown|dress-suit)\b.*\b(?:wig|beard|belt|boots|shirt|overalls|breeches|stockings|cravat|apron|gown|hat|belt)\b")
NOT_A_LABEL = re.compile(r"^(?:Enter|Re-?enter|Exit|Exeunt|Scene|Act|Song|Curtain|Aside|Enters|Manet|To them|To him|To her|The same|Discovers|Discovered|Spoke|Recit|Yours|Note|N\.B|First Entry|Second Entry|Third Entry|"
                         r"Second Dumb|The second|A passage|Alarum|Flourish|Sennet|Trumpets?|Music|Drums?|Thunder|Knock|Tableau|Pause|Silence|Act[,.]? |Costumes?|Properties|Time|Place|Period|Duet|Trio|Air|Chorus of\b.* singing|"
                         r"Illustration|Footnote|Dated|London|Paris|January|February|March \d|April|May \d|June|July|August|September|October|November|December|P\.S|And|But|Or|For|With|In|On|At|From)\b", re.I)
CAPS_INSIDE = re.compile(r"(?<=[.!?”\"’\-—])\s+(?P<label>(?P<who>[A-Z][A-Z'’]{2,}(?: [A-Z][A-Z'’.]+){0,2})[.:])\s+(?=[A-Z“\"'‘])")
FOLDED = re.compile(r"^[{}|\s]*(?:(?P<hon>Mrs?|Sir|Lady)\.? (?=_))?(?P<i>_)?(?:(?P<num>(?:[1-9]|1st|2nd|2d|3rd|3d|4th|1ST|2ND|2D|3RD|3D|4TH|First|Second|Third)\.? [A-ZÀ-Þ][A-Za-zÀ-ÿ]{2,14})|(?P<name>(?:[A-ZÀ-Þ][A-Za-zÀ-ÿ'’]{1,14}\.? ?){1,2}?))(?(num)(?:\.|:|(?=\s*[(\[])|(?(i)(?=_)|(?!)))|(?:\.|:|(?=\s*[(\[])|(?(i)(?=_)|(?!))))(?(i)_)[.:]?\s*(?P<text>(?<=[\s_])[A-ZÀ-Þ'‘’“\"—-].*|[(\[].*)$", re.S)
FOLDED_OWN = re.compile(r"^_?(?P<num>(?:[1-9]|1st|2nd|2d|3rd|3d|4th|5th|6th|1ST|2ND|2D|3RD|3D|4TH)\.? [A-ZÀ-Þ][A-Za-zÀ-ÿ]{2,14})\.?_?\s*(?P<d>\[[^\]]*\]|\([^)]*\))?\.?$")
WORDS = frozenset("CERTAINLY THANKS NONSENSE NOTHING SURE AYE AY H'M HEE-HEE GOOD CEASE READING NEXT LOOK SILENCE BLESSINGS ME DESIRES INVISIBLE WHO PROSE KIN".split()) - {"READING", "NEXT", "SILENCE", "PROSE", "KIN", "LOOK", "WHO"}
LIST_LINES = frozenset(["BLESSINGS", "ME", "DESIRES", "INVISIBLE", "UNTO TRUE SOLDIERS", "FAUSTUS GIVES TO THEE HIS SOUL"])
_ROM = r"(?:[IVX]+|ONE|TWO|THREE|FOUR|FIVE)"
NEVER_A_PART = re.compile(r"^(?:ACT(?:US)? .*|SC[EÆ]N(?:A|E)?\.? (?:%s|PRIMA|SECUNDA)\b.*|STAVE %s|DIALOGUE %s|(?:FIRST|SECOND|THIRD|FOURTH|FIFTH|SIXTH) (?:INTERLUDE|MASQUE|SCENE|ACT)|THE (?:FIRST|SECOND|THIRD) (?:MASQUE|ACT|SCENE|DUMB[ -]SHOW)|"
                          r".*--ACT %s|(?:TOINEN|KOLMAS|NELJÄS) NÄYTÖS|SETTING|ACTION|THE (?:PLEASANT )?(?:TRAGEDY|MASSACRE|COMEDY)(?: OF| AT)?.*|SCENERY|THE SCENE|DESCRIPTION OF .*|MUSICAL INDUCTION|A? ?DUMB-?\s?SHOW|(?:VERY )?(?:SLOW|QUICK) CURTAIN|THE CURTAIN .*|QUICK CURTAIN|"
                          r"WHEN THE CURTAIN RISES|DISCOVERED|CENTER|R\. U\. E|SITUATION|N\. B|SIGNAL NO|MELODY NO|THUNDER AND LIGHTNING|A DANCE|SWELL MUSIC|FULL STAGE SCENE|SAME (?:SET|SCENE)|THE SAME (?:AFTERNOON|EVENING)|THE NEXT (?:MORNING|DAY)|"
                          r"INTERIOR OF .*|HALL OF .*|THE ACTORS['’]? NAMES|ACTORVM NOMINA|STORY OF THE PLAY|TO THE READER|POST-SCRIPTUM|A CONFERENCE|HORACE AND TREBATIUS|COMMENDATORY VERSES|TO HIS FRIEND MR|INTENDED FOR VORTIGERN|THE ACROSTIC ARGUMENT|(?:THE )?ARGUMENT|RECREATION SONG|MOTIONS|VARIATION|AFTERMATH|ERECTED|MEASURE|AFTER THE THEATRE|MARKET PLACE AT .*|BEFORE (?:THE )?.*|EXITS AND ENTRANCES|"
                          r"RELATIVE POSITIONS|THE DECAY OF LYING|THE CRITIC AS ARTIST|A DIALOGUE|DIALOGUE IN MUSIC|FOREWORD|NOTE|NOTES|MORNING|EVENING|AFTERNOON|NOON|FURTHER APOLOGY|THE DEACON DINING ROOM|THE PIANO STORE)$" % (_ROM, _ROM, _ROM, _ROM))
PLACE_ROLE = re.compile(r"^(?:(?:A|AN|THE|ANOTHER|IN|AT|ON|BEFORE|NEAR|OUTSIDE|INSIDE|SAME)\s)?(?:[\w'’.-]+\s){0,4}?(?:ROOM|HALL|STREET|GARDEN|HOUSE|FOREST|CASTLE|PALACE|CHAMBER|APARTMENT|LODGINGS|STUDY|CHURCH|PRISON|GAOL|"
                        r"DUNGEON|CELLAR|KITCHEN|SQUARE|ROAD|FIELD|CAMP|GATE|MARKET-?\s?PLACE|MANSION|MILL|MINE|CATHEDRAL|PROMENADE|SUMMER-HOUSE|WELL|SETTEE|MOUNTAINS|WASTE|TOWN)(?:\s(?:AT|OF|IN|BEFORE|ON)\s.*)?$")
OPENS_SCENE = re.compile(r"^(?:SCENE|Scene|Same scene|SAME SCENE|The scene|THE scene|The Scene|Enter\b|ENTER\b|Re-?enter\b|At rise|At Rise|The curtain|The stage|Interior|Part of (?:a|the)|A (?:parlor|room|street|wood|garden|prison|"
                         r"pavilion|dell|glen|terrace|ring|simply|luxuriously|DarkChamber|Dark ?Chamber)|The (?:glen|terrace|same (?:scene|room|place|glen|as)|dark (?:room|chamber))|Before the|On the (?:terrace|mountains)|Turret|Same room|Opposite a|In a First-class|discovered\b|"
                         r"IT IS NIGHT|NIGHT$|THE interior|At Worcester|The train stops|Drum within)(?![a-z])")
PLACE_NAMES = re.compile(r"^(?:LONDON|FRANCE|ENGLAND|SCOTLAND|VENICE|ROME|WARKWORTH|GLOUCESTERSHIRE|WESTMINSTER|ANGIERS|CARTHAGE|CAIRO|PARIS|BELMONT|PADUA|VERONA|MANTUA|ATHENS|CYPRUS|EPHESUS|MILAN|NAPLES|FLORENCE|"
                         r"YORK|ROUEN|ROUSILLON|ELSINORE|INVERNESS|FORRES|MESSINA|SICILIA|BOHEMIA|TYRE|TARSUS|ANTIOCH|PENTAPOLIS|MYTILENE|ALEXANDRIA|MISENUM|SARDIS|PHILIPPI|TROY|WINDSOR|VIENNA|BRITAIN|CORIOLI|ANTIUM)$")
SONG_ROLE = re.compile(r"^(?P<form>(?:AIR|SONG|BALLAD|ARIA|RECIT(?:ATIVE)?|ROMANCE|DUETT?|TRIO)(?: [IVXLC]+)?)(?P<who>(?:(?:\.?--| )|\.?-)(?P<w>.+))?$")
ROMAN = re.compile(r"^(?=[IVXL])(?:XC|XL|L?X{0,3})(?:IX|IV|V?I{0,3})$")
HEADING_WORD = re.compile(r"^(?:Act|Scene|Part|Stanza|Verse|Voice of|Edition|Set|Dress|Costume)$", re.I)
SETTING = re.compile(r"\b(?:room|rooms|stage|scene|curtain|door|table|enters?|discovered|discover|left|right|opposite|compartment|walk|house|saloon|years later|flies towards|horror|corridor|garden|drawing-room|moonlight|reception|passageways|"
                     r"following|seen|corner|kitchen-garden|conversation|characters|amber boudoir|from [“\"]|the door slams)\b|^_?From\b", re.I)
VARIANTS = re.compile(r"^(?:VERSE AND PROSE VARIATIONS|ll?\. \d+[.,\s–-]|pp?\. ?\d+, ?ll?\.|(?:[A-G], )*[A-G]\] )")
COSTUMES_AFTER = re.compile(r"^(?:Costumes? of|[A-Z][\w ,'’-]{0,60}\b(?:suit|doublet|shirt|trousers|coat|hat|gown|dress|hair|wig|green|blue|yellow|brown)\b)", re.I)
VARIANT_IN = re.compile(r"\bl\. \d+\. (?:[A-G](?:,| and|\])|2nd folio|C\b)")
NARRATED = re.compile(r"\bmust be the scene\b|\bsitting-?\s?room\b|\bThe scene (?:is|represents)\b|\bA Little Comedy\b|\bthe stage (?:is|represents)\b|^ACT I\b|^(?:Numerous|For Miss Calcium)\b|^A Little Comedy|\bwas (?:acted|published|entered)\b", re.I)
ACTION_LABEL = re.compile(r"\b(?:is|has|have|are|opens|closes|comes|goes|stops|turns|sounds?|pause|knock|music|falls|rises|above|stage|arm-chairs|invocation|solo)\b", re.I)
WORN = re.compile(r"\b(?:dress|coat|gown|shawl|waistcoat|breeches|bonnet|grey and black)\b", re.I)
NOT_NAMES = frozenset("notes therefore thereupon another herself himself nothing notice noted andirons butter button artists area arena heroes heroine".split())
STANZA = re.compile(r"^[IVX]+(?:\. \d)?$")
FUNCTION = frozenset("THE AN AND BUT NOT ARE IS WHO OR DO AS IN ON TO DE BE IF SO HER ALL ANY CAN MAY ONE OUR OUT NOW TOO FOR".split()) - {"ALL", "ONE"}
