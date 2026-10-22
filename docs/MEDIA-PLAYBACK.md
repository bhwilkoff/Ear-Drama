# The media playback and captions doctrine

Learned in Archive Watch's 2026 campaigns (Decision 021 onward in that
repository): streaming public-domain video from archive.org to five
platforms, then captioning it live on device. The `resilient-media-streaming`
skill carries the core loader pattern. This doc carries everything the
campaigns taught beyond it. It is for media apps only, so skip it otherwise.
Incident names refer to Archive Watch, where the full write-ups live in that
repository's `DECISIONS.md` and its `docs/decisions/` archive.

## 1. The resilient loader (the settled core)

When streaming from hosts you don't control (archives, rotating storage
nodes, idle-connection resets), own the connection: a resource-loader
delegate (Apple `AVAssetResourceLoaderDelegate` / Media3
`LoadErrorHandlingPolicy`) that serves ranged requests with a SHORT idle
timeout, resumes from the exact byte offset on any reset (never restart at
0, because the player flushes its whole buffer otherwise), streams bytes as they
arrive (never whole-chunk), pins the post-redirect storage node, and fails
over across the host's published alternate nodes on hard errors only
(5xx, 403, 404).
A timeout is the expected idle drop, never a health signal.
Diagnostics are permanent but env-gated. No bitrate ceiling: resilience is
what makes full-quality files safe.

Hard-won refinements to the core:

- **A block cache for badly-muxed files**: a long interleaved upload makes
  the player fetch tiny random sample chunks, each paying full request
  latency, for an effective 3–4 Mbps ceiling on a 100 Mbps node. Serve small
  bounded reads from aligned ~2 MB cached blocks with an LRU sized to the
  playhead's working set (~50 MB; an 8-block cap thrashed).
- **Two decoder cursors read the same bytes.** Audio and video walk an
  interleaved file separately; without a shared cache every byte is fetched
  2–3×. Only visible on a throttled network (see §5).
- **Start within a hard budget or fall back**: viewers leave at ~30 s. If
  the source cannot serve the file's bitrate at all (measured: a 5.7 Mbps
  file served at 2 Mbps), fail over to a pipeline-vetted same-title smaller
  copy, with identity vetted at BUILD time, never fuzzy-matched at runtime.
  Mid-film failures never switch copies; resume position survives the
  rebuild. And never add a "slow chunk" watchdog with a throughput floor.
  It was shipped and reverted twice (a 5.6 Mbps floor killed normal Wi-Fi;
  a 0.2 Mbps floor killed slow startup probes); the idle timeout already
  covers dead connections.
- **Host-wide connection discipline**: hammering one host's MAIN endpoints
  (metadata/images) rate-limits the whole IP and breaks even unrelated
  playback in the household. Cap connections per host, share sessions,
  never use the default shared session or a bare `AsyncImage` for grids.

## 2. The custom loader disqualifies native features

A custom scheme/loader means the receiving process cannot fetch your media.
Measured consequences, each a shipped bug:

- **Video AirPlay does not work** (Apple's own position). On route-engage,
  swap the item to a published receiver-fetchable URL; restore the loader
  on disengage. Route ALL such swaps through one helper that CHECKS the
  scheme, so new loaders must not be addable without the AirPlay check
  learning about them. Same class: Google Cast needs an https URL the
  receiver can fetch (a `blob:` track is document-scoped and invisible to
  it), and Roku's `Video` node owns networking outright.
- **OS-generated captions need a plain MP4 the system can see.** The
  OS 27 system captions (iOS, iPadOS and tvOS) were measured on a film with
  no subtitle file: the direct https URL offered a caption track, and so did
  a loopback `http://127.0.0.1` proxy serving the same plain MP4. A
  segmented HLS wrapper offered NO caption track on either device. So if you
  want the system to caption a film, keep it on a plain-MP4 path (direct or
  a local proxy) and do not wrap it in HLS. Probe for the track, and require
  emitted text before claiming the feature (see section 4).
- File-reading APIs (`AVAssetReader`, export sessions) refuse remote and
  custom-scheme assets entirely.

## 3. HLS and subtitles: the shapes that work and the bombs

Side-load subtitles as tracks; never re-encode video for them.

- Apple cannot side-load a sidecar VTT onto a progressive MP4. The native
  path is a synthesized HLS master (video + subtitle renditions). The
  loader may serve playlists, keys, and the VTT itself; **the media segment
  must stay a direct https URL** (a custom-scheme segment fails
  CoreMediaError -12881).
- A local `file://` HLS master referencing anything remote NEVER plays.
  It sits at `.unknown` forever with an empty error log. Serve local
  playlists through the loader too.
- **The single-segment memory bomb**: a one-segment HLS wrapper around a
  feature-length MP4 makes the whole film the player's atomic buffering
  unit. A low-RAM device's media server dies mid-film (-11819), the
  silent rebuild leaves an UNDEAD player (pause() does not stop a
  pipeline; only `replaceCurrentItem(nil)` does), and the double pipeline
  is your "stutter and repeated lines." On constrained devices, render the
  subtitle file in your own overlay over the plain resilient stream
  instead.
- Fix mistimed subtitle files AT THE SOURCE (pipeline re-time), the only
  route by which platforms without on-device speech get correct timing.
  Two distinct fault classes need two tools: a constant offset (audio
  alignment) and framerate DRIFT. A file whose last cue ends after the
  film is PHYSICS-provably wrong; a 23.976/25 rescale repairs the telecine
  subset. Detect on physics, never on pattern.

## 4. Live captions on device (Apple speech stack)

If you caption uncaptioned media with `SpeechAnalyzer`:

- **Transcribe AHEAD of playback with a second muted scout player at 2×**,
  tapped via `MTAudioProcessingTap`. Tapping the playing item can only
  trail the speech. Scale cue times by the scout rate; map analyzer time
  to media time by `offset + t × rate`, never by tap timestamps (they're
  film-time on macOS and compressed-time on tvOS). Pin
  `audioTimePitchAlgorithm` explicitly; drop tap buffers whose timestamps
  rewind; the display loop follows the CURRENT player and runs until
  cancelled.
- **The scout is an economy**: it earns bandwidth only after playback has
  banked buffer (start-gated), yields on depth hysteresis (not a
  fired-too-late health flag), resyncs by SEEKING (never rebuilding), and
  SURRENDERS when it mathematically cannot keep up, saying so once.
- **`AssetInventory.status(forModules:)` is the only honest capability
  signal.** Platform-SDK presence, `supportedLocale(equivalentTo:)`, and a
  granted `reserve` all mislead on model-less devices. Gate every caption
  surface on it; never advertise a feature the device cannot run.
- **Offered ≠ selected ≠ emitting.** An available caption track proves
  nothing: select it, then require EMITTED TEXT before trusting it. This
  conflation shipped four separate wrong fixes. Judge published subtitle
  files against your own transcript (word PRESENCE near expected time
  swept over offsets, never sequence alignment), with evidence floors
  scaled to the verdict's cost: condemning a human file needs 100+ heard
  words; a shift smaller than the judge's own noise (~1.5 s) is adopted
  only on dense agreement; no-verdict must stay reachable: absence of
  proof of a match is not proof of a mismatch.
- **Caption display rules**: cues never overlap (push the later one), are
  held for reading time (~2.5 words/s) divided by character count, and a
  drift correction may never rewind the schedule past the viewer's
  playhead. Late text can still be read; text for a moment already passed
  cannot.
- **Never ship machine transcription of unknown audio as subtitle FILES.**
  On poor archival audio it hallucinates coherent nonsense, and a wrong
  subtitle is worse than none. (Whisper was built, shipped, and torn out.)
  Live on-device captioning the viewer opted into is different: it's
  labeled, ephemeral, and better than a blank screen.

## 5. How this domain is verified

All of `docs/DEVICE-HARNESSES.md` applies with force here, because every
one of these bugs was invisible to logs: ship gates run on RELEASE builds
through a throttled range server (~10 Mbps, because stock `http.server` ignores
Range and feeds players garbage); localhost-served copies are the control
arm that exonerates file/network/server in one run; instruments must never
perturb the pipeline (an audio watchdog that re-attached its tap
MANUFACTURED the dropouts it reported); and the verdict is the glass (OCR
of on-screen captions against the source file, tap-metered audio), never
the player's own state flags.
