# Voices, recording and mixing for collaborative radio plays (2026-10-18)

Track 08a of the collaborative-recording research. The owner asked for people to
record a public-domain script one role at a time, with the roles nobody has
recorded yet read by the device's built-in voices, and the human recordings
merged as more parts are taken. **Owner clarification, the same day, verbatim:**
*"The simulated audio would not be recorded. It would only be used when someone
is recording their parts of the play against the simulated voices. The simulated
voices could then be recorded-recorded as real human voices. The idea is that you
would take one part and act it out. The other non-recorded roles would be
simulated audio when you are recording your parts (but only your part would
actually be recorded). Then the next person would take one of the simulated parts
and record that. Every time a new person would take a new part of the play and
record it until all of the parts are taken."*

So this file is built around one rule: **synthesized voices are a live cue,
played on the performer's own device while they record. They are never written
to a stored file, never uploaded, never part of a mix.** Only human takes are
stored. Facts checked directly on 2026-10-18 are marked **MEASURED** or
**READ**. Anything not confirmed from a primary source is marked **UNVERIFIED**.

---

## Verdict

1. **Feasible on iPhone/iPad, Mac and Android phones; feasible with limits on the
   web; not a recording surface on tvOS, Google TV, Fire TV or Roku** (they can
   still play finished and partial plays). The core loop is to cue the previous
   lines (a human take where one exists, a live system voice where not), record
   the performer's line, detect where it ends, and cue the next. It is built from
   documented APIs on every phone and desktop platform (§3, §8).
2. **The license question gets much smaller under the owner's rule, but it does not
   go away.** The macOS license explicitly lets a person use System Voices "while
   running the Apple Software". It forbids "recording, publishing or
   redistribution ... in a profit, non-profit, public sharing or commercial
   context" (READ, §1.4). Playing a voice live as a cue is the permitted use.
   Uploading audio that contains it would not be. The iOS/iPadOS license has no
   System Voices clause at all, and it forbids Personal Voice in public sharing
   (READ). The one real leak is **bleed**: a cue played on a speaker and picked up
   by the microphone. The design closes it three ways (§4.4): headphones by
   default, per-line slicing that throws away the cue windows, and a bleed gate
   before upload.
3. **The stored artifact is per-line human clips plus a JSON timeline (an edit
   decision list).** The mix is rendered from them. A partial play is never mixed
   into a file. It is played live on each listener's device, with the missing
   roles voiced live and locally (§7). A complete play gets a CI-rendered mixdown
   (ffmpeg, at -16 LUFS) uploaded to archive.org beside its clips.
4. **The web can cue with `speechSynthesis` but cannot get its audio** (READ: the
   spec has no output stream). It cannot know a line's length in advance, schedule
   it to the sample, or check for bleed against it. So the web gets "wait for me"
   pacing only, and requires headphones.
5. **Personal Voice cannot stand in for a performer's part.** Apple's license
   forbids it in any public-sharing context, and Apple tells developers it is
   "primarily" for augmentative and alternative communication apps.
6. **Sound effects and music come from sources with evidence a reader can open.**
   Those are Freesound CC0, archive.org items whose CC0 licence is corroborated
   (not just claimed by an uploader), and Musopen's CC0 or PD-mark recordings.
   **BBC Sound Effects is not open:** its RemArc licence is for non-commercial,
   personal or research use and excludes non-profits (READ, §9).

---

## 1. Apple system speech synthesis

### 1.1 The API surface (READ from Apple's documentation JSON, 2026-10-18)

| API | Availability | What it gives |
|---|---|---|
| `AVSpeechSynthesizer.speak(_:)` | iOS 7, macOS 10.14, tvOS, watchOS | Plays an utterance through the system |
| `AVSpeechSynthesizer.write(_:toBufferCallback:)` | iOS 13, macOS 10.15, tvOS 13, watchOS 6, visionOS 1 | "Generates speech for the utterance and invokes the callback with the audio buffer": PCM in memory, which the app may play, measure or discard |
| `write(_:toBufferCallback:toMarkerCallback:)` | iOS 16, macOS 13, tvOS 16 | The same, plus word/phoneme/bookmark markers (`AVSpeechSynthesisMarker`) |
| `AVSpeechSynthesisVoice.audioFileSettings` | iOS 13, macOS 10.15 | The format of a voice's buffers. Apple's text says it is for when "you want to generate speech and save it as an audio file to share or play later". The API allows it; the license (§1.4) decides whether that is allowed |
| `usesApplicationAudioSession` | iOS 13, tvOS 13 (not macOS) | `true`: speech runs in the app's own `AVAudioSession`, so it shares the `.playAndRecord` session the recorder needs |
| `AVSpeechUtterance` `rate`, `pitchMultiplier`, `volume`, `preUtteranceDelay`, `postUtteranceDelay` | iOS 7 | Per-utterance prosody and timing |
| `AVSpeechUtterance(ssmlRepresentation:)` | iOS 16, macOS 13, tvOS 16 | SSML input. Apple: "properties that affect the prosody of a voice, such as its rate and pitchMultiplier, don't apply to an utterance that uses an SSML representation". SSML `<prosody>` and `<break>` carry it instead |
| `AVSpeechSynthesisVoiceQuality` `.default` / `.enhanced` / `.premium` | premium from iOS 16, macOS 13 | Premium is "a premium quality voice that you must download to use" |
| `AVSpeechSynthesisVoice.Traits` `.isNoveltyVoice`, `.isPersonalVoice` | iOS 17, macOS 14, tvOS 17 | Lets the app filter out novelty voices (Bells, Bubbles...) and Personal Voices |
| `voice.gender` (`AVSpeechSynthesisVoiceGender`) | iOS 13 | `male` / `female` / `unspecified`. This is the only casting attribute the API exposes. There is no age or "character" attribute |
| `requestPersonalVoiceAuthorization` | iOS 17, macOS 14, tvOS 17 | See §1.3 |
| `AVSpeechSynthesisProviderAudioUnit` (speech synthesis provider extensions) | iOS 17 / macOS 14 | A third-party app can install its own voices system-wide. Apple: "Speech Synthesis provider audio unit extensions will be embedded in a host app and will receive speech requests in the form of SSML" (WWDC23 session 10033) |

**Which voices a third-party app gets.** `speechVoices()` returns every installed
voice in every language: the compact defaults, plus any Enhanced/Premium voices
the user has downloaded under Settings > Accessibility > Spoken Content. The
Novelty voices also appear, and the app can filter them out by trait. **The Siri
voices do not appear.** This is not stated in Apple's reference. Forum reports
say so consistently: Siri voices cannot be selected through `AVSpeechSynthesizer`
(<https://developer.apple.com/forums/thread/682438>), and `speechVoices()` does
not list downloaded Siri voice packs
(<https://developer.apple.com/forums/thread/676726>). UNVERIFIED as policy;
consistent in practice. A June 2026 question asks whether the new, more
expressive Siri voice will reach third-party apps; it has no answer (READ,
<https://developer.apple.com/forums/thread/832465>).

**Known gaps that affect casting:**
- The voice list on a fresh iOS 16+ device can be thin, because voices are
  downloaded, not bundled (<https://developer.apple.com/forums/thread/714708>).
- There is no API to list voices that could be downloaded but are not installed
  yet (<https://developer.apple.com/forums/thread/758460>). The app can only say
  "more voices are in Settings".
- `speechVoices()` can list Enhanced voices that are gone after an OS upgrade
  (<https://developer.apple.com/forums/thread/735893>). So a casting choice is
  re-validated on every session.

**How many distinct voices per language.** UNVERIFIED as a number; it varies by
OS version and by what the user has downloaded. Measure it on the bench devices
(§To measure, 1). For US English, macOS has historically offered several dozen
voices, counting the Novelty ones; a fresh iPhone has far fewer.

**What this means for a cast.** A script can have 15 speaking parts. A device may
have 2-4 natural English voices of each gender, and many fewer at Premium
quality. So cue voices will repeat, and that is acceptable: a cue only has to
tell the performer who is speaking and what the line is. The app should:
- assign voices by `gender` from the script's cast list (where the script says it);
- vary `pitchMultiplier` (0.5-2.0) and `rate` slightly so two parts on one voice
  can be told apart. This is not available with SSML (Apple, above), so use plain
  utterances;
- show the speaking character's name on screen as every cue plays. The text does
  the identifying, not the voice.

### 1.2 Rendering in memory, not to a file

Under the owner's rule, `write(_:toBufferCallback:)` is still the right call. It is
used to put the cue into the app's own audio graph in memory, not to save it:

- Each upcoming system-voice line is synthesized into `AVAudioPCMBuffer`s one to
  three lines ahead.
- The buffers are scheduled on an `AVAudioPlayerNode` in the same `AVAudioEngine`
  that plays the human takes and taps the microphone.
- The app then knows each cue's **exact length before it plays**. It can place
  cues to the sample (`scheduleBuffer(_:at:options:completionHandler:)`), and
  §4.4's bleed gate can correlate the microphone against the exact signal played.
- The buffers are released after the line plays. Nothing reaches disk.

`speak(_:)` would also work for cueing, but its start time is not exactly known,
and the app never sees its audio.

UNVERIFIED, to measure: whether `write` works for every voice class (Premium,
Personal Voice, third-party provider voices), and whether it renders faster than
real time. Forum reports of empty buffers on some OS versions exist but were not
confirmed. If `write` fails for a voice, fall back to `speak(_:)` with
`usesApplicationAudioSession = true` and "wait for me" pacing (§5.1).

### 1.3 Personal Voice

- Apps ask with `requestPersonalVoiceAuthorization`. Once allowed, Personal Voices
  appear in `speechVoices()` with `.isPersonalVoice`. Apple: "usage of Personal
  Voice is sensitive and should be primarily used for augmentative or alternative
  communication apps" (WWDC23 10033,
  <https://developer.apple.com/videos/play/wwdc2023/10033/>).
- **The license forbids it for any part that would be published.** Both the macOS
  and the iOS/iPadOS licenses allow Personal Voice "for your personal,
  non-commercial use" only. They forbid "recording, publishing or redistribution
  in a profit, non-profit, public sharing or commercial context" (READ, §1.4).
- **Recommendation: do not offer Personal Voice at all.** It might be acceptable as
  a private rehearsal cue for the person's own line. But it invites the wrong idea
  ("let my Personal Voice play my part"), it is aimed at AAC users, and it adds a
  permission prompt for nothing the product needs. This also keeps faith with
  "make people more active": your part is performed, not generated.

### 1.4 The license text (READ 2026-10-18; this is the critical question)

**macOS Tahoe 26 Software License Agreement**, §2.F, "Voices; Live Captions"
(<https://www.apple.com/legal/sla/docs/macOSTahoe.pdf>; the same words in macOS
Sequoia, <https://www.apple.com/legal/sla/docs/macOSSequoia.pdf>, and macOS
Sonoma, <https://www.apple.com/legal/sla/docs/macOSSonoma.pdf>):

> F. Voices; Live Captions. Subject to the terms and conditions of this License,
> you may: (i) use the system voices included in the Apple Software ("System
> Voices") (1) while running the Apple Software and (2) to create your own
> original content and projects for your personal, non-commercial use; (ii) use
> the Live Captions ... only for your personal, non-commercial use; and (iii) use
> the Personal Voice feature to create a voice on device that sounds like you
> ("Personal Voice") using your own personal voice for your personal,
> non-commercial use. No other creation or use of the System Voices, Live
> Captions or Personal Voice is permitted by this License, including but not
> limited to the use, reproduction, display, performance, recording, publishing
> or redistribution of any of the System Voices, Live Captions or Personal Voice
> in a profit, non-profit, public sharing or commercial context.

**iOS and iPadOS 26 Software License Agreement**, §2(f)
(<https://www.apple.com/legal/sla/docs/iOS26_iPadOS26.pdf>; iOS 18,
<https://www.apple.com/legal/sla/docs/iOS18_iPadOS18.pdf>, reads the same). It
covers "System Characters" (Genmoji, Memoji), Live Captions and Personal Voice
with the same "profit, non-profit, public sharing or commercial context"
prohibition. **It has no System Voices clause** (MEASURED: `grep -i "system
voices"` finds nothing in the English text of the iOS 17, 18 and 26 licenses).

**tvOS 26 and tvOS 18** (<https://www.apple.com/legal/sla/docs/tvOS26.pdf>):
there is no voices clause (MEASURED).

**Assessment.**
- **Live cueing on the performer's own device is permitted.** It is use "while
  running the Apple Software", by the person who owns the device, for their own
  rehearsal and recording. This is clause (i)(1) on macOS, and no clause forbids
  it on iOS.
- **A live "listen with placeholders" mode is also on the permitted side.** The
  synthesis happens on each listener's own device for that listener, the same as
  VoiceOver reading a web page aloud. It must stay live and local: no stream, no
  file, no AirPlay to a crowd, no Watch Together broadcast of a partial play.
- **Uploading audio that contains a System Voice to archive.org is not
  permitted** from a Mac. archive.org is a "public sharing ... context", and
  "non-profit" is named. From an iPhone, the license is silent: it neither grants
  nor forbids. Apple licenses some of its voices from third parties (UNVERIFIED
  which), and silence is not a license. **Treat the iOS case the same as the
  macOS case.** The owner's rule already does: the system voice never enters a
  stored file.
- **The residual risk is bleed** (§4.4). A take recorded with the cue on a speaker
  can carry the system voice into a published file. The protections in §4.4 are
  what make the rule true in practice, not just in intent.
- Not a legal opinion; the owner's call (Q1).

### 1.5 Open-licence voices: an alternative cue engine, and the only route if a placeholder must ever be stored

If the owner later wants a stored placeholder (for example, a finished play with
one part never taken), the voice must carry a license that allows public
distribution. Candidates, READ from their model cards and licence files:

| Engine | Code license | Voices / data | Fit |
|---|---|---|---|
| Kokoro-82M (<https://huggingface.co/hexgrad/Kokoro-82M>) | Apache-2.0 weights | 20 US English voices (11F 9M), 8 British (4F 4M); "trained exclusively on permissive/non-copyrighted audio data". The card also thanks contributors of "synthetic training data", whose source is not named (UNVERIFIED provenance) | Good quality; 82M parameters; ONNX builds exist |
| Piper (<https://github.com/OHF-Voice/piper1-gpl>) | **GPL-3.0** since development moved there; the old `rhasspy/piper` repo was MIT | Each voice carries its dataset's license: `en_US-ljspeech` "public domain" (LJ Speech, read from LibriVox); `en_US-libritts_r` **904 speakers, CC BY 4.0** (LibriTTS-R, from LibriVox readings); `en_GB-vctk` 109 speakers, CC BY 4.0; some voices are NC (`hfc_female`: CC BY-NC-SA) | The voices are the right kind: LibriVox volunteers reading public-domain books. GPL in an App Store app is a known conflict; use another runtime |
| sherpa-onnx (<https://github.com/k2-fsa/sherpa-onnx>) | Apache-2.0 | Runs Piper and Kokoro models on iOS, Android and WebAssembly | The runtime that sidesteps Piper's GPL code. Its espeak-ng phonemizer data's license must still be checked (UNVERIFIED) |

This also answers the web's problem (§3): a WebAssembly model produces buffers
the page can schedule. The cost is the download: tens of MB per model
(UNVERIFIED size; measure). The project rule "no AI-written copy" is not
engaged, since the voice reads a human-written public-domain script. But a
neural voice is a model output, so the owner should decide (Q3).

---

## 2. Android

### 2.1 The API surface (READ from developer.android.com, 2026-10-18)

| API | Level | Notes |
|---|---|---|
| `TextToSpeech.speak(CharSequence, int, Bundle, String)` | 21 | Plays through the engine's own `AudioTrack` |
| `synthesizeToFile(CharSequence, Bundle, File, String)` | 21 | Writes WAV. Asynchronous; completion comes through `UtteranceProgressListener` |
| `synthesizeToFile(..., ParcelFileDescriptor, ...)` | 30 | Writes to a descriptor, so a pipe can be used: in memory, no file |
| `UtteranceProgressListener.onBeginSynthesis(id, sampleRate, format, channels)` | 24 | Format of the coming PCM |
| `onAudioAvailable(id, byte[])` | 24 | "a copy of what will be synthesized to the speakers ... or written to the file system". This is how an app gets cue PCM into its own `AudioTrack` with a known length |
| `onRangeStart(id, start, end, frame)` | 26 | Word timing, only "if the engine supplies timing information" |
| `getVoices()`, `Voice.getQuality()` (`QUALITY_VERY_HIGH` = 500 ... `VERY_LOW`), `getLatency()`, `isNetworkConnectionRequired()`, `getFeatures()` | 21 | **There is no gender attribute.** Google's voice names (e.g. `en-us-x-sfg-local`) encode a voice id, not a gender. Gender must come from a hand-made map per engine (UNVERIFIED mapping) |
| `getMaxSpeechInputLength()` | 18 | One radio line is far below the limit |

**In-memory cueing on Android.** Call `synthesizeToFile` to a pipe (API 30+). Below
30, write to a temporary file in the app's cache, read it and delete it
immediately. In both cases collect `onAudioAvailable` chunks and play them in the
app's own `AudioTrack` or Media3 graph. Under the owner's rule, a cache file that
lives for milliseconds and is never uploaded is processing, not storage. But
prefer the pipe where the OS allows it.

**Engines.** Android TTS is pluggable. Most Play devices run "Speech Services by
Google" (`com.google.android.tts`), whose voices are local or network
(`isNetworkConnectionRequired`). A network voice sends the script line to Google;
the privacy policy has to say so, or the app should cast local voices only.
Samsung devices often default to Samsung's engine (UNVERIFIED). Fire OS ships
Amazon's engine (UNVERIFIED), and Fire TV is not a recording surface anyway.

**Terms on distributing output.** The Play listing for Speech Services by Google
links only to the general Google Terms of Service and Play Terms (MEASURED: the
listing's links). No output-specific license was found. A Google engineer, on the
W3C Speech API list in 2012: *"the license for some text-to-speech engines
specifically forbids saving the audio data and playing it back later - or it only
allows it for personal use; for example it's not allowed to stream the speech to
multiple users without purchasing a more expensive license"* (READ,
<https://lists.w3.org/Archives/Public/public-speech-api/2012Jul/0001.html>).
Treat device voices on Android exactly as on Apple: live and local only.

### 2.2 Recording sources (READ)

| `MediaRecorder.AudioSource` | Level | Use |
|---|---|---|
| `VOICE_PERFORMANCE` | 29 | "audio meant to be processed in real time and played back for live performance (e.g karaoke). The capture path will minimize latency and coupling with playback path." The best fit with headphones on |
| `UNPROCESSED` | 24 | Raw, "if available". The cleanest master, with no AGC or noise suppression |
| `VOICE_COMMUNICATION` | 11 | "will for instance take advantage of echo cancellation or automatic gain control if available". The no-headphones fallback |
| `AcousticEchoCanceler.isAvailable()` / `NoiseSuppressor` | 16 | Per-device; whether the app's own TTS stream is the echo reference depends on the device (UNVERIFIED; measure) |

---

## 3. Web (Web Speech API)

- `speechSynthesis` has `speak`, `cancel`, `pause`, `resume` and `getVoices()`,
  and nothing that returns audio (READ: the IDL in the Draft Community Group
  Report of 15 October 2026, <https://webaudio.github.io/web-speech-api/>).
  `SpeechSynthesisVoice.localService` is `false` for "voices supplied by a remote
  speech synthesizer service". Chrome's "Google US English" voices are remote
  (UNVERIFIED per browser), so the script is sent to Google.
- **No capture.** Speech plays through the OS speech service, not through a Web
  Audio node. The workarounds don't fit:
  - `getDisplayMedia` tab or system audio capture needs a picker each time,
    differs by browser and OS, and is unsupported on mobile Safari (UNVERIFIED).
  - An open-licence WebAssembly voice (§1.5) is the real alternative.
- **What the web can do:** play cues with `speechSynthesis` and use the `onend`
  event to start listening; record with `getUserMedia` plus `MediaRecorder` or an
  `AudioWorklet` (for PCM WAV); play human takes with Web Audio.
- **Echo cancellation.** Media Capture now defines `echoCancellation: "all"`:
  "The system MUST attempt to remove all sound being played by the system from the
  input signal". `"remote-only"` removes only WebRTC remote audio (READ,
  <https://w3c.github.io/mediacapture-main/>). Browser support for `"all"` is
  UNVERIFIED. Classic `true` has historically referenced only audio the page
  plays itself, which `speechSynthesis` output is not (UNVERIFIED). **So the web
  requires headphones.**
- On-device recognition: the same spec now has `SpeechRecognition.available()`
  and `install()`, and accepts an `audioTrack`. That makes the "did they say the
  line" check (§6.4) possible on the web where a browser supports it.

Web verdict: **recording works, with "wait for me" pacing only, headphones
required, and no sample-accurate cues.** Listening to a partial play live is
possible with the same limits.

---

## 4. The recording session: live cues against stored human takes

This is the center of the feature.

### 4.1 What plays and what is recorded

For a performer taking role R in a script of lines L1..Ln:

```
for each line Li in scene order:
  if role(Li) == R:   mark "your line" -> capture the mic -> detect the end (VAD)
  elif an approved human take exists for Li:   play that clip (prefetched from archive.org)
  else:   synthesize Li live in a cue voice, play it, release the buffer
```

Only the microphone is recorded. The output mix (takes plus cue voices) goes to
the performer's ears and nowhere else.

### 4.2 Scheduling on one clock

- **Apple.** One `AVAudioEngine`:
  - an `AVAudioPlayerNode` for human takes (decoded from MP3/FLAC);
  - a second player node for cue buffers from `write(_:toBufferCallback:)`;
  - an input tap on `inputNode` writing the master file.

  Every event (cue start, cue end, "your line" start, VAD end) is stamped in the
  engine's sample time, so the marks and the audio share one clock. Set
  `.playAndRecord` with `.allowBluetoothA2DP` and `.defaultToSpeaker`. On iOS,
  set `usesApplicationAudioSession = true` on the synthesizer so speech joins this
  session. Use a small `setPreferredIOBufferDuration` (5-10 ms).
- **Android.** Oboe/AAudio or `AudioRecord` plus `AudioTrack`, with cue PCM from
  `onAudioAvailable`. Stamp events with `AudioTrack.getTimestamp()` and
  `AudioRecord.getTimestamp()` (API 24) on one clock.
- **Web.** One `AudioContext` for takes plus a recording `AudioWorklet`. Cue
  timing comes from `speechSynthesis` events, which have unknown latency and so
  are coarse.

### 4.3 Latency and headphones

- What the performer hears is late by the output latency. What the mic captures is
  stamped late by the input latency. Apple reports both (`outputLatency`,
  `inputLatency`). Apple warns AirPlay "can result in a 2-second delay" (READ). So
  **AirPlay is refused as a recording output.**
- Bluetooth A2DP headphones add more latency, often 150-300 ms (UNVERIFIED;
  measure on AirPods).
  - With "wait for me" pacing (§5.1), the latency doesn't matter. The next cue
    starts after the performer stops, and the gap is set in the timeline later.
  - With timeline pacing (§5.2, overlaps), compensate using the reported latencies.
    Offer an optional one-time "clap" calibration for routes that misreport.
- **Bluetooth microphones are refused for masters.** HFP is narrowband. iOS 26 adds
  `bluetoothHighQualityRecording` for "certain AirPods models", but Apple notes it
  "isn't currently supported in the European Union" and "may increase input
  latency" (READ). The default route is: **headphone output, built-in or USB/wired
  microphone input**. iOS allows exactly this with `.playAndRecord` and
  `.allowBluetoothA2DP`. Apple: if both A2DP and HFP options are set, "the system
  gives hands-free ports a higher priority", so **do not set `allowBluetoothHFP`**
  (READ).
- Detect the route before recording. On Apple, check that
  `AVAudioSession.currentRoute.outputs` includes `.headphones`,
  `.bluetoothA2DP` or `.usbAudio`. On Android, check
  `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` for wired, A2DP or USB headset.

### 4.4 Keeping the cue voice out of the stored take (the license's practical edge)

1. **Headphones by default.** With no headphones, the app asks for them before
   recording starts. It is a refusal with a reason, which the "essential
   information only" rule allows.
2. **No-headphones fallback, where the platform supports it:**
   - Apple voice processing (`setVoiceProcessingEnabled(true)` on the engine's I/O
     node, iOS 13 / macOS 10.15) cancels the app's own playback. Its ducking of
     other audio is configurable from iOS 17
     (`voiceProcessingOtherAudioDuckingConfiguration`).
   - On "certain 2024 or later iPhone models", iOS 18.2's
     `setPrefersEchoCancelledInput(true)` gives echo cancellation "tuned for
     better capture of a wider range of audio signals". It is valid only with
     `.playAndRecord` and `.default` mode; check `isEchoCancelledInputAvailable`
     (READ).
   - Android: `VOICE_COMMUNICATION` plus `AcousticEchoCanceler`, device-dependent.
   - Voice processing is tuned for calls (AGC, gating), so a fallback take is a
     lesser master. The app labels it internally (`capture: "aec"`) so a later
     re-take can replace it.
3. **Slicing.** The stored clip for line Li is only the "your line" window (from
   VAD onset minus 250 ms to VAD end plus 250 ms). Cue windows are never kept, so
   bleed can only enter where a cue and the performer overlap (an interruption).
4. **The bleed gate.** On Apple and Android, the app holds the exact cue signal it
   played (§1.2). Before upload it measures the correlation between that signal
   (delayed by the route latency) and the mic in each kept window. Above a
   threshold, the line is flagged, and the performer re-takes it with headphones.
   The level of mic signal during cue-only windows (which should be room tone)
   is a second, signal-free check that also works on the web. The threshold is
   UNVERIFIED; measure it (§To measure, 4).

### 4.5 Listening to a partial play ("preview with placeholders")

This uses the same engine with no microphone. Human takes play, and the
unrecorded roles are voiced live on the listener's device. It never streams,
casts or broadcasts a system voice. AirPlay of a partial play counts as local
playback to the person's own speaker, though the latency makes it sluggish.
Watch Together-style broadcast is limited to complete, all-human plays. The cue
voices differ from device to device, and that is acceptable for a preview nobody
stores.

---

## 5. Line-level performance tools

### 5.1 Pacing modes

- **Wait for me (default).** The cue plays, the performer speaks, and VAD detects
  the end (about 600-800 ms of trailing silence; tune it). After a short "pickup"
  gap the next cue starts. The real gap between lines is set later in the
  timeline (§7.2), so pacing during recording only has to feel natural.
- **Timeline (for overlaps, interruptions and "—" cut-offs).** Cues play at fixed
  times taken from a reference timeline: the previous human takes, plus
  synthesized reference durations for the missing lines. The performer speaks
  into a window, ADR-style. This needs latency compensation (§4.3).
- **Run-up.** Before each of the performer's lines, play the previous one or two
  lines (human where recorded, cue voice where not). Allow scrubbing back a scene.

### 5.2 Teleprompter and references

- Show the current line large, the next line dim, the character name and any
  parenthetical ("(whispering)"). Scroll on VAD onset, not on a timer.
- **Reference length.** Synthesize the performer's own line in a cue voice, in
  memory only (§1.2), and show "about 4 s". It is a guide, never a target, and is
  never played unless the performer asks to hear the line read.
- **Hear it read** is a rehearsal aid. A system voice reading the performer's own
  line once on request is permitted (§1.4). It has to be optional, because the
  project's values favor the performer's own interpretation.

### 5.3 Takes, retakes and punch-in

- Each line keeps multiple takes. The performer marks a favorite, and the
  favorite is uploaded.
- **Retake a line:** run up from the previous cue, then capture again.
- **Punch-in** inside a line is not worth building. Radio lines are short, and a
  whole-line retake is simpler and sounds more natural.

### 5.4 Automatic trimming and checking

- **Trim** leading and trailing silence with VAD, keeping 250 ms handles. Apple
  offers `SpeechDetector` (VAD) from iOS/macOS 26. On iOS 18-25, use an energy
  plus zero-crossing VAD or WebRTC's VAD (BSD) on every platform.
- **Did they say the line?** Run on-device recognition:
  - Apple `SpeechTranscriber` from 26;
  - Apple `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, from iOS 13,
    plus `contextualStrings` for character names;
  - Android `SpeechRecognizer` on-device (UNVERIFIED by API level);
  - web `SpeechRecognition` where `available()` says so.

  Score word error against the script line. Over a threshold, the app asks
  "Keep it anyway?". The performer may ad-lib; never auto-reject.
- **Word alignment for the timeline.** The recognizer's word timings, or
  `write(...toMarkerCallback:)` markers for references, place the end of a line
  so an interruption can overlap it precisely.

### 5.5 Room tone

Record 5 seconds of silence at the start of each session (with an on-screen
countdown). This gives:
- a noise floor for the VAD threshold;
- a noise profile for gentle reduction in CI;
- **fill for gaps** in the mix, so cuts between performers recorded in different
  rooms don't drop to digital silence.

---

## 6. Recording formats and loudness

- **Master:** mono, 48 kHz, 24-bit (or float32) PCM, stored as **FLAC** per line.
  FLAC is lossless and about half the size of WAV. Apple Podcasts' own spec
  accepts FLAC at 16- or 24-bit and 44.1-192 kHz, and 24-bit WAV (READ,
  <https://podcasters.apple.com/support/893-audio-requirements>).
- **Derivative for playback:** MP3 or AAC. Apple's figures are 32 kbps mono MP3 at
  44.1 kHz, and 96-128 kbps for stereo mixes (READ, same page). archive.org
  derives an MP3 from an uploaded FLAC by itself (UNVERIFIED for this collection;
  see the archive.org track).
- **Loudness:**
  - Each clip's integrated loudness is measured (ITU-R BS.1770) and stored in the
    timeline as a gain. The source clip is never rewritten.
  - The final mix is normalized to **-16 LUFS integrated, -1 dBTP true peak**.
    Apple: "around -16 dB LKFS, with a +/- 1 dB tolerance ... true-peak value
    doesn't exceed -1 dB FS", per BS.1770-5 (READ, same page).
  - EBU R128's -23 LUFS is a broadcast target and too quiet for phones in a car.
    (The EBU page refused a fetch with a Cloudflare block, so the -23 figure is
    from general knowledge, UNVERIFIED here.)
- Capture setup: Apple `preferredMicrophoneMode` (iOS 15, macOS 12) reports the
  mic mode the user picked in Control Center (Standard / Voice Isolation / Wide
  Spectrum). The app can only read it and show the system picker. Store it with
  the take. Voice Isolation suits untreated rooms; Standard suits a good room.

---

## 7. Mixing and assembly

### 7.1 The canonical artifact: clips plus an edit decision list

```json
{
  "production": "aw-play-<scriptId>-<n>",
  "script": "<scriptId>@<rev>",
  "sampleRate": 48000,
  "roles": { "MARLOWE": { "pan": -0.15, "eq": "none", "takenBy": "<performerId>" } },
  "events": [
    { "line": "s1.l004", "role": "MARLOWE", "clip": "lines/s1.l004.marlowe.t2.flac",
      "in": 0.21, "out": 3.94, "gainDb": 1.8, "at": "after:s1.l003", "gap": 0.35 },
    { "cue": "SOUND", "asset": "sfx/door-creak.flac", "source": "freesound:12345 CC0",
      "at": "with:s1.l004", "offset": -0.4, "gainDb": -9 },
    { "cue": "MUSIC", "asset": "music/bridge.flac", "source": "archive.org:<id> PD-mark",
      "at": "after:s1.end", "fadeIn": 0.5, "fadeOut": 2.0, "duck": -12 }
  ]
}
```

- **Relative placement** (`after:`, `with:`, `gap`, `overlap`) rather than
  absolute seconds. A re-take that is half a second longer then ripples correctly,
  and so does a role's first recording replacing its reference length.
- The timeline is data, rendered by a pure function on every platform. This is
  Archive Watch's "computed in the pipeline, never restated in a client" lesson
  (Decision 050) applied to audio.
- **Unrecorded lines appear in the timeline only as script references**
  (`{"line": "s1.l005", "role": "VIVIAN", "clip": null}`). A player voices them
  live, and a renderer skips them or refuses (§7.3).

### 7.2 Rendering per platform (READ)

| Platform | Live playback of the timeline | Offline render (for a check or a local export) |
|---|---|---|
| Apple | `AVAudioEngine` player nodes scheduled at sample times; `AVAudioUnitEQ` and pan per role | `enableManualRenderingMode(_:format:maximumFrameCount:)` (iOS 11), or `AVMutableComposition` plus `AVAudioMix` and `AVAssetExportSession` |
| Android | Media3 / AudioTrack mixer | Media3 Transformer `Composition`: "MediaItem instances can be concatenated or mixed" (READ, <https://developer.android.com/reference/androidx/media3/transformer/Composition>); `@UnstableApi` |
| Web | `AudioContext` with `AudioBufferSourceNode.start(when)`, `StereoPannerNode`, `BiquadFilterNode` | `OfflineAudioContext.startRendering()` (READ, <https://webaudio.github.io/web-audio-api/>) |
| CI | — | ffmpeg in GitHub Actions: `adelay`/`amix` or `acrossfade`, `loudnorm` two-pass to -16 LUFS / -1 dBTP; the same runner pattern as Archive Watch's catalog workflows; $0 |

### 7.3 Mixdown policy

- **Partial play: no file.** It is heard live (§4.5).
- **Complete play** (every speaking line has an approved human take): CI renders
  `mix.flac` and an MP3 and uploads both to archive.org beside the clips and the
  timeline. A newer take, or an editor's timeline change, re-renders it. Version
  every mixdown, never overwrite one.
- **A part nobody takes** (a one-line policeman) never becomes a system voice in a
  file. Options for the owner: leave the play "incomplete" forever, let a narrator
  or director read the leftover lines, or use an open-licence voice that is
  disclosed in the credits (§1.5, Q3).

### 7.4 How professional radio drama does it (for the defaults)

Radio drama is traditionally recorded with the cast together, in perspective
around the microphones, with live spot effects. Remote and asynchronous audio
drama, the closer model here, records each actor's lines "wild" and assembles
them in a timeline, with an editor setting the gaps. This is ADR practice, and
it is what Casting Call Club-style productions do (UNVERIFIED: no primary
source fetched for these practice claims). The defaults that follow from it:
- 250-500 ms between ordinary lines;
- overlaps for interruptions;
- a slight per-role stereo spread, or mono for 1940s-style flatness;
- one shared room-tone bed;
- reverb by scene ("perspective") chosen by an editor, not by default.

All of this sits in the timeline, editable by a human editor. A model never picks
it (no AI-written choices in the product).

---

## 8. Sound effects and music

### 8.1 Mapping script cues

OTR scripts mark cues as `SOUND:` (or `SFX:`, `EFFECTS:`), `MUSIC:` (`BRIDGE`,
`STING`, `UP AND UNDER`, `OUT`), and `BIZ`. Parse them into typed timeline events
with the script's own words as the description. A human picks the asset from a
search over the sources below. Candidate matching by tag search is fine, but the
choice is made by a person. Until an asset is chosen, a cue is shown in the
teleprompter as text and is silent in playback.

### 8.2 Sources

| Source | License | Use |
|---|---|---|
| **Freesound** (<https://freesound.org/docs/api/>) | Per sound; filter to CC0 (CC BY is usable with credit in the timeline; skip NC) | Search and previews take an API token; "the original file ... Download Sound (OAuth2 required)" (search result quoting <https://freesound.org/docs/api/overview.html>; freesound.org refused direct fetches from this environment, so the API terms are UNVERIFIED here). OAuth2 means each editor signs in, or CI holds one account's token. Store the sound id and license in the event |
| **archive.org sound effects** | Per item | MEASURED 2026-10-18: 3,582 audio items match "sound effects", and 447 carry a public-domain-family `licenseurl` (CC0 or PD Mark). **An uploader's licence claim is not evidence** (Decision 140's lesson). Examples: `designers-choice-complete` (CC0, creator Nicholas A. Judy) is plausible; `freesound_community-footsteps-stairs-fast-90220` has no licence and a personal uploader, so it is a re-upload of someone else's sound. Use only items whose creator is the uploader or whose source is cited |
| **Musopen** (<https://musopen.org>) | Its own recordings are CC0 or PD-marked | MEASURED: 17 archive.org Musopen items carry CC0 or PD-mark licences (e.g. `musopen-chopin-complete-works-flac` CC0, `musopen-lossless-dvd-flac` PD-mark). Some "Musopen" items are third parties' CC BY-NC-ND readings and are excluded |
| **archive.org 78 rpm (Great 78 Project)** | Recording under §1401 (02-rights §1): only pre-1926 recordings in 2026 | Pre-1926 78s are usable; anything later is not. The composition is a second layer (02-rights §3.2) |
| **US government** (NASA, NPS) | 17 USC §105 | NASA's audio is public domain; check per item |
| **BBC Sound Effects** (<https://sound-effects.bbcrewind.co.uk>) | **RemArc licence, not open** | READ (<https://raw.githubusercontent.com/bbcarchdev/Remarc/master/doc/2016.09.27_RemArc_Content%20licence_Terms%20of%20Use_final.pdf>): allowed "For non-commercial, personal or research purposes" and formal education; "for commercial purposes ... for non-profit and government organisations ... you'll need to get our permission first". A public archive.org production is outside this. **Excluded** |

A **house library** is the practical answer: about 200 cleared, loudness-matched
effects and bridges, uploaded once to an archive.org item with each one's
provenance. Productions then reference it, and no editor needs a Freesound
account.

---

## 9. Capability matrix

| | iOS / iPadOS (18 floor) | macOS | tvOS | Android phone (7 / Play) | Google TV / Fire TV | Roku | Web |
|---|---|---|---|---|---|---|---|
| Live cue voices | Yes (`write` to buffers, iOS 13+) | Yes | Yes (no mic) | Yes (`onAudioAvailable` 24+; pipe 30+) | Yes, preview only | UNVERIFIED (`roTextToSpeech`?); preview only | Yes, `speechSynthesis`, no buffers |
| Voice gender for casting | `gender` | `gender` | `gender` | No (needs a hand map) | — | — | No (name only) |
| Sample-accurate cue scheduling | Yes | Yes | — | Yes | — | — | No |
| Record a master | Yes | Yes | No (Apple: "input hardware isn't available in tvOS"; Continuity mic aside) | Yes (`VOICE_PERFORMANCE` 29+, `UNPROCESSED` 24+) | No | No | Yes (`getUserMedia`) |
| No-headphones echo cancellation | Voice processing; iOS 18.2+ echo-cancelled input on 2024+ iPhones | Voice processing | — | `VOICE_COMMUNICATION` + AEC, varies by device | — | — | `echoCancellation: "all"` (support UNVERIFIED) |
| Bleed gate against the exact cue | Yes | Yes | — | Yes | — | — | Level-only |
| On-device line check | `SFSpeechRecognizer` on-device (13+), `SpeechTranscriber` (26+) | Same | — | `SpeechRecognizer` (UNVERIFIED on-device level) | — | — | `SpeechRecognition` where available |
| Live partial-play preview | Yes | Yes | Yes | Yes | Yes | UNVERIFIED | Yes |
| Offline mix render | Yes | Yes | Yes | Yes (Transformer, unstable API) | — | — | Yes (`OfflineAudioContext`) |
| **Verdict** | **Full** | **Full** (the best editing seat) | Listen only | **Full**, varies by device | Listen only | Listen to complete plays | **Record with limits; listen** |

---

## Risks and open owner questions

1. **Q1 (license posture).** Is "system voices are live cues only; the bleed gate
   and slicing keep them out of stored takes" enough? Or must uploads also require
   headphones (refusing AEC-fallback takes)? Recommendation: allow fallback takes,
   flag them, and run the bleed gate on all of them.
2. **Q2 (preview).** Should the live partial-play preview be offered to everyone or
   only to the production's own cast? The license view (§1.4) permits both. The
   product question is whether a half-voiced play should face the public at all.
3. **Q3 (a part nobody takes).** Leave the play incomplete, let a narrator or
   director read the leftovers, or use a disclosed open-licence voice (Kokoro or
   Piper LibriTTS-R, §1.5)? This is the only path where a synthetic voice could
   ever be stored, and it needs the owner's word.
4. **Q4 (Personal Voice).** Recommend not offering it (§1.3). Confirm.
5. **Risk: thin voice lists.** A fresh iPhone may have one or two English voices,
   and casting will repeat them. Mitigations: the character name on screen, pitch
   and rate variation, and a "more voices are in Settings" pointer.
6. **Risk: Android variance.** Echo cancellation, `UNPROCESSED` support and engine
   voices differ by manufacturer, so test on the Pixel 8a plus one Samsung.
7. **Risk: network voices leak the script.** Remote voices on the web and on Google
   TTS send each line to a server. Prefer local voices (`localService`,
   `!isNetworkConnectionRequired`) and say so in the privacy policy.
8. **Risk: Freesound OAuth and terms** were not read directly (blocked from here),
   so treat API use as UNVERIFIED until read.
9. **Risk: an uploader's licence claim on archive.org SFX** is not evidence. Accept
   only corroborated items.

## To measure

```sh
# 1. Voice inventory per bench device (Swift snippet in a DEBUG door):
#    AVSpeechSynthesisVoice.speechVoices().filter{ $0.language.hasPrefix("en") }
#      .map{ ($0.name, $0.quality.rawValue, $0.gender.rawValue, $0.voiceTraits) }
#    Report the count by quality and gender on the iPhone 12, iPhone 15 Pro, iPad Pro and Mac.
# 2. write(_:toBufferCallback:) per voice class: buffer count > 0, rendered seconds
#    against wall-clock seconds (faster than real time?), and format (audioFileSettings).
#    Include Premium, Novelty and a third-party provider voice.
# 3. Round-trip latency: built-in speaker, wired, AirPods (A2DP) on iPhone; Pixel 8a
#    wired/A2DP. Play a click through the cue node, record it through the mic, and
#    compare with outputLatency + inputLatency.
# 4. Bleed: play a cue on the speaker at normal volume, record with
#    (a) no processing, (b) voice processing, (c) prefersEchoCancelledInput (2024+ iPhone),
#    (d) Android VOICE_COMMUNICATION + AEC, (e) Chrome getUserMedia {echoCancellation:"all"}.
#    Measure residual cue energy (dB below the direct speech) and set the gate threshold.
# 5. Android voices: TextToSpeech.getVoices() on the Pixel 8a and a Samsung; count
#    local vs network en-* voices; check whether onAudioAvailable fires during synthesizeToFile.
# 6. Web: list speechSynthesis.getVoices() with localService on Chrome, Safari and Firefox (desktop and mobile).
# 7. Open voices: sherpa-onnx Kokoro and Piper (libritts_r) model sizes and real-time
#    factor on an iPhone 12 and in WebAssembly; read the espeak-ng data licence.
# 8. archive.org: does a FLAC upload to a new item get an MP3 derivative, and how fast?
# 9. Freesound: read the API terms (docs/api/terms) from a network that reaches it.
```

## Sources

- Apple SLAs, READ 2026-10-18: macOS Tahoe <https://www.apple.com/legal/sla/docs/macOSTahoe.pdf>,
  Sequoia <https://www.apple.com/legal/sla/docs/macOSSequoia.pdf>, Sonoma
  <https://www.apple.com/legal/sla/docs/macOSSonoma.pdf>; iOS/iPadOS 26
  <https://www.apple.com/legal/sla/docs/iOS26_iPadOS26.pdf>, 18
  <https://www.apple.com/legal/sla/docs/iOS18_iPadOS18.pdf>, 17
  <https://www.apple.com/legal/sla/docs/iOS17_iPadOS17.pdf>; tvOS 26
  <https://www.apple.com/legal/sla/docs/tvOS26.pdf>
- Apple developer documentation (all under <https://developer.apple.com/documentation/avfaudio/>):
  AVSpeechSynthesizer, `write(_:toBufferCallback:)`,
  `write(_:toBufferCallback:toMarkerCallback:)`, `usesApplicationAudioSession`,
  `requestPersonalVoiceAuthorization(completionHandler:)`, AVSpeechUtterance,
  `init(ssmlRepresentation:)`, AVSpeechSynthesisVoice, `audioFileSettings`,
  AVSpeechSynthesisVoiceQuality `.premium`, AVSpeechSynthesisVoice.Traits,
  AVAudioIONode `setVoiceProcessingEnabled(_:)`, AVAudioInputNode
  `voiceProcessingOtherAudioDuckingConfiguration`, AVAudioSession
  `setPrefersEchoCancelledInput(_:)`, `isEchoCancelledInputAvailable`,
  `outputLatency`, `inputLatency`, `setPreferredIOBufferDuration(_:)`, Mode
  `voiceChat`, CategoryOptions `allowBluetoothA2DP`,
  `bluetoothHighQualityRecording`, AVAudioEngine `inputNode`,
  `enableManualRenderingMode(_:format:maximumFrameCount:)`, AVAudioPlayerNode
  `scheduleBuffer(_:at:options:completionHandler:)`; AVFoundation AVCaptureDevice
  `preferredMicrophoneMode`; Speech `SpeechAnalyzer`, `SpeechDetector`,
  SFSpeechRecognitionRequest `requiresOnDeviceRecognition`, `contextualStrings`
- WWDC23 "Extend Speech Synthesis with personal and custom voices" <https://developer.apple.com/videos/play/wwdc2023/10033/>
- Apple Developer Forums: <https://developer.apple.com/forums/thread/682438>,
  <https://developer.apple.com/forums/thread/676726>, <https://developer.apple.com/forums/thread/714708>,
  <https://developer.apple.com/forums/thread/735893>, <https://developer.apple.com/forums/thread/758460>,
  <https://developer.apple.com/forums/thread/832465>
- Apple Podcasts audio requirements <https://podcasters.apple.com/support/893-audio-requirements>
- Android: <https://developer.android.com/reference/android/speech/tts/TextToSpeech>,
  <https://developer.android.com/reference/android/speech/tts/Voice>,
  <https://developer.android.com/reference/android/speech/tts/UtteranceProgressListener>,
  <https://developer.android.com/reference/android/media/MediaRecorder.AudioSource>,
  <https://developer.android.com/reference/android/media/audiofx/AcousticEchoCanceler>,
  <https://developer.android.com/reference/androidx/media3/transformer/Composition>;
  Speech Services by Google Play listing <https://play.google.com/store/apps/details?id=com.google.android.tts>
- Web: Web Speech API <https://webaudio.github.io/web-speech-api/>; Media Capture
  and Streams <https://w3c.github.io/mediacapture-main/>; Web Audio API
  <https://webaudio.github.io/web-audio-api/>; Mazzoni on TTS licences
  <https://lists.w3.org/Archives/Public/public-speech-api/2012Jul/0001.html>
- Open voices: <https://huggingface.co/hexgrad/Kokoro-82M> (README, VOICES.md);
  <https://github.com/rhasspy/piper> (MIT, "Development has moved");
  <https://github.com/OHF-Voice/piper1-gpl> (COPYING: GPL-3.0); Piper model cards
  <https://huggingface.co/rhasspy/piper-voices> (ljspeech, libritts_r, vctk,
  hfc_female); <https://github.com/k2-fsa/sherpa-onnx> (Apache-2.0)
- Sound effects and music: BBC RemArc licence (PDF linked in §8.2);
  <https://sound-effects.bbcrewind.co.uk>; Freesound API overview
  <https://freesound.org/docs/api/overview.html>; archive.org advancedsearch and
  metadata (MEASURED queries, §8.2); <https://musopen.org>
- Project context: `docs/research/02-rights.md` §1 (§1401), §3 (scripts, music);
  Decisions 050, 140
