# R2-S: The script reader and the studio (Round 2 research, 2026-11-14)

The owner, 2026-11-14 (Round 2, item 5, verbatim): *"We need to work on the
recording and reading features in the app. Both should be first-class
experiences. You should be able to read a script and turn pages and mark them up
and do all of the things that a good book/script reading experience should
contain. The recording experience should allow you to read the script as you
would any book or script while you record your lines. It should be easy to go
back and forth within the script and rerecord any line that you'd like to do
another take with. The virtual voices who play the different parts should also
be intuitive (before humans re-record them). You should be able to set all of
the parts of the script with different virtual voices (built in to the device or
downloadable from open source models that you should be able to research).
Additionally, on an iPhone Duo with the screen open, you should be able to see
the script on one side and the recording featueres on the other."*

This is track **S** of DESIGN-LOOP.md's Round 2. It is research and a proposal.
Nothing here is built, and nothing in it binds until the owner answers §7 and
PLAYS-DESIGN.md is amended (fix the doc first, then the feature).

Rules this design is held to (not restated below):
- **A synthetic voice is a live stand-in only, never stored** (AGENTS.md, Decisions
  055/059, PLAYS-DESIGN §5). A *downloaded model* is not a stored voice: it is an
  engine on the device, like a system voice. What it renders lives in memory and
  is released after it plays, as today.
- No AI-written copy. A neural voice reading a human-written public-domain script
  is not copy (08a §1.5), but every synthetic line stays labeled "Device voice"
  and drawn as a dashed ring, never a face (D2b §7.6).
- Direction D (DESIGN-LOOP.md): part hues, faces, strips, red only for recording.
- Feature parity, native idiom; no third-party Swift packages; real devices only.
- The read-along memory (owner 2026-11-09): one script id scheme, one client seam
  that can open an in-app synced reader (Now Playing included), parsed cues kept.
  **The reader proposed here is that reader**; the studio is the reader with a
  dock.

---

## 0. Summary

1. Today there is **no script reader**. The recorder shows only the performer's
   own lines (a stage of before / cue / mine / next, or a list of the part's
   lines); you cannot read the play, page through it, or reach another part's
   line. "Read the script" on an episode is a link out.
2. The take model is already right: every take kept, one chosen per line,
   Again / With cue / Keep, Discard the run. What is missing is reaching any line
   from the script itself and a per-line take drawer.
3. Voices are **not cast**: each platform hands out device voices in the order
   parts first speak, with pitch varied. The recorder and the listen-through keep
   separate assignment maps, so a part can sound different in each. No picker, no
   preview, no gender use (PLAYS-DESIGN §5 says gender is used; the code does not).
4. Proposal: **one Reader** on every platform (scroll by default, paged as an
   option, "I'm playing ___" drives highlight / hide / cue), **marks anchored to
   line ids** (highlight, underline, breath and pause slashes, beat, note; Apple
   Pencil ink on iPad), **the Studio as the Reader plus a dock and a take drawer**
   (the three recording modes become three ways the reader moves), and **a cast
   sheet with a voice per part** (preview the part's first line, speed and pitch,
   auto-cast distinct voices, every choice overridable).
5. Wide layouts: the script is the primary pane and the studio the supporting pane:
   SwiftUI `ArrangementView` split on the open iPhone Duo (iOS 27.1, gated), the
   same two panes in an `HStack` on iPad and iOS below 27.1, a Mac window with an
   inspector, `SupportingPaneScaffold` on Android, two columns on the web at 860 px.
   Closed Duo: the script with a compact record dock.
6. Downloadable voices: **Kokoro-82M** (Apache-2.0 weights, 28 English voices,
   ~86-92 MB q8 ONNX) on all three stacks, with the GPL eSpeak phonemizer kept out;
   **Kitten TTS 0.8 nano** (Apache-2.0, ~25 MB int8, 8 voices) as the light option.
   Piper, XTTS, F5, Kitten 2 and every voice-cloning model are refused. On the web a
   model is also the first way to get synthetic audio into a buffer, which buys the
   web its first bleed check and sample-timed cues.
7. tvOS: read-along only (the script following a listen-through or a transcript in
   Now Playing, ≥29 pt, current line ±1). No markup, no recording.
8. Seven phases (§6), each shippable on every platform; owner questions in §7.

---

## 1. Audit: today's reader and recorder

Read from main at 1.0.128 (9685156), 2026-11-14. Files: Apple
`apple/Core/Plays/{PlayScript,Production,RecordingSession,StandIn,LiveListen}.swift`,
`apple/Shared/{RecordingScreen,PlaysScreens,SourcePages}.swift`; Android
`android/.../plays/*.kt`, `ui/screens/{Recorder,PlaysScreens}.kt`; web
`js/plays-{core,session,ui,voice}.js`.

### 1.1 How a script is parsed and stored

- `catalog/tools/script_parse.py` slices each printed block into a line; no word is
  rewritten. `build_castable_scripts.py` writes `catalog/plays/castable-scripts.json`
  (bundled in the apps): **15 scripts** (11 stage, 4 Carlton radio), 9,591 lines
  (8,751 speech, 840 direction), 1.84 MB.
- A script: `id` (`gut-49295`), `revision` (hash), `kind`, `title`, `year`,
  `authors`, `source`, `rights`, `roles[{name, lines, words}]`, `lines[]`.
- A line: `id` (`L0001`, script-local, stable per revision), `kind`
  (`speech | direction | sound | music`), `role`, `parts[]` of `{say|direction|mic|sound}`
  slices, `source` (the printed block).
- Parts are `PartID` (`role:NAME`, `directions`, `sound`); cast order is largest
  first; part hues are the first seven speaking parts (`PlayScript.partHues`).
- **Not in the data**: acts, scenes, or pages. They exist only as direction lines
  ("ACT I.—...", "SCENE 1.—Noon."). No character descriptions are parsed (the
  printed cast list is a direction block). Nothing records voice gender.

### 1.2 The recorder

| Capability | Apple | Android | Web | Notes |
|---|---|---|---|---|
| Three modes (Run through, Line by line, Step) | ✅ | ✅ | ✅ | Owner ruling 4 (2026-10-29); same session names, golden-tested |
| Shows the **whole script** | ❌ | ❌ | ❌ | `session.lines` is the part's lines; Step shows before / cue / mine / next |
| Reach another part's line, read ahead, flip back a scene | ❌ | ❌ | ❌ | Only the part strip (one tick per own line) |
| Re-record any own line | ✅ (Line by line, strip ticks) | ✅ | ✅ | |
| Takes kept, one chosen per line, numbered take dots | ✅ | ✅ | ✅ | `Production.takes`, `chosen[lineID]`; "Keep N takes / Discard the run" |
| Hear a take with its cue | ✅ With cue | ✅ | ✅ | |
| Delete unused takes | model only (`Production` prunes non-chosen) | ? | ? | No visible verb |
| Live level meter | ✅ bars | ✅ | ✅ | No target band, no clip history |
| Run-up, Hear it read, voice speed | ✅ | ✅ | ✅ | Speed is global, not per part |
| Wide layout | ≥840 pt: scene rail / stage / aids rail | one column | one column | Apple's three-column layout is the closest thing to a split |
| Keyboard | Space, Return, R, arrows (Mac, iPad keyboard) | hardware key records | Space, arrows | No PgUp/PgDn, no pedal mapping |
| Markup, notes, highlights | ❌ | ❌ | ❌ | |
| Reading without recording | ❌ | ❌ | ❌ | A signed-out person can take a part and read along, but only their own lines |

### 1.3 The voices

- Apple `DeviceVoices.castable()`: English, not Personal, not Novelty, current
  language first, then by `quality`, then identifier. `SystemStandInVoice` gives a
  part the next index the first time it renders (`assigned[part] = assigned.count`)
  and varies pitch over five values when voices run out. Web `StandInVoice` and
  Android `SystemStandInVoice` do the same with `localService` /
  `!isNetworkConnectionRequired`.
- **Defect (seen on the way, not fixed):** assignment depends on which part
  speaks first in *this session*, and the listen-through (`SystemListenSpeaker`)
  keeps its own map. The same part can be read by different voices in the recorder,
  in Run-up versus Step, and in the listen-through. A person cannot learn "Rodney is
  that voice."
- **Doc/code mismatch:** PLAYS-DESIGN §5 says "by `gender` on Apple where the script
  states one and by a small hand map on Android". Neither exists; scripts state no
  gender in the data.
- Personal Voice: offered as a live listen-through voice only (`PersonalVoiceToggle`),
  through `speak`, never a buffer. Apple's runtime refuses Personal Voice in the buffer
  callback anyway ("Cannot use AVSpeechSynthesizerBufferCallback with Personal Voices",
  <https://developer.apple.com/forums/thread/736148>).
- The web cannot hear its own stand-in (no capture of `speechSynthesis`), so its bleed
  check is level-only and its cues are loosely timed (08a §3).

### 1.4 What is missing, against the owner's words

| Owner asked | Today | Gap |
|---|---|---|
| Read a script, turn pages | Not possible in-app | A reader |
| Mark it up | Nothing | Marks, notes, Pencil |
| "All of the things a good book/script reader" has | Nothing | Position memory, contents (acts/scenes), search, text size, theme, find my next line, hide my lines |
| Read the script as you would while recording | Own lines only | Studio inside the reader |
| Go back and forth, re-record any line | Strip ticks / Line by line list of own lines | Tap any line in the script; take drawer |
| Virtual voices intuitive; set every part's voice | Auto, order-dependent, inconsistent | Cast sheet with voice picker, preview, persistence |
| Built-in or downloadable open models | Built-in only | Model downloads (§5) |
| Duo open: script one side, recording the other | No Duo layout | Two-pane arrangement (§4.5) |

---

## 2. Findings, with sources

### 2.1 Reading apps

- **Apple Books** offers Curl, Slide and None (a cross-fade); Curl was removed in iOS 16
  and restored in 16.4 after complaints; Slide is the default and continuous Scroll is a
  toggle in Themes & Settings
  (<https://www.macrumors.com/how-to/re-enable-page-turning-animation-apple-books/>,
  <https://9to5mac.com/2023/03/01/curl-page-turn-effect-apple-books-is-back/>,
  <https://appleinsider.com/inside/ios-18/tips/inside-apple-books----the-best-app-for-book-lovers/amp>).
  *Take:* offer paging and scroll; slide, never curl.
- **Kindle**: four highlight colors, synced notes, "My Notebook" collecting every mark;
  Page Flip lets you look elsewhere while keeping your place; X-Ray lists characters
  sortable by appearance (<https://apps.apple.com/app/kindle/id302584613>,
  <https://www.techlearning.com/tl-advisor-blog/5504>,
  <https://oreilly.com/library/view/amazon-fire-phone/9781491911259/ch04.html>).
  *Take:* a notebook of my marks; peek without losing place; the cast as an index.
- **Readwise Reader** is fully keyboard-drivable: `H` highlights a paragraph (double tap
  on mobile), `T` tags, `?` / Cmd-K lists every shortcut
  (<https://docs.readwise.io/reader/docs/faqs/highlights-tags-notes>,
  <https://help.readwise.io/article/79-how-do-keyboard-shortcuts-work>).
  *Take:* single-key marks on Mac and web, a `?` sheet.

### 2.2 Actor script apps

- **Scriptation Playback Mode** merges Read, Rehearse and Record: pick the character you
  play; Auto-Highlight; your lines muted in readback; Cue mode "On voice" waits for you;
  presets Table Read, Rehearsal (dialogue only), Teleprompter; blackout of your own lines
  to learn them; each character gets an on-device voice, voice/language/rate per
  character, casting saved and reused; it tells users to download Apple's Enhanced and
  Premium voices (<https://help.scriptation.com/en/article/what-is-playback-mode-dg5uqr/>,
  <https://help.scriptation.com/en/article/what-is-record-mode-1rphrli/>,
  <https://help.scriptation.com/en/category/playback-mode-1wkg8it/>).
  *Take:* one "I'm playing" choice drives highlight, mute, cue and hide; one control bar.
- **LineLearner**: record a scene, choose where gaps fall, a Prompt button gives the line
  you forgot, partners send their lines remotely, other characters' pitch shifted to tell
  them apart (<https://apps.apple.com/app/linelearner/id368070258>). **Rehearsal Pro**:
  per-role color highlighting, line blackout, unlimited versions of a scene; reviewers
  punished v3 for removing v2's uncover-during-playback
  (<https://apps.apple.com/app/id1116896197>). **Off Book! Pro** "Mute My Line"
  (<https://apps.apple.com/app/id1072004273>); **Cold Read** listens for your last word,
  on device, no account (<https://apps.apple.com/us/app/-/id6759092894>); **Run Lines**
  "Hide My Lines" (<https://apps.apple.com/us/app/id6755323192>).
  *Take:* hide-and-peek is the core learning mechanic; never remove a verb people rely on.
- **Final Draft Go** (iPad): character highlighting, read-only without subscription
  (<https://apps.apple.com/us/app/id1614876398>).

### 2.3 What actors mark

A small slash is a breath, a larger slash a pacing pause, several a long pause; `//` a
beat or shift in tone with a one- to three-word label in the margin; underline for
emphasis, double underline for stronger stress; most actors add personal circles and
brackets (<https://actingmagazine.com/2018/04/woodshed-your-copy/>,
<https://www.peterdrewvo.com/?p=106>,
<https://www.npr.org/sections/npr-training/2025/09/29/g-s1-90460/how-marking-scripts-can-help-you-sound-more-natural>,
<https://www.backstage.com/magazine/article/what-are-beats-in-acting-76101/>).
*Take:* a six-mark set (highlight, underline, double underline, breath, pause, beat with
label) plus a margin note, and free ink where there is a pencil.

### 2.4 Pencil, keys, pedals

- PencilKit on a document page: `PDFPageOverlayViewProvider` (iOS 16 / macOS 13) puts a
  `PKCanvasView` over a page (<https://developer.apple.com/videos/play/wwdc2022/10089/>);
  overlays need interaction enabled and blur when zoomed
  (<https://developer.apple.com/forums/thread/792941>,
  <https://developer.apple.com/forums/thread/773633>). Our text is reflowed, not PDF, so
  the canvas belongs per line block, not per page (§4.2).
- Page-turn pedals (AirTurn) send Up/Down arrows by default, Left/Right or PgUp/PgDn as
  modes (<https://onsongapp.com/docs/interface/menubar/utilities-menu/editors/actions/pedals/mode-chooser>);
  since iOS 15.1 arrows can move keyboard focus instead of turning pages
  (<https://help.musicnotes.com/hc/en-us/articles/205183375-Hands-Free-PageTurn-Support>).
  Android readers (Play Books, Kindle, Kobo) offer "volume keys turn pages"
  (<https://kvibber.com/tech-tips/boox-page-buttons/>).
- tvOS body text: 29 pt default, 23 pt minimum
  (<https://developer.apple.com/design/human-interface-guidelines/accessibility>).

### 2.5 Recording tools

- **Punch-and-roll** (audiobook narration): pre-roll of the recorded audio before the
  edit point, then record at the cursor; ~5 s default; most narrators work this way
  (<https://cchogan.dancingbear.co.uk/audiobook-tips-a-short-guide/punch-and-roll-recording/>,
  <https://larryjordan.com/articles/audition-cc-magic-inside-the-record-button/>).
  Ear Drama's cue line already *is* the pre-roll (D2b §7.1).
- **ACX**: RMS -23 to -18 dB, peaks ≤ -3 dB, noise floor ≤ -60 dB
  (<https://help.acx.com/s/article/acx-audio-submission-requirements>). *Take:* a target
  band on the meter and a room-tone floor reading are facts, which the essential-words
  rule allows.
- **Logic take folders / Quick Swipe Comping**: non-destructive stacked takes, choose the
  best (<https://help.apple.com/logicpro/mac/10.4/en.lproj/lgcp317d758e.html>);
  **GarageBand iOS** Multi-Take with "Delete Unused Takes"
  (<https://support.apple.com/HT207727>). *Take:* our per-line takes plus a visible
  "Delete unused takes" (the person's own act).
- **Descript** "record into script" (into the script, replace selection, new layer)
  (<https://www.descript.com/blog/article/how-to-use-descript>): the script is the
  timeline. **Voice Memos layered recording** separates voice from speaker playback, A18
  Pro only (<https://www.macrumors.com/2024/12/11/ios-18-2-layered-voice-memo-recordings/>):
  not a basis for a no-headphones path.
- **Teleprompters**: PromptSmart's voice tracking stops when you pause and sometimes loses
  you (<https://apps.apple.com/us/app/id894811756>). *Take:* voice-following may help, but
  a tap and a key always work.
- **Latency**: `inputLatency + outputLatency + 2 × ioBufferDuration` is an estimate, off on
  some iPads; calibrate by loopback (<https://developer.apple.com/forums/thread/25197>,
  <https://support.audacityteam.org/troubleshooting/solving-recording-problems/latency-compensation>).

### 2.6 Casting voices in other apps

- **WriterDuet ReadAloud**: auto-assigns by language and the character's gender and age,
  a drop-down per character to change it, speed only
  (<https://www.writerduet.com/article/119-readaloud>).
- **Arc Studio Table Read**: "Manage voices" lists narrator and characters against voices;
  drag or + to assign; a sample button per voice; "Auto-assign missing"; speed, pause
  between elements, and which elements are read (dialogue only, all)
  (<https://help.arcstudiopro.com/guides/table-read>).
- **Final Draft** Tools > Assign Voices maps each character to a system voice
  (<https://kb.finaldraft.com/hc/en-us/articles/15575029300244-Are-there-any-more-voices-for-the-text-to-speech-feature>).
- **tableread**: ~40 voices, tone and pitch per voice, a narrator part
  (<https://www.finaldraft.com/blog/the-bricks-of-breaking-in-make-your-own-table-read-with-this-writing-tool>).
- *Common pattern:* a cast sheet (character → voice), a narrator slot for directions, a
  preview on each voice, an overridable auto-assign, global speed and pause, casting saved.

### 2.7 Built-in voices

- **Apple**: quality `.default` (installed), `.enhanced` and `.premium` ("that you must
  download to use"; premium since iOS 16)
  (<https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality>).
  `speechVoices()` lists only installed voices; no API lists or starts downloads
  (<https://developer.apple.com/forums/thread/758460>,
  <https://developer.apple.com/forums/thread/787779>). `gender` exists (male, female,
  unspecified) since iOS 13 and many voices report unspecified
  (<https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice/gender>).
  `write(_:toBufferCallback:)` runs on iOS, macOS **and tvOS** 13+
  (<https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:)>).
  Siri voices are not exposed (<https://developer.apple.com/forums/thread/676726>). Users
  add voices in Settings > Accessibility > Spoken Content > Voices (iOS 26 may call it
  Read & Speak, UNVERIFIED, <https://www.comaps.app/news/ios-hq-voices/>); an iOS 26 report
  says `AVSpeechSynthesisVoice(language:)` ignores the user's choice, so pick by identifier
  (<https://developer.apple.com/forums/thread/804648>).
- **Android**: `Voice` has quality 100-500, latency, `isNetworkConnectionRequired`,
  features, no gender; `KEY_FEATURE_NOT_INSTALLED` voices download on `setVoice`;
  `ACTION_INSTALL_TTS_DATA` opens the engine's installer; `KEY_PARAM_PAN` pans a voice
  (<https://developer.android.com/reference/android/speech/tts/Voice>,
  <https://developer.android.com/reference/android/speech/tts/TextToSpeech.Engine>).
- **Web**: Chrome desktop's Google voices are online only, cut off after ~14-15 s;
  Edge's 250+ natural voices are online; Safari hides downloadable voices and marks every
  voice default; Firefox lists OS voices; no browser exposes gender; voices load on
  `voiceschanged` (<https://readium.org/speech/docs/WebSpeech.html>,
  <https://github.com/phetsims/utterance-queue/issues/60>,
  <https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesis/voiceschanged_event>).
  No spec captures synthesis audio (<https://soledadpenades.com/posts/2023/web-speech-to-web-audio/>).
  One utterance per line already avoids the cutoff; the `localService` filter already
  drops the online voices (§5 rule 5).

### 2.8 Open on-device models

Full table in §5. Key facts:
- **eSpeak NG is GPL-3.0-or-later** (<https://github.com/espeak-ng/espeak-ng/>) and is the
  phonemizer inside Piper, Kitten, NeuTTS, StyleTTS2, kokoro-js, and sherpa-onnx's Kokoro
  archives (<https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html>). GPL
  and the App Store conflict (VLC was pulled in 2011:
  <https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html>). Kokoro's own
  G2P, **misaki**, is Apache and runs without the eSpeak fallback
  (<https://pypi.org/project/misaki/>).
- **Kokoro-82M**: Apache-2.0 weights, trained on permissive audio, 28 English voices
  (20 US, 8 UK); ONNX fp16 163 MB, q8 92 MB, q8f16 86 MB
  (<https://huggingface.co/hexgrad/Kokoro-82M>,
  <https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX>,
  <https://cdn.jsdelivr.net/npm/kokoro-js@1.2.0/README.md>). Only old-device benchmarks:
  RTF 0.62 on an A12X iPad, 1.13-2.42 on a Galaxy S10, i.e. slower than real time on old
  Android (<https://voiceping-landingpage-prod.pages.dev/en/blog/research-offline-tts-eval/>).
  CoreML conversions exist (<https://huggingface.co/mattmireles/kokoro-coreml>).
- **Kitten TTS 0.8**: Apache-2.0; nano 15M (~25 MB int8), micro 40M (41 MB), mini 80M;
  8 voices; faster than real time on old phones (RTF ~0.39 on a Galaxy S10)
  (<https://huggingface.co/KittenML/kitten-tts-nano-0.8>,
  <https://github.com/KittenML/KittenTTS>). Kitten **2** weights are under a revocable,
  revenue-capped community license with mandatory attribution: refused.
- **Supertonic 3**: MIT code, OpenRAIL-M weights (commercial allowed; must disclose
  machine-generated content; no impersonation), ~99M, 10 voices, **no G2P**, official
  Swift / WebGPU / Java; the repository was archived after 2026-04-29
  (<https://github.com/supertone-inc/supertonic>,
  <https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE>).
- **sherpa-onnx**: Apache-2.0 runtime for iOS, Android, macOS, WebAssembly; runs Piper,
  Kokoro, Kitten 0.8, Supertonic 3, Pocket TTS (<https://github.com/k2-fsa/sherpa-onnx>).
- **Piper** moved to GPLv3 (piper1-gpl v1.7.0), and the lessac family of voices derives from
  research-only Blizzard data (<https://github.com/OHF-Voice/piper1-gpl/releases>,
  <https://github.com/rhasspy/piper/discussions/271>). Research 08a §1.5's Piper-on-sherpa
  route still carries eSpeak and per-voice license checks; superseded by §5 here.
- **Refused**: XTTS-v2 (CPML, non-commercial; <https://huggingface.co/coqui/XTTS-v2>),
  F5-TTS (CC-BY-NC weights; <https://github.com/SWivid/F5-TTS>), Breeze TTS 2
  (non-commercial), and every **cloning** model (Pocket TTS's reference input, Chatterbox,
  NeuTTS Air, CSM, Orpheus): in an app built on broadcasts of real, mostly dead performers,
  a few seconds of reference audio recreates them, which the models' own terms
  (<https://huggingface.co/kyutai/pocket-tts>, <https://huggingface.co/sesame/csm-1b>) and
  our stand-in rule forbid.

### 2.9 iPhone Duo, iPad, Android foldables

- **iPhone Duo**: shipped 2026-10-23; outer 5.4" 1398×2034, inner 7.6" 1878×2670
  (<https://www.macrumors.com/roundup/iphone-duo/>). The inner display is regular width;
  bars move to a vertical strip on the outer display and inner landscape; the fold is a
  reserved region only while partially folded; Apple says do not design per pose
  (Archive Watch `docs/research/IPHONE-DUO.md` §2, from Apple's HIG
  <https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo>).
- **`ArrangementView`** (SwiftUI, **iOS 27.1+**,
  <https://developer.apple.com/documentation/swiftui/arrangementview>): a primary and a
  secondary view laid out "based on size class, orientation, and reserved regions".
  `.split` keeps both in separate spaces (primary leading in landscape, top in portrait;
  `.split.axes(.horizontal)` forces side by side); **"When someone is holding a closed
  iPhone Duo in landscape orientation, the split arrangement only shows the primary
  view."** `.overlay` stacks on a flat display and separates across a fold. Do not put it
  in a scroll view or navigation split view, or a tab or split view inside it. A developer
  reports it showing only one child on iPad (<https://developer.apple.com/forums/thread/847787>,
  unanswered): treat iPad behavior as unproven and keep an `HStack` fallback.
- **Android**: `FoldingFeature` `HALF_OPENED` + horizontal hinge is tabletop, + vertical is
  book (<https://developer.android.com/guide/topics/large-screens/make-apps-fold-aware>);
  Material 3's canonical **supporting pane** layout (`SupportingPaneScaffold`) is one pane
  at compact width, two at expanded
  (<https://developer.android.com/develop/ui/compose/layouts/adaptive/canonical-layouts>).
- **iPadOS 26** windows are freely resizable, so width, never device, decides the layout
  (<https://www.macrumors.com/review/ipados-26/>).

---

## 3. Design principles (what the four questions say)

`learning-orientation-design`, applied:
1. **Deepens understanding**: marking a script is how an actor thinks about a line
   (breath, beat, stress). The reader makes that work visible and keeps it; it never
   suggests a reading.
2. **Invites participation**: the listen-through, the reader and the cast sheet all end
   in "Take this part". Hide-my-lines turns reading into rehearsal.
3. **Agency**: every auto-cast voice is overridable; every take is kept until the person
   deletes it; marks are theirs, never synced or shared without their choice.
4. **Clarity**: a synthetic voice is always labeled and drawn as a dashed ring; no score,
   no streak, no "AI coach".

Refused on the way (record in SCRATCHPAD "Out of scope" if the owner agrees): voice
cloning of any kind; AI line readings or delivery suggestions; AI-written character
descriptions for casting; storing any synthetic render; network TTS voices.

---

## 4. Proposed design

### 4.1 The Reader (all platforms that read)

**Where it opens.** One seam, `ScriptReader.open(scriptID, at: lineID?, mode:)`,
from: a play's page ("Read" beside "Start an ear drama"), the cast sheet, the studio,
the listen-through (follow mode), and later Now Playing for an episode whose script we
may show (the read-along memory). Reading needs no account, no part, no microphone.

**The page.** The play's hue block (title, author, year, "12 parts · 840 lines") opens
the script once, then the text in a reading measure (about 60-70 characters):
- Speaker names in small caps in the part's mark color (D's part hues; neutral after the
  seventh), speech in the reading face, directions in italic in brackets as printed,
  sound and music cues set as cue lines with a small speaker glyph (SF Symbols /
  Material Symbols, R-ICON-1).
- Act and scene headings, derived in the pipeline (§6 phase S0), as section breaks and
  as the **Contents** (a sheet: acts, scenes, and "My lines" with counts).
- No line numbers by default (a toggle; a director wants them).

**Turning pages.** Scroll is the default (Books' own setting and the friendlier one for
dialogue that runs across pages). **Pages** is an option in the reader's Aa sheet:
- iOS/iPadOS: horizontal paging with Slide, never Curl; tap the outer fifth of either edge
  or swipe; on the open Duo and iPad landscape, two facing pages when the reader has the
  whole width.
- Mac: Space / Shift-Space, PgUp/PgDn, arrow keys; two-page spread in a wide window;
  trackpad swipe.
- Android: swipe and edge taps; opt-in "Volume keys turn pages".
- Web: Space, arrows, PgUp/PgDn; CSS multi-column paging with scroll-snap in Pages.
- Pedals: arrows and PgUp/PgDn are mapped on every platform; on iOS the reader holds key
  focus so an arrow turns the page instead of moving the focus ring.
- Pages are a client layout of the reflowed text at the current size, never stored;
  position is a **line id**, so it survives size changes, rotation, and another device.

**The reader's controls.** A quiet top bar (Close, Contents, Search, Aa, and Marks) that
hides while reading and returns on a tap (Books' behavior).
- **Aa**: text size (system Dynamic Type plus a reader step), theme follows the system
  (light, dark; a paper tint only if the design tokens carry one), Scroll / Pages, line
  numbers, show directions (on / dimmed / hidden; Scriptation's "Rehearsal" preset).
- **Search** within the script; results as lines with speaker.
- **"I'm playing"**: choose one or more parts (a radio actor often doubles). That choice:
  highlights those lines with the part's hue as a left rule and tint; jumps with "Next
  line of mine" (a button and `J`/`K` on keyboards); sets what **Hide my lines** hides
  (blackout bar in the part's hue; tap or hold to peek, LineLearner's Prompt); and is the
  part the studio records.
- **Follow** (read-along): while a listen-through or take plays, the current line is lit
  and kept in view; touching the text stops following until "Back to the line".
- **Position** remembered per script per device; "Continue reading" on the play's page.

### 4.2 Marks

Marks are data anchored to `(scriptID, revision, lineID, start, end)` where start/end
are offsets into the line's `source`. Line ids are already stable per revision; a new
revision maps marks by exact text match of the anchored slice, and an unmatched mark
moves to the notebook's "Unplaced" list instead of vanishing.

| Mark | Gesture | Drawn as |
|---|---|---|
| Highlight | Select text → Highlight (H) | Tint in the reader's mark color (one color by default, four as an option) |
| Underline / double underline | Select → Underline (U, UU) | Ink rule under the words: stress |
| Breath | Tap between words with the mark tool → `/` | A short slash in the gutter of the line |
| Pause | `//` | A long slash; three for a long pause |
| Beat | Select → Beat + 1-3 words | `//` with the label in the margin |
| Note | Select or tap a line → Note (N) | A margin dot; the note in a popover / sheet |
| Pencil ink (iPad, Apple Pencil) | Draw | Free ink over the line block |

- **Pencil**: one `PKCanvasView` per line block (not per page), sized to the block and
  stored as `PKDrawing` data with the line anchor, so ink moves with its line when text
  reflows or pages change; strokes scale with text size. Scribble writes into the note
  field. Pencil only (finger scrolls) by default (`PKCanvasView.drawingPolicy = .pencilOnly`).
- Mac gets typed marks and keyboard shortcuts; the drawings made on iPad display on the
  Mac read-only (and on iPhone), same anchor.
- Android: typed marks; stylus ink (Ink API) is a later phase, not parity-blocking (cell ⏳).
- Web: typed marks (Selection API); no ink.
- **Notebook**: every mark and note in script order, tap to jump (Kindle's My Notebook);
  Export as text through the share sheet (the person's own act).
- **Where marks live**: on the device first (Apple: a file per script in Application
  Support; Android: Room; web: IndexedDB). Sync and sharing are owner questions Q4, Q5.
- In the studio the marks are visible on your lines exactly as in the reader: the whole
  point is to perform from your marked script.

### 4.3 The Studio: the Reader plus a dock

The recorder stops being a separate one-line stage. **Recording happens in the script.**

- Opening a part from the cast sheet opens the Reader at the part's next unrecorded line
  with "I'm playing" set to that part and the **studio dock** attached (bottom on a
  phone; the supporting pane when wide, §4.5).
- **Every line is reachable**: scroll or page anywhere. Your lines carry their take state
  in the gutter (empty ring: no take; filled in the part's hue: chosen take; warning dot:
  flagged take). Other parts' lines carry who voices them: a face with a name for a human
  take, the dashed ring for a device voice (D2b §7.6).
- **Tap one of your lines** → it becomes the current line (outlined in ink) and the dock
  shows its takes. **Record** plays the cue and records, as today. **Tap someone else's
  line** → it plays (their take or the device voice); long press → "Play from here".
- **The take drawer** (in the dock, or the supporting pane): the line's takes as small
  waveforms with length, numbered, the chosen one filled; tap to hear, "With cue",
  choose, Again; swipe or context menu to delete one; "Delete unused takes" for the
  part (confirmation, the person's own act). Non-destructive by default, as today.
- **The three modes become three ways the reader moves** (owner ruling 4 kept word for
  word):
  - *Run through*: the reader follows the play from the current line; other parts play;
    the mic opens on each of your lines as it comes; the page turns or scrolls itself.
  - *Line by line*: the reader is free; tap any of your lines to record or re-record it.
  - *Step*: after each kept take the reader moves to your next line and waits for a tap.
  The segmented control stays (native, disabled while busy), in the dock.
- **Cue length** (today's Run-up): the line before (default), the two lines before, or
  from the scene's start. Shown as a sweep along the cue line in the script itself
  (D2b's streamer, now drawn on the real line, not a card).
- **Meter**: today's live bars plus a faint target band (about -23 to -18 dB RMS) and a
  peak tick at -3 dB; after a take, "Very quiet" / "It crackled" only when true (existing
  warning copy). Room tone's measured floor shown once as a fact ("Room −62 dB") only when
  it is above -60 dB, as a warning.
- **Hide my lines while recording** is allowed (some performers record from memory).
- **Keys**: Space record/stop, Return keep, R again, ↑/↓ previous/next of my lines,
  PgUp/PgDn page, `?` the shortcut sheet (Mac, iPad keyboard, web); Android hardware key
  and pedal arrows the same.
- **Latency**: a one-time "Check timing" per route (play a click, hear it back) stores
  the offset per device and route; takes are trimmed by it. Optional; the estimate is
  the default.
- Headphones, sign-in, room tone, bleed, interruption states: unchanged from D2b §4.

### 4.4 Voice casting

**The cast sheet gains a voice per part.** Each part row: the part's hue mark, name, line
count, who has it (a face) or, when open, the **voice chip** (dashed ring + voice name,
e.g. "Ava (Premium)" or "Kokoro · Heart"). Tapping the chip opens the **voice picker**:

- A list grouped by engine: *On this device* (system voices, best quality first, each
  with its quality as the system names it), *Downloaded* (model voices, §5), and a row
  "Get more voices" (Apple: a short instruction and Open Settings, since no API reaches
  the voice store; Android: the engine's installer via `ACTION_INSTALL_TTS_DATA`; web:
  the model download, §5).
- **Preview reads this part's first line** in each voice on tap (Arc Studio's sample
  button, but with the play's own words); the person hears Rodney as Rodney.
- **Speed** and **pitch** per part (two small steppers), default from today's pitch table
  when two parts share a voice.
- **Narrator**: "Stage directions" and "Sound effects" are parts already (PLAYS-DESIGN
  §2.2). Their voice defaults to *Not read* (today's behavior: unrecorded directions and
  sound are skipped) with a choice of a voice, so a table read can hear the directions.
- **Auto-cast** fills every open part once, when a production is created: distinct voices
  in cast order, largest part first gets the best-quality voice, alternating the engine's
  own reported voice gender (Apple `gender`; Android and web have none, so alternate by
  voice only), never guessing a character's gender from a name. "Recast all" re-runs it.
  Whether the printed cast list's own words may inform it is owner question Q7.
- **One assignment everywhere**: a `VoiceCast` (part → engine, voice identifier, rate,
  pitch) is read by the recorder's stand-in, Hear it read, Run-up, the listen-through and
  the reader's "Play from here". That fixes §1.3's defect. It is stored with the
  production on this device (`production.json` gains `voices`); a voice missing on another
  device falls back to auto-cast there, silently, chip showing the fallback.
- A voice never looks like a person: the chip is the dashed ring and the reader labels
  every synthetic line "Device voice" whatever engine reads it.
- **Personal Voice** stays as built: listen-through only, through `speak`, a toggle, never
  a buffer; the picker does not list it for the studio (Apple refuses it in the buffer
  path, and the SLA reading in 08a stands).

### 4.5 Wide, split and folded layouts

One model everywhere: **the script is the primary pane; the studio (takes, cast, notes)
is the supporting pane.** At compact width the studio collapses into the dock and sheets.

| Device / state | Layout | API |
|---|---|---|
| iPhone, Duo closed (outer display, compact) | Reader full screen; compact dock at the bottom (record, previous/next of my lines, the line's take dots); takes and cast as sheets. The record button must stay reachable, so "script alone" means script plus dock | `NavigationStack`, `.safeAreaInset(edge: .bottom)`; vertical bar strip handled by system bars |
| **Duo open** (inner, regular width), flat | Script left, studio right, side by side in portrait and landscape | `ArrangementView { Reader } secondary: { Studio }` with `.arrangementViewStyle(.split.axes(.horizontal))`, behind `if #available(iOS 27.1, *)` |
| Duo open, landscape, closing | Primary (the script) alone, as Apple documents for split | Same view, free |
| Duo partially folded, tabletop | Script on the upper half, dock and meter on the lower (Apple: controls on the stable half) | `.split` (vertical axis allowed for this state) or `reservedRegions(kind: .division)` to keep line text off the fold |
| iPad, iOS < 27.1 on Duo, iPad windows ≥ ~700 pt | The same two panes in an `HStack` with a draggable divider; studio 320-380 pt | `onGeometryChange` on width, never idiom (the existing 840 pt switch generalized) |
| Mac | A production is a window: Contents sidebar (acts, scenes, my lines), the Reader, the studio as an `.inspector` (toggle ⌥⌘I); menu bar "Recording" menu with every shortcut | `NavigationSplitView` + `.inspector` |
| Android phone | Reader + bottom dock, sheets | Compose `Scaffold` |
| Android tablet / foldable open (expanded) | Script and studio side by side; tabletop posture puts the dock below the hinge | `SupportingPaneScaffold`, `currentWindowAdaptiveInfo().windowPosture` |
| Web ≥ 860 px | Two columns: reader (reading measure) and studio column (360 px); below 860 px reader + sticky dock | CSS grid, container queries |
| tvOS | No studio (below) | |

Duo details from Apple (via Archive Watch IPHONE-DUO.md): toolbar items need a symbol
**and** a title (`Label`) to move into the vertical strip; no layout per pose; App Store
builds need the iOS 27.1 SDK for edge-to-edge (the CI image question in that doc applies
here too).

### 4.6 tvOS and the listening surfaces

The TV records nothing (PLAYS-DESIGN §2, tvOS-DESIGN). Proposed: a **read-along** panel
during a production's listen-through (and, when rights allow, an episode's script in Now
Playing): the current line and one before and after, ≥ 29 pt, speaker in the part's hue,
"Device voice" beside synthetic lines; no free scrolling, no marks, no pages. Focus stays
on the transport. Smart-TV web and Android TV take the same panel. Whether the TV shows it
at all is Q10.

---

## 5. Voice models: recommendation and licenses

### 5.1 License table

| Engine | Code | Weights / voices | Commercial | eSpeak (GPL) in the usual pipeline | Size | English voices | Verdict |
|---|---|---|---|---|---|---|---|
| Apple system (`AVSpeechSynthesizer`) | OS | OS; live use only (08a §1.4) | Live stand-in yes; never stored | No | 0 (Enhanced/Premium ~100-500 MB each, user-installed, UNVERIFIED) | Device-dependent | **Default on Apple** |
| Android system (`TextToSpeech`) | OS | Engine's | Same reading | No | 0 | Device-dependent | **Default on Android** |
| Web `speechSynthesis` (local only) | Browser | OS | Same | No | 0 | Few local on Chrome; OS voices on Safari/Firefox | **Default on web** |
| **Kokoro-82M** | Apache-2.0 (misaki G2P Apache) | Apache-2.0, permissive training audio | Yes | Only through the eSpeak fallback: keep it off | q8 ~86-92 MB; fp16 163 MB | 28 (20 US, 8 UK) | **Recommended download** |
| **Kitten TTS 0.8** | Apache-2.0 | Apache-2.0 | Yes | Likely (VERIFY before adopting) | nano int8 ~25 MB, micro 41 MB, mini ~80 MB | 8 | **Light option** |
| Supertonic 3 | MIT | OpenRAIL-M (disclosure, no impersonation) | Yes, with restrictions | None (raw text) | ~99M params; cache ~400 MB UNVERIFIED | 10 | Fallback if the G2P port fails; repo archived |
| Pocket TTS | MIT | CC-BY-4.0; voices CC0 / CC-BY / **CC-BY-NC** | Only CC0/CC-BY voices, attribution | Not found | 100M | 26 presets | Not now (cloning-first, gated download) |
| Piper (piper1-gpl) | **GPL-3.0** | Per voice; lessac family research-only | Engine copyleft | Yes | 15-60 MB a voice | many | Refused |
| sherpa-onnx | Apache-2.0 | per model | Yes | Its Kokoro/VITS archives bundle espeak-ng data | runtime | — | Possible Android runtime, without eSpeak |
| XTTS-v2 | MPL | **CPML non-commercial** | No | — | large | cloning | Refused |
| F5-TTS | MIT | **CC-BY-NC** | No | — | large | cloning | Refused |
| Kitten TTS 2 | Apache | Stellon Community License (revenue cap, attribution, revocable) | Conditional | ? | 7M-1.7B | 115 + cloning | Refused |
| Chatterbox, NeuTTS Air, CSM-1B, Orpheus, Dia | MIT/Apache (Orpheus: Llama terms?) | various | Yes / unclear | NeuTTS yes | 350M-3B | cloning / GPU | Refused (cloning, size) |
| Parler-TTS mini, MeloTTS | Apache / MIT | Apache / MIT | Yes | Melo: VERIFY | 0.9B / ~200 MB | 34 / 4 accents | Too big (Parler) or slow on device (Melo RTF 2.87 on A12X) |

Sources: §2.8 and <https://huggingface.co/hexgrad/Kokoro-82M>,
<https://huggingface.co/KittenML/kitten-tts-nano-0.8>,
<https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE>,
<https://huggingface.co/kyutai/tts-voices>,
<https://github.com/OHF-Voice/piper1-gpl/releases>,
<https://huggingface.co/coqui/XTTS-v2>, <https://github.com/SWivid/F5-TTS>,
<https://github.com/KittenML/KittenTTS>, <https://huggingface.co/parler-tts/parler-tts-mini-v1>,
<https://huggingface.co/myshell-ai/MeloTTS-English>.

### 5.2 Recommendation

1. **System voices stay the default everywhere**, now cast per part (§4.4), with "Get
   more voices" pointing at the platform's own Enhanced/Premium downloads (Scriptation's
   advice, free, no app download).
2. **Kokoro-82M as the one downloadable model**, the same voices on every platform, so a
   cast travels between devices. Per platform, native-first:
   - **Apple**: convert the Apache weights to a Core ML `.mlpackage` in our own pipeline
     (Core ML is Apple's; a model file is data, not a Swift package). The phonemizer is
     the hard part: port misaki's Apache lexicon lookup to Swift ourselves (no eSpeak, no
     KokoroSwift package). Old play texts are full of names and archaic words outside any
     lexicon, so the out-of-vocabulary fallback must be measured (§6 S5 spike).
   - **Android**: ONNX Runtime (a Gradle dependency, allowed on Android) or sherpa-onnx's
     Kotlin API with our own misaki lexicon, never its espeak-ng data.
   - **Web**: onnxruntime-web (self-hosted WASM, WebGPU where present) with the q8 or
     fp16 model and the same lexicon in JS. kokoro-js itself pulls eSpeak, so it is a
     reference, not the build.
   - Model files are fetched on demand from **our own GitHub Release** (the cache-Release
     pattern), pinned by SHA-256, shown with their size before download, deletable in
     Settings/Library. They are never bundled.
   - Rendered audio stays in memory exactly like a system stand-in (`StandInAudio`,
     `SyntheticAudio.mark`), so every never-stored guard test covers it unchanged.
3. **Kitten 0.8 nano** (~25 MB) as the light choice for older phones and the web, if its
   phonemizer can be made eSpeak-free; else Kokoro only.
4. **What a model buys the web**: the first synthetic audio a page can hold in a buffer,
   so the web gets correlation bleed checks and sample-timed cues like Apple and Android,
   and could drop "web: headphones only, loose cues" once measured.
5. **Speed**: Kokoro is slower than real time on 2019-era Android (RTF 1.13-2.42); the
   session already renders "one to three lines ahead" (§4.1), so a slow device waits a
   beat before the first cue, never mid-scene. Measure on the bench (iPhone 12, Pixel 8a,
   iPad, Duo, a 2019 Android if one is on hand) before promising it there.

---

## 6. Phased build plan (each phase ships on every platform)

Sized for the autonomous loop: one phase per batch, one worktree, Opus for the design
call of each phase, Sonnet for straight ports, frames read by the main thread before
merge, real devices only. PLAYS-DESIGN and each platform's design doc are amended at the
start of each phase (binding-design-doc discipline).

| Phase | Ships | Web | Apple (iOS, iPadOS, Duo, Mac) | Android | tvOS | Tests seen to fail |
|---|---|---|---|---|---|---|
| **S0 Data** | Section markers (act, scene) derived from direction lines in `build_castable_scripts.py`; a `sections[]` index; marks and voice-cast models; mark anchoring with revision remap | decoder | decoder | decoder | decoder | Golden: same sections for all 15 scripts on every stack; a remap case with a negative control; a catalog dry-run (`tools/catalog_dryrun.sh`) and the client suites (memory: catalog change runs client suites) |
| **S1 Reader** | Read any castable script: scroll/pages, Contents, search, Aa, position memory, "I'm playing" highlight, Next line of mine, Hide my lines with peek, Follow during the listen-through | ✅ | ✅ (paging, two-page at width) | ✅ (+ volume keys) | read-along panel in listen-through | Layout at 320/375/390/430 and 1440; paging at text-size extremes; position restored by line id after rotation |
| **S2 Cast sheet voices** | Voice chip per part, picker with first-line preview, speed/pitch, auto-cast, one `VoiceCast` read by recorder and listen-through, Get more voices | ✅ | ✅ | ✅ | uses the cast in listen-through | A test that the same part gets the same voice in recorder, Run-up and listen-through (fails on today's code) |
| **S3 Studio in the reader** | Dock, tap any line, take drawer, Delete unused takes, modes as reader movement, cue sweep on the line, meter band | ✅ | ✅ | ✅ | n/a (no recording) | The existing mode goldens unchanged; a take deleted only on the person's act; tap tier on iPhone/iPad, Pixel bench, web harness |
| **S4 Wide and folded** | Two panes: `ArrangementView` on Duo (27.1-gated), `HStack` fallback, Mac inspector window, `SupportingPaneScaffold` + tabletop, web two columns | ✅ | ✅ (Duo on device) | ✅ | n/a | Frames: Duo closed / open / folded, iPad windows, Mac narrow and wide, Pixel; the 27.1 SDK in CI checked first |
| **S5 Marks** | Highlight, underline, breath, pause, beat, note; notebook; export; then Pencil ink per line block (iPad), read-only ink elsewhere | ✅ typed | ✅ typed + Pencil | ✅ typed (ink ⏳) | n/a | Marks survive text size, paging and a revision remap; unplaced marks listed, never dropped |
| **S6 Downloadable voices** | Spike first: Kokoro q8 on iPhone 12, Pixel 8a, Chrome, Safari: RTF, first-audio latency, OOV rate on the 15 scripts without eSpeak. Then: model download (our Release, SHA-pinned), model voices in the picker, web buffer path + correlation bleed check | ✅ | ✅ (Core ML) | ✅ (ONNX Runtime) | n/a | The never-stored guard tests extended to model audio and each seen to fail; a license check that refuses a model file without its recorded license |
| **S7 Polish** | Latency check per route, pedal mapping sheet, Run-through page turns, Reduce Motion paths, VoiceOver/TalkBack reading order of the two panes | ✅ | ✅ | ✅ | — | Keys pressed on real devices (memory: press the keys yourself) |

S1 and S2 are independent and can run in parallel worktrees (different files); S3 depends
on both; S4 on S3; S5 on S1; S6 on S2. PARITY.md gains rows: Script reader, Marks, Pencil
ink, Voice casting, Downloadable voices, Read-along on TV, Studio two-pane.

---

## 7. Owner decisions (multiple choice; recommended first)

**Q1. How should the script read by default?**
- (a) Scroll by default, with Pages (slide, two-page when wide) as a setting **(recommended)**
- (b) Pages by default, scroll as a setting
- (c) Scroll only

**Q2. Should reading be its own front door, separate from recording?**
- (a) Yes: "Read" on every castable play's page, no account, and the studio opens from inside the reader **(recommended)**
- (b) Reading only inside the recording flow
- (c) Reading only after taking a part

**Q3. Which marks in the first marks release?**
- (a) Typed marks everywhere (highlight, underline, breath, pause, beat, note) plus Apple Pencil ink on iPad, anchored to lines **(recommended)**
- (b) Typed marks only, no ink anywhere
- (c) Free ink everywhere, finger included

**Q4. Where do a person's marks live?**
- (a) On the device first; sync across their own devices later through the existing per-ecosystem sync when signed in **(recommended)**
- (b) Synced to their account from the first release
- (c) Device only, never synced

**Q5. Can marks be shared inside a shared production?**
- (a) Not now: marks are private; a later "director's notes" layer is a separate decision **(recommended)**
- (b) Yes, anyone in the production can choose to show their marks to the others
- (c) Yes, the director's marks are visible to the whole cast

**Q6. Which downloadable voice model?**
- (a) Kokoro-82M (~90 MB, 28 English voices, Apache-2.0) on every platform, with Kitten nano (~25 MB) as a light option if it passes the license check **(recommended)**
- (b) Kitten nano only (smaller, 8 voices, plainer quality)
- (c) Supertonic 3 (no phonemizer to port, 10 voices, OpenRAIL-M, archived repository)
- (d) No downloads yet; system voices only

**Q7. How should auto-cast pick voices before anyone changes them?**
- (a) Distinct voices in cast order, best voice to the largest part, alternating the voice's own reported gender, never guessing a character's gender; every choice overridable **(recommended)**
- (b) Also read the printed cast list's own words ("his wife", "a maid") to match a voice's gender, from the data only
- (c) No auto-cast: every open part starts on one voice until the person picks

**Q8. Does a voice cast travel with a shared production?**
- (a) Each device keeps its own cast; a shared production starts from auto-cast on each device **(recommended)**
- (b) The director's cast travels as engine + voice names, falling back on devices that lack a voice
- (c) Only model voices travel (they are the same everywhere); system voices stay per device

**Q9. On a closed iPhone Duo (and any phone), what does the studio show?**
- (a) The script with a compact record dock; takes and cast in sheets **(recommended)**
- (b) The script only; recording needs the phone opened (or another device)
- (c) Today's one-line stage when closed, the script and studio when open

**Q10. What does Apple TV (and the other TVs) do with scripts?**
- (a) A read-along panel during a production's listen-through, large type, current line ±1; no marks, no recording **(recommended)**
- (b) Nothing: scripts stay off the TV
- (c) A full reader on the TV, paged with the remote

**Q11. The three recording modes, inside the reader:**
- (a) Keep all three (Run through, Line by line, Step) as the three ways the reader moves **(recommended)**
- (b) Keep Line by line and Run through; drop Step
- (c) One mode: tap any line to record; a play button runs from it

**Q12. Stage directions in a listen-through or table read:**
- (a) Not read by default (today), with a voice choice on the "Stage directions" part **(recommended)**
- (b) Read by a narrator voice by default
- (c) Never read by a device voice

---

## 8. Seen on the way (not fixed here)

1. Voice assignment is per session and per player (§1.3): the same part can sound
   different in the recorder and the listen-through. S2 fixes it; it is a defect today.
2. PLAYS-DESIGN §5 claims gender-based assignment on Apple and a hand map on Android;
   neither is in the code. Correct the doc in S2 (or at once).
3. Research 08a §1.5 names Piper's LibriTTS-R voices on sherpa-onnx as a route; Piper's
   engine is now GPLv3 and its usual phonemizer is GPL eSpeak. §5 here supersedes it;
   C6 (a stored openly licensed voice for an untaken role) would also have to drop Piper.
4. No visible "Delete unused takes" although `Production` already prunes non-chosen takes.
5. `ArrangementView` is iOS 27.1+; the iOS floor is 18, and App Store builds need the 27.1
   SDK for the Duo's edge-to-edge look (Archive Watch IPHONE-DUO §2a, §6). Check what the
   CI image selects before S4.
6. iOS 26 reportedly ignores the user's chosen voice in `AVSpeechSynthesisVoice(language:)`;
   the app picks by identifier already, keep it that way.

## Sources

Repository: `docs/PLAYS-DESIGN.md` §§2-5, `docs/research/08-collaborative-productions.md`,
`08a-voices-and-mixing.md` (§§1.4, 1.5, 3, 5), `08b-scripts.md`, `08c-collaboration-and-storage.md`,
`docs/research/design/D1c-making-sharing.md`, `D2b-record-a-line.md`, `DESIGN-LOOP.md`
(Round 2), `catalog/plays/castable-scripts.json`, Archive Watch
`docs/research/IPHONE-DUO.md`; the code files listed in §1.

Web (all read 2026-11-14 or cited by the research agents that day; UNVERIFIED marks the
weak ones): every URL inline above, plus
- <https://developer.apple.com/documentation/swiftui/arrangementview>
- <https://developer.apple.com/forums/thread/847787>
- <https://swiftjectivec.com/iPhone-Duo-First-Developer-Good-to-Knows/> (secondary digest of Apple's Duo talks)
- <https://dev.classmethod.jp/en/articles/ios27-1-iphone-duo-new-apis/> (secondary)
- <https://developer.android.com/guide/topics/large-screens/foldable-postures-and-states>
- <https://developer.android.com/develop/ui/compose/layouts/adaptive/canonical-layouts>
- <https://bendodson.com/weblog/2024/04/03/using-your-personal-voice-in-an-ios-app/>
- <https://developer.apple.com/forums/thread/812285> (Personal Voice SLA quote, no Apple reply)
- <https://www.caktusgroup.com/blog/2025/11/03/the-halting-problem/> (Chrome cutoff)
- <https://k2-fsa.github.io/sherpa/onnx/tts/kitten>, <https://csukuangfj.github.io/sherpa/onnx/tts/supertonic.html>
- <https://offlinetts.com/blog/browser-tts-showdown-kokoro-piper-kitten/> (browser speed, UNVERIFIED)
- <https://www.descript.com/blog/article/how-to-use-descript>, <https://www.wooji-juice.com/products/ferrite/in-depth>
- <https://riverside.com/blog/local-recording> (double-ender)
