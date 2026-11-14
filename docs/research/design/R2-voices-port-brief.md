# R2 voices port brief: casting the device voices on Apple and Android (Decision 076, S2)

The web shipped voice casting first (2026-11-14). This brief is the exact spec for the Apple
(iOS, iPadOS, macOS; tvOS reads the cast only) and Android ports. It binds nothing new: the
rules are PLAYS-DESIGN §2.8 (the verbs) and each platform's design doc (iOS-DESIGN §4.12c,
macOS-DESIGN §4.5c, ANDROID-DESIGN §4.9b, tvOS-DESIGN §4.13). Where this brief and a design
doc differ, the doc wins; fix the doc first.

The owner, 2026-11-14: *"The virtual voices who play the different parts should also be
intuitive."* Owner rulings (076, R2 §7 Q7, Q8, Q12 answered (a)): each part gets a voice on
the cast sheet; one shared assignment everywhere; the picker previews the part's own first
line; speed and pitch per part; auto-cast = distinct voices in cast order, best voice to the
largest part, alternating the voice's own reported gender where the platform reports it,
never guessing a character's gender; every choice overridable; each device keeps its own
cast; stage directions not read by default, with a voice choice on their part.

**Before you start.** Real devices only (iPhone 12, iPad, a Mac window; Pixel 8a); never a
simulator or emulator. **Do not play audio aloud in automated runs**: every test stubs the
synthesizer, and a picker preview on a device is pressed only with the owner's say-so (memory:
ask before an audible test run). The reader port (`R2-reader-port-brief.md`) may not be merged;
the cast sheet half of this brief does not depend on it, the reader half (§3.4, §4.4) does.

**The web reference** (read it; port behavior, not idiom):
- `js/voice-cast.js`: `tierOf`, `genderOf`, `systemVoices`, `autoCast`, `normalize`,
  `resolve`, `caster` (`ensure`, `resolve`, `entry`, `set`, `recast`), `load`/`save`/`forget`,
  `productionKey`/`scriptKey`, `PITCHES`, `RATE`, `PITCH`, `NOT_READ`.
- `js/plays-voice.js`: `StandInVoice.create({ cast })`, `reads(part)`, `speak(text, part, rate)`
  (the part's rate times the session's), `speakAs(text, voice, {rate, pitch})` (the preview).
- `js/plays-core.js`: `listenPlan(p, script, reads)` (the optional third argument).
- `js/plays-session.js`: `ListenThrough` (passes `reads`), `TableRead`.
- `js/cast-ui.js`: the chip, the picker, the reader's Voices list.
- `js/voice-cast.test.js`: every case below, each seen to fail. `tools/web_fit_cast.py`: the frames.

---

## 1. The model (both stacks, Core only, no UI)

1. **`VoiceCastEntry`**: `engine` (`system` | `kokoro` | `none`), `voice` (String?, the
   engine's stable id), `name` (String?, the voice's display name, kept so a vanished voice can
   be named), `rate` (0.5...2, default 1), `pitch` (0.5...1.5, default 1). Codable / kotlinx
   serializable. `kokoro` decodes and falls back (§1.4) until S6 adds the engine. Normalize on
   read: an unknown engine or a system entry without a voice is "no entry"; rate and pitch are
   clamped and rounded to 0.01.
2. **The castable voices, best first** (`systemVoices`): English, local only, then
   - Apple: `AVSpeechSynthesisVoice.speechVoices()` minus `.isPersonalVoice` and
     `.isNoveltyVoice` (as `DeviceVoices.castable()` today); tier = `quality` (`.premium` 2,
     `.enhanced` 1, `.default` 0); gender = `gender` (`.male`/`.female`; `.unspecified` is none);
     id = `identifier`.
   - Android: `tts.voices` with `locale.language == "en"`, `!isNetworkConnectionRequired`,
     and not `features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)`; tier =
     `quality` (500 down to 100); gender none; id = `name`.
   - Sort: tier desc, then the person's own language exactly (Apple
     `AVSpeechSynthesisVoice.currentLanguageCode()`, Android `Locale.getDefault()`), then the
     system default where the platform says (Android `tts.defaultVoice`), then display name,
     then id. **Change from today's Apple order** (language before quality): quality now leads,
     as on the web, so the largest part gets the best voice. Golden this order in a test.
3. **`autoCast(parts, voices)`**, parts in `Relay.castParts` / `castParts` order (largest
   first, then sound, then directions). Port it line for line:
   - non-speaking parts → `none`;
   - speaking parts: a pool = the voices in order; take index 0, except when a gender was
     taken before, take the first remaining voice whose gender is known and differs; record
     the taken voice's gender when it has one; when the pool empties, refill it and move to the
     next pitch in `[1.0, 0.86, 1.14, 0.93, 1.07]`;
   - it reads **nothing** of a part but its place: no name, no title, no line, no cast list.
4. **`resolve(entry, part, voices, auto)`** → not read (engine `none`, or no voice on the
   device: say which), or read with `voice`, `rate`, `pitch`, `missing`: when the entry's voice
   is not on this device, `voice` is the part's auto-cast voice (else the best), `rate` stays
   the person's, `pitch` is the auto-cast pitch, and `missing` is the entry's `name`.
5. **`VoiceCast` (the caster)**: `init(key:, seed:, parts:, voices: () -> [Voice], store:)`.
   `ensure()` fills every part without an entry by auto-cast **only when there is at least one
   voice**, keeps every existing entry, and saves when anything was added (or when the key had
   no cast yet, starting from the `seed` key's cast). `resolve(part)`, `entry(part)`,
   `set(part, change)` (merges into the current entry and saves), `recast()` (auto-cast over the
   voices now, replacing the cast).
6. **Storage**: one key `ed.cast` holding `{ "<key>": { "parts": {...}, "at": ms } }`, the
   newest 80 kept. Keys `p:<production id>` and `s:<script id>`; a production's caster seeds from
   its script's. Apple `UserDefaults.standard` (tvOS too; never Application Support on tvOS);
   Android `SharedPreferences("ed.cast")`. **Not** in `production.json`, not in the Worker's
   production, not in iCloud / Firestore sync (Q8). Deleting a production forgets its key.

## 2. One cast everywhere (both stacks)

Today each player keeps its own `assigned[part] = assigned.count` map (Apple
`SystemStandInVoice`, `SystemListenSpeaker`; Android `SystemStandInVoice`, `LiveListen`), so a
part changes voice between the recorder and the listen-through (R2 §8 item 1). Replace every
one with the caster:

- Apple: `SystemStandInVoice(cast:)` and `SystemListenSpeaker(cast:)` (both `nonisolated`
  where they are today; the caster is a value read on the main actor and passed in, or an
  actor-safe snapshot of `[PartID: Resolved]` taken when the session starts and refreshed on
  `set`). `utterance.voice = AVSpeechSynthesisVoice(identifier: r.voice.id)`, **never**
  `AVSpeechSynthesisVoice(language:)` (iOS 26 ignores the person's Settings choice there);
  `utterance.pitchMultiplier = r.pitch`; `utterance.rate = min(max, default * r.rate * sessionRate)`.
  Personal Voice is untouched: when the listen-through's toggle is on, it wins over the cast,
  through `speak` only.
- Android: `SystemStandInVoice(context, cast)` and `LiveListen(context, folder, cast)`:
  `tts.voice = voice`, `tts.setPitch(r.pitch)`, `tts.setSpeechRate(r.rate * sessionRate)` per
  utterance (they are engine-wide settings, so set them before every `synthesizeToFile` /
  `speak`).
- `Relay.listenPlan(p, script, reads:)` (Apple) / `listenPlan(p, script, reads)` (Android): an
  optional predicate; a non-speech line without a usable take enters the plan as a voice entry
  only when `reads(part)` is true. Default nil keeps every existing golden unchanged. The
  listen-through passes `{ !isSpeaking($0) && cast.resolve($0).read }`. The recorder's
  `runPlan` and cues never read directions or sound.
- The picker's preview and the reader's table read use the same caster.

## 3. Apple UI (iOS, iPadOS, macOS)

1. **Chip.** In each part card (`PlaysGrammar.swift`'s part card) whose part no person holds
   (status open and no usable take), the status line becomes a `Button` with the voice's
   `name`, `.font(.caption)`, `.tint` the link color, a trailing `chevron.down` (small), and a
   leading `exclamationmark.triangle.fill` in the warning color when `missing`. "Not read" for
   directions and sound until given a voice, "No Voice" when the device has none. When the part
   has a non-1 rate or pitch, append it muted: "1.2×, pitch −1" (pitch shown as steps of 0.1).
   Accessibility label: "Voice for COL: Ava (Premium)"; with a missing voice, "Allison
   (Enhanced) is not on this device; Zoe (Enhanced) reads instead".
2. **Picker.** iPhone: a push (`navigationDestination`) from the cast sheet; iPad: `.sheet` with
   `[.medium, .large]` detents; Mac: a pop-up `Menu` of voices in the row plus "Voice
   Settings…" opening a popover with the same `Form` (macOS-DESIGN §4.5c). The `Form`:
   - the missing-voice warning as the first row when there is one ("Allison (Enhanced) is not
     on this device.");
   - **Speed** `Stepper` (0.5× to 2× by 0.1, shown "1.0×") and **Pitch** `Stepper` (−5 to +5,
     shown "0", "+1", "−1"), disabled while the part is Not read;
   - section **On This Device**: "Not Read" first for directions and sound, then every voice
     (`name`, its `language` as a secondary caption), a checkmark on the current one (the
     fallback voice when the chosen one is missing), and a `play.circle` button that `speak`s
     **the part's first line** (`Relay.linesFor(script, part).first`'s spoken text) in that
     voice at the part's rate and pitch; tapping again stops; leaving the picker stops;
   - section footer: "Add voices in Settings > Accessibility > Spoken Content > Voices." and a
     button **Open Settings** (`UIApplication.openSettingsURLString`; no API lists or downloads
     voices). Verify the iOS 26 pane name on the iPhone before shipping (R2 §2.7 marks it
     UNVERIFIED) and write the true path into iOS-DESIGN §4.12c.
   - Every change is kept at once (`set`); no Save.
3. **Recast All** joins the cast sheet's manage actions (with Discard Unused Takes). Selection
   haptic on a voice change.
4. **The reader** (`ScriptReaderView`, once the reader port lands): a **Voices** toolbar item
   (`person.wave.2`) opening a sheet that lists every part with its chip (`s:<script>` cast) and
   Recast All; **Hear the Cast** (`play.fill` / `stop.fill`, label from regular width) reads from
   the first line on the page to the end through a `TableRead` port, `follow(lineID)` on each
   line, and a one-line "Device voice · BIJAH" strip in the dock slot while it reads; Close
   stops it.
5. **voiceschanged**: `AVSpeechSynthesizer.availableVoicesDidChangeNotification` repaints the
   chips and the picker (a voice downloaded in Settings appears on return).

## 4. Android UI

1. **Chip**: an `AssistChip` in the part card's status slot, the same words and states as §3.1,
   `Icons.Outlined.Warning` for missing, TalkBack description as on Apple.
2. **Picker**: a `ModalBottomSheet` (full height on a phone, `skipPartiallyExpanded = false`):
   the warning, Speed and Pitch as − value + `OutlinedIconButton` steppers, then "On this
   device" as `RadioButton` rows with a play `IconButton`. A voice's label: Android engines name
   voices like `en-us-x-sfg-local`, which says nothing; show `locale.getDisplayName()` plus, when
   two voices share a locale, a number in sort order ("English (United States) 2"), and the
   quality as the engine reports it only when it is 400 or more ("High quality"). Never show the
   raw name except to TalkBack as a hint.
3. **Get more voices**: a `TextButton` that starts
   `Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA)` (catch `ActivityNotFoundException`;
   hide the button when no activity resolves).
4. **Recast all** in the cast sheet's actions; the reader's Voices and Hear the cast as §3.4 in
   Compose idiom (a top-bar `IconButton` `RecordVoiceOver`, a bottom-bar `TextButton`).
5. **Voices changing**: re-read `tts.voices` on `onInit` and on resume (no broadcast exists).
6. Android TV reads the cast in its listen-through; no picker (tvOS-DESIGN §4.13's rule).

## 5. tvOS

The TV's listen-through builds a `VoiceCast` over the TV's voices with the `p:` key and reads
through it; there is no picker and no Voices. Each device keeps its own cast.

## 6. Tests (each seen to fail first, then fixed)

Port `js/voice-cast.test.js` case by case; a fake synthesizer / fake voices, nothing spoken:
1. Castable order golden (Premium, Enhanced, own language, default, name), ids not languages.
2. Auto-cast deterministic; distinct voices; the largest part gets the best voice; sound and
   directions `none`.
3. **Renaming every part changes nothing** (e.g. "LADY MACBETH", "MRS. GIBBS", "FATHER BROWN").
   Plus a source scan: the auto-cast function reads no title, role, name or line.
4. Gender alternation on Apple-reported genders: voices a(f) b(f) c(m) d(none) e(m), four parts
   → a, c, b, e. Android: a test that a list with no genders casts in plain order.
5. Fewer voices than parts: the third part repeats the best voice at pitch 0.86.
6. **One cast everywhere**: a recorder stand-in cueing MOLLY then DOC, and a listen-through
   starting with FIBBER, read MOLLY and DOC in the same voices. Control: two players without the
   caster disagree. Run it against today's code first; it must fail (on the web: Samantha in the
   recorder, Ava (Premium) in the listen-through).
7. A choice is read by another player built later; rate times the session rate, pitch; Recast
   all restores auto-cast.
8. Directions Not read until given a voice; then the listen-through reads them in that voice
   with the italic marks stripped; sound stays Not read.
9. A missing voice falls back to the auto-cast voice with `missing` named; the choice is kept;
   it returns when the voice does; a `kokoro` entry falls back the same way.
10. No voices: nothing cast, nothing stored, nothing spoken; voices arrive → auto-cast runs and
    is kept.
11. A production seeds from its play's cast; changing it leaves the play's alone; 80 keys kept;
    the sync code never names `ed.cast`.
12. The never-stored guards (`StandInNeverStoredTest`, Apple's synthetic-buffer guard) still
    pass with the caster in place.

**Frames** (real devices, read every one): the cast sheet with chips, a missing-voice chip, the
picker (light and dark, smallest and largest Dynamic Type / font scale), the directions picker
with Not Read checked, the reader's Voices and Hear the cast running. iPhone 12, iPad (sheet
detents), Mac window narrow and wide, Pixel 8a. A preview pressed on a device is audible: ask
first.

## 7. PARITY and docs when each port lands

Update the PARITY rows "Voice casting" and "Hear the cast" with the files, the test names and
the frames' date; turn the platform's ⏳ to 🚧 (✅ only after the owner hears it on a device).
Correct the platform design doc if the build differed from it, the same day.
