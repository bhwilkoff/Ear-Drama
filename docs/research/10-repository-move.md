# Moving Ear Drama into its own repository (2026-10-21)

Owner, 2026-10-21: *"The app is going to be called "Ear Drama". ... Please move
forward with the research necessary before I move this project into its own
repository."* This file lists what moves, what stays, and the order to do it in.
Ear Drama is a separate app (owner, 2026-10-19), built from an updated Universal
App Template.

## 1. What moves

| Path in Archive Watch | Size | Into the new repository as |
|---|---|---|
| `docs/research/RADIO-DRAMA.md` | 60 KB | `docs/research/RESEARCH.md` (the start point) |
| `docs/research/radio/` (01-10, `data/`) | 0.7 MB | `docs/research/` |
| `radio-catalog/` except `dist/`, `out/`, `.cache/` | 4 MB | `catalog/` (pipeline, editorial, tests, reports, DECISIONS, prototypes) |
| `radio-catalog/dist/*` | 189 MB | a GitHub **Release** (below), never git |
| `tools/probe_otr_corpus.py` | 20 KB | `catalog/tools/` |

The catalog is self-contained: stdlib Python, no imports from Archive Watch.
Its one Archive Watch data file, the printed film renewals, is copied in as
`radio-catalog/editorial/film_renewals_cce.json` (2026-10-21). Paths inside the
tools are relative to the catalog root (`ia_lib.ROOT`), so renaming the folder
needs no code change. Docstrings cite `docs/research/radio/NN`; after the move
those read `docs/research/NN`.

To keep history, split it out rather than copying:

    git subtree split --prefix=radio-catalog -b ear-drama-catalog
    # then, in the new repository: git pull <archive-watch> ear-drama-catalog

The docs have their own history under `docs/research/`; a plain copy is fine
for them, because the commit messages on this branch carry the owner's words.

## 2. The data goes on a Release

Decisions 017/018 (Archive Watch): a catalog lives on a Release, never in git.
The snapshot rides this branch only because the session could not upload one.

1. In the new repository, create a Release (e.g. `catalog-2026-10-21`) and upload
   the database parts and the cache parts with `SHA256SUMS`, `build_report.json`
   and `coverage.json`. Joined forms: `radio-catalog.sqlite.xz` (48 MB) and
   `harvest-cache.tar.xz` (149 MB); single files under the 2 GB asset limit,
   so the 45 MB split is no longer needed.
2. Point the catalog README's "rebuild without re-harvesting" line at the Release.
3. **Delete `radio-catalog/dist/` from this branch before it merges into Archive
   Watch**, or the 189 MB stays in Archive Watch's history forever. Better still,
   do not merge the catalog into Archive Watch at all: merge only what Archive
   Watch keeps (§4).

## 3. Rename on the way

- **User-Agent**: `ia_lib.UA` reads `ArchiveWatch-RadioCatalog/0.1
  (https://archivewatch.org; ...)`. Archive.org, Wikimedia and OTRR are asked
  to identify a real contact; change it to Ear Drama's own name and URL once
  the domain exists (09-ear-drama-brand.md).
- **"the radio app" / "radio drama app"** in docs and DECISIONS: Ear Drama.
- `radio-catalog` -> `catalog`; `RADIO-DRAMA.md` -> the new repository's research
  start point.

## 4. What stays in Archive Watch

- `SCRATCHPAD.md`'s pointer and its 2026-10-17 session-log entry, rewritten to
  say the research moved and where.
- RADIO-DRAMA §9's two findings, which are Archive Watch's own defects and not
  Ear Drama's: `discover_archive_collections.scrape_query` and
  `archive_lib.adv_search` read a throttled call as "nothing found"; and
  archive.org now sends CORS on audio storage nodes, which contradicts
  `docs/CATALOG-CONTRACT.md`. Both stay open in Archive Watch.

## 5. What the new repository inherits as rules

Carry these into Ear Drama's CLAUDE.md, with their source (they are the
owner's, not this research's):

| Rule | Source |
|---|---|
| Take-down model for audio and images: kept when unclaimed, hidden on a claim a reader can open, removed on request; never "public domain" for unclaimed | owner 2026-10-17; catalog DECISIONS 001 |
| No paid licence (no SoundExchange §114 statutory licence) | owner 2026-10-17 |
| No review queue: an image is used when its own record carries the evidence | owner 2026-10-21 |
| No AI-written lists or copy in the product | Archive Watch CLAUDE.md, owner 2026-09-26 |
| Only essential information on screen | owner 2026-09-22 |
| US English; no emojis | owner |
| Real devices only for testing | Archive Watch DEVICE-TESTING |
| Brand chrome vs semantic genre accents never mix | Archive Watch Decision 013 |
| A photo is never reshaped: fit at its own aspect | Archive Watch Decision 097 |
| Public domain by age follows the calendar | Archive Watch Decision 137 |
| Never recommended, always findable (Nazi-state speeches) | Archive Watch Decision 149; catalog `no_recommend` |
| A synthetic voice is a live stand-in only, never stored | owner 2026-10-18; 08a |
| Every catalog writer is additive and merge-guarded; a run that read nothing goes red | Archive Watch Decisions 020, 093, 107 |

## 6. Order

1. Wait for the three 2026-10-21 tracks (people portraits, photo archives,
   brand) to land on this branch.
2. Create the repository from the updated Universal App Template.
3. Move §1, then upload §2's Release.
4. Rename §3; write the new CLAUDE.md with §5.
5. On this branch: delete `radio-catalog/dist/`, then decide whether anything
   radio-related merges into Archive Watch beyond §4.
