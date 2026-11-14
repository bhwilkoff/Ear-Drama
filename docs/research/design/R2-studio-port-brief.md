# R2 studio port brief: the studio inside the reader on Apple and Android (Decision 076, S3)

The web shipped the studio first (2026-11-14, commit 54d1dd0). This brief is the spec for the
Apple (iOS, iPadOS, the iPhone Duo, macOS) and Android ports. It binds nothing new: the rules
are PLAYS-DESIGN §2.9 (the verbs) and each platform's design doc (iOS-DESIGN §4.15 "The studio",
macOS-DESIGN §4.7, ANDROID-DESIGN §4.17; tvOS-DESIGN §4.13 says the TV has none). Where this
brief and a design doc differ, the doc wins; fix the doc first.

The owner, 2026-11-14: *"The recording experience should allow you to read the script as you
would any book or script while you record your lines. It should be easy to go back and forth
within the script and rerecord any line that you'd like to do another take with. ...
Additionally, on an iPhone Duo with the screen open, you should be able to see the script on one
side and the recording featueres on the other."*

**Before you start.** The reader (S1) and the voice cast (S2) must be on the stack: Apple has
both (`ScriptReaderView`, `VoiceCast`); Android has the reader (`ReaderScreen`) and S2 is ⏳, so
on Android port S2's `VoiceCast` first or cue the stand-in through the existing per-session voice
and note the gap. Real devices only (iPhone 12, iPad, the Duo closed and open, a Mac window;
Pixel 8a); never a simulator or emulator. Ask before any audible run; the mute door
(`APP_MUTE` / `?mute=1`) silences cues, takes and the mix. Press the keys yourself.

**The web reference** (port behavior, not idiom):
- `js/studio-core.js`: `startLine`, `lineState`, `productionFor`, and `create()` (the
  controller: `current`, `select`, `move`, `primary`, `again`, `keep`, `takes`, `choose`,
  `deleteTake`, `unused`, `deleteUnused`, `kept`, `onFollow`). No DOM; port it to Core
  (`StudioCore.swift`) and to `plays/StudioCore.kt` as plain types.
- `js/studio.test.js`: every case below, against the shipped session with fakes.
- `js/plays-core.js`: `deleteTake(p, takeID)` (refuses the chosen take) and
  `discardUnused(p, lineIDs?)` (one part's lines when given).
- `js/plays-session.js`: one addition, `onPhase` (a second observer of every phase change).
- `js/studio.js` (the view) and `tools/web_fit_studio.py` (the frames and the gate).

---

## 1. Core (both stacks)

1. **`Production.deleteTake(takeID) -> [Take]`** (Apple `mutating`, Android returning
   `Pair<Production, List<Take>>` like `discardUnused`): removes the take only when it is not
   its line's chosen take; returns what went so the files are deleted. The chosen take is
   refused (empty result). `PlayFiles.deleteTake(id, takeID) -> Bool` deletes the file and saves.
2. **`Production.discardUnused(lines: Set<String>? = nil)`**: the existing method gains an
   optional line set; with it, only unchosen takes on those lines go. The cast sheet still
   calls it with none. `PlayFiles.discardUnusedTakes(id, lines:)` returns the count.
3. **`RecordingSession.onPhase`** (Apple: a closure property, `@MainActor`; Android: a
   `(Phase) -> Unit` or collect the existing `StateFlow` of the phase): called on every phase
   set, before the screen's own observer. The studio follows `cue` and `listening` lines with it.
4. **`StudioCore`**, a port of `js/studio-core.js`:
   - `startLine(production, script, part, ask)`: `ask` when it is one of the part's lines, else
     the part's first line with no usable take, else its first line.
   - `lineState(production, lineID) -> (state: none|chosen|flagged, takes, chosen)`; `chosen` is
     the 1-based index of the chosen take among the line's takes (oldest first).
   - `productionFor(productions, isShared, script, part)`: the newest unshared production of
     this script where the part is `recording` (continue); else the newest where it is `open`
     and no part records (take it); else make one.
   - The controller over a session: `current` (a line id of the part), `select(id)` (refused
     for another part's line and while busy or in a run), `move(±1)` (my next / previous, never
     wrapping), `primary()` (Run through: start from `current` or pause; otherwise stop
     listening, cancel the cue, or record `current`), `again(lineID?)` (a new take, chosen),
     `keep()` (Step's review: back to idle and `current` = my next line; a run's review:
     `keepRun`), `deleteTake`, `unused()`, `deleteUnused()`, `kept()`. While a run plays or
     the microphone is open, `current` follows: the line being recorded, or my next line at or
     after the line being heard.
5. **Tests, each seen to fail first** (mirror `js/studio.test.js`, same fixture: MOLLY 5 lines,
   FIBBER 3, DOC 1): the start line; the three take states; move by my lines only; Step keep
   moves on; Line by line stays; Run through follows and records every line of mine from
   `current`; Record again keeps the older take and chooses the new; only an unchosen take can be
   deleted (its file too); Delete unused is one part's; `deleteTake` / `discardUnused(lines:)`
   directly; `productionFor`'s five cases. Mutants to show failing: Keep not advancing,
   `deleteTake` without the chosen refusal, `discardUnused` ignoring its lines, `addTake`
   replacing a line's takes. The existing mode goldens (`RecordingModeTests`,
   `RecordingModesTest`) must pass unchanged.

## 2. The reader gains the studio (both stacks)

- **One seam**: Apple `ScriptReaderView(script:, startLine:, studio: StudioTarget?)` with
  `struct StudioTarget { let production: String; let part: String }`; Android
  `Route.Reader(scriptId, lineId?, productionId?, part?)`. The script is the production's own
  copy (`PlayFiles.script(for:)`), never the library's, so line ids match the takes.
- **Doors**: the cast sheet's Take Part, Record and Open Part open the reader with the studio
  (replacing `RecordingScreen` / `Recorder`'s push; keep their files until the studio is seen
  on a device, then delete them in a follow-up). A shared production's part that is not this
  person's keeps its read-along. **Record** in the reader's bottom bar appears once a part is
  chosen (SF Symbol `mic`, Material `mic`), runs `productionFor`, takes the part if needed, and
  reopens the reader with the studio.
- **In studio mode** the reader's bottom bar is the transport: I'm Playing, Next Line, Hear the
  Cast and Record step aside; Hide My Lines and the page count stay. The cast the reader reads
  is the production's (`VoiceCast` keyed by the production).
- **On the page**: after each of my lines' speaker name, the take state (Apple `circle` /
  `circle.fill` + count in the hue / `exclamationmark.triangle.fill` in the warning color;
  Android `radio_button_unchecked` / a filled circle + count / `warning`), a button: make
  current, open the take list. VoiceOver/TalkBack labels: "No take", "3 takes, take 2 chosen",
  "Re-take: the microphone heard the device voice". The current line outlined in the primary
  ink; dashed record red while its cue plays; solid record red while the microphone is open.
  **My lines never split across pages in the studio** (paginate my lines as unbreakable blocks
  when the studio is attached; a line longer than a page still breaks), so the line being
  recorded is whole on screen; an 8 pt head and foot inset keeps the outline from being clipped.
- **A tap on one of my lines** makes it current and does not turn the page (the outer-fifth
  tap zones still turn pages elsewhere). J / K (hardware keys) and Previous / Next move by my
  lines and turn to the page.
- **The dock** (compact): the mode `Picker(.segmented)` / `SingleChoiceSegmentedButtonRow`,
  disabled while busy or in a run, the last mode kept per device as today; one status row:
  "Line 3 of 44" and a takes button ("Take 2 of 3", "No take", "Re-take") that opens the take
  list; during a cue the speaker in the hue and "Device voice"; while listening "Recording 0:03"
  in record red and the live meter. Before the first take the row is the gate: signed out
  ("Recording needs an account." and sign-in; offline, sign-in disabled and "You are offline."),
  the route check and headphones request (Apple and Android can see the route: refuse as
  §4.3 says, no checkbox), Start Recording, room tone with its countdown, a refused or missing
  microphone in the error color.
- **The transport**: Previous, the round record control (record red, 52 pt / dp; Stop while
  listening; Cancel in ink while a Step or Line by line cue plays; "From here" in Run through,
  Pause or Stop during a run), Next. Step's review: Again, With Cue, Keep. A run's review:
  Discard the Run, Keep N Takes. On a phone the review hides the page count and the Studio
  button so the three fit at 320 pt.
- **The panel** (one view, two homes): the part's name in its hue and "K of N"; **Takes** for
  the current line (oldest first: a radio to choose, "Take 2" over its length, Play, With Cue,
  Delete on unchosen takes only; then Record Again); during a run's review the run's takes
  instead (Play with cue, Again); **Cast** (the S2 cast list with chips and the picker);
  **Listen Through From Here** (the listen plan from the current line; the reader follows);
  **Delete Unused Takes** (confirmation naming the count; hidden when there are none); **Done
  With This Part** (enabled when every line has a usable take; shared parts finish on the cast
  sheet); the keys (only where there is a keyboard).
- **Where the panel lives**:
  - iPhone, closed Duo, a compact iPad window: a sheet (`.presentationDetents([.medium,
    .large])`) from a Studio button (`Label("Studio", systemImage: "slider.horizontal.3")`) in
    the bottom bar and from the status row's takes button.
  - iPad and the open Duo once the reader holds 860 pt (`onGeometryChange`, never the idiom):
    an `HStack` with the reader and a 340-380 pt trailing pane with a divider; the reader
    re-paginates in what is left (two facing pages only if it still holds 860). The Duo open is
    867-951 pt beside its strip, so the open Duo gets one page plus the studio; that is the
    owner's "script on one side and the recording features on the other". In S4, on iOS 27.1,
    `ArrangementView { reader } secondary: { studio }` with `.arrangementViewStyle(.split.axes(
    .horizontal))` behind `if #available(iOS 27.1, *)`; keep toolbar items as `Label`s so they
    move into the Duo's vertical strip.
  - Mac: the reader window's `.inspector` (⌥⌘I), 320-380 pt; a **Recording** menu
    (`.commands`) with Space, J, K, R, Return and the inspector toggle.
  - Android compact: a `ModalBottomSheet`. Expanded (860 dp or more):
    `SupportingPaneScaffold` (main pane the reader, supporting pane the studio); tabletop
    posture puts the dock below the hinge (`currentWindowAdaptiveInfo().windowPosture`).
- **Keys** (iPad keyboard, Mac, Android hardware keyboard and pedals): Space record / stop /
  cancel (Run through: start / pause); J / K my next / previous line; R record again; Return
  keep in a review; the arrows and Page keys keep turning pages. Captured before the player's
  own Space / J / K (the web found the player listening for them).
- **Leaving** the reader ends the session and stops the microphone (`session.end()`), as
  leaving `RecordingScreen` does.

## 3. Verify

- Unit tests (§1.5) on each stack, seen to fail, then pass; the existing plays suites unchanged.
- Frames, muted, on devices: iPhone 12 (compact: the gate, idle dock, recording, the take list
  sheet, Step's review), the Duo closed (compact) and open (the two-pane studio), iPad
  landscape (two panes), a Mac window narrow and wide (inspector), Pixel 8a portrait, light and
  dark. Read every frame before reporting. A refused microphone (revoke the permission in
  Settings) shows the refusal.
- Real input: a tap on a line selects it; a hardware Space records and stops; J / K move; the
  take list's Delete is absent on the chosen take; Delete Unused asks first.
- PARITY: move the Apple, Mac and Android cells of "Studio inside the reader" from ⏳ to 🚧
  with what was seen, and the three-modes row's notes.

## 4. Known on the web (do not copy)

- The web's headphones check is a checkbox because a browser cannot see the route; Apple and
  Android check the route and refuse (PLAYS-DESIGN §4.3).
- The web's bleed check is level only; Apple and Android correlate (§4.1), unchanged.
- At 320 px the web's reader bar truncates the part's name to two letters once Record joins
  it; give the part picker its own width on phones.
