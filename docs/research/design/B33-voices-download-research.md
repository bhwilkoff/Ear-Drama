# B33: a small download, better voices on demand (research, 2026-11-26)

Owner, 2026-11-26: "Can we also ensure that the app download remains small, but that we start working on a onboarding for the app that allows for people to download the better quality voices for their chosen device?"

Read first: Decisions 076, 078 (and its 2026-11-15 and 2026-11-22 addenda), 086, 087; PLAYS-DESIGN §2.8 rules 10 and 11; R2-kokoro-feasibility; the three Kokoro stores in code. Facts about platform APIs marked (knowledge) come from my own knowledge of the platforms, not from a fetched page, and should be checked against Apple and Google documentation before a design relies on them.

## 1. Finding: no voice model is in any store download today

The model is never bundled. Every platform already fetches it only on the person's tap, shows the size first, resumes, checks SHA-256, and offers Delete (rule 10). B33 is therefore not "shrink the build"; it is "keep it so" (a guard) and "offer the download at the right moment" (onboarding), on top of Library > Voices.

| Platform | Where the model comes from | What the person fetches | Source in code |
|---|---|---|---|
| iOS, iPadOS, macOS | GitHub Release `kokoro-model`, plain HTTPS with Range, to Application Support | 639,302,458 B on the release for v2+v3 files; the Apple set (v3: two Core ML packages, tokenizer, voices) is **532,310,241 B (508 MiB)** | apple/Core/Plays/KokoroModelStore.swift (`knownBytes`, `release`) |
| tvOS | none (KokoroLive and the store are `#if os(iOS) \|\| os(macOS)`); reads the cast only | 0 | KokoroLive.swift; R2 S6e table |
| Android | Same Release for the q8 model + Play Feature Delivery on-demand module `:kokoro` (ONNX Runtime) | 92,361,116 + 14,622,720 + 3,497 = **106,987,333 B (107 MB)** model + ~19 to 34 MB engine module (design doc says 19 MB, Decision 078 addendum says ~34 MB per device; unreconciled) = about **126 to 141 MB** | android/app/.../kokoro/KokoroModelStore.kt; android/kokoro/build.gradle.kts; app/build.gradle.kts `dynamicFeatures += ":kokoro"` |
| Web | eardrama.org/data/kokoro (assembled into the site at deploy from the same Release), fp32 in eight parts under 50 MB, to Cache Storage `ed-kokoro-v1`; offered only where WebGPU passes a self-test | **326 MB** (parts 7 x 45,000,000 + 10,532,232 + tokenizer, voices 14.6 MB) | js/kokoro-model.js; tools/fetch_kokoro_model.py; tools/assemble_site.sh |

Voices table (14,622,720 B) and tokenizer (3,497 B) are shared by every platform. Phonemes are not on the device as a model asset: the catalog builds them per play (Decision 078) and they ride with the play library entries (per-play files; the library release is 11 assets, 766 MB total, three newest 101 MB archives). So "phonemes" add nothing to a voice download.

## 2. Measured sizes

What I could and could not measure (read-only, no devices, no big downloads):

| Item | Size | How measured |
|---|---|---|
| iOS app bundle (Debug device build, DerivedData) | 50 MB, of which 45.5 MB is `EarDrama.debug.dylib` (Debug only); seed sqlite 3.3 MB, castable-scripts.json 1.8 MB, Assets.car 0.2 MB, fonts 92 KB | `du` on `Debug-iphoneos/EarDrama.app` |
| tvOS app bundle (Debug) | 27 MB | same |
| macOS app bundle (Debug) | 49 MB | same |
| Android debug APK | 107 MB (41.7 MB `classes.dex` plus split dex files; resources.arsc 1.8 MB; no model inside) | `unzip -lv` on app-debug.apk |
| App Store Connect download/install sizes (Release, per device) | **not measurable**: builds 1.1.3 (175) are VALID for iOS, tvOS, macOS, but `buildBundles` and `buildBundleFileSizes` return 403 "no allowed operations" to our API key; sizes show only in the App Store Connect page for the build | `tools/asc.py get` (GET only) |
| Play AAB / install size | not measurable here: no AAB on disk and no CI artifact kept (play-release run 45640660305 succeeded; its log shows no artifact sizes) | `gh api .../artifacts` empty for both runs |
| Web shell (js 1.8 MB, css 160 KB, fonts 148 KB, tv 64 KB) | about 2.2 MB | `du` |
| Published site | about 1.2 GB (owner's figure): `data/plays/library` 461 MB locally (`catalog/out/plays-library`), `data/kokoro` 326 MB, the rest the catalog projection | `du`, assemble_site.sh |

The Debug numbers overstate the iOS binary (debug dylib) and say nothing of App Thinning; treat them as an upper bound with no model inside. Action for the build: add one line to the Apple and Android CI workflows that prints the IPA and AAB sizes (the exported IPA and `bundletool get-size total`) so the next owner question has a number. Not done here (read-only).

The only large things in the store builds are code (Android dex is classes from Media3, Compose, Room) and a 3.3 MB seed database. Nothing in a bundle comes near the voices, which is the point: any real size risk is an accidental bundling of the model, so a guard test is the right "keep it small" mechanism (section 6).

## 3. "Better voices" per platform

### Apple (iOS, iPadOS, macOS)
- System tiers (knowledge): `AVSpeechSynthesisVoice.quality` is `.default`, `.enhanced`, `.premium`; Enhanced and Premium are downloaded by the person in Settings > Accessibility > Spoken Content > Voices (macOS: System Settings > Accessibility > Spoken Content > System Voice > Manage Voices). Apps cannot start that download and there is no public deep link to the Voices pane; `UIApplication.openSettingsURLString` opens only the app's own settings page. The app can read which tiers are installed (`speechVoices()` and `quality`) and can say "install Enhanced voices in Settings" as text only. Several sources note Siri voices (the best ones) are not exposed to `AVSpeechSynthesizer`.
- Personal Voice is already handled (LiveListen.swift: authorization status, `.isPersonalVoice`).
- Kokoro (ours): 532 MB fp32 Core ML only. Every compressed conversion failed the PyTorch check (Decision 078 addendum 2026-11-22), so there is no smaller Apple tier today. A smaller model is a new conversion that must pass the same check; not available to offer.

### Android
- Google Text-to-speech engine voices: installed or updated through the engine; an app can send `TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA` (knowledge: deprecated in practice on recent Android, behavior depends on the engine) or open `com.android.settings.TTS_SETTINGS`. Quality varies; many Google voices are network-backed unless downloaded. Samsung and others ship their own engines. The app already lists device voices best first (DeviceVoices.kt).
- Kokoro: q8 ONNX (92 MB) with fp32 activations; q8f16 yields NaN on ONNX Runtime Android, so there is only one choice (Decision 078 addendum).

### Web
- Browser voices (`speechSynthesis`): quality depends on the OS, and Chrome's network "Google" voices are not offline. Safari and iOS reuse the system voices above.
- Kokoro: fp32 326 MB, WebGPU only; browsers run q8 slower than real time (Decision 078). Cache Storage holds it; Safari without an installed web app may evict script-writable storage after about seven days of non-use (knowledge), so the web download can vanish; `navigator.storage.persist()` and `estimate()` are the tools, and the page already treats "downloaded" as a checked state.

## 4. Delivery options, with tradeoffs

### Apple
1. **Keep plain HTTPS to Application Support (today).** Free, we control versions (a new `kokoro-vN` is a data change, no app review), resumes, deletable, works the same on Mac. Costs: foreground-oriented unless a background `URLSession` is used (check: the store uses the one `APIClient`); hosting on GitHub Releases has no stated bandwidth cap for assets but is not a CDN SLA.
2. **Background Assets (Apple-hosted, 2025+; knowledge, verify).** Apple can host the pack (App Store Connect upload, up to a large allowance), the system downloads it in the background after install or on demand, even before first launch, with a progress and a pause surface. Reviews: the asset is reviewed with the build; a new model needs an asset-pack submission. Fits "download when the app is installed, no foreground wait". Costs: a new pipeline in `appstore-build-x27.yml`, per-OS availability (floors), and a second delivery path for Mac and iOS to keep identical to the Core ML check. Delivery to macOS is supported by Background Assets (knowledge).
3. **On-Demand Resources.** Older, tied to the App Store build and tags, 20 GB per app total; not the direction Apple is pushing (knowledge). Not recommended for a new pipeline.
4. **tvOS.** App ships no model; if ever needed, tvOS may write only to Caches (purgeable), which is why Kokoro is n/a there (R2 S6e). Keep n/a, and keep the sentence on screen that rule 10 requires.

### Android
1. **Today:** `:kokoro` engine module via Play Feature Delivery on demand plus the 107 MB model from the GitHub Release. Works; two fetch paths.
2. **Play Asset Delivery on-demand asset pack** (knowledge): the model as an asset pack (up to 1.5 GB per on-demand pack; fast-follow and on-demand types), delivered by Play with its own progress and wifi prompt, no GitHub dependency, removable. Review implication: models are data, allowed; a model change needs a new bundle upload, which is a Play release (the owner's rule: no new Play version until the one in review is approved), so a model fix cannot ship by data alone. Trade: loses the "new kokoro-vN without an app release" speed.
3. **Plain HTTPS to app files dir:** what the model store does. Best for fast model iteration.
Suggestion: keep (1) for the engine and put only the model behind whichever path the owner prefers; do not add asset packs unless the GitHub dependency worries the owner.

### Web
Cache Storage (today) is right: HTTP cache semantics, range via parts, Delete, SHA-256. OPFS (knowledge) is better for one big file with streaming writes and is not evicted differently on Safari; not needed for 45 MB parts. The 326 MB sits in the published site and is the largest single item of the repo-over-guideline site; Pages is a poor home for a model, but the Release is the real origin and the deploy copies it. If the Pages size matters, the web could fetch parts straight from the Release URL (CORS: GitHub release downloads redirect to objects.githubusercontent.com without permissive CORS headers, knowledge, so a Worker proxy would be needed) - not recommended; leave as is.

### Hosting source (archive.org vs GitHub)
The owner's 2026-11-19 ruling ("We are using archive.org for storage, not cloudflare. We already decided that teachers could upload the full recording under their name.") is about recordings and takes (storage of audio). It does not cover model hosting, which is project data under Apache-2.0 and already ships from GitHub Releases on all platforms. I did not find a ruling on where models live; I recommend leaving them on Releases and not proposing Cloudflare (R2, KV) per the memory. Ask once (question 1).

## 5. Onboarding precedents

- **Choice, size shown, never forced:** Apple's own Spoken Content voices list rows with the size and a cloud-download glyph; Maps offline areas, Music "Download" and Podcasts "Download" show size and wait for a tap; Google Translate offers language packs with size at first use and a Wi-Fi-only default; Duolingo and Kindle ask a one-time "download for offline?" with size. The common pattern: the app works at once with what is here, the better thing is one clearly sized button, a stopped download resumes, and Delete returns the space.
- **Wi-Fi caution:** these download on cellular only by explicit choice (rule 10: "never started for the person, on any network"); the offer can say "On Wi-Fi" as a fact when `NWPath.isExpensive` or Android's metered flag is true, since it is a warning the person cannot discover by looking (essential words rule).
- **Learning orientation (the four questions):** the voices are what the person directs (they cast the part and hear their cast as a scene partner), so choosing is part of the craft, not a settings chore. Onboarding should let a person hear one line in the better voice before they commit 532 MB, and name what changes for them (the stand-in reads the other parts while they record). It must not auto-cast for them: Decision 086 keeps the order and ticks theirs, the app only seeds. Skippable, reachable later in Library > Voices; nothing blocks recording or listening.
- **Anti-pattern to avoid:** a first-run modal wall before any content. First launch is a listening app; the offer should appear when it earns its place (the first time a person opens a script to read, cast, or record, which is where the robotic voice is felt), plus once in a quiet slot on Home or Library when Voices is untouched.

## 6. Recommendation

1. **Keep the store downloads small by rule, with a check.** Model files never enter a bundle. Add a test (`tools/test_no_model_in_bundle.py`, with a negative control) that fails if project.yml or the Android build references `kokoro-v*` files, `.mlpackage`, `.onnx` or `voices-en.bin` as bundled resources or assets, and CI prints IPA and AAB sizes each build. Record a budget in DECISIONS (suggest: iOS download under 60 MB, Android install under 60 MB, measured at Release; I could not measure either today).
2. **No new delivery pipeline now.** Plain HTTPS from the `kokoro-model` Release (Apple, model on Android, web via the site) is working, resumable, checked, and changeable without a store review. Revisit Background Assets only if a Release outage or the 532 MB Apple size becomes a real complaint; then it is the best Apple answer (Apple-hosted, background). Do not use ODR.
3. **Onboarding = one short sheet, not a flow.** "Better voices for this device": the person's device name or class, the exact size ("532 MB" iPhone, iPad, Mac; "126 MB" Android; "326 MB" web where WebGPU passes), a one-line preview button (a line in the best voice, playing a bundled-free sample: it must be rendered live, so offer preview only after download, or ship no sample and say nothing), Download and "Not now". The sheet is the same controls as Library > Voices, presented once (first time they open Read, Cast or Record, and not again after "Not now" until they open Voices). Platforms where the better voices do not apply (tvOS; web without WebGPU) show nothing.
3a. **For system voices on Apple and Android**, the sheet's second line, shown only when no Enhanced or Premium voice is installed: "Better system voices are in Settings" with the Settings button (Apple: app settings page only; Android: TTS settings intent). This is the only way to "download" them, and it is the person's step.
4. **Parity:** one Library > Voices state machine (absent, downloading, ready, failed) already exists on web, iOS, Android; the onboarding is a presentation of it. Add PARITY.md rows (Voices onboarding) and set tvOS n/a, Mac native (a sheet in the window, not a modal over the app).

## 7. Owner questions (at most three)

1. **Hosting:** keep the voice model on GitHub Releases (all platforms today) rather than archive.org or Apple/Google-hosted packs? The 2026-11-19 archive.org ruling covers recordings, not models; I will not move it unless you say.
2. **Apple size:** 532 MB is the only quality that passed the check, a big ask on a phone. Accept it as the single "Better voices" choice, or commission a smaller conversion (a new version that must pass the same PyTorch comparison) before onboarding offers it?
3. **When to offer:** the first time someone opens Read, Cast or Record (my recommendation), or at the very first launch after the intro? 
