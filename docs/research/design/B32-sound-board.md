# B32: The sound board (design, 2026-11-26)

Design phase of BACKLOG-LOOP B32. Research: `B32-sound-board-research.md`. Frames: `b32-frames/` (made by
`b32-proto/shoot.mjs` from `b32-proto/mock.html`; every word of a play on them comes from the real library through
`b32-proto/make_data.py`: Caesar Rodney's Ride by Henry Fisk Carlton, a radio play, Gutenberg 28051, lines L0172 to
L0191, and Toinette and the Elves by Elsie Hobart Carter, Gutenberg 58546). No product code changed.

The owner, 2026-11-26: *"I'd like to add the ability to record both stage direction (as a character) and foley sounds
within a well-designed foley (or sound effects, depending on the need of the play) soundboard/interface that would
allow someone to add sounds in the backgrounds of a recording. You should be able to duck the sound effects and foley
work under the voices and/or add your own custom sounds. Ideally, I'd like to be able to background music and use
public domain audio clips and music for all of it."*

Already decided (BACKLOG-LOOP B32, round 3): sounds are placed on lines first, live trigger pads later; own sounds stay
private and are never published; sources are Kenney and OpenGameArt CC0 and public-domain-marked music only, until the
owner rules on the USC libraries; Android needs a mix renderer first (corrected in 1.1: it has one; it needs a cue
decoder).

**Learning orientation (the four questions).**
*Deepens understanding*: the board is the radio sound man's job made visible. The script's own cue marks become slots;
placing a sound before, under or after a line, and hearing the music drop when a voice comes in, teaches what sound does
for a scene (a door that opens before the line, rain that sits under a whole stretch, a sting after it). The settings
use the craft's words (before, under, after, bed, fade, under voices) rather than hiding them.
*Invites participation*: every sound in a production is a person's choice. A slot opens empty with the script's words
above it; the search field holds a word taken from those words, visible and editable, which is search, never
authorship. Nothing is filled in, placed, or levelled by guessing.
*Agency*: performing the sound is first-equal with choosing one. The round record control stays in the dock: knock on
the table for the door (PLAYS-DESIGN §2 step 2, the radio tradition) and the knock is a take of the Sound part. Your own
sounds sit beside the library.
*Clarity*: placement is relative to lines, the same grammar the studio already uses (§4.2: "placement is relative, so
a re-take ... ripples"). There is no free multitrack timeline to learn, and the duck is a computed rule the person can
read in one line ("Under voices −6 dB"), never a detector that guesses.

*What it refuses*: a DAW timeline (a phone-hostile second app inside the first), auto-filling cues from their words, a
"smart mix", and any sound without license evidence. *Who it touches*: the person holding the Sound part (often the
director doubling it), a class where a teacher gives a student Sound (a classic first job for a shy reader), listeners
of the finished ear drama. *What people might stop learning*: performing foley; hence record stays the round control.

**Look at these frames first:** `board-375-light.png` (the board as a sheet over the page), `page-375-dark.png` (the
Sound part's page: cue slots, chosen sounds, the bed's rule in the margin), `mac-1440-dark.png` (a bed under lines 180 to
191 in the wide panel), `mix-1440-light.png` (how the duck is computed), `cast-375-light.png` and
`directions-375-light.png` (directions and sound as parts), then `ios-390-dark.png`, `android-412-light.png`,
`ipad-1180-light.png`, `states-375-light.png`.

---

## 1. What the repo and the library say (measured)

### 1.1 Corrections to the research

1. **Android already has a mix renderer.** `android/.../plays/MixTimeline.kt` holds `MixTimeline.build` and
   `MixRenderer.render` (a chunked float mixer, 4,096 frames a chunk), `MixEncoder.kt` holds `AacMixSink`
   (MediaCodec AAC-LC 96 kbps into MediaMuxer), and `PlayFiles.renderMix` writes `mix.m4a` (commits 10706fa6,
   d665fb80, 39e486aa, 2026-10-23/24; PLAYS-DESIGN §4.5). What Android lacks is a **decoder for compressed cue files**
   (takes are WAV it reads itself) and the envelope. The batch below is sized for that, not for a renderer.
2. **The Sound part does not exist for most scripts that have cues.** `castParts` lists `sound` only when a line's
   `kind` is `sound`. Caesar Rodney's Ride has 34 cue pieces, every one inside a speech (`{"sound": "sound of gavel"}`),
   and 0 sound lines, so its cast sheet has no Sound row today and the reader's sound lane has no owner.
3. **The parser's `sound` key is not always a sound.** In radio scripts it is (Caesar Rodney: 34 of 34 are sounds). In
   stage plays it also catches business: Toinette and the Elves' 12 "cues" include "All bow low and go to door." and
   "Goes to door as if to call." beside a real "Tap at the door." The design must let a person leave a slot silent
   without it counting against them, and must never auto-fill from the key.

### 1.2 The library (`b32-proto/` counting over `catalog/out/plays-library`, 1,194 scripts, 811,389 lines)

| Measure | Count |
|---|---|
| Scripts with at least one cue row (the reader's rule: a `sound` piece or line, or an aside starting "sound of", "noise of", "music") | 472 (40%) |
| Cue rows in all | 3,769 |
| Scripts with 5 or more stage directions | 1,084 (91%); median 44 directions a script |
| Sound words inside ordinary directions (not cue rows) | bell(s) 853, knock/knocks/knocking 828, music 871, telephone/phone 377, clock 355, trumpet(s) 335, thunder 225, whistle(s) 235, drum(s) 234, applause 109, storm 109, shot 99, crash 81, gong 79 |

So most sound moments in stage plays are inside directions ("A knock at the door.", "Thunder"), not in cue rows. The
board therefore offers a slot on **any line** (Add a sound here), with the cue rows as the slots it suggests.

---

## 2. Stage directions as a part read by a person

PLAYS-DESIGN already has the part (`directions`, "Stage directions", §2 step 2: "a person can read the directions aloud";
§2.8 rule 7: Not read by default, a voice like any part). B32 makes it something a person would choose. Binding words for
PLAYS-DESIGN §2.8 rule 7a (new) and §2.9 rule 3b (new):

1. **The cast sheet lists Stage directions after the speaking parts with its line count and its voice chip**, "Not read"
   until a voice or a person is given (`cast-375-light.png`). Its title stays "Stage directions", the script's own
   term; it is never renamed Narrator, because many scripts have a NARRATOR or ANNOUNCER part of their own (Caesar
   Rodney's ANNOUNCER).
2. **Take part works as for any part.** The studio opens on the first direction with no take; each direction line carries
   the take ring (§2.9 rule 3), recorded in the three modes, with the bleed check and room tone as for speech
   (`directions-375-light.png`: "TIME: Christmas Eve." recorded, the scene direction current with two takes, the next
   one an empty ring).
3. **A direction with no take is silent and never blocks the play.** Only speaking lines decide completeness
   (`missingSpeech`, unchanged). The person reads the directions that serve the listener ("SCENE: The kitchen of a
   peasant cottage ...") and leaves "Exit door L." unread. The part's progress reads "6 of 22 recorded · the rest silent";
   **Done with this part** is enabled from the first take.
4. **Asides inside speeches stay with the speaker** ("(absently)", "(giving in)"): the actor performs them; they are
   never the Directions part's lines (`linePart`, unchanged).
5. **A stand-in may read the part live** (§2.8 rule 7, unchanged): never stored, never mixed.
6. **In the mix**, a recorded direction is a voice placement like a speech: it takes the gap rule, it ducks sound, its
   gain targets −16 LUFS.

## 3. The board

### 3.1 The Sound part (binding words for PLAYS-DESIGN §2.2 and a new §2.12)

1. **Every script has a Sound part.** `castParts` always ends with Sound, then Stage directions when there are any.
   Its title is **Sound** (it holds music as well as effects; "Sound effects" was the phase 1 title). Its row says
   "N cues" (the cue rows, by the reader's rule) and, once taken, "9 of 12 cues · 2 beds". A script with no cue rows
   says "Add sounds".
2. **Taking Sound opens the studio as the Sound part.** The reader with I'm playing set to Sound: each cue row is a
   **slot** with the take ring beside it (empty, or filled with the number of sounds in it); the current slot is
   outlined in ink; chosen sounds are listed under the cue in L5 with their placement ("Thunder, close · After"); a bed
   draws a 3 px rule in the left margin from its first line to its last, across pages (`page-375-*.png`).
3. **Any line can take a sound.** A long press (context menu on a Mac, right click on the web) on any line offers **Add a
   sound here**, which makes it a slot at that line's end; an added slot with nothing in it is removed when the person
   leaves it.
4. **A slot is never filled for the person.** It opens empty. **Leave silent** on a slot marks it done (the parser's
   business-as-cue rows, 1.1 item 3). The part never blocks completeness: a play with every speaking line taken can be
   mixed whatever its sound state.
5. **The dock** (§2.9 rule 6) for Sound: no mode control (sound records line by line); the status line "Cue 13 of 34 ·
   Thunder, close · After"; the transport is **Sounds** (opens the board), Previous slot, the round record control,
   Next slot, Listen from here. Keys: `J` / `K` next and previous slot, Space records, `S` opens the board, `L` hears the
   slot in place.
6. **Recording a sound is a take of the Sound part**, on the slot (the radio tradition: knock on the table). It follows
   every take rule: headphones, room tone, the bleed check, kept, chosen, deletable when unchosen. (Whether a performed
   sound may be published with the play is owner question 1.)

### 3.2 The board itself (binding words; `board-375-*.png`, `ios-390-*`, `android-412-*`, `ipad-1180-light`, `mac-1440-dark`)

On a phone the board is a sheet over the page (web `<dialog>` as the reader's sheet; iOS `.sheet` with
`.presentationDetents([.medium, .large])`; Android `ModalBottomSheet`); from 860 of reader width it is the studio panel
(§2.9 rule 7). Top to bottom:

1. **The slot**: "Cue 13 of 34 · Uriah" (L5 caps) and the cue's own words as the reader draws them (the sound-lane
   block). Done.
2. **In this cue**: each chosen sound as a row (play, its title, its length and placement, Remove), then for the selected
   one: the placement control (segmented: **Before · Under · After · Bed**), **Start** (−/+ in 0.1 s, the offset from the
   anchor), **Level and fades** (a disclosure: level −12 to +6 dB, fade in and out 0 / 0.2 / 0.5 / 1 / 2 s, length:
   whole, or loop to the end of the line for Under, and Under voices: the lane's default or this cue's own, including
   Off), and **Hear it in place** (plays from the line before the slot to the line after, mixed as it will be).
   A **Bed** shows **Until** (the last line it sits under: picked by tapping a line on the page, the sheet dropping to
   its medium detent; on wide, the page is beside it) and fades in 1.5 s and out 2 s by default.
3. **Search** (`<input type="search">`, `.searchable`, M3 `SearchBar`): it opens holding the first word of the cue's
   text that is a tag in the pack (thunder, knock, rain, door, bell, hooves, gavel); otherwise empty. It searches
   titles and tags.
4. **One row of categories** (single select, the pack's own): Doors, Steps, Bells, Weather, Rooms, Travel, Animals,
   Objects, Water and fire, Weapons, Music, Mine. One filter row, never two (mobile-first-density rule).
5. **Results**: 56 px rows (iOS a grouped list, Android a 72 dp list item): play / stop (audition, the raw file, at
   the cue's level), title, then "0:06 · OpenGameArt · CC0" (length; "loop" for a loopable file; source; license), then
   **Add** (In cue when added). A category not downloaded heads its rows with its size and Download ("Weather · 1.3
   MB"); its rows are dimmed until it is here. A tap on a row's title opens its record: source page, license and the
   evidence link, the date checked.
6. **Mine** lists the person's own sounds, then **Record a sound** (the record outline; up to 30 s; no cue plays, so no
   headphones gate) and **Bring a file** (the platform file picker; audio up to 10 minutes and 50 MB, decoded and
   stored as the platform's take format). Own sounds are on this device only (3.4).

Audition plays through the session's output only while nothing records; a press of record stops it.

### 3.3 Placement (binding; the same math on every stack, 4.1)

| Placement | Starts | Moves later lines? | Duck |
|---|---|---|---|
| **Before** | in the gap before the anchor line, ending `gap` before the line starts, plus Start | Yes: the line waits for the cue (its length after trimming) | Yes, under any other voice it meets |
| **Under** | at the anchor line's start plus Start; a cue inside a speech (a piece after said words) defaults Start to the share of the line's said words before it, times the take's length, shown as a number the person changes | No | Yes |
| **After** | after the anchor line ends, at the gap, plus Start | Yes: the next line waits for it | Yes |
| **Bed** | at the slot's point (line start, or after it if the cue piece follows the words), loops until the end of the Until line plus its fade-out | No | Yes, by the music lane's depth |

A line's sounds play in the order chosen. A Start below zero (up to −2 s) overlaps the previous line for Before and
After, which is how a door slams on a last word.

### 3.4 Your own sounds (binding; owner decision, round 3)

1. Own sounds are kept on the device that made or imported them (`Sounds/mine/` beside `Plays/`), never synced, never
   uploaded, never published. A production stores the own sound's id.
2. Another device of the same production shows the slot's sound as "On another device" and plays nothing for it;
   export there refuses with the names and offers **Export without them** (`states-375-light.png`). Nothing is dropped
   silently.
3. **Publish** says, as a warning before the consent: "Your own sounds stay on this device. The published play leaves
   them out." The published files carry library cues and takes only.
4. Export my data includes `Sounds/mine/` (they are the person's own data), with each file's name and date.
5. A class: an under-13 student may record or bring own sounds; they stay on that device like everything else there.

### 3.5 What is not in this batch

Live trigger pads during a take (decided: later). Stereo and pan (the mix stays mono, §4.4). A sound inside a word
(Start is per line, to 0.1 s). Pitch or speed changes. Effects processing (reverb, telephone filter): a later idea, noted
in SCRATCHPAD out of scope when the build lands.

## 4. The mix

### 4.1 The timeline gains two lanes (PLAYS-DESIGN §4.2, contract in 5.1)

`buildTimeline` keeps every voice placement exactly as now when a production has no sound (so the voice-only golden
stays byte-identical) and, when it has, inserts the Before and After lengths into the gaps and adds `effects` and `music`
placements: `{ cueID | ownID | takeID, lane, start, inFrame, outFrame, loop, gain, fadeIn, fadeOut, duck }`, frames at
48 kHz. One function per language, proven by `catalog/tests/golden/mix_sound.json` on web, Apple and Android
(`cross-platform-determinism`).

### 4.2 The duck is computed from the timeline (binding; `mix-1440-light.png`)

1. **Voice activity** is the set of intervals where a voice placement (a speech or a direction take) sounds. Intervals
   closer than 1.0 s merge, so a bed does not pump between lines and rises only in a real pause.
2. Each sound placement's gain is its level times the duck envelope: full outside voice activity; its lane's depth
   inside; ramping down linearly in dB over the **attack**, starting 120 ms before a voice interval (look-ahead is free:
   the take's start is known), and back up over the **release**, 600 ms after it ends.
3. **Depths**: effects −6 dB, music and beds −12 dB; a cue's own Under voices overrides its lane (Off for a gunshot that
   must cut through). Defaults are UNVERIFIED: to set on a listening pass with three plays on headphones and a phone
   speaker before W ships.
4. Fades multiply the envelope. Breakpoints are computed in Core as `[(frame, gainDb)]` and are part of the golden.
5. Never detected from the audio: a computed duck is the same on every device and in every export.

### 4.3 Loudness

Takes keep their stored gain to −16 LUFS (§4.4). Each pack file carries its integrated loudness and sample peak, measured
at ingest (BS.1770, the same meter as takes); effects play at −19 LUFS before the duck and beds at −20 LUFS (so a ducked
bed sits near −32 LUFS, 16 dB under the voices). Own sounds are measured on save the same way. When a production has
sound, the render runs twice: the first pass measures the sum's sample peak, the second writes with one scalar so the
peak is at or below −1 dBFS (no limiter, deterministic); a production without sound keeps the one pass.

### 4.4 Listen through, Hear it in place, export, publish

- **A complete play** (every speaking line taken): Listen Through plays the rendered mix with sound (Apple and Android
  already play `mix.m4a`; the web its WAV); export is the same file.
- **A partial play** (listen any time, Decision 067): the listen plan plays takes and live stand-ins; sounds play at their
  anchors with the duck driven live by each entry's start and end (a take's length is known; a stand-in's end is its
  speech event). Close, not sample-exact; the export is the computed mix.
- **Hear it in place**: the listen plan from the line before the slot to the line after.
- **Missing pack files** at render: the render downloads the categories it needs (sizes shown, a confirmation on
  cellular), or refuses naming the cues when offline. Never silently dropped.
- **Publish**: the archive.org item keeps one file per line (Decision 073, `worker/src/plays-archive.js`) and gains
  `sound.json` (the production's `sound` block with own sounds removed, plus each used cue's manifest row: source,
  license, evidence). A player of a published ear drama computes the same timeline and envelope from the takes' lengths
  and fetches cues from the pack item. Batch P.
- **tvOS** plays a published or mixed ear drama with its sound; it has no board (it records nothing, PLAYS-DESIGN §2.9;
  no file import, no touch). tvOS-DESIGN: n/a, listen only.

## 5. Data

### 5.1 The production record (`production.json`, Apple's field for field, web and Android the same)

```json
"sound": {
  "v": 1,
  "lanes": { "effects": { "duckDb": -6 }, "music": { "duckDb": -12 } },
  "slots": [
    { "id": "S7F2...", "line": "L0180", "piece": 1, "added": false, "silent": false,
      "sounds": [
        { "id": "C91A...", "src": { "pack": "eardrama-sounds-1", "cue": "thunder-close" },
          "at": "after", "startMs": 0, "gainDb": 0, "fadeInMs": 0, "fadeOutMs": 0, "loop": false, "duckDb": null },
        { "id": "C91B...", "src": { "pack": "eardrama-sounds-1", "cue": "rain-steady-1" },
          "at": "bed", "until": "L0191", "startMs": 0, "gainDb": 0, "fadeInMs": 1500, "fadeOutMs": 2000, "loop": true, "duckDb": null }
      ] }
  ]
}
```

- `src` is one of `{pack, cue}`, `{own}` (an own sound's id, this device only), `{take}` (a Sound part take).
- `piece` is the index of the cue piece in the line's `parts` (null for a whole line or an added slot).
- Absent `sound` means no sound; old records read unchanged. The record syncs as today (§11): the `sound` block goes with
  the production; own sound files never do.
- Export my data: `takes[]` rows gain `sound` (the block) and `ownSounds[]` (name, created, length, bytes).

### 5.2 The cue pack (CATALOG-CONTRACT §8, an extension file; `catalog/sounds/`)

- **Hosting**: one archive.org item owned by the project's account, `eardrama-sounds-1` (owner 2026-11-19: "We are using
  archive.org for storage, not cloudflare."), its metadata `licenseurl` CC0 for the effects files' dedication carried
  through; music files keep their own PDM row in the manifest. A new version is a new item (`-2`), never an overwrite.
- **Files**: AAC-LC mono 48 kHz in `.m4a` (decodes on Safari, Apple, Android and Chrome without an Opus question), 64 kbps
  for effects and music; silence trimmed to 20 ms; beds cut to loop at zero crossings with a 50 ms crossfade.
  Path `<category>/<cue-id>.m4a`.
- **`sounds.json`** (the manifest, also served from the item):
  `{ "format": 1, "pack": "eardrama-sounds-1", "built": "2026-..", "categories": [{ "id": "weather", "title": "Weather",
  "bytes": 1340211 }], "cues": [{ "id": "thunder-close", "title": "Thunder, close", "category": "weather",
  "tags": ["thunder", "storm"], "kind": "effect|ambience|music", "ms": 6120, "loop": false, "file": "weather/thunder-close.m4a",
  "bytes": 49210, "sha256": "...", "lufs": -18.4, "peak": 0.71, "source": { "name": "OpenGameArt", "page": "https://...",
  "file": "https://...", "maker": "..." }, "license": { "id": "CC0-1.0|PDM-1.0|US-pre-1926", "url": "https://...",
  "evidence": "https://...", "checked": "2026-..-.." } }] }`
- **Download on demand**, by category, size shown before ("Weather · 1.3 MB"); the manifest itself (about 40 KB) is fetched
  when the board first opens. Stored where the person's work is: Apple `Application Support/Sounds/eardrama-sounds-1/`,
  Android `noBackupFilesDir/sounds/` (re-downloadable, not the person's work), web Cache Storage `ed-sounds-1` (the
  service worker's cache-first rule; `navigator.storage.persist()` already asked when a play is cast). Each file is
  checked against its sha256 before use.
- **Offline**: downloaded categories work; the rest show their size and "Offline".
- **The rights gate** (`evidence-gated-catalog-curation`): `catalog/sounds/sources.csv` is hand-picked rows; the builder
  refuses any row whose license id is not in `{CC0-1.0, PDM-1.0, US-pre-1926}`, any row without an evidence URL and a
  checked date, and any source host on the refused list (freesound.org, sonniss.com, bbcrewind, the USC item, any CC-BY
  page); `catalog/tests/test_sound_pack.py` proves it with a planted CC-BY row that must fail (AGENTS.md: a test is not a
  test until seen to fail). A take-down removes a cue by a new pack version and a forwarding row (the old id names its
  replacement or nothing; a production whose cue was removed shows the slot empty with the cue's name, never a different
  sound).

## 6. The starter pack

Picked 2026-11-26 from listings only (no file was heard). OpenGameArt file names were read with `unzip -l` from the
packs' own small zips; **Kenney file names are from memory** (kenney.nl refuses scripted fetches) and K1 verifies them
at download. Every row's license was read on the source page; K1 records the evidence URL and date per file.

**Sources**

| Short | Page (license evidence) | License as stated | Download |
|---|---|---|---|
| OGA-A | https://opengameart.org/content/100-cc0-sfx-2 | CC0 (license field) | `sfx_100_v2.zip`, 2.4 MB, OGG |
| OGA-B | https://opengameart.org/content/100-cc0-sfx | CC0 | `100-CC0-SFX_0.zip`, 2.9 MB, OGG |
| OGA-C | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | CC0 | `sfx_breaking_and_falling.zip`, 1.6 MB |
| OGA single items | rain-loopable, rain-long-thunder, rain-and-thunders, crank-movie-telephone-ringtone, doorbell-ring, ticking-clock, tick-and-tock, typewriter-sounds, basic-sound-effects, park-ambiences (each `https://opengameart.org/content/<slug>`) | CC0 on each page | per item |
| KEN-RPG, KEN-IMP | https://kenney.nl/assets/rpg-audio , https://kenney.nl/assets/impact-sounds | "Creative Commons CC0" on the page | the page's zip |
| MUSOPEN-CHOPIN | https://archive.org/details/musopen-chopin (performer Aaron Dunn) | item `licenseurl` http://creativecommons.org/publicdomain/zero/1.0/ | `https://archive.org/download/musopen-chopin/<name>` |

**Effects: 72 cues** (cue id: source and file)

| Category | n | Cues |
|---|---|---|
| Doors | 12 | door-open: OGA-B door_open; door-close-1..3: OGA-B door_close_01..03; door-creak-1, 2: OGA-B door_01, door_02; door-slam-1, 2: OGA-B slam_01, 02; key-in-lock: OGA-B key_open_01; lock-open: OGA-A sfx100v2_lock_open_01; latch: KEN-RPG metalLatch; door-creak-3: KEN-RPG creak1 |
| Knocks | 6 | knock-wood-1..3: OGA-B wooden_01..03; knock-hit-1, 2: OGA-A wood_hit_01, 02; knock-heavy (the gavel's stand-in): KEN-IMP impactWood_heavy_000 |
| Steps | 10 | steps-wood-1..4: OGA-A footstep_wood_01..04; steps-hard-1, 2: OGA-A footstep_01, 02; steps-wet-1, 2: OGA-A footstep_wet_01, 02; steps-grass, steps-snow: KEN-IMP footstep_grass_000, footstep_snow_000 |
| Bells and phones | 8 | phone-ring-old: crank_ringtone.mp3; doorbell-old: doorbell-old-tring.ogg (see doubts); bell-1..3: OGA-B bell_01..03; gong-1, 2: OGA-B gong_01, 02; bell-small: basic-sound-effects bell1_0 |
| Weather | 8 | thunder-close: OGA-A sfx100v2_thunder_01; rain-long-thunder: rain-thunder.ogg; rain-steady-1..4: rain-loopable 1.ogg..4.ogg (25-45 s loops); wind-field: park_ambience_wind; rain-night: Dark_Rainy_Night(ambience).ogg |
| Rooms and places | 6 | room-loop-1..3: OGA-A loop_ambient_01..03 (to hear); street: OGA-A loop_highway; machine-room: OGA-A loop_machine_01; birds-park: park_ambience_birds |
| Water and glass | 10 | water-loop-1, 2: OGA-A sfx100v2_loop_water_01, 02; river: park_ambience_river; splash-1, 2: OGA-B splash_01, 02; glass-clink-1, 2: OGA-B glass_01, 02; glass-break-1..3: OGA-C bfh1_glass_breaking_01..03 |
| Objects | 10 | clock-tick: ticking_clock.wav; clock-tock: tick.ogg; typewriter-1..3: typewriter1..3.wav; paper-1, 2: OGA-B paper_01, 02; book-flip: KEN-RPG bookFlip1; coins: KEN-RPG handleCoins; dishes: OGA-B dishes_01 |
| Weapons and breaks | 2 | shot-1: OGA-B shot_01; explosion-distant: basic-sound-effects explosion_distant_0 (OGA-C bfh1_wood_breaking_01, 02 are spares) |

**Music: 11 beds and stings** (all MUSOPEN-CHOPIN, CC0, piano; cut at ingest to a 90 s loop or a 4-30 s sting)

| Cue id | Use | File (full length) |
|---|---|---|
| calm-nocturne | calm | Nocturne Op. 15 no. 1 In F major.mp3 (5:05) |
| calm-prelude | calm | Prelude Op. 28 no. 7.mp3 (2:35) |
| suspense-prelude | suspense | Prelude Op. 28 no. 24.mp3 (2:37) |
| mystery-sting | sting | Prelude Op. 28 no. 14.mp3 (0:32) |
| sad-nocturne | sad | Nocturne B. 49 in C sharp minor (3:58) |
| sad-prelude | sad | Prelude Op. 28 no. 15.mp3 (4:55) |
| romance-waltz | romance | Waltz Op. 69 no. 1 in A flat major.mp3 (4:08) |
| waltz | waltz | Waltz Op. 64 no. 1 in D flat major.mp3 (1:47) |
| chase-prelude | chase | Prelude Op. 28 no. 16.mp3 (1:15) |
| chase-tarantelle | chase | TarantelleOp.43.mp3 (3:17) |
| heroic | a bridge | PolonaiseOp.53InAFlatMajorheroic.mp3 (7:18) |

**Size**: effects about 3 MB (72 clips, about 12 of them 25-45 s loops, AAC 64 kbps mono); music about 8 MB (11 cuts of
90 s or less at 64 kbps). **About 11 MB in all**, plus about 40 KB of manifest; the largest category (Music) about
7.9 MB, the smallest under 200 KB.

**Gaps (no CC0 file found)**: horse hooves (the only good set is CC-BY 4.0), fire, animals, crowd murmur and applause
(one applause file's name says CCBY3 though its page says CC0 since 2024-10-05: held), a gavel, cars, trains and wagons,
phone dial and hang-up, purpose-made stings, an orchestra or a band. Caesar Rodney's Ride alone asks for hooves eight
times and a gavel four. Until a source is ruled in, those slots are the Sound part's to **perform** (coconut shells on a
table are the radio original), which the board treats as first-equal; the frames show the hooves slot filled by a
performed take.

**Held, and why**: the Library of Congress National Jukebox marches, waltzes and dance bands (1903-1922; public domain by
statute, but the item pages say they are served "pursuant to permission from the rightsholders" and their file records
carry `rights_restricted: true`, which is not a public-domain mark, so out under the round-3 rule); Musopen items with no
`licenseurl` (most of them); Musopen's CC0 Brahms and Mozart sets and the PD-marked Magic Flute (eligible, but multi-GB
zips; K1 takes single files if the item lists them); the Owlish sound-effects pack (CC0, 142 MB of WAV with footsteps,
phone, kettle, crickets: a K1 candidate if one whole download is acceptable).

**Doubts K1 settles at ingest**: Kenney names from memory; `doorbell-old-tring.ogg` was re-uploaded to OpenGameArt from
Wikimedia Commons (check the Commons license); OGA-A's `loop_ambient_*` contents are unknown until heard; the
OpenGameArt license field is trusted as the uploader states it (the same standard as any CC0 page).

## 7. The four states (`states-375-light.png`)

| State | Board | Export and Listen |
|---|---|---|
| Loading | the manifest: three skeleton rows in the results' shape; a category download: a progress ring in its header | the render's own progress, as now |
| Empty | a search with no match: "No sound called “zeppelin”." and **Record it**; Mine empty: "No sounds of your own yet." with **Record a sound** and **Bring a file** | a play with no sound renders as today |
| Error | "The sounds could not be reached." and **Try again**; a failed category download says so in its header with Try again; a file whose sha256 fails is deleted and downloaded again once, then the error | a cue that cannot be decoded: the render refuses naming it |
| Offline | downloaded categories work; others show their size and "Offline", dimmed | missing cues: "2 sounds are on another device: Owl at night, Gate creak." with **Export without them** / Cancel; pack cues missing offline are named the same way |

No hint banner and no walkthrough: the slot shows the script's words and the board's controls name themselves.

## 8. Per platform (same verbs, native idiom)

| | Web | iPhone, iPad, Mac | Android (phone, tablet, foldable) | Apple TV, Google TV |
|---|---|---|---|---|
| Board | `<dialog>` sheet below 860 px, the studio panel above; `<input type="search">`; categories as the reader's chips | `.sheet` with detents on compact, trailing pane at 860 pt, the Mac inspector; `.searchable` with tokens; `Picker(.segmented)`; SF Symbols `speaker.wave.2`, `music.note`, `waveform` | `ModalBottomSheet`; `SupportingPaneScaffold` pane when expanded; M3 `SearchBar`, `FilterChip`, `SingleChoiceSegmentedButtonRow`; Material `GraphicEq`, `MusicNote`, `VolumeUp` | n/a: listen only (records nothing, no import, no touch) |
| Audition | `AudioBufferSourceNode` on the studio's `AudioContext` | an `AVAudioPlayerNode` on the session's engine | `AudioTrack` (static mode) on the session | |
| Own file import | `<input type="file" accept="audio/*">`, decoded with `decodeAudioData` | `.fileImporter(allowedContentTypes: [.audio])` | `ActivityResultContracts.OpenDocument("audio/*")` | |
| Mix | `renderMix` chunks with `GainNode.gain.linearRampToValueAtTime` from the breakpoints | an arithmetic chunk mixer with `vDSP` ramps feeding the existing AAC writer (the player-node graph cannot hold a sample-exact envelope; the golden decides) | `MixRenderer` gains cue lanes; `CueDecoder` (MediaExtractor + MediaCodec to float) | plays the result |

Binding docs to stamp the same day the build starts: WEB-DESIGN §4.16 item 14 (a "Sound" sub-item), iOS-DESIGN §4.15 "The
studio" (and §4.20 note for the Duo), macOS-DESIGN §4.7, ANDROID-DESIGN §4.17, tvOS-DESIGN (read-along plays sound; no
board), PLAYS-DESIGN §2.2, §2.8 rule 7a, §2.9 rule 3b, new §2.12 (3.1 to 3.4 above), §4.2 (lanes and the duck), §6 (the
two new rows: `Sounds/mine/`, the pack cache), §10 (remove "an effects library" from out of scope).

## 9. Batches for build

**K1 Catalog: the pack.** `catalog/sounds/sources.csv` from section 6 (the Kenney names verified, every file heard), `build_sound_pack.py` (fetch, verify the license
page still states the license, ffmpeg to mono AAC, trim, loop-cut beds, BS.1770 loudness and peak, sha256, `sounds.json`),
`test_sound_pack.py` with the planted CC-BY and missing-evidence controls, a dry run on real files before any upload
(`failures_must_be_real_and_prevented`), then the archive.org item (after owner question 2). Accept: 60 or more effects
and 10 or more beds in the manifest, every row with evidence, total under 15 MB, the planted rows fail, a hand listen of
every file (no voices, no clicks at loop points), CATALOG-CONTRACT §8 row.

**K2 Core on three stacks: parts, record, timeline, duck.** `castParts` always ends Sound (title Sound) then Stage
directions; `sound` in the record; `buildTimeline` lanes and placement (3.3); `duckEnvelope` (4.2); the two-pass scalar
(4.3). `catalog/tests/golden/mix_sound.json`: 3 voice takes, a Before, an Under inside a speech, an After with a −0.5 s
Start, a bed over two lines; expected placements, breakpoints, and the rendered samples of synthetic inputs (sines and a
click) to ±1 LSB at 16 bit. Accept: green on web (`js/plays.test.js`), Apple (`swift test`), Android (JVM), the voice-only
golden unchanged byte for byte, the golden seen to fail with a planted 1 ms attack change.

**W Web.** The Sound part's studio (3.1), the board (3.2), Mine (3.4), pack download and Cache Storage, `renderMix` lanes,
listen-plan cues, Hear it in place, export refusal, Export my data. `tools/web_fit_studio.py` cases at 320 to 430 px and
1440 for the board and the Sound page. Accept: the frames here matched within the fit tool's tolerance; four states seen;
a mixed export heard on headphones and a phone speaker (ask before anything audible); real Safari on the iPhone.

**A Apple (iOS, iPadOS, macOS; tvOS plays only).** The same in SwiftUI per section 8; the arithmetic mixer behind
`MixRenderer`; `test_apple_design_rules.py`. Accept: golden green; the board and a mixed export on the iPhone 12, the open
and closed Duo (fold during a board audition changes the layout only, §2.9 rule 11) and a Mac window; Ben Bedroom plays a
mixed ear drama with sound.

**D Android (phone, foldable; Google TV plays only).** `CueDecoder`, `MixRenderer` lanes, the board in Compose per section
8, `lintRelease` clean, Roborazzi frames light and dark. Accept: golden green; the board and an export on the Pixel 8a;
the Google TV plays a mixed ear drama.

**P Publish with sound** (after W, A, D): `sound.json` on the item, the published player's cue scheduling, own sounds left
out with the publish warning. Accept: a planted own sound never reaches archive.org (Worker test), a published play with
cues heard to the end on web and a phone.

PARITY rows: Sound part, The sound board, Own sounds, Music beds, Ducking in the mix, Stage directions read by a person,
Sound in published plays (tvOS and Google TV: n/a for the board, ✅ for playing).

## 10. Questions only the owner can answer

1. **A sound someone performs for a cue** (knocking on a table, recorded as the Sound part): is it a take like any line,
   published with the play under the take rules and the CC0 consent, or an "own sound" that stays private? The design
   treats it as a take (it is a performance, and the radio sound man was credited); own sounds are files someone brings
   or saves to Mine.
2. **The pack's archive.org item**: may K1 create `eardrama-sounds-1` under the project's archive.org account (the same
   account question as B31's plates), holding about 80 CC0 and public-domain files with their evidence in the manifest?
3. **The USC Sunset Editorial libraries** (still open from the research): the CC0 sources leave hooves, fire, animals, crowds, a gavel and vehicles empty (section 6), the sounds a radio play asks for most; the USC item (CC0 by its restorer, 1,022 Hollywood editorial effects, 1964-1987) has all of them. Take single files from it into the pack, with the uploader's CC0 and the provenance risk recorded per row, or keep it out and leave those slots to performed sound?

---

## Files

- `docs/research/design/b32-proto/make_data.py`, `data.js`: the play lines and casts on the frames, from the library.
- `docs/research/design/b32-proto/mock.html`, `shoot.mjs`: the frames (`node shoot.mjs <outDir> [port] [only]`).
- `docs/research/design/b32-frames/*.png`: 14 frames, quantized.
