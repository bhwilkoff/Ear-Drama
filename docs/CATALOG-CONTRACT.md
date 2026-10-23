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
| `manifest.json` | the same Release | every native client, tooling | the served projection's: `schemaVersion`, `generatedAt`, `cleanOnly`, row counts, `rightsLines`, `listenShelves` (§5.1), bytes, sha256 of the `.zz`; uploaded after the `.zz` it vouches for |
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
| `title` | TEXT | display title |
| `aka` | TEXT | alternate titles (AFRS retitlings), JSON array |
| `length_s` | REAL | the default copy's measured length |
| `rights` | TEXT | `clean` or `unclaimed` (§6) |
| `rights_basis` | TEXT | the bucket that decided it, for the rights line's detail |
| `no_recommend` | TEXT | NULL, or the reason it is never recommended (§6) |
| `network`, `network_source` | TEXT | the network that aired it, and which witness says so |
| `sponsor` | TEXT | dated sponsor, when a log gives one |
| `has_transcript` | INTEGER | 1 only when the default copy's automatic transcript was fetched and passes the on-screen gate (Decision 058: 50-220 words a minute, at most 10% repeated four-word runs, `catalog/tools/transcript_gate.py`); 0 otherwise, including a transcript that failed the gate (still searchable, §3.4) |
| `gain_db` | REAL | retired, always NULL: the target lives in the clients (Decision 061), so the pipeline publishes the measurement below, never a gain |
| `added_at` | TEXT | when the episode first appeared in a published catalog |
| `detail_json` | TEXT | Detail-only fields (credits, versions, other performances, witnesses), decoded only on Detail |
| `loudness_i` | REAL | the default copy's integrated loudness, LUFS (EBU R128, `ffmpeg ebur128=peak=true` over the whole file); NULL until measured |
| `loudness_tp` | REAL | the default copy's true peak, dBTP; NULL exactly when `loudness_i` is |
| `transcript_url` | TEXT | archive.org's own `{stem}.autogenerated.txt` beside the default copy, percent-encoded; set exactly when `has_transcript = 1`, NULL otherwise |

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

**Playback loudness** (Decision 061). Each client holds one constant, the
target, -21 LUFS, and plays an episode at `gain = target - loudness_i` dB,
clamped so `loudness_tp + gain <= -1`; a boost beyond the clamp is not applied,
and the web only cuts (a Web Audio gain above 1 would clip). NULL means
unmeasured: play at unity gain, never a guessed value. The two columns describe
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

### 3.3 `series`, `runs`, `people`, `credits`, `art`

- `series`: `key`, `name`, `genre` (one of the eight, §5.5), `first_date`,
  `last_date`, `networks`, `episodes` (served count), `canonical_episodes` (what
  the logs say aired), `kind_summary`.
- `runs`: `(id, series_key, first_date, last_date, kind, network)`; kind is one
  of anthology, character, serial, strip, comedy-variety, news, broadcast-day.
- `people`: `id`, `name`, `birth`, `death`, `portrait` (an `art` row or NULL).
- `credits`: `(episode_id, person_id, role, character)`, the one home of
  credits: Detail joins it to `people` (they are not repeated in `detail_json`).
- `art`: images with their evidence (`url`, `width`, `height`, `license`,
  `evidence_url`, `author` when the license requires credit). An image is
  served only when its own record carries the evidence (DECISIONS 055).

### 3.4 Search

`episodes_fts` (FTS5, contentless, `detail=column`; a match's `rowid` is the
episode's `rowid`), columns `title` (title and aka), `series`, `people`
(credited names), and `transcript`: the default copy's automatic transcript,
indexed for every fetched transcript whether or not it passes the gate (an
episode can be found by a word spoken in it and still show no text). Contentless
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

### 3.5 Forwarding ids

`episode_aliases (old_id, new_id)`. 79,612 episodes in the 2026-10-21 snapshot
have no date, and their ids come from a title slug or an archive file path that
can change when parsing improves. When an id changes, the old one forwards; a
saved history, queue, or share link never breaks (`canonical-entity-identity`).

## 4. The web projection (Pages)

Cut from the served projection, never built separately. *Layout to measure*;
the starting shape, Archive Watch's:

- `data/index/series.json`: every served series as a positional row for
  browsing and search.
- `data/series/{key}.json`: one series page, its runs, seasons, and episode rows.
- `data/episodes/{shard}.json`: Detail fields, sharded by a stable hash of the
  episode id (FNV-1a, positions append-only), one shard per Detail view.
- `data/tonight.json` and `data/channels.json`: the Radio tab (§8).

A Detail row's last field, `transcript`, is §3.1's `transcript_url` (null
unless the gate passed). Web search does not index transcript words yet: the
served projection's FTS is contentless, so the web builder has no text to cut
from, and adding about 9,000 transcripts' vocabulary to the two-character term
files is a size to measure before it is built. Until then, transcript search is
native only (PARITY).

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
| `withPerson(id)` | episodes crediting a person | none |

### Named filter clauses

- `recommendAnd`: `no_recommend IS NULL`. Every surface that chooses for the
  listener (shelves, Tonight, channels, widgets, Top Shelf, autoplay after a
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
| `genreFirsts` | `rule`, `genre`, `episodes` | for each served series in the genre, its earliest recommendable episode (oldest first: dated before undated, then `air_date`, then `num` with nulls last, then `id`), series with the most served episodes first, ties by key, limit 20. Precomputed: `episodes` is the ordered id list, so a client reads ids and never re-derives the query. |

- **Order**: `onThisDay` first, then one `genreFirsts` per genre in
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
- **Excluded pending the owner**: "Most episodes" (the web's series shelf,
  `index/listen.json` `most`) is not a rule here; whether a size ranking belongs
  on Listen is the owner's call (HUMAN-SHAPED.md B). `index/listen.json` stays
  until the web reads `listenShelves`.

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
  (Nazi-state speeches today; WWII propaganda per catalog DECISIONS 006).
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
  the restored snapshot, and which ids left and why: aliased, now hidden, or
  neither, the last a warning per §9.6).
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
`channels.json`, the genre channels' schedules on the one clock (R10). The
Listen shelves are not a file: they ride in the manifests as `listenShelves`
(§5.1), so a widget reads them without opening the database.

`tonight.json` (built by `catalog/tools/build_evenings.py tonight`):

- **Window**: from yesterday through 13 days ahead of the build's UTC date,
  keyed `YYYY-MM-DD`; a client reads the key for the person's own date.
- **Never changes**: each build merges onto the file published now; a day
  already in it keeps its evening, network, and slots. The one change a
  kept day can take is a withdrawal: an episode the served projection no
  longer serves becomes a gap with `withheld: true`. `build_evenings.py
  kept` refuses any other change under the publish lock.
- **Served only**: a slot is filled only by an episode the served projection
  holds and recommends (`recommendAnd`); the pick's coverage counts only
  those. The web's copy is the same evenings with each episode the web
  projection does not serve withheld, so every platform plays the same
  evening on the same date.
- **Shape**: `zone`, `floor` and `floor_provisional` (the coverage floor of
  DECISIONS 058, one constant, provisional until the owner fixes it),
  `days.{date}`: `evening`, `picked` (`anniversary` or `weekday`),
  `network`, `station`, `coverage`, `witness` (paper, station, page URL),
  and `slots[]`: `et_start`, `et_end`, `length_min`, `utc_start`,
  `utc_end`, then `episode` (`id`, `series`, `title`, `rights`, `length_s`)
  or `gap: true` with `known_series` (a catalog series name, only when the
  printed text reads clearly as one), `withheld`, or `refused`. `printed`
  is the paper's OCR text, kept as witness; clients do not draw it until
  the owner rules on it.

## 9. Contract tests (to write with the publish step)

Each asserts the documented shape over the real published artifact, every row,
and has a negative control:

1. No served row has a `state` outside `keep_clean` and `keep_unclaimed`.
2. Every `rights = unclaimed` row's display string is never "public domain".
3. Every episode has exactly one rank-0 recording with a percent-encoded URL.
4. Every `no_recommend` episode is absent from every shelf, evening, and channel.
5. Every web shard id is in the series index (the gatekeeper).
6. Every id that left the catalog since the last publish is either aliased or
   in `takedowns.json`. Reported by `catalog/tools/publish_diff.py` on every
   publish (a takedown shows as a hidden row with its bucket); a warning, not a
   gate, until aliases are written for undated ids.
