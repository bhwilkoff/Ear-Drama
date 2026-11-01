"""Every text a listener reads, field by field (catalog/audits/2026-10-31-display-fields.md; P-8, owner 2026-10-31:
"I don't want raw text uploads to show at all ... Titles without context don't belong in the app").

    python3 tests/test_display_fields.py
    PROJECTION=out/publish/ear-drama.sqlite python3 tests/test_display_fields.py

Fixtures prove each detector and the repair that answers it, each with its refusal (a clean text is untouched). With
PROJECTION (or out/publish/ear-drama.sqlite) set, the guard runs over every displayed field of the real artifact and
fails on identifier-shaped text, words run together, file and rip tags, count and uploader suffixes, broken encodings,
upload codes in brackets, doubled punctuation and capitalized small words. It counts classes; it never pins a row.
Seen failing on the live projection of 2026-10-31 (the P-7 catalog): 11,737 episode titles with capitalized small
words, 730 with words run together, 840 with upload codes in brackets, 190 roles in broken encodings.
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import display_text as DT
import enrich_scope as ES
import field_defects as FD
import polish as PL

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# Detectors: each class and its control.
d = FD.text_defects
check("identifier: an underscore", "IDENT" in d("OTRR_Suspense_Singles", "label"), True)
check("identifier: an ID3 default title", "IDENT" in d("Title1 - Chapter 01", "title"), True)
check("identifier: letters and digits in one token", "IDENT" in d("TopSecret15", "title"), True)
check("control: a long real word", d("Reconstruction", "title"), [])
check("words run together", "GLUED" in d("Drugstore WFrank Sinatra", "title"), True)
check("words run together: a glued article", "GLUED" in d("Sally Gives Cecil APink Sweater", "title"), True)
check("control: Mc and O names", d("McGee and Molly", "name") + d("Pat ODaniel and His Boys", "name"), [])
check("rip tag", "RIPTAG" in d("Hillbilly Feud (OTR)", "title"), True)
check("count suffix", d("Bergen & McCarthy 48 Eps", "name"), ["COUNT"])
check("control: Series 1 Episode 10 is a title", d("Series 1 Episode 10 Journey Up the Nile", "title"), [])
check("uploader suffix", "UPLOADER" in d("Armed Forces Vietnam Network (AFVN) ALT SOURCE", "name"), True)
check("uploader suffix: copy", "UPLOADER" in d("Dodgers at Cardinals copy", "title"), True)
check("control: HQ is headquarters", d("Gildys Campaign HQ", "title"), [])
check("broken encoding", "MOJIBAKE" in d("The Gravedigger???s Spades", "title"), True)
check("code in brackets", "CODE" in d("Costello The Stunt Man [474]", "title"), True)
check("doubled punctuation", "DOUBLED" in d("Danger--Man at Bay", "title"), True)
check("small words capitalized", d("The Case Of The Kewpie Doll Champ", "title"), ["SMALLWORDS"])
check("control: sentence case keeps its capitals", d("Meet the Nolans and The Kids", "title"), ["SMALLWORDS"])
check("control: a sentence-case title with a capital word is left", d("Gone to the Dogs", "title"), [])
check("control: a small word at the start or after a dash", d("Of Mice and Men - The Radio Play", "title"), [])
check("role: a note, not a role", d("chief of police of santa barbara", "role"), ["LOWERROLE"])
check("control: a role", d("commercial spokesman", "role"), [])

# Repairs: the sightings of the iPhone pass and the owner's examples.
t = PL.polish_title
check("title: small words", t("The Case Of The Kewpie Doll Champ"), "The Case of the Kewpie Doll Champ")
check("title: Bob And Ray", t("Bob And Ray Show"), "Bob and Ray Show")
check("title: hyphenated In", t("Mother-In-Law Murder"), "Mother-in-Law Murder")
check("title: contraction Lets", t("Lets Call The Whole Thing Off"), "Let's Call the Whole Thing Off")
check("title: contraction Dont", t("Dont Worry"), "Don't Worry")
check("control: Lets as a verb is left", t("Mother Lets Go"), "Mother Lets Go")
check("title: part number as Ep", t("The Silent Queen Matter - Ep 3"), "The Silent Queen Matter, episode 3")
check("title: glued Ep01of03", t("Trouble in Millersville Ep01of03"), "Trouble in Millersville, episode 1 of 3")
check("title: glued article", t("Sally Gives Cecil APink Sweater"), "Sally Gives Cecil A Pink Sweater")
check("title: code in brackets", t("Costello The Stunt Man [474]"), "Costello the Stunt Man")
check("title: network tag", t("The Ben Bryson Matter [AFRTS]"), "The Ben Bryson Matter")
check("title: upload code and note", t("Aud01 Audition Show 1 [modified]"), "Audition Show 1")
check("title: double hyphen", t("Lawrence McGaffigan--Cop"), "Lawrence McGaffigan - Cop")
check("title: broken apostrophe", t("The Gravedigger???s Spades"), "The Gravedigger's Spades")
check("title: copy suffix", t("Dodgers at Cardinals copy"), "Dodgers at Cardinals")
check("title: pid", t("The Burglar (with Michael Robbins) [b00rl56h]"), "The Burglar (with Michael Robbins)")
check("title: unrepairable encoding is dropped, not shown", t("Hope?Ã\u0083Â³?Ã\u0083Â©s In Hospital"), None)
check("title: an inverted article is set right", t("Alligator Bag Incident, The"), "The Alligator Bag Incident")
check("control: a comma and a name are not an inverted article", t("Smith, Brown and Jones"), "Smith, Brown and Jones")
check("control: a number in parentheses is the source's own", t("1932 (01) Search For Robert Danforth"), "1932 (01) Search for Robert Danforth")
check("control: a clean title is untouched", t("Sorry, Wrong Number"), "Sorry, Wrong Number")
check("control: Series 1 Episode 10 is untouched", t("Series 1 Episode 10 Journey Up the Nile"), "Series 1 Episode 10 Journey Up the Nile")
check("apostrophe from a source spelling", PL.apostrophe_from("Lets Call The Whole Thing Off", {"Let's Call the Whole Thing Off"}),
      "Let's Call the Whole Thing Off")
check("apostrophe: two different spellings are not guessed", PL.apostrophe_from("Witchs Tale", {"Witch's Tale", "Witchs' Tale"}), "Witchs Tale")
check("apostrophe: a shouted witness is not taken", PL.apostrophe_from("Dont Go", {"DON'T GO"}), "Dont Go")
n = PL.polish_name
check("name: episode-count suffix", n("Bergen & McCarthy 48 Eps"), "Bergen & McCarthy")
check("name: uploader suffix", n("Armed Forces Vietnam Network (AFVN) ALT SOURCE"), "Armed Forces Vietnam Network (AFVN)")
check("name: small words", n("Chet Chetters Tales From The Morgue"), "Chet Chetters Tales from the Morgue")
check("control: a numbered show keeps its number", n("77 Sunset Strip"), "77 Sunset Strip")
check("role: a stage name moves to the character", PL.polish_role("host, as â\u0080\u0099geoffrey barnesâ\u0080\u0099"), ("host", "Geoffrey Barnes"))
check("role: a question mark is dropped", PL.polish_role("? writer"), ("writer", None))
check("role: a sentence is withheld", PL.polish_role("chief of police of santa barbara"), (None, None))
check("role: a clean role is untouched", PL.polish_role("commercial spokesperson"), ("commercial spokesperson", None))
check("character: broken quote marks", PL.polish_character("Ã¢??Old Nancyã¢"), "Old Nancy")
check("person: a doubled first capital", PL.polish_person("JOhnny Neblett"), "Johnny Neblett")
check("person: control, Mc", PL.polish_person("Frank McGee"), "Frank McGee")

import art_policy as AP
check("credit: wiki template", AP.clean_author("{{Fortepan |id= 84697 |orig= Magyar Hirek|archive=}}"), "Fortepan")
check("credit: file line and talk", AP.clean_author("*Barry_in_concert.jpg: Geoff Leonard. () *derivative work: Impy4ever (talk)"),
      "Geoff Leonard; derivative work: Impy4ever")
check("credit: a link is dropped", AP.clean_author("Greg Hernandez at https://www.flickr.com/photos/x/"), "Greg Hernandez")
check("control: a name is untouched", AP.clean_author("Wolfgang Fischer"), "Wolfgang Fischer")

# The recording's label.
lab = PL.recording_label
check("label: OTRR release series", lab("OTRR_Suspense_Singles", "Suspense - Single Episodes", 890), "Old Time Radio Researchers")
check("label: an organization before the dash", lab("BDP_Suspense", "Bowser-Dunning Project - Suspense", 100), "Ron Bowser-John Dunning Project")
check("label: shouted word set in case", lab("SUSPENSE_Radio_Digitally_Restored_Collection",
                                              "SUSPENSE Radio Digitally Restored Collection", 90), "Suspense Radio Digitally Restored Collection")
check("label: a count is dropped", lab("fibber-mc-gee-and-molly", "Fibber McGee and Molly - 1254 Episodes of the Exceptional Old Time Radio Comedy", 1232),
      "Fibber McGee and Molly")
check("label: an acronym stays", lab("cbotrarchive", "CBOTR Archive - Classic Baseball on the Radio", 695), "CBOTR Archive")
check("label: a run-together title is split and its rip tag dropped", lab("x", "MurderMostBritish OTR Favorites Vol. 1", 69), "Murder Most British Favorites Vol. 1")
check("label: an item that is one broadcast has none", lab("Suspense420617TheBurningCourt", "Suspense 42 06 17 The Burning Court", 1), None)
check("label: a title with a date has none", lab("x", "Great Gildersleeve 47 12 10 Christmas Shopping", 4), None)
check("label: an identifier title has none", lab("JackBenny_HQ_601", "JackBenny_HQ_601", 746), None)

# Scope: band remotes, run-together music names.
cls = lambda name, **kw: ES.classify(name, kw.get("items", 0), kw.get("kinds", {}), kw.get("drama", 0), kw.get("music", 0), 0, 0, None)
check("scope: a band remote", (cls("Remote-HarryJames") or ("",))[0], "music")
check("scope: a band remote with a space", (cls("Remote Harryjames") or ("",))[1:2], ("name_names_a_band_remote",))
check("control: a program that merely says remote", cls("The Remote Control Murders"), None)
check("scope: a music group with a run-together name", (cls("ArbershopQuartet barbershopQuartet") or ("",))[0], "music")
check("control: a spoken title with a run-together name", cls("McGee and Molly Radio Drama"), None)

# Withheld names and non-programs.
check("a sentence of dates is withheld", DT.series_withheld("Organ donation / Rabbi Seymour Siegel Aired 15", "k", True), "series_name_is_a_file_name")
check("an intro track is not a program", DT.episode_out_of_scope("Old Time Radio Researchers Introduction"), "out_of_scope_not_a_program")
check("control: a program with Old Time Radio in its name", DT.episode_out_of_scope("Old Time Radio Murder Mystery Hour"), None)
check("a placeholder title is unreadable", DT.readable_title("xx xx no title"), False)
check("a title with a pid left is unreadable", DT.readable_title("The Burglar [b00rl56h]"), False)
check("control: a plain title is readable", DT.readable_title("The Burglar"), True)

# The real artifact.
GUARDED = {
    "series.name": {"IDENT", "GLUED", "COUNT", "UPLOADER", "MOJIBAKE", "CODE", "FILE", "DOUBLED", "SMALLWORDS"},
    "episodes.title": {"IDENT", "GLUED", "RIPTAG", "COUNT", "UPLOADER", "MOJIBAKE", "CODE", "FILE", "DOUBLED", "SMALLWORDS"},
    "episodes.aka": {"IDENT", "GLUED", "RIPTAG", "COUNT", "UPLOADER", "MOJIBAKE", "CODE", "FILE", "DOUBLED", "SMALLWORDS"},
    "episodes.sponsor": {"GLUED", "MOJIBAKE", "CODE", "SMALLWORDS"},
    "episodes.network": {"GLUED", "MOJIBAKE", "CODE"},
    "series.networks": {"GLUED", "MOJIBAKE", "CODE"},
    "credits.role": {"MOJIBAKE", "LOWERROLE", "CODE", "DOUBLED", "IDENT"},
    "credits.character": {"MOJIBAKE", "CODE", "DOUBLED", "IDENT"},
    "people.name": {"GLUED", "MOJIBAKE", "CODE"},
    "voices.name": {"GLUED", "MOJIBAKE", "CODE"},
    "arcs.title": {"IDENT", "GLUED", "RIPTAG", "COUNT", "UPLOADER", "MOJIBAKE", "CODE", "FILE", "DOUBLED", "SMALLWORDS"},
    "art.credit": {"MOJIBAKE", "CODE", "FILE", "DOUBLED"},
    "recordings.label": {"IDENT", "GLUED", "RIPTAG", "COUNT", "UPLOADER", "MOJIBAKE", "CODE", "FILE", "DOUBLED", "SMALLWORDS", "SHOUT"},
}
path = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(path):
    res = FD.audit(path)
    check("every displayed field is audited", sorted(GUARDED) == sorted(set(GUARDED) & set(res)), True)
    for field, guarded in GUARDED.items():
        for c, rows in sorted(res.get(field, {"classes": {}})["classes"].items()):
            if c in guarded:
                check(f"{field} has no {c} text (e.g. {rows[:5]})", len(rows), 0)
    print(f"projection {os.path.basename(os.path.dirname(path))}: " + ", ".join(
        f"{f} {r['distinct']}" for f, r in res.items()))
else:
    print("no projection to read (set PROJECTION): fixtures only")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
