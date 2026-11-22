# Voices port brief: Settings > Voices and Defaults on Apple and Android (Decision 086)

The web shipped this first (2026-11-22). This brief is what the Apple (iOS, iPadOS, macOS; tvOS reads only)
and Android ports must do, file by file, to reach the same verbs in each platform's idiom. Binding: DECISIONS
086, PLAYS-DESIGN §2.8 rules 4, 5, 6, 10 and 11, WEB-DESIGN §4.11a (the web's idiom, for reference only).

Owner, 2026-11-22: *"I thought we started allowing for multiple different voices to be downloaded/used with
the recordings. It seems like everything is still using super robotic voices that no realistic person would
want to use to listen to a play (or having other characters reading the lines as you record your own). Can we
make it easier to use the high-fidelity voices and how to implement them as a default from the settings tab vs
from the individual play that you are casting?"*

## 1. What changes in the model (both stacks, mirror `js/voice-cast.js`)

The web's reference is `js/voice-cast.js` (`loadDefaults`, `saveDefaults`, `usesVoice`, `ordered`, `poolOf`,
`move`, and `caster`) and its tests in `js/voice-cast.test.js` (the four tests under "The device's voice
defaults") and `js/kokoro.test.js` ("the Default casts downloaded voices first"). Port the tests first and see
each fail on today's code.

1. **Voice defaults**, stored on the device only, never synced: `{ order: [String], off: [String: Bool], rate: Double }`,
   keys `"<engine>:<voice id>"`. Apple: `UserDefaults` key `ed.voices` (beside `ed.cast`). Android: the same
   SharedPreferences file as the cast, key `ed.voices`. Normalize on read (drop non-strings, clamp rate 0.5 to 2).
2. **`ordered(voices, defaults)`**: Kokoro before system (engine rank), then the person's order, then the
   incoming best-first order. **`poolOf`**: `ordered` less voices not used; if that is empty, all of them.
   **`usesVoice`**: the person's tick if set, else `!voice.offByDefault`. Kokoro voices with a grade under C-
   (D+, D, D-, F+: Jessica, River, Echo, Eric, Liam, Onyx, Santa, Adam, Alice, Lily, Daniel, Lewis) carry
   `offByDefault = true`. Sort Kokoro voices by Kokoro's grade list `A, A-, B-, C+, C, C-, D+, D, D-, F+`, then
   the table index (the web's `KokoroVoice.GRADES`).
3. **`move(voices, defaults, voice, by)`**: swaps within the voice's engine group and writes that group's full
   order to the front of `order`.
4. **The caster keeps only choices.** Delete `ensure()`'s write-back (Apple `VoiceCast.swift` `ensure()`,
   Android `VoiceCast.kt` `ensure()`): `resolve(part)` = the stored choice if any, else
   `autoCast(parts, poolOf(allVoices, defaults), rate: defaults.rate)[part]`, with `isDefault = (no choice)`.
   Add `choice(part)`, `defaultEntry(part)`, `reset(part)` (drop the choice), and make `recast()` save an empty
   cast (every part back to Default). `set(part)` merges into the choice, else into the Default entry.
   Auto-cast gains a `rate` argument applied to each speaking entry.
5. **Old rows are not choices.** Rows written before this have auto-cast in them. Version the row
   (web: `{ v: 2, parts, at }`); a row without `v == 2` reads as no choice. Apple `VoiceCastBook.load` and
   Android `VoiceCasting.load` gain the same check.
6. **The voices a cast sees**: one list, Kokoro (when downloaded and allowed) plus system voices. Today Apple
   and Android pass Kokoro separately as `downloaded` and auto-cast "casts system voices only" (comments at the
   top of both files): change both so the Default pool includes Kokoro, and fix the header comments.
7. **The system fallback** for a Kokoro line Kokoro cannot read: the part's Default among system voices only
   (`autoCast(parts, poolOf(systemOnly, defaults))`), as the web's `StandInVoice.systemFallback`.

Tests to port (each seen to fail first, then pass): the pool order with a fake Kokoro list and a fake device
list (Kokoro first; person's order; unticked dropped; all unticked = all), untouched parts at the default speed
and `reset`, a download reaching every untouched part while a chosen part keeps its voice, defaults persisting
and surviving a broken row, an old (unversioned) row read as no choice, and "a Default is never written into
the cast" (read a cast, then assert storage holds nothing for it). Negative controls as listed in the web
tests' headers.

## 2. Settings > Voices (the surface)

Contents and words are PLAYS-DESIGN §2.8 rule 11 and WEB-DESIGN §4.11a; same verbs, each platform's idiom:

| | iOS / iPadOS | macOS | Android | tvOS |
|---|---|---|---|---|
| Entry | A **Settings** row in Library under the account row (`NavigationLink` to a `Form`), titled "Settings"; section "Voices" | The app's **Settings scene** (`Settings { }`, Cmd-,) with a Voices pane | A **Settings** `ListItem` in Library under the account row, a Compose screen with a "Voices" section | n/a: reads the cast only; the TV's Defaults are its own system voices, best first |
| Kokoro | "Download Voices (151 MB)" (title case, the size from `kokoro-v3-apple-manifest.json`), progress, Cancel, Delete, attribution; until S6e is measured on an iPhone, a refusal ("This device can't run Kokoro voices yet.") behind the existing flag | same as iOS | "Download voices (126 MB)" (module + q8 model), `KokoroModule` states, Play's confirmation, progress, Cancel, Delete, attribution | n/a |
| Speed | `Stepper` 0.5x to 2x by 0.1 | `Stepper` | the picker's stepper | n/a |
| Order | `List` with `.onMove` (EditButton) and a Use `Toggle` per row; quality as the secondary text (Kokoro "Grade A"; Apple's `quality` enhanced/premium); Hear (a line of today's scene) | `List` with drag to reorder and checkboxes | `LazyColumn`, Move up / Move down icon buttons (or drag), `Checkbox` | n/a |
| Footer | "Add voices in Settings > Accessibility > Spoken Content > Voices." + Open Settings (as §4.12c) | System Settings path, as macOS §4.5c | "Your speech engine's settings add voices." + the engine installer intent | n/a |

Binding docs to amend before building (the rules they replace are quoted there): iOS-DESIGN line "There is no
Settings tab or gear" (a Settings row in Library is not a tab or a gear; say so), macOS-DESIGN §2.3 "No
Settings scene" (replace: Voices is the first preference), ANDROID-DESIGN §4.11 "Android has no Settings screen
and gets none for this" (replace for Voices). Each platform's cast-sheet section (iOS §4.12c, macOS §4.5c,
ANDROID §4.9b): the picker's first row **Default** (naming what it reads now), Downloaded above On this device,
the picker's own Download button removed (Settings owns it), a chip on its Default says "Default", Recast all
returns every part to Default, and one quiet **Better voices** (opens Settings > Voices) on the cast sheet and
the reader's Voices while Kokoro could run here and is not downloaded.

## 3. Gates (unchanged by this decision)

- Android: Kokoro on in release (S6a passed); the engine module is fetched on demand with the model. Nothing new.
- Apple: Core ML S6e stays flag-only until the iPhone 12 measurement passes; until then Settings shows the
  refusal and the Default pool is system voices only. When the flag flips, nothing else changes.
- Never a stored synthetic line (Decision 076; `StandInNeverStores*` tests stay green).

## 4. Verification

Apple: `xcodegen generate`, the macOS test run (report "Test run with N tests"), generic iOS and tvOS builds,
0 warnings, `tools/test_apple_design_rules.py`; frames of Settings > Voices on the iPhone 12 and the Duo
(not downloaded, downloading, downloaded, refused) and the cast sheet with Default chips, read before
merging. Android: `:app:testDebugUnitTest :app:assembleDebug :app:lintRelease`, frames on the Pixel 8a.
No simulator, no emulator; nothing played aloud (muted doors, stubbed engines).

PARITY: update "Voice casting" and "Downloadable voices (Kokoro)" from ⏳ VOICES-PORT-BRIEF to 🚧 with the
evidence.
