---
name: internet-archive-source
description: "Use when an app or pipeline reads archive.org (the Internet Archive): enumerating collections, fetching item metadata, picking a playable file, streaming audio or video, harvesting reviews/views/lists, or building a catalog from it. Carries what Archive Watch measured over six months and ~27,000 items, plus the 2026-10 audio-corpus measurements: scrape vs advancedsearch, throttled-is-not-empty, the main-host connection limit, honest User-Agent, upload date is not the work's date, item ids lie about content, private and history files, asynchronous derivatives, storage-node redirects and pinning, CORS facts, per-item vs per-file signals, and the archive's own collections as evidence. Triggers on archive.org, Internet Archive, advancedsearch, scrape API, /metadata, /download, storage node, ia_lib, archive_lib, pick_video, OTR, public-domain media source, 'nothing found' from archive.org."
---

# Reading archive.org

Archive Watch built its whole catalog from archive.org, and an audio
sister app is about to do the same. archive.org is generous and free,
and it is also a shared public service with its own habits: answers
that look empty when they are throttled, dates that describe the upload
instead of the work, and items whose ids say one thing while their
files hold two hundred others. These are the habits we measured.

The thesis: **treat every archive.org answer as evidence about the
upload, then prove what it says about the work.**

## 1. Enumerating and searching

- **Bulk enumeration uses the scrape API**
  (`/services/search/v1/scrape?q=&fields=&count=5000&cursor=`), walking
  the cursor to the end. `advancedsearch.php` is for counts (`rows=0`)
  and small batched `identifier:(a OR b ...)` lookups.
- **Never trust a scrape total alone.** Measured 2026-10-17:
  `total_only=true` returned the same total for every query tried, and
  some small calls returned a single bogus record. Cross-check against
  advancedsearch `numFound`, which was consistent.
- **A throttled call is not "nothing found."** AW's own helpers returned
  `[]` (and a bare `return`) on a non-OK response, so a 429 read as an
  empty collection. Distinguish the three outcomes in the return type:
  results, a definitive empty, and could-not-read. A could-not-read
  turns the run yellow and retries; it never writes "zero."
- Pace the main host: sequential or two to three workers, a pause
  between calls, backoff on 429/5xx. For a first full harvest of a large
  corpus, archive.org asks you to email info@archive.org first.

## 2. The connection limit and the honest client

- archive.org rate-limits a client IP that opens too many simultaneous
  connections to its MAIN host (`/metadata`, `/services/img`, the
  `/download` redirect). When tripped it refuses connections outright,
  and every feature that needs the main host breaks at once while
  streams from storage nodes keep playing, which is the tell. Fix it
  with one shared session per app capped at about 3 connections per
  host, and a global limiter on fan-out work (thumbnails, metadata,
  re-encodes). Never `URLSession.shared` or an ungated image view in a
  grid of archive items.
- **Send an honest User-Agent with a contact URL or email** on every
  request, from every tool. Without one, ffmpeg got 403/401/5xx on
  nearly every file. Some services in the same pipeline (Wikimedia,
  loc.gov) refuse spoofed or datacenter clients outright; loc.gov blocks
  GitHub Actions IPs, so plan a non-CI path for it.
- **Only 404/410 is definitive.** 403, 429, 5xx, and timeouts are
  transient. Never hide, delete, or mark dead on one.
- `/metadata/<id>` can hang for minutes or 404 on an item that plays.
  Bound it (20 s in a browser, 40 s in a pipeline) and bake the
  resolved `downloadURL` into the catalog rather than re-deriving it on
  a person's device.

## 3. What an item's metadata does and does not say

- **`date` is usually the UPLOAD date.** "The Devil's Holiday (1930)"
  carried `date: 2025`. Read `year`, then a year stated in the title,
  then the description, and record which one you used.
- **Item ids lie about content.** `the-shadow-1938-10-09-141-death-stalks-the-shadow`
  holds 239 episodes. Never derive a work's identity from an item id
  unless the item holds exactly one work, and never assume the largest
  file is the right one (AW once played "Felix Finds Out" for a
  different cartoon). Many-works-in-one-item is the common case for
  serials and radio; see `canonical-entity-identity` §sub-item identity.
- **The license field is the uploader's claim.** It is the starting
  signal, never the verdict (`evidence-gated-catalog-curation` §2).
- **The description is the uploader's voice**: often a review, a shot
  list, or a note about digitizing. Stamp it `source: archive` if you
  show it at all.
- **The archive's own collections are evidence.** An item in
  archive.org's trailer collection is a trailer, whatever title it
  wears (AW Decision 163), and AW refuses to promote an item in
  archive.org's own `deemphasize` collection into a series (a numbered
  antisemitic audiobook passed every file rule but that one, AW
  Decision 166). Read collection membership as a signal before guessing
  from titles.
- Community signals (reviews, favorites, views, member lists) are
  **per item, not per file**. For a many-works item they say nothing
  about any one episode; report "unknown," never zero.

## 4. Picking a playable file

- `private: true` files fail with 401/403 forever, on every node. Guard
  them out in the picker, not in a cleanup sweep, or each new upload
  reintroduces them (AW Decision 104). `history/files/*.~N~` are old
  revisions, never copies.
- **Derivatives are made asynchronously.** A fresh upload may have no
  MP3, OGG, or MP4 derivative yet. Record the gap and re-pick later
  rather than settling on the original forever.
- Prefer the format every target platform's native player opens. Apple
  players do not open Ogg or Matroska; a work with no compatible file
  is not a playable copy anywhere it must play natively.
- Judge a fragment by runtime evidence (a 4-minute file against a
  30-minute entry), never by title.

## 5. Streaming from storage nodes

- `/download/<id>/<quoted name>` answers with a 302 to a storage node
  (`dnNNN.<region>.archive.org`) that supports byte ranges. Store the
  `/download/` form and let the client follow the redirect.
- **Pin the node after the redirect** for the rest of a session, resume
  an interrupted transfer from the exact byte offset, and on a hard
  failure fail over to another node (AW Decisions 021, 031, 034; the
  full pattern is `resilient-media-streaming`). archive.org drops idle
  connections mid-file. For ffmpeg, pass `-reconnect 1
  -reconnect_streamed 1` and the honest User-Agent.
- **CORS: measure before you design.** AW's 2026 contract recorded that
  storage nodes send no CORS, which is fine for `<video>`/`<audio src>`
  and blocks Web Audio, MediaSource, and waveform analysis in a browser.
  The 2026-10-17 audio measurements found CORS headers on audio storage
  nodes. Probe the exact file types you serve, from a browser origin,
  before building a web feature that depends on either answer.
  `/metadata` sends CORS. GitHub Release assets do not.

## 6. Pipeline habits that came from archive.org

- Cache every network answer into a committed editorial file keyed by
  item id, with a fetched-at time and a TTL tiered by visibility (hot
  items re-checked sooner), so the build itself runs without a network
  and a re-run is resumable.
- "Already attempted" markers are per source, or a second source never
  runs (AW Decision 055).
- Ingest applies no rights judgment of its own, but it must carry what
  the rights audit needs (license URL, dates, network, country) onto
  every copy, so nothing reaches a shelf unjudged. And new items are
  judged before they ship: hand discovery off to the audit, not
  straight to publish.
- Print a yield line from every writer (items read, written, skipped,
  could-not-read), so the fleet auditor can tell SILENT from DRAINED
  (`ci-fleet-engineering`).

The cost of all this is time: a careful full harvest of ~12,000 large
radio items at a polite pace took an estimated 20 hours. Run it
incrementally, keyed on what changed, and let the cache carry the rest.
