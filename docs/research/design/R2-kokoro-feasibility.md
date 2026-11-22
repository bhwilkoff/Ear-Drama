# R2-S6: Kokoro feasibility (spike, 2026-11-15)

Phase S6 of `R2-script-reader-and-studio.md` §6 starts here. The owner chose Kokoro-82M
for downloadable voices (Decision 076). This spike measures the open risks instead of
estimating them. It covers licenses, pronunciation without eSpeak, runtime and size per
platform, and where the model lives. It also built a web prototype behind a flag. The
recommendation and the build plan follow from the measurements.

Nothing here ships to users. The web prototype loads only with `?kokoro=1`. *(Updated 2026-11-22, Decision 086: the flag is gone; the web offers Kokoro in Settings > Voices where WebGPU works, loading the engine only on download.)*

Rules this is held to (not restated below): a synthetic voice is a live stand-in, never
stored (PLAYS-DESIGN §5, Decision 055); the casting unit is §2.8's
`{ engine, voice, name, rate, pitch }`; eSpeak (GPL) and Piper (GPLv3) stay out; no
third-party Swift packages; real devices only for any device claim (this spike makes
none: phone figures below are published numbers, cited, and say so).

---

## 0. Summary

| Risk | Finding | Verdict |
|---|---|---|
| Licenses | Kokoro weights and voices Apache-2.0; misaki Apache-2.0; onnxruntime MIT; sherpa-onnx Apache-2.0 and GPL-free since 2026-10-20; Kitten nano 0.8 weights Apache-2.0 but its only phonemizer is eSpeak | Kokoro clear. Kitten out for now (§1) |
| Pronunciation without eSpeak | misaki alone: **4.0%** of words unknown, **33.5%** of lines touch one (1.15M words, 574 plays). Five eSpeak-free fixes: **1.86%** and **20.8%**. The rest go to a permissive neural guesser that is right **19%** of the time on unseen names (27% phoneme error) | Feasible **only if the catalog builds the phonemes once** and an editor can correct them. Never on the device (§2) |
| Runtime, this Mac (M3, CPU, native) | RTF fp32 0.62, fp16 0.65, **q8 0.24, q8f16 0.23** single-threaded; 0.20 / 0.21 / **0.11 / 0.11** at 4 threads | Native is comfortably real-time |
| Runtime, the web | onnxruntime-web in Chrome. WASM is single-threaded (eardrama.org can't be cross-origin isolated): **RTF 1.29** for q8f16 and q8, slower than real time on an M3. WebGPU: only **fp32 (326 MB)** is both sound and fast, RTF 0.18 to 0.21 on ordinary lines. fp16 on WebGPU is fast and **silent (NaN)**, and q8 or q8f16 on WebGPU are slow or hang | The web needs a second, 326 MB model and WebGPU (§3.3) |
| Quality per precision | Transcribed by a local Whisper, 40 lines, 2 voices: q8f16 WER 9.8% / 13.1% against fp32 10.2% / 11.5% (as intelligible). fp16 28.5%: NaN audio on CPU, and on WebGPU 7 of 8 lines silent | q8f16 on CPU paths; fp32 on WebGPU; never fp16 |
| Size and hosting | Native: q8f16 model 86.0 MB + 28 voices 14.6 MB = **100.7 MB**. Web: fp32 326 MB + voices + 29.5 MB runtime. Release assets are not CORS-readable from a browser (measured), so the web needs its own host | Native: our GitHub Release. Web: eardrama.org (Pages), in parts (§4) |
| Phones | No published Kokoro figures for iPhone 12 or Pixel 8a. Nearest: iPhone 13 Pro about 0.6 RTF (fp32, anecdotal); an arm64 Android emulator 0.58 RTF | Must be measured on the bench (S6a gate) |

**Recommendation**: build it, in this order. (1) Phonemes in the catalog, as a published
data plane. (2) Android (ONNX Runtime, the easy path). (3) Apple (Core ML conversion,
the risky path). (4) The web last, WebGPU with the fp32 model only, or not at all (Q1).
Details in §5 and §6; owner questions in §7.

---

## 1. Licenses (checked 2026-11-15)

| Component | License | Source | Notes |
|---|---|---|---|
| Kokoro-82M v1.0 weights | Apache-2.0 | <https://huggingface.co/hexgrad/Kokoro-82M> (card metadata `license: apache-2.0`; "With Apache-licensed weights, Kokoro can be deployed anywhere") | Training data: "permissive/non-copyrighted audio", plus two CC BY sets used in v1.0: Koniwa `tnc` (CC BY 3.0) and SIWIS (CC BY 4.0). The card has an attribution section; we repeat it on our model page (§6 S6c) |
| Kokoro voices (`voices/*.bin`) | Apache-2.0 (the repo's license; no separate voice license) | same repo, VOICES.md | 28 English voices: 20 US (11 F, 9 M), 8 UK (4 F, 4 M) |
| ONNX export | Apache-2.0 | <https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX> at commit `1939ad2a8e41` | The exact files measured here: `model.onnx` 325.5 MB, `model_fp16` 163.2, `model_quantized` (q8) 92.4, `model_q8f16` 86.0 |
| misaki (G2P) 0.9.4 | Apache-2.0 | <https://github.com/hexgrad/misaki>, wheel METADATA | **Its README does not say where `us_gold.json` / `us_silver.json` come from.** They are Apache by inclusion, but provenance is unstated. Owner question Q3 |
| misaki's eSpeak fallback | GPL (espeak-ng, phonemizer-fork) | misaki README: "out-of-dictionary words are handled by espeak" | **Refused.** The spike runs `fallback=None` throughout |
| spaCy + `en_core_web_sm` 3.8.0 | MIT (code and model) | model meta: `license: MIT` (trained on OntoNotes 5, "commercial (licensed by Explosion)") | Build time only (POS tags for misaki); never on a device |
| num2words 0.5.14 | LGPL (wheel METADATA) | PyPI | Build time only, in the catalog pipeline; never distributed in an app |
| g2p_en 2.1.0 (neural fallback) | Apache-2.0 | <https://github.com/Kyubyong/g2p>; network trained on CMUdict (BSD-style) | Build time only. Only its 3.3 MB numpy network is used (no nltk tagger). Weak (§2.4) |
| onnxruntime (Python, Android, web) | MIT | <https://github.com/microsoft/onnxruntime/blob/main/LICENSE> | onnxruntime-web 1.31.1 dist: `ort-wasm-simd-threaded.wasm` 14.8 MB, `.jsep.wasm` (WebGPU) 29.5 MB |
| sherpa-onnx | Apache-2.0 | <https://github.com/k2-fsa/sherpa-onnx> | **"Remove espeak-ng and piper-phonemize from sherpa-onnx (#4055)", merged 2026-10-20**: "sherpa-onnx is GPL-free after this PR." It now takes pre-phonemized input (`phoneme_codepoints` / `tokens`). Older releases bundle espeak-ng: pin ≥ the release with #4055 if ever used |
| Kitten TTS nano 0.8 | Weights Apache-2.0 | <https://huggingface.co/KittenML/kitten-tts-nano-0.8> | Its ONNX path depends on `phonemizer` + `espeakng_loader` (the `kittenml` requirements: "Lightweight ONNX models ... espeakng_loader, phonemizer"). It expects eSpeak's IPA, a different alphabet from misaki's. **Out unless someone retrains or maps it, and proves it by ear** |
| Kitten TTS 2 | Stellon Community License | R2 §5.1 | Refused (unchanged) |
| Piper | GPL-3.0 | R2 §5.1 | Refused (unchanged) |

Nothing GPL ends up in an app or on the site. num2words (LGPL) and spaCy run only in
the catalog pipeline, so their output (phoneme strings) is data, not their code.

---

## 2. Pronunciation without eSpeak

### 2.1 Method

`docs/research/design/kokoro-spike/oov2.py` (the scratch scripts are kept beside this doc).
The corpus is 574 of the 803 published plays, from <https://eardrama.org/data/plays/library/>.
The sample is 300 speech lines drawn at random (seed 76) from all 421,811 speech lines, and
the corpus pass is every 8th speech line (52,727 lines, 1.15M words). misaki 0.9.4, US
lexicon (gold + silver), with spaCy `en_core_web_sm` for tags. Every word misaki cannot
phonemize goes to a recorder that returns nothing. Kokoro drops such a word (it becomes
`❓`), so a "guessed" word is one the listener would otherwise not hear at all.

Separately counted: **spelled-out** words. misaki treats an unknown ALL-CAPS word as
initials and spells it letter by letter (`CHESTERTON` read as C-H-E-S-T-...). That is a
silent failure, worse than a skip.

### 2.2 What each fix buys (cumulative)

| Stage | 300-line sample: words guessed | lines touched | lines with a spelled-out word |
|---|---|---|---|
| S0 misaki as is | 4.08% | 36.0% | 3.3% |
| S1 + text normalization (em dashes spaced, `ſ`→s, `æ`→ae, curly quotes) | 3.86% | 33.3% | 3.3% |
| S2 + a per-play lexicon of role-name words | 3.19% | 27.0% | 0.7% |
| S3 + elisions (`-'d`→`-ed`, `o'er`, `'tis`, `on't`→on it, `i'th'`) | 2.91% | 25.0% | 0.7% |
| S4 + early-modern spelling (`haue`→have, `vpon`→upon, `Iacob`→Jacob, `selfe`→self), kept only when the lexicon knows the result | 2.04% | 21.7% | 0.7% |
| S5 + ALL-CAPS words looked up in lower case, never spelled | **2.07%** | **22.0%** | **0.0%** |
| Corpus (52,727 lines) at S0 | 4.0% | 33.5% | 2.9% |
| Corpus at S5 | **1.86%** | **20.8%** | **0.0%** |

The role-name lexicon has a median of 6 entries per play (max 72, 4,415 in all).

### 2.3 What is left (corpus, S5: 21,418 guessed tokens)

| Class | Tokens | Examples (most frequent first) |
|---|---|---|
| Capitalized: names, places, foreign words | 9,287 | Ay, Ile, Monsieur, Mortimer, Margaret, Mistris, Twere, Royall, Maiestie, Signior, Angelo, Gaveston |
| Lowercase: archaic, rare, dialect | 6,703 | th, ay, dont, wil, shouldst, wid, seest, ain, denied, knowest, yong, onely, themselues |
| Other elisions | 2,229 | H'm, d'you, ne're, thou'rt, y'are, wee'l, dar'st, Pr'ythee, nothin' |
| Old spellings the variant rules missed | 1,548 | twere, prethee, seruice, neere, beleeue, chuse, diuell, ayre, counsaile, euill |
| Tokenizer artifacts | 949 | St., Ah!, No!, Oh!, ll., Ff. |
| `-'d` the rule missed (u/v inside) | 456 | wou'd, shou'd, resolu'd, aduis'd, deceiu'd, ioyn'd, liu'd |
| Accented / non-ASCII | 200 | Sílych, Samsón, Lázar, Blanchefôret, café, Rémond, señor |
| Role names (Mc/O' forms) | 46 | McComas, O'Connell, M'Closky, D'ESTIVET |

Before the fixes, the worst classes were old spelling (11,603 tokens in lowercase shape
alone), Shakespeare's `-'d` (2,898), and role names (4,970, cut to 46 by the per-play
lexicon). Much of the remainder yields to more rules of the same kind: archaic verb
endings (`-est`, `-st`, `-eth`: shouldst, seest, knowest), `y`→`ied` (denied, which
misaki's own stemmer misses), `Ay`/`aye`, rules applied together (`wou'd` = u/v then
`'d`), and missing contractions (`dont`, `ain`). The rest is names and foreign words. No
rule finds those; a person has to.

### 2.4 The neural fallback is a last resort, not a fix

`fallback_eval.py`: g2p_en's network (Apache-2.0, trained on CMUdict) scored against
misaki's own gold pronunciations, stress removed, flaps and reduced vowels folded (`ɾ`→t,
`ᵊ`→ə, `ᵻ`→ɪ):

| Words | Exact | Phoneme error rate |
|---|---|---|
| 500 names in misaki's lexicon but not in CMUdict (never seen in training) | **18.6%** | **27.0%** |
| 500 lowercase words not in CMUdict | 27.6% | 23.7% |
| 500 names in CMUdict (seen in training: an upper bound) | 50.0% | 15.3% |

Examples of its misses: Samhain → `sˈæmhɪn` (should be `sˈWən`), Boeotia → `bOˈAtiə`,
Iroquois → `ˌɪɹOkwˈOjuz`, and the old spelling `haue` → `hˈWi`. It is better than a dropped
word and worse than a person. **So the remaining guesses must be visible to an editor,
listed in a report, and correctable in one file**, the same pattern as
`catalog/editorial/*.json`.

### 2.5 What this decides

- **The device never phonemizes play text.** The catalog builds every line's phonemes
  once, in Python with real spaCy and the measured rules, and publishes them beside the
  script (`data/plays/library/phonemes/<id>.json`). That follows the shared-data rule
  ("publish a computed value rather than mirror its algorithm"). It removes the riskiest
  part of R2 §5.2 (porting misaki and a tagger to Swift, Kotlin and JS). Clients need
  only a 114-symbol vocabulary table.
- **Size**, measured: King Lear (1,065 speech lines) is 64 KB gzipped for US phonemes and
  128 KB for US + UK, keyed by line id. That works out to about 25 MB gzipped for the whole
  library in US, fetched one play at a time, only by someone who downloaded the voices.
- **Two dialects.** The 8 UK voices expect misaki's GB lexicon (`gb_gold`). The file
  carries `us` and `gb`, and a voice reads its own.
- **One correction file**: `catalog/editorial/pronunciations.json`, word → phonemes (or
  word → a sounds-like respelling run through misaki). It overrides the lexicon, the rules
  and the guesser, and is reviewed like the other editorial files. The build report lists
  every guessed word by frequency, with the plays it appears in. The first review list is
  the top of that report; the corpus figure (21,418 guessed tokens in an eighth of 574
  plays) is mostly a long tail of names.
- Words with no phonemes are never silently dropped. The build fails a play whose
  guessed share exceeds a threshold (proposed: 5% of its words) until an editor looks.

---

## 3. Runtime

### 3.1 This Mac, native (onnxruntime 1.32.0 CPU, Apple M3, 8 lines from the plays, median of 3)

| Model | File | RTF, 4 threads | RTF, 1 thread | First short line ("Come in."), 1 thread | Peak memory growth (fp32 run) |
|---|---|---|---|---|---|
| fp32 `model.onnx` | 325.5 MB | 0.204 | 0.617 | 0.87 s | ~540 MB |
| fp16 | 163.2 MB | 0.208 | 0.653 | 0.84 s | — |
| q8 `model_quantized` | 92.4 MB | **0.106** | **0.237** | 0.31 s | — |
| q8f16 | 86.0 MB | **0.112** | **0.232** | 0.31 s | — |

RTF = synthesis time / audio length; below 1 is faster than real time. Session load is
0.2 to 0.5 s. **fp16 on CPU produced NaN samples (a silent line, "Come in.") in one of three
runs at 4 threads**: fp16 is a GPU format, so it is never shipped to a CPU path.

### 3.2 Phones: published figures only (not measured here)

| Device | Figure | Source | Strength |
|---|---|---|---|
| iPhone 13 Pro | ~0.6 RTF, fp32, after weights load | <https://huggingface.co/hexgrad/Kokoro-82M/discussions/18> | Anecdote in the model's discussion forum |
| Apple Silicon (Mac) Core ML | ~17× real time (RTF 0.06), ANE; "Apple Silicon (M1+) or A15+ for Neural Engine" | <https://huggingface.co/mattmireles/kokoro-coreml> | Mac only |
| M4 Pro, Core ML via FluidAudio | 23.2× RTFx, 1.50 GB peak RAM; first run ~15 s ANE compile, later loads ~2 s | <https://docs.fluidinference.com/tts/kokoro>, <https://docs.fluidinference.com/reference/benchmarks> | Mac only; the RAM matters on a 4 GB iPhone 12 |
| Android emulator arm64, no NNAPI | 0.58 RTF (1,075 ms for 1.9 s) | <https://soniqo.audio/benchmarks/android> | Emulator; the page *expects* 2-3× faster on Snapdragon with NNAPI (unmeasured) |
| On-device TTS survey (sherpa-onnx) | Kokoro EN v0.19 RTF 0.62, 833 MB memory | <https://voiceping-landingpage-prod.pages.dev/en/blog/research-offline-tts-eval/> | Older Kokoro; the text contradicts its own table |
| 2019-era Android | RTF 1.13 to 2.42 | R2 §5.2 | Slower than real time |

Scaling from this Mac: an M3 performance core runs q8f16 at 0.23 single-threaded. An
iPhone 12 (A14) core is roughly 0.6 to 0.7× an M3 core and a Pixel 8a (Tensor G3) core
roughly 0.5×, which suggests 0.35 to 0.5 single-threaded and better with 2 to 4 threads.
**That is an estimate, not a measurement**, and memory (the fp32 run grew ~540 MB) is the
more likely limit on a 4 GB iPhone 12. The S6a gate below measures it.

### 3.3 The web (onnxruntime-web 1.31.1, Chrome 157 headless, the prototype's own worker)

| Model / backend | Session load | RTF after the first line | First line |
|---|---|---|---|
| q8f16 (86 MB), WASM, 1 thread | 2.4 s | **1.29** | 5.7 s for 4.2 s of audio |
| q8 (92 MB), WASM, 1 thread | 0.6 to 0.9 s | **1.29 to 1.32** | 5.5 s for 4.3 s |
| q8f16, WebGPU | — | **never finished** (no result in 400 s) | — |
| q8, WebGPU | 2.1 s | 1.39 (its int8 operators fall back to the CPU) | 6.2 s for 4.3 s |
| fp16 (163 MB), WebGPU | 1.8 s | 0.11, **but the audio is NaN**: 7 of 8 lines silent (rms 0, ~65,500 NaN samples each); only the 14-symbol line was sound | — |
| **fp32 (326 MB), WebGPU** | 2.0 to 2.4 s | **0.18 to 0.21** on lines up to ~210 symbols; 0.39 to 0.92 on longer ones; 0.26 and 0.45 over two runs | 0.7 s / 1.1 s for 4.3 s |

The machine load was 4 to 13 during these runs (other sessions were running headless
Chrome too), so the browser figures are upper bounds. The long-line spikes on WebGPU fit
a recompile for each new input length. Padding renders to a few fixed lengths should
remove them; that is an S6f measurement, not assumed here. Every WebGPU figure was checked
for NaN and silence after the fp16 result. **A speed figure without a sample check is not
evidence.**

`crossOriginIsolated` is false on eardrama.org and on the harness: GitHub Pages cannot send
COOP/COEP headers, so WASM threads are unavailable. (A service worker can add those
headers, the "coi-serviceworker" technique, but that changes every page's embedding rules
and is out of scope for a voice.) **Single-threaded WASM is slower than real time even on
an M3**, so on a phone it would wait many seconds per line. The full engine path worked
in the browser: download (100.7 MB, SHA-256 checked, Cache Storage), the play's phonemes,
the worker, Web Audio playback muted. `KokoroVoice.speak` read a King Lear line in George's
voice and returned true, both on WASM (q8f16) and on WebGPU (fp32: 12.7 s for the first line,
which includes loading the 326 MB session and compiling the shaders). A line with no phonemes
returned false, so the system voice takes it. After the fp16 result the worker refuses any
render with a non-finite sample. Run against fp16, it refused ("65529 non-finite samples"),
so the line falls back instead of playing silence.

### 3.4 Quality by precision (transcription check)

`asr_check.py`: 40 random speech lines (2 to 60 words) from the 574 plays, phonemized by the
measured pipeline, rendered on CPU (onnxruntime, default threads) in Heart (`af_heart`, grade
A) and Michael (`am_michael`, C+). Each was transcribed by faster-whisper `base.en` (MIT, CPU)
and scored by word error rate against the script text. Whisper also "corrects" old spellings
(Vpon → upon counts as an error) and can't spell names, so the absolute figure has a floor
of its own. **The comparison between precisions is the measurement.**

| Model | Heart WER | Michael WER | Short lines (< 20 tokens), Heart / Michael |
|---|---|---|---|
| fp32 | 10.2% | 11.5% | 11.5% / 15.4% |
| fp16 | **28.5%** | 14.4% | 11.5% / 15.4% |
| q8 | 10.2% | 13.0% | 11.5% / 19.2% |
| **q8f16** | **9.8%** | 13.1% | 11.5% / 23.1% |

- **q8f16 is as intelligible as fp32** for Heart, and within about 1.6 points for Michael on 40
  lines, at a quarter of the size and twice the speed. The "q8 is garbled" reports (§Sources)
  don't hold for this export on CPU.
- **fp16 failed again**: Whisper heard only "you" (its usual output for silence) on several
  Heart lines, the NaN seen in §3.1.
- Short lines are Kokoro's known weak spot (VOICES.md: "Weakness on short utterances"). "Ha,
  ha!" failed in every model and voice, and "By Jove!" in some. Laughter and exclamations need
  a listening check on the bench, and maybe an editorial respelling.
- The worst line was not Kokoro's fault: The Philanderer's L0095 carries other speakers'
  names and lines inside JULIA's speech (§8).

---

## 4. Size, download and hosting

| What | Bytes |
|---|---|
| q8f16 model | 86,033,585 |
| 28 English voices, one table (28 × 510 × 256 float32) | 14,622,720 |
| Vocabulary (`tokenizer.json`) | 3,497 |
| **Total download** | **100,659,802 (101 MB)** |
| Android since S6a: q8 model (`model_quantized.onnx`, fp32 activations) instead of q8f16, `kokoro-v2-manifest.json` | 92,361,116; total **106,987,333 (107 MB)** |
| Phonemes per play, on demand | ~10 to 130 KB gzipped |
| Web only: fp32 model instead of q8f16 (§3.3) | 325,532,232 (326 MB) |
| Web only: onnxruntime-web runtime (WASM, or JSEP for WebGPU) | 14.8 MB or 29.5 MB, self-hosted |

- **Native (Apple, Android)**: a GitHub Release asset `voices-kokoro-v1` on our repo, like
  `catalog-latest`. Measured: a Release asset answers `Range: bytes=0-99` with `206` and
  `Content-Range`, so a native download can resume. Each file is pinned by SHA-256 in a
  manifest inside the app build. The manifest records each file's license, and the client
  refuses one without a permissive license (`KokoroModel.accept`, tested).
- **Web**: a different file (fp32, §3.3), and the Release asset **cannot be fetched by a browser** anyway. Measured, the
  redirect from the Release URL carries no `Access-Control-Allow-Origin`, and neither does
  the final `release-assets.githubusercontent.com` response. So the web copy is served from
  eardrama.org (Pages, beside `data/plays/library/`), split into parts under 50 MB (Pages
  refuses files over 100 MB) so a broken download resumes by part. Hugging Face serves CORS
  but is a third party we'd depend on; the Worker could proxy R2 at a cost. Owner question Q2.
- Never bundled in an app. Shown with its size before download, deletable in Settings or
  Library, and a removed model makes each Kokoro part fall back visibly (§2.8 rule 8, tested).

---

## 5. Recommendation

1. **Phonemes are catalog data.** `build_play_phonemes.py` beside `build_play_library.py`:
   misaki (no fallback) + the S1 to S5 rules + more rules (§2.3) + the role lexicon +
   `catalog/editorial/pronunciations.json` + the neural guesser as a last resort, US and GB,
   one file per play keyed by line id and revision. A report lists guesses by frequency. A
   golden test pins a dozen lines across the library, including a Shakespeare `-'d`, an
   old spelling, a role name and a caps word.
2. **Model**: q8f16 (86 MB) on CPU paths (Android, and Apple until Core ML proves a GPU or
   ANE path). fp32 for WebGPU. Never fp16: NaN measured on CPU and on WebGPU. Every
   engine's self-test checks the samples, not only the clock.
3. **Android first** (ONNX Runtime Android, MIT, a Gradle dependency): the shortest path and
   the same graph measured here. Inference on `Dispatchers.Default` with 2 to 4 intra-op
   threads, played through `AudioTrack` in float.
4. **Apple second**: Core ML only (no third-party Swift packages, so no onnxruntime-objc
   and no KokoroSwift). Convert the Apache ONNX or PyTorch weights to an `.mlpackage` in our
   own pipeline (coremltools, build time). Kokoro's variable length and its iSTFT are the
   known conversion traps; published conversions use fixed-length buckets. The S6c spike
   first proves one conversion on the Mac, then the iPhone 12. Memory is the gate.
5. **Web last, WebGPU only, fp32**: offer Kokoro on the web only where WebGPU exists and a
   two-line self-test after download renders sound (no NaN, nonzero level) below RTF 0.7.
   Otherwise the picker says so and the system voices stay. That is a 326 MB download
   (plus the 29.5 MB WebGPU runtime), more than three times the native one, which is why
   Q1 offers leaving the web out. Single-threaded WASM (1.29 on an M3) is not offered, and
   neither is fp16 (NaN).
6. **Voices in the picker**: under "Downloaded", named `Heart (Kokoro)` etc. (the chip
   needs to tell Kokoro's Daniel from the Mac's Daniel). Ordered by Kokoro's own grades:
   only four voices grade B- or better (Heart A, Bella A-, Nicole B-, Emma B-); the best male
   voices are C+ (Fenrir, Michael, Puck). Auto-cast already reads a voice's own reported
   gender, which Kokoro's ids carry (`af_` female), so it alternates without reading a part.

---

## 6. Build plan (each phase ships on every platform it names; tests seen to fail first)

| Phase | Ships | Gate before the next |
|---|---|---|
| **S6a Bench** | Measure, on the bench, with the existing harnesses (no simulators): q8f16 via ONNX Runtime on the Pixel 8a (a debug-only activity), Core ML on the iPhone 12 and iPad from the S6c conversion, WebGPU on Chrome (Pixel, Mac) and Safari 26 (iPhone, Mac). RTF, first-audio latency, peak memory, thermals over a 20-minute listen-through, all muted | RTF ≤ 0.7 and memory under 600 MB on the iPhone 12 and Pixel 8a, or the platform waits |
| **S6b Phonemes** | `build_play_phonemes.py`, the editorial pronunciation file, the guess report, publishing beside the library; `DATA-CONTRACT.md` gains the phoneme file; a catalog dry-run on real data (memory: failures must be real) | Guess share under 2% across the library; the top 200 guesses reviewed by a person |
| **S6c Model release** | Manifest (path, role, bytes, SHA-256, license per file), Release `voices-kokoro-v1` (native) and Pages parts (web), the attribution page (Kokoro, Koniwa, SIWIS) on the website | A license test refuses a manifest file without a recorded permissive license on every stack (web done here) |
| **S6d Android** | ONNX Runtime engine behind `VoiceCast` engine `kokoro`; download with size and resume; Downloaded group in the picker; fallback when absent | The never-stored guards extended to Kokoro buffers, each seen to fail; a tap on the Pixel |
| **S6e Apple** | Core ML engine (iOS, iPadOS, Mac; tvOS reads the cast only, n/a); same | Same, on the iPhone 12 and the Mac |
| **S6f Web** | The prototype here, hardened: self-hosted runtime, WebGPU-only gate, the buffer path also gives the web the correlation bleed check (R2 §5.2 item 4) | Same, in the web harness |

PARITY.md gains a "Downloadable voices" row at S6d. PLAYS-DESIGN §2.8 rule 6 already
names the "Downloaded" group. §2.8 rule 1's `engine: kokoro` is unchanged. One rule is
added at S6b: **a Kokoro line with no published phonemes is read by the part's auto-cast
system voice**, never skipped and never phonemized on the device.

### 6.1 What the web prototype in this commit does

- `js/kokoro-model.js`: flag (`?kokoro=1` / `?kokoro=0`, kept per browser), manifest
  acceptance (sizes, SHA-256, permissive license per file), download with progress into
  Cache Storage, checksum check, delete. Model bytes only, no audio path.
- `js/kokoro-voice.js`: the 28 voices (grades, dialect, the voice's own gender), `castable`,
  `chunks` (≤ 400 symbols at punctuation: VOICES.md says Kokoro rushes past ~400),
  `tokenize`, and the engine. The engine loads the play's phoneme file, renders in a worker,
  plays once through Web Audio (speed by the model, pitch by playback rate with the tempo
  compensated), and keeps nothing.
- `js/kokoro-worker.js`: onnxruntime-web from jsDelivr at a pinned version (the shipped
  build self-hosts it), WebGPU when the browser has it, else WASM. It refuses a render with
  any non-finite sample, so the system voice reads the line instead of silence playing.
- `VoiceCast.resolve` now matches engine and id. Before, a Kokoro casting could never
  resolve. `StandInVoice` hands a Kokoro part to the engine and falls back to the part's
  auto-cast system voice when Kokoro can't read the line or isn't loaded. Before, it gave
  the Kokoro voice object to `speechSynthesis`.
- The cast offers downloaded voices first (they were fetched to be used). The picker
  shows a "Downloaded" group with "Download voices (101 MB)" when the flag is on.
- `app.js` loads the two scripts only with the flag. They are not in the service worker's
  shell and not in `index.html`.
- Tests: `js/kokoro.test.js` (39 checks; five failed against the S2 code and one against
  the engine first being read at creation, listed in its header). The source scan in `js/plays.test.js` now covers `kokoro-*` (cache, IndexedDB,
  Blob, object URLs banned in the voice and worker; audio banned in the model file). Its
  four new controls were seen to fail before the rule was extended.

Not done (by design): no phoneme builder in the catalog (a spike script made two plays'
files for the harness), no published model, no UI beyond the picker group, nothing on
Apple or Android.

---

## 7. Owner questions (multiple choice; recommended first)

**Q1. Where may Kokoro run on the web?**
(a) Only where WebGPU renders sound faster than real time on that device after download,
with the 326 MB fp32 model; elsewhere the web keeps the system voices and says so.
*Recommended*: the only measured web path that is both sound and fast.
(b) Not on the web at all; Kokoro is an app feature, and the web keeps its system voices.
(c) Everywhere, with WASM where there is no WebGPU, accepting a wait longer than the line
before each line (1.29× real time on an M3, worse on phones).

**Q2. Where does the web download come from?**
(a) eardrama.org (Pages), in parts under 50 MB, beside the play library. *Recommended*: our
own host, no new service; about 341 MB of the site's 1 GB soft limit (fp32 model, voices,
runtime).
(b) Hugging Face's CDN (CORS-enabled, free, a third party that could change).
(c) Cloudflare R2 behind the existing Worker (costs nothing at today's scale, one more
moving part).

**Q3. misaki's dictionaries don't state their source.** They ship under Apache-2.0 inside
an Apache package, but the README does not say what they were built from.
(a) Accept them under the package's license and ask the author in an issue to state the
source, recording the answer in DECISIONS. *Recommended*: the license on the package is
the license we receive.
(b) Rebuild the lexicon from CMUdict (BSD-style) alone, losing misaki's stress and flap
detail and its 93k silver entries.

---

## 8. Seen on the way

- **The Philanderer (`gut-5071`) parses other speakers into JULIA's lines**: 38 of her
  speech lines carry Shaw's stage description and "CRAVEN . Henrik? CUTHBERTSON . Ibsen,
  man", so any voice, and the reader, gives those words to Julia. Speaker names written
  `NAME .` (space before the period) are not recognized as speaker turns. It is a
  `script_parse.py` defect, not fixed here. *Update, S6a (2026-11-15)*: the spike read a library
  built before the run-in speech fix (becc7bb, D1: "GRACE (reflecting). Never" opens its own
  speech). The " ." was the join of the say parts around a split-out direction ("CRAVEN" +
  "(puzzled)" + ". Henrik?"), not a spacing in the text. Measured on the current build
  (revision 731aac4167ab, the published one): 0 speeches in The Philanderer carry another
  speaker's name (the spike's copy, revision 6ec7307c62e9: 200, 32 of them Julia's). A literal
  "NAME ." occurs in the cached texts only in cast lists.

- `VoiceCast.resolve` matched only `engine: 'system'`, so the S2 code could never resolve
  a Kokoro casting (fixed here, tested).
- `StandInVoice` would have handed any non-system voice object to `speechSynthesis`
  (fixed here, tested).
- misaki's stemmer misses `-ied` past tenses ("denied") and spells unknown ALL-CAPS words
  letter by letter. Both are handled by the build rules, not by patching misaki.

## S6a on the Pixel 8a (Android, 2026-11-15): the gate PASSES with the q8 model

`KokoroBenchActivity` (DEBUG only, `android/app/src/debug/`), muted (no AudioTrack opened), 50 real
lines from three published plays (`gut-1782`, `gut-44302-3`, `gut-70684-2`; 118 characters on average),
the voices in turn, ONNX Runtime Android 1.31.1 CPU, 4 intra-op threads, thermal status 0 throughout.
PSS is the whole app process (about 215 MB before the model loads); later runs also sample PSS every
200 ms during renders, since a render's own peak is freed before the between-line sample.

| Model, session | Minutes | RTF mean / p95 | First audio p50 / p95 | Peak PSS | Gate |
|---|---|---|---|---|---|
| **q8f16 (the published model)**, arena on | 1 | n/a: **every sample NaN**, 49 s for one 154-character line, 2.2 GB | n/a | 2.2 GB | fail |
| q8f16, no graph optimization / XNNPACK | 1 each | same NaN | n/a | 2.2 GB | fail |
| q8 (`model_quantized.onnx`, 92.4 MB), arena on, 400-symbol pieces | **10** (259 lines, 1,896 s of audio) | **0.295** / 0.344 | 1,186 / 5,453 ms | **1,364 MB** | fail (memory) |
| q8, arena on, 150-symbol pieces | 3 | 0.297 / 0.345 | 1,243 / 2,711 ms | 845 MB | fail (memory) |
| q8, arena off, 400 | 3 | 0.612 / 0.781 | 2,640 / 9,558 ms | 402 MB (between lines only) | fail (speed) |
| q8, arena off, 150 | 3 | **0.793** / 0.867 | 3,775 / 7,908 ms | **517 MB** | fail (speed) |

The same q8f16 file and the same inputs (tokens from published phonemes, the voice table's row)
render sound on desktop onnxruntime 1.31.1 on an Apple M-series CPU (47,400 finite samples, peak
0.54), so the NaN is ONNX Runtime Android's fp16 path, not our inputs. ONNX Runtime 1.32.0
(2026-11-13, which fixes Arm64 fp16 grouped `Conv` packing) still renders it all-NaN (1 minute,
0 of 5 lines, 1,379 MB), so Android does not wait for a fix: it reads the q8 model.

**Second round (same bench, same 50 lines).** The arena keeps the largest render's buffers and
grows by doubling, which is where the memory went; without it every allocation goes to the system
allocator, which is where the speed went. The fix keeps the arena and hands its chunks back after
every render (`RunOptions` `memory.enable_memory_arena_shrinkage = cpu:0`), and caps a piece at
100 symbols (the existing splitter: sentence end, else comma, else space). Rows are 3 minutes
unless marked; q8 model throughout; 4 intra-op threads, 1 inter-op, unpinned, unless marked.

| Session | ORT | RTF mean / p95 | First audio p50 / p95 | Peak PSS | Gate |
|---|---|---|---|---|---|
| arena + shrink, 150-symbol pieces | 1.31.1 | 0.262 / 0.330 | 1,167 / 2,570 ms | 759 MB | fail (memory) |
| arena + shrink, 150, memory pattern off | 1.31.1 | 0.345 / 0.382 | 1,477 / 3,187 ms | 734 MB | fail (memory) |
| arena + shrink, 150, initializers outside the arena | 1.31.1 | 0.259 / 0.298 | 1,100 / 2,544 ms | 761 MB | fail (memory) |
| arena + shrink, 120 | 1.31.1 | 0.317 / 0.341 | 1,335 / 2,290 ms | 603 MB | fail (memory, by 3 MB) |
| **arena + shrink, 100** | 1.31.1 | 0.327 / 0.370 | 1,383 / 2,395 ms | 577 MB | **pass** |
| arena + shrink, 100, prepacking off | 1.31.1 | 0.331 / 0.369 | 1,379 / 2,333 ms | 574 MB | pass |
| arena + shrink, 100 | 1.32.0 | 0.323 / 0.362 | 1,404 / 2,259 ms | 581 MB | pass |
| arena + shrink, 100, memory pattern off | 1.32.0 | 0.339 / 0.366 | 1,385 / 2,356 ms | 577 MB | pass |
| arena + shrink, 80 | 1.32.0 | 0.254 / 0.293 | 833 / 1,359 ms | 576 MB | pass |
| arena off, 150, 5 threads pinned to the big cores (CPUs 6 to 9) | 1.31.1 | 0.611 / 0.705 | 2,702 / 5,292 ms | 516 MB | pass, barely on speed |
| **Shipped: arena + shrink, 100, the v2 download through the app's own store** | 1.31.1 | **10 minutes**, 231 lines, 1,945 s of audio: **0.303** / 0.356 (max 0.469) | **1,172 / 2,128 ms** | **579 MB** | **PASS** |
| **Shipped, through the on-demand `:kokoro` module** (debug bundle, `bundletool --local-testing`; the bench installed the module first: Pending, 34.5 MB downloaded, Installed) | 1.31.1 | **10 minutes**, 240 lines, 1,981 s of audio: **0.297** / 0.350 (max 0.389) | **1,101 / 2,091 ms** | **579 MB** | **PASS** |

Peak PSS sits at 574 to 581 MB for every piece cap of 100 or less, so it is set by the model and
runtime (about 405 MB once loaded) plus one short render, not by how long the run lasts; thermal
status stayed 0 (headroom 0.6 to 0.76) in every run. The shipped run began with the download
(PSS 299 MB before the model loaded, against about 240 MB in the other runs) and still peaked at
579 MB. The margin is about 20 MB, so a change to the piece cap, the thread count or the ORT
version reruns this bench before it ships.

**What shipped (Android, 2026-11-15).** The q8 model as `kokoro-v2-manifest.json` on the
`kokoro-model` Release (92,361,116 + 14,622,720 + 3,497 bytes; `tools/publish_kokoro_model.py
--version 2 --native q8 --native-only`; v1 untouched for Apple and the web), the shipped session as
`OrtKokoroRenderer.Options()` (arena on, shrink after every render, 4 threads) and
`Kokoro.PIECE_SYMBOLS = 100`. **Download on demand** (owner, same day): ONNX Runtime and the
renderer are the on-demand Play Feature Delivery module `:kokoro`, fetched with the model when the
person taps Download voices, so the base install does not grow by the engine. Measured with
bundletool 1.18.3 on the release bundles for an arm64-v8a phone: the base download is 5,660,271
bytes against main's 5,590,972 (+69 KB: the Play feature-delivery library and the install states;
the universal release APK 15,096,874 against 14,964,829), and the module is 18,651,788 bytes
(17.3 to 20.9 MB across the four ABIs), so the button reads 126 MB. The first local-testing
install crashed the base at launch: ONNX Runtime's AAR declares a startup provider, module
components merge into the base manifest, and the base could not find the class; the module's
manifest now removes it (`KokoroModuleTest` checks, with a control). The second install loaded the
module but not the runtime: ONNX Runtime on Android loads only its JNI library and leaves
`libonnxruntime.so` to the linker, which does not search SplitCompat's folder for a module installed
while the app runs; the module's entry point now loads `onnxruntime` by name first.
Not run: NNAPI and XNNPACK on the q8 graph (XNNPACK
did not help q8f16; the q8 graph's integer MatMuls are not XNNPACK ops), and the onnx-community
`model_uint8` variants (177 MB and 114 MB: bigger downloads than q8, and q8 already passes).

## S6e on the Mac (Apple, 2026-11-16): the gate passes on an M3; the iPhone 12 is not measured yet

Our own conversion (`tools/convert_kokoro_coreml.py`, hexgrad's PyTorch weights at the pinned revision, fp16 compute
with the source phase and the inverse STFT in fp32, int8 weights): `KokoroDuration` (3 token buckets, 19.9 MB) and
`KokoroDecoder` (6 frame buckets, 112.0 MB), with the voice table and tokenizer **151,355,119 bytes**, as
`kokoro-v3-apple-manifest.json` (built locally, **not published**). The converter's own checks passed: the wrappers
against kokoro's forward, SNR 46.0 dB; every bucket padded against the line alone, worst 50.4 dB. Its Core ML step
cannot run here: coremltools 9.0 segfaults loading any Core ML model on macOS 27, so every measurement below is the
Swift engine (`CoreMLKokoroRenderer` through `KokoroReader`), from the macOS test runner
(`apple/Tests/KokoroBenchTests.swift`).

| Measure | Result |
|---|---|
| Quality: Whisper base.en WER, the same 40 published lines (4 plays), Heart / Michael | PyTorch fp32 **5.8% / 6.5%**; our Core ML through the app's engine (100-symbol pieces) **7.3% / 6.2%**; no non-finite line (`kokoro-spike/coreml_asr_check.py`) |
| Compute units, 4 lines | CPU: works. GPU: works, RTF similar, footprint **977 MB**. `.all`: the Neural Engine compiler refuses the decoder (ANECCompile FAILED) and every render then fails. The engine runs on the CPU |
| Speed and memory, CPU, 3 minutes, 219 renders of 50 lines from Android's three plays, the 28 voices in turn | **RTF 0.096** (p95 0.285, max 1.05 when a bucket loads), first audio p50 0.29 s / p95 1.32 s (max 5.95 s: a first load of the 512-frame bucket), **peak footprint 350 MB**, 0 refused, thermal nominal: **passes on the Mac** |
| Size | 151 MB against Android's 107 MB. About 48 MB of the decoder is waste: each `zeros_like` on a select's other side is folded into a constant of its bucket's shape, per function, and int8-stored. Fixing it needs a reconversion on a Mac where coremltools runs |

Not measured: the iPhone 12 (the S6a gate's device for memory) and the iPad; the download through the app's store
(nothing is on the Release); first loads on a phone, where each decoder bucket's plan is built on first use and the
engine keeps two loaded (`APP_KOKORO_BENCH_KEEP` changes it). `KokoroFlag.inRelease` stays false until the iPhone run
passes.

## Sources


<https://huggingface.co/hexgrad/Kokoro-82M>, <https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md>,
<https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX>, <https://github.com/hexgrad/misaki>,
<https://github.com/KittenML/KittenTTS>, <https://huggingface.co/KittenML/kitten-tts-nano-0.8>,
<https://github.com/k2-fsa/sherpa-onnx/pull/4055>, <https://github.com/microsoft/onnxruntime/blob/main/LICENSE>,
<https://www.npmjs.com/package/onnxruntime-web>, <https://github.com/Kyubyong/g2p>,
<https://huggingface.co/hexgrad/Kokoro-82M/discussions/18>, <https://huggingface.co/mattmireles/kokoro-coreml>,
<https://docs.fluidinference.com/tts/kokoro>, <https://docs.fluidinference.com/reference/benchmarks>,
<https://soniqo.audio/benchmarks/android>, <https://voiceping-landingpage-prod.pages.dev/en/blog/research-offline-tts-eval/>,
<https://cdn.jsdelivr.net/npm/kokoro-js@1.2.0/README.md> (q8 for WASM, fp32 for WebGPU).
