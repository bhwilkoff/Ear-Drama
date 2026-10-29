# D2b-2: Record a Line, rethought from research (2026-10-29)

The owner on D2: *"I also don't think we have gotten even close on the Record
a Line designs (on any of the designs)."* And on the create flow: *"the 'Start
an ear drama' on the Company design is exactly what we are trying to avoid
(undifferentiated/undesigned lists of text without any visuals or colors
whatsoever)."*

This file is the research, the interaction model, every state, and what it
would change in `docs/PLAYS-DESIGN.md` (binding). It changes no app code and
does not edit PLAYS-DESIGN: §8 below is the proposed rule change for the owner
to accept, after which the binding doc changes first and the build follows
(`binding-design-doc-discipline`). Skills followed: `catalog-experience-design`
(rule 8, making is a cast sheet, a prompter and a call sheet),
`mobile-first-density-design`, `learning-orientation-design`, and Decision 064
(On Air: red means recording; ink for actions; blue for wayfinding; genre hues
are content).

Prototype: `docs/research/design/directions/record/` (open `index.html?s=pick`
and press through; every state is also a frozen frame by `?s=<state>`). PNGs:
`docs/research/design/img/d2b-2/` (§9).

---

## 1. Verdict

What was wrong with every D2 recorder (`img/d2/{a,b,c}/create-record-375.png`)
was not its styling. It drew **one line on an empty page**: the scene partner
was a dim caption, the device voice looked like a person, nothing showed what
was about to happen, there was no sign that the microphone was listening, no
take to judge, and no sense of where you were in the part. The tools that help
an amateur perform one line well all do four things the old flow does not:

1. **They show the scene, not the line.** Karaoke and table-read apps keep the
   other voices on screen, each in its own place or color, and the line coming
   up visible before it arrives (Apple Music Sing's duet view; karaoke duet
   coloring; Off Book's script view).
2. **They make the cue a countdown.** ADR's streamer and three beeps, a
   teleprompter's countdown, Off Book's "friendly ding right before it's your
   turn": the performer always knows when to breathe in. In Ear Drama the cue
   line *is* the pre-roll, so it becomes a visible sweep that ends where your
   line begins.
3. **They make listening visible and quiet.** One red control (Voice Memos,
   Pixel Recorder), a live waveform while it records, and level advice only
   when it matters, never a red alarm (red is taken: it means recording).
4. **They judge a take in context.** A self-tape app replays the take; a
   rehearsal app plays the scene up to your cue. The useful review for a line
   of dialogue is the cue and your line together, then *Again* or *Keep*, and
   Keep moves straight into the next cue.

Direction D's visuals carry it: the performer and the scene partners are
**faces** (initials on their part's hue; a device voice is a dashed ring with
a wave, never a face), the play is a **bold hue block**, and the part's
progress and the play's shape are **strips** (the Almanac's data idiom). Red
appears only inside the recorder, only while the microphone is armed or open.

---

## 2. Findings, with sources

### 2.1 Teleprompters: the text follows the voice

- **PromptSmart**'s VoiceTrack "follows the speaker's words and pauses,
  adjusting scroll speed to match their pace"; if the speaker improvises,
  scrolling stops and resumes when they return to the script; recognition runs
  on the device ([App Store](https://apps.apple.com/app/id894811756);
  [Speech Technology](https://www.speechtechmag.com/Articles/News/Speech-Technology-News/PromptSmart-Launches-Teleprompter-App-with-Voice-Recognition---98763.aspx)).
  A comparison reports recognition-accuracy complaints
  ([teleprompter.com](https://teleprompter.com/compare/teleprompter-vs-promptsmart)).
- **Teleprompter Premium+** lists voice scrolling that highlights each word as
  it is spoken, a countdown before scrolling begins, adjustable font, size,
  line spacing and margins, and a cue marker ([listing](https://mwm.ai/apps/teleprompter-premium/6779357842)).
- **BIGVU**: multiple takes, choosing the best on a preview page after
  recording ([CapCut's guide](https://www.capcut.com/resource/bigvu-teleprompter);
  [G2 reviews](https://www.g2.com/products/bigvu/reviews)). No per-sentence
  retake was found.

**Steal**: the countdown before the words, and the size controls. **Refuse**:
scrolling by speech recognition. A line of radio dialogue is one to forty
words; it fits on the screen whole, so there is nothing to scroll, and a
recognizer that mishears would move the page under the performer.

### 2.2 ADR and voice booths: the cue tells you when

- A **streamer** "is a vertical line which appears on one side of moving
  picture ... and glides to the other side ... The line reaching its
  destination marks the moment the event occurs"
  ([SFU, Gotfrit](https://sfu.ca/~gotfrit/ZAP_Sept.3_99/s/streamer.html)).
- **Three beeps**: "three audio beeps ... spaced 20 frames apart prior to cue
  point ... to cue the actor to begin their line on the fourth 'imaginary'
  beep" ([Smart Post Sound spec](https://www.smartpostsound.com/_files/ugd/e953b2_a8b625e04b0a40de8c1edb072dd84373.pdf?index=true);
  [USC ADR notes](https://animation.usc.edu/student-portal/sound-resources/adr/)).
- **Pre-roll** is "some lead-in of previous lines/sounds/video before the
  recording starts" ([DVinfo](https://dvinfo.net/forum/all-things-audio/471358-adr-sanity-check.html)).

**Steal**: the streamer as a sweep under the cue line, filling as the cue
plays, ending as your line opens; the pre-roll as "Run-up" (two lines before).
**Refuse as a default**: the three beeps. ADR syncs to a fixed picture; Ear
Drama's pacing is "wait for me" (PLAYS-DESIGN §2.4, 08a §5.1), so there is no
fixed sync point to count toward. The cue's own last word is the beat.

### 2.3 Karaoke and dubbing: the line coming up, and whose it is

- **Apple Music Sing**: "animated lyrics that dance to the rhythm of the
  vocals"; "Vocal lines sung simultaneously can animate independently";
  "Multiple vocalists show on opposite sides of the screen to make duets ...
  easy to sing along to" ([Apple Newsroom, 2022](https://www.apple.com/newsroom/2022/12/apple-introduces-apple-music-sing/)).
- **Karaoke duet coloring**: PowerKaraoke's duet mode "changes the coloring and
  alignment of the text to visualize the change of a singer"
  ([docs](https://docs.powerkaraoke.com/link/79)); Youka lets you "give each
  singer their own color scheme", with shared lines as "Both"
  ([Youka duet editor](https://docs.youka.io/en/web/duet-editor.md)).
- **Smule** joins a recorded duet partner ([App Store](https://apps.apple.com/it/app/smule-sing-duet/id509993510));
  how it colors parts was not found in its own documentation.

**Steal**: the duet layout (partners' lines on one side, yours inset on the
other, each in its part's hue), and word-by-word lighting of the cue *when the
engine reports word boundaries*: the web's `boundary` event
([MDN](https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesisUtterance/boundary_event)),
Apple's `willSpeakRangeOfSpeechString` ([Apple](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer(_:willspeakrangeofspeechstring:utterance:))),
Android's `onRangeStart`, API 26 ([Android](https://developer.android.com/reference/android/speech/tts/UtteranceProgressListener)).
A human take has no word timing, so its cue shows the streamer only.

### 2.4 Table-read, rehearsal and self-tape apps

- **Off Book!**: "Record your script line by line"; "Cue My Line ... gives you a
  friendly ding right before it's your turn"; "Mute My Line ... the scene plays
  right up to your cue, then pauses just long enough for you to nail the
  line"; playback speed of castmates' lines; LineSync: "As castmates record
  their lines, the director hears them show up automatically"
  ([App Store](https://apps.apple.com/app/id1072004273)).
- **Rehearsal Pro**: record your lines, play them back while the script scrolls
  "like a teleprompter", or "blackout mode" to test yourself
  ([Backstage](https://www.backstage.com/magazine/article/apps-every-actor-use-4886/);
  [App Store](https://apps.apple.com/app/id1116896197)).
- **LineLearner**: "record the full scene, tag your lines, then switch to
  cue-only playback that inserts a precise pause where your dialogue should
  land" ([Artfolio review](https://www.artfolio.com/article/line-learning-apps-reviewed-which-tools-really-help-actors-lock-lines-fast)).
- AI scene-partner apps (CueUp, Linus, CastingNinja, ScriptReady) voice the
  other parts, "listen for your cue" and advance when you finish
  ([CueUp](https://apps.apple.com/ch/app/line-reader-cueup/id6762047987);
  [Linus](https://apps.apple.com/us/app/linus-learn-lines-self-tape/id6742599484?l=ar);
  [CastingNinja](https://www.producthunt.com/products/castingninja-2)).

**Steal**: the ding before your turn (as the `selection` haptic plus a soft
tone, PLAYS-DESIGN §7), partner speed, and the director's view filling in by
itself. **Refuse**: the AI partner as a performer. Ear Drama's device voice is
a scene partner only and is never kept (§5 of PLAYS-DESIGN; Decision 055).

### 2.5 Voice Memos, Pixel Recorder and GarageBand

- **GarageBand** (iPhone): "Tap the Record button"; "The ruler shows the area
  being recorded in red"; "If the level turns red, drag the slider down (or
  record the part again more softly) to prevent distortion"
  ([Apple](https://support.apple.com/guide/garageband-iphone/chs39283a21/ios)).
- **Voice Memos**: Replace records over a stretch from the playhead; Save as
  New Recording keeps both ([Apple, Mac](https://support.apple.com/guide/voice-memos/vmac7e39c22e/mac)).
- **Pixel Recorder**: a large red button, a live waveform and timer; pause
  turns into resume; save or delete after ([Pixel Tablet help](https://support.google.com/googlepixeltablet/answer/13587843);
  [9to5Google hands-on](https://9to5google.com/2019/10/02/google-recorder-hands-on/)).

**Steal**: one red control, a red live waveform as the "it is listening"
signal, and keeping every take (Ear Drama's takes are immutable, §8 rule 5).
**Refuse**: GarageBand's red for clipping. Red means recording (Decision 064),
so a level problem is the `warning` color, and only after the take.

### 2.6 Podcast recorders

- **Riverside** records each person locally, uploading as it goes
  ([Riverside](https://riverside.fm/blog/progressive-video-uploading)); guests
  keep the tab open until upload completes
  ([Riverside help](https://support.riverside.com/hc/en-us/articles/5456518076189)).
- Echo: hosts "strongly advise that both parties ... wear headphones", plug
  them in before opening the session, and prefer wired over Bluetooth
  ([Podcast Engineering School](https://podcastengineeringschool.com/echo-cancellation-in-zencastr);
  [The Four Top guest guide](https://thefourtop.org/guest-guide);
  [Riverside on echo](https://support.riverside.com/hc/en-us/articles/5460377113501-How-to-minimize-echo-in-the-Studio-and-on-my-recorded-tracks-even-when-Guests-are-already-wearing-headphones)).
- Levels: a mic-test tool reads good, too quiet, or clipping, with peaks below
  -20 dB as too quiet ([Castos](https://castos.com/tools/microphone-test/)); and
  do not frame a bad level as the guest's fault ([Get Your Best Broadcast Voice](https://shows.acast.com/get-your-best-broadcast-podcast-and-video-voice/episodes/0534-a-bit-for-level-please)).

**Steal**: headphones asked for before the session with the reason; the
level judged on the take, in words that suggest rather than blame ("Very
quiet. Hold the phone closer?").

### 2.7 LibriVox

LibriVox's dramatic works give each reader a part and an editor assembles
them; readers record a file per act they appear in, leave "at least 2-3
seconds of silence between each line", and proof-listeners check that "all
lines are recorded and none go missing"
([LibriVox wiki, dramatic readings](https://wiki.librivox.org/index.php/Dramatic_Readings_and_Plays);
[coordinating](https://wiki.librivox.org/index.php/Information_on_coordinating_dramatic_readings);
[forum guidelines](https://forum.librivox.org/viewtopic.php?p=1541866)).
The app already does the editor's slicing by recording line by line; what it
should steal is the proof-listener's question, answered on screen: which lines
of my part are still missing (the part strip, §3.3).

### 2.8 Accessibility for reading aloud

- WCAG 2.2.1 Timing Adjustable: a time limit the content sets must be
  possible to turn off, adjust, or extend ([W3C](https://www.w3.org/WAI/WCAG22/Understanding/timing-adjustable.html)).
  "Wait for me" pacing already has no limit; the device voice's speed is
  adjustable; nothing advances while a person reads.
- Dyslexia style guidance (secondary sources on the BDA guide): a large
  sans-serif, line spacing around 1.5, left-aligned unjustified text, lines of
  60-70 characters ([Dyslexia Scotland](https://dyslexiascotland.org.uk/dyslexia-friendly-typed-formats);
  [Wigan's style guide](https://www.wigan.gov.uk/Docs/PDF/Business/Professionals/SEN/HEFA/Dyslexia-Style-Guide.pdf)).
  Your line is set at 25 px (32 px on a desktop), line height 1.3, left
  aligned, inside a box that keeps it under 40 characters a line on a phone
  and about 55 on a desktop.
- Interruptions on Apple: an interruption posts `began`; `ended` is not
  guaranteed, so a recorder must check the session itself
  ([Apple, handling interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions);
  [Apple forums](https://developer.apple.com/forums/thread/776118)).

---

## 3. The interaction model, step by step

### 3.1 Pick a play (never a bare list)

- The shell's Library (and "Has a script" in Browse, unchanged) opens
  **Start an ear drama**. A production in progress leads, as a block with its
  cast's faces and "RODNEY · 5 of 76 lines" and an ink **Continue**.
- Then the plays, grouped **Radio plays** and **Stage plays**, each group
  ordered by a stated rule, "Shortest first" (a fact, not a ranking).
- Each play is a **bold block** in its genre hue (Sleeve): kind ("Radio
  play"), title in Big Shoulders, author with years; below it the **cast
  fingerprint**: one bar, every part's share of the play's words, largest
  first, in the part hues; then "about 26 min · 12 parts" and the three
  largest parts as initials.
- **The play's hue is data**: a rule over Project Gutenberg's own subject
  headings and shelves (`Comedy plays`, `Farce`, `Tragicomedy`, `Humour` give
  comedy; everything else drama). The bundle today yields only those two, so
  most blocks are drama's magenta. That is honest; the fingerprint is what
  tells a two-hander from Hamlet. New hues arrive with new sources (a mystery
  or western radio script), never by inventing a genre. The bundle needs to
  carry `subjects` (§8).

### 3.2 Claim a part: the playbill

- A hero block: the play's hue, title, author, length, the fingerprint, and the
  rights line linked to its evidence ("Public domain in the USA. · Project
  Gutenberg", the source's own claim, never ours).
- One row of actions that never wraps: ink **Listen through**, blue **Invite**.
- **Recording as Lou · Change**: the name asked once (D1c Pattern 3).
- The parts as a two-column playbill (four on a desktop), largest first. Each
  part card: a top rule in the part's hue, the name as printed, "about 7 min"
  and "97 lines" on two lines (never split at a dot), a **presence strip**
  (where in the play the part speaks, 48 bins), and who holds it: a face and
  "Pat / Recorded", "Sam / 12 of 44", or a dashed device-voice ring.
- The suggested part (largest open, C7) has **Take part** in ink outline; the
  rest in blue outline; your own part has an ink **Continue**. Red is not on
  this screen: opening the recorder is not recording.

### 3.3 The recorder (phone)

Top to bottom, at 320-430 px:

1. **Top bar**: close (down chevron), the part's name in display type, the
   play, and "5 of 76" (tabular).
2. **Part strip**: one tick per line of the part, filled in the part's hue
   when kept, the current one tall and ink (red while recording). Tap a tick
   to go to that line. Over about 110 lines a tick is a bin.
3. **Opposite you**: the partners in this stretch of the script, each a face
   with the part name and who voices it ("URIAH Pat", "PRUDENCE Device
   voice").
4. **The stage**, duet layout: the line before (dimmed, with "✓ Take 2" when it
   is yours), the **cue card** (partner's face, part, who voices it, the line
   as printed, directions in brackets and italics, the part's hue as its left
   edge), **your line** inset from the left in a large box tinted with your
   part's hue, then the next line, dimmed.
5. **Aids**, one row that never wraps: Run-up (the two lines before), Hear it
   read (the device voice reads your line once, never kept), and the device
   voice's speed (0.8×, 1×, 1.2×). Hidden, but holding their space, while the
   cue plays or the microphone is open.
6. **The dock**: previous line, the one red record control (76 px), next line.

### 3.4 One line, before, during, after

| Moment | What the performer sees | Hears | The control |
|---|---|---|---|
| **Ready** | The cue card and your line, still; the dock's red Record | Nothing | Record (red) |
| **Cue playing** | The cue card's streamer sweeps under the line; words light as the engine reports them (device voice only); your box gets a dashed red edge and "Next" | The cue: a human take, or the device voice live | Cancel (dashed red ring) |
| **Your turn** | At the cue's end: the `selection` haptic, a soft tone in the headphones (Off Book's ding), "Your line" announced to a screen reader before listening starts (§7 of PLAYS-DESIGN) | The tone | |
| **Recording** | Your box's edge turns solid red, a red "Recording 0:02" pill, and a red live waveform growing under the line over a faint band where speech should land; the strip's current tick turns red | Itself, if the route monitors | Stop (red square); the line-end detector usually stops it first |
| **Review** | The take as a waveform with its length ("3.1 s"), numbered take dots (chosen one filled in ink); a quiet-or-clipped note in the warning color only if the take is very quiet or clipped | Nothing until asked | Three equal buttons: **Again** (red outline: it records), **With cue** (blue: plays the cue then your take, the review that matters for dialogue), **Keep** (ink) |
| **Kept** | Keep moves to your next line and plays its cue at once, so a scene runs like a scene until you pause | The next cue | |

Return keeps, R records again, Space records or stops, the arrow keys move by
line (Mac, web, iPad with a keyboard). The rails on a desktop say so (a fact
the person cannot discover by looking).

### 3.5 Done with the part

When the last line is kept: a block in the part's hue, "RODNEY" large,
"✓ Recorded by you · 76 lines", **The cast so far** as faces (checked when
recorded, dashed when open), then one row: ink **Listen through** and blue
**Pass the phone**, and the suggested open part ("ANNOUNCER · Open · about 4
min · 10 lines" with **Take part**). Shared productions put **Upload N takes**
in the place of Pass the phone (PLAYS-DESIGN §11.7 rule 5). No confetti, no
streak, no score (§8 rule 6; `values-based-feed-ranking`).

### 3.6 Listen through

A focus screen: the play's hue block with the title and a **voice strip**:
the play in 48 bins, each as opaque as its share of lines with a human take,
so the listener sees how much of the play is people; the playhead in ink. The
cast as faces, the one speaking ringed in ink (never red: nothing records).
The script follows the playback, the current line lit in a card with its part's
hue. Every device-voice line keeps "Device voice" beside its speaker and a
blue **Take this part**: the listen-through is the invitation to perform.
Transport: previous line, ink play/pause, next line.

---

## 4. Every state

| State | Trigger | Screen | Words (only refusals, warnings, facts) |
|---|---|---|---|
| Signed out | Start recording, signed out | The preflight with sign-in in place of Start recording | "Recording needs an account." + the platform's sign-in |
| Headphones (web) | Each session | Headphones art, the reason, a checkbox, who you will hear; Start recording disabled until checked | "They keep the other voices out of your take. This browser cannot tell whether they are on." / "My headphones are on" |
| Headphones (native) | Route has no headphone output | The same, with the route as a fact; Check again; Record without headphones (Apple, Android: echo cancellation, `capture: "aec"`) | "Plug in headphones." |
| AirPlay route | Output is AirPlay | Refusal | "AirPlay delays sound too much to record. Choose headphones." |
| Bluetooth microphone | Input is HFP | The built-in or wired microphone is chosen; never a refusal the person must act on | none |
| Microphone denied | Permission refused | Mic-off art, an error box, Open Settings (native) or Try again (web) | "Ear Drama needs the microphone to record your part." (+ "Allow it for this site in the browser's settings." on the web) |
| No microphone | No input device | Same box | "No microphone found." |
| Room tone | First take of a session | A red ring counting 5 to 1, "Recording the room" pill (red: it records) | "Quiet, please" |
| Ready | | §3.4 | |
| Cue playing | Record, Again, Keep | §3.4 | "Next" |
| Recording | Cue ended | §3.4 | "Recording 0:02" |
| Review | Line end or Stop | §3.4 | the length |
| Quiet or clipped take | Peak below about -30 dBFS, or samples at full scale | Review with a warning note; Keep stays enabled (never a rejection, §8 rule 6) | "Very quiet. Hold the phone closer?" / "It crackled. A little further from the phone?" |
| Flagged take (bleed) | Bleed check fires | Review with the warning box; take dot in warning color; **Keep disabled** (a flagged take counts as missing, PLAYS-DESIGN §1 M7) | "The microphone heard the device voice. Record it again with headphones on." |
| Interrupted | A call, Siri, an alarm, the app backgrounded, the tab hidden, headphones unplugged mid-take | Back to Ready on the same line; the partial take is discarded, never saved | "Your headphones came out. That take was not kept." / "A call stopped the take." / "Recording stopped when the app left the screen." |
| Save failed | Write error, storage full | Review stays; error box | "This take was not saved." (+ "The device is full." when the OS says so) |
| Another part recording (shared) | The Worker's `another_part_is_recording` | The cast sheet's line, unchanged | "{Part} is still recording." |
| Uploads off (shared) | `uploads` false | Before anyone records | "Uploads are off." |
| Done with the part | Last line kept | §3.5 | "Recorded by you · 76 lines" |
| Listen through | Any time | §3.6 | "Device voice" on every unrecorded line |

---

## 5. Alone, with others, and the device voice

- **Alone**: every other part is the device voice: dashed rings in the
  partners' hues, "Device voice" on each cue, and words lighting as it reads.
  The point of the dashed ring is honesty: a stand-in never looks like a
  person (PLAYS-DESIGN §5 rule 3).
- **Pass the phone**: the next person sees the first performer's face where
  the dashed ring was, and hears their take as the cue.
- **Shared** (phase 2): the same faces, filled from the Worker's record when
  the production is opened; a part someone holds but has not finished shows
  their face and "12 of 44"; their kept lines are the cues.
- **Headphones**: asked before every session; the prototype's preflight lists
  who you will hear, so the reason is concrete. Bleed is checked on every take
  on Apple and Android (correlation) and by level on the web.

---

## 6. Platforms and sizes

| Size | Layout |
|---|---|
| 320-430 px phone | §3.3, one column; the dock and aids each one row at 320 px (measured, §9) |
| iPad | The script and the cast side by side (PLAYS-DESIGN §2): the stage in the middle, "In this scene" on the left, This line on the right, as the 1440 frames; the person waiting can follow along |
| Mac | The same three columns in a resizable window; Space, Return, R and the arrows; the rails list them |
| Android | Material 3, the same anatomy; a hardware key records or stops (PLAYS-DESIGN §7); the haptic is `selection` |
| Web | As the prototype; the headphones checkbox; boundary-lit device-voice words where the browser fires `boundary` |
| TVs | No recorder (unchanged); listen-through as §3.6 without Take this part |

Reduce Motion: no sweep, the streamer is replaced by the cue's words lighting
in steps, and the stage changes as a page per line. Dynamic Type: your line
scales with no truncation; the box grows.

---

## 7. The hardest choices

1. **No count-in by default.** ADR's three beeps are the most famous cue, but
   they exist because picture is fixed. Ear Drama waits for the performer, so
   the cue line itself is the count, made visible by the streamer, and the
   haptic plus a soft tone mark the beat. A count-in can be a setting later.
2. **Review in context, not alone.** "With cue" plays the partner's line and
   then your take, because a line of dialogue is right or wrong against the
   line before it. Keep goes straight into the next cue so a scene flows, at
   the cost of a person sometimes keeping too quickly (Again is always one tap
   from the take dots of any line).
3. **Red lives only inside the recorder.** Continue, Take part and Record on
   the cast sheet all open the recorder and are ink or blue; red is the record
   control, the armed edge, the recording pill, the live waveform, and room
   tone. A clipped take is the warning color, never red.
4. **Part hues skip drama's magenta.** The cast's colors are the seven other
   genre hues in largest-first order, so nothing next to the red control reads
   as red. The play's own hue may be drama; it stays on the play's block and
   the playbill, never in the recorder.
5. **The play's hue only from the record.** Two hues today is a truthful
   palette; variety comes from the cast fingerprint and presence strips, which
   are data, and from new sources later.
6. **A device voice is a dashed ring, never a face.** Even in the listen-through.

---

## 8. What this changes in PLAYS-DESIGN (proposed; the binding doc changes first)

- **§2 step 1 (Pick a play)**: add "Plays are shown as blocks in their genre
  hue (from the source's subject headings) with the cast fingerprint and
  length; grouped by kind; shortest first, said on screen." The bundle carries
  each script's `subjects` (Gutenberg's headings) so
  `build_castable_scripts.py` can apply the rule; the rule and a test live
  with the bundle.
- **§2 step 2-3 (cast sheet, take a part)**: each part card shows a presence
  strip; length as minutes and lines on two lines; the name asked once;
  Take part in ink outline for the suggested part, Continue in ink for your
  own; no red on the cast sheet.
- **§2 step 4 (record line by line)**: replace the paragraph with §3.3-3.4 of
  this file: duet stage, the streamer and boundary-lit words, the armed and
  recording states, review with Again / With cue / Keep, and Keep runs on to
  the next cue. "Hear a run-up" and "Hear it read" stay optional aids.
- **§2 platform table**: iPad, Mac and wide web use the three-column recorder.
- **§4.2**: a take records `peak` and `loudness` already; the review's quiet
  and clipped notes read them (thresholds to measure on devices).
- **§7 Accessibility**: add "Reduce Motion replaces the streamer with stepped
  word lighting"; "the cue's end comes with the `selection` haptic and a soft
  tone"; "the review never auto-plays".
- **New rule for §8**: "Red appears only in the recorder, only while the
  microphone is armed, open, or recording room tone (Decision 064)." A check:
  a design-rules test that fails when `--color-record` / `brandRecord` is used
  outside the recorder's files.
- **Interruptions (new §4.7)**: a began interruption, a route change that
  loses headphones, backgrounding (`visibilitychange` on the web) each end the
  listening state and discard the partial take; the recorder returns to Ready
  on the same line with one warning line. Apple does not rely on `ended`.

Owner calls this raises (none is made here):
- Keep running straight on into the next cue (the default here), or stop after
  each Keep?
- Is the suggested part's Take part ink (a primary action) or blue (D1c's open
  question)? The prototype uses an ink outline.
- The play hue rule from Gutenberg subjects (comedy vs drama), or no play hue
  until a richer source exists?

---

## 9. Prototype and evidence

- `docs/research/design/directions/record/`: `index.html`, `app.js` (the
  states and a timer-driven simulation: Record plays the cue sweep, then the
  fake meter, then review; Keep runs on), `style.css` (the shared tokens and
  base), `data.js` written by `build_data.py` from
  `catalog/plays/castable-scripts.json` (15 castable plays; the scene is
  *Caesar Rodney's Ride*, L0106-L0172, every word the bundle's), and
  `shoot.mjs` (the shots and the fit check). 128 KB in all.
- **Shots**: `img/d2b-2/<state>-375.png` (through a 375 px iframe) and
  `<state>-1440.png`, each also `-dark`, for the 13 states: `pick`, `part`,
  `preflight`, `denied`, `roomtone`, `ready`, `cue`, `recording`, `review`,
  `flagged`, `interrupted`, `done`, `listen`.
- **Fit**: `node shoot.mjs <repo> <out> <port> --fit` lays every state out at
  320, 375, 390, 430 and 1440 px and fails on sideways scroll, a box whose text
  overflows it (a word that would break inside itself; `word-break` and
  `hyphens` are off everywhere), a control row whose items stack, a button
  whose label wraps, or a heading or fact line whose last line is a stray
  word. Result: "fit-checked 13 of 13; 0 problems", light and dark. The
  negative control `--break` (stacks the review buttons, narrows every button,
  and puts an unbreakable word in the title) was seen to fail: "row stacks"
  and "button wraps" at every width, and the title overflows. The 320 px
  frames are in `img/d2b-2/fit/`. Earlier runs caught real defects that are
  now fixed: "about 7 min · / 97 lines" split at the dot, "Sam · 12 of / 44",
  an author's years orphaned, and "RODNEY · / YOU" wrapping at 320 px.

Not verified: real audio (no microphone, speech or haptics in the prototype),
iOS Safari, VoiceOver and TalkBack behavior, Dynamic Type at the largest
sizes, and the quiet and clipped thresholds.

## 10. Seen on the way

- `docs/research/design/img/d2/*/create-record-375.png` (all three): the
  device voice drawn like a person's line; PLAYS-DESIGN §5 rule 3 asks for the
  label, and the D2 recorders show it only during the cue. Fixed here by the
  dashed ring; the shipped apps should be checked for the same.
- `js/plays-ui.js` `prompter()`: Run-up, Hear it read, speed and Keep are four
  equal buttons and Keep is not beside the record control (D1c inventory);
  this design moves Keep into the review dock.
- The quiet and clipped review notes (§4) are designed but not drawn in the
  prototype; their thresholds need device measurements first.
- The castable bundle carries no subjects or year, so no play can show its
  genre or decade today (§8).
