# 08b — The scripts: what is free, where the text is, and how to turn it into roles and lines

*2026-10-18. Track: collaborative recording of radio plays (owner's request, 2026-10-18).
Everything marked "measured" was run today against the source named; prototype
parsers are in the session scratchpad (paths at the end), nothing in the repo was changed.*

## Verdict

1. **Stage plays are the abundant, clean, easy class.** Project Gutenberg's catalog has
   **1,721 English texts** on its drama shelf or with a Drama subject (measured, of 3,033 in
   all languages); Standard Ebooks has **~115 dramas, CC0, already marked up speech by
   speech**; LibriVox has **640 dramatic projects** (574 English), **444 of them with a role
   list in their metadata**, and 377 link the Gutenberg text they read. A rule parser
   matched Standard Ebooks' own markup on *The Importance of Being Earnest*, speaker for speaker,
   on **877 of 879 speeches**.
2. **Genuinely free radio scripts are a small, specific set.** These are:
   - **Government series.** The best is *Uncle Sam's Forest Rangers*, **562 USDA Forest
     Service scripts from 1932-44** on archive.org.
   - **Radio plays published in books** that are now out of copyright, such as H. F.
     Carlton's NBC *Great Moments in History* plays on Gutenberg (4, plus one on archive.org).
   - **Scripts registered in Class D and never renewed.** The Catalog of Copyright Entries
     (CCE) prints these. In the 1947-49 volumes, **3,342 registrations mention radio and 146
     have a matching renewal**.
3. **"Before 1931" does not free a radio script.** A broadcast script was almost always
   unpublished, so §303 governs it. A work made for hire written in 1928 is protected until
   2048, unless it was registered (95 years from registration, so 1930 and earlier is free now)
   or its individual author died in 1955 or earlier.
4. **Generic Radio Workshop (GRW): about 1.6% falls in a clearly free class.** Of its
   **1,371 scripts**: **10** are government work (Forest Rangers), **3** have the same play
   published on Gutenberg, and **9** match a 1946-49 registration whose series never shows
   up in the renewal-era catalogs (Fibber McGee ×4, Great Gildersleeve ×2, Dr. Christian,
   First Nighter, Green Hornet). GRW's texts are volunteer transcriptions with added notes,
   so we should use them to find scripts and ask GRW before reusing their text.
5. **Parsing is reliable on clean text and fails on raw OCR.**
   - On 291 GRW transcriptions, **84,063 speech blocks** were found. A hand check gave
     **100/100 correctly attributed**.
   - About **1-2% of blocks** need an editor: missed continuations, cast lines taken as
     speech, and aliases such as FIB/FIBBER.
   - On the USDA typescripts, the plain OCR text separates **58-100% of role labels** from
     their speeches, because of the two-column page layout. Rebuilding rows from hOCR word
     coordinates restores them, which was shown on a real page.
6. **Recommendation.** Use one canonical JSON script model with stable line ids, Fountain
   as the export format, and TEI or Standard Ebooks markup as import formats. A human
   editor must approve the role attribution before a script opens for casting. No model
   writes or rewrites a word of script text.

---

## 1. Public-domain sources of performable scripts

### 1.1 Stage plays

| Source | Measured | Structure | Rights evidence | Notes |
|---|---|---|---|---|
| **Project Gutenberg** | Catalog CSV (`pg_catalog.csv.gz`, 79,576 texts): **2,955** on "Category: Plays/Films/Dramas", **3,033** with that shelf or a "Drama" subject; **1,721 English**. **55** on the "One Act Plays" shelf, **78** with one-act in subject or title | Plain text: `ROLE.` on its own line (Wilde, Synge) or `ROLE: text` (Glaspell); stage directions in `[brackets]` or `_italics_` | Per-book RDF `dcterms:rights` reads "Public domain in the USA." (seen on #27357) | Many records are collections (Glaspell's *Plays* holds 7) or closet drama. **245** English records credit a translator: check the translation's date, not the play's (§1.6) |
| **Standard Ebooks** | `/ebooks?tags[]=drama`: 48 + 48 + 19 = **~115** titles | XHTML tables: `<td epub:type="z3998:persona">` for each speech. *Earnest* has 879 persona rows | Every page carries a "CC0 1.0 Universal Public Domain Dedication" | Best import format. The structure was written by a human editor, not inferred by us |
| **LibriVox** (cached `librivox.json.gz`) | **640** dramatic projects (genres Plays / Dramatic Readings / Drama); **574 English**; **591** with source year ≤ 1930; **444** descriptions carry a "LibriVox cast:" role→reader list; text sources: Gutenberg 377, archive.org 151, none 45 | The cast list gives role names exactly as the text spells them, e.g. "John Worthing, J.P.: Hans-Stefan Ducharme" | LibriVox records only public-domain texts | 8 projects have a source year after 1930. They are pulp SF stories (1952-62) that are free because nobody renewed them. LibriVox already pairs script, role list and recording |
| **Wikisource (en)** | `Category:Plays` has **85 pages + 8 subcategories** directly (API, measured once); the deep count was **blocked by HTTP 429** from the shared proxy | Mostly proofread transcriptions of PD editions, with page scans | The texts are PD; Wikisource adds CC BY-SA for its own contributions | To measure (probe §7) |
| **Folger Shakespeare** | — | TEI Simple, fully structured | Folger: "free to use for all **non-commercial** purposes"; DraCor lists its Folger-derived Shakespeare corpus as **CC BY-NC 3.0** | **Avoid.** NC is not public domain, and archive.org uploads of derived recordings would inherit the restriction. Use Gutenberg or Standard Ebooks Shakespeare instead |
| **DraCor** (dracor.org) | 24 corpora; American corpus **40** plays (1765-1949); English corpus 753 plays (1485-1700) | TEI with `<sp who>`, `<castList>` | Per corpus: CC0 (German, Ibsen, Russian…), CC BY-NC (Shakespeare, French) | A good *structured* import for early modern English and translated drama. Check each corpus's licence |

**Rights rule for stage plays.** A play published in the US in 1930 or earlier is free in
2026 (Decision 137's age line, which moves each 1 January). A play published 1931-63 is free
only if its renewal is missing, which is exactly what Gutenberg's clearance establishes; we
should rely on the Gutenberg clearance, not on the age line. Foreign plays published
1931-1977 may have been restored by the URAA (Decision 156), so the play's own year and
country decide.

### 1.2 Radio scripts: which are actually public domain

The underlying rule is in 02-rights §3.1. What changes here is **(c)**, the "pre-1931" class.
Statute (read today):

- §303(a): copyright in a work created before 1978 but "not theretofore in the public domain
  or copyrighted, subsists from January 1, 1978, and endures for the term provided by section
  302 … if the work is published on or before December 31, 2002, the term … shall not expire
  before December 31, 2047."
- §302(c): a work made for hire or anonymous work "endures for a term of 95 years from the
  year of its first publication, or a term of 120 years from the year of its creation,
  whichever expires first."

| Class | What frees it | Evidence a reader can open | Measured supply |
|---|---|---|---|
| **(a) US government** | §105: "prepared by an officer or employee of the United States Government as part of that person's official duties" | Item metadata + author's employer | `collection:usda-unclesamsforrang` **562** (45-52 a year, 1932-1944); `usda-usdaradioservice` **747** (mostly talks); NAL items titled drama/playlet/skit/radio-play subject **30**; dialogues **109**; *Housekeepers' Chat* **22** volumes |
| **(b) Registered (Class D) and not renewed** | 28-year term lapsed | The CCE registration entry, plus the absence of a renewal in year +27/+28 | 1947-49 volumes: **3,342** radio-mentioning registrations, **146** with a renewal row (§1.3) |
| **(c) Published 1930 or earlier** | 95 years from publication | The published book or pamphlet | Gutenberg "Radio plays" subject: **5** records (4 Carlton plays + 1 novel); archive.org open-access "radio plays" texts **22** (mostly not plays) |
| (c′) Registered 1930 or earlier, unpublished | 95 years from **registration** (expired either way) | CCE registration | 1928-1946 dramatic-composition volumes are on archive.org (Part 1 Group 3, 1928-45 found). The 1938 OCR interleaves two columns (below) |
| (c″) Unpublished, unregistered, individual author died in 1955 or earlier, not for hire | §302(a) life + 70 | Author identity and death date (Wikidata) | Unmeasured. Requires knowing who wrote it and that it was not a staff assignment |
| **Not free** | Unpublished, unregistered network script, written for hire | — | The default: §303, 120 years from creation (1945 → 2065) |

**Two traps inside the "free" classes:**
- **Adaptation.** A free script that adapts a protected story is not free; the Lux / Screen
  Guild logic is in 02-rights §3.3. Forest Rangers episodes say what they adapt: the 1937
  item's episode is "adapted from a story entitled 'War Eagle War', by Julian Rothery of the
  U. S. Forest Service", which is also government work. Each episode needs its source
  checked.
- **Collection is not authorship.** Items in the National Agricultural Library are not all
  USDA work. One 1943 item reads "source, 'Womanpower' (CBS and Federal Security Admin)".
  Each item needs an author and employer recorded before it is classed `gov`.

**Music inside scripts.** Songs, themes and lyrics in a free script are separate works
(02-rights §3.2). A *Fibber McGee* script carries a King's Men number. The recording studio
should mark `MUSIC:` cues as "not performable" unless the composition is itself free.

### 1.3 Registered and not renewed: can it be proven from the CCE?

**Yes, from data we already hold, for 1947-1949 registrations.**
- From 1947, each annual "Dramas and Works Prepared for Oral Delivery" volume prints the
  year's *registrations*. The 1947 preface says it lists "all registrations in Class C … and
  Class D … Radio, television and film scripts comprise a substantial portion".
- From 1951, the same volumes print *renewals*, which the catalog already parsed
  (11,166 rows).
- Radio series are entered under the series with each script's air date and registration
  number. Example: "FIBBER MC GEE AND MOLLY. (Radio program) … © S.C. Johnson & son, inc. …
  30-32. Apr. 22, 29, May 6, 1947. © 1c each 27May47; D unp. 10030-10032."
- So a registration number can be joined to the renewal file on class + number.

Measured (scratchpad `cce_regs.py`, every D-number token, any entry mentioning radio):

| Registered | D registrations | Mention radio | With a renewal row | Renewal volumes that cover them |
|---|---|---|---|---|
| 1947 | 6,189 | 1,140 | 63 | 1974-75 |
| 1948 | 5,752 | 1,077 | 22 | 1975-76 |
| 1949 | 5,067 | 1,125 | 61 | 1976-77 |
| 1950 | 4,224 | 1,233 | 48 | 1977 + **1978 online records (not read)** |

**How a non-renewal is proven, and its limits:**
1. **The renewal file misses entries to OCR damage.** The README measures a loss of a
   quarter to a third in the worst 1970s volumes, so a missing renewal row is not proof on
   its own.
2. **The second test is a name search in the raw OCR** of all five renewal-era volumes
   (1973-77). Every renewal layout from 1971 prints the series in parentheses, so a renewed
   episode almost always puts the series name on the page.
   - Example: "fibber" appears **0 times** in the 1974-77 volumes.
   - For contrast, *Life of Riley* appears with **44** renewal rows, and the 1947-50
     *Lone Ranger* with 214.
3. **A person then checks the scanned pages** for that year's renewals under the series and
   the claimant. The `src` links already open the scan.
4. **1950 registrations** renew partly in 1978, which is the Copyright Office's online
   catalog (publicrecords.copyright.gov). One query per series.
5. **1928-1946 registrations** are in the New Series "Part 1, Group 3: Dramatic Compositions"
   volumes, which are on archive.org (e.g. `catalogofcopyrig111libr`, 1938). The 1938 OCR
   **interleaves two columns** ("City desk; by M. Gilman and H. S.|Cosmoso; by M. Gottesman.
   © 1 ©. Kraft! …"), so it needs the hOCR coordinate rebuild described in §2.3 before
   it can be parsed.

**Having a registration does not mean having the text.** Deposit copies went to the
Copyright Office and Library of Congress. The texts we can actually read are GRW
transcriptions, scans in archives, and the UCSF Industry Documents Library (tobacco-sponsored
series; GRW links collections for Dragnet, The Fat Man, Blondie, FBI in Peace and War and
others). For each "lapsed" registration, the job is to find a surviving copy.

### 1.4 Generic Radio Workshop, quantified

GRW's own statement (genericradio.com/copyright, read today) is "TLDR: Assume Copyright".
It also reasons that "the average mimeographed radio script was never published … So unless
its author died before 1938 [sic, written for an earlier year], that script is still under
copyright", and that scripts "published in books ('Best Radio Plays of 1938' for example)
have a greater chance of being in the public domain". Its home page says: "We make no claims
to ownership … they remain … the copyright of their respective owners."

Index measured today (`.cache/grw/scripts.json`): **1,371 scripts, 206 series, 0 failed
series pages**. Dated 1925-1930: 29; 1946-10 to 1950: 399; undated: 104.

| Clean class | GRW scripts | Which |
|---|---|---|
| Government | **10** (+3 **UNVERIFIED**) | *Uncle Sam's Forest Rangers* 10 (also on archive.org). *You Can't Do Business With Hitler* 3 was an OWI production; whether federal employees wrote it is unverified |
| Published ≤1930, text on Gutenberg | **3** | GRW's "Great Moments in History" (1926-28): *Landing of the Pilgrims*, *Story of Nathan Hale*, *Washington Crossing the Delaware*, which are Carlton's published plays (PG 27357, 28527; archive.org `washingtoncrossi28205gut`) |
| Dated ≤1930, otherwise | 26 | **Not free by age.** Unpublished: needs a registration (CCE 1925-30, not yet read) or an author who died ≤1955 |
| Registered (exact series + air date in the 1947-50 volumes) | **20** of 399 | Life of Riley 8, Fibber 4, Gildersleeve 2, Let's Pretend 2, Lone Ranger 1, Green Hornet 1, Dr. Christian 1, First Nighter 1 |
| …of which **no renewal trace** in the 1973-77 OCR | **9** | Fibber McGee 1947-05-06 "Good Grammar" (D unp. 10032), 1949-01-18, 1949-02-22, 1949-03-01; Gildersleeve 1948-04-21, 1948-09-08; Dr. Christian 1947-11-26; First Nighter 1947-12-18; Green Hornet 1947-11-11 (the only "Green Hornet" text in 1974 is an unrelated 1974 play, DU92615) |
| Registered and renewed | 11 | Life of Riley, Let's Pretend, Lone Ranger |

**Total clearly free: 22 of 1,371 (1.6%), and 9 that exist nowhere else as open text.**

**GRW text is not the registered script.**
- **73 of 316** cached texts mention transcription ("Thanks goes to Tom Cherry for this
  transcription").
- Cast blocks carry the transcriber's own notes ("MR. WIMPLE, wimpy; Droopy Dog voice").
- A faithful transcription of a free script adds nothing protectable, but the notes are
  GRW's, and scraping is governed by GRW's terms.

**Recommendation:** use GRW to find scripts and dates, ask GRW (Lou Genco) for permission on
the free subset, and strip transcriber notes. A free script also keeps its trademarks:
"Johnson's Wax" commercials, and titles such as "Green Hornet".

### 1.5 Teleplays (quick assessment)

- **Television scripts are in the same CCE drama volumes.** Mentions of television rise
  from 53 (1947) to 677 (1950), 656 (1952), 616 (1955), 348 (1958) and 173 (1962), while
  radio falls from 1,400 to 109.
- **Teleplays registered 1950-77** renew from 1978, so their renewals are in the Copyright
  Office's **online** records. The non-renewal test is therefore one search per registration,
  with no OCR involved, which makes it cleaner than for radio.
- **Unregistered teleplays** are §303 works, the same as radio scripts.
- **Two layers to check.** A teleplay adapting a protected story or novel is the Lux case
  again. A teleplay also comes with a filmed program, which is a separately protected work
  (Archive Watch's TV audit applies to the recording, not the script).
- **Verdict:** feasible as a second phase. Proof is cleaner than for radio, the supply of
  surviving texts is unmeasured, and teleplay format adds camera direction we would drop.

### 1.6 The translation trap

A public-domain play in a modern translation is the **translator's** copyrighted derivative.
- **Chekhov:** Gutenberg's *Plays by Anton Chekhov, Second Series* is Julius West's
  translation (1891-1918), which is free. A 1990s translation is not.
- **Ibsen:** Gutenberg's *Ghosts* and *A Doll's House* are R. Farquharson Sharp's (1864-1945).
  Archer's are free; Fjelde's (1965) are not.
- **How to apply:** record `translator` and the translation's own publication year in rights
  evidence, and judge that year. Never infer "PD" from the playwright. Gutenberg's catalog
  names the translator (`[Translator]` in Authors) on 245 English drama records.
- **The same trap applies to users' own uploads** of "a script I found". The app should
  accept only scripts imported from a source with rights evidence.

---

## 2. Script structure and parsing (measured)

### 2.1 Radio conventions seen in the GRW texts

| Element | Forms seen | Rule |
|---|---|---|
| Speech | `FIBBER: text`, `Announcer: text` (Damon Runyon), `ALLEN     text` (3+ spaces), `ROLE` alone then text, `[NARRATOR]:`, `2ND ANNCR:`, `NUÑEZ:` | Role = 1-5 words before `:`/`;`; ordinals and non-ASCII allowed |
| Sound | `SOUND:`, `SFX:`, `F/X:`, `FX:`, `SOUND EFFECT`, `BIZ`, and bare `DOOR SLAM:`, `CROWD: MURMURS`, `TELEPHONE: CUTS OFF` | Tag list, plus a sound-noun list that demotes false roles |
| Music | `MUSIC:`, `ORCHESTRA:`, `THEME`, `BRIDGE`, `STING`, prose ("Incidental music closes scene.") | Tag list; prose cues stay unclassified for the editor |
| Directions | `(FADING IN)`, `(FILTER)`, `(OFF)`, `(CHUCKLING)`, `[_off_]`, `[_coming in_]` | Parenthetical inside a speech → `direction`; mic words (in/off/fade/filter) → `mic` |
| Cast | `CAST:` then names, often `NAME, description` ("BETTY, teenage daughter"; "PEGGY (1 line)") | Header-triggered block |
| Non-script | Network IDs, commercials, "NOTE: This script aired…", dates, credits | Left unclassified; commercials should be flagged, not cast |

### 2.2 Measured on 316 cached GRW texts (`radio_parse.py`)

- **25 of 316 are stubs**: link pages ("Scanned scripts from the tobacco industry archives",
  Dimension X pointers) or a different layout. **291** were parsed.
- **Blocks:** speech **84,063**, cue **10,432**, direction **1,005**, unclassified **4,593**
  (4.6%). Speech share per script: median **0.85**, 10th percentile 0.73.
- **Precision (hand check).** Random 100 speech blocks: **100/100 correctly attributed**,
  including 2ND ANNCR, 2ND JUROR, THE VOICE and group roles. Random 40 cues: **40/40 non-speech**
  and 39/40 the right kind (an "OPENING COMMERCIAL" was typed as sound).
- **Recall: the 50 unclassified blocks sampled split as follows.**
  - ~20 cast-list entries.
  - ~10 continuation paragraphs of a long speech (should join the speech before).
  - ~8 untagged cues (`LAUGHTER`, `APPLAUSE`, `HOOFBEATS quicken`, `MUSIC UP AND OUT`).
  - 3 genuine missed speeches (`EDGAR Yes…`, `COMMISSIONER (shouts…) Leiningen!`,
    `DIRECTOR:`, a role that collides with a stop-word).
  - Network IDs, notes and dates.
  - Extrapolated, roughly **1,100-1,400 of ~84,000 speech blocks (1.3-1.7%)** need an
    editor's touch.
- **Roles.** Median **12** per script (max 43). Median **8** roles have 5+ lines and are the
  castable parts. Median **3** have 2 lines or fewer, and **244 of 1,197** such rare roles are
  near-duplicates of a frequent role (CARSTY/CARSTAIRS, BRAODWAY, DOC/DOCTOR).
- **Frequent aliases need a per-series table.** FIB (1,154 speeches) / FIBBER (2,016); MOL
  (792) / MOLLY (1,528).
- **Size.** Median script is **279 speeches, 4,122 words** (range 28-919, 577-10,502).
- **Cast headers.** **188** scripts have one, and they contain on average **79%** of the
  script's frequent roles (the rest appear unlisted or under a full name).
- **Gender.** Of 1,999 cast entries, **815** carry a description and **425 (21%)** a gender
  cue word. Gender cannot be read from the text for most roles.

### 2.3 OCR typescripts (USDA): the layout is the problem, not the words

- **Raw text.** In `_djvu.txt`, role labels on many pages come out as a column by
  themselves ("BESS: / JIMS / BESS: / JIM: / MARY; / JERRY:") followed by the speeches.
- **Measured on 11 Forest Rangers items:** **58-100%** of role labels sit in such runs
  (median ~80%). Plain-text attribution is unusable.
- **Fix, demonstrated.** Rebuilding rows from `_hocr.html` word boxes (group words by
  vertical center, sort by x) restores the page. Output for page 3 of `CAT11087275262`:
  `BESS: It was enough to worry a person to death.` / `JIMS That was a long time ago,
  Bess…` / `JIM: That's right, Bess. (CHUCKLING-) Those old boys…`.
- **Remaining work is character-level OCR repair:** "JIMS" for "JIM:", "elseo", "dayso",
  "HUSICs" for "MUSIC:". This is transcription, done against the page image (§4).

### 2.4 Stage plays in Gutenberg plain text (`stage_parse.py`)

| Play | Format | Parsed speeches | Check | Result |
|---|---|---|---|---|
| Wilde, *The Importance of Being Earnest* (PG 844) | `ROLE.` own line, `[directions]` | 877 | Standard Ebooks persona sequence (879), aligned | **877/879 in order**; the 2 misses are `GWENDOLEN and CECILY [Speaking together.]` |
| Carlton, *The Landing of the Pilgrims* (PG 27357, radio play) | `_CAST_` block; `ROLE` or `ROLE [_off_]` own line; inline `[_knock_]` | 293 | Independent label count in the text: 294 | **293/294**; the first ANNOUNCER label was taken as the last cast-list name |
| Glaspell, *Trifles* (in PG 10623) | `ROLE: (_direction_) text` | 150 | Lines starting `ROLE: `: 150 | 149 true + **1 false**: the bare cast name "MRS HALE" captured the SCENE paragraph; 1 continuation missed. Cast names ("GEORGE HENDERSON (County Attorney)") differ from speech labels ("COUNTY ATTORNEY"), which needs an alias |
| Synge, *Riders to the Sea* (PG 994) | `ROLE.` own line, `_direction_.—text` | 123 | — | 4 principal roles; the title was read as a role once; "CATHLEEN AND NORA" is a group speech |

**What the rules cannot settle**, and the editor must:
- group speeches ("ALL", "MOB", "X and Y");
- cast-list boundaries and aliases (full name in the cast list, short label in the
  speeches);
- continuation paragraphs;
- whether a bracket is a mic position, a sound cue or acting direction. In *Pilgrims*,
  "rattle of paper" was typed as acting direction and "mob assents" as sound.

### 2.5 Interchange formats

- **Fountain** (fountain.io/syntax, read today). "A Character element is any line entirely
  in uppercase, with one empty line before it"; `@` forces a character name with lower case;
  `^` marks dual dialogue; `(parentheticals)`; `[[notes]]`. Use it as an **export format**
  people can read and edit in screenwriting tools. It has no line ids, so we carry ours in
  notes (`[[L0042]]`) so a round trip keeps them.
- **TEI P5 drama module** (tei-c.org, DR chapter). `castList`, `sp` ("an individual speech"),
  `speaker`, `stage` with types (setting, entrance, exit…). Use it as an **import format**
  for DraCor and Wikisource-derived texts, and as an archival export.
- **Standard Ebooks XHTML** (`z3998:persona`). Import directly; no inference needed.

---

## 3. Canonical script data model (proposed)

The design rules are:
1. **Lines are identified by an id assigned once at import and never recomputed.** A
   correction changes `text` and bumps `rev`. It never changes `id`.
2. **Recordings attach to `(script_id, line_id, rev)`.** If an editor later fixes a line, a
   take recorded against rev 1 stays attached and is flagged "text changed since this take"
   when the difference is more than punctuation, so the reader decides whether to re-record.
3. **Re-import** of a corrected source aligns the new sequence to the old one with a
   sequence diff (the same alignment that matched *Earnest* above), so ids carry over.
   Inserted lines get new ids (`L0042a`), and deleted lines become `retired`, never reused.
4. **Cues sit inside a line at the position the script puts them** (`parts`), because "Of
   course, Pastor. [door opens] Good day to you, sir." is one speech with a sound in the
   middle.
5. **Rights evidence travels with the script.** It applies to the text, not to any recording
   of it.

```json
{
  "id": "gut-27357",
  "title": "The Landing of the Pilgrims",
  "kind": "radio_play",
  "authors": [{"name": "Henry Fisk Carlton", "born": 1892, "died": 1973, "role": "author"},
              {"name": "Claire Turner Zyve", "role": "editor"}],
  "source": {"name": "Project Gutenberg", "id": "27357",
             "url": "https://www.gutenberg.org/ebooks/27357",
             "edition": "Dramatic Hours in Colonial History series"},
  "rights": {"state": "clean", "bucket": "script_pd_published",
             "evidence": [{"claim": "Public domain in the USA.",
                           "src": "https://www.gutenberg.org/ebooks/27357.rdf"}],
             "translator": null, "adapts": null, "music_risk": "none"},
  "roles": [
    {"id": "RCARVER", "name": "CARVER", "cast_name": "ELDER CARVER", "aliases": [],
     "lines": 67, "words": 886, "gender": null, "voice_hint": null, "group": false},
    {"id": "RJONES", "name": "JONES", "cast_name": "CAPTAIN JONES",
     "lines": 71, "words": 795, "gender": null, "voice_hint": null, "group": false},
    {"id": "RMOB", "name": "MOB", "lines": 1, "words": 14, "group": true}
  ],
  "scenes": [{"id": "S1", "first_line": "L0001", "setting": "Leyden, Holland, early 1620"}],
  "lines": [
    {"id": "L0006", "role": "RCARVER", "rev": 1, "text_sha1": "46f871099f",
     "parts": [{"say": "I'll not lose faith, Pastor Robinson. I know a way will be found for us."},
               {"sound": "knock"}]},
    {"id": "L0008", "role": "RCARVER", "rev": 1, "text_sha1": "b0137140aa",
     "parts": [{"say": "Of course, Pastor."}, {"sound": "sound of opening door"},
               {"say": "Good day to you, sir."}]},
    {"id": "L0078", "role": "RCARVER", "rev": 1, "text_sha1": "a4ce1f3139",
     "parts": [{"mic": "off"}, {"say": "Oh, Pastor Robinson?"}]}
  ],
  "review": {"status": "parsed", "parser": "stage_parse 2026-10-18",
             "open_issues": ["first ANNOUNCER speech absorbed into cast list",
                             "cast names vs speech labels not yet aliased"],
             "approved_by": null, "approved_at": null},
  "edits": []
}
```

**Worked example, produced by the prototype from the real text** (PG 27357, Carlton's NBC
*Great Moments in History* play, Gutenberg-cleared). The lines above are verbatim output;
`cast_name`, `scenes` and `review` were filled in by hand to show the fields.
- **Roles found (lines / words):** CARVER 67/886, JONES 71/795, KIEFT 55/626, ROBINSON
  44/422, PETER 29/344, WESTON 9/104, ANNOUNCER 7/666, VOICE 7/32, ALL 3/16, MOB 1/14.
- **Totals:** 293 lines, 3,905 words.
- **Cues:** 13 sound cues and 6 mic positions placed inside speeches; 26 acting directions.
- **The one open defect** a reviewer would fix before casting: the opening ANNOUNCER
  narration (two paragraphs) was left unattributed. This is the case §4 exists for.

**Fields that need an editor, not a rule:**
- `gender` and `voice_hint` (register/age, used to pick a device voice for unrecorded roles).
  The text states them for about 21% of radio cast entries, and honorifics (Mrs, Miss, Mr)
  give a rule-based hint.
- `aliases`
- `group`
- `scenes`
- `music_risk` per `MUSIC:` cue.

**Storage on archive.org.**
- One item per script holds `script.json` (this model), the source text, and the rights
  evidence as files.
- Recordings live in their own items and reference `script_id`, `line_id` and `rev` in a
  manifest.
- The Worker/D1 holds only the mutable state (who claimed which role, review status), as
  Watch Together rooms do. This is 06/04's territory.

---

## 4. Human review: the correction workflow

1. **Import.** A parser produces `review.status = parsed`, with every unclassified block,
   rare role and cast/label mismatch listed in `open_issues`. These are the measured failure
   modes in §2.
2. **Attribution pass.** An editor works through the speeches in a side-by-side view: the
   source (text or page image) on one side, parsed lines on the other. They resolve:
   - aliases (FIB = FIBBER);
   - group roles;
   - continuations;
   - cast boundaries;
   - cue types.

   Every change is an entry in `edits` (who, when, line id, before → after), shown with the
   script's history.
3. **Text pass (OCR sources only).** The editor corrects OCR errors **to match the page
   image**. "elseo" → "else." is transcription. Changing the author's words is not allowed,
   and neither is modernizing dialect, which the Carlton preface explicitly says is
   deliberate ("the speeches have been written in the way in which these men and women would
   talk").
4. **Approve.** `review.status = approved` opens the script for casting. A script that has
   not been approved is listed without a record button. A later correction bumps the line's
   `rev`, and takes recorded earlier are flagged, not deleted.
5. **Who edits.** Start with the owner and invited editors. Later, a second reviewer
   (Distributed Proofreaders' model: several passes by different people) before a script
   becomes castable. This is itself collaborative work the app can invite people into.

**Why no model writes or rewrites script text.**
- **The rule.** The project rule (CLAUDE.md, owner 2026-09-26: "I don't want AI making lists
  and writing copy") applies directly. A script is the author's words, and the app's whole
  claim is that people are performing *that* text.
- **The rights.** A rewritten line is no longer the public-domain text: it is a new
  derivative of uncertain authorship. It would also break the evidence chain
  (`text_sha1` against the source).
- **The values.** "Why we build" asks for tools that make people more active. Proofreading
  and casting a script together is exactly that kind of work, and it should not be handed to
  a model.
- **What rules may do.** Deterministic rules may *propose* attributions and flag defects, as
  in §2, and a human accepts or rejects each one. A model must not draft cast descriptions,
  synopses, "modernized" lines or filled-in gaps where OCR failed. A gap stays marked
  `[illegible]` until a person reads the page.

---

## 5. The starting library (day one, by clean class)

| Class | Measured supply | Text quality | Roles / lines (measured examples) | Day-one realistic |
|---|---|---|---|---|
| Stage, Standard Ebooks (CC0, persona markup) | ~115 | Structured, proofread | *Earnest*: 9 roles, 879 speeches | **~100**, nearly no review needed |
| Stage, LibriVox-linked Gutenberg texts | 377 Gutenberg sources; 444 cast lists | Clean text + an existing role list to check against | *Riders*: 4 principal roles, 123 speeches; *Trifles*: 5 roles, 150 | **~150-300** one-acts and short plays first (one editor-hour each, est.) |
| Stage, other Gutenberg English drama | 1,721 records (incl. collections, translations) | Clean text, varied conventions | — | Grows with editors |
| Radio, government: Forest Rangers | 562 scripts, 1932-44 | Typescript OCR; needs hOCR rebuild + OCR repair | Page sample: JIM, JERRY, BESS, MARY, GALLOWAY, ANNOUNCER (5-8 roles, 15 min each) | **~20-50** in the first batch; the series is the strongest free radio drama found |
| Radio, government: other USDA dramas/dialogues | 30 dramas/playlets/skits + 109 dialogues | Typescript OCR | 2-6 roles | ~20, after authorship check |
| Radio, published ≤1930 | 5 Carlton plays (PG + archive.org) | Proofread (Distributed Proofreaders) | *Pilgrims*: 10 roles, 293 lines, 3,905 words | **5**, immediately |
| Radio, registered-not-renewed with surviving text | 9 GRW (1946-49), more as GRW and archives are matched | Transcription; needs GRW permission | Fibber "Good Grammar": cast of 9 incl. The King's Men (music cue) | **0** until permission + scan check; then ~9 |
| Radio, registered-not-renewed, text not yet found | ~3,200 1947-49 candidates (3,342 − 146), before OCR-loss correction | — | — | Research backlog, not a library |
| GRW otherwise | 1,349 | — | — | **Not offered** (assume copyright) |

**Day one is roughly 300-450 castable scripts, nearly all stage plays, plus about 25-55
genuine free radio plays.** The radio set is mostly Forest Rangers and Carlton. Its size is
set by editor time (attribution plus OCR repair), not by supply, so the first collaborative
feature the app needs may be the proofreading and attribution queue itself.

---

## 6. Risks and open owner questions

1. **Q-S1: radio-first or stage-first?** The free *radio* library is small (tens of scripts
   on day one) and the free *stage* library is large. Do we open with both, or only with
   radio scripts and accept a small start?
2. **Q-S2: GRW.** Ask Generic Radio Workshop for permission on the 9 + future
   registered-not-renewed scripts, or rebuild those texts from scans only?
3. **Q-S3: unpublished scripts by authors who died ≤1955 (§302(a) life + 70).** Legally free
   if not for hire. Proving "not for hire" for a network-era writer is hard. Do we accept
   individual-author evidence, or require registration or publication?
4. **Q-S4: who may approve a script.** Is it owner-only at first, invited editors, or a
   two-reviewer rule?
5. **Q-S5: commercials inside free scripts.** Johnson's Wax copy, the Camel jingles. Do we
   keep them as part of the historical text, offered as optional parts, or omit them from
   casting?
6. **Risk: OCR loss reads as non-renewal.** The renewal file loses roughly a quarter to a
   third of entries. A non-renewal must be confirmed by the series-name search plus a
   person reading the scan. Never let a missing row alone open a script.
7. **Risk: adaptations and music.** A lapsed script can adapt a protected story or embed a
   protected song. `rights.adapts` and `music_risk` must be filled before approval.
8. **Risk: translations.** A user who imports "Chekhov" may bring a protected translation.
   Allow only imports from sources with rights evidence.
9. **Risk: trademarks and characters.** A free 1947 *Fibber McGee* or *Green Hornet* script is
   free text, but titles and characters can carry trademark claims (02-rights §2). Recordings
   should be titled by episode, with the series as a fact, not a brand.
10. **Risk: NC licences dressed as "free".** Folger and some DraCor corpora are
    non-commercial. Archive.org recordings derived from them would carry NC terms. Exclude
    them.

## 7. To measure

```sh
# 1. Wikisource deep count of plays (blocked today by HTTP 429 through the shared proxy):
curl -A "ArchiveWatch-research/1.0 (contact)" \
 "https://en.wikisource.org/w/api.php?action=query&list=search&srsearch=deepcat:Plays&srnamespace=0&srinfo=totalhits&format=json"
# 2. CCE 1928-1946 dramatic-composition registrations (Part 1 Group 3, on archive.org):
#    fetch *_hocr.html, rebuild columns by x/y, count radio registrations per year, join
#    to cce_drama_renewals.json.gz on class+number.
# 3. 1950 registrations renewed in 1978: one publicrecords.copyright.gov search per
#    series registered in 1950 (Fibber, Gildersleeve, Cavalcade, Life of Riley...).
# 4. Forest Rangers at scale: hOCR row rebuild over all 562 items; measure the share of
#    speeches with a recognized role label after rebuild (today: 1 page shown by eye).
# 5. Forest Rangers adaptations: grep each episode for "adapted from" and record the
#    source author's employer.
# 6. HathiTrust full-view radio-play anthologies (catalog blocked by a Cloudflare
#    challenge today): subject "Radio plays", full view, US 1923-1963 -> pd/pdus.
# 7. The 1947-50 "radio" counts use a crude any-mention flag; sample 100 registrations
#    and measure how many are broadcast scripts.
# 8. Editor time: time 5 one-act plays and 5 Forest Rangers episodes from import to
#    approval, to replace the "one editor-hour" estimate in §5.
```

## Sources

- 17 U.S.C. §303, §302, §105 (read today): https://www.law.cornell.edu/uscode/text/17/303 ·
  https://www.law.cornell.edu/uscode/text/17/302 · https://www.law.cornell.edu/uscode/text/17/105
- Project Gutenberg catalog feed: https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv.gz ;
  rights field: https://www.gutenberg.org/ebooks/27357.rdf ; texts: https://www.gutenberg.org/ebooks/844 ,
  https://www.gutenberg.org/ebooks/994 , https://www.gutenberg.org/ebooks/10623 , https://www.gutenberg.org/ebooks/27357 ,
  https://www.gutenberg.org/ebooks/2467 , https://www.gutenberg.org/ebooks/7986
- Standard Ebooks drama: https://standardebooks.org/ebooks?tags%5B%5D=drama ;
  https://standardebooks.org/ebooks/oscar-wilde/the-importance-of-being-earnest/text/single-page (CC0)
- LibriVox API: https://librivox.org/api/feed/audiobooks/?id=243&format=json&extended=1 ; cached harvest `catalog/.cache/librivox.json.gz`
- Wikisource API (Category:Plays): https://en.wikisource.org/w/api.php?action=query&prop=categoryinfo&titles=Category:Plays&format=json
- Folger downloads ("free to use for all non-commercial purposes"): https://www.folger.edu/explore/shakespeares-works/download/
- DraCor corpora and licences: https://dracor.org/api/v1/corpora
- TEI P5 Performance Texts: https://tei-c.org/release/doc/tei-p5-doc/en/html/DR.html
- Fountain syntax: https://fountain.io/syntax/
- Generic Radio Workshop copyright page: https://www.genericradio.com/copyright ; library: https://www.genericradio.com/library.php
- USDA / NAL on archive.org: https://archive.org/details/usda-unclesamsforrang ,
  https://archive.org/details/usda-usdaradioservice , item https://archive.org/details/CAT11087275262
  (and its `_djvu.txt`, `_hocr.html`)
- Catalog of Copyright Entries, Dramas 1947-1977 (cached `catalog/.cache/cce_drama/`), e.g.
  https://archive.org/details/catalogofcopyrig3134libr (1947) ; New Series Part 1 Group 3, 1938:
  https://archive.org/details/catalogofcopyrig111libr
- Gutenberg radio plays on archive.org: https://archive.org/details/thelandingofthep27357gut ,
  https://archive.org/details/washingtoncrossi28205gut
- Prior project research: `docs/research/02-rights.md` §3; `catalog/README.md`

**UNVERIFIED in this document:**
- the first publication year of Carlton's *Dramatic Hours in Colonial History* (Gutenberg's
  clearance is the evidence relied on);
- whether *You Can't Do Business With Hitler* was written by federal employees;
- the Library of Congress's custody of Class D deposit copies;
- the Wikisource deep count.

Prototype code (copied into the repo 2026-10-18; they read caches under catalog/.cache and a scratch directory — adjust paths before rerunning):
`catalog/prototypes/scripts/radio_parse.py`,
`.../parse/stage_parse.py`, `.../parse/to_model.py`, `.../parse/measure_grw.py`,
`.../cce_regs.py`, `.../cce_match.py`, worked-example output `.../pilgrims_model.json`.
