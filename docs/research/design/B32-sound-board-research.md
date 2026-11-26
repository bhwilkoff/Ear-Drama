# B32 research: a foley and music board for recording

Date 2026-11-26. Research only; no code, no decision taken. Owner ask (2026-11-26): record stage
directions as a character, a foley/sound-effects board that puts sound under a recording, duck it under
voices, add your own sounds, background music, "public domain audio clips and music for all of it."

## 0. Where the app already is (read from the repo)

- The script data already has the parts. `js/plays-core.js` defines `DIRECTIONS = 'directions'` and
  `SOUND = 'sound'` as castable parts ("Stage directions", "Sound effects"); a line's parts are
  `{say}|{direction}|{mic}|{sound}`; reader-core draws a "sound lane" for sound pieces and asides
  beginning "sound of", "noise of", "music" (PLAYS-DESIGN §2.6). Both are "Not read by default"
  (§2.8 rule 7, Q12a) and "may be left silent". So item 4 of the brief is mostly built: a person can
  already take the Directions part and record it. What is missing is a nicer way to offer it (a
  named "Narrator / Directions" role on the cast sheet, one tap) and the sound lane doing something.
- The mix is a pure function of a timeline of human takes only: `MixTimeline.swift`,
  `MixRenderer.swift` (AVAudioEngine, `.offline` manual rendering, player node, per-take stored gain),
  `plays-core.js renderMix` (OfflineAudioContext in 30 s chunks, 16-bit mono WAV). One golden timeline
  proves each stack (`cross-platform-determinism`). Finished mix: -16 LUFS integrated, -1 dBTP, AAC 96 kbps mono.
- PLAYS-DESIGN §4.3 says: "Sound and music cues show as text and are silent until someone records them or
  picks a sound with evidence (08a §8); phase 1 ships no effects library." B32 is that later phase.
- A synthetic voice is a live stand-in, never stored (Decisions 076, 088). Cues are not voices, but the
  same discipline applies: the mix may hold only things with evidence behind them.
- Storage: owner 2026-11-19 (Decision lines ~156, ~787): "We are using archive.org for storage, not
  cloudflare." Cue files therefore live on archive.org (or in the app bundle), never R2.
- Android: no mix renderer found under `android/app/src/main` (grep for mix hits only manifest paths,
  Components.kt, ReaderRoom.kt, ReadScreens.kt). Android's mix/export parity needs its own check in design.

## 1. Sources (license evidence)

Rule applied: Ear Drama says a thing is public domain only on evidence; CC0 or a Public Domain Mark on
the item is evidence, "uploaded to archive.org" is not. "Redistribute raw files" means: may we put the
files in our own bundle or on our own archive.org item, not merely let a person use them inside a mix.

| Source | License (evidence) | Raw redistribution | Attribution | Quality / count / formats | Verdict |
|---|---|---|---|---|---|
| **USC Sunset Editorial / Red / Gold / SSE libraries on archive.org** https://archive.org/details/sound-effect-libraries-red-gold-sunset-editorial | Item page shows CC0 1.0 Universal. Item text: 1,022 effects from Sunset Editorial (Hollywood editorial house, about 1964-1987), restored by Craig Smith (iZotope RX 10); uploaded 2023-05-17. https://blog.archive.org/2023/05/20/crash-bark-boom-the-usc-sound-effects-library/ states no license, so the CC0 label is the uploader's, not USC's. Per-sub-item pages e.g. https://archive.org/details/SSE_Library_WEAPONS also CC0. | Yes if the CC0 label holds. Residual risk: the CC0 is a dedication by a restorer of tapes he did not record; sounds are 1930s-80s professional library effects of unknown authorship. | None required. | Excellent period-correct mono effects, WAV. Three ZIPs 11.2 + 7.7 + 4.2 GB (23.1 GB). Category coverage is the best found. | **Primary effects source, with an owner call on the provenance risk (Q1).** Pull individual files, never ship the ZIPs. |
| **Kenney audio packs** https://kenney.nl/assets/rpg-audio (CC0, 50 files, tags foley/footstep/weapon); https://kenney.nl/assets/interface-sounds (CC0, 100); https://kenney.nl/assets/ui-audio (CC0, 50); sci-fi sounds (CC0, 70) | CC0 on Kenney's own pages (fetched: rpg-audio, interface-sounds, ui-audio from search). Impact Sounds' CC0 confirmed only through a Godot mirror. | Yes. | Optional. | Clean, game-flavored (footsteps, cloth, coins, book, weapons, UI). OGG. Tiny. | **Safe gap-filler** (footsteps, book, cloth, coin, bell-ish). Not period-feeling. |
| **OpenGameArt CC0 items** e.g. https://opengameart.org/content/door-open-door-close-set (CC0), https://opengameart.org/content/sound-effects-pack | Per-item license field; many CC0 but some CC-BY (e.g. "Footsteps on different surfaces" is CC-BY 3.0, excluded). | CC0 items yes. | CC0 none. | Hobbyist, uneven. | **Per-item only**; record license URL per file; skip CC-BY. |
| **Freesound, CC0 filter only** https://freesound.org/help/tos_api | The sounds carry their own CC0 deed. But the API terms (fetched) bar distributing or linking to Content "from any location" outside your own application (4a), allow only "limited intermediate copies", forbid full copies of the database, and make commercial API use "negotiated case by case with UPF" (3). | Murky: CC0 says yes; API terms say no for API-fetched copies. Downloading by hand from a sound's page (no API) is governed by the site's own terms and the CC0 deed. | None for CC0. | Huge, best breadth, uneven quality; MP3/OGG previews, original WAV/FLAC. | **Do not use the API to build the bundle.** Hand-curate a few dozen CC0 downloads from the site only if the owner accepts the risk, and record sound ID and uploader per file. Prefer sources above. |
| **Sonniss GameAudioGDC bundles** (e.g. https://scrubby.duckdns.org/Sonniss.com%20-%20GDC%202023%20-%20Game%20Audio%20Bundle/License.pdf is a mirror, not official) | Royalty-free license, not a PD/CC grant. Secondary sources: usable embedded in a project, standalone redistribution of individual sounds prohibited. Official sonniss.com page not retrieved. | **No** for an app bundle of raw files that a person could extract; arguable for use inside a finished mix only. | Not required, but license terms apply. | Pro quality, 30-40 GB a year, WAV. | **Refuse.** The brief's own test (raw files) fails and it is not "public domain". |
| **BBC Sound Effects (RemArc)** https://sound-effects.bbcrewind.co.uk/ (page not fetchable here) | Personal, educational and research use only (widely stated; unverified by fetch). | No. | n/a | 33,000 clips. | **Refuse** (non-commercial). Verify the licensing page if the owner wants it confirmed. |
| **Musopen (PD recordings)** https://musopen.org/faq/ | Musopen's own FAQ: cannot guarantee user uploads are PD; foreign works may not be; Musopen's own site and service materials are copyrighted. Their Kickstarter-funded orchestral recordings are mirrored on archive.org (MP3 plus WAV multitracks); third-party catalogs list Public Domain Mark 1.0 for them. Not confirmed CC0. | Yes for the Kickstarter set if the item shows PDM/CC0; check each. | None for PDM. | Good modern orchestral performances, MP3. | **Use only items whose archive.org or Wikimedia page shows PDM or CC0.** Do not rely on Musopen's site. |
| **Library of Congress National Jukebox / Citizen DJ** https://citizen-dj.labs.loc.gov/public-domain-2022/ | Pre-1923 recordings public domain from 2022 (Music Modernization Act); Citizen DJ says its sounds are "completely free-to-use"; 1923 recordings entered 2024, 1924 in 2025, 1925 on 2026-01-01 (MMA 95-year rule; verify on loc.gov). National Jukebox streaming rests partly on a Sony gratis license, so per-item. Terms of the bulk page not retrieved. | PD items yes; the site offers per-collection download; bundling not addressed on the page read. | None required. | Acoustic and early electric era (78s), noisy, mono, period-true for stings and bridges. | **Good music-bed source** (dance bands, marches, waltzes, classical excerpts) restricted to Citizen DJ collections and to items pre-1926. Read the "Copyright & ethics guide" first. |
| **NASA audio** https://www.nasa.gov/multimedia/guidelines/index.html ; https://www.nasa.gov/artemisaudio | Generally not copyrighted; Artemis Audio files "cleared for use" under the media guidelines; no endorsement implied; logo not PD; identifiable-person limits. | Yes, with the no-endorsement rule. | Not required; credit courteous. | Rocket, radio chatter, space ambience. | **Small special set** (rocket, beeps). Skip human voices. |
| **US government works** | Not copyrighted (17 U.S.C. 105) for federal authors only; contractors/other-owner items excluded. | Yes when federal. | None. | Scattered. | Use only through NASA/LOC/NPS-type pages with a federal statement. |
| **Wikimedia Commons** (Musopen mirrors, PD sounds) | Per-file license tag (PD/CC0/CC-BY). Many Musopen performances are on Commons. | PD/CC0 files yes. | PD none; CC-BY excluded. | Mixed. | Good for music beds; same per-file evidence rule. |
| **Free Music Archive CC0** | Per-track license; FMA also has non-commercial licenses and a personal-use license. | CC0 tracks yes. | None. | Modern, mostly not radio-drama-shaped. | Low priority; per-track only. |
| **Kevin MacLeod, most royalty-free music** | CC-BY. | Attribution burden. | Required. | | **Out** (brief: no attribution we cannot meet). |

Caveat: license text was read through search snippets and fetches of a handful of pages; per-file
evidence (URL, license mark, date checked, who marked it) must be captured at ingest, as
`evidence-gated-catalog-curation` requires. A `catalog/` manifest row per cue (source URL, license URL,
retrieved on, sha256, duration, category) is the deliverable that makes this auditable.

## 2. Starter cue list (target 90) and music beds (target 16)

I could confirm the library, not individual file names (the USC item is three ZIPs with metadata
spreadsheets; the catalog sheet must be read to name files). Named files below are therefore categories
with the likeliest source; the build step picks and names exact files and records them in the manifest.
The library is Hollywood editorial 1930s-80s, so mono-compatible, and the right sound for a radio drama.

Effects (counts per category; S = SSE/Red/Gold USC item pages, K = Kenney rpg-audio, O = OpenGameArt CC0):

| Category | n | Cues | Likely source |
|---|---|---|---|
| Doors | 8 | wood door open, close, slam, creak, screen door, door knock x3 (single, triple, urgent), latch, key in lock | S, O door set |
| Footsteps | 10 | walk on wood, stone, gravel, grass, snow, stairs up/down, run, heels, boots | S, K |
| Phone and bells | 8 | rotary ring, hang up, dial, doorbell, church bell, hand bell, ship bell, school bell | S |
| Weather | 8 | rain light/heavy, thunder x2, wind, storm, howling wind, drip, fog horn | S |
| Rooms and crowds | 10 | quiet room tone, street ambience, crowd murmur, restaurant, tavern, applause, cheer, courtroom hush, night crickets, forest | S |
| Vehicles and animals | 14 | car start, car pass, car door, horn, horse hooves, horse whinny, carriage, train pass, train whistle, steam engine, ship horn, airplane, bicycle bell, wagon | S |
| Weapons (decision: yes, short) | 6 | pistol shot, rifle, sword draw, sword clash, cannon, door-splinter | S, K |
| Clocks and small objects | 8 | clock tick, grandfather chime, alarm clock, typewriter, pen scratch, paper rustle, match strike, coins | S, K |
| Water, fire, glass | 8 | splash, pour, drip, boat oars, fire crackle, flame whoosh, glass break, glass clink | S |
| Animals | 6 | dog bark, dog growl, bird song, owl, cat, rooster | S |
| Body and human extras | 4 | heartbeat, knocking at wall, cough, gasp (use sparingly; no voices) | S |
| **Total** | **90** | | |

Music beds (PD recordings or PDM/CC0, 12 to 30 s unless noted; stings 2 to 8 s):

| Role | n | Material | Source |
|---|---|---|---|
| Stings (curtain, tension, comedic, sad) | 4 | cut from public-domain 78s excerpts | LOC Citizen DJ (pre-1926) |
| Bridges and transitions | 4 | orchestral phrases: Grieg "In the Hall of the Mountain King" opening, Mussorgsky "Night on Bald Mountain" (a Wikimedia/Musopen file exists: Modest_Mussorgsky_-_night_on_bald_mountain.ogg), Beethoven, Dvorak | Musopen PDM on archive.org/Commons |
| Underscores (calm, suspense, chase, romance, mystery, sea) | 6 | slow movements from Satie, Debussy "Clair de Lune", Chopin nocturnes, Schubert | Musopen PDM / Commons |
| Radio-era dance band / theme beds | 2 | pre-1926 band and waltz 78s | LOC National Jukebox via Citizen DJ |

Total about 16. Composition may be PD while a given recording is not; the recording's own evidence is the test.

Budget: 90 cues x 40 KB (OGG/Opus mono, 24 kbps, ~5 s avg) plus ambience loops 30 s x 8 at 100 KB is about 4.5 MB; 16 beds
x ~600 KB (Opus mono 32 kbps, 20 s) about 10 MB. Total roughly 15 MB, well under any bundle or on-demand pack concern.

## 3. How radio foley and boards work (and app precedents)

- Radio effects were made live by the sound-effects person, in the studio, at the same mic, on cue
  (coconut shells, door frames, thunder sheets, wind machines): https://en.wikipedia.org/wiki/Foley_(sound_design),
  https://mag.uchicago.edu/sound-effects, https://ruyasonic.com/sfx_primer.htm. Scripts carried cue marks in
  the margin; a crew could not talk during a take so cueing was rehearsed; actors paused to let effects land
  (Purdue transcript). Effects stay sparse: "only significant sounds"; music bridges and stings mark scenes.
- Digital precedents (from general knowledge, not fetched): a pad grid (soundboard apps, Anchor's sound
  effects, Hindenburg's "Clipboard" and sound drawer, Ferrite's markers), a timeline lane under a voice
  lane (GarageBand, Soundtrap, Ferrite), automatic ducking (Hindenburg Auto-ducking, Adobe "Auto Duck" with
  sensitivity / reduction / fade: https://helpx.adobe.com/ro/premiere-pro/how-to/automatic-audio-ducking.html).
- Interaction patterns for Ear Drama, in order of fit:
  1. **Place on a line (the primary)**: the sound lane already exists in the reader; tapping a
     "sound of ..." row opens the board pre-filtered by what the text says; choose a cue and the line shows it
     as chosen (like a take). Placement is relative to a line, like gaps and overlap in `MixTimeline`, so a longer re-take ripples it.
  2. **Pads during a take (secondary, optional, v2)**: trigger a cue live while recording a line or a run; the
     cue's time relative to the line's start is stored as an offset on that line. Live trigger needs
     monitoring on headphones so the cue is not captured by the mic (the bleed check applies to cues too).
  3. **Under a span (beds)**: music and ambience apply to a range of lines (from line A to line B), with fade
     in/out; one bed at a time per lane, pad to cross-fade.
  4. **Own sounds**: record in the app (a "your sound" pad, up to 10 s) or import a file the person owns;
     kept on the device with the production, shared only if the person publishes, and their declaration covers it (13+, Decision 088 item 5).
- Ducking parameters (engineering practice, unverified by a standard; the fetched sources give concept
  only): music bed to about -18 dB relative to its un-ducked level while any voice is active, effects to
  about -10 dB (effects are short and should stay audible); attack 80-150 ms ahead of the voice start (the
  take's in point is known, so the duck can start early with look-ahead); release 400-800 ms; duck is
  computed from the take timeline, not detected from audio. Voices always win. Make depth a per-lane slider
  (Music, Effects) with the defaults above.
- Loudness: voice takes are already gain-normalized to -16 LUFS; beds sit about -24 to -28 LUFS short-term
  under speech (in practice a -18 dB duck from a bed set at about -9 dB relative to voice). The whole mix
  stays normalized to -16 LUFS integrated, -1 dBTP as today (podcast norm; Apple's own spec not
  retrieved in this pass: confirm against Apple Podcasts specs before citing).

## 4. Platform audio APIs

All three platforms already render offline from a timeline; B32 adds lanes to the timeline and gain
envelopes. Ducking is computed from the timeline, so it is deterministic and one golden test proves it on
every stack, the same way the placement math is proven.

- **Web**: `GainNode.gain.setValueAtTime / linearRampToValueAtTime / setTargetAtTime` (https://developer.mozilla.org/docs/Web/API/AudioParam),
  scheduled on an `OfflineAudioContext` for export (already used by `renderMix`) and an `AudioContext` for
  preview. A DynamicsCompressor sidechain is not available natively (no sidechain input); a precomputed
  envelope from the timeline is the better route and the deterministic one. `AudioBufferSourceNode` with
  `loop = true` for beds. Decoding OGG/Opus works in all current browsers; Safari decodes Opus in CAF/WebM
  and recent versions in OGG, so test, or ship AAC/M4A (decodeAudioData) for safety.
- **Apple**: the existing `MixRenderer` uses `AVAudioEngine` with `enableManualRenderingMode(.offline)` and
  one `AVAudioPlayerNode`. Add a player node per lane (voices, effects, music) into per-lane
  `AVAudioMixerNode`s; automate lane volume by splitting the render loop into render blocks and setting
  `mixerNode.outputVolume` or `volume` at each block boundary (a ramp every 10 ms is smooth), or apply the gain
  envelope to the PCM buffer directly (simplest, bit-exact, matches the web path). Pre-compute the
  envelope in `MixTimeline` so web and Apple share it. Looping bed: schedule a looping buffer
  (`scheduleBuffer(options: .loops)`). Docs: https://developer.apple.com/documentation/avfaudio/avaudioengine.
- **Android**: native only (no Oboe needed): decode cues with `MediaCodec`/`MediaExtractor` to PCM, mix into
  a float buffer in Kotlin with the same envelope, encode to AAC with `MediaCodec`/`MediaMuxer`, or write a WAV
  as the web does. Preview through `AudioTrack` in streaming mode (https://developer.android.com/reference/android/media/AudioTrack),
  or Media3 `ExoPlayer` for single-file playback of the rendered mix. Android currently has no mix renderer
  (confirm in design), so B32 on Android includes the base renderer.
- Parity: one JSON timeline schema (`lanes: voices|effects|music`, each placement `{lineID|spanStart/spanEnd,
  cueID, offsetMs, gain, loop, fadeInMs, fadeOutMs}`), one ducking function, golden test on every stack.

## 5. Stage directions as a read part

Already data: `DIRECTIONS` is a part with its own cast row ("Stage directions"). Today a person can cast
themselves in it, but it appears last on the cast sheet, silent by default, unlabelled as a role. Recommend:
rename the row's display to "Narrator (stage directions)" for scripts with 5 or more directions, offer
"Read the directions" as a one-tap role when casting, give it the same Default (device voice, never stored)
rule as other parts, and in Listen Through include directions only when the part has recorded takes or a
live voice, as now. The tiny sound-lane line ("[A door opens]") is a sound cue candidate, not a direction
to speak: the board resolves which, from the part's key (`sound`) or a CUE_WORDS aside ("sound of", "noise
of", "music"), which reader-core already does; a person can reclassify a line (PLAYS-DESIGN line 1969:
"part, Direction, or Sound").

## 6. Size and hosting

- Ship the 90 cues and 16 beds (about 15 MB) as an on-demand "Sound pack" fetched from an archive.org item
  we own (owner 2026-11-19: storage is archive.org, never Cloudflare), listed in a `sounds.json`
  manifest (id, title, category, duration, license URL, source URL, sha256, retrieved on). Per-category pack
  (e.g. doors 2 MB) so a person downloads only what they use. The web fetches the pack from archive.org as
  it fetches episode audio; Apple/Android cache in Application Support / noBackup dir.
- Nothing bigger is needed. Do not mirror the 23 GB USC ZIPs; extract only chosen files and record the item
  URL they were taken from.
- Offline: a production that uses a cue stores the cue ID, not a copy; the cue must be present on the
  device that exports, or the export says which cue is missing (never silently dropped).

## 7. Recommendations

1. Build the sound lane as a third lane in `MixTimeline`; ducking is computed from the timeline; one golden test on web, Apple and Android.
2. Primary interaction: place a cue on a line from the reader's sound lane; add "pads during a take" later.
3. Starter pack of 90 cues and 16 beds, hosted on an archive.org item we own, with a per-cue evidence manifest.
4. Effects from the USC CC0 libraries (if the owner accepts the provenance risk) plus Kenney CC0 and per-item OpenGameArt CC0; music from pre-1926 LOC items and Musopen PDM files with item-level evidence.
5. Refuse Sonniss, BBC RemArc, CC-BY music (MacLeod), and any Freesound API-fetched copies.
6. Keep "a synthetic voice is a live stand-in, never stored" and the bleed check: a cue never carries a voice, and the exported mix holds only human takes, own sounds, and evidenced cues.
7. Define the missing Android mix renderer as part of the same batch.
8. Learning-orientation (before building): the board should show what the script says ("sound of a door opening") and invite a choice; it must not auto-place sound by guessing. A suggestion row filtered by the cue's words is search, not authorship.

## 8. Owner questions (at most three)

1. **USC CC0 libraries**: the CC0 label is the restorer's, not USC's; the sounds are 1930s-80s Hollywood library effects of unknown authorship. Use them as the main effects source (best quality and coverage), or limit the first pack to Kenney and OpenGameArt CC0 only (smaller, safer, modern)?
2. **Pads during a take** (live triggering as a person records): in the first release, or place-on-line only?
3. **Own sounds**: allowed in a published production (covered by the 13+ declaration), or private to the person and their group only in the first release?
