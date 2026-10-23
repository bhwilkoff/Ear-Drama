# Ear Drama plays, phase 1: pass the phone (Feature Design, BINDING)

**Binding.** Quote this document before changing any recording, casting, or
play-mixing path on any platform. Where a platform design doc and this one
disagree about plays, this doc wins on what the feature does and the platform
doc wins on how it looks. Numbers marked *measured* were run on 2026-10-22
against the caches named; the rest is from research 08 and says so.

I want a family at a kitchen table, or a class with one iPad, to be able to
open a play nobody owns anymore, hand the device around until every part has
a human voice, and then listen to what they made together.

On 2026-10-18 the owner described the relay in their own words: *"you would
take one part and act it out. The other non-recorded roles would be simulated
audio when you are recording your parts (but only your part would actually be
recorded). Then the next person would take one of the simulated parts and
record that."* Decision 059 put phases 1 and 2 in 1.0, with radio scripts and
public-domain stage plays both castable when their own record carries the
rights evidence, and no approval queue. This page is phase 1, which is the
relay on one device, with no server, no account, and nothing uploaded.

The device voice is a scene partner, never a performer.

---

## §1. Why it should exist, and who it touches

The `learning-orientation-design` skill asks three questions of the idea
before the four questions of the feature, so here are both, answered for
this feature rather than in general.

**Should it exist at all?** LibriVox has done this by hand for years: forum
casting, one reader per role, an editor stitching the takes together, and
five to twelve months a play (research 08c §1.1). Rehearsal apps such as Run
Lines and Acting Pal sell a synthetic scene partner, but nothing they make is
kept. What we can give people that neither does is a play finished in an
evening, by the people in one room, from a text whose rights a reader can
check, with the voice of every part belonging to someone who was there.

**Who does it touch?** The performers first, and some of them will be
children. Then the people outside the screen: the playwrights and the estates
and companies that may still hold a claim (which is why the rights test in §3
runs before a script is offered), the Generic Radio Workshop volunteers whose
transcriptions we read but may not reuse yet (research 08 C8), and Apple and
Google, whose voice licenses decide what a stand-in may be (§5).

**What will people learn, and what will they stop learning?** They will read
a script closely enough to perform it, make choices about a character, learn
to time a line against someone else's, and listen to one another. The risk is
the one the owner named: if the device voice were good enough to keep, people
would stop performing. So it is never kept (§5), and a play cannot be
finished with one in it.

**The strongest case against it,** made for the people outside the screen: a
child's voice is personal information (16 CFR 312.2 names an audio file of a
child's voice), and a recording made at a kitchen table can travel. Phase 1
answers it by keeping every take on the device it was made on; the only way a
recording leaves is an export the person makes themselves (§6). The cost of
that answer is real, because a family on two phones cannot share a production
until phase 2.

### The four questions

1. **Does it deepen understanding?** Yes. The cast sheet shows the play's own
   structure (who speaks, how much, in which scenes), and recording a part
   means reading it line by line against the lines around it. The stage
   directions stay visible as directions, so the people casting a stage play
   decide for themselves how it should sound on radio (Decision 059).
2. **Does it invite participation?** It is nothing but participation. Every
   part is a person's choice, every take is theirs to keep or redo, and the
   relay makes each performer act opposite the people who went before.
3. **Does it support human agency?** Yes, and the design protects it in two
   places: the app never judges a performance (a line check offers "Keep it
   anyway?" and never rejects), and "hear it read" is an optional rehearsal
   aid, never a default, because the performer's own reading is the point.
4. **Clarity over cleverness?** One device, one script model, line-by-line
   recording with "wait for me" pacing, and a timeline that is plain data.
   The fancier options (a neural voice, live multi-device sessions, automatic
   mixing choices) are left out of phase 1 on purpose.

---

## §2. The flow

Every platform does the same seven things, in its own idiom.

1. **Pick a play.** The Plays tab lists only scripts whose rights state is
   `castable` (§3) and whose parse is clean. Each shows its title, author,
   source, its number of parts, and its rights line with a link to the
   evidence. Nothing on the list is written by a model.
2. **Read the cast sheet.** Parts are listed largest first, with line counts
   and the scenes each appears in, using the script's own names. A part can be
   taken by anyone in the room, one person may double several small parts (a
   radio tradition), and "Stage directions" and "Sound effects" are parts
   like any other, so a person can read the directions aloud or knock on the
   table for the door.
3. **Take a part.** The performer types a name (or not) and picks their part.
   The app checks the audio route and asks for headphones (§4.3), records five
   seconds of room tone with a visible countdown, and opens the script at
   their first scene.
4. **Record line by line.** The previous line plays, from a human take where
   one exists and from a live device voice where not, with the speaking
   character's name and line on screen. Then the device stops and listens
   for the performer's line, and voice detection ends the take. They can redo
   any line, hear a run-up from a line or two before it, and mark the take
   they like.
5. **Pass the phone.** "Done with this part" returns to the cast sheet, which
   now shows that part as recorded. The next person takes another part and
   hears the first performer's takes where the device voice used to be.
6. **Listen through.** The play can be heard from the top with every human
   take in script order. Whether a half-recorded play may be previewed with
   its open parts voiced live (each labeled as a device voice) is an owner
   question (C5, §9). Pending owner, the apps take the conservative reading:
   no preview of a half-voiced play outside the recording flow, so the
   listen-through is offered only once every speaking line has a human take.
   Inside the recording flow the cue before a line, and a run-up, still play
   the device voice live where no take exists.
7. **Finish and keep it.** When every speaking line has a human take and
   someone has listened all the way through, the device renders the mix and
   the play joins the person's library. They can play it back on this device,
   send it by AirPlay or Cast to a television, or export the file through the
   share sheet. An export is the person's own act, not the app publishing.

### The platform idioms

Same verbs, native idioms (`cross-platform-parity-discipline`).

| Platform | Records? | The idiom |
|---|---|---|
| iPhone | Yes | One line at a time in a large teleprompter, the next line dim, one record control at thumb height; the cast sheet is a list and the relay is a push |
| iPad | Yes | The script and the cast side by side (a split view), so the person waiting their turn can follow along on the same screen |
| Mac | Yes | A production is a window, the script in a sidebar, and the keyboard drives it (Space to record or stop, Return to keep a take, the arrow keys to move by line); the best seat for listening through and fixing timing |
| Android phone | Yes | Material 3 list and teleprompter, the same verbs; recording quality varies by device (§4.2) |
| Web | Yes, with headphones only | "Wait for me" pacing only, no sample-accurate cues, and no bleed check, because a browser cannot capture synthesized speech (08a §3) |
| Apple TV, Google TV, Fire TV, Roku | No | Play back only (research 08 §5). In phase 1 a finished play reaches a TV by AirPlay or Cast from the device that made it |

---

## §3. Which plays can be cast today

### The rights test

`catalog/tools/script_rights.py` is the test, written like the audio audit:
ordered buckets, every hide before every rescue, the first match wins, and
evidence a reader can open on every row. The hides are a take-down, the text
source's own terms (the Generic Radio Workshop says "TLDR: Assume
Copyright"), a non-commercial license, and a live renewal of this script by
its registration number or by its title, author, and year. A renewal of new
material on an old play (an adaptation, a translation, an acting version) is
not a claim on the play. Then come three "not enough evidence" states: an
adaptation whose source is unchecked, a translation without its own evidence,
and a foreign play published after the line that the URAA may have restored.

The rescues are publication in 1930 or earlier (the line is computed from the
calendar and moves every 1 January), registration in 1930 or earlier, a
clearance by Project Gutenberg or Standard Ebooks, registration in 1931-1963
with a recorded renewal search, and government work when this script's own
author and employer are on record. A missing renewal row alone never opens a
script, because the printed renewal file loses a quarter to a third of its
entries to OCR (08b §1.3).

"Individual author died by 1955" (research 08 C9) is recorded as
`script_author_died_unapplied` and is not castable, because the owner has not
ruled on it. Everything else is `script_no_evidence`, which is not castable.
The tests are `catalog/tests/test_script_rights.py`: 22 cases, each with a
control, and eleven broken controls recorded in its docstring.

### What is castable, measured

| Source | Records | Castable | Why |
|---|---|---|---|
| Project Gutenberg, English drama shelf or Drama subject | 1,740 (of 3,033 in all languages; 78,383 texts in the catalog) | **1,722** (1,718 stage, 4 radio) | 1,716 on Gutenberg's own "Public domain in the USA." and 6 more on a copyright line of 1930 or earlier in the text; 15 are Gutenberg's "Copyrighted" translations (Frank J. Morlock's, mostly), 2 carry a live renewal (*Night Must Fall*, 1935, renewed 1962; *The Terrible Meek*), and 1 is not a play and carries no evidence |
| Generic Radio Workshop | 1,371 | **0** | GRW's terms hide all of them until we ask GRW (C8). With permission, 10 are *Uncle Sam's Forest Rangers* scripts that still need their own author and employer on record, 1 (*Fibber McGee*, "Good Grammar", D unp. 10032) still needs its renewal search, and 1,360 carry no evidence at all |

The four castable radio plays are Henry Fisk Carlton's NBC *Great Moments in
History* plays (*The Landing of the Pilgrims*, *Caesar Rodney's Ride*, *The
Tree That Saved Connecticut*, and *The Story of Nathan Hale*), published in a
book and cleared by Gutenberg, two of which GRW also lists. So the castable radio library today is four plays, and the
stage library is large. Research 08b's other free radio class, the USDA
typescripts on archive.org, waits on OCR repair and per-script authorship
(08b §2.3), and it is the next radio harvest to build.

### The file the apps read

Phase 1 bundles the castable scripts in the apps rather than publishing them
beside the catalog: casting then needs no network and no fetch, and the file
is small. `catalog/tools/build_castable_scripts.py` writes
`catalog/plays/castable-scripts.json` from the cached texts, keeping a script
only when `script_rights.judge` says `castable` and `script_parse` says clean
(§8 rule 1), with each line as the parser's exact slices, the rights evidence,
and a revision hash. Both the Apple and the Android apps bundle that one file.
Measured on 2026-10-23: 24 cached texts read, **11 plays written, all stage
plays**, 1,645,122 bytes (477,111 gzipped). The stage parser first finds where
the play begins and ends, so title pages, publishers' catalogs, prefaces, and
transcriber notes are set aside with their words and never become a part. A
text is refused, never split, when it holds several plays (cast lists or first
acts counted over the whole text) or sets aside over 40% of its words (the
plays measured set aside at most 28%).
None of the four Carlton radio
plays ships yet, because each parses with more than 5% of its blocks
unclassified. The file moves beside the catalog once the library outgrows a
bundle.

Rights is not the only gate. A rights-castable text also has to parse into
parts a person can perform, and some of Gutenberg's drama shelf is not a play
at all: the random sample below drew a playwriting manual, an issue of *The
Strand Magazine*, and a verse narrative.

### The harvest

`catalog/tools/harvest_gutenberg_plays.py` reads Gutenberg the way its robot
policy asks: "The Project Gutenberg website is intended for human users only,"
and its catalog data "are granted to the public domain." So the harvester
reads the weekly CSV and the daily RDF file from `/cache/epub/feeds/`, once
each, and plain texts from the aleph.pglaf.org mirror, one at a time with a
three-second pause, as "EarDrama/0.1 (+https://eardrama.org)". It records the
title, the authors and translators with their dates, Gutenberg's rights
statement and its link, the source URL, and the LibriVox cast size where a
LibriVox project read the same text. It keeps no summary.

Gutenberg's metadata "does not include the original print source publication
date(s)," so a year is recorded only from evidence a reader can open: a
copyright line in the text itself or the source year LibriVox recorded. That
gave a year for 145 of 1,740 records, measured. Of the authors whose death
year Gutenberg records (1,420 records), 250 died in 1950 or later, and 241
English records name a translator, which is why the translation rule exists.
LibriVox read 146 of these exact texts; where its description prints a cast
list (66), the median cast is 16 parts (quartiles 11 and 20, the largest 62).

### Parsing into parts and lines

`catalog/tools/script_parse.py` turns a radio script or a play into roles and
lines. Every line keeps the block exactly as printed beside its parts
(speech, direction, mic position, sound), and a part is a slice of that block,
so no word is rewritten (08b §4). Directions are kept apart from speech so the
people casting decide how to read them. Its tests, with four broken controls,
are `catalog/tests/test_script_parse.py`.

A **stub** is not a script: under 500 words, or a page of links with no
dialogue. Measured over all 1,028 cached GRW texts, 39 are too short ("Information
Coming Soon...") and 25 are link pages ("PDF files on Old Time Radio Researchers
Group website"). A long text with no dialogue found is a parse **failure**,
not a stub (7 of them, such as a Campbell Playhouse *Rebecca* whose line
breaks were lost). Of the 957 that parse, 827 parse clean.

Measured on seeded samples (`python3 tools/script_parse.py measure`):

| | GRW, 50 scripts | Gutenberg, 20 texts |
|---|---|---|
| Stubs or failures | 2 stubs (too short) | 1 failure (a verse narrative) |
| Parsed clean | **42 of 50** | **9 of 20** |
| Parts per script, median | 11 (8 with five lines or more; 2-13) | 23 (11 with five lines or more) |
| Speeches, median | 272 | 488 |
| Unclassified blocks, median | 1.4% | 4.6% |
| Failure kinds | more than 5% unclassified (6): cast lists in prose, commercials, untagged cues | more than 5% unclassified (8), several plays in one volume (3), not a play (3), Folio texts with rare abbreviated speakers and textual notes (2), a long prose introduction or verse preface (2) |
| Possible aliases flagged | 12 (FIB and FIBBER, DOC and DOCTOR) | 6 |

"Clean" means 5% or less unclassified, at least two parts with five lines or
more, and one play in the text. A hand check of 25 random speeches from the
clean GRW scripts found all 25 attributed to the right speaker. The same check
on the clean plays found 24 of 25 right, the Folio *Hamlet*'s abbreviated
speakers (HAM, OPHE, GUILD) among them, stored as printed for an alias table
to expand later; the miss was a song heading read as a speaker ("SHAMROCK AND
ROSE"), and one direction ("Going towards the door") was typed as a sound. A script that parses clean opens for casting; one that does not
waits for a person to fix its parts, which is editing, not a rights review.

---

## §4. Recording and mixing on each platform

The APIs are the ones research 08a read in Apple's, Google's, and the W3C's
documentation. The deployment floors are iOS 18, macOS 26, and Android 10
(`minSdk = 29`); an API newer than the floor is adopted behind a runtime and a
compile-time gate (Decision 048).

### §4.1 The pipeline

| Step | iPhone, iPad, Mac | Android | Web |
|---|---|---|---|
| Stand-in voice | `AVSpeechSynthesizer.write(_:toBufferCallback:)` into `AVAudioPCMBuffer`s one to three lines ahead, released after playing; `usesApplicationAudioSession = true` on iOS | `TextToSpeech.synthesizeToFile` to a pipe (`ParcelFileDescriptor`, API 30) collecting `onAudioAvailable` chunks; on API 29 a cache file deleted the moment it is read | `speechSynthesis.speak`, whose audio the page cannot see |
| One clock | One `AVAudioEngine`: a player node for human takes, one for stand-in buffers, an input tap for the microphone, every event stamped in sample time | `AudioTrack` and `AudioRecord` (or Oboe/AAudio) with `getTimestamp()` on both | One `AudioContext`; stand-in timing from `speechSynthesis` events, which is coarse |
| Capture | `.playAndRecord` with `.allowBluetoothA2DP`, never `.allowBluetoothHFP`; 5-10 ms I/O buffer | `VOICE_PERFORMANCE` (API 29), `UNPROCESSED` where offered | `getUserMedia` into an `AudioWorklet` writing PCM |
| Route check | `currentRoute.outputs` includes `.headphones`, `.bluetoothA2DP`, or `.usbAudio`; AirPlay is refused for recording | `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` for a wired, A2DP, or USB headset | Asks for headphones and cannot verify |
| Without headphones | Voice processing (`setVoiceProcessingEnabled`), or `setPrefersEchoCancelledInput` on 2024 and later iPhones (iOS 18.2); the take is marked `capture: "aec"` | `VOICE_COMMUNICATION` with `AcousticEchoCanceler`, device by device | Refused |
| End of a line | `SpeechDetector` (26, gated); an energy and zero-crossing detector on iOS 18-25 | An energy detector, or WebRTC's (BSD) | The same detector in the worklet |
| "Did they say the line?" (optional, never a rejection) | `SpeechTranscriber` (26, gated), `SFSpeechRecognizer` with `requiresOnDeviceRecognition` below it | `SpeechRecognizer` on device where offered (UNVERIFIED by API level) | `SpeechRecognition` where `available()` says so |
| Bleed check before a take is kept | Correlate the microphone against the exact stand-in buffer played, delayed by the route latency | The same, against the `onAudioAvailable` PCM | Level only, in the stand-in windows |
| Mix a finished play | `AVAudioEngine` manual rendering (`enableManualRenderingMode`) | Media3 Transformer `Composition` (`@UnstableApi`) | `OfflineAudioContext.startRendering()` |

### §4.2 The takes and the timeline

A take is the performer's line only: from voice onset less 250 ms to its end
plus 250 ms, mono, 48 kHz, 24-bit, so the stand-in windows are never kept.
Each take records what its performer heard (the take id for each other part,
or `standin`), which is how the credits can say who played opposite whom.

The mix is a timeline that is plain data: lines in script order, each pointing
to a take with its in and out points, a gap before it (0.35-0.5 s by default),
an overlap where someone interrupts, and a gain measured by ITU-R BS.1770 and
stored, never written into the take. Because placement is relative, a re-take
that runs half a second longer ripples correctly. The renderer is a pure
function of the timeline, written once per language and proven by one golden
timeline on every platform (`cross-platform-determinism`), and the finished
mix is normalized to -16 LUFS integrated and -1 dBTP. Sound and music cues
show as text and are silent until someone records them or picks a sound with
evidence (08a §8); phase 1 ships no effects library.

### §4.4 As built on Apple (2026-10-22)

- One `AVAudioEngine` per recording session (`Core/Plays/LiveAudio.swift`): one
  player node for takes and stand-in buffers, a tap on the input converted to
  mono 48 kHz in memory. The microphone permission is asked when the performer
  presses Start Recording, never at launch.
- Takes are FLAC from a 24-bit source, which writes on macOS 27 (measured); the
  iOS 18 floor is still to measure on a device.
- The end of a line is an energy detector on 20 ms frames with its floor from
  the session's room tone, ending after one second of silence; the one record
  control also stops it. `SpeechDetector` and the line check are not built yet.
- The bleed check correlates each kept take against the stand-ins that cued it
  and flags a match (`BleedCheck.threshold` is 0.5, to measure on devices).
- The finished mix is rendered offline by `Core/Plays/MixRenderer.swift` into
  `mix.m4a` (AAC, 96 kbps mono). Each take's gain targets -16 LUFS and is held
  so its sample peak stays at or below -1 dBFS; sample peak stands in for true
  peak until a true-peak meter is written. The listen-through plays that
  rendered mix, which holds only human takes, and reaching its end without
  skipping ahead finishes the play.
- Gaps are 0.4 s; overlaps, room-tone fill, and per-role pan are not built.

### §4.5 As built on Android (2026-10-23)

- `AudioRecord` at 48 kHz mono float from `VOICE_PERFORMANCE` with
  headphones; without them `VOICE_COMMUNICATION` with
  `AcousticEchoCanceler`, the cue played as voice-call audio, and the takes
  marked `capture: "aec"`. The built-in or wired microphone is preferred
  over a Bluetooth one. The cue plays through an `AudioTrack`.
- The stand-in is collected from `onAudioAvailable` into memory. On API 30
  and later `synthesizeToFile` writes to a pipe, which is drained and
  dropped; on API 29, which has no pipe overload, the engine speaks at zero
  volume while the same callback hands over the samples (UNVERIFIED on a
  device). No cache file is ever made, stricter than §5 rule 1 allows.
- Takes are 24-bit PCM WAV, not FLAC: MediaMuxer has no FLAC container, so
  FLAC would mean hand-writing the stream around MediaCodec's frames on a
  path no JVM test can read back. The file names and `production.json`
  keys are Apple's.
- The timeline, gain, detector, and bleed check are Apple's, line for line
  (`plays/`). The mix is rendered a chunk at a time and encoded by
  `MediaCodec` (AAC-LC, 96 kbps mono) into `MediaMuxer` as `mix.m4a`, not
  Media3 Transformer. The listen-through plays it with `MediaPlayer`.
- Export is the share sheet through a `FileProvider` scoped to `Plays/`.

Recording quality varies on Android by manufacturer (echo cancellation,
`UNPROCESSED` support, and engine voices all differ), so the bench needs the
Pixel 8a and one Samsung before Android is called done.

### §4.3 Headphones

Headphones are asked for before every recording session, and the request is a
refusal with its reason, which the essential-words rule allows. They do two
jobs: they keep the stand-in out of the microphone, and they let the
performer hear the scene without the room hearing it. Bluetooth microphones
are refused for takes (HFP is narrowband), so the route is headphone output
with the built-in or a wired microphone.

---

## §5. The live stand-in rule

A synthetic voice is a live stand-in only and is never stored (Decisions 055
and 059). Apple's macOS license allows the system voices "while running the
Apple Software" and forbids "recording, publishing or redistribution ... in a
profit, non-profit, public sharing or commercial context" (08a §1.4); Google's
engine has no output license we could find, and the safe reading is the same.
So, on every platform:

1. Stand-in audio lives in memory buffers (or, on Android 10, a cache file
   that lives for milliseconds) and is released after it plays.
2. The stored take is the performer's line window only, and the bleed check
   flags any kept window whose microphone signal matches the stand-in it
   overlapped. A flagged line is re-taken with headphones.
3. A partial play is never mixed into a file. A listen-through plays the human
   takes and voices the open parts live, on this device, and the screen labels
   each such line as a device voice, so a stand-in never passes as a person
   (`learning-orientation-design`, the honesty checklist).
4. A play cannot be finished with a stand-in in it, and an export of an
   unfinished play is refused with a sentence that says why.
5. Only local voices are offered: `localService` on the web and
   `!isNetworkConnectionRequired()` on Android, so a script line is never sent
   to a speech server.
6. Personal Voice is not offered (C10, recommended): Apple forbids it in any
   public-sharing context and aims it at people who use it to speak.

Voices are assigned per part from what the device has, by `gender` on Apple
where the script states one and by a small hand map on Android, with pitch and
rate varied so two parts on one voice can be told apart. A fresh iPhone may
have only a few English voices, so the character's name on screen does the
identifying, and the app points to Settings for more.

---

## §6. What is stored where on the device

Phase 1 keeps everything on the device that made it. Nothing is uploaded, no
account is needed, and no record leaves the device unless the person exports
the finished play.

| What | Apple (iPhone, iPad, Mac) | Android | Web |
|---|---|---|---|
| The script as cast (the parsed model, with its line ids and revision) | Application Support, `Plays/<production>/script.json` | `filesDir/Plays/<production>/script.json` | The origin private file system (OPFS) |
| Takes, one file per kept take, never overwritten | `Plays/<production>/takes/` as FLAC (if the floor OS cannot write FLAC, ALAC in CAF; to measure) | `filesDir/Plays/<production>/takes/` as 24-bit WAV (§4.5) | OPFS, WAV |
| Room tone, per session | `Plays/<production>/roomtone/` | the same | OPFS |
| The production record (parts, who took which part by the name they typed, what each take heard, the timeline) | `Plays/<production>/production.json` | the same | OPFS |
| The rendered mix of a finished play | `Plays/<production>/mix.m4a`, rebuilt from the takes whenever they change | the same | OPFS, after `navigator.storage.persist()` is asked |
| Stand-in audio, transcripts of takes, analytics | Never stored | Never stored | Never stored |
| Apple TV | Nothing: it records nothing and stores no plays in phase 1 (tvOS writes only to Caches) | | |

Takes are in Application Support rather than Caches because they are the
person's own work and the system may purge Caches; they go into the device
backup like any other document. A line check keeps only its score, not the
words it heard. Deleting a production deletes its folder, and "discard
unused takes" removes every take that is not a part's chosen one. Because
nothing leaves the device, phase 1 collects nothing under COPPA, which is
why it is open to everyone, children included (08c §6.2).

---

## §7. Accessibility

- **Screen readers.** VoiceOver and TalkBack speak through the same speaker
  the microphone hears, so the app announces "your line" before it starts
  listening and makes no announcement while it listens. The line itself is
  on screen and on a braille display before the take begins.
- **Type.** The teleprompter follows Dynamic Type and the platform's font
  scale with no truncation; a long line wraps rather than shrinks.
- **One action.** Recording starts and stops with one control, reachable by
  Switch Control, Voice Control ("Record"), a keyboard (Space on the Mac and
  the web), and a hardware key on Android, and "wait for me" pacing never
  rushes anyone.
- **Cues you can see and feel.** Every stand-in line shows its speaker and
  text as it plays, and "your line" comes with the `selection` haptic and a
  visible countdown, so a performer who is hard of hearing can follow the
  scene.
- **Pace.** Stand-in rate is adjustable, and Reduce Motion turns off the
  scrolling teleprompter in favor of a page per line.
- **The honest cost.** A person who cannot speak cannot record a part in
  phase 1, because Personal Voice is not offered (§5, C10). They can still
  direct, take the sound-effects part, and listen.

---

## §8. Rules (binding)

1. A script is offered for casting only when `script_rights.judge` returns
   `castable` and its parse is clean. A new kind of evidence is a new bucket
   with a paired test and a broken control, never a list of ids.
2. No model writes, rewrites, summarizes, or fills in a word of a script, a
   cast list, or a description. Stage directions are shown as printed.
3. A synthetic voice is never written to a stored file, never part of a mix,
   and always labeled as a device voice where it plays (§5).
4. Phase 1 uploads nothing and needs no account.
5. A take is immutable; choosing a different take never deletes the old one
   until the person discards it.
6. The app never scores or rejects a performance.
7. Every platform that records ships the same seven verbs (§2) in the same
   change set, or carries a ⏳ cell in PARITY.md with its reason.

---

## §9. Questions only the owner can answer

These are still open from research 08, plus three this design raised.

| # | Question | What phase 1 does until it is answered |
|---|---|---|
| C5 | May anyone hear a half-recorded play with live stand-ins, or only its cast? On one device the cast and the listeners are usually the same people | Pending owner: no preview of a half-voiced play outside the recording flow; the listen-through opens once every speaking line has a human take |
| C6 | A part nobody takes: leave the play unfinished, let someone double it, or allow a stored openly licensed voice (Kokoro, Apache-2.0; Piper's LibriTTS-R voices, CC BY 4.0)? | Pending owner: the play stays unfinished and never gets a stored synthetic voice; one person may double parts; only sound effects and stage directions may be left silent |
| C7 | Relay order: strictly one part at a time, or any order with "largest part first" as the suggestion? Claim expiry (7 days) matters in phase 2 | Pending owner: strictly one part at a time, in a fixed order, largest first; a finished part can be reopened for a re-take only while no other part records |
| C9 | Accept "individual author died by 1955" as evidence for an unregistered script? | Pending owner: recorded as `script_author_died_unapplied`, not castable |
| C10 | Sponsors' commercials inside free scripts: keep, make optional, or drop? Personal Voice: not offered (recommended)? | Pending owner: scripts are performed as published, commercials included; Personal Voice is never offered or asked for |
| New | Decision 057 says signing in is "required to record, cast, or publish a shared play." Does a local, never-shared recording need an account? | Pending owner: phase 1 is local only and needs no sign-in; Decision 057's sign-in covers sharing |
| New | A text that is rights-castable but parses unclean (11 of the 20 sampled plays): who fixes its parts, and is that an editing role phase 1 needs? | Not offered until someone fixes it |
| New | GRW (C8): ask before reusing its transcriptions? It decides whether the GRW radio scripts with other evidence can ever be cast from GRW's text | All 1,371 hidden on GRW's own terms |

---

## §10. Out of scope for phase 1

Uploading, invite links, accounts, the Worker, and archive.org (phase 2);
open casting and peer review (phase 3); a stored synthetic voice of any kind;
an effects library; teleplays; any model-written text in a play; any score,
like, or ranking of a performance.

Bring back the owner's answers to C5, C6, C7, C9, and C10.
