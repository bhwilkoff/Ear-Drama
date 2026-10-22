---
name: camera-recognition-pipeline
description: Use when building or debugging any feature that identifies physical objects with a live camera — trading cards, labels, tickets, book spines, receipts, product packaging. Carries the on-device-first rule, the silent-wrong-beats-all failure-mode principle (fingerprint primary / OCR confirm / guarded veto), confidence-AND-margin floors, cross-frame evidence aggregation, layered recovery paths instead of loosened thresholds, the desktop CLI mirror harness with byte-identical pixel parity, and the camera-layer gotchas (EXIF orientation, multi-camera contention, rectangle under-detection). Triggers on OCR, live scan, camera scan, Vision framework, VNRecognizeTextRequest, ML Kit text recognition, image fingerprint matching, embedding match, "scanner identifies the wrong item", "scan commits the wrong record", camera pipeline, scan queue.
---

# Camera Recognition Pipeline

How to identify physical objects from a live camera feed without ever
silently committing the wrong answer. Distilled from a shipped scanner
that identifies 17k+ catalog items on-device (iOS Vision + Android ML
Kit), including a 56-iteration accuracy campaign and the wrong-commit
incidents that forced the architecture. (Origin: BOBA Playbook scan
mode.)

## Rule 0 — On-device by default

Frames never leave the device. iOS: `AVFoundation` +
`VNRecognizeTextRequest`. Android: CameraX + ML Kit Text Recognition.
This is not just a cost/latency constraint — for a camera pointed at
the user's physical possessions, on-device processing is the *right*
choice, and it's a marketing-honest privacy claim ("no image is ever
uploaded").

A web fallback (`getUserMedia` → frame → server-side OCR worker) is a
legitimate **adjunct** for users without the native apps — but it is
never the canonical scanner. Frame it as a fallback in copy and route
its surfaces through the native-app CTA.

## Rule 1 — Silent-wrong beats all other failure modes

The principle that dictates the whole architecture:

- **OCR fails partially, in success-looking ways.** A partial ID
  ("BHBF-37" arriving as "37") is itself a *real* ID for a different
  record. The resolver returns a confident hit, the app commits it,
  and the user never knows. Silent-wrong is the worst possible outcome
  for recognition UX.
- **Image-fingerprint matching fails completely, in failure-looking
  ways.** No good match → nil → "Not identified" → the user re-aims
  and retries. Loud-fail is annoying; silent-wrong is corrosive.

Therefore:

1. **Fingerprint is PRIMARY.** An embedding index over the catalog's
   reference images; the top-K candidates by distance (K≈30) form the
   candidate pool.
2. **Every other signal contributes scores, not answers.** OCR'd ID,
   OCR'd name, visually-classified attributes each add or subtract
   from candidates in the pool. No single signal commits alone.
3. **A strong veto** (e.g. −2.0) fires when a *clearly-read*
   discriminating signal (the name printed in a known region)
   contradicts a candidate.
4. **The resolver returns nil below BOTH floors**: an absolute
   confidence floor AND a margin-over-runner-up floor (e.g. score
   ≥ 1.4 AND margin ≥ 0.3). For batch extraction pipelines the same
   shape: accept only ≥ 0.85 AND top candidate ≥ 1.5× the runner-up.
   **Margin matters as much as confidence** — a high score with a
   close runner-up is an ambiguous read, not a good one.

## Rule 2 — Guard the veto so it can't fire on noise

A veto that triggers on *any* fuzzy positional match lets a
low-confidence match on background noise suppress every legitimate
candidate. Split the matcher: the veto reads only a **strict subset**
(exact substring of a cleanly-recognized token); fuzzy matches still
earn the positive bonus but never veto. Negative signals need a higher
evidentiary bar than positive ones.

## Rule 3 — Aggregate evidence across frames

Demanding one perfect frame is the wrong model; combining imperfect
frames is the single biggest accuracy lever:

- **Sliding token buffer** (~10 frames, deduped, cleared on commit) so
  signal A read in frame 3 combines with signal B read in frame 7.
- **A second, parallel preprocessing pipeline** — a contrast-stretched
  snapshot every ~600 ms feeding the *same* buffer — rescues the
  hardest inputs (glare, foil, low contrast) at ~5% of one core.
- **Tier the commit gate by confidence** instead of a flat
  N-observations rule: high-score candidates commit on 1 observation,
  medium on 2, low on 3. Keeps the anti-wrong-answer protection
  without adding lag on clean reads.

## Rule 4 — Layered recovery paths, never loosened thresholds

When a hard input class fails, add an independent recovery path;
don't soften a global threshold. The proven ladder:

1. **Strict primary parse** — the ID regex over raw tokens.
2. **Cross-token reassembly** — tokenizers split IDs across
   boundaries; also run the pattern against space-joined and
   no-space-joined token streams.
3. **Conservative character-confusion normalization** — digits↔letters
   in both directions, only the conservative pairs (O/0, I/1, S/5, B/8);
   every generated candidate must re-validate against the strict
   pattern AND exist in the catalog.
4. **Structural reconstruction** — a missing separator re-inserted.
5. **Partial-prefix narrowing** — gated on a second corroborating
   signal so it can never broadcast to many records.

The cautionary revert to keep in the log: relaxing two thresholds
together once broke a case that previously worked. **Per-input signal
quality is more variable than your test fixtures predict** — the safe
move is a new gated path, not a looser gate.

## Rule 5 — Canonicalize both sides; match on identity, not display

- ONE shared canonicalization helper (case, whitespace, punctuation)
  applied to the index, every matching pass, and the lookup. Ground
  truth carries punctuation the recognizer drops; canonicalizing only
  one side fails short values at zero edit distance.
- **Preserve non-ASCII letters** — don't quietly anglicize the catalog.
- **Word-prefix matching, not substring**: "amon" matches "Amon-Ra",
  never "Damon". Roll one matcher helper and forbid raw `.contains()`.
- **Dedupe on the canonical ID, never the display name.** A dedupe
  keyed on name silently no-ops for distinct records sharing a name —
  the chip doesn't update, the haptic doesn't fire, the queue doesn't
  append.
- **Never reverse-parse a composite ID** (`id.substringBefore('-')`)
  — it breaks when a component contains the delimiter. Look the record
  up by ID and read the canonical field.

## Rule 6 — The desktop CLI mirror harness

The biggest iteration lever. Vision (macOS) and ML Kit are the same
frameworks on desktop, so a **single-file CLI** (built with `swiftc`,
no app project) runs the *shipped* recognition pipeline against local
fixture photos in seconds:

- Print per-item: expected value, top OCR tokens, strict-pattern hit,
  loose hit, final match/miss — a verdict table you can diff between
  iterations.
- Keep fixture photos of every hard case that ever shipped a bug.
- Escalate to three tools as the feature grows: an `ocr_probe` (one
  shebang file, no build step), a detector CLI (geometry + crops), a
  recognizer CLI (full pipeline + scoring).

**The invariant that makes the harness valid: byte-identical pixel
parity.** The app must hand the pipeline the same bytes the CLI does —
never JPEG round-trip in between. On iOS:
`cgImageRepresentation` → `CIImage.oriented(_:)` →
`CIContext.createCGImage`. A fix validated in the CLI ports cleanly
ONLY if this parity holds; if the app path re-encodes, you validated a
different image.

## Rule 7 — Camera-layer gotchas

- **Correct EXIF orientation BEFORE Vision/CIImage.** Captured photos
  are sideways at the pixel level relative to their metadata; OCR on
  un-rotated pixels fails mysteriously and only on device.
- **`UIImagePickerController` is broken on multi-camera iPhones**
  (camera contention on triple-camera hardware). Use
  `AVCaptureSession` + `AVCapturePhotoOutput` pinned to
  `.builtInWideAngleCamera`.
- **Detected-rectangle anchors under-measure.** Rectangle-detection
  anchors run ~20% smaller than the physical object. For multi-object
  (grid) scans, derive crop dimensions from grid/lane spacing, not
  from anchor size, and add bleed before perspective correction.

## Rule 8 — Environment tuning before more algorithm

Cheaper and more reliable than another matching layer:

- **Capture resolution**: the default preset (~640×480) renders small
  print at 6–8 px and OCR misreads it *confidently*; 1280×720 is ~4×
  the detail in the same cost class.
- **Exposure bias** ~−2/3 EV preserves highlight detail on glossy /
  foil surfaces.
- **User-controllable torch** for dim rooms.
- **Multi-pathway preprocessing** (the parallel contrast-stretch pass
  from Rule 3) for holographic and shiny surfaces.

## Rule 9 — One coordinator, one queue, context-set destination

Scanning is a cross-cutting capability, not a per-tab feature. ONE
scan coordinator, one live-scan view, one queue-review surface. The
*invoking* surface sets the destination and default action:

| Invoked from | Destination | Default action |
|---|---|---|
| Browse/search | identify only | hold in queue; tap → detail |
| Builder/editor | current draft | add immediately; review dupes |
| Collection | chosen bucket | add to that bucket; review can change it |

Per-tab scan implementations are the anti-pattern — they drift, and
every accuracy fix has to land N times.

## Rule 10 — ROI filter with unfiltered fallback

Filtering OCR input to the on-screen guide region cuts background
noise — but breaks when the user tilts the object out of the guide.
Two-pass: filtered first (preferred), unfiltered on nil. This is safe
*because* the strict veto (Rule 2) still rejects the noise the filter
existed to catch.

## Rule 11 — Run accuracy work as a disciplined loop

- Write the exit criteria BEFORE iteration 0 (no crashes; each
  workflow end-to-end; accuracy ≥ a named baseline measured by a named
  test; explicit deferrals). The loop terminates on the checklist, not
  fatigue.
- One causal hypothesis per iteration; log reverts as first-class rows
  with the lesson.
- **Diagnostics as a deliberate iteration**: one tick that changes no
  behavior but logs the almost-committed candidates and every signal
  set per throttled tick. When a user reports a miss, you read which
  signal was absent instead of guessing.
- Tier-A tests: fast pure-logic unit tests over synthetic signal
  structures (clean, partial, single-signal, must-NOT-commit,
  ambiguous multi-candidate). Watch: platform geometry types return
  zeros under JVM test runtimes — hold plain primitives in domain
  types with a converter at the live boundary.
- Extract shared math (ROI regions, scoring) into a pure module the
  moment two call sites exist — the overlay must provably draw the
  same region the filter reads.
