---
name: live-capture-and-broadcast
description: "Use when an app captures a camera, microphone, another app's audio, or a window, mixes it with media it plays, or publishes live (RTMP/RTMPS to YouTube or Twitch, or records several sources to a file). Carries what Archive Watch's on-device broadcast studio learned on macOS, iOS, tvOS, and Android: own the small protocol and prove it against a local server with a wrong-key control; composite from the decoder, never the screen; every buffer carries its capture time and each voice is held to its own picture; steer bitrate by what the link carried; the host must be in the show; capture only what a call runs in; stream keys never typed or stored; OAuth traps; ask before an audible run. Triggers on RTMP, live stream, go live, encoder, VideoToolbox, MediaCodec, AVCaptureSession, process tap, ScreenCaptureKit, A/V sync, lip sync, audio drift, bitrate adaptation, dropped frames, stream key, YouTube Live API, multi-track recording, remote voices."
---

# Live capture and broadcast

Archive Watch's owner wanted people to watch a public-domain film
together with the whole internet, with the host on camera beside it,
and without a server or a paid encoder. The Studio that came out of
that publishes from the device itself on four platforms. Most of what
it taught is about time: when a frame was captured, when a sound was
heard, and how much the network actually carried. Those lessons apply
to any app that records or mixes more than one source, including a
radio drama recorded by several voices in different rooms.

The thesis: **every sample carries the time it was captured, and every
claim about the stream is read from the stream.**

## 1. Own the small protocol, and prove it locally first

- RTMP is a handshake, a chunk stream, four AMF0 commands, and FLV
  tags. AW wrote its own publisher (Swift, then a Kotlin port) rather
  than adding a dependency, for the same reason it owns its stream
  loader: on the day a platform changes a handshake, you can fix code
  you can read (AW Decision 127).
- **Prove the publisher against a local server before any platform
  account exists**: `mediamtx` on the Mac, `ffprobe` reading the stream
  back, and a WRONG key as the negative control that must fail. A bench
  destination on the local network needed no Local Network grant on
  iPhone or Apple TV (measured, not assumed).
- Check a library that "looks like exactly this" before adopting it.
  Media3's compositor composes media items for export; nothing in it
  takes a live camera or encodes in real time (AW Decision 129).

## 2. Composite from the decoder, never the screen

- Read decoded frames from the player (`AVPlayerItemVideoOutput` on
  Apple, an external OES texture from a `SurfaceTexture` on Android) and
  composite with the camera and overlays into the encoder's input.
  Screen capture is a fallback only if measurement says composition
  cannot hold the frame rate.
- On Android, `Player.setVideoSurface` is EXCLUSIVE: give it the
  studio's texture and the screen goes black. Draw the composed program
  twice, to the encoder's surface and to the screen, which means the
  Android host sees exactly what the audience sees. Include
  `EGL_RECORDABLE_ANDROID` in the config or the stream is silently black.
- Follow the player when it swaps items. AW's Mac player replaced its
  `AVPlayerItem` about ten seconds into a show, and the engine stayed
  attached to the old item: a black program with no error.
- A surface that tears down its player when a window closes must not do
  so when the UI merely REBUILDS the view during a live show. Ask
  whether the engine still holds the player before tearing it down.

## 3. Every buffer carries its capture time

- Stamp each buffer on one host clock at capture: the camera and
  microphone from their capture sessions' synchronization clock, a
  shared window from ScreenCaptureKit, another app's audio from its
  IOProc (AW Decision 160).
- Measure how old each picture is when it is composited, and hold each
  voice to the age of ITS OWN picture: insert or drop a few milliseconds
  of audio at a time while that voice is quiet, more only if it is
  badly off. Never a fixed delay constant: camera latency differs by
  device (a borrowed iPhone's camera is hundreds of milliseconds).
- A timer that cannot run on time merges its missed fires. Make every
  packet that is due on each tick (AW caps it at eight), or the audio
  drifts behind by one packet per missed fire. Measured on a Mac: the
  voice was 40 to 65 ms late unaligned, 2 to 13 ms aligned.
- Log the ages every few seconds in every build (`camAgeMs`,
  `micSyncMs`, catch-up counts) so a real session can be read
  afterwards, and keep an off switch as the control.
- Sample-rate mismatches are real: a call tapped at the output device's
  48 kHz resampled to a 44.1 kHz program. A 5.1 source must be folded to
  stereo before it is mixed with a voice.

## 4. Steer by what the link carried

- On a narrow link, lower the bitrate before you drop a frame. Steer by
  what the link actually carried over the last second while a queue
  stood, not by queue depth, which is a symptom (AW Decision 161).
- Step down straight to about 80% of the measured link; when a drop has
  drained, ask the encoder for a keyframe immediately so the freeze
  ends now, not at the next scheduled keyframe; step back up after ten
  clear seconds. On one throttle, dropping alone lost 263 frames,
  stepping by quarters lost 80, and stepping to the measured link lost 0.
- Never answer congestion with resolution or frame rate. And a throttle
  the program fits under proves nothing: the test must refuse to judge
  unless its control drops frames.
- Hardware encoders deliver about 70 to 75% of the rate asked; on an
  Apple TV 4K, nothing above 6 Mbps was worth asking for.

## 5. The host is in the show, and capture is limited to calls

- Going live requires the host's own camera AND microphone, present and
  allowed. Archive Watch's owner, 2026-09-24: *"Streaming a movie on
  your own serves no purpose, as the movie on its own is already
  available."* A device that cannot capture the host says why, as a
  state, not a hidden button (AW Decisions 132, 138).
- A picker that can put ANY app's audio or window on air is a way
  around the rights gate. Offer only calling apps and browsers (a call
  in a browser is how many people call), with a warning on a browser,
  and never a media player.
- A macOS process tap (`AudioHardwareCreateProcessTap`, 14.2+) captures
  one named app and excludes the rest (82 dB of isolation measured),
  which is what keeps the app's own soundtrack from being captured
  twice. It needs `NSAudioCaptureUsageDescription`; it is macOS only.
- When the media ends, the broadcast does not. Ask the PLAYER
  (`didPlayToEndTime`) rather than inferring from a frame counter, tell
  the host their audience is watching a still, and offer, not impose,
  the closing card.

## 6. Accounts, keys, and quota

- Stream keys come from OAuth'd API calls, never typed, never stored
  past the session, never logged. The quota for those calls belongs to
  the APP, shared by every host, so price each call and keep sign-in
  slim (`third-party-revocation-resilience`).
- YouTube: a write's `part=` must name every property its body sets,
  or it fails (one word blocked every go-live). `prompt=consent` alone
  never offers the Brand Account chooser; use `prompt=select_account
  consent`. A channel's first live activation can take 24 hours, so
  read readiness with a call that creates nothing and grey Go Live with
  the reason. A requested scope must also be declared on the consent
  screen, or people see "unverified app."
- macOS: `ASWebAuthenticationSession`'s completion arrives on an XPC
  queue. A closure that inherits main-actor isolation traps there under
  Swift 6 while iOS and tvOS pass; mark it `@Sendable`. Check the Mac
  Info.plist actually declares the client-id keys the build substitutes.
- On tvOS, `ASWebAuthenticationSession` hands the sign-in to a nearby
  iPhone ("Sign in with Apple Device") and the token lands on the TV, so
  the iOS OAuth client works there with no second client and no secret.
  Device-code flow is the fallback for platforms with no such hand-off.

## 7. Testing a studio without intruding

- A bench run attaches the owner's REAL camera and microphone. Skip host
  capture on the bench, or ask first.
- A muted monitor mutes the media in the broadcast too, and a test that
  measures audio plays it aloud in someone's house. Ask before any
  audible run.
- Bench doors leave debug instances running; close each after its show,
  and quit only after the show has ended (quitting mid-show raises an
  "end the broadcast?" prompt that blocks automation).
- Prove a control where its value LANDS: read the stream back from the
  server, not the setting from the UI (see `docs/ENGINEERING-PROCESS.md`).

The cost of owning all of this is a large surface to keep honest, and
AW's Studio carried several "verified" claims that had never had a
measurement. Write down the number that proves each one, or call it
unverified.
