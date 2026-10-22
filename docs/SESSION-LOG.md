# Session log: older entries

Newest first, word for word. The entries below were written in Archive Watch's
research branch, before Ear Drama had its own repository; paths in them are the
old ones (`radio-catalog/` is now `catalog/`, `docs/research/radio/` is
`docs/research/`, `RADIO-DRAMA.md` is `RESEARCH.md`).

### 2026-10-17 — research for a public-domain radio drama app (nothing built)

Owner: *"I'd like to have a public domain audio app that is specifically focused
upon radio dramas, plays and other public domain radio shows ... The result of
this loop should be all of the design, metadata, and content research necessary
to start working on the app in a future session."* Seven parallel tracks;
network opened mid-session (it had blocked everything but search).

- **Synthesis**: `docs/research/RADIO-DRAMA.md`; detail `docs/research/radio/01-07`,
  probe `tools/probe_otr_corpus.py`, sample outputs `radio/data/`.
- **Corpus** (MEASURED): `oldtimeradio` 8,952 items, 807,585 files, 5.32 TB;
  episodes are files inside items; OTRR filenames give a full date 83.7%.
  Duplicates never share md5 — merge on series + date.
- **Spine**: RadioEchoes (owner's question) — 5,069 human-genred series, dated
  episodes; never play its S3 audio. Goldin's index: facts free (*Feist*), ask
  for an export anyway (owner's question).
- **Rights**: pre-1972 recordings are §1401's, protected to 2067 unless
  published; by-age stays in (1925 in 2026). Owner pushed back on practice:
  §1401(f)(5) (no statutory damages without a filed schedule), §512, and the
  §114 SoundExchange license for channels make a four-layer structure (§3a).
- **Design**: 697 App Store reviews; bedtime and the car; "Tonight in 1947".
**Open**: owner Q1-Q12 (`RADIO-DRAMA.md` §7). Found, not fixed: Archive Watch's
`scrape_query`/`adv_search` read a throttled call as "nothing found"; archive.org
now sends CORS on audio storage nodes, contradicting CATALOG-CONTRACT.

