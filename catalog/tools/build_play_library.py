"""Build the play library published beside the catalog (Decision 075): every Project
Gutenberg play whose rights are castable AND whose text parses clean, as an index plus
one script file per play. Nothing here writes a word; each script is the parser's exact
slices (build_castable_scripts.script_entry), so a play the apps already bundle comes out
here with the same id and revision (and the same entry as a fresh bundle build; the shipped
bundle predates `sections`, Decision 076 S0).

    python3 tools/harvest_gutenberg_plays.py --rsync-castable   # caches every cleared text
    python3 tools/build_play_library.py                         # writes out/plays-library/
    python3 tools/build_play_library.py --check                 # build in memory, write nothing, print the report
    python3 tools/build_play_library.py --no-phonemes           # skip the phoneme step (not publishable)

Output (catalog/out/plays-library/, served at <site>/data/plays/library/):
    index.json              one row per play; the shelf Record browses
    scripts/<id>.json       {"format": 1, "scripts": [<one script entry>]}: the same shape as
                            plays/castable-scripts.json, so one decoder reads both
    phonemes/<id>.json      each speech line's phonemes for the Kokoro voices, written by
                            build_play_phonemes.py in catalog/.venv-phonemes (Decision 078)

The id is the record's own (`gut-<Gutenberg ebook number>`), never reissued; a script whose
text changes keeps its id and gets a new `revision`. A play split out of a collected volume is
`gut-<ebook>-<n>`, n counting every play the volume holds in text order (script_parse.split_volume).
The same work under several ids is kept once (dedupe); every drop is listed in the report.

A text the first reader (script_parse.parse) does not read clean is read again by its layout (play_layouts,
BACKLOG-LOOP B16). The first reader's plays are settled first and alone: a second-reader play never changes,
replaces or renumbers one of them. A play found through a volume's contents list is `gut-<ebook>-<100 + n>`, n its place
among the listed titles, so it never takes a number split_volume gave. What is still held is listed, with its reason and, for a
text that is not a play, the evidence, in held.json beside the index (not in the index, which phones load).
"""
import collections
import datetime
import gzip
import json
import math
import os
import re
import shutil
import subprocess
import sys
import zlib

sys.path.insert(0, os.path.dirname(__file__))
import build_castable_scripts as B
import play_layouts as PL
import script_parse as P
import script_rights as R

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out", "plays-library")
BUNDLE = os.path.join(HERE, "..", "plays", "castable-scripts.json")
FORMAT = 1
WORDS_PER_MINUTE = 150


def failure_reason(rights, parsed):
    """Why a rights-cleared text is not in the library: one reason, the first that applies."""
    if not rights["castable"]:
        return "rights_" + rights["bucket"]
    if parsed.get("status") == "stub":
        return "stub_" + parsed.get("stub_kind", "?")
    if parsed.get("status") != "parsed":
        return "parse_" + ",".join(parsed.get("issues") or [parsed.get("status", "?")])
    for issue in ("several_plays_in_one_text", "fewer_than_two_castable_roles", "mostly_set_aside",
                  "unclassified_over_5pct", "role_only_before_play"):
        if issue in parsed["issues"]:
            return "unclean_" + issue
    return "unclean_other"


def title_unusable(entry):
    """A title cut off by the record's own punctuation ("The", "The Collected Works of") names no play,
    nor does the name of a volume ("Hecuba and other plays") shown as if it were one play."""
    words = entry["title"].lower().split()
    if VOLUME_TITLE.search(entry["title"]):
        return True
    return not words or words[-1] in B.SMALL or (len(words) == 1 and "collection" in entry and words[0] in B.SMALL)


NOT_A_TITLE = re.compile(r"\b(PRINTERS?|PUBLISHERS?|LTD|COPYRIGHT|CONTENTS|ILLUSTRATIONS?|CURTAIN|FINIS|LITERATURE|"
                         r"DISPOSITION|SCENE)\b|^[IVXL]+[.\s]|^(THE|A|AN|BY)$|^OR\b")
VOLUME_TITLE = re.compile(r"\b(Works|Volume|Vol\.|Collection|Plays|Dramas|Farces|Comediettas|Tragedies|Comedies|Representative)\b|"
                          r"\band other\b|\[", re.I)


def volume_play_title(title, record):
    """The title a volume prints above a play, cased for a list, or None when it names no play: a
    bare article, a section or publisher line, a roman-numeral heading, or the name of the volume's
    author or translator (a half-title page, not a play)."""
    if not title:
        return None
    printed = title.strip(" ;:,.")
    if not printed or NOT_A_TITLE.search(printed):
        return None
    names = set()
    for who in (record.get("authors") or []) + (record.get("translators") or []):
        for tok in re.split(r"[\s,()]+", who.get("name") or ""):
            if len(tok) > 2:
                names.add(tok.upper().strip("."))
    words = [w.strip(".,;:") for w in printed.upper().split()]
    if names and sum(w in names for w in words) >= max(1, len(words) - 1):
        return None
    return B.cased_title(printed)


def is_volume(raw, record):
    """A text the whole-text parse passed as one play that is really a volume: two or more of the plays
    split_volume finds each parse clean under a printed title."""
    segs = P.split_volume(raw)
    if len(segs) < 2:
        return False
    whole = 0
    for _, title, text in segs:
        if volume_play_title(title, record) and P.parse(text, "stage", title).get("clean"):
            whole += 1
            if whole == 2:
                return True
    return False


BARE_HONORIFIC = re.compile(r"^(MRS?|MISS|MS|DR|ST|MME|MLLE)\.?$")
HEADING_ROLE = re.compile(r"^(THE (SUBJECT|SUMMARY|ARGUMENT)\b|(ANTI)?STROPHE\b|EPODE\b|TABLEAU\b|DIALOGUE$|(FIRST|SECOND|THIRD|FOURTH|FIFTH) (SCENE|ACT)$)")


def role_artifact(entry):
    """A role the parser read out of something that is not a speaker: a bare honorific (a cast list's
    "MRS. CRILLY" split at the period), the play's own title, a translator's heading, or a chorus
    or tableau marker. Names it, or None. "DR." with a castable part is the Doctor speaking (gut-70635-5)."""
    title = entry["title"].upper().strip(" .")
    for r in entry["roles"]:
        name = r["name"].upper().strip(" .")
        if (BARE_HONORIFIC.match(name) and not (name.startswith("DR") and r["lines"] >= P.CASTABLE_LINES)) \
                or HEADING_ROLE.match(name):
            return r["name"]
        if (name == title or name == "THE " + title) and r["lines"] < P.CASTABLE_LINES:
            return r["name"]
    return None


def volume_entries(record, rights, raw, report):
    """The plays of a collected volume that parse clean, as script entries `gut-<ebook>-<n>`. Only a
    volume with one named author is split (the volume's author is each play's author; an anthology
    does not say which of its authors wrote which). Rights are the volume's own evidence."""
    if len(record.get("authors") or []) != 1:
        report["volumes_held_not_one_author"] = report.get("volumes_held_not_one_author", 0) + 1
        return []
    out = []
    for n, title, text in P.split_volume(raw):
        report["split_segments"] = report.get("split_segments", 0) + 1
        parsed = P.parse(text, "stage", title)
        why = None
        printed = volume_play_title(title, record)
        if parsed.get("status") != "parsed":
            why = "split_not_a_play"
        elif not printed:
            why = "split_no_printed_title"
        elif not B.offered(rights, parsed):
            why = "split_" + failure_reason(rights, parsed)
        if why:
            report["split_failures"][why] = report["split_failures"].get(why, 0) + 1
            continue
        entry = B.script_entry({**record, "id": f"{record['id']}-{n}"}, rights, parsed)
        entry["collection"] = B.clean_title(record["title"])
        entry["title"] = B.clean_title(printed)
        entry["sort_name"] = B.sort_name(entry["title"])
        if role_artifact(entry):
            report["split_failures"]["split_role_artifact"] = report["split_failures"].get("split_role_artifact", 0) + 1
            continue
        if title_unusable(entry):
            report["split_failures"]["split_title_cut_off_or_a_volume"] = report["split_failures"].get(
                "split_title_cut_off_or_a_volume", 0) + 1
            continue
        out.append(entry)
    return out


SHINGLE, SAMPLE = 5, 4
SAME_WORK = 0.55
SIMILAR_SIZE = 0.4
SAME_TITLE_AND_AUTHOR = 0.2


def shingles(entry):
    words = []
    for l in entry["lines"]:
        if l["kind"] == "speech":
            words += re.findall(r"[a-z0-9']+", " ".join(p["say"] for p in l["parts"] if "say" in p).lower())
    return {h for h in (zlib.crc32(" ".join(words[i:i + SHINGLE]).encode()) for i in range(len(words) - SHINGLE + 1))
            if h % SAMPLE == 0}


def work_key(entry):
    title = re.split(r"[;:]| or,? ", entry["title"].lower())[0]
    title = re.sub(r"^(the|a|an)\s+", "", re.sub(r"[^a-z0-9 ]", "", title)).strip()
    return title, tuple(sorted(a["name"] for a in entry["authors"] if a.get("name")))


def edition(entry):
    """How well a text of a play keeps it, in quarters so that two good texts tie (higher is better):
    (speeches whose speaker is a full name, speeches that keep their verse lines). A speaker is abbreviated when a direction prints a longer
    name it starts ("HAM" beside "Enter Hamlet"); verse lines are kept when a speech holds a line break.
    A Folio text (gut-2265 Hamlet: "Bar."/"Barn.", every speech run onto one line) scores below a modern
    edition (gut-1524) of the same play."""
    printed = set()
    for l in entry["lines"]:
        if l["kind"] == "direction":
            printed.update(w.upper() for w in re.findall(r"\b[A-ZÀ-Þ][A-Za-zÀ-ÿ]{2,}\b", l.get("source") or ""))
    speech = [l for l in entry["lines"] if l["kind"] == "speech"]
    if not speech:
        return (0, 0)
    short = {r["name"] for r in entry["roles"] if " " not in r["name"]
             and any(w.startswith(r["name"]) and len(w) >= len(r["name"]) + 2 for w in printed)}
    full = sum(l["role"] not in short for l in speech) / len(speech)
    verse = sum(any("\n" in p.get("say", "") for p in l["parts"]) for l in speech) / len(speech)
    return (int(full * 4), int(verse * 4))


def prefer(entry, protect):
    """Higher wins: a bundled play (never reissued), then the better edition (full speaker names, then
    verse lines kept: `edition`), then a single-play text over a volume's play, then the fuller cast list,
    then the longer text, then the lower ebook number."""
    voices = sum(1 for r in entry["roles"] if r["lines"] >= P.CASTABLE_LINES)
    words = sum(r["words"] for r in entry["roles"])
    ebook = [int(x) for x in entry["id"][4:].split("-")]
    return (entry["id"] in protect, edition(entry), "collection" not in entry or entry["id"][4:].isdigit(), voices, words,
            [-x for x in ebook])


def dedupe(entries, protect=()):
    """One entry per work. Entries are taken best first (see prefer) and one is dropped when it is the
    same work as an entry already kept: its spoken text overlaps the kept one's by at least SAME_WORK of
    the smaller (5-word shingles, sampled), or by SAME_TITLE_AND_AUTHOR when the normalized title and
    the authors also match (two editors' texts of one play share about a third of their shingles).
    Texts of very different length are never the same work, so a bundle never swallows its plays.
    Returns (kept, rows for the report, same title and author with different text: reported, kept)."""
    sh = {e["id"]: shingles(e) for e in entries}
    keyed = {e["id"]: work_key(e) for e in entries}
    by_hash = collections.defaultdict(list)
    for eid in sorted(sh):
        for h in sh[eid]:
            by_hash[h].append(eid)
    common = collections.Counter()
    for ids in by_hash.values():
        for i, x in enumerate(ids):
            for y in ids[i + 1:]:
                common[(x, y)] += 1
    near = collections.defaultdict(dict)
    for (x, y), n in sorted(common.items()):
        small, big = sorted((len(sh[x]), len(sh[y])))
        c = n / max(1, small)
        if small / max(1, big) >= SIMILAR_SIZE and (c >= SAME_WORK or (
                c >= SAME_TITLE_AND_AUTHOR and keyed[x] == keyed[y] and keyed[x][1])):
            near[x][y] = near[y][x] = round(c, 3)
    kept, rows, kept_ids = [], [], set()
    for e in sorted(entries, key=lambda e: prefer(e, protect), reverse=True):
        hit = sorted((k for k in near[e["id"]] if k in kept_ids), key=lambda k: -near[e["id"]][k])
        if not hit:
            kept.append(e)
            kept_ids.add(e["id"])
            continue
        k = next(x for x in kept if x["id"] == hit[0])
        rows.append({"kept": k["id"], "dropped": e["id"], "title": e["title"], "kept_title": k["title"],
                     "overlap": near[e["id"]][k["id"]],
                     "reason": "same work; kept " + ("the bundled play" if k["id"] in protect else
                               "the better edition (full speaker names, verse lines)" if edition(k) > edition(e)
                               else "the single-play text" if "collection" in e and "collection" not in k
                               else "the fuller cast and text")})
    rows.sort(key=lambda r: (r["kept"], r["dropped"]))
    keys = collections.defaultdict(list)
    for e in kept:
        keys[keyed[e["id"]]].append(e["id"])
    shared = [sorted(ids) for k, ids in sorted(keys.items()) if len(ids) > 1 and k[1]]
    return kept, rows, shared


OPENING_SPEECHES = 2
OPENING_CHARS = 90


def is_verse(said):
    """js/reader-core.js isVerse: printed breaks are verse when every row after one opens in a capital and the rows are
    not mostly as long as a wrapped prose line."""
    rows = [r.strip() for r in said.replace("_", "").split("\n") if r.strip()]
    if len(rows) < 2 or any(not re.match(r"[\s'\"‘’“”(\[_—–-]*[A-ZÀ-ÞŒ]", r) for r in rows[1:]):
        return False
    body = rows[:-1]
    return sum(len(r) >= 60 for r in body) < 0.7 * len(body) and (len(rows) >= 3 or len(rows[0]) < 50)


def opening_of(entry):
    """The play's first speeches as {role, text}: its own said words, cut at a word near OPENING_CHARS.

    A play tile shows them in its window (WEB-DESIGN §4.15) so a list reads as scripts, without
    fetching any (Decision 075). Printed italic marks, a speaker's
    stray stop left at the front (". Come quickly") and repeated whitespace are dropped;
    a printed double hyphen reads as the dash it stands for."""
    out = []
    for line in entry["lines"]:
        if line["kind"] != "speech":
            continue
        said = " ".join(p["say"] for p in line.get("parts", []) if "say" in p)
        # a verse speech keeps its rows, as the reader does
        said = re.sub(r"[^\S\n]+", " ", said.replace("_", "")) if is_verse(said) else re.sub(r"\s+", " ", said.replace("_", ""))
        said = re.sub(r" ?\n\s*", "\n", said).strip().lstrip(".,:;\u2014- ").strip().replace("--", "\u2014")
        if not said:
            continue
        if len(said) > OPENING_CHARS:
            cut = said[:OPENING_CHARS + 1]
            cut = cut[:max(cut.rfind(" "), cut.rfind("\n"))] if re.search(r"\s", cut) else cut[:OPENING_CHARS]
            said = cut.rstrip(" ,;:-—") + "…"
        out.append({"role": line.get("role", ""), "text": said})
        if len(out) == OPENING_SPEECHES:
            break
    return out


def index_row(entry):
    voices = sum(1 for r in entry["roles"] if r["lines"] >= P.CASTABLE_LINES)
    words = sum(r["words"] for r in entry["roles"])
    row = {
        "id": entry["id"],
        "revision": entry["revision"],
        "title": entry["title"],
        "sort_name": entry["sort_name"],
        "kind": entry["kind"],
        "authors": [a["display"] for a in entry["authors"] if a.get("display")],
        "voices": voices,
        "roles": len(entry["roles"]),
        # Each named role's speeches, largest first: the cast window and fingerprint a list draws
        # without fetching the script (Decision 076, WEB-DESIGN §4.15).
        "cast": sorted((r["lines"] for r in entry["roles"]), reverse=True),
        "lines": sum(1 for l in entry["lines"] if l["kind"] == "speech"),
        "words": words,
        "minutes": max(1, math.ceil(words / WORDS_PER_MINUTE)),
        "opening": opening_of(entry),
        "rights": entry["rights"],
        "source": entry["source"],
        "path": f"scripts/{entry['id']}.json",
    }
    if "year" in entry:
        row["year"] = entry["year"]
    if "collection" in entry:
        row["collection"] = entry["collection"]
    return row


def script_file(entry):
    return {"format": FORMAT, "scripts": [entry]}


NOT_PLAY_SUBJECT = re.compile(r"-- (?:Periodicals|History and criticism|Biography|Criticism|Stage history|Indexes|Catalogs|Technique|Criticism and interpretation|Correspondence|"
                              r"Dictionaries|Bibliography|Stories, plots, etc\.|Anecdotes|Readers)|^(?:Indexes|AP|Motion pictures|Short stories|Theater|Actors|Acting|Playwriting|Copyright)\b|"
                              r"^(?:Actors|Actresses|Theaters?|Theatrical|Dramatists)\b|\bfiction$|-- Fiction$|Juvenile fiction|Encyclopedias|Vaudeville$|-- Characters$|-- Knowledge\b|syllabi|Prose poems$|Study and teaching", re.I)
PLAY_SUBJECT = re.compile(r"-- Drama\b|\bdrama\b(?!.*(?:History and criticism|Technique|Bio|Period))|\bplays\b|Tragedies|Comed(?:y|ies)|Farces|Librettos|Masques|Pageants|Dialogues|Interludes|Monologues|"
                          r"Entertainments|Operas$|Tableaux", re.I)
PERIODICAL = re.compile(r"\b(?:Punch|Punchinello|Magazine|Review|Journal|Mirror of|Poet-Lore|Monthly|Mercury|Messenger|Harper's|Strand|Galaxy|Fly Leaf|Index of the Project Gutenberg|Encyclop)", re.I)


# Printed over a play, but not the name of one (second reader only; the first reader's titles stay as published).
NOT_THE_TITLE = re.compile(r"^(?:A |AN |THE )?(?:COMEDY|TRAGEDY|DRAMA|FARCE|PLAY|MASQUE|PERSON(?:AE|S|NAE)|PERSONAGES|ACT\w*\s+[IVX]+|APPENDI\w+|CAST\b.*|CHORUS.*|ARGUMENT|HISTORIES|COMEDIES|TRAGEDIES|LIBRETTO|"
                           r"FRAGMENTS?|WOMEN|MEN|PRELUDE.*|PROLOGUE.*|EPILOGUE.*|KY\wGEN|[IVX]{3,}I*|(?:FIRST|SECOND|THIRD|FOURTH|FIFTH|LAST)\s+(?:INTERLUDE|GLIMMER|EPISODE|PART|SCENE|ACT|DAY|NIGHT).*|"
                           r"AN OUTLINE.*|OUTLINE.*|TAKEN FROM.*|ATTRIBUTED.*|FROM THE .*|AN OPERATIC BURLESQUE|.*\bLIBRARY|.*\bSERIES|.*\bEDITION|.*\bPRESS|MASQUE STRUCTURE|A STUDY\b.*|"
                           r"EPIGRAMS.*|.*\bIN (?:ONE|TWO|THREE|FOUR|FIVE) ACTS?|SYNOPSIS.*|DIALOGUES?|MONOLOGUES?|RECITATIONS?|EXERCISES?|PAGEANTS?|NAMES?\b.*|PART\b.*|VOLUME.*|"
                           r"ORIGINAL CAST.*|MODERN\b.*|DRAMATI\w+|SPEAKERS?|PUPPETS?|TABLEAUX?|SCENES?|SETTING|PLACE|TIME|POEMS\b.*|SELECTIONS\b.*|.*\bREAD-ALOUD PLAYS)$", re.I)
# Second-reader plays held after a read against the source found a fault no test catches yet (2026-11-24).
READ_AND_HELD = {"gut-40559": "a parallel text: the same speeches in Spanish and Nahuatl and in English",
                 "gut-35389": "a picture's caption is read as its first two speeches",
                 "gut-47609-106": "a heading (THE WIGWAM) is read as a speaker"}
ANTHOLOGY = re.compile(r"Collection of Old English Plays|\bAnthology\b|\bMasterpieces\b|German Classics|World's Greatest|\bLibrary of\b|Plays by Modern Authors|"
                       r"Contemporary One-Act|Modern Plays|Old Miracle|\bReadings\b|St\. Nicholas Book", re.I)


def good_case(title):
    """The case B.cased_title loses: a roman numeral, "Mc", the first letter after a quotation mark."""
    title = re.sub(r"\b(?=[IVXivx]{2,}\b)((?:[Xx]{0,2})(?:[Ii][Xx]|[Ii][Vv]|[Vv]?[Ii]{0,3}))\b", lambda m: m.group(1).upper() if m.group(1) else m.group(0), title)
    title = re.sub(r"\bMc([a-z])", lambda m: "Mc" + m.group(1).upper(), title)
    return re.sub(r"([“\"‘]|(?<=\s)')([a-z])", lambda m: m.group(1) + m.group(2).upper(), title)


def title_speaks(entry):
    """A running title read as a speaker ("A CHRISTMAS TALE", 14 lines of gut-61613)."""
    key = P._title_key(entry["title"])
    return len(key.split()) >= 2 and any(P._title_key(r["name"]) == key for r in entry["roles"])


def second_title(title, record):
    printed = volume_play_title(title, record)
    if not printed or NOT_THE_TITLE.match(printed.strip(" .,;:")) or len(printed) > 90:
        return None
    return B.clean_title(good_case(printed if title.upper() == title else title.strip(" ;:,.")))


def surname(name):
    name = re.sub(r"\s*\([^)]*\)", "", name or "")
    return (name.split(",")[0] if "," in name else name.split()[-1] if name.split() else "").upper().strip(" .")


def named_authors(record):
    return [a for a in record.get("authors") or [] if (a.get("name") or "").lower() not in ("various", "anonymous", "unknown", "")]


def not_a_play(record, subjects, speech_share):
    """The evidence that a held text is not a play, or None: what the record calls it, or how little of it is speech."""
    if PERIODICAL.search(record["title"]):
        return f"a periodical or an index by its title: {record['title'][:80]!r}"
    plays = [x for x in subjects if PLAY_SUBJECT.search(x) and not NOT_PLAY_SUBJECT.search(x)]
    other = [x for x in subjects if NOT_PLAY_SUBJECT.search(x)]
    if other and not plays:
        return f"Gutenberg subject: {other[0]!r}"
    if speech_share is not None and speech_share < 0.25:
        return f"labeled speech is {speech_share:.0%} of its words"
    return None


def monologue(parsed):
    """One speaking part, read clean but for that. Held as its own class: check_play_library asks two voices, and the
    parse's clean test two parts of five lines; no client asks for two ("1 voice" is set on every platform)."""
    return parsed.get("status") == "parsed" and parsed["castable_roles"] == 1 and parsed["issues"] in (
        ["fewer_than_two_castable_roles"], ["fewer_than_two_castable_roles", "possible_aliases"]) \
        and max(r["lines"] for r in parsed["roles"]) >= 0.8 * sum(r["lines"] for r in parsed["roles"])


def joint_authors(plays):
    """Author pairs that wrote together by the record: two or more records name exactly those two."""
    n = collections.Counter(tuple(sorted(a["name"] for a in p.get("authors") or [])) for p in plays)
    return {k for k, c in n.items() if len(k) == 2 and c >= 2}


def second_whole(record, rights, text):
    """(entry, why held): the whole text as one play, by its layout."""
    parsed = PL.parse(text, record.get("title"))
    if not parsed or parsed.get("status") != "parsed":
        return None, "format_unrecognized", None
    if not B.offered(rights, parsed):
        return None, next((i for i in parsed["issues"] if i not in ("possible_aliases",)), "unclean"), parsed
    entry = B.script_entry(record, rights, parsed)
    if VOLUME_TITLE.search(record["title"]):
        printed = second_title(parsed.get("printed_title"), record) if parsed.get("printed_title") else None
        if printed:
            entry["collection"] = B.clean_title(record["title"])
            entry["title"] = printed
            entry["sort_name"] = B.sort_name(entry["title"])
    if title_unusable(entry) or NOT_THE_TITLE.match(entry["title"]):
        return None, "title_cut_off", parsed
    if role_artifact(entry) or title_speaks(entry):
        return None, "role_artifact", parsed
    return entry, None, parsed


def second_volume(record, rights, text, have, joint, held, report):
    """The plays of a volume the first reader left: those its contents list names (numbered from 101), then the segments
    split_volume found, read by their layout. `have` holds the volume's entries already kept; a play among them is not added."""
    authors = named_authors(record)
    team = not ANTHOLOGY.search(record["title"]) and len(authors) == 1 or tuple(sorted(a["name"] for a in authors)) in joint
    sh = [shingles(e) for e in have]
    out = []

    def add(n, title, text, who, how):
        printed = second_title(title, record) if title else None
        row = {"id": f"{record['id']}-{n}", "title": title}
        parsed = PL.parse(text, title) or {}
        layout = parsed.get("layout")
        if parsed.get("status") != "parsed":
            # a heading of the volume with no dialogue under it is not a held play
            report["volume_parts_without_dialogue"] = report.get("volume_parts_without_dialogue", 0) + 1
            return
        if not B.offered(rights, parsed):
            held.append({**row, "why": next((i for i in parsed.get("issues") or [] if i != "possible_aliases"), "unread")})
            return
        if not printed:
            held.append({**row, "why": "no_printed_title"})
            return
        if not team and not who:
            held.append({**row, "why": "author_not_printed"})
            return
        if team and who and len(authors) == 1 and surname(who) not in {surname(a["name"]) for a in authors}:
            held.append({**row, "why": "another_author_printed"})
            return
        entry = B.script_entry({**record, "id": f"{record['id']}-{n}", **({} if team else {"authors": [{"name": who}]})}, rights, parsed)
        entry["collection"] = B.clean_title(record["title"])
        entry["title"] = printed
        entry["sort_name"] = B.sort_name(entry["title"])
        if role_artifact(entry) or title_speaks(entry) or title_unusable(entry):
            held.append({**row, "why": "title_cut_off" if title_unusable(entry) else "role_artifact"})
            return
        mine = shingles(entry)
        if any(len(mine & x) >= SAME_WORK * max(1, min(len(mine), len(x))) for x in sh):
            return
        sh.append(mine)
        entry["_how"] = layout or "contents"
        out.append(entry)

    for n, title, who, part in PL.split_by_contents(text, bool(PL.POEMS.search(record["title"]))):
        add(100 + n, title, part, who, "contents")
    if team:
        taken = {e["id"] for e in have}
        for n, title, part in P.split_volume(text):
            if f"{record['id']}-{n}" not in taken:
                add(n, title, part, PL.byline(PL.paragraphs(part)), "segment")
    return out


def mend(entry, record, rights, text):
    """A first-reader play from a file once read in the wrong encoding, with its lost letters back, when every line id and
    role stays ("Thérèse" for "Th\ufffdr\ufffdse"); otherwise the play as it was published, because people's takes are kept
    by line id (gut-8499-1, gut-8499-3, gut-8688-4 and gut-8689-3 would gain lines, 2026-11-24)."""
    part, title = text, record.get("title")
    n = entry["id"][4:].partition("-")[2]
    if n:
        part, title = next(((x, t) for k, t, x in P.split_volume(text) if str(k) == n), (None, None))
    parsed = P.parse(part, record["kind"], title) if part else {}
    if not B.offered(rights, parsed):
        return entry
    fresh = B.script_entry({**record, "id": entry["id"]}, rights, parsed)
    if [l["id"] for l in fresh["lines"]] != [l["id"] for l in entry["lines"]] or \
            [(r["name"], r["lines"]) for r in fresh["roles"]] != [(r["name"], r["lines"]) for r in entry["roles"]] or \
            [l.get("role") for l in fresh["lines"]] != [l.get("role") for l in entry["lines"]]:
        return entry
    return {**entry, "lines": fresh["lines"], "revision": fresh["revision"], "roles": fresh["roles"],
            **({"sections": fresh["sections"]} if "sections" in fresh else {})}


def build(plays, ctx, read_text, protect=(), read_as_published=None):
    """plays: harvest records; read_text(id) -> text or None; read_as_published(id) -> the text as the first reader has
    always decoded it (the published line ids come from it). Returns (entries, report)."""
    entries, seen, uncached = [], 0, 0
    report = {"split_failures": {}}
    left, volumes, held = [], [], []
    for p in sorted(plays, key=lambda x: x["id"]):
        record = R.from_gutenberg(p)
        rights = R.judge(record, ctx)
        if not rights["castable"]:
            continue
        text = read_text(p["id"][4:])
        if text is None:
            uncached += 1
            continue
        seen += 1
        right, text = text, (read_as_published(p["id"][4:]) if read_as_published else text)
        parsed = P.parse(text, record["kind"], record.get("title"))
        if record["kind"] == "stage" and parsed.get("status") == "parsed" and p["id"] not in protect and (
                "several_plays_in_one_text" in parsed["issues"] or (parsed.get("clean") and is_volume(text, record))):
            report["volumes"] = report.get("volumes", 0) + 1
            split = volume_entries(record, rights, text, report)
            report["split_clean"] = report.get("split_clean", 0) + len(split)
            entries += split if right == text else [mend(e, record, rights, right) for e in split]
            volumes.append((p, record, rights, right, split))
            continue
        entry = B.script_entry(record, rights, parsed) if B.offered(rights, parsed) else None
        if entry and VOLUME_TITLE.search(entry["title"]):
            printed = volume_play_title(parsed.get("printed_title"), record)
            if printed:
                entry["collection"] = B.clean_title(record["title"])
                entry["title"] = B.clean_title(printed)
                entry["sort_name"] = B.sort_name(entry["title"])
        if entry and title_unusable(entry):
            why = "unclean_title_cut_off"
        elif entry:
            entries.append(entry if right == text else mend(entry, record, rights, right))
            continue
        else:
            why = failure_reason(rights, parsed)
        left.append((p, record, rights, right, why, parsed))
    report["split_failures"] = dict(sorted(report["split_failures"].items()))
    report["single_play_texts_with_a_role_artifact"] = sorted(e["id"] for e in entries if role_artifact(e))
    before = len(entries)
    entries, dups, same_title = dedupe(entries, set(protect))
    first = {e["id"] for e in entries}

    # -- the second reader, over what the first left
    joint = joint_authors(plays)
    new, layouts, why_held = [], collections.Counter(), collections.Counter()

    def hold(pid, title, why, evidence=None):
        why_held[why] += 1
        held.append({"id": pid, "title": title, "why": why, **({"evidence": evidence} if evidence else {})})

    for p, record, rights, text, split in volumes:
        rows = []
        evidence = not_a_play(record, p.get("subjects") or [], None)
        if evidence and not split:
            hold(p["id"], record["title"], "not_a_play", evidence)
            continue
        got = [] if VOLUME_TITLE.search(record["title"]) or split else None
        whole = why = None
        if got is None:
            whole, why, parsed = second_whole(record, rights, text)
        if whole:
            layouts[parsed["layout"]] += 1
            new.append(whole)
            continue
        got = second_volume(record, rights, text, split, joint, rows, report)
        for e in got:
            layouts[e.pop("_how")] += 1
        new += got
        for r in rows:
            hold(r["id"], r["title"], "volume_" + r["why"])
        if not got and not split and not rows:
            hold(p["id"], record["title"], "volume_not_divided")
    for p, record, rights, text, why, parsed in left:
        if record["kind"] != "stage" or why.startswith("stub_"):
            evidence = not_a_play(record, p.get("subjects") or [], None)
            hold(p["id"], record["title"], "not_a_play" if evidence else why, evidence)
            continue
        entry, again, reread = second_whole(record, rights, text)
        share = speech_share(reread or parsed)
        evidence = not_a_play(record, p.get("subjects") or [], share)
        if entry and not evidence:
            layouts[reread["layout"]] += 1
            new.append(entry)
            continue
        if not evidence:
            # several plays under one record that no cast list or first act divides: the contents list may
            rows = []
            got = second_volume(record, rights, text, [], joint, rows, report)
            if len(got) + sum(r["why"] != "no_printed_title" for r in rows) >= 2 and got:
                for e in got:
                    layouts[e.pop("_how")] += 1
                new += got
                for r in rows:
                    hold(r["id"], r["title"], "volume_" + r["why"])
                continue
        hold(p["id"], record["title"], "not_a_play" if evidence else "monologue" if monologue(parsed) else again if reread else why, evidence)
    for e in new:
        e.pop("_how", None)
    # another edition of a play already given (no translator on either) is the same work
    translated = {p["id"] for p in plays if p.get("translators")}
    plain = lambda e: "-".join(e["id"].split("-")[:2]) not in translated
    works = collections.defaultdict(list)
    for e in entries:
        works[work_key(e)[1]].append((work_key(e)[0], e))
    fresh = []
    for e in sorted(new, key=lambda e: ("collection" in e, e["id"])):
        title, who = work_key(e)
        if e["id"] in READ_AND_HELD:
            hold(e["id"], e["title"], "read_and_held", READ_AND_HELD[e["id"]])
            continue
        hit = next((k for t, k in works[who] if who and plain(k) and plain(e) and same_title_words(t, title)), None)
        if hit:
            held.append({"id": e["id"], "title": e["title"], "why": "another_edition", "evidence": "the same title and author as " + hit["id"]})
            why_held["another_edition"] += 1
            continue
        fresh.append(e)
        works[who].append((title, e))
    entries, more, same_title = dedupe(entries + fresh, set(protect) | first)
    assert first <= {e["id"] for e in entries}, "the second reader displaced a first-reader play"
    entries.sort(key=lambda s: (s["sort_name"], s["id"]))
    # The report in the index is counts: phones load it. The rows are held.json.
    report.update({"rights_cleared_uncached": uncached, "parsed": seen, "clean": len(entries),
                   "clean_before_dedupe": before, "first_reader": len(first),
                   "second_reader": len(entries) - len(first), "second_reader_layouts": dict(sorted(layouts.items())),
                   "failures": dict(sorted((k, v) for k, v in why_held.items() if v > 0)),
                   "duplicates_dropped": len(dups) + len(more),
                   "same_title_and_author_different_text_kept": len(same_title)})
    report["_held"] = {"held": sorted(held, key=lambda r: r["id"]), "duplicates_dropped": dups + more,
                       "same_title_and_author_different_text_kept": same_title}
    return entries, report


def same_title_words(a, b):
    """One title holds the other's words in order ("hamlet" in "the tragedy of hamlet prince of denmark")."""
    x, y = sorted((a.split(), b.split()), key=len)
    if not x or re.search(r"\bpart\b|\d|\b[ivx]{1,4}\b", a + " " + b) and a != b:
        return False
    return x == y or len(" ".join(x)) >= 5 and any(y[i:i + len(x)] == x for i in range(len(y) - len(x) + 1)) and len(y) - len(x) <= 5


def speech_share(parsed):
    if not parsed or parsed.get("status") != "parsed":
        return 0.0
    said = sum(len(x["say"].split()) for l in parsed["lines"] if l["kind"] == "speech" for x in l["parts"] if "say" in x)
    return said / max(1, parsed["words"])


def index_doc(entries, report):
    import play_art
    return {"format": FORMAT, "count": len(entries), "wordsPerMinute": WORDS_PER_MINUTE,
            "report": report, "plays": play_art.attach([index_row(e) for e in entries])}


def write(entries, report, out=OUT):
    os.makedirs(os.path.join(out, "scripts"), exist_ok=True)
    keep = set()
    for e in entries:
        name = f"{e['id']}.json"
        keep.add(name)
        with open(os.path.join(out, "scripts", name), "w", encoding="utf-8") as f:
            json.dump(script_file(e), f, ensure_ascii=False, separators=(",", ":"))
            f.write("\n")
    for name in sorted(os.listdir(os.path.join(out, "scripts"))):
        if name not in keep:
            os.remove(os.path.join(out, "scripts", name))
    # The phonemes are derived from the scripts just written: never keep a stale set (build_play_phonemes.py).
    shutil.rmtree(os.path.join(out, "phonemes"), ignore_errors=True)
    if os.path.exists(os.path.join(out, "phonemes-report.json")):
        os.remove(os.path.join(out, "phonemes-report.json"))
    held = report.pop("_held", None)
    if held is not None:
        with open(os.path.join(out, "held.json"), "w", encoding="utf-8") as f:
            json.dump({"format": FORMAT, **held}, f, ensure_ascii=False, indent=1)
            f.write("\n")
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index_doc(entries, report), f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


def main():
    ev = json.load(open(R.EDITORIAL))
    ren = json.load(gzip.open(os.path.join(R.CACHE, "cce_drama_renewals.json.gz"), "rt"))
    ctx = {"renewals": R.renewal_index(ren), "takedowns": ev.get("takedowns", {}), "today": datetime.date.today()}
    plays = json.load(open(os.path.join(R.CACHE, "gutenberg", "plays.json")))["plays"]
    text_dir = os.path.join(R.CACHE, "gutenberg", "text")

    def read_text(pid):
        path = os.path.join(text_dir, pid + ".txt")
        return P.read_text(path) if os.path.exists(path) else None

    bundled = {s["id"] for s in json.load(open(BUNDLE))["scripts"]}
    def read_as_published(pid):
        with open(os.path.join(text_dir, pid + ".txt"), encoding="utf-8", errors="replace") as f:
            return f.read()

    entries, report = build(plays, ctx, read_text, bundled, read_as_published)
    missing = sorted(bundled - {e["id"] for e in entries})
    report["bundled"] = len(bundled)
    report["bundled_missing_from_library"] = missing
    print(json.dumps({k: v for k, v in report.items() if k != "_held"}, indent=1))
    if missing:
        sys.exit("a bundled play is not in the library: " + ", ".join(missing))
    if "--check" not in sys.argv:
        write(entries, report)
        size = sum(os.path.getsize(os.path.join(OUT, "scripts", n)) for n in os.listdir(os.path.join(OUT, "scripts")))
        print(f"wrote {len(entries)} scripts, {size} bytes, to {os.path.relpath(OUT)}", file=sys.stderr)
        if "--no-phonemes" not in sys.argv:
            phonemes()


PHONEME_PYTHON = os.environ.get("PHONEME_PYTHON") or os.path.join(HERE, "..", ".venv-phonemes", "bin", "python")


def phonemes():
    """Every play's phonemes (Decision 078), in the phoneme environment (misaki and spaCy, build time only)."""
    if not os.path.exists(PHONEME_PYTHON):
        sys.exit(f"no phoneme environment at {PHONEME_PYTHON}: run bash tools/setup_phoneme_env.sh "
                 "(or pass --no-phonemes for a library that cannot be published)")
    rc = subprocess.call([PHONEME_PYTHON, os.path.join(HERE, "build_play_phonemes.py"), OUT])
    if rc:
        sys.exit(f"build_play_phonemes.py failed ({rc})")


if __name__ == "__main__":
    main()
