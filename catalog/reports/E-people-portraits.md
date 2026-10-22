# Track E — credited people, Wikidata, and portraits (2026-10-21)

Built and run in this session against `out/radio-catalog.sqlite` as it stood on
2026-10-21 (53,925 `people`, 18,855 of them credited in `episode_credits`).
Every number below is MEASURED from the caches and the two new tables.

## What was built

| File | Does |
|---|---|
| `tools/harvest_people_wikidata.py` | Three resumable phases: (1) every name variant of every credited person, most-credited first, asked of the query service as exact en/mul label-or-alias of a human (P31 Q5), 150 variants per query; (2) each candidate's label, description, enwiki, birth/death with precision, occupations (P106 labels), P18, P345, P373, 200 items per query; (3) the Commons file page (`action=raw`) of each P18 of a MATCHED person and of each Track D file whose Structured Data depicts one. Track D's cached pages are read first. Caches under `.cache/people_wd/`, rewritten as each batch lands |
| `tools/enrich_people_art.py` | The matching rules and licence classes (pure functions), and the POST-BUILD step: drops and rebuilds only `people_wikidata`, `people_art`, `people_art_meta`; writes `out/enrich_people_art_report.json`. No network. Licences are classed again from the cached page text on every run, so a rule change needs no re-harvest |
| `tests/test_people_art.py` | 66 checks on synthetic data, 10 mutation controls (docstring) |

Run (all resumable; a killed run picks up at the last batch):

    python3 tools/harvest_people_wikidata.py               # ~2.8 h first run: names 15 min, entities 45 min, Commons pages 1 h 50 min
    python3 tools/harvest_people_wikidata.py --top 2000    # only the most-credited, if time is short
    python3 tools/enrich_people_art.py                     # seconds; after any build_db.py
    python3 tests/test_people_art.py                       # 66/66

Access: the query service answered every request (0 failed, no 429 in this
session); `commons.wikimedia.org/w/index.php?action=raw` answered at 1.5 s
spacing. No image binary was downloaded; `thumb_url` is Commons'
`Special:FilePath/<file>?width=330`, which a client may fetch itself.

## Tables

`people_wikidata` — one row per credited person: `qid` (or NULL), `basis` (how it
matched, or why it did not), `detail` (the competing QIDs when refused, the
occupations when matched undated), label, description, Wikidata birth/death,
occupations, IMDb, enwiki title, Commons category, `credited_episodes`, `rank`
(1 = most credited), `evidence_url` (the Wikidata item).

`people_art` — one row per (person, file): `found_via` (`wikidata:P18` or
`commons:depicts`), `license_class`, `usable`, `template` as written on the page,
`obligations` (`attribution` / `attribution, share-alike`), `author` (the file
page's author/photographer field, markup stripped), `date_field`,
`source_links` (from `|source=`), `evidence_url` (the file page), `thumb_url`.

## Matching rules (conservative; every row says which applied)

- **Candidates**: Wikidata humans whose English or `mul` label or alias equals one
  of the person's name variants: the name, every spelling in `names`, the birth
  name, the name without a quoted or parenthesized nickname, the nickname +
  surname, without middle initials (never when the FIRST token is an initial:
  "E. G. Marshall" stays whole), "Jr." forms, and von/Von particle case. Groups
  ("… and His Orchestra", "The King's Men", "Honey Dreamers, The") and one-word
  names are never asked (1,039 credited "people" are groups).
- **When we hold a birth or death year** (OTRRpedia's), each event is compared:
  `day` (same full date), `year` (same year), `near` (one year apart),
  `monthday` (same month and day, years 2-10 apart), `conflict`. A candidate
  needs no conflict and a `day` or `year` on one event (or `monthday` beside
  `near`). One such candidate matches; several are ambiguous unless exactly one
  agrees on both events. A candidate with no Wikidata years is refused.
  `monthday` exists because performers' birth years differ between sources while
  the birthday and death date agree exactly: Joseph Kearns 1904/1907, Hans
  Conried 1915/1917, Alice Faye 1912/1915, Gracie Allen 1902/1895, Laird Cregar
  1916/1913 (all with an exact death date).
- **When we hold no year**: exactly ONE human candidate across all variants; it
  carries a radio-trade occupation (actor, writer, announcer, broadcaster,
  musician, singer, director, producer, composer, comedian, journalist …,
  `RELEVANT_OCC`); it has a Wikidata year; and it fits our credits' era (born at
  least 12 years before the first credited air date, not dead before it).
- The enwiki-radio-category route in the brief was not used: the occupation rule
  plus uniqueness already covers it and costs nothing extra.

## Measured: matches

| | People | Matched | Dated rule | Undated rule | IMDb | enwiki |
|---|---|---|---|---|---|---|
| top 500 by credited episodes | 500 | **339 (68%)** | 321 | 18 | 319 | 315 |
| top 2,000 | 2,000 | **1,109 (55%)** | 1,023 | 86 | 1,023 | 1,015 |
| all credited | 18,855 | **5,204 (28%)** | 3,629 | 1,575 | 4,531 | 4,780 |

Why the rest did not match (all 18,855): no human of that name on Wikidata
7,523; several namesakes and no date of ours to choose by 3,307; one namesake
with an unrelated occupation 1,034 (football players, politicians …); dates
disagree 488; a group, not a person 1,039; undated namesake from the wrong era
167; no Wikidata year to check 82; several agreeing 11.

67 QIDs are matched by more than one person id: duplicates in `people` itself
("Ken Carpenter" otrr:50356 and "Kenneth 'Ken' Carpenter" otrr:970; Chester Lauck
as goldin: and otrr:), not matching errors. Worth merging in Track C.

**Known-good controls** (all match on the dated rule): Orson Welles Q24829, Agnes
Moorehead Q231221, William Conrad Q505831, Lucille Fletcher Q2249482, Arch Oboler
Q632079, Jack Benny Q148732, Elliott Lewis Q5365687, Norman Corwin Q1251336; also
Fred Allen, Gracie Allen, Hans Conried, Mercedes McCambridge, Carlton E. Morse,
Raymond Edward Johnson, and Wyllis Cooper (undated rule; Goldin-only record).

**False-match check, by hand** — two random samples of 30 matches (seeds 7 and
11; 15 dated + 15 undated each), our credits (top series, roles, years) read
against the Wikidata item's description, occupations and dates:

| Sample | Wrong | Notes |
|---|---|---|
| dated, 30 | **1** | Dorothy 'Dotty' McGuire: credited on Lux / Theater Guild 1941-55 (the actress, 1916-2001), but OTRRpedia's record carries the dates of the McGuire Sisters singer (1928-2012), so we matched the singer exactly. An upstream conflation, not a rule failure: no date rule can catch it |
| undated, 30 | **1** (+1 unconfirmed) | Peggy Lloyd, credited once as "daughter of Harold Lloyd" (1954), matched Peggy Lloyd 1913-2011, stage actress and Norman Lloyd's wife. Robert Chesterman (Nightfall, CBC 1982) -> a film director/producer 1931-2007: plausible, not confirmed |

So about **1 in 30 on each rule (~3%)** wrong in these samples, with the undated
rule the weaker and the only one that can fail on its own logic. Also seen:
Senator Joseph McCarthy (matched correctly: he is the record's dates and is heard
on Hear It Now) carries one Lux "composer" credit that belongs to the songwriter
Joseph McCarthy — again an OTRR conflation. A client should show portraits from
undated matches only after a person has looked, or not at all.

## Measured: portraits

3,876 (person, file) rows, 3,765 distinct files, every page read (0 unread,
0 missing): 3,610 from P18, 266 from Track D's Commons files whose Structured
Data depicts the person.

| | Matched | With any image | With a usable image |
|---|---|---|---|
| top 500 | 339 | 223 | **219** |
| top 2,000 | 1,109 | 767 | **734** |
| all | 5,204 | 3,503 | **3,177** (2,498 on dated matches, 679 undated) |

Of the top 500's matched people, 116 have no image at all on Wikidata or in
Track D's depicts; 4 have only unusable ones.

People with a usable portrait, by the best class they have:

| Best class | top 500 | top 2,000 | all |
|---|---|---|---|
| `pd_us` | 205 | 643 | 2,605 |
| `pd_us_gov` | 1 | 7 | 88 |
| `cc0` | 0 | 11 | 35 |
| `pd_release` | 0 | 10 | 131 |
| `free_use` | 0 | 1 | 3 |
| `cc_by` (attribution) | 3 | 26 | 135 |
| `cc_by_sa` (attribution, share-alike) | 10 | 36 | 180 |

315 people's only usable portraits carry an obligation (CC BY or BY-SA): the
client must show the author and licence, and a BY-SA crop or edit shares alike.

Files by class: `pd_us` 2,798 (PD-Pre1978 910, PD-US-not renewed 660, PD-US-no
notice 501, PD-US-expired 186, PD-US 159, PD-1923 54, … ), `cc_by_sa` 195,
`pd_source_only` 172, `cc_by` 144, `pd_release` 133 (mostly PD-Gottlieb jazz
photographs), `no_known_restrictions` 115, `pd_us_gov` 98, `unknown` 56, `cc0`
39, `gfdl_only` 12, `free_use` 3.

## Licence rules

Read from the file page's wikitext; Track D's `template_class` (PD-US templates
and their redirects) is reused by import, and wrappers' parameters are read
(`{{self|…|Cc-by-sa-3.0}}`, `{{PD-Art|PD-old-auto-expired}}`,
`{{PD-scan|1=PD-US-no notice}}`), including through nested templates.

- **usable**: `pd_us` (PD-US-*, PD-US, PD-1996, PD-*-expired, PD-old-*-1923, and
  the redirects read on Commons today: PD-Pre1978, PD-Pre1964, PD-old-auto-1978,
  PD-old-auto-1964; NoC-US); `pd_us_gov` (PD-USGov*); `cc0`; `pd_release`
  (PD-self/author/user, PD-Gottlieb, PD-NYWT&S); `free_use` ("Copyrighted free
  use"); `cc_by` (incl. LATimes UCLA, CC BY 4.0); `cc_by_sa`.
- **not usable**: `contested` (a deletion request, copyvio, no-permission,
  no-source or no-licence tag on the page outranks any licence); `gfdl_only`;
  `pd_source_only` (PD-old-70, PD-Canada, PD-Australia, PD-because …: no US
  evidence); `no_known_restrictions` (Flickr Commons and the Library of
  Congress's "no known copyright restrictions": PD-Van Vechten, PD-Bain,
  PD-Harris-Ewing, PD-National Photo Company — a statement that nothing is known,
  not a determination); `unknown` (user-space templates, a placeholder, nothing
  recognized).

Each template decision taken from a template page is cited in the code
(`ALIASES`), with what the page says.

## Caveats

- **A Commons tag is a claim, not proof.** As Track D found, many PD-US-no
  notice / PD-Pre1978 tags on publicity stills rest on nobody having seen the
  back of the print. `source_links` are recorded (2,475 of the usable files
  carry one: eBay, Heritage Auctions, LOC …) so a person can check before a
  portrait ships. 630 usable files have no author or "unknown".
- **P18 is often not the radio-era face.** Agnes Moorehead's P18 is a 1969
  Bewitched still, William Conrad's a 1972 Cannon still; both are tagged
  PD-Pre1978 and usable, but a radio app may prefer a 1940s photograph. The
  P373 Commons categories were NOT crawled (each MWAPI category read costs
  ~50 s, Track D measured); `commons_category` is recorded so it can be.
- Orson Welles' P18 is the Van Vechten portrait (LOC, not usable here); he
  still has two usable portraits through Track D's depicts (a CC0 NPG scan and a
  1938 PD-US-not renewed photograph).
- Our dates are OTRRpedia's and are sometimes wrong (shaved birth years) or
  belong to a namesake (McGuire). The `monthday` rule absorbs the first; nothing
  here absorbs the second.
- Only people with at least one `episode_credits` row were matched (18,855 of
  53,925).

## Open questions

1. Library of Congress "no known restrictions" collections (Van Vechten 44
   files, Bain 38, Harris & Ewing 11): count them as usable? Many Bain images are
   pre-1930 and would be PD by age, but the tag does not say so per image.
2. Should portraits from undated (`name+occupation+unique`) matches be shown
   without review? The sample says ~1 in 30 is someone else.
3. Is a modern-era still (a 1969 TV still tagged PD-Pre1978) acceptable as a
   radio performer's portrait, or should a radio-era image be preferred and
   found via the person's Commons category (a ~1 h crawl for the top 2,000)?
4. Merge the 67 duplicate person ids in `people` (Track C).
5. 3,307 ambiguous undated people (OTRRpedia has no dates for them) could be
   resolved by Goldin's or OTRRpedia's own dates if a later harvest finds them,
   or by series co-credit evidence; not attempted.
