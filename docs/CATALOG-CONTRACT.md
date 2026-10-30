# Ear Drama catalog contract

> **DRAFT v1, 2026-10-22 (loop tick 9).** The publish step exists
> (`.github/workflows/catalog-publish.yml`, §7); its first real run is pending.
> Sizes still marked *to measure* are settled by that run. When this doc and the
> code disagree, the code wins, and the doc is fixed in the same change.

I want every Ear Drama app, on every platform, to show the same episode with
the same date, the same cast, the same rights line, and the same default copy,
because none of them works any of it out for itself. The catalog in `catalog/`
decides all of that once, in the pipeline, and publishes it; the apps read it
and filter it with a `WHERE` clause. This is the `shared-data-plane-contract`
skill applied to radio, and Archive Watch's `CATALOG-CONTRACT.md` is its model.

## 1. The one rule

No client re-derives, re-audits, re-matches, re-ranks, or re-hosts anything in
this catalog. Rights states, the default copy, broadcast seasons, genres,
evenings, the transcript gate, and the never-recommended flag are all pipeline
outputs. A client that needs a value the plane does not carry asks for a new
field here; it never computes one.

## 2. Published assets

| Asset | Host | For | Notes |
|---|---|---|---|
| `ear-drama.sqlite.zz` | GitHub Release, rolling tag `catalog-latest` (`https://github.com/bhwilkoff/Ear-Drama/releases/download/catalog-latest/ear-drama.sqlite.zz`) | Apple and Android apps | the served projection (§3), raw DEFLATE (`zlib.compressobj(9, DEFLATED, -15)`), built by `catalog/tools/build_projection.py`; MEASURED 2026-10-22 on a rebuild from the 2026-10-21 caches: 26.2 MB compressed, 127 MB on disk, 116,380 episodes (clean-only: 1.0 MB, 5.4 MB, 14,670) |
| `manifest.json` | the same Release | every native client, tooling | the served projection's: `schemaVersion`, `generatedAt`, `cleanOnly`, row counts, `rightsLines`, `listenShelves` (§5.1), `forwarding` (§3.5), bytes, sha256 of the `.zz`; uploaded after the `.zz` it vouches for |
| `data/manifest.json` | GitHub Pages | web, smart-TV web, Roku | the web projection's own manifest (counts, field names, shard math, rights lines, `listenShelves` cut to the web's own served rows (§5.1), bytes); not the site's `/manifest.json`, which is the web app manifest |
| `ear-drama-seed.sqlite` | bundled in each native app | first launch offline | a small slice (clean pools plus the Radio tab's next week); *size to measure* |
| `data/index/`, `data/series/{key}.json`, `data/episodes/{shard}.json`, `data/search/` | GitHub Pages, deployed by Actions with the site (never committed) | web, smart-TV web, Roku | §4, built by `catalog/tools/build_web_projection.py`; MEASURED 2026-10-22, gate closed: 14,670 episodes in 656 series, 7.2 MB raw |
| `tonight.json` | `catalog-latest` beside the database, and `data/tonight.json` on Pages | every client's Radio tab | §8; the web's copy withholds what the web projection does not serve |
| `radiologs.tar.xz` | rolling Release `radiologs-latest` | the pipeline only | the measured evenings (`evenings.jsonl`: station, time, program as printed, matched episode) and the log links (`log-urls.json`); facts only, never the newspaper pages, which stay JJ's (docs/research/evenings.md §1) |
| `loudness.json.gz` (and `loudness.prev.json.gz`, the one before) | rolling Release `loudness-latest` | the pipeline only | the loudness measurements by episode id, with errors and `suspect` rows kept as evidence; written by `.github/workflows/catalog-loudness.yml`, read by the publish step into §3.1's `loudness_i` and `loudness_tp`; never read by a client |
| `transcripts.json.gz` (and `transcripts.prev.json.gz`, the one before) | rolling Release `transcripts-latest` | the pipeline only | archive.org's automatic transcript of each served episode's default copy, by episode id, with the URL it was read from and the on-screen gate's verdict and features (`catalog/tools/fetch_transcripts.py`); misses and errors kept as evidence; written by `.github/workflows/catalog-transcripts.yml`, read by the publish step into §3.1's `has_transcript` and `transcript_url` and §3.4's search index; never read by a client. MEASURED 2026-10-22: 8,999 candidates; 233 fetched made 1.77 MB, so the full cache is about 68 MB gzipped (about 181 MB of text, median 21 KB a transcript) |
| `radio-catalog.sqlite.xz`, `harvest-cache.tar.xz`, `SHA256SUMS` | dated Release (`catalog-YYYY-MM-DD`) | the pipeline only | the full research database, hidden rows included, and every harvest cache; never read by a client. The publish step restores from the newest one and does not write it; a dated Release is cut by whoever refreshes the harvests |

Audio is never re-hosted. Every client plays `https://archive.org/download/{id}/{file}`
from the episode's default recording, percent-encoded by the pipeline (the stored
URLs hold raw spaces today). The browser plays it through an `<audio>` element,
which needs no CORS; archive.org's storage nodes also answered ranged GETs with
`access-control-allow-origin: *` on 2026-10-17 (research 04 §5), which the web's
loudness gain through Web Audio depends on and which the web must re-measure
before relying on it.

Refresh is an ETag-conditional GET (`If-None-Match`; 304 keeps the cache). A
downloaded database is validated before the swap: a size floor, `PRAGMA
integrity_check`, and `schemaVersion` at or above the app's minimum, then an
atomic rename. A half-downloaded catalog never becomes the live one.

## 3. The served projection (native SQLite)

Only rows whose `state` begins with `keep_` are served. Hidden rows never leave
the pipeline, so no client can show one by mistake. Every table below is
additive: new columns only, clients ignore what they do not know, and a field
is never renamed or repurposed.

### 3.1 `episodes`, the catalog row

The broadcast is the identity (research §4): one row per broadcast, however
many copies survive.

| Column | Type | Meaning |
|---|---|---|
| `id` | TEXT PK | stable episode id; dated episodes are `{seriesKey}|{YYYY-MM-DD}` |
| `series_key` | TEXT | → `series.key` |
| `air_date` | TEXT | `YYYY-MM-DD`, or NULL when no witness dates it |
| `date_source` | TEXT | which witness dated it (filename, OTRR log, Goldin, ID3 album tag) |
| `season` | TEXT | broadcast season, `1949-50`, computed in the pipeline (Decision 058); NULL when undated |
| `run_id` | TEXT | the dated run it belongs to, with that run's kind (R2) |
| `num` | INTEGER | log number, when a log gives one |
| `title` | TEXT | display title, computed once by `catalog/tools/titles.py` (catalog DECISIONS 022): upload numbering, codes, durations and the series' own name stripped where words remain, an all-capitals title set in the catalog's own case, a run-together word or one-hump token split only into words the catalog spells on their own (never a name a title spells whole), the series name stripped only where two or more of its episodes carry it (catalog DECISIONS 023); a series whose undated order rests on its leading numbers keeps them. No client re-derives it |
| `raw_title` | TEXT | the title as the source wrote it, only where it differs from `title`; NULL otherwise. Search indexes both |
| `aka` | TEXT | alternate titles (AFRS retitlings), JSON array |
| `length_s` | REAL | the default copy's measured length |
| `rights` | TEXT | `clean` or `unclaimed` (§6) |
| `rights_basis` | TEXT | the bucket that decided it, for the rights line's detail |
| `no_recommend` | TEXT | NULL, or the reason it is never recommended (§6) |
| `network`, `network_source` | TEXT | the network that aired it, and which witness says so |
| `sponsor` | TEXT | computed (`catalog/tools/sponsors.py`): the OTRRpedia dated sponsor run covering the air date, several joined by " / "; NULL when no dated run covers it, and "Sustained", "Multi", "Syndicated" are never published; clients show it as the third fact after the network, and the web detail shard carries it as `sponsor` |
| `has_transcript` | INTEGER | 1 only when the default copy's automatic transcript was fetched and passes the on-screen gate (Decision 058: 50-220 words a minute, at most 10% repeated four-word runs, `catalog/tools/transcript_gate.py`); 0 otherwise, including a transcript that failed the gate (neither shown nor searchable, §3.4) |
| `gain_db` | REAL | retired, always NULL: the target lives in the clients (Decision 061), so the pipeline publishes the measurement below, never a gain |
| `added_at` | TEXT | when the episode first appeared in a published catalog |
| `detail_json` | TEXT | Detail-only fields (credits, versions, other performances, witnesses), decoded only on Detail |
| `loudness_i` | REAL | the default copy's integrated loudness, LUFS (EBU R128, `ffmpeg ebur128=peak=true` over the whole file); NULL until measured |
| `loudness_tp` | REAL | the default copy's true peak, dBTP; NULL exactly when `loudness_i` is |
| `transcript_url` | TEXT | archive.org's own `{stem}.autogenerated.txt` beside the default copy, percent-encoded; set exactly when `has_transcript = 1`, NULL otherwise |
| `script` | TEXT | the id of a script in `catalog/plays/castable-scripts.json` a person may record this episode from (Decision 068, `catalog/tools/episode_scripts.py`); NULL otherwise |

**Transcripts** (Decision 058). A client shows a transcript only when
`has_transcript = 1`, fetches the text from `transcript_url` on demand, and
labels it automatic. The text is served by archive.org, not re-hosted, chosen
by measurement on 2026-10-22: a GET with `Origin` answered
`access-control-allow-origin: *` on both the archive.org 302 and the storage
node's 200 (`text/plain; charset=utf-8`), and a preflight `OPTIONS` answered
204 with `GET` allowed, so a browser can fetch it; a transcript is about 21 KB
(median of 233, largest 50 KB), sent uncompressed. Hosting the text ourselves
would mean about 181 MB on Pages or 9,000 Release assets, for text archive.org
already serves. The cost: the text a client reads can differ from the one the
gate judged if archive.org regenerates it; the next fetch of a new copy
re-judges it. The publish step re-runs the gate on the cached text with the
projection's own length, so a gate change applies without fetching again.
`manifest.json` counts `counts.transcripts` (shown) and
`counts.transcriptsSearchable` (indexed).

**Scripts** (Decision 068). `script` is set only when the pipeline matched a
script to this episode on series and air date, the two titles agree (equal, or
every content word of the shorter in the longer, at least two), and the script
is in the castable bundle with a castable rights bucket. The bundle is the
rights test's output (`script_rights.py`), so the projection judges nothing. A
script whose source has not given permission (Generic Radio Workshop, until it
answers) is matched and counted in the build log, never linked. A client shows
"Start an ear drama" on Detail only when `script` names a script its own copy
of the bundle holds (a newer catalog can name one an older app lacks), and
Browse's "Has a script" keeps a series with any linked episode. `manifest.json`
counts linked rows as `counts.scripts`. The guard is
`catalog/tests/test_episode_scripts.py`.

**Playback loudness** (Decision 067, superseding 061's per-file gain). No
client reads `loudness_i` or `loudness_tp`: every player levels volume on the
device as it plays (each platform's design doc names its mechanism), so a new
or unmeasured recording is leveled like any other. The columns stay, additive
and unread, filled only from measurements already taken; the measuring
workflow no longer runs on a schedule. The two columns describe
the rank-0 copy only; a measurement of another copy is never published, so a
new default copy reads NULL until it is measured. A measurement outside -45 to
-5 LUFS, or with a true peak above +6 dBTP, is kept in the pipeline as
`suspect` and never published. Coverage grows by batches
(`.github/workflows/catalog-loudness.yml`); `manifest.json` counts the filled
rows as `counts.loudness`.

### 3.2 `recordings`, the copies

`(episode_id, rank, archive_id, url, format, kbps, length_s, variant, partial)`;
`url` is percent-encoded by the pipeline and is the only path a client plays. Rank 0 is the default copy, chosen by `build_db.order_recordings`
(catalog DECISIONS 007): complete before partial, domestic before AFRS, OTRR's
copy, then measured bitrate. The versions picker lists the rest in rank order.

### 3.2a Commercial segments (R8): a seam, no data yet

R8 shows a broadcast's commercials as chapters and never skips them. No
source the pipeline reads marks where a commercial starts and ends (checked
2026-10-24: the research database's `recordings` carry no segment times, and
archive.org's files carry no chapter marks), so no projection carries chapters
and no player draws them. When a source does, its times arrive as
`segments (episode_id, rank, start_s, end_s, kind)` keyed to the copy they were
measured on, and each player shows them as chapters where the platform has
them (Apple's `AVPlayerItem.navigationMarkerGroups`, Media3's chapter metadata,
none on the web), never as a skip. Segment times are never estimated.

### 3.3 `series`, `runs`, `people`, `credits`, `art`, `arcs`

- `series`: `key`, `name` (the display name, `titles.display_name`: the same rules as a title, with no
  series to drop, so "01 The Hobbit" is "The Hobbit"; `raw_name` is the source's name where it
  differs, else NULL), `genre` (one of the eight, §5.5), `first_date`,
  `last_date`, `networks`, `episodes` (served count), `canonical_episodes` (what
  the logs say aired), `kind_summary`, `star` (§3.3a, or NULL), `sort_name` (below),
  `downloads` (below), `picture`, `picture_kind`, `picture_source` (§3.3a; all
  three NULL together), `year_counts` (below).
- **`series.year_counts`** (and `years` on the web series index and series page, as a number
  array): the run histogram, the series' served episodes per broadcast year, as text "first
  year,count,count,..." with one count per year from the first dated year to the last, 0 for a
  year with none ("1932,3,12,0,4" is 3 in 1932 and 4 in 1935); NULL when no served episode is
  dated. Each output counts its own rows, so the clean-only web counts what it serves. The run
  strip draws these years instead of a first-to-last span; none re-derives it.
  `build_projection.year_counts`; guarded in `tests/test_projection.py` (the counts sum to the
  dated episodes, the first and last years are not 0). MEASURED 2026-10-30 on the 2026-10-29
  caches: 4,202 of 10,641 series carry one, 35.8 KB of text in all, the longest 123 characters.
- **`series.downloads`** (and `downloads` on the web series index): Browse's
  "Popular" key, the series' `mostDownloaded` sum (§5.1, Decision 067):
  archive.org's own download counts over the distinct items holding its
  served episodes' default copies (`shelves.series_downloads`), kept only
  for a series with a recommendable served episode (`shelves.browse_downloads`).
  NULL, never 0, when no count was read or the series may not be
  recommended: Browse lists it after the counted ones, by `sort_name`
  (never recommended, always findable). Each output sums its own rows, so
  the clean-only web counts only what it serves. Every client sorts
  Popular by it (counted first, most first, then `sort_name`) and treats a
  catalog without the column as all uncounted, so Popular is A to Z; none
  re-derives it. `meta.counts.seriesDownloads` (the manifest's
  `counts.seriesDownloads`) is how many series carry one. Guarded in
  `catalog/tests/test_listen_shelves.py`.
- **`series.sort_name`** (and `sortName` on the web series index, `sort_name`
  on a castable script): the A-to-Z key, computed once by
  `catalog/tools/sort_name.py` and golden-tested in `tests/test_sort_name.py`.
  It is the key of the display `name`, so a name that lost its track number sorts by its words.
  Accents dropped, leading non-alphanumerics skipped (`"Banjos`, `: CARL`,
  `? Jiminy`), then one leading article (The, A, An), then case-folded; digits
  sort before letters. Every client sorts Browse A to Z by it and falls back
  to `name` when an older catalog lacks the column; none re-derives it.
- `runs`: `(id, series_key, first_date, last_date, kind, network)`; kind is one
  of anthology, character, serial, strip, comedy-variety, news, broadcast-day.
  Not published yet: the story arcs below decide queueing without it.
- **`arcs`** `(id, series_key, title, parts, method, next_arc)` and
  **`arc_parts`** `(episode_id PRIMARY KEY, arc_id, part)`: one serial story's
  parts in order (Decision 067, catalog DECISIONS 011, `catalog/tools/arcs.py`).
  `method` says how it was derived (`titled-parts`); `next_arc` is the series'
  following arc whose first part is recommendable, or NULL; `title` is the
  story's name from its first part's title, or NULL ("Chapter 1"). Guarantees
  (`catalog/tests/test_arcs.py`, each broken once; the build refuses to publish
  otherwise): every arc has at least two parts, every part is a served episode
  of the arc's series, no episode is in two arcs, and dated parts rise in order.
  MEASURED 2026-10-24 on the 121,907-episode build: 480 arcs over 3,886
  episodes in 238 series. A client plays the next part when one ends, and on
  the last part offers `next_arc`'s part 1 (§5 `arcOf`).
- `people`: `id`, `name`, `birth`, `death`, `portrait` (an `art.id` or NULL).
- `credits`: `(episode_id, person_id, role, character)`, the one home of
  credits: Detail joins it to `people` (they are not repeated in `detail_json`).
- `items`: `(archive_id, downloads)`, archive.org's own download count for
  each item a served recording comes from (`catalog/tools/harvest_downloads.py`,
  else the seed scrape's count in `seeds.json`). An item whose count was never
  read is absent, never zero. Read by the `mostDownloaded` shelf (§5.1).
- `art`: `(id, url, width, height, license, author, credit, evidence_url, face)`.
  `url` is Commons' `Special:FilePath/<file>` with no width: each client's one
  image helper appends `?width=` from Commons' standard steps (120, 330, 500,
  960), never another value (Commons refuses most others) and never a re-hosted copy.
  MEASURED 2026-10-28: `?width=800` is served as the 960 thumbnail, and a request
  wider than the original returns the original, so 960 is always safe to ask for.
  `width`/`height` are the original's when known, else NULL: a portrait's from
  `harvest_people_wikidata.py --phase dims` (Commons imageinfo, size only), a
  series photograph's from `art`. A client lays a picture out by this shape before
  it arrives (WEB-DESIGN §6.4a; wide past 1.15). MEASURED 2026-10-28: all 3,765
  harvested files sized; the 271 series stars are 222 upright, 25 square, 24 wide. `license` is the
  class (`pd_us`, `pd_us_gov`, `cc0`, `pd_release`, `free_use`, `cc_by`,
  `cc_by_sa`); `credit` ("Author, CC BY-SA 3.0") is set exactly when the license
  requires attribution, and a client shows it wherever the image is shown at
  header size or in the Detail credits; `evidence_url` is the file page.
  `face` is where a small crop centers (§3.3a), or NULL.
- `episodes.star`: the episode's face (§3.3a), or NULL.

### 3.3a Portraits: what is served, and whose face a show wears

`catalog/tools/art_policy.py` is the one predicate; both builders use it. A
portrait is served only when all hold (DECISIONS 055, 069): the file's license
class is one above; the PERSON was matched on a date (OTRRpedia's birth or death
agreeing with Wikidata's; the undated one-namesake rule, about 1 in 30 wrong, is
not served, RESEARCH §12 V1); the file is the person's own Wikidata image (P18),
never a "depicts" file (often a group); and a license that needs credit has an
author, and the file is not an own work its own date contradicts: a license the
uploader gave (`{{self|...}}`, PD-self, PD-user, or a Creative Commons license on a
file whose source is `{{own}}`) on a file dated after the death of the person it
shows cannot be the uploader's (Richard Kollmar died in 1971; File:Kollmar.jpg,
"a photograph I took of Richard Kollmar", is dated 2019). The same rule refuses a
show image dated after the death of the earliest-dying person the program's record
marks (`art_policy.implausible_own_work`; `own_work` is read from the file page by
`enrich_people_art.own_work`, the death from `people_wikidata`). One portrait per
person, the most permissive class first, unless it is under the size floor: when it fills less
than the largest window a client draws (`art_policy.LARGEST_SLOT`, 300, tvOS's show tile; the
pixels `fill_px` counts are the ones every client's `windowFill` compares) and a file of the same
person showing one face (the detector's confident faces, `people_art.faces`) fills more, the one
of those that fills most is served, an own image before a stand-in. A stand-in may be a file whose
Structured Data depicts the person (`commons:depicts`) only when it shows one face and passes every
other check, and only for a person who has a served own image: it changes which picture of them is
shown, never who has one (catalog DECISIONS 021). A group never replaces a portrait. Library of
Congress "no known restrictions" and Smithsonian CC0 photographs are not served
(V2, V4, the owner's). MEASURED 2026-10-24 on the 121,907-episode build: 2,344
images, 2,364 people, 305 series with a star, 24,894 episodes with one.

- **`series.picture`** (an `art.id`), **`picture_kind`** and **`picture_source`**:
  the picture that leads the show, the first that exists of (owner, 2026-10-29:
  *"images/graphics that show the full 'show' are better than individual
  contributors. Images that show the star(s) are better than those that show folks
  that are less recognizable."*):
  1. `show`: the show's own image. The series' Wikidata item (catalog
     `enrich_external.py`) must be matched on more than its title: `title+years`
     (the item's own dates, its article's decade category, or the years its own
     description names, "radio Western drama series (1952-1961)", overlap ours, ±2) or
     `title+network` (its broadcaster is one of our networks); a title alone is
     refused. The file comes from the item's own record, in this order of
     `picture_source`: `wikidata:P18` (image), `wikidata:P154` (logo),
     `wikidata:P3383` (poster), `wikidata:P2716` (collage), `wikidata:P6802`
     (related image), `commons:P180` (a Commons file whose Structured Data depicts
     the item), `commons:category` (a file whose own page lists the item's Commons
     category, P373). Its license class is one a portrait is served under (read
     again from its file page, credited when owed), its shorter side is at least
     160 px (the largest show tile), and neither its name nor its categories say
     television (a still of the TV run is another broadcast), and its own date (its
     page's date field, else a year in its name) lies inside the run, ±2 years of the
     earliest logged broadcast (`first_broadcast`, else our first episode) and our last
     episode, whatever its source: a "depicts" statement on a 1914 photograph of a hotel
     is not the 1939 soap opera named for it. archive.org items'
     own cover art is not a source: its only rights statement is the uploader's
     license for the item (catalog DECISIONS 002). `art_policy.show_served`.
  2. `star`: `series.star` when chosen by recognizability: a person the
     program's own OTRRpedia record marks (a "Noted Role" that is the title role,
     Star, Host, Himself; `otrrpedia:noted-role`), heard on at least 3 and a tenth
     of the credited episodes (any, when none is credited: a host of one season of a
     twenty-year anthology is not its face); else a regular (the heard-most
     eligibility below) whom at least one Wikipedia covers
     (`wikipedia:sitelinks`). Among either, the highest share of credited episodes
     x `1 + ln(1 + Wikipedias with an article about the person)`; ties by id.
  3. `person`: `series.star` by the heard-most rule (`credits:heard-most`).
  **One face per star** (owner, 2026-10-29): a person is the picture of at most one
  show (a show's own image is unaffected and never counts). Of the shows 2 and 3
  would give them, they keep one: a show whose title holds their full name (the Jack
  Benny Program) beats every other; then a marked role, only when that show holds at
  least half as many of their credited episodes as their biggest show (Jack Webb's
  seven episodes of Pete Kelly's Blues, the title role, do not outweigh his 474 of
  Dragnet); otherwise the show with most of their episodes; then the highest share;
  then the series key. Every other show is decided again without them: its next
  candidate, else the typographic card. `series.star` follows the picture.
  `art_policy.assign_faces`; guarded by the contract query "a person's portrait
  leads at most one show" in `tests/test_projection_art.py`.
  `picture` is that person's portrait for `star` and `person`. All NULL: the
  typographic card. `art_policy.series_face`; the harvest is
  `harvest_series_art.py` (`.cache/series_art/`), the evidence tables
  `series_art`, `series_marks`, `wikipedia_sitelinks` (`enrich_series_art.py`).
- **`series.star`**: the face chosen by 2 and 3 above, kept when a show image
  leads (an episode wears it). The heard-most rule: the person with a served
  portrait heard on the air (cast, host, narrator, performer, guest, announcer
  excluded) on the most of the series' credited episodes, when that is at least 3
  episodes and a third of them (an anthology's guest is not its face); ties by
  person id.
- **`episodes.star`**: the series' star when heard in the episode, else the
  episode's first on-air credit with a served portrait, else NULL.
- A series with no picture is drawn as the typographic card (name, years,
  network, on its genre hue) by each client from data.
- **`art.face`**: the box a small crop (a row tile, a cast face, an avatar, the
  lock screen's square) centers on, as `"x,y,w,h"`, four numbers normalized to the
  image with the origin at its top left (the web's `art` array carries it as
  `[x, y, w, h]`); NULL when no face was found or none was looked for. Computed
  once, on a Mac, by `harvest_people_wikidata.py --phase faces`: Apple Vision's
  face rectangles (revision 3, `catalog/tools/face_boxes.swift`) over Commons' 500
  thumbnail: of the faces at confidence 0.5 or more, the largest, or, when others
  are at least a quarter of its area (a group photograph), the box holding them
  all, so a crop never zooms onto one face of a group; kept in `files.json.gz`
  beside the size, with the detector's raw boxes (`faces`). MEASURED 2026-10-28:
  all 3,765 harvested files read; of the 2,453 served, 2,422 have a box (204 of
  them a group's), 278 of the 282 wide ones; a random 36 checked by eye were all
  on a face. The 31 misses are mostly halftones, drawings and profiles, or not a
  photograph of a person at all. A hint for a crop, never a claim of whose face it is. Every
  client crops with the one formula below and never detects faces itself; a page
  that is about the picture shows it whole and ignores it.
  **The crop square** (`cropRect`, golden cases in `js/api.test.js`, Apple's
  `CatalogQueryTests`, Android's `ArtTest`), in units of the image's height for an
  image of aspect `a = width / height`: the largest square is `S0 = min(a, 1)`. With
  a face, `m = max(w * a, h)` is its size, the square's side is
  `S = clamp(2 * m, S0 / 4, S0)` (the face about half the square, at most 4x zoom),
  centered on the face's center `((x + w / 2) * a, y + h / 2)` and moved inside the
  image. Without a face an upright or square picture takes `S0` at 50 % across and
  20 % down the slack; a wide one is not cropped (the tile keeps its letter, an
  avatar its empty slot). The result is published to the view as a rectangle
  normalized to the image (`x = left / a`, `y = top`, `w = S / a`, `h = S`), drawn by
  scaling the image to `1 / w` of the slot's width and shifting it by `-x / w`.
  An unknown size (an older catalog) keeps the plain fill crop at (0.5, 0.2).
- Guarantees (`catalog/tests/test_projection_art.py`, each broken once): every
  image's class is served; a face lies inside its image; a credit exactly when owed, with an author; every
  image is worn by a person or a series and every portrait exists; a star wears a portrait
  and an episode's star is credited in it; a series' picture, kind and source are set
  together, a star's or person's picture is that person's portrait, and a show picture's
  source is one of the show's own records; every published image (portrait or show
  picture) traced back to its source rows passes the predicate again, so a title-only
  match or a file without license evidence is refused.

### 3.4 Search

`episodes_fts` (FTS5, contentless, `detail=column`; a match's `rowid` is the
episode's `rowid`), columns `title` (title and aka), `series`, `people`
(credited names), and `transcript`: the default copy's automatic transcript,
indexed only where it passes the gate (`has_transcript = 1`; catalog
DECISIONS 012), so whatever Search finds by what is said, Detail can show; a
client also requires `has_transcript = 1`, so an older projection that indexed
every transcript is read the same way. Contentless
means only the index is stored, never the text. `detail=column` keeps
word-prefix terms and column filters (`series:"x"*`), which are every query the
clients make, and drops token positions, which only phrase and NEAR queries
need. MEASURED 2026-10-22 on the out/next rebuild (108,005
episodes): the projection is 25.66 MB compressed with positions and no
transcripts, 24.66 MB with `detail=column` and an `optimize`; 233 transcripts
add 0.49 MB (2.1 KB each), so all 8,999 add about 19 MB if every transcript
brought new words, and 11.4 MB in a simulation reusing the 233 texts over
8,999 rows: the full projection lands near 36-44 MB. With positions kept, the
233 added 2.01 MB (8.6 KB each), about 78 MB over the catalog. Matching is word-prefix, never substring, on every
platform: each typed word must begin a word in the row ("sorr wrong" finds
"Sorry, Wrong Number"; "sorr" also finds "Mr. Sorrowful", correctly), and a
match never starts inside a word ("orry" finds nothing).

Search has three episode sections on every platform. **Episodes** match
`{title series people}`. **Aired** lists the episodes whose `air_date` begins
with the date the query names ("1954", "August 1954", "Aug 2, 1954", "2 August
1954", "1954-08", "1954-08-02", "8/2/1954"), oldest first, narrowed by the
query's other words in `{title series people}`. **Automatic transcript** lists
the episodes whose shown transcript has every query word of three letters or
more as a word prefix (`{transcript} : "w"*`), oldest first, less those in
Episodes; each row's snippet is the first transcript line saying a query word,
cut on the device from the text at `transcript_url`, verbatim, to about 120
characters with an ellipsis at a cut. The date rule and the snippet rule are
golden cases in `catalog/tests/golden/search_text.json`, which the web, Apple,
and Android tests all read. MEASURED 2026-10-27 (5,657 transcripts shown of
5,889 fetched): gating the index took 59 KB off the compressed served
projection (32.55 to 32.49 MB) and 3 KB off the clean-only seed (1.266 to
1.264 MB, one shown transcript).

### 3.5 Forwarding ids

An episode id is a stored string in every person's history, queue, downloads,
synced rows, and every share and deep link. It changes when parsing improves: a
dated id carries a date a parse fix can correct (C1, 2026-10-28: "Jack Benny
Show, The 43-11-21" had been read as 1921-03-11), and 79,612 undated ids in the
2026-10-21 snapshot come from a title slug or a file path. So the old id
forwards, permanently (catalog DECISIONS 014, `canonical-entity-identity`).

| Table | Columns | Meaning |
|---|---|---|
| `episode_aliases` | `old_id` TEXT PK, `new_id` TEXT | an id this projection no longer serves, and the served episode it now is |
| `episode_tombstones` | `id` TEXT PK | an id that left with no successor: it will not come back as itself |

**Built on every publish** (`catalog/tools/forwarding.py`, called by
`build_projection.py --previous`): the build reads the projection live on
`catalog-latest`, and every id that projection served and this one does not
gets exactly one row:

- an **alias** to the served episode that now holds its default copy (rank 0),
  matched by recording identity, the archive.org item plus the file name read
  back from the served URL, never by title. When no served episode holds the
  default copy, or several do, the episode holding the most of the old id's
  copies (among those holders) is the successor, and a tie is none;
- else a **tombstone** (a takedown, a hide, a recording no longer served).

Both are **cumulative**: the live projection's aliases and tombstones are
carried into the new one. **Chains collapse**: an alias whose target left this
build takes that target's fate, so `a -> b` then `b -> c` publishes `a -> c`,
and `a` is tombstoned when `b` is. An id **served again** (a parse change
reverted, a takedown restored) sheds its alias or tombstone. The clean-only
projection (`--forwarding-from` the served one) takes the same rows, keeping an
alias only when its target is one it serves. `manifest.json` counts
`counts.aliases` and `counts.tombstones` and records `forwarding`: `base`, the
sha256 of the live `.zz` it was computed against (null on a first publish), and
the build's report (`left`, `aliased`, `tombstoned`, carried, `returned`).

**Guards**, each seen red (`catalog/tests/test_forwarding.py`, also run over
the real artifacts by the publish workflow): no alias ends at an id that is not
served (`missing`), no alias target is itself aliased (`chain`), no cycle, no
aliased id is served, no id is both aliased and tombstoned, and no tombstoned id
is served (`tombstone served`). The builder refuses a projection that breaks
one. `publish_diff.py` refuses a publish in which any id left with neither row,
and the publish job refuses when `forwarding.base` is not the sha256 of what
is live under the lock (another publish landed in between).

**Clients resolve in one place** each (the web's `js/api.js` with `js/store.js`,
Apple's `Core/Catalog/IDForwarding.swift`, Android's `data/IdForwarding.kt`):
an aliased id reads as its `new_id`; a tombstoned id is gone; any other unknown
id is kept, since it may come from a newer catalog than this device holds (a
synced row, a link from a newer app). Every stored id is rewritten on read, once:
history and positions merge into the new id by the newer stamp, the queue maps
and drops tombstoned ids, downloads re-key (their files keep their names). A
rewrite keeps each row's own stamp and is not uploaded; every device resolves
the Worker's rows for itself, so a device on an older catalog is never
overwritten by one on a newer catalog. Deep links, Universal and App Links, and
rows synced from other devices go through the same resolution.

MEASURED 2026-10-28, the C1 parse fix rebuilt from the same cache
(PYTHONHASHSEED=0) and forwarded against the pre-fix rebuild: 984 served ids
left; 899 aliased onto 895 episodes (633 into an id the old projection already
served, the rest kept under a corrected date or series); 85 tombstoned, every
one now hidden under its corrected id (82 post-1972, 3 by other audit rules);
the clean-only projection 0 aliases and the same 85 tombstones.

**Series keys forward the same way.** A series key is stored too: every
follow, every series link and deep link (`/series/{key}`), and the Worker's
follow rows. 237 of the C1 rebuild's 899 episode aliases changed series key.

| Table | Columns | Meaning |
|---|---|---|
| `series_key_aliases` | `old_key` TEXT PK, `new_key` TEXT | a series key this projection no longer serves, and the served series it now is |
| `series_key_tombstones` | `key` TEXT PK | a series key that left with no successor |

Every series key the live projection served and this one does not gets
exactly one row: an **alias** to the served series that now holds **more than
half** of its recordings (the distinct archive.org item plus file of every
copy of every episode it served, the same recording identity as above), else a
**tombstone**. More than half, because a follow is a choice of one program:
forwarded to a series holding less than half of what was followed, it most
likely names a different program (a split, or a bag of one-offs filed apart),
and a wrong program is worse than a dead follow; a majority is also never a
tie. The denominator is every recording the series served, not only those
still served somewhere, so a series mostly taken down is not forwarded on the
strength of its remainder. Cumulative, chains collapse, a key served again
sheds both, the clean-only projection inherits them, and the same six guards
hold, each seen red. `manifest.json` counts `counts.seriesAliases` and
`counts.seriesTombstones`, and `forwarding.series` is the series report (the
same keys as the episode one). `publish_diff.py` refuses a publish in which a
series key left with neither row. The web projection publishes
`data/index/series-aliases.json` (only aliases to a series it serves) and
`data/index/series-tombstones.json`.

**Clients resolve a series key in the same one place** as an episode id: an
aliased key reads as its `new_key`, a tombstoned key is gone, any other
unknown key is kept. A follow under a moved key merges into the new key's by
the newer stamp, keeping its own stamp and pending state (never uploaded as
new); a tombstoned key's follow stays (it is the person's choice; it simply
has no new episodes). A series page, a series deep link, and a Worker follow
row each resolve through it. A download stores its series key when it is made
(from the episode's own series field, never parsed out of the episode id) and
forwards it like a follow; a record written before the key was stored reads it
from its id once, on decode.

MEASURED 2026-10-28, the same pair of builds: 46 served series keys left; 20
aliased (every one onto a series holding all of its recordings: 139 of 139 for
"Ron Bowser John Dunning Project Information Please" onto Information
Please), 26 tombstoned (24 with none of their recordings served anywhere; the
largest split, "Tube Talk", has at most 4 of its 26 in any one series, "The Big
Broadcast" 1 of its 20). Every threshold above 4 of 26 (15 %) gives these
same rows; more than half is the rule because it is the one with a reason.

## 4. The web projection (Pages)

Cut from the served projection, never built separately. *Layout to measure*;
the starting shape, Archive Watch's:

- `data/index/series.json`: every served series as a positional row for
  browsing and search.
- `data/series/{key}.json`: one series page, its runs, seasons, and episode rows.
- `data/episodes/{shard}.json`: Detail fields, sharded by a stable hash of the
  episode id (FNV-1a, positions append-only), one shard per Detail view.
- `data/tonight.json` and `data/stations.json`: the Stations section (§8).
- `data/index/aliases.json` (`{old_id: new_id}`, only aliases to an id this
  projection serves) and `data/index/tombstones.json` (sorted ids): §3.5's
  forwarding. An alias to an episode the web does not serve (the public-web
  gate) is left out, so on the web that id is simply not served.
- `data/index/series-aliases.json` (`{old_key: new_key}`, only aliases to a
  series this projection serves) and `data/index/series-tombstones.json`
  (sorted keys): §3.5's series forwarding, gated the same way.
- `data/people/{shard}.json`: `withPerson` (§5), sharded as the episodes
  are but by the person id: `{id: [name, birth, death, art, credits]}`
  (`fields.person`), each credit `[id, date, title, num, series, role,
  character]` (`fields.personCredit`), one row per credit, oldest first
  (R1), so an episode a person wrote and directed is two rows. Only served
  episodes' credits; a person with none has no page.
- `data/search/said/{p}.json`: what is said, filed as `search/terms` is (a
  word's first two characters): `{word: delta-coded doc numbers}` for every
  word of three letters or more (`search.saidMinWord`) in each shown
  transcript (§3.4), cut from the transcript cache by `build_web_projection.py
  --transcripts` for the episodes whose `transcript_url` is set. Never the
  text. MEASURED 2026-10-27, gate open: 5,657 transcripts, 91,535 words in 796
  files, 12.8 MB raw (4.7 MB gzip), the largest `co.json` at 387 KB (144 KB
  gzip).
- `data/search/dates/{yyyy}.json`: a year's dated docs for Search's Aired
  section, `{fields, rows}` with rows the doc row and its number (`fields.date`:
  `id`, `title`, `date`, `series`, `doc`), oldest first. MEASURED 2026-10-27,
  gate open: 53 files, 1.2 MB raw (0.25 MB gzip) before the doc rows were
  added; the publish log prints the current reading.
- `data/search/people/{p}.json`: people for Search, filed under the term
  file (`termFile`) of each word of the name, `{fields, rows}` with rows
  `[id, name, episodes, art]` (`fields.people`), most episodes first.
  MEASURED 2026-10-24 on the 2026-10-22 projection, gate open: 15,784
  people, 4,015 person shards, 29.7 MB raw (7.0 MB gzip), the largest
  206 KB (30 KB gzip, Don Wilson's 1,384 credits); 267 search files,
  11.0 MB raw (2.8 MB gzip), the largest `an` at 335 KB (78 KB gzip). Most
  of the search bytes are 1,011 Goldin "people" whose name is a whole cast
  list (`Name (role); Name (role)`), filed under every word of it; splitting
  those credits in `enrich_db.py` is the fix, not a client filter. Gate
  closed: 122 people, 56 KB in all.

A Detail row's `transcript` is §3.1's `transcript_url` (null unless the gate
passed). Portraits (§3.3a) travel inline as `art` arrays (`fields.art`: `url`,
`width`, `height`, `credit`, `evidence`, `face`): a series row appends `star` (the
face's name) and `art` (the face's portrait), then, after `downloads`, `picture` (the
series' leading picture, §3.3a, as an `art` array), `pictureKind` and `pictureSource`
(null together; a series page carries the same three keys), a series page carries both as keys, a credit appends
`art` (its person's portrait or null), and a Detail row appends `star` (the
episode's face, a person id among its credits). A series row appends `scripts` (how many of its served episodes carry a
`script`), then `downloads` (§3.3, or null) and a Detail row appends `script` (§3.1, or null), then `arc`
(`fields.arc`: `id`, `part`, `parts`, `next`, `nextStory`; null outside an
arc). The web serves an arc only whole: one with a part the clean-only gate
holds back is not served, and is never another arc's `nextStory` (MEASURED
2026-10-24: 198 arcs over 2,942 of the web's 15,125 episodes). Web search
finds what is said through `search/said/` (above): the served projection's FTS
is contentless, so the web builder reads the transcript cache itself, only for
an episode the served projection shows a transcript for.

The series index is the gatekeeper for every thin client: an id absent from it
is never fetched, listed, or linked. Deploying through Actions means the owner
moves Settings > Pages > Source to GitHub Actions; until then the publish
workflow builds and tests the web projection and skips its deploy with a
warning (§7).

## 5. Query verbs

Every client reproduces these natively; each says which filter clauses it applies.

| Verb | Returns | Clauses |
|---|---|---|
| `continueListening` | the person's in-progress episodes | none (the person's own) |
| `seriesBrowse(genre, network, decade, kind)` | series rows | `recommendAnd` on shelves only |
| `seriesPage(key)` | runs, seasons, episodes, oldest first (R1) | none |
| `episodeDetail(id)` | the row plus `detail_json`; resolves aliases | none |
| `search(q)` | episodes and series, word-prefix | none |
| `shelf(rule)` | episodes for a Listen shelf, by a rule from `listenShelves` (§5.1) | `recommendAnd` |
| `tonight(localDate)` | the evening for the person's own date | `recommendAnd` |
| `withPerson(id)` | the person (`people`: name, birth, death, portrait) and every served credit (`credits` joined to `episodes`), oldest first, one row per credit; a client groups by series and may reverse the order | none |
| `searchPeople(q)` | people whose name has every query word as a word prefix, most served episodes first | none |
| `arcOf(id)` | the episode's arc, its part and part count, the next part's id (none on the last part), and on the last part only the next story's first part | none (`next_arc` already applies `recommendAnd`) |

### Named filter clauses

- `recommendAnd`: `no_recommend IS NULL`. Every surface that chooses for the
  listener (shelves, Tonight, stations, widgets, Top Shelf, autoplay after a
  serial's arc) applies it; every surface the listener drives (search, browse,
  series pages, Detail) does not.

### 5.1 Listen shelves

The Listen tab's shelves are pipeline outputs, not client logic (Decision 058;
HUMAN-SHAPED.md finding 6). Every client draws the list it is handed, in order:
`meta.listenShelves` in the served projection (a JSON array) and
`listenShelves` in the web manifest, each computed over that output's own
served rows by `catalog/tools/shelves.py`, which both builders import. A
shelf is a rule over data, never a written list (R13): it carries only its
rule's keys, no title or blurb; its heading is the client's word for the rule
and, for a genre, the published genre name (§5.5). A client drops a shelf that
comes back empty, and ignores a rule it does not know.

```json
[{"rule": "onThisDay"},
 {"rule": "genreFirsts", "genre": "drama", "episodes": ["<id>", "..."]}, ...]
```

| Rule | Keys | Definition |
|---|---|---|
| `onThisDay` | `rule` | episodes whose `air_date` is a full `YYYY-MM-DD` on the person's own calendar month and day, any year (a month or year alone never matches; 29 February shows only on 29 February), `recommendAnd`, ordered by `air_date` ascending, ties by `id`, limit 20. It depends on the person's date, so it is a query by rule, never precomputed; `catalog/tests/golden/on_this_day.json` holds the cases every client's query must return. |
| `mostDownloaded` | `rule`, `episodes` | Decision 067: popularity from data. Each served series' downloads are archive.org's own counts summed over the distinct items holding its served episodes' default copies (`shelves.series_downloads`, over that output's own rows, so the clean-only web ranks only what it serves); the series with the most, each by its earliest recommendable episode (front matter skipped, as `genreFirsts`), ties by key, limit 20, published when at least `MIN_SERIES` series rank. A series with no count read is not ranked. Precomputed ids. Its heading is the client's word for the rule ("Most downloaded"). |
| `genreFirsts` | `rule`, `genre`, `episodes` | for each served series in the genre, its earliest recommendable episode (oldest first: dated before undated, then `air_date`, then `num` with nulls last, then `id`), series with the most served episodes first, ties by key, limit 20. Precomputed: `episodes` is the ordered id list, so a client reads ids and never re-derives the query. |

- **Order**: `onThisDay` first, then `mostDownloaded`, then one `genreFirsts` per genre in
  `genres.GENRES` order that has at least `MIN_SERIES` (5) served series with
  a recommendable episode. MEASURED 2026-10-23 on the 2026-10-22 projection:
  natively drama 986, comedy 469, mystery 227, documentary 154, serial 128,
  news 53, scifi 47, western 39, so all eight publish; the clean-only web set
  has drama 608, comedy 2, the rest 0, so the web publishes drama only. Any
  floor from 3 to 39 gives the same lists today; 5 is one ten-foot row.
- **Guarantees** (`catalog/tests/test_listen_shelves.py`, each broken once):
  the key exists in both outputs; every rule is from the known set and carries
  only its keys; every published id is served by that output and recommendable;
  a genre shelf names one of the eight and is never empty.
- **Excluded by the owner** (Decision 067): "Most episodes" (the web's series
  shelf, `index/listen.json` `most`) is not a rule here; popularity is
  `mostDownloaded`. `index/listen.json` stays for older clients (Roku).
  MEASURED 2026-10-24 on the 2026-10-22 projection with `seeds.json`'s counts:
  6,215 of 8,724 default-copy items carry a count (91,305 of 108,005 episodes);
  `harvest_downloads.py` reads the rest (one batched advancedsearch call per 100
  items, a pause between).

### 5.5 Display vocabulary

The words are published, not typed into each client: `meta.rightsLines` in the
served projection (a JSON object keyed by `unclaimed` and each clean basis) and
`rightsLines` in the web manifest carry exactly the strings below. A client
shows the published string; a basis it has no string for shows no line, never
the unclaimed one.

| Field value | Shown as |
|---|---|
| `rights = clean` | by `rights_basis`: `rec_gov_work` "Government recording", `rec_librivox` "LibriVox recording", `rec_pd_published_age` "Published before 1926", `rec_cc_corroborated` "Creative Commons recording" |
| `rights = unclaimed` | "No rights claim known. Removed on request." Never "public domain" |
| `variant = AFRS` / `AFRTS` | "Armed Forces Radio rebroadcast" |
| `partial = 1` | "Incomplete copy" |
| the eight genres | their names; hues from `color.genre` in `design-tokens.json` (Decision 064) |

## 6. Policy flags

- **Rights** come from `catalog/tools/audit_audio_rights.py`: hides run before
  rescues, the stricter of the recording and underlying-work layers wins, and
  every row carries its evidence. Only `keep_clean` (served as `clean`) and
  `keep_unclaimed` (`unclaimed`) are served.
- **The public-web gate**: until the DMCA agent is registered, the web
  projection serves `clean` rows only. This is one flag in the publish step,
  never a client filter (LOOP-PLAN standing rules).
- **Never recommended, always findable**: `no_recommend` carries the reason
  (Nazi-state speeches and broadcasts, archive.org's own `deemphasize`
  collection, and racist caricature with its source: catalog DECISIONS 006
  and 013).
- **Take-downs** go in `catalog/editorial/takedowns.json` and remove the rows at
  the next publish.

## 7. Refresh protocol

`.github/workflows/catalog-publish.yml`, daily at 09:41 UTC and on dispatch.
Two jobs:

- **build**, no lock: restores `radio-catalog.sqlite.xz` and
  `harvest-cache.tar.xz` from the newest `catalog-YYYY-MM-DD` Release (checked
  against its `SHA256SUMS`), rebuilds with `build_db.py` and `enrich_db.py`,
  runs every suite (`catalog/tests/run_all.sh`), builds the served projection,
  the clean-only projection, and the web projection, runs `test_projection.py`
  (`PROJECTION=`) and `test_web_projection.py` (`WEB_PROJECTION=`) over the real
  artifacts, and prints what the publish changes (`catalog/tools/publish_diff.py`:
  counts and bytes against the live manifest, episodes per rights state against
  the restored snapshot, and which ids left and why: aliased, tombstoned as now
  hidden, tombstoned, or neither, the last refusing the publish per §3.5). It
  reads the live projection before it builds, so the served projection forwards
  every id the live one served (§3.5).
- **publish**, holding `catalog-writers`, the one concurrency group every
  catalog writer shares (`cancel-in-progress: false`): re-reads the live
  `manifest.json` from `catalog-latest` and `data/manifest.json` from Pages,
  refuses either projection when it serves more than 2% fewer episodes
  (`MAX_SHRINK`) without a recorded reason, uploads `ear-drama.sqlite.zz` then
  `manifest.json` to `catalog-latest` (`--clobber`, through `tools/gh_retry.sh`,
  sizes checked after), and deploys the site with the web projection under
  `/data/` through `actions/deploy-pages`.

The guard is the merge rule: the catalog is rebuilt whole from the snapshot's
caches, so nothing is merged field by field, and the guard keeps a rebuild from
publishing less than is live. The recorded reason is the dispatch input
`shrink_reason`, printed into the run summary. A missing `catalog-latest` is a
first publish; one that exists without its manifest is an emergency and fails.
A second floor (`RESEARCH_FLOOR`, 10%) holds the rebuild against the snapshot it
was restored from, so a half-read cache is caught even on a first publish; it is
looser because a snapshot can predate rights rulings (the 2026-10-21 snapshot
serves 121,907 episodes, the 2026-10-22 audit 116,380).

A run that read nothing goes red: no dated Release, a checksum mismatch, a build
with no episodes, a red suite, or a projection under its floor (10,000 served,
1,000 clean-only) each stop the run before anything is published. A red X is
reserved for broken: Pages not yet served from Actions (`build_type` other than
`workflow`) skips the deploy with a warning.

The public-web gate is the repository variable `DMCA_AGENT_REGISTERED`: the web
projection gets `--include-unclaimed` only when it is exactly `true`, and the
build fails if the web manifest's `cleanOnly` disagrees with the variable. The
native projection serves clean and unclaimed rows either way.

## 8. Extension files

Small JSON the pipeline computes, so a widget or Top Shelf never opens the
database: `tonight.json` keyed by calendar date (starting yesterday, so every
time zone finds its own today, and a day once published keeps its value), and
`stations.json`, the genre stations' schedules on the one clock (R10). The
Listen shelves are not a file: they ride in the manifests as `listenShelves`
(§5.1), so a widget reads them without opening the database.

`tonight.json` (built by `catalog/tools/build_evenings.py tonight`):

- **Window**: from yesterday through 13 days ahead of the build's UTC date,
  keyed `YYYY-MM-DD`; a client reads the key for the person's own date.
- **Never changes**: each build merges onto the file published now; a day
  already in it keeps its evening, network, and slots. A kept day's slot may
  change in two ways only: a withdrawal (an episode the served projection no
  longer serves becomes a gap with `withheld: true`), and an id that moved,
  whose episode id is rewritten to its alias in `episode_aliases` (§3.5;
  owner, 2026-10-29: "Yes"), at the same instants. A tombstoned id stays a
  gap. `build_evenings.py kept` refuses any other change under the publish lock.
- **Served only**: a slot is filled only by an episode the served projection
  holds and recommends (`recommendAnd`); the pick's coverage counts only
  those. The web's copy is the same evenings with each episode the web
  projection does not serve withheld, so every platform plays the same
  evening on the same date.
- **Which evening** (Decisions 058, 067): the date's anniversary in its
  best-surviving year whenever any program of that evening survives (the 0.25
  floor is gone); else the best evening for the weekday; never one with
  nothing to play.
- **Shape**: `zone`, `days.{date}`: `evening`, `picked` (`anniversary` or
  `weekday`), `network`, `station`, `coverage`, `witness` (paper, station,
  page URL), `slots[]`, and `years[]`. A slot is `et_start`, `et_end`,
  `length_min`, `utc_start`, `utc_end`, then `episode` (`id`, `series`,
  `title`, `rights`, `length_s`) or `gap: true` with `known_series` (a catalog
  series name, only when the listing matched a series), `withheld`, or
  `refused`. A gap shows its time and `known_series`, never the newspaper's
  text: the paper's OCR text is not published (Decision 067; the measured
  cache keeps it as witness).
- **Other years** (Decision 067): `years[]` holds the same calendar date's
  other published years, oldest first, one evening per year (that year's best
  network), each with `evening`, `network`, `station`, `coverage`, `witness`,
  and `slots[]` on today's clock, served only and never stitched; a listener
  may pick one in place of the day's evening. A weekday pick offers none. A
  kept day keeps its evening and slots and takes the new build's years; a
  withdrawal applies to them too, and a year left with nothing to play leaves
  the list.

`stations.json` (built by `catalog/tools/build_stations.py build`, Decisions
058 and 068: *"collections of ear dramas should be stations"*):

- **One station per genre** (`genres.py`, in its order) with at least
  `MIN_SERIES` (5) series in its pool, named by `genres.NAMES` (data, never
  copy). Shape: `schemaVersion`, `generatedAt`, `rule`, `stations[]`: `genre`,
  `name`, `slots[]`. A slot is exactly `utc_start`, `utc_end`, `length_s`, then
  `episode` (`id`, `series`, `title` when it has one) or `withheld: true`.
- **One clock, published, never computed on a device**: slots run back to
  back (each starts where the one before ends; `length_s` is start to end), so
  every listener tuned to a station hears the same episode at the same moment.
  A client finds the slot whose instants hold now and joins it at its offset
  (`onNow` / `StationClock.onNow`), with the evening's live rules (R14).
- **The pool**: served (the projection holds it), recommendable
  (`recommendAnd`), the default copy complete (`partial = 0`) and 5 to 90
  minutes long, never a book's front matter, its series in that genre.
- **The order is data**: the genre's pool in the order it first aired (dated by
  air date; undated by log number, so series interleave), continuing after the
  last published slot and wrapping at the end; an episode already in the
  window is never scheduled again; a series waits until six others have aired
  (or every other series, in a smaller genre), passed over this cycle.
- **Window**: from the slot running an hour before the build through at least
  four days past it (the daily publish lands hours late; four days survives
  three missed runs). The guard requires every station on the air at the build
  and reaching three days ahead.
- **Never changes**: each build keeps every published slot still running or
  ahead exactly as it is and appends after the last. A kept slot may change in
  two ways only, each with the same instants so the clock never moves: a
  withdrawal (its episode no longer served, it becomes `withheld`), and an id
  that moved, whose episode id is rewritten to its alias in `episode_aliases`
  (§3.5; owner, 2026-10-29: "Yes"), taking that episode's series and title. A
  tombstoned id has no alias and stays a withheld gap. `build_stations.py kept`
  refuses any other change under the publish lock.
- **The web's copy** (`build_stations.py web`) is the same schedules with each
  episode the web projection does not serve withheld; a station left with
  nothing to play is not offered there.
- **Guards**: `catalog/tests/test_stations.py` (no gap or overlap, every slot
  served and recommendable, no repeat, the window's floor, keys only, names
  from data, a published slot kept), each broken once; the publish workflow runs
  it over the real projection and `kept` under the lock.

## 9. Contract tests (to write with the publish step)

Each asserts the documented shape over the real published artifact, every row,
and has a negative control:

1. No served row has a `state` outside `keep_clean` and `keep_unclaimed`.
2. Every `rights = unclaimed` row's display string is never "public domain".
3. Every episode has exactly one rank-0 recording with a percent-encoded URL.
4. Every `no_recommend` episode is absent from every shelf, evening, and station.
5. Every web shard id is in the series index (the gatekeeper).
6. Every id that left the catalog since the last publish is either aliased or
   tombstoned (§3.5), and the forwarding breaks no §3.5 guard. Refused by
   `catalog/tools/publish_diff.py` on every publish (a takedown shows as a
   tombstoned hidden row with its bucket); `catalog/tests/test_forwarding.py`
   runs over the real artifacts.
