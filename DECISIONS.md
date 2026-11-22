# Ear Drama — Architecture & Technology Decisions

Entries capture the *why* behind choices — not the *what* (the code
already shows that). Each entry should answer: **"what would the next
developer get wrong if they didn't know this?"** Lead with the rule,
follow with `**Why:**` and `**How to apply:**`. Append-only.

When a decision affects people and not just code, add one line:
**Who was in the room, who gains, who pays:** (who took part in the
decision, who benefits, and who bears the cost, in money, effort, or
something lost).

Invoke the `architectural-decision-log` skill when adding a new entry.

---

## Index

Entries 001-045 are in `docs/decisions/DECISIONS-001-045.md` and 046-065 in `docs/decisions/DECISIONS-046-065.md`, verbatim; 066 onward are below in full.

- 001: Vanilla HTML/CSS/JS for Web (archived)
- 002: Xcode Project at Repository Root (archived)
- 003: Shared Apple Version Config via xcconfig (archived)
- 004: SwiftUI + @Observable + SwiftData (Apple) — iOS 26 / tvOS 26 baseline (archived)
- 005: Cross-Platform Feature Parity (archived)
- 006: Kotlin + Jetpack Compose for Android (NOT KMP / CMP / Flutter / RN) (archived)
- 007: Material 3 + M3 Expressive; brand theme default, dynamic color opt-in (archived)
- 008: Android: Compose-only, no XML / AppCompat / ActionBar (archived)
- 009: Android: edge-to-edge + predictive back are non-negotiable (archived)
- 010: Universal Links / App Links: `/.well-known/` is the contract (archived)
- 011: Refresh JWT before every Worker / Storage / Edge Function call (archived)
- 012: Brand vs Semantic color split is binding on all platforms (archived)
- 013: One universal Apple target serves iPhone, iPad, and Apple TV (archived)
- 014: The platform set is a decision, not a default (archived)
- 015: Per-ecosystem sync on the user's OWN cloud; no backend to run (archived)
- 016: Shared data plane: published once, every client a consumer (archived)
- 017: tvOS persistence: Caches + App Group only (archived)
- 018: Debug/state env hooks ship in the app, as production no-ops (archived)
- 019: macOS joins the universal Apple target (amends 013) (archived)
- 020: Default Apple submission is a cloud build on a GitHub runner (archived)
- 021: Android publishes to Play via the Developer API from the CLI (archived)
- 022: Player title/metadata uses each platform's native chrome hook (archived)
- 023: Cross-platform multiplayer rides a transport seam; the protocol + arbiter live in Core (archived)
- 024: Online play is per-ecosystem native + a neutral backend; bot-first with honest labels (archived)
- 025: Cross-platform-identical values use order-independent hash-rank + golden-parity tests (archived)
- 026: Persist per-event detail, not just aggregates (archived)
- 027: Cloud Apple builds self-revoke stale auto-created Development certs (archived)
- 028: Smart TVs are two builds plus two zero-app routes, never six apps (archived)
- 029: Windows is an optional first-class platform, and CI is the Windows machine (archived)
- 030: The CI fleet runs on the split-lock / budget / guard / sweeper / auditor doctrine (archived)
- 031: A red X is reserved for broken (archived)
- 032: The agent is never the tester: changes ship on external observation (archived)
- 033: DECISIONS.md stays context-sized: index + recent entries; archives are verbatim (archived)
- 034: Markers carry their source, their timestamp, and their evidence (archived)
- 035: Account deletion is a launch requirement, and the anonymous account is an account (archived)
- 036: Bundled content is queried, never loaded: RAM is a shipping constraint (archived)
- 037: A generator's output is not the shipped artifact; re-running one must be additive (archived)
- 038: Randomness lives outside the selection pipeline (archived)
- 039: Store billing APIs disagree in shape; port the intent, never the code (archived)
- 040: Local persistence must never block launch: open in do/catch, fall back to in-memory (archived)
- 041: When the native project can't live at the repo root, a root workspace shim satisfies the CI host (archived)
- 042: Platform-free logic gets a sidecar SPM package so `swift test` runs without a simulator (archived)
- 043: Algorithmic surfaces honor the user's own moderation and explain every ranked item (archived)
- 044: Every user-visible affordance must control something real (archived)
- 045: Feature gating: keep the code, gate the single UI entry point (archived)
- 046: One canonical ID and one canonical asset per entity (archived)
- 047: Two backend postures: sync islands OR the hosted split — choose in M0 (archived)
- 048: Next-OS APIs are adopted additively behind BOTH a runtime and a compile-time gate (archived)
- 049: Marketplace-adjacent features never touch money (archived)
- 050: Market data is provenance-honest, and the sold history is generated, not bought (archived)
- 051: Every third-party data dependency is presumed revocable (archived)
- 052: User-facing vocabulary is a render-layer contract over frozen schema names (archived)
- 053: The look has one source, and every platform's tokens are generated from it (archived)
- 054: Ear Drama is its own app and repository, `app.eardrama`, at eardrama.org (archived)
- 055: The catalog's rules are the owner's, carried from Archive Watch and the research (archived)
- 056: Version 1.0 is the core five, with every other platform as a stub (archived)
- 057: Signing in is optional; it syncs, and it is required to make plays with others (archived)
- 058: Listening features in 1.0: Radio evenings, Listen Together, transcripts (archived)
- 059: Shared plays in 1.0: pass the phone and invite links, radio and stage scripts, CC0 (archived)
- 060: The look: the ring microphone, Big Shoulders and Public Sans, new genre hues (archived)
- 061: Playback loudness targets -21 LUFS, reached by cutting (superseded by 067 and 069) (archived)
- 062: One set of player numbers on every platform (archived)
- 063: Sign-in is verified at the Worker, which issues its own session; sync is last-write-wins per row (archived)
- 064: The palette is On Air (archived)
- 065: Listen Together rooms need no account; the host is a member and hands off (archived)
- 066: Shared plays live on the Worker, invite-only, with take audio in R2 behind the owner's switch
- 067: The owner's rulings of 2026-10-23 on plays, Radio, playback, and the shell
- 069: Volume is leveled by each platform's own dynamics processor, at one set of numbers
- 071: Downloads are a whole run in the apps, asked first; the web downloads nothing
- 072: Invite-only takes need an account, not the CC0 consent
- 073: One archive.org item per production, one file per line, named so a retry can only overwrite
- 074: Take-down notices: a complete notice removes on its own, and nobody's details are public
- 075: Five sections with Record among them; Home opens on what is on the air (answered 2026-11-14)
- 076: A script reader of its own, pages first; the studio lives inside it; Kokoro for downloadable voices (answered 2026-11-14)
- 077: Audio starts without reading the whole file; Play on the loaded episode resumes it
- 078: Kokoro voices: phonemes built in the catalog; apps first; the web on WebGPU only (answered 2026-11-15)
- 079: A first take needs no account; empty productions stay out of sight; Today's scene everywhere (answered 2026-11-15)
- 080: At regular width Now Playing stands beside what plays next; closing the Duo never stops a take (answered 2026-11-16)
- 081: Drawn label art for everything without a picture, and a Home that reads as one thing (owner 2026-11-19)
- 082: Reading together: read rooms, classes that own productions, takes that pass through (owner 2026-11-19)
- 083: Relay across time, and credit the maker (owner 2026-11-19, T6)
- 084: Student privacy: who recorded what is deleted on a schedule, the ear drama is kept, and the school decides (owner 2026-11-21)
- 085: The owner's routes take a GitHub OIDC token, not a stored one (owner 2026-11-22)
- 086: Voice defaults live in Settings; Kokoro leads them where it can run; a play's cast only overrides (owner 2026-11-22)

---

## 066: Shared plays live on the Worker, invite-only, with take audio in R2 behind the owner's switch

*Date: 2026-10-23*

A production is checked against a castable manifest (each castable cast
sheet's SHA-256) and seen only by its members, who join by an invite token
(256-bit, stored as a hash, revocable, expiring in 1 to 30 days). Takes are
immutable R2 objects checked from their own WAV or FLAC headers (mono, at most
300 s and 45 MB; a bleed-flagged take is refused). Reports, blocks, and a
server-side name filter answer App Store guideline 1.2. CC0 consent is recorded
by version id; publishing only queues a `pending_owner_account` job.

**Why**: Decision 057 requires an account to cast a shared play. D1's 500 MB
holds under an hour of 24-bit audio, while R2 has free egress but asks for a
payment method (research 08c Q8), so the take store waits on the owner. The
Worker never takes a client's word for what is castable.

**How to apply**: run `node worker/tools/castable-manifest.mjs` after every
castable rebuild (a test fails when the two drift). New consent words need a new
`CONSENT_VERSION`; the words are the owner's, approved 2026-10-29 ("Let's refine
the text and use it", then "Yes. Change the first line. It should all make sense
as one coherent approval."), version `cc0-2026-10-29`, verbatim:

> Publishing puts this play on the Internet Archive.
> - Your recording will be public. You can replace it with a new take or remove it later, but copies others have already made can't be called back.
> - You dedicate it to the public domain (CC0). Anyone may copy, change, or sell it, for any purpose and without credit, including training AI and cloning voices.
> - It must be your own live voice: no synthetic or cloned voices, and no imitating a real person.
> - You're 13 or older, or your teacher has recorded your school's consent.
>
> Agree button: "I agree to publish my recording under CC0."

Publish refuses any consent recorded at a version whose text starts with
"OWNER:" (the owner's "yes", 2026-10-29). Clients fetch the words from
`GET /consent` and never hard-code them; `GET /consent` also says
`publishes` (the archive.org keys exist), and Publish is offered only when it
is true. Every person table goes in USER_TABLES, and any person
column that is not `user_id` in OTHER_PERSON_COLUMNS. Owner items P1 to P8
(R2, consent words, a vetted deny list, report handling, school consent, the
archive.org account, C6/C7, class ownership) are in PLAYS-DESIGN §11.6.

**Superseded in part, 2026-11-19 (Decision 082)**: the R2 take store is not the
path. Storage is archive.org; takes pass through the Worker to the leader's
device and are deleted on arrival. P1 (turn on R2) is closed.

---

## 067: The owner's rulings of 2026-10-23 on plays, Radio, playback, and the shell

*Date: 2026-10-23*

Answered in one sitting, replacing the defaults that stood in for them:

- **What plays next**: a serial plays to its arc's end and stops; the next arc
  is offered, never started (research R3). Until arcs exist: one episode, then
  anything queued.
- **Loudness**: no per-file measurement. The owner: *"There has to be a way to do
  this in software rather than as a metric for each recording ... Evening out
  volume on an app shouldn't be about knowing how loud an audio file is."* Each
  player levels volume on the device as it plays; the measuring workflow stops.
  Supersedes Decision 061's per-file gain.
- **Plays listen-through**: parts with human takes play those takes; parts
  without one are read live by the listening device's own voice (or an openly
  licensed voice generated on that device), so anyone can hear the whole play
  and choose to add their voice. Never stored or exported (the catalog rule
  holds); Export needs every speaking line human and is available any time
  then. C5 and C6 resolved so.
- **C7**: parts in any order, largest first suggested. **C9**: "the individual
  author died by 1955" is accepted as evidence. **C10**: commercials stay, each
  its own part. **Personal Voice**: offered, live only, never stored.
- **Recording needs an account**, always, even a play never shared.
- **Children and teachers**: plays are marked only by facts from their records
  (year, author, length); no invented age ratings.
- **Listen Together**: a guest may pause their own sound and catches up on resume.
- **Tonight in 19xx**: an evening shows when any program survives (the 0.25 floor
  goes); a gap shows its time and the program's name when the listing matched a
  series, never the newspaper's printed text; a listener may pick another
  published year for the same date.
- **Command Performance**: the AFRS rule stands.
- **Shell**: six sections; on an iOS 18 iPhone Search goes in More.
- **Listen**: a popularity shelf from data (archive.org's own download counts),
  not "Most episodes".
- **Sign-in** merges the device's history automatically. **No data export** for 1.0.
- **Fonts and the CC0 microphone photo** may be downloaded. **GRW**: ask before
  using any transcription (the owner sends the request). **Samsung**: not for
  1.0. **Store category**: Entertainment.

**Why**: these were the owner's calls (SCRATCHPAD "Waiting on you" 2, 4-9, 12-14
and PLAYS-DESIGN §9), each blocking a feature batch.

**How to apply**: each binding design doc gets the rule before its feature
changes; LOOP-PLAN "Feature batches" carries the work.

## 068: Sections are actions, as in Archive Watch; Stations; any script can become an ear drama

*Date: 2026-10-24*

The owner: *"we should focus on actions and not content type ... we should
mimic the items from Archive Watch."* The shell becomes Archive Watch's: **Home ·
Browse · Stations · Surprise · Search · Library**, placed per platform exactly as
Archive Watch places them (iPhone: five tabs, Home, Browse, Stations, Search,
Library, with Surprise behind a toolbar button on Home; iPad, Mac, and Apple TV
sidebars and the web's nav list Surprise; Android's Home top bar opens it).
Listen becomes Home, Series becomes Browse, Radio becomes **Stations**: *"Ear
drama is the type of content across the app, but collections of ear dramas
should be stations."* There is no Plays section. Supersedes 067's "six
sections; Search in More".

Recording is an action on anything with a script, not a section for one kind of
content: *"You should be able to re-record anything that has a script. You
search for something that has a script, and you should be able to start a new
ear drama. It could be a radio show/drama or it could be a play ... the content
type doesn't matter ... Ones you have participated in will show in library."*

**Why**: a section named for a content type (Series, Plays) splits one verb
(find something, listen to it, make your own) across places; Archive Watch's
tabs are verbs (browse-curated, browse-all, lean back, find, saved), and the
owner wants both apps to read the same.

**How to apply**: every binding design doc's shell rule changes first (WEB,
iOS, macOS, tvOS, ANDROID), then the code on all five, and PARITY.md. Stage
plays appear in Browse and Search beside radio series; any item whose record
carries a usable script shows "Start an ear drama" on its page; Library lists
the ear dramas a person has recorded in or joined. Script rights rules stand
(GRW only after they answer; C9). The verb test from Archive Watch's iOS-DESIGN
§12.2 applies: a new section must own a verb no other owns.

---

## 069: A show's picture is a served portrait of its star, else its typographic card

*Date: 2026-10-24*

A portrait reaches a client only when the image's own Commons record carries
public-domain or free-license evidence AND the person was matched to Wikidata on
a date of ours; the image is the person's own Wikidata image (P18). A series
wears the portrait of the person heard on most of its credited episodes (at
least 3 and a third of them); an episode wears its series' star when heard, else
its first on-air credit with a portrait. Everything else is drawn as a
typographic card from data: the name, the years, the network, on the genre hue.

**Why**: the owner, 2026-10-24: *"I don't see any images or artifacts from the
shows yet."* Track E measured about 1 in 30 matches as someone else, mostly on
the undated rule, which is the only rule that fails on its own logic; a wrong
face presented as checked is worse than none (`evidence-gated-catalog-curation`
§7). No series photograph is usable (Track F), so series art comes through the
stars. The undated rule (RESEARCH §12 V1), Library of Congress "no known
restrictions" (V2) and Smithsonian CC0 (V4) stay closed until the owner answers.

**How to apply**: `catalog/tools/art_policy.py` is the one predicate;
`docs/CATALOG-CONTRACT.md` §3.3a the shape; `catalog/tests/test_projection_art.py`
the guard. A CC BY / BY-SA image carries its `credit` wherever it is shown at
header size or in Detail credits (a required fact). Clients never re-host,
never crop a portrait into a frame that loses the face (top-anchored), and draw
no stock placeholder: the typographic card is the default artwork. To open a
closed class, answer its V question; the predicate changes, never a list of ids.

*Amended 2026-10-28 (V3)*: a face's box takes the picture's shape. Owner: *"I
think you can find better solutions for different aspect ratios of images, then
just blurring and black bars."* The projection now publishes each portrait's
width and height (`harvest_people_wikidata.py --phase dims`), wide is past 1.15
on every platform, an upright face is a print beside its heading and a wide one
a plate above it, and nothing is drawn behind a picture
(`artwork-presentation-design`, WEB-DESIGN §6.4a, R11a in each design doc).

*Amended 2026-10-28 (V4)*: "top-anchored" is replaced by the published face. A
wide portrait's small crop showed the middle of the frame (J. Carrol Naish's
title card), so each served portrait now carries a face box computed once, on a
Mac, by Apple Vision (`harvest_people_wikidata.py --phase faces`, contract
§3.3a), and every small crop is the square around it from one formula (the
face about half the square, at most 4x zoom: anchoring alone kept Naish's
lettering in a 32 px circle). Without a face an
upright picture keeps the top anchor and a wide one is not cropped. No client
detects faces: the same box on every device, no model shipped, no battery.

*Amended 2026-10-29 (D2c-2)*: the show's own picture leads, then its star. Owner: *"The
images that should lead should always be ones that best represent the whole Ear Drama. So,
images/graphics that show the full 'show' are better than individual contributors. Images that
show the star(s) are better than those that show folks that are less recognizable."* Each series
now publishes `picture`, `picture_kind` (show, star, person) and `picture_source`: a file from the
show's own Wikidata or Commons record, matched on more than its title, with the same license
evidence as a portrait; else the star the program's record marks or a Wikipedia covers; else the
heard-most person; else the card (catalog DECISIONS 017, contract §3.3a). Clients still draw
`star`'s portrait until D2c-3 reads `picture`.

---

## 070: Volume is leveled by each platform's own dynamics processor, at one set of numbers

*Date: 2026-10-24*

Every player levels volume on the device as it plays, on by default, with one
switch ("Level volume") on the player that the person may turn off (kept on
the device). No client reads a per-file measurement. One compressor over the
whole signal, the same numbers everywhere: threshold -24 dBFS, ratio 4,
attack 3 ms, release 250 ms, makeup gain 10.8 dB (the Web Audio rule, 0.6 x
the compression at 0 dBFS, which the browser applies on its own), and a 12 dB
knee where the platform has one. Web: a `DynamicsCompressorNode` on the
`<audio>` element (`Player.LEVEL`). Apple: an `MTAudioProcessingTap` on the
item's audio track running Apple's DynamicsProcessor unit (`LevelNumbers`,
ratio stated as 6 dB headroom), holding samples inside full scale. Android:
`android.media.audiofx.DynamicsProcessing` on ExoPlayer's audio session, one
full-band compressor band and a limiter at -1 dBFS (`LevelNumbers`).

**Why**: the owner, 2026-10-23 (Decision 067): *"There has to be a way to do
this in software rather than as a metric for each recording."* A per-file gain
needed a 25 GB-a-day measuring run and still left a new or unmeasured copy at
unity; a compressor levels every copy, downloaded or streamed, the moment it
plays. Each platform's own processor was chosen over one hand-written
algorithm (`Native APIs, no workarounds`): the browser's node, Apple's unit,
and Android's effect are maintained by the platform and run off the main
thread. The numbers are the browser's defaults moved toward speech (ratio 4
rather than 12, so a voice is evened, not flattened), and the makeup rule is
the browser's own so the two platforms that set it by hand match the one that
cannot. Measured offline through the Apple unit on 2026-10-24: a -40 dBFS
passage followed by a -6 dBFS one, 34 dB apart, comes out 21 dB apart.

**How to apply**:
- The numbers live once per platform under the same names and are tested
  against these values (`js/player.test.js`, `VolumeLevelerTests`,
  `LevelingAndQueueTest`); change all three together.
- The web asks archive.org with `crossorigin` (it sends
  `access-control-allow-origin: *`, research 04 §5), builds the graph only once a
  tap has started the AudioContext, and loads a copy refused that way again
  without it, unleveled. Not on iPhone or iPad web (a page's AudioContext stops
  at the lock screen) or a TV engine (unmeasured): the switch says "Not in this
  browser".
- A track, tap, or effect that cannot be made plays unleveled; it never stops
  playback.
- The sleep timer's fade and the mute door stay on the player's own volume (on
  the web, the graph's output gain), after the leveler.
- `loudness_i` / `loudness_tp` stay in the projection, unread;
  `catalog-loudness.yml` runs only on dispatch.
- Not yet heard on a device: the agent never plays sound at the owner. The
  first device check listens to a quiet and a loud episode in turn with the
  switch on and off.

---

## 071: Downloads are a whole run in the apps, asked first; the web downloads nothing

*Date: 2026-10-24*

On iPhone, iPad, Mac, and Android a person downloads an episode, a season, or
a whole series run from the series page, and every bulk download asks first
with the count and about how much space it takes (bitrate times length, from
the catalog's own recording rows). Downloads become a place pushed from one
Library row, grouped by series, with the storage held and Remove All at its
foot. The Apple TV says on screen that downloads are on iPhone, iPad, and Mac.
The web offers no download at all.

**Why**: R17, the car and bedtime: the listener wants the next twenty episodes
of a serial on the phone before a drive, and twenty taps on twenty Detail
pages is the wrong verb. A run can be gigabytes, so the space is a fact the
person cannot see by looking, and the one place a caption earns its words.
Hundreds of rows in Library's middle would bury In progress and Played, so
the downloads moved behind one row. The web was weighed honestly: Cache
Storage could hold a file and a service worker could answer the `<audio>`
range requests, but the places offline matters are a phone in a car and a
phone locked at bedtime, and iPhone web stops a page's audio at the lock
screen while its storage is best-effort and can be cleared without a word.
Android has the app. A download the web cannot promise to keep is not
offered (WEB-DESIGN §7.2a, and §5.8's standing "audio is never cached").

**How to apply**:
- The series key is an episode id's part before `|` (Route's own rule), so a
  series' downloads are found from the records already on disk; no field was
  added to the index.
- A plan (`DownloadPlan`, both stores) skips what is downloaded or running and
  retries what failed; transfers are capped at four at once (the background
  session's per-host limit on Apple, a four-wide queue on Android) so a run
  never opens hundreds of connections to archive.org.
- Playback still prefers only a finished file; a queued, running, failed, or
  partial download never plays (`localFile`). The leveler and the queue rule
  are unchanged: a downloaded file is leveled as it plays, and what plays
  next is still Decision 067's.
- The car's Downloads tab lists finished downloads on CarPlay and Android Auto.
- Not verified on a device: no real run was downloaded by the agent (tests use
  fixtures), and nothing was heard.


---

## 072: Invite-only takes need an account, not the CC0 consent; the consent screen and Publish wait for the owner's words (answered 2026-10-29)

*Date: 2026-10-28*

Owner, 2026-10-28, asked whether a take for invitees needs the CC0 consent before
upload or only at publish: "Consent at publish only."

A take uploaded to the Worker is heard only by the production's members, so
uploading it asks for an account and nothing more. The CC0 consent, with
its warning, is asked before anything goes beyond the members, which today
means Publish. The owner approved the words on 2026-10-29 (Decision 059), so the three
gates (`TODO(M8-consent-screen)`: web/Android `PlaysShare.PUBLISH_OPEN`, Apple
`PlaysShare.publishOpen`) are gone. Each app shows the consent screen with the
Worker's words before Publish and records consent at that version, and offers
Publish only when `GET /consent` says `publishes`; until the Ear Drama
archive.org account is connected it shows "Publishing opens when the Ear Drama
archive account is connected."

**Why**: Decision 059's consent is about publishing ("contributions are
dedicated CC0 and uploaded to archive.org"), and its words are the owner's
to approve (LOOP-PLAN M8: "the words go to the owner before the screen
ships"). Batch 1 (2026-10-24) asked for that consent before every upload and
showed the Worker's "OWNER:" placeholder as the screen, so a person could
agree to words nobody had written, and a member could not send a take to
the people who invited them without signing away rights to strangers.
Batch M8a's brief (2026-10-28): "Do NOT ship, write or invent: the consent
screen with the CC0 warning ... Gate anything that would publish beyond the
invitees behind a clearly named TODO for that screen."

**How to apply**:
- The Worker's `uploadTake` checks no consent (`worker/test/plays.test.js`,
  "need no CC0 consent"; the mutation "upload demands the CC0 consent").
  `publish` still needs every performer's consent at the current version.
- The clients' upload path never calls `GET /consent`'s `agree`; it reads
  `GET /consent` only for the owner's `uploads` switch.
- Done 2026-10-29: `CONSENT_TEXT` and `CONSENT_VERSION` (`cc0-2026-10-29`) in
  `worker/src/plays.js`, the screen from PLAYS-DESIGN §11.7 rule 6.
- Owner to confirm: that a take shared with invitees only is outside 059's
  consent. If not, uploads wait for the screen too (one line in
  `uploadTake`).

---

## 073: One archive.org item per production, one file per line, named so a retry can only overwrite

*Date: 2026-10-29*

A published production is one archive.org item, `eardrama-<production id,
lowercased>`, in Community Audio (`opensource_audio`), made by the Worker's
cron through the S3-like API with the Ear Drama account's keys. Each line's
chosen take is one file, `NNNN-PART.wav` (or `.flac`), NNNN its place in the
script, so the item lists the play in order and a line keeps its name for
good. A performer replaces their own line's take or removes it, and the
director removes any line; the Worker overwrites or deletes that one file and
keeps who removed it and why. Publish opens only when both
`IA_S3_ACCESS_KEY` and `IA_S3_SECRET_KEY` are set.

**Why**: the owner gave the account's keys on 2026-10-29 and asked (P12):
*"We don't want to provide a pathway for people to delete and re-upload a
full recording?"*, and the approved consent words promise *"You can replace it
with a new take or remove it later"*. A promise of removal needs a file a
person can point at: one file per line is the unit a performer owns, while a
mixed file would hold everyone's voice and could only be re-cut on a device
(the mix is rendered on the device, PLAYS-DESIGN §2.7, never on the Worker).
An identifier fixed when the production is made, and file names fixed by the
script, make every retry land on the same name, which archive.org overwrites
rather than adding a second copy; an archive.org identifier is permanent, so
it carries no title or person that could change. Community Audio is the
collection archive.org opens to a new account's audio; a collection of Ear
Drama's own needs archive.org to make it.

**How to apply**:
- `worker/src/plays-archive.js` is the only code that talks to archive.org:
  20 requests a run, every five minutes (`*/5 * * * *`); check_limit before
  uploading; 429, 5xx (archive.org's 503 SlowDown), and network errors back
  off from 5 minutes, doubling to 12 hours, and fail after 10; any other 4xx
  (a size refusal, a refused key) fails at once with archive.org's code as the
  reason. The keys are never logged and are redacted from any stored reason.
- Metadata is data: the script's title, source, and rights evidence from
  `castable-manifest.json`; `creator` and `credits` from the performers'
  chosen names; `licenseurl` CC0 1.0; `mediatype` audio. When a performer's
  last line leaves the item, their name leaves its credits (the metadata write
  API).
- A replacement needs the performer's consent at the current version, and a
  reported take is held back from the item until its report is answered. A
  line the director removed cannot be put back by its performer.
- A failed job is queued again by the director's Publish; lines already on
  the item stay sent.
- Owner to decide: whether deleting an account also removes that person's
  lines from the item (today it does not; their lines stay, uncredited once
  the account goes), and whether to ask archive.org for an Ear Drama
  collection.

**Who was in the room, who gains, who pays:** the owner gave the account and
asked for replace and remove; the agent chose the identifier, the collection,
and the file layout. Performers gain a recording they can take back from the
item; listeners on archive.org get the play line by line, not one file; copies
others made before a removal stay out of reach, as the consent says.


## 074: Take-down notices: a complete notice removes on its own, and nobody's details are public

**Rule**: the take-down page asks for the elements of a 17 U.S.C. section 512(c)(3)
notice and nothing more, through a quiet form (one footer link) or email. A complete
notice removes unless the evidence contradicts it. The public list holds a date and a
case number; the requester sits in a private D1 table, erased three years after the
case closes. Nothing a requester wrote reaches Actions logs or issues.

**Why**: the owner, 2026-11-04: *"Let's keep personal details out of the public
repo... All of these proposals seem incredibly reasonable."* (Archive Watch's note,
its Decision 175; the owner is the registered agent, DMCA-1083942; reply time 48
hours, owner 2026-11-14, was one week.) The full rule, signals and tests are catalog Decision 029.

**How to apply**: a Worker change reruns `cd worker && npm test && npm run test:mutations`;
a change to `catalog/tools/takedown_*.py` reruns `catalog/tests/test_takedown_check.py`.
The deploy needs migration `0005_takedowns.sql` on D1 `eardrama` and `wrangler deploy`
(adds the `TAKEDOWN_LIMITER` binding). The case routes once took a stored `TAKEDOWN_TOKEN`;
since Decision 085 they take only `takedown-check.yml`'s GitHub OIDC token. No
platform app change: each already links to the web page (PARITY.md).

## 075: Five sections with Record among them; Home opens on what is on the air (answered 2026-11-14)

**Rule**: the app's sections are **Home · Browse · Record · Search · Library**.
Home opens on what is on the air now with Listen live (tonight's evening, else a
genre station), then three doors (Listen, Find a show, Record a play), then rows
each filled by a published data rule. Stations opens from Home's live block;
Surprise is a Home toolbar button. Record holds the person's productions, then the
plays, browsable by voices, length and kind. "Record this" sits beside Play on any
page with a castable script. No sentence explaining the app: the live block and the
doors say it. The play library grows to every rights-cleared Gutenberg play that
parses clean, published beside the catalog. Radio scripts come next from the USDA
typescript harvest (OCR repair, per-script authors), not from the Generic Radio
Workshop. Replaces Decision 068's six sections.

**Why**: the owner, 2026-11-14: *"It is entirely unclear what the app is or how to
use it easily... Right now, it just shows as a database of old content"* and *"The
ability/functionality for recording new Ear Dramas is significantly buried."*
Research (`docs/research/design/R2-home-and-create.md`): Home opened on a chart with
no Play button; the recorder sat 3-4 taps behind a hidden filter; radio apps make
their purpose plain by leading with what is on now; creation stays visible when the
button sits on the thing itself. The owner chose these options from that report;
on radio scripts they chose the USDA harvest over asking GRW.

**How to apply**: the binding design docs' tab rules change first (iOS, iPad, macOS,
tvOS, web, Android), then PARITY.md, then the build. Ranking stays rule-based
(`values-based-feed-ranking`); every row names its data rule.

## 076: A script reader of its own, pages first; the studio lives inside it; Kokoro for downloadable voices (answered 2026-11-14)

**Rule**: every castable play has a **Read** door (no account) that opens a reader
of its own: **pages by default** (a slide, never a curl; two pages when wide),
continuous scroll as a setting; contents by act and scene, search, text settings,
and "I'm playing ___" (highlight my lines, jump to my next, hide them to rehearse).
The studio opens from inside the reader: tap any line to record or re-record it,
every take kept, a take list per line. The three recording modes (Run through,
Line by line, Step) stay, as three ways the reader moves. Each part gets a voice on
the cast sheet; one shared assignment everywhere (the recorder and the listen-through
today keep separate maps, a defect). Auto-cast never guesses a character's gender.
Downloadable voices: **Kokoro-82M** (Apache-2.0) on every platform, Kitten nano as a
light option if its license checks; eSpeak (GPL) and Piper (GPLv3 engine) stay out;
model audio is a live stand-in, never stored. The owner took the research's
recommendations on the rest: typed marks everywhere plus Pencil ink on iPad, anchored
to lines; marks on the device first, synced later; marks private; each device keeps
its own cast; a closed phone shows the script with a compact record dock; TVs get a
read-along panel only; stage directions not read by default.

**Why**: the owner, 2026-11-14: *"You should be able to read a script and turn pages
and mark them up and do all of the things that a good book/script reading experience
should contain... It should be easy to go back and forth within the script and
rerecord any line."* Research: `docs/research/design/R2-script-reader-and-studio.md`.
The owner chose pages over the recommended scroll default.

**How to apply**: build by that report's phases (S0 data, S1 reader, S2 voices on
the cast sheet, S3 studio in the reader, S4 wide and Duo layouts, S5 marks, S6 Kokoro,
S7 polish), each on every platform. Design docs and PARITY.md first.
## 077: Audio starts without reading the whole file; Play on the loaded episode resumes it

**Rule**: Apple opens a network recording WITHOUT
`AVURLAssetPreferPreciseDurationAndTimingKey`, holds play until the item is
ready and its first 64 KB of frame headers are read (`StartTiming.sniff`,
past an ID3 tag if need be), and reopens it with precise timing, at the same
place, only when the frames vary and the first frame carries no
Xing/Info/VBRI table. Unreadable frames fall back to the quick duration
against the catalog length (5%). A download keeps precise timing. On every
platform, Play on the episode already on the player resumes it in place
(no reload); a load that fails while paused is retried paused; Play on a
load that failed for good opens it again at its place.

**Why**: the owner, 2026-11-14: *"The playback of items from Archive.org
seems to take a very long time to get started... Additionally, resuming play
from a paused show doesn't resume the show correctly."* Measured on a Mac
(muted, real archive.org files, a query string per trial so nothing is
cached): with precise timing AVPlayer downloads the WHOLE file before the
first sound, 1.2 to 44 s (a 70 MB file), while `timeControlStatus` already
reads `.playing` and the clock stands still; without it, 0.6 to 2.2 s. The
real AudioPlayer, tap to a moving clock: 2.7 to 12.3 s before, 1.5 to 3.1 s
after. The 1.0.73 reason for precise timing is real but narrow: of 79 sampled
files only a few are variable-bitrate with no table, and for those the
catalog length is itself a bitrate estimate (Challenge of the Yukon
1949-12-09: listed 1956 s, decodes to 1757 s), so only the frames can find
them. Every Play button reloaded the item, and with precise timing each
resume re-downloaded the file; every platform's recovery started what the
person had paused.

**How to apply**: never put the precise-timing key back on network items
wholesale. A start measurement interleaves arms or repeats them; caching
flatters whichever arm runs second (`PlaybackStartProbeTests`,
`ED_START_PROBE=1`). Android (`Mp3Seeking`) and the web still time a
variable-bitrate file with no table from the catalog length or the
browser's estimate, so a resume there can land off by the length error
(about 10% on the Yukon file): not fixed here.


## 078: Kokoro voices: phonemes built in the catalog; apps first; the web on WebGPU only (answered 2026-11-15)

**Rule**: the catalog builds every castable line's phonemes once (misaki under its
Apache license, plus project lexicons for role names, elisions and early-modern
spellings; never eSpeak) and publishes them per play with a correction file and a
report of guessed words; no device converts text to phonemes. Native apps run the
q8f16 model (~86 MB + voices, ~101 MB) from a GitHub Release asset; build order
Android (ONNX Runtime), then Apple (our own Core ML conversion, no third-party
Swift packages). The web offers Kokoro only where WebGPU works, with the fp32
model (~326 MB) served from eardrama.org in parts under 50 MB, gated by a
self-test after download; other browsers keep the built-in voices. Never fp16
(NaN audio). misaki's dictionaries are used under the package's Apache license and
the author is asked to document their source. A Kokoro voice is a live stand-in,
never stored (Decision 076).

**Why**: the owner chose these options on 2026-11-15 from
`docs/research/design/R2-kokoro-feasibility.md`: 98.1% of play words get a
pronunciation with the build-time fixes; q8f16 matches fp32 by Whisper WER;
browsers run q8 slower than real time and fp16 produces NaN.

**How to apply**: phases S6a to S6f in that report, each with its gate; the phone
benchmark (iPhone 12, Pixel 8a) is S6a's gate.

*Update, S6a Android (2026-11-15)*: ONNX Runtime Android renders the q8f16 model as
all-NaN (1.31.1 and 1.32.0; sound on desktop), so Android reads the q8 model with
fp32 activations instead (`kokoro-v2-manifest.json`, ~107 MB), with the CPU arena
shrunk after every render and 100-symbol pieces: RTF and peak memory pass the gate
(R2-kokoro-feasibility, "S6a on the Pixel 8a"). Never fp16 on Android either.

## 079: A first take needs no account; empty productions stay out of sight; Today's scene everywhere (answered 2026-11-15)

**Rule**: a newcomer can record without signing in; takes stay on the device, and
an account is asked for only to share, invite, publish, or start a second
production. A production appears in Yours only after its first take, and one that
stays empty is removed. Once finished ear dramas exist, they lead Home right under
the three doors while there are fewer than six, then return to the Made here row.
Today's scene (a two-voice play of at most 20 minutes, same date hash as Today's
play, with Try a line and Hear it) replaces Today's play on every platform.
Replaces the 2026-10-23 rule that recording needs an account (Decision 072's
invite-only takes still need one).

**Why**: the owner chose these on 2026-11-15 from
`docs/research/design/R2-design-review.md`: recording took five steps then stopped
at "Recording needs an account"; empty productions piled up; nothing showed what an
ear drama sounds like; research (Duolingo, Smule, Nielsen's participation
inequality) says let people try before asking for commitment.

**How to apply**: binding design docs first, then web, Apple, Android in one batch;
PARITY rows.

**Amended 2026-11-15**: the post-leave cleanup has no timer. A production is never
deleted while a take write for it is pending or a recording session for it is open;
leaving the studio waits for the production's take writes to settle (web
`store.discardIfAbandoned`, Apple `removeWhenSettled`, Android `dropWhenSettled`), and one
still empty then goes unless a screen holds it. **Why**: a take still encoding more than
2 s after leaving lost both itself and its production.

**078 addendum (owner, 2026-11-15):** Kokoro passed the Android gate (q8, ORT 1.31.1, arena hand-back, 100-symbol pieces; RTF 0.30, peak 579 MB on the Pixel 8a). The engine (~34 MB per device) ships as a Play on-demand feature module fetched with the voices, never in the base install ("Download on demand").

## 080: At regular width Now Playing stands beside what plays next; closing the Duo never stops a take (answered 2026-11-16)

**Rule**: at regular width (the open iPhone Duo, an iPad, a wide window) Now
Playing opens over the whole window as two panes, the player and what plays next
(the arc's next part, then the person's queue, reordered by drag in place; while
listening live, the station's or evening's lineup): an `ArrangementView` split,
side by side in landscape and stacked in portrait. A compact width keeps the
sheet. Closing the Duo during a take keeps recording: the take, the session and
the studio go on, the outer display shows the script with the record control,
nothing is lost, and opening the phone returns to the studio where it was.

**Why**: the owner held the first App Store submission for the Duo on 2026-11-16:
*"There is no reason to have the first version of our app not look as good as
possible on one of the most important devices for new apps that are built for
the duo (the app store has seen a huge resurgence in apps that are built
specifically to take advantage of the Duo - let's be a part of that)."* Q2
(Now Playing): *"Two panes."* Q4 (the fold mid-take): *"Keep recording."* Apple's
own example of an arrangement is a player beside its Up Next; its HIG asks that
functionality and state stay the same between displays.

**How to apply**: iOS-DESIGN §5.3 and §11.5 (amended), §5.9 (the queue pane) and
§4.15's fold rule; PLAYS-DESIGN §2.9 rule 11. Width decides, never the device: the
presentation is chosen once, when the player opens, so a fold never dismisses it;
the queue pane reads the player's own queue (`AudioPlayer.upNext`, `ListeningQueue`,
`LiveRadio`'s lineup) and offers only the queue's own verbs. A take's audio lives in
Core (`RecordingSession`, the `LiveAudio` engine), never in a view: a re-layout
starts and stops nothing, and the engine rebuilds its tap into the same capture when
the hardware reconfigures. PARITY rows "Now Playing beside its queue" and "Folding
during a take". Android foldables and tablets may mirror both later (⏳).

## 081: Drawn label art for everything without a picture, and a Home that reads as one thing (owner 2026-11-19)

**Rule**: anything with no real picture that passes the size floor is drawn as **the label**
(R3a §3.4, option C): a flat transcription disc made only from the item's own data. The board is
the genre, an arc on a fixed 1930-1962 dial is the years it ran (no arc when undated, never an
invented era), the center label is the monogram (on an episode, its air date or number), and at
large sizes the rim names the primary network and the decade in our own type. A finished ear
drama wears the same disc with its cast's part hues around the rim and no arc; a person without
a portrait is a round window with the initials inside one groove ring; a stage play keeps its
script page and adds 1-4 voice-band rules. A real picture always wins over the label, the two are
never shown for the same object side by side, and ranking never looks at pictures. Networks and
sponsors appear as names in our type, never as logos. User-made ear dramas get the drawn label
only, never an uploaded picture. Home follows all eight rules of R3a §4.1: On the air is the one
lead object (tier L, the evening's year ticked on the dial) with the genre stations as a row of
small labels under it; the doors become two quiet ghost buttons (Find a show, Record a play);
every rail uses one window size and one art system; a show appears at most once per Home, and no
rail opens on the show of the rail above; two inks per screen (the day board's bars in onBoard,
or moved to Browse; Today's scene a wide card at the grammar's size, not a full-width slab);
rhythm L, S, M, L, M, S, never two large objects adjacent; framing from data only. The data
plane publishes the label's one new input, `series.network` (one normalized primary network with
its source, `catalog/tools/networks.py primary_network`); clients never parse `networks`.

**Why**: the owner, 2026-11-19 (ROUND3-LOOP.md): *"We need to continue making the app more
visually appealing, both from the home screen perspective (which still reads like a long list of
items that feel unrelated) and the individual item perspective. We have very few images that
represent only a few Ear Dramas ... We also can design default (or programatically generated)
designs that could take the place of images that don't exist (or don't yet exist, anyway). The
goal is to have the home view feel more cohesive and inviting from the moment that you open the
app."* Rulings the same day: label art C on every platform; Home all of R3a §4.1; network and
sponsor names in type, never logos (trademarks, R3a §1.4); user ear dramas the drawn label only.
R3a measured why: 81% of shows (1,059 of 1,311) have no picture and today's default art carries
one fact (the initials), so a wall of shows reads as one repeated placeholder, and Home showed
five visual vocabularies with the loudest one not the lead. Every product that sounds cohesive
bought it with one system, not more pictures (Penguin, Blue Note, NYPL's generated covers). Of
the three options, only the label gives each episode its own image (lock screen, Continue) and
marks user-made work as different without words or red, and every mark on it is a fact the
catalog holds, so the art teaches era, length of run and network at a glance. Option A (a title
card) carries words the tile already shows; option B (a hash-seeded motif) is chance dressed as
meaning.

**How to apply**: binding design docs first (WEB-DESIGN §4.2 and §6, iOS-, macOS-, tvOS- and
ANDROID-DESIGN Home and art sections, the `artwork-presentation-design` skill's default-art
section), then Round 3 V1-V8 in order: the pipeline's `series.network` and wider identity (V1),
`art.label` tokens in `design-tokens.json` and a pure `labelSpec` with the same goldens on web,
Swift and Kotlin (`cross-platform-determinism`; drawing stays native: SVG, SwiftUI `Canvas`,
Compose `Canvas`), then Home, then Detail. The label is computed from published fields only; no
hash, no client-side network parsing, no invented dates. tvOS keeps its own idiom: focus does the
work and the hero fills the ten-foot art area; the label never takes focus chrome a picture would
not. The Home de-duplication is deterministic from the published shelves and their order, the
same on every platform, and named in the catalog contract. PARITY rows: label art, Home
composition, series hero and gallery, play title page.

**Who was in the room, who gains, who pays**: the owner chose from R3a's three options and
eight rules; listeners gain a Home and pages where every show says something true about itself,
and the 81% of shows without a picture stop looking like placeholders; makers' finished ear
dramas get their own mark. The cost is a drawn system kept identical on three stacks (goldens on
each), one more pipeline field, and a skeuomorphic object whose arc stays blank on the half of
shows that are undated until the date work fills them.

## 082: Reading together: read rooms, classes that own productions, takes that pass through (owner 2026-11-19)

*Date: 2026-11-19*

**Rule**: a group reads a play together in a **read room**: one shared cursor (a
line id and a generation) that a person moves, on every device in the room, in
four modes (Table read, Rehearse, Record in the room, Relay across time;
PLAYS-DESIGN §12). Its rules live in the pure `worker/src/read-protocol.js`;
each room is carried by its own **Durable Object over WebSockets**, with D1
polling as the fallback for a client or a Worker without a socket, both with
the same messages. A **class owns a production**, seen only by its seats; the
parts its teacher assigns may record at once (elsewhere the one-part relay,
C7, stays); a **seat** (a name the teacher typed) reads and records without an
account, its takes belonging to the teacher's account. **Takes pass through**:
each device records its own lines, and a take travels through the Worker to the
leader's device during the session and is deleted the moment it arrives;
nothing is kept at rest on Cloudflare (no R2, no audio in a Durable Object, KV,
or D1). The finished recording goes to **archive.org**, uploaded by the
teacher under their own name through the existing uploader (Decision 073),
for classes marked 13 and over only, with the CC0 consent; an under-13 class's
work is never published, and the teacher exports a file. One cross-platform
read room, Apple included; no SharePlay.

**Why**: the owner set the scope on 2026-11-19 (ROUND3-LOOP.md part 2): *"We need
to build out how a teacher actually would manage that process. We also need to
build out how someone would do this with a bunch of different devices in the
same room (whether a classroom of kids or a group of adults doing a table
read)."* Then the rulings: *"We are using archive.org for storage, not
cloudflare. We already decided that teachers could upload the full recording
under their name."* The classes bundle (rulings 3 to 5) was adopted as R3c
recommended, except its storage. Decision 065 chose D1 polling for Listen
Together "because Durable Objects are not on the free plan"; Cloudflare's
pricing page now puts SQLite-backed Durable Objects on the free plan (R3c §1.3,
fetched 2026-11-19), so that reason no longer holds **for read rooms**. The
reasons to move them are measured: a reader's own line should light before
they need it (one round trip on a socket against half a poll interval plus a
round trip); 30 devices polling at 1 s behind one school address is the load
Listen Together's per-address limits were set to refuse; and polled presence
writes would spend the Worker's whole free D1 allowance at about 25 class
periods a day, where an object keeps presence in memory. Listen Together stays
on D1 until it has a reason of its own to move. Decision 066's R2 take store is
not the path: it needed a payment method on file and kept every child's voice
on Cloudflare, and the owner's ruling puts storage on archive.org.

**How to apply**:
- **The transport gate (T4)**: the socket must show a cursor delay under 300 ms
  at the 95th percentile on the real bench (each device logs when it drew the
  lit line, corrected by the protocol's `clockOffset`; 100 presses; polling's
  numbers recorded beside it). Until T4 passes, polling is not removed and the
  socket is not called done.
- **The protocol** imports nothing (a test fails if it gains an import,
  `fetch`, `WebSocket`, `env.`, `Date.now`, or `crypto.`). The web, Swift and
  Kotlin ports are held to `worker/test/read-golden.json`, written by
  `node worker/tools/read-golden.mjs` from the protocol itself, one file for
  every stack. Codes, member keys, the clock and presence are Listen
  Together's, copied with their constants (a test holds the two equal).
- **Rules carried in the protocol**: only the leader moves the cursor; a move
  carries the cursor generation it was made from, a repeat is a no-op, an old
  generation is `stale`; in Record only the device holding the line ends it,
  and the cursor skips lines nobody holds; an adult room's first claim of a
  part wins; a class's parts come only from its assignments, which may split a
  part by scene; a class room holds still for its leader (the teacher or the
  seat they chose) and never passes the lead to a random student, while an
  adult room hands it after 2 minutes to the reader present longest; a screen
  never leads or holds a part; 40 members at most ("This reading is full").
- **Limits by member or seat, never only by address**: read routes have their
  own address floor (`READ_IP_LIMITER`, 3,000 a minute, in place of the
  Worker-wide 600), a per-address join floor of 60 a minute against code
  guessing, and 120 messages a minute per member key.
- **Pass-through takes (T2)**: a take is refused when no leader's device is
  present to receive it; it waits on the recording device (written there
  first, as every take is) and sends when both are present. The Worker holds
  it only in flight. No route, table or binding stores take audio.
- **Publishing**: the teacher's Publish uploads the full recording under their
  own name via `plays-archive.js` (073), 13-and-over classes only, after each
  performer's CC0 consent at the current version; an under-13 class has Export
  and no Publish (Decision 059's school route stays blocked until P5).
- **TVs record nothing**: Apple TV and Google TV join as the shared screen with
  a pairing code (tvOS-DESIGN §4.13, ANDROID-DESIGN's TV panel rule).
- Out of scope (SCRATCHPAD): a speech-following cursor, reading-level labels or
  casting by ability, leaderboards and fluency scores, every phone speaking
  stand-ins in sync, the exquisite-corpse relay.

**Who was in the room, who gains, who pays:** the owner ruled on storage,
classes, seats and the transport's purpose; R3c's research and the agent chose
the Durable Object, the limits and the protocol's rules. Students gain a part
in a whole-class recording with no account and no email; teachers gain the
casting and the room, and pay the upload under their own name. Under-13 voices
never reach a public archive. The cost is a second transport to keep honest
(polling beside sockets) and recordings that exist only on the leader's device
until the teacher uploads or exports them.

**Addendum 2026-11-19 (T4, owner-rule decisions by the main thread)**: (a) the leader's name travels in the read snapshot (`leader_name`: a seat's label, or the owner's `owner_name`), so readers see "Waiting for <name>"; (b) "Read open parts" is a leader message (`read-open`, snapshot `read_open`) the screen obeys, not a local switch; (c) a seat key lasts for the session or app run only on a shared device: the web keeps it per tab, Apple and Android keep it in memory, never in the keychain or on disk.
**Why:** a class device is shared by students; a key at rest would let the next student read as the last. **How to apply:** `read-protocol.js` + `read-golden.json` carry (a) and (b); `ReadSeatKeys` (Swift and Kotlin) is the only holder of seat keys on a device.

## 083: Relay across time, and credit the maker (owner 2026-11-19, T6)

**Decision.** A seat or member records their assigned lines at home; each take stays on that device until the teacher's
(director's) app is open, then passes through the Worker and is deleted on arrival (Decision 082; nothing waits on
Cloudflare). The sender asks `GET .../receiver` first, backs off 5, 10, 20, 40, then 60 s, and shows one state per take. In
an adult room an anonymous reader's take is credited to the name they gave on joining, never to the leader, and a
production with a line by a maker who has not consented cannot publish: Publish lists who must.

**Why.** "Please research ways of doing 'table reads' or other methods for reading through plays together (either
synchronously in the same room or across space and time)." The leader's name on a stranger's take made the leader the
performer, and the leader's own CC0 consent then stood in for someone else's. A relay that keeps takes on the Worker
would break the archive.org-only storage ruling; one that drops them when the teacher is away would lose a student's
work.

**How to apply.** The rules are `docs/PLAYS-DESIGN.md` §12.11; the Worker's are `docs/WORKER.md` ("Credit and
consent"). A seat key kept so waiting takes can be sent later lives in the Keychain or Keystore (web: the device's own
store), put there only when a student records at home, never on joining a room; Decision c (memory only) still holds
for the room. New client states or words for a take are changed in §12.11 first.


## 084: Student privacy: who recorded what is deleted on a schedule, the ear drama is kept, and the school decides (owner 2026-11-21)

*Date: 2026-11-21*

**Rule**: a class's identifying data is deleted on a schedule, and the recorded ear drama is kept. **Deleted**: seats and the names the teacher typed, the links from a take to its seat, review marks and notes, casting, class membership, the school's authorization record, and every production of the class that was never submitted. **Kept**: a submitted production (it has an archive job), its takes' fields without their seats, its job and its archive.org files, and its credits, which carry only the teacher's chosen name (Decision 082). Deletion happens when the teacher presses **Delete class**; the day after the class's **end date** (by default the July 31 that closes the school year it was made in; the teacher changes or extends it, up to 400 days ahead); after **12 months idle**, once a 30-day notice shown in the teacher's class list has run; and when a **school asks**, through the owner's operator route, within 30 days. An account **idle 3 years** is deleted as if its owner had (Decision 035), 30 days after a notice that any sign-in cancels. A director's **Delete production** removes a production that was never submitted; a submitted one stays (its lines are removed one by one, P12). For an **under-13 class**, the school or district decides (FTC COPPA FAQ N.3): the teacher records which authorization (`reference`, now required). For a **13-and-over class**, Publish needs the teacher's two confirmations, that every performer agreed and that the school holds a media release for each performer under 18, besides the teacher's own CC0 consent; this replaces §12.11's "the teacher consents" and makes Decision 082's "each performer's CC0 consent" hold for a class. A **neutral age question** (birth year, no default) comes before a person's first invite, joining by invite, or publish outside a class; only "under 13 or not" is kept, on the device, and an under-13 answer keeps sharing off on that device. The privacy contact is Learning is Change, ben@learningischange.com.

**Why**: the owner, 2026-11-21: *"We want this to work for the vast majority of school districts, schools, teachers and students. The only way to do this is to build upon the work of the teachers and other advocacy groups that have already shown how to allow schools to create such great works of art (ear dramas) without compromising student privacy."* Then, on retention: *"I don't mind deleting the info about who recorded what, but we need to be able to keep the recorded Ear Dramas in our database. That should work, given that identifiable information is not accessible via the recordings."* R3d (`docs/research/design/R3d-student-privacy.md`) found the architecture already met most school rules and three controls missing: a teacher could not delete a class or a production, could not export a class, and nothing ever expired one, while the amended COPPA Rule (in force April 22, 2026) requires a written retention policy that never keeps data indefinitely, and every district agreement (SDPC NDPA Exhibit D, California AB 1584, Colorado, Florida, Ohio) asks for deletion at the end and on request. Seesaw, Book Creator and Canva set the precedent of a published schedule, 12 months idle, and a school's request answered within weeks. The FTC's FAQ N.3 says the school or district, not one teacher, should authorize an under-13 collection, so the teacher names the authorization. A teacher cannot dedicate a 13-to-17-year-old's performance to the public domain alone, and districts ask for a media release before student work is posted; the owner ruled both confirmations. The age question is the amended rule's neutral screen for a general service with a part meant for children.

**How to apply**:
- **The sweep never deletes a submitted production.** `deleteClass` (`worker/src/plays-retention.js`) detaches a submitted production first (seat links, notes and casting go; `class_id` is cleared), then deletes the rest; account deletion already did the same (`playsBeforeDeletion`). Every rule has a test in `worker/test/retention.test.js` and a break (`084:`) in `test/mutations.mjs`.
- **The end date is a date, not a time**: `ends_on` is the class's last day; the class may go from noon UTC the next day, after that day has ended in every US time zone. Idle counts the teacher opening the class, its productions' activity, and its seats being claimed; the teacher's list shows `deletes_on` during a notice.
- **No notice by email**: we hold none. The class notice is in the teacher's list; the account notice can only be the published policy, and any sign-in cancels it.
- **A school's request** is `GET /v1/operator/classes?code=` or `?reference=`, then `DELETE /v1/operator/classes/:id`, dispatched through `.github/workflows/operator.yml` with no stored key (Decision 085; `docs/WORKER.md` "A school asks"); the owner confirms in writing within 30 days.
- **The class export** is the teacher's file (`GET /classes/:id/export`): labels, casting, progress, takes' fields with review states and notes; no audio, since none is stored.
- **Words** are the owner's, approved 2026-11-21 ("The policy wording looks good to me."): the privacy page, the schools page, and in the apps only the controls' own labels and refusals.
- Not built, and so not promised: shared-device clearing of a student's takes (R3d D5, the owner's Q6), seat-key expiry at home (D6), report notes fading (D7), and keeping the school's authorization record a year after its class (deleted with the class instead).

**Who was in the room, who gains, who pays:** the owner ruled on retention, the signing entity, the 13+ confirmations and the age question; R3d's research and the agent set the mechanisms. Schools and families gain a schedule they can read and a deletion they can ask for; teachers gain Delete, Extend and Export, and carry two confirmations before a class publishes. Students lose nothing they made: the published work stays, without their names. The owner pays in promises that bind every future feature, and in running a school's request by hand.

## 085: The owner's routes take a GitHub OIDC token, not a stored one (owner 2026-11-22)

**Rule**: `/v1/operator/*` and the take-down case routes accept only a GitHub Actions OIDC token, verified against GitHub's published keys, with `aud` equal to the Worker's origin and `repository`, `repository_id`, `ref` (`refs/heads/main`), `job_workflow_ref` (one named workflow file) and `event_name` pinned as constants in `worker/src/github-oidc.js`. There is no `OPERATOR_TOKEN` or `TAKEDOWN_TOKEN` in code. Any other secret value moves only through `tools/secrets.sh`'s fixed recipes, and `tools/test_no_secrets.py` (pre-commit and `secrets-check.yml`) fails on anything shaped like a secret in git.

**Why**: the owner, 2026-11-22: *"I do not want to set or keep track of keys and passwords for this repo."* A stored operator key would have had to be minted, kept and typed by someone; the classifier refused an agent minting one, rightly. A token GitHub signs for one run of one workflow on main needs no keeping, expires in minutes, is never given to a fork's pull request, and leaves `actor` and `run_id` for the audit trail. The pins are constants rather than `[vars]` so no environment can loosen them; the only test seam is the bench's `LOCAL_TEST_JWKS`, which a Worker refuses to carry on a public host. Research: `docs/research/SECRETS-PLAN.md`.

**How to apply**:
- A new owner route names its workflow and events in `OWNER_WORKFLOWS`, gets a refused-claims test in `worker/test/github-oidc.test.js` and an `oidc:` mutant per check; never a new shared token.
- The workflow needs `permissions: id-token: write` and asks for the token with the Worker's origin as its audience; its log is public, so it prints ids, dates and counts only.
- Renaming a pinned workflow file, the repository or the default branch locks the routes until the constant changes with it.
- The owner's own take-down commands (`open`, `list`, `show`, `decide`) read the private record in D1 through their own wrangler login (in the Keychain), never through a token.

## 086: Voice defaults live in Settings; Kokoro leads them where it can run; a play's cast only overrides (owner 2026-11-22)

**Rule**: a part nobody cast reads its **Default**: auto-cast (PLAYS-DESIGN §2.8 rule 4) over the device's voice defaults, worked out at each read and never written into the cast. The defaults live in **Settings > Voices** on every platform (§2.8 rule 11): the Kokoro download, a default speed, and an order of voices, downloaded (Kokoro, best grade first) before the device's own (best quality first), each tickable and movable. Kokoro is on by default wherever its gate passes (web: a WebGPU adapter and the self-test after download, Decision 078; Android: the q8 module, on in release; Apple: S6e once measured on an iPhone), and its grades under C- start unticked. The device's own voices are ordered best quality first. A play's cast sheet only overrides a part ("Default" is its first choice), and Recast all returns every part to its Default. The cast keeps only the person's choices (web rows carry `v: 2`; rows from before this, which wrote auto-cast in as if chosen, are read as no choice). On the web the Kokoro engine loads only when the person downloads or a finished download is here; `?kokoro=1` is gone as a gate, `?kokoro=0` stays as a kill switch. A synthetic voice is still a live stand-in, never stored (Decision 076).

**Why**: the owner, 2026-11-22: *"I thought we started allowing for multiple different voices to be downloaded/used with the recordings. It seems like everything is still using super robotic voices that no realistic person would want to use to listen to a play (or having other characters reading the lines as you record your own). Can we make it easier to use the high-fidelity voices and how to implement them as a default from the settings tab vs from the individual play that you are casting?"* Three things kept people on the robotic voices: on the web Kokoro sat behind `?kokoro=1`, which nobody types; §2.8 rule 10 said a download recasts nothing, so even a person who downloaded heard the old voices until they recast every play; and the cast wrote auto-cast into storage the first time it was read, so every play ever opened stayed pinned to the voices of that day. A default is a device-wide preference, so it belongs in Settings, set once; a play's cast is where a person makes a casting decision for that play. Keeping the defaults out of each cast is what makes a change in Settings reach every untouched part.

**How to apply**:
- Never write a Default into a cast; store only what the person picked. A test reads the stored cast after a first read and must find nothing (`js/voice-cast.test.js` "a Default is worked out at each read").
- A new voice engine joins the Default pool by `VoiceCast.ordered`'s engine rank, never by being written into casts.
- The person, not the app, decides what a Default sounds like: the order and ticks are theirs; the app only seeds them (Kokoro's grades, the platform's tier). No voice is chosen by a part's name or the script (rule 4).
- The Apple and Android ports follow `docs/research/design/VOICES-PORT-BRIEF.md`; their casts drop stored auto entries the same way.

**Who was in the room, who gains, who pays:** the owner asked; people listening to or rehearsing a play gain voices worth hearing without hunting a flag or recasting each play; the cost is the download (340 MB on the web, more than three times the apps') and the casts a person made on the web before this, whose auto-cast entries are dropped (their explicit choices could not be told apart from auto-cast, so a part chosen by hand before 2026-11-22 returns to its Default once).
