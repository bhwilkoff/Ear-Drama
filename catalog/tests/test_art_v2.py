"""Round 3 V2 (contract section 3.3c): the predicates for more real images, on fixtures, each with a
control that must fail the way the rule says (R3b section 5.2), plus the candidate stage of the enrichment.

    python3 tests/test_art_v2.py

Seen to FAIL (2026-11-19): every `control` was run against a copy of the predicate with its rule removed
(the name-in-file check, the date requirement, the one-word-radio rule, the free flag, the collection words,
the surname, the liveness verdict) and went red. Nothing here pins catalog contents.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import art_policy as AP
import enrich_series_art as ESA

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# --- H4: a Commons search hit (rules 6, 3, 2) -------------------------------------------------
FIRST, LAST = "1946-03-01", "1952-06-01"
RADIO_CAT = ["1948 in radio"]


def hit(file, cats=RADIO_CAT, when=None, name="Stories of Mercy General"):
    return AP.name_hit_served(file, list(cats), when, name, FIRST, LAST)


LONG = "Stories of Mercy General"   # a program named by more than two words
check("name hit: the name opens the file's title, radio in a category, a date in the run",
      hit("Stories of Mercy General cast 1948.jpg"), True)
check("name hit: a category that is the program (its parenthesis dropped), the date in the page's date field",
      hit("Cast photo.jpg", ["Stories of Mercy General (radio series)"], "1949"), True)
check("name hit: a name of three words may stand anywhere in the title",
      hit("Cast of Stories of Mercy General.jpg", RADIO_CAT, "1948"), True)
check("name hit: two years either side of the run is allowed (YEAR_SLACK)",
      hit("Stories of Mercy General.jpg", ["Radio programs"], "1954"), True)
check("control: a caption the search engine matched is not the file's own name (rule 6)",
      hit("Hospital ward.jpg", ["Hospitals in 1948", "Radio"], "1948"), False)
check("control: a word that only contains the name is not the name", hit("Mercy Generals 1948.jpg", name="Mercy General"), False)
check("control: a longer program's name that contains ours is not ours (Radio Theater is not Lux Radio Theatre)",
      AP.name_hit_served("Bacall and Bogart on Lux Radio Theatre 1946.jpg", ["Lux Radio Theatre", "CBS Radio publicity photos"],
                         "1946", "Radio Theater", FIRST, LAST), False)
check("control: a one-word program is not a word inside a longer title ('Music' in 'Great Moments in Music')",
      AP.name_hit_served("Great Moments in Music Jan Peerce 1948.jpg", ["Radio programs from the United States"],
                         "1948", "Music", FIRST, LAST), False)
check("control: an undated hit is no evidence of the run (the Saint hit was a 2004 photograph)",
      hit("Stories of Mercy General.jpg", RADIO_CAT, None), False)
check("control: a file dated outside the run is refused (rule 3)", hit("Stories of Mercy General.jpg", RADIO_CAT, "2004"), False)
check("control: a year in the name outside the run is refused too", hit("Stories of Mercy General 1914.jpg", RADIO_CAT, None), False)
check("control: a series with no run bounds takes no name hit", AP.name_hit_served(
      "Stories of Mercy General 1948.jpg", RADIO_CAT, "1948", LONG, None, None), False)
check("control: an audio file is not a picture", hit("Stories of Mercy General 1948.ogg", RADIO_CAT, "1948"), False)
check("control: the television twin's still has the name, the stars and the date but no radio (Gunsmoke 1962)",
      AP.name_hit_served("Burt Reynolds Gunsmoke 1962.jpg", ["CBS publicity photos", "Gunsmoke"], "1962", "Gunsmoke",
                         "1952-04-26", "1961-06-18"), False)
check("name hit: the radio program's own photograph says radio (Gunsmoke, CBS Radio publicity photos)",
      AP.name_hit_served("Gunsmoke cast 1953.jpg", ["CBS Radio publicity photos", "Gunsmoke"], "1953", "Gunsmoke",
                         "1952-04-26", "1961-06-18"), True)
check("name hit: one word, the file's title opens with it and says radio",
      AP.name_hit_served("Suspense radio 1948.jpg", [], "1948", "Suspense", FIRST, LAST), True)
check("article is not part of the name: 'The Saint' is found as 'Saint'",
      AP.name_hit_served("Saint radio drama 1948.jpg", [], "1948", "The Saint", FIRST, LAST), True)

# the show predicate: a name hit needs its own tie, every other source needs the item's
kw = dict(author=None, width=900, height=700, file="Stories of Mercy General 1948.jpg")


def served(identity, source, cls="pd_us", **over):
    a = {**kw, **over}
    return AP.show_served(identity, source, cls, a["author"], a["width"], a["height"], a["file"], (), "1948", LAST, FIRST)


check("show_served: a name hit with the file's own tie", served(AP.NAME_IDENTITY, "commons:name"), True)
check("control: a name hit whose tie is only the title", served("title", "commons:name"), False)
check("control: the name tie cannot stand in for an item's identity on a Wikidata source",
      served(AP.NAME_IDENTITY, "wikidata:P18"), False)
check("show_served: an item's identity serves a lead image from enwiki", served("title+years", "commons:enwiki"), True)
check("control: a lead image needs the item's identity", served("title", "commons:enwiki"), False)
check("control: a television item gets no name hit", served("television", "commons:name"), False)
check("control: an audio file is never a show image (Father Knows Best's .ogg)",
      served("title+years", "wikidata:P18", file="Father Knows Best.ogg"), False)
check("every new source ranks after the old ones",
      [AP.SHOW_RANK[s] for s in ("commons:category", "commons:enwiki", "commons:name")], [6, 7, 8])

# --- H3: the enwiki lead image -----------------------------------------------------------------
check("lead: free by Wikipedia's flag and on Commons", AP.lead_image_served("Cast.jpg", "ok"), True)
check("control: the flag is absent (an enwiki fair-use file)", AP.lead_image_served(None, "ok"), False)
check("control: free, but its Commons page does not exist", AP.lead_image_served("Cast.jpg", "missing"), False)

# --- hero, gallery -----------------------------------------------------------------------------
def row(file, src="wikidata:P18", cls="pd_us", w=1000, h=700):
    return (file, src, cls, None, None, w, h, None, "title+years")


check("hero: the best landscape image at least 600 px wide", AP.pick_hero([row("a.jpg", w=800, h=900), row("b.jpg"),
                                                                           row("c.jpg", src="commons:name")])[0], "b.jpg")
check("control: a portrait is never a hero", AP.pick_hero([row("a.jpg", w=700, h=900)]), None)
check("control: a landscape under 600 px is never a hero", AP.pick_hero([row("a.jpg", w=500, h=300)]), None)
check("control: a square is not landscape", AP.pick_hero([row("a.jpg", w=900, h=900)]), None)
check("hero: source order, then license class, then name",
      AP.pick_hero([row("z.jpg", cls="cc_by"), row("y.jpg", cls="pd_us"), row("x.jpg", src="commons:category")])[0], "y.jpg")
rows7 = [row(f"{i}.jpg") for i in range(8)]
check("gallery: at most six", len(AP.pick_gallery(rows7)), AP.GALLERY_MAX)
check("control: the gallery never repeats the picture or the hero",
      [r[0] for r in AP.pick_gallery(rows7[:4], {"0.jpg", "1.jpg"})], ["2.jpg", "3.jpg"])
check("control: a crop of a photograph already in the gallery is the same picture twice",
      [r[0] for r in AP.pick_gallery([row("Cast 1937.jpg"), row("Cast 1937 (cropped).jpg"), row("Cast 1937 edited.jpg"),
                                      row("Other 1937.jpg")])], ["Cast 1937.jpg", "Other 1937.jpg"])
check("control: nor the picture's own crop", [r[0] for r in AP.pick_gallery([row("Cast 1937 (cropped).jpg")], {"Cast 1937.jpg"})], [])
check("control: a file listed twice is one entry", [r[0] for r in AP.pick_gallery([row("a.jpg"), row("a.jpg")])], ["a.jpg"])

# --- Gallery and hero files must say radio (R3b section 5.2 rule 4; owner 2026-11-19) ------------------------
GR = lambda f, cats=(), t=None, a=None, ppl=("Willard Waterman",), nets=("NBC",): AP.gallery_is_radio(f, list(cats), t, a, ppl, nets)
check("radio: a network radio publicity category", GR("Mary Lee Rob 1948 NBC photo.jpg", ["NBC Radio publicity photos"], ppl=()), True)
check("radio: the word in the file's own name", GR("Fibber and Molly radio studio 1941.jpg", ppl=()), True)
check("radio: the page's credit says radio", GR("Hattie McDaniel Beulah 1948.jpg", ["Beulah (given name)"], "PD-Pre1978", "CBS Radio", ()), True)
check("radio: a marked person named in the file, no screen credit", GR("Willard Waterman 1952.jpg", ["Willard Waterman"]), True)
check("the Gildersleeve 1955 television still: the program's category, a marked person, an episode screenshot: refused",
      GR("Willard Waterman in The Great Gildersleeve (The Expectant Father).jpg", ["The Great Gildersleeve", "Willard Waterman"],
         "PD-US-not renewed", "episode screenshot (NBC)"), False)
check("...and the same program's 1955 still credited to a producer is refused", GR(
      "Great Gildersleeve 1.jpg", ["Stephanie Griffin", "The Great Gildersleeve", "Willard Waterman"], "PD-US-not renewed",
      "NBC Productions"), False)
check("control: a television word refuses even a marked person", GR("Willard Waterman Gildersleeve television 1955.jpg",
      ["Willard Waterman"]), False)
check("control: television in the page's credit refuses a radio publicity category", GR(
      "Life of Riley cast 1953.JPG", ["NBC Radio publicity photos"], "PD-Pre1978", "NBC Television", ()), False)
check("control: a plain publicity category without radio is not a radio category (the twins sit there)", GR(
      "Lewis and Martin.jpg", ["Publicity photos"], ppl=()), False)
check("control: a place that shares the program's name names no person", GR("Prairie Home Cemetery, Moorhead.jpg", ["Cemeteries"],
      ppl=("Garrison Keillor",)), False)

# --- H5: archive photographs through people (R3b section 5.1; owner V2/V4) -----------------------------------
check("portrait title: the person's name alone", AP.portrait_title("Graham McNamee", "Graham McNamee"), True)
check("portrait title: the name and portrait words", AP.portrait_title(
      "[Herbert Hoover, three-quarter length portrait, seated, facing slightly left]", "Herbert Hoover"), True)
check("portrait title: at the microphone", AP.portrait_title("Graham McNamee at the microphone", "Graham McNamee"), True)
check("control: a Jr. is another person", AP.portrait_title("Herbert Hoover, Jr., and radio set", "Herbert Hoover"), False)
check("control: a title naming two people is no portrait of one", AP.portrait_title(
      "Graham McNamee and Ted Husing", "Graham McNamee"), False)
check("control: an event is not a portrait", AP.portrait_title("Wheeler bill would cripple radio. Sen. Alben Barkley", "Alben Barkley"), False)
check("control: a one-word name is too short to tie a title", AP.portrait_title("Cher", "Cher"), False)
AS = lambda **k: AP.archive_portrait_served(**{"source": "loc", "rights_class": "no_known_restrictions", "usable": 1,
                                              "title": "Graham McNamee", "name": "Graham McNamee", "photo_year": 1925,
                                              "birth": "1888-07-10", "death": "1942-05-09", "basis": "name+birth_day+death_day",
                                              "link_basis": "", **k})
check("archive portrait: LoC, no known restrictions, a title that is the person, a year inside their life", AS(), True)
check("archive portrait: a Smithsonian CC0 sitter line", AS(source="smithsonian", rights_class="cc0", title="Neutral", link_basis="portrait: x"), True)
check("archive portrait: our own birth and death, no Wikidata match", AS(basis=None), True)
check("archive portrait: a Smithsonian photographic negative is a photograph", AS(
      source="smithsonian", rights_class="cc0", link_basis="portrait: x", object_type="Photographic Negative"), True)
check("control: a Smithsonian caricature, drawing, bust or poster is the sitter's likeness, not a photograph", [AS(
      source="smithsonian", rights_class="cc0", link_basis="portrait: x", object_type=t) for t in
      ("Drawing", "Painting", "Print", "Silhouette", None)], [False] * 5)
check("control: a record that restricts publication", AS(rights_class="restricted"), False)
check("control: a photograph taken before the person was grown", AS(photo_year=1895), False)
check("control: a photograph taken after their death", AS(photo_year=1950), False)
check("control: no year on the photograph", AS(photo_year=None), False)
check("control: nothing of the person's own to set the year against", AS(birth=None, death=None), False)
check("control: one known date and no Wikidata match is not enough", AS(birth="1888", death=None, basis=None), False)
check("control: a title that is about something else, no sitter line", AS(title="Graham McNamee and Ted Husing"), False)
check("archive image: LoC's tile address is served as it is", AP.archive_image_url("loc", "https://tile.loc.gov/x/3a03536r.jpg"),
      "https://tile.loc.gov/x/3a03536r.jpg")
check("archive image: a Smithsonian master becomes the 960 px delivery, ending in a parameter the client's ?width= falls into",
      AP.archive_image_url("smithsonian", "https://ids.si.edu/ids/download?id=NPG-NPG_94_50Welles-000002.jpg"),
      "https://ids.si.edu/ids/deliveryService?id=NPG-NPG_94_50Welles-000002&max=960&w=")
import json
import sqlite3
import build_projection as BPJ
_h5 = sqlite3.connect(":memory:")
_h5.executescript("""
CREATE TABLE people (id TEXT, name TEXT, names TEXT, birth TEXT, death TEXT);
CREATE TABLE people_wikidata (person_id TEXT, basis TEXT, birth TEXT, death TEXT);
CREATE TABLE archive_photos (source TEXT, record_id TEXT, title TEXT, year INTEGER, width INTEGER, height INTEGER,
  rights_class TEXT, usable INTEGER, evidence_url TEXT, image_url TEXT);
CREATE TABLE archive_photo_links (source TEXT, record_id TEXT, target_kind TEXT, target_id TEXT, basis TEXT, strength TEXT);
INSERT INTO people VALUES ('p1', 'Graham McNamee', '[]', '1888-07-10', '1942-05-09'), ('p2', 'Ted Husing', '[]', '1901-11-27', '1962-08-10');
INSERT INTO archive_photos VALUES ('loc', 'r1', 'Graham McNamee', 1925, 751, 1024, 'no_known_restrictions', 1,
  'https://www.loc.gov/item/r1/', 'https://tile.loc.gov/r1.jpg'),
  ('loc', 'r2', 'Graham McNamee and Ted Husing', 1930, 800, 600, 'no_known_restrictions', 1, 'https://www.loc.gov/item/r2/', 'https://tile.loc.gov/r2.jpg');
INSERT INTO archive_photo_links VALUES ('loc', 'r1', 'person', 'p1', 'title', 'title'), ('loc', 'r2', 'person', 'p1', 'title', 'title'),
  ('loc', 'r2', 'person', 'p2', 'title', 'title');
""")
_got = BPJ.served_archive_portraits(_h5, {"p1": "Graham McNamee", "p2": "Ted Husing"}, None, {}, set())
check("projection: the person whose title it is gets the record; the second person of a two-person title gets none",
      sorted(_got), ["p1"])
check("projection: the row carries the record page, where it was found and the tie", _got["p1"][7:], (
      "https://www.loc.gov/item/r1/", "loc:record-title", "record title is the person; photograph year inside their life"))
check("control: a person who already has a Commons portrait is not given another",
      BPJ.served_archive_portraits(_h5, {"p1": "Graham McNamee"}, None, {}, {"p1"}), {})
check("control: a source without the archive tables serves none",
      BPJ.served_archive_portraits(sqlite3.connect(":memory:"), {"p1": "x"}, None, {}, set()), {})

# --- H9: liveness ------------------------------------------------------------------------------
check("liveness: 200 and a redirect chain's last 200 are ok", [AP.liveness_verdict(s) for s in (200, 301)], ["ok", "ok"])
check("liveness: 404 and 410 are gone", [AP.liveness_verdict(s) for s in (404, 410)], ["gone", "gone"])
check("control: a 429, a 503 or a failure is never a death", [AP.liveness_verdict(s) for s in (429, 503, None)],
      [None, None, None])
check("alive: a file found gone is not", AP.alive({"a.jpg": {"verdict": "gone", "day": 1}}, "a.jpg"), False)
check("control: a file never checked is presumed alive", AP.alive({}, "a.jpg"), True)
check("control: a file found ok is alive", AP.alive({"a.jpg": {"verdict": "ok", "day": 1}}, "a.jpg"), True)
check("ttl: a check older than the TTL is stale", AP.liveness_stale({"day": 100}, 100 + AP.LIVENESS_TTL_DAYS + 1), True)
check("control: a recent check is not", AP.liveness_stale({"day": 100}, 100 + AP.LIVENESS_TTL_DAYS), False)
check("control: no check at all is stale", AP.liveness_stale(None, 5), True)

# --- H7: plays ---------------------------------------------------------------------------------
def ed(title="Chantecler; a pictorial edition", creator="Rostand, Edmond, 1868-1918", year=1910, mediatype="texts"):
    return {"title": title, "creator": creator, "year": year, "mediatype": mediatype}


S = ["rostand"]
check("edition: a 1910 text, the author's name in its creator, its title opening with the play's", AP.edition_served("Chantecler", S, ed()), True)
check("edition: the year may be an ISO date's", AP.edition_served("Chantecler", S, ed(year="1910-01-01T00:00:00Z")), True)
check("control: published after 1930 is not public domain by age", AP.edition_served("Chantecler", S, ed(year=1940)), False)
check("control: no year is no evidence", AP.edition_served("Chantecler", S, ed(year=None)), False)
check("control: a creator without the author's name (a different Sutro duologue)",
      AP.edition_served("Chantecler", S, ed(creator="Sutro, Alfred")), False)
check("control: a title that does not open with the play's (Ninon, Moliere et Tartuffe)",
      AP.edition_served("Tartuffe", ["moliere"], ed("Ninon, Moliere et Tartuffe", "Moliere", 1815)), False)
check("control: a collection is not a first edition (rule 8)",
      AP.edition_served("Chantecler", S, ed("Chantecler and other plays: the best known works of Rostand")), False)
check("control: a book about the play is not an edition of it",
      AP.edition_served("Chantecler", S, ed("Chantecler: a study of the play")), False)
check("edition: a collection word the play's own title carries is the title ('Three Sisters')",
      AP.edition_served("Three Sisters", ["chekhov"], ed("Three Sisters: a drama", "Chekhov, Anton", 1920)), True)
check("control: not a text (a film's record)", AP.edition_served("Chantecler", S, ed(mediatype="movies")), False)
check("control: a creator list is read by whole words ('Rostand' is not in 'Frostand')",
      AP.edition_served("Chantecler", S, ed(creator=["Frostand, A."])), False)
check("surname: 'Last, First' and 'First Last' agree", (AP.surname_of("Shaw, Bernard"), AP.surname_of("George Bernard Shaw")),
      ("shaw", "shaw"))
check("surname: accents fold", AP.surname_of("Moliere"), AP.surname_of("Molière"))

PAGES = ["", "Digitized by Google", "CHANTECLER", "CHANTECLER PLAY IN FOUR ACTS BY EDMOND ROSTAND TRANSLATED BY GERTRUDE HALL "
         "NEW YORK DUFFIELD AND COMPANY 1910", "Copyright 1910 by Edmond Rostand All rights reserved",
         "CHANTECLER Rostand " + "word " * 400]
check("title page: the first short leaf holding the play's title and the author's name", AP.title_page_ocr(PAGES, "Chantecler", S), 3)
check("control: a half-title with no author is not a title page", AP.title_page_ocr(PAGES[:3], "Chantecler", S), None)
check("control: a leaf with the play's title and no author is not a title page (a half-title with a printer's line)",
      AP.title_page_ocr(["CHANTECLER A PLAY IN FOUR ACTS NEW YORK 1910"], "Chantecler", S), None)
check("control: a copyright page has the author but not the title", AP.title_page_ocr([PAGES[4]], "Chantecler", S), None)
check("control: a long leaf that names both (a text page, a contents page) is not a title page",
      AP.title_page_ocr([PAGES[5]], "Chantecler", S), None)
check("control: the title words must stand in order", AP.title_page_ocr(["CONQUER STOOPS SHE BY GOLDSMITH"], "She Stoops to Conquer",
                                                                      ["goldsmith"]), None)
check("title page: OCR noise around the words does not matter",
      AP.title_page_ocr(["THE TENTH MAN A TRAGIC COMEDY In Three Acts Ss Br W. 8. MAUGHAM?>> LONDON"], "The Tenth Man", ["maugham"]), 0)
check("control: past the first leaves nothing counts", AP.title_page_ocr([""] * AP.TITLE_PAGE_SCAN + [PAGES[3]], "Chantecler", S), None)
check("agree: the scan data's Title leaf and the OCR's are the same page", AP.title_page_agrees(8, 8), True)
check("agree: the OCR list may lack the first leaf", AP.title_page_agrees(9, 8), True)
check("control: a Title leaf two pages from the OCR's is another page (a copyright page, a contents page)",
      AP.title_page_agrees(10, 8), False)
check("control: a Title leaf before the OCR's is another page", AP.title_page_agrees(7, 8), False)
check("control: no leaf from either record, no title page", [AP.title_page_agrees(None, 3), AP.title_page_agrees(3, None)], [False, False])

import harvest_art_v2 as H
SCAN = ("<book><pageData><page leafNum='0'><pageType>Cover</pageType><addToAccessFormats>false</addToAccessFormats></page>"
        "<page leafNum='1'><pageType>Normal</pageType><addToAccessFormats>true</addToAccessFormats></page>"
        "<page leafNum='2'><pageType>Title</pageType><addToAccessFormats>true</addToAccessFormats><origWidth>1275</origWidth>"
        "<origHeight>1650</origHeight></page></pageData></book>")
check("scan data: the index counts only leaves in the page list (a leaf with addToAccessFormats false is not one)",
      H.scan_title_leaf(SCAN), (1, 1275, 1650))
check("control: no Title leaf, no index", H.scan_title_leaf(SCAN.replace("Title", "Normal")), None)
OCRX = "<BODY><OBJECT data='a'><WORD>One</WORD><WORD>two</WORD></OBJECT><OBJECT data='b'></OBJECT><OBJECT data='c'><WORD>Three</WORD></OBJECT>"
check("OCR: one text per page, an empty page kept (the index counts it)", H.ocr_pages(OCRX), ["One two", "", "Three"])

work = {"label": "In Honour Bound", "authors": ["Sydney Grundy"], "description": "play by Sydney Grundy"}
check("work: the label is the title and the author is one of ours", AP.work_served("In Honour Bound", ["grundy"], work), True)
check("control: the same title by another author (the 1925 radio play)",
      AP.work_served("In Honour Bound", ["grundy"], {**work, "authors": ["Someone Else"], "description": "radio play"}), False)
check("control: a different title", AP.work_served("Honour Bound", ["grundy"], work), False)
check("work: the description names the author when P50 does not",
      AP.work_served("In Honour Bound", ["grundy"], {**work, "authors": []}), True)

check("work image: a scene or a title page of the play stands for it",
      [AP.work_image_is_of_the_work(f, "Misalliance", ["shaw"]) for f in ("Misalliance 1910 Royal Court.jpg", "Valentine and Proteus.jpg")],
      [True, True])
check("control: a portrait of the author is not the work (G Bernard Shaw.jpg is Misalliance's own P18)",
      AP.work_image_is_of_the_work("G Bernard Shaw.jpg", "Misalliance", ["shaw"]), False)
check("work image: the author's name with the title is the work's title page",
      AP.work_image_is_of_the_work("Captain Brassbound's Conversion by George Bernard Shaw.jpg", "Captain Brassbound's Conversion", ["shaw"]), True)
check("play title: cut at a subtitle or a note", [AP.play_title("She Stoops to Conquer; Or, The Mistakes of a Night"),
                                                  AP.play_title("The Tragical History of Doctor Faustus\r From the Quarto of 1604"),
                                                  AP.play_title("Ghosts: A Domestic Tragedy in Three Acts")],
      ["She Stoops to Conquer", "The Tragical History of Doctor Faustus", "Ghosts"])
check("play image: a PD file at a tile size", AP.play_image_served("pd_us", None, 400, 500), True)
check("control: under the tile floor", AP.play_image_served("pd_us", None, 100, 100), False)
check("play image: public domain where it was made is used (040)", AP.play_image_served("pd_source_only", None, 400, 500), True)
check("control: a restricted play image is refused", AP.play_image_served("restricted", None, 400, 500), False)
check("control: CC BY with no author to credit", AP.play_image_served("cc_by", "Unknown", 400, 500), False)
check("control: an own work dated after the author's death",
      AP.play_image_served("pd_release", None, 400, 500, True, "2019", "1918"), False)
check("pick_play: the work image, then a title page, then the author",
      [AP.pick_play(rs)[0] for rs in ([("author",), ("titlePage",), ("work",)], [("author",), ("titlePage",)], [("author",)])],
      ["work", "titlePage", "author"])
check("control: no image, no picture", AP.pick_play([]), None)

# --- the enrichment's candidate stage ------------------------------------------------------------
trackd = {"File:Stories of Mercy General 1948.jpg": {"categories": ["Category:Radio programs"]},
          "File:Cast of Stories of Mercy General.jpg": {"categories": []},
          "File:Mercy hospital.jpg": {"categories": ["Category:Hospitals"]}}
idx = ESA.word_index(trackd)
check("candidates: Track D files holding every word of the name, whatever the order",
      ESA.name_candidates("Stories of Mercy General", idx), ["Cast of Stories of Mercy General.jpg", "Stories of Mercy General 1948.jpg"])
check("control: a file holding only some of the words is not a candidate", ESA.name_candidates("Mercy General Hospital", idx), [])
check("candidates: search hits come first and once", ESA.name_candidates(
      "Stories of Mercy General", idx, ["Stories of Mercy General 1948.jpg"])[0], "Stories of Mercy General 1948.jpg")
check("control: a name too short to carry a file's title has none", ESA.name_candidates("Ab", idx), [])

# --- the play library's pictures (play_art.py) -----------------------------------------------------
import play_art as PA

PF = {"Work.jpg": {"class": "pd_us", "width": 800, "height": 600},
      "Author.jpg": {"class": "cc_by_sa", "template": "cc-by-sa-3.0", "author": "A. Photographer", "width": 400, "height": 500},
      "Small.jpg": {"class": "pd_us", "width": 100, "height": 100},
      "Late own work.jpg": {"class": "pd_release", "own_work": True, "date_field": "2019", "width": 400, "height": 500}}
EDITION = {"id": "chantecler01rost", "leaf": 7, "width": 1275, "height": 1650}
CTX = {"plays": {"gut-1": {"work": {"files": ["Small.jpg", "Work.jpg"]}, "edition": EDITION, "edition_v": 2,
                           "author": {"files": ["Author.jpg"], "died": "1918", "basis": "name+birth_year"}},
                 "gut-2": {"work": None, "edition": None, "author": {"files": ["Late own work.jpg"], "died": "1918"}}},
       "files": PF, "live": {}}
got = PA.pictures("gut-1", CTX)
check("play: the work's image leads, the small one passed over", (got["picture"]["kind"], got["picture"]["url"]),
      ("work", AP.image_url("Work.jpg")))
check("play: the title page is the archive.org leaf, 800 wide, in the scan's own shape",
      (got["titlePage"]["url"], got["titlePage"]["width"], got["titlePage"]["height"], got["titlePage"]["source"]),
      ("https://archive.org/download/chantecler01rost/page/n7_w800.jpg", 800, 1035, "archive.org"))
check("play: the author's portrait carries its credit, its source and its tie",
      (got["authorArt"]["credit"], got["authorArt"]["source"], got["authorArt"]["tie"]),
      ("A. Photographer, CC BY-SA 3.0", "wikidata:P18", "name+birth_year"))
dead = {**CTX, "live": {"Work.jpg": {"verdict": "gone", "day": 1}}}
check("control: a work image found gone falls back to the title page", PA.pictures("gut-1", dead)["picture"]["kind"], "titlePage")
dead2 = {**CTX, "live": {"Work.jpg": {"verdict": "gone", "day": 1}, PA.page_url(EDITION): {"verdict": "gone", "day": 1}}}
check("control: and with that gone too, to the author", PA.pictures("gut-1", dead2)["picture"]["kind"], "author")
check("control: a file found ok is kept",
      PA.pictures("gut-1", {**CTX, "live": {"Work.jpg": {"verdict": "ok", "day": 1}}})["picture"]["kind"], "work")
check("control: an edition judged before the title-leaf rule (no edition_v) is not served",
      PA.pictures("gut-1", {**CTX, "plays": {"gut-1": {k: v for k, v in CTX["plays"]["gut-1"].items() if k != "edition_v"}}})["titlePage"], None)
check("control: an own work dated after the author died is refused", PA.pictures("gut-2", CTX)["authorArt"], None)
check("control: a play cut from a volume takes the volume's author, never its work or edition",
      [k for k, v in PA.pictures("gut-1-3", CTX).items() if v], ["authorArt", "picture"])
check("control: a play with no record has no picture", PA.pictures("gut-99", CTX), {"titlePage": None, "production": None, "authorArt": None, "picture": None})
PF["G Bernard Shaw.jpg"] = {"class": "pd_us", "width": 800, "height": 900}
PCTX = {"plays": {"gut-3": {"title": "Misalliance: A Debate", "authors": ["Shaw, Bernard"], "work": {"files": ["G Bernard Shaw.jpg"]},
                            "edition": None, "author": {"files": ["Author.jpg"], "died": "1950", "basis": "name+birth_year"}}},
        "files": PF, "live": {}}
check("control: the work's own image that is a portrait of its author is not served as the work; the author slot has hers",
      [(k, bool(v)) for k, v in PA.pictures("gut-3", PCTX).items()], [("titlePage", False), ("production", False), ("authorArt", True), ("picture", True)])
check("control: ...and what leads is the author, not the portrait twice", PA.pictures("gut-3", PCTX)["picture"]["kind"], "author")
rows = PA.attach([{"id": "gut-1"}, {"id": "gut-99"}], CTX)
check("attach: a row with nothing keeps its own keys only", sorted(rows[1]), ["id"])
check("attach: a row with pictures gains the three keys", sorted(rows[0]), ["authorArt", "id", "picture", "titlePage"])

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
