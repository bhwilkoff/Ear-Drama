# R2: The script reader and studio, re-judged against the owner's words (2026-11-15)

The owner, 2026-11-14:

> *"I would like for people to get excited about recording new Ear Dramas ... We need to design
> for this (with design pattern research) rather than just bolt this functionality on to the app."*
>
> *"You should be able to read a script and turn pages and mark them up and do all of the things
> that a good book/script reading experience should contain. The recording experience should
> allow you to read the script as you would any book or script while you record your lines. It
> should be easy to go back and forth within the script and rerecord any line that you'd like to
> do another take with. The virtual voices who play the different parts should also be intuitive
> (before humans re-record them)."*

Scope: the studio as shipped by Decision 076 S3 (the reader with the studio attached), walked the
way a first-time person walks it: Record, a play, Take part, the reader, the headphones gate, a
first take, hear it, go back and retake one, listen through. `R2-design-review.md` already judged
Home and the Record tab and is not repeated. Lenses: `learning-orientation-design`,
`mobile-first-density-design`, `native-platform-first`, `binding-design-doc-discipline`, and the
research in `R2-script-reader-and-studio.md` §4.3 and §4.4, which this review holds the build to.

**Frames.** `tools/web_fit_studio.py --shots` (headless Chrome, muted, `speechSynthesis` and the
microphone stubbed: nothing heard, nothing recorded from a real microphone), signed out, on the
bundled play the harness picks (After Taps, part POLLY, 85 lines), at 375 and 1440 px, light and
dark: 28 frames before (`build/review-studio/before/`), 40 after at 320, 375, 430 and 1440
(`build/review-studio/after/`). Five are kept in `img/r2-studio/`. I read every frame named here.
Not judged on a device in this pass (see "What I could not observe").

---

## Findings, ranked by how much they block "excited to record" and "easy to go back and retake"

### F1. Going back to retake a line in Run through starts a run (blocks retake; built)

*"It should be easy to go back and forth within the script and rerecord any line that you'd like
to do another take with."*

Run through is the mode a newcomer meets first (PLAYS-DESIGN §2.4: "The recorder opens in Run
through the first time"). Tap a line three back and press the round control: it is labeled
"From here" only to a screen reader (`aria-label`/`title`); on screen it is the same red dot as
in the other modes, and it starts a **run** from that line, playing on through every later line
and opening the microphone on each of yours. The only single-line retake was `R` on a keyboard
or the take list behind the badge. And a single take started by `R` in Run through could not be
stopped: the round control stayed a disabled "From here" while the microphone was open, and
Space was ignored (`StudioCore.primary` only paused runs). Frame:
`img/r2-studio/before-idle-375.jpg` (Run through, Line 1 of 85, no way to retake one line).

**Built:** in Run through with no run on, a line holding a take shows **Again** in the status row
(the record outline, before its takes); it records that line alone. While that single take's cue
plays the round control reads Cancel, while the microphone is open Stop, and Space does the same
(`primary()` stops or cancels a single take instead of starting a run). The three modes and the
first-run default are unchanged. After: `img/r2-studio/after-again-375.jpg`.

### F2. Hearing your take in the scene is buried (blocks "excited"; built)

*"I would like for people to get excited about recording new Ear Dramas."*

The payoff of a take is hearing it answer the other voices. **Listen through from here** existed,
but at 375 px it sat in the Studio sheet below the take list and a cast list of 17 parts, and at
1440 px it was below the fold of the side panel, under the same cast list
(`img/r2-studio/before-wide-1440.jpg`: the panel ends at GIBBS; the button is off screen). After a
take the bar offered Previous, Record, Next: nothing to hear. Punch-and-roll narration and Logic's
take folders (the research's §2.5) keep playback beside record for this reason, and the first
review's research (`R2-design-review.md` §2, Smule's duets) found that recording *with* a partner
is what draws a first-timer in: the partner has to be heard.

**Built:** the transport ends with **Listen from here** (a play icon; Stop while it plays,
disabled while a cue, the microphone or a run is on; a record press stops it first). One tap from
the page at every width. After: `img/r2-studio/after-listening-1440-dark.jpg`.

### F3. The virtual voices are invisible where they speak (blocks "intuitive voices"; built)

*"The virtual voices who play the different parts should also be intuitive (before humans
re-record them)."*

On the page, my lines carry a take ring; every other part's line carries nothing. Nothing says
that BIJAH will be read by a device voice, which voice it is, or how to change it. The voice is
chosen in a list two levels away (the Studio sheet's Cast, or the top bar's unlabeled Voices
icon), by part name, away from the words it will read. R2 §4.3 specified "Other parts' lines carry
who voices them ... the dashed ring for a device voice" and §4.4 "A voice never looks like a
person: the chip is the dashed ring"; S3 shipped the take rings but not this.

**Built (PLAYS-DESIGN §2.9 rule 3a):** in the studio, each other part's line a device voice will
read carries the dashed ring in the part's hue with a waveform and the voice's short name ("Zoe").
A tap opens that part's voice picker, which previews the part's own first line in each voice. A
line with a human take shows nothing. After: `img/r2-studio/after-again-375.jpg` (BIJAH, the ring,
"Zoe") and `img/r2-studio/after-voice-375-dark.jpg` (the picker from the ring).

### F4. On a phone the page is a third dock (not built; for the owner)

*"read the script as you would any book or script while you record your lines."*

At 375 x 760 the studio's dock (mode segments, status row) and the transport take about 170 px,
and a page holds two or three speeches (`before-idle-375.jpg`: POLLY, BIJAH, one POLLY line, then
70 px of blank page because the next speech is kept whole). The mode control is on screen every
moment though it changes rarely. Folding it into the status row (a menu) would give the page back
about 50 px, but PLAYS-DESIGN §2.9 rule 6 and §2.4 call for the visible native segmented control;
that is the owner's call, not a fix.

### F5. "pitch −1" on a voice chip (not built; small)

The cast list's chips read "Ava (Premium) pitch −1" when auto-cast reuses a voice. It is a true
fact but in an engineer's words; "Ava, lower" would say the same. Left for the voices pass with
Kokoro (S6), where chips change anyway.

---

## Learning test (`learning-orientation-design`)

All three built changes give the person more of the act, never less: Again keeps every take (the
person chooses); Listen from here lets them judge their own reading in context; the ring makes the
machine's part visible and theirs to change, and labels it as a device voice (never a face). No
copy was written beyond the verbs "Again", "Listen from here" and the voice's own name.

## What was built where

| Fix | Web | iOS / iPadOS / macOS | Android |
|---|---|---|---|
| F1 Again in Run through, Stop / Cancel for a single take | `js/studio.js` (`.st-again-line`), `js/studio-core.js` `primary()`; `js/studio.test.js` case | `StudioController.primary()` (`StudioCore.swift`), Again in `StudioStatus` (`StudioViews.swift`); the round control already read Stop / Cancel from the phase; `PlaysTests` case | `StudioController.primary()` (`StudioCore.kt`), Again in `StudioStatus` (`StudioUi.kt`); `StudioTest` case |
| F2 Listen from here in the transport | `js/studio.js` (`[data-act=listen]`, `aria-pressed` while it plays) | `StudioTransport` (`play.fill` "Listen From Here", `stop.fill` "Stop") | `StudioTransport` (`PlayArrow`, `Stop`), via `rememberListenAction` |
| F3 Device-voice ring and name on other parts' lines | `js/studio.js` (`.rd-vc`), `css/styles.css` | `ReaderLayout.ringSpots` + draw (`ScriptPagination.swift`, placed like the take mark; a name too long for the gutter is cut with an ellipsis), `ReaderModel.studioRings` and the picker sheet (`ScriptReader.swift`), `VoiceChipText.short` | the reader canvas ring (`ReaderScreen.kt`, `GraphicEq`), `StudioCore.shortVoiceName` |

Every stack: a record press (the round control, Space, R, Again) stops a playing Listen from here
first, so recording and listening never overlap.

Gate: `tools/web_fit_studio.py` now fails on a missing ring (or one on my own line, or one with
no voice name), a ring that does not open the picker, no Listen from here in the transport, no
Again in Run through for a line with a take, and a single Run-through take with no Stop.

Verified 2026-11-16 (after the restart): `tools/test_web.sh` PASS (22 suites; `js/studio.test.js`
16 passed); `tools/web_fit_studio.py --shots` PASS at 320, 375, 430 and 1440, light and dark, frames
read (idle, Again, listening, the picker from the ring); macOS `xcodebuild test` 446 tests in 83
suites passed; `ReaderPageRenderTests` rendered the ring on The Philanderer as GRACE at 375 (light,
dark) and 1024 (gutter, light, dark), read; iOS and tvOS generic builds, 0 warnings;
`./gradlew testDebugUnitTest lintRelease` green (522 tests, 0 failures); `tools/test_us_english.py`
and `tools/test_design_tokens.mjs` PASS. The gutter render first showed a cut name with no
ellipsis ("Sama"); fixed in `ringSpots` and re-rendered ("Sam…").

## What I could not observe

No real microphone, no audible run (stubbed voices and microphone, muted Chrome). Android was seen
on the Pixel 8a (dark, muted, the stubbed engine, Caesar Rodney's Ride as RODNEY): the rings
beside PRUDENCE, a ring opening PRUDENCE's picker, Listen from here in the bar, and Again beside
"Take 4 of 4" in Run through (`build/review-studio/pixel/`, not kept in the repo). Apple is
verified by macOS tests, the iOS and tvOS builds and a render of the ring on the page; the
iPhone, the iPad and a Mac window were not looked at in this pass.

Seen on the way: on the Pixel, opening the studio door on a play whose part already records in a
production on the device first showed "A second production needs an account." over the studio
(PLAYS-DESIGN §2.9 rule 1 says the reader's Record continues that production); it may be the
DEBUG door's path rather than the reader's Record, and was not chased here.
