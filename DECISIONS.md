# Ear Drama — Architecture & Technology Decisions

Entries capture the *why* behind choices — not the *what* (the code
already shows that). Each entry should answer: **"what would the next
developer get wrong if they didn't know this?"** Lead with the rule,
follow with `**Why:**` and `**How to apply:**`. Append-only.

When a decision affects people and not just code, add one line:
**Who was in the room, who gains, who pays:** (who took part in the
decision, who benefits, and who bears the cost, in money, effort, or
something lost).

Invoke the `architectural-decision-log` skill when adding a new entry.

---

## Index

Entries 001-045 are in `docs/decisions/DECISIONS-001-045.md`, verbatim; 046 onward are below in full.

- 001: Vanilla HTML/CSS/JS for Web (archived)
- 002: Xcode Project at Repository Root (archived)
- 003: Shared Apple Version Config via xcconfig (archived)
- 004: SwiftUI + @Observable + SwiftData (Apple) — iOS 26 / tvOS 26 baseline (archived)
- 005: Cross-Platform Feature Parity (archived)
- 006: Kotlin + Jetpack Compose for Android (NOT KMP / CMP / Flutter / RN) (archived)
- 007: Material 3 + M3 Expressive; brand theme default, dynamic color opt-in (archived)
- 008: Android: Compose-only, no XML / AppCompat / ActionBar (archived)
- 009: Android: edge-to-edge + predictive back are non-negotiable (archived)
- 010: Universal Links / App Links: `/.well-known/` is the contract (archived)
- 011: Refresh JWT before every Worker / Storage / Edge Function call (archived)
- 012: Brand vs Semantic color split is binding on all platforms (archived)
- 013: One universal Apple target serves iPhone, iPad, and Apple TV (archived)
- 014: The platform set is a decision, not a default (archived)
- 015: Per-ecosystem sync on the user's OWN cloud; no backend to run (archived)
- 016: Shared data plane: published once, every client a consumer (archived)
- 017: tvOS persistence: Caches + App Group only (archived)
- 018: Debug/state env hooks ship in the app, as production no-ops (archived)
- 019: macOS joins the universal Apple target (amends 013) (archived)
- 020: Default Apple submission is a cloud build on a GitHub runner (archived)
- 021: Android publishes to Play via the Developer API from the CLI (archived)
- 022: Player title/metadata uses each platform's native chrome hook (archived)
- 023: Cross-platform multiplayer rides a transport seam; the protocol + arbiter live in Core (archived)
- 024: Online play is per-ecosystem native + a neutral backend; bot-first with honest labels (archived)
- 025: Cross-platform-identical values use order-independent hash-rank + golden-parity tests (archived)
- 026: Persist per-event detail, not just aggregates (archived)
- 027: Cloud Apple builds self-revoke stale auto-created Development certs (archived)
- 028: Smart TVs are two builds plus two zero-app routes, never six apps (archived)
- 029: Windows is an optional first-class platform, and CI is the Windows machine (archived)
- 030: The CI fleet runs on the split-lock / budget / guard / sweeper / auditor doctrine (archived)
- 031: A red X is reserved for broken (archived)
- 032: The agent is never the tester: changes ship on external observation (archived)
- 033: DECISIONS.md stays context-sized: index + recent entries; archives are verbatim (archived)
- 034: Markers carry their source, their timestamp, and their evidence (archived)
- 035: Account deletion is a launch requirement, and the anonymous account is an account (archived)
- 036: Bundled content is queried, never loaded: RAM is a shipping constraint (archived)
- 037: A generator's output is not the shipped artifact; re-running one must be additive (archived)
- 038: Randomness lives outside the selection pipeline (archived)
- 039: Store billing APIs disagree in shape; port the intent, never the code (archived)
- 040: Local persistence must never block launch: open in do/catch, fall back to in-memory (archived)
- 041: When the native project can't live at the repo root, a root workspace shim satisfies the CI host (archived)
- 042: Platform-free logic gets a sidecar SPM package so `swift test` runs without a simulator (archived)
- 043: Algorithmic surfaces honor the user's own moderation and explain every ranked item (archived)
- 044: Every user-visible affordance must control something real (archived)
- 045: Feature gating: keep the code, gate the single UI entry point (archived)
- 046: One canonical ID and one canonical asset per entity
- 047: Two backend postures: sync islands OR the hosted split — choose in M0
- 048: Next-OS APIs are adopted additively behind BOTH a runtime and a compile-time gate
- 049: Marketplace-adjacent features never touch money
- 050: Market data is provenance-honest, and the sold history is generated, not bought
- 051: Every third-party data dependency is presumed revocable
- 052: User-facing vocabulary is a render-layer contract over frozen schema names
- 053: The look has one source, and every platform's tokens are generated from it
- 054: Ear Drama is its own app and repository, `app.eardrama`, at eardrama.org
- 055: The catalog's rules are the owner's, carried from Archive Watch and the research
- 056: Version 1.0 is the core five, with every other platform as a stub
- 057: Signing in is optional; it syncs, and it is required to make plays with others
- 058: Listening features in 1.0: Radio evenings, Listen Together, transcripts
- 059: Shared plays in 1.0: pass the phone and invite links, radio and stage scripts, CC0
- 060: The look: the ring microphone, Big Shoulders and Public Sans, new genre hues
- 061: Playback loudness targets -21 LUFS, reached by cutting (superseded by 067 and 069)
- 062: One set of player numbers on every platform
- 063: Sign-in is verified at the Worker, which issues its own session; sync is last-write-wins per row
- 064: The palette is On Air
- 065: Listen Together rooms need no account; the host is a member and hands off
- 066: Shared plays live on the Worker, invite-only, with take audio in R2 behind the owner's switch
- 067: The owner's rulings of 2026-10-23 on plays, Radio, playback, and the shell
- 069: Volume is leveled by each platform's own dynamics processor, at one set of numbers

---

## 046 — One canonical ID and one canonical asset per entity
*Date: 2026-08-26 (from BOBA Playbook's "One ID per Card, One Image per Card")*

Every entity in a shared catalog gets exactly one canonical identifier
(a composite-ID formula defined in ONE source per language, stored as a
real field, never recomputed at runtime) and exactly one canonical
asset, enforced at the byte layer by an md5-collision guard in the
pipeline.

**Why**: identity drift is the root of the worst catalog bug classes —
wrong-entity merges, duplicate rows, one entity silently wearing
another's image. Each is invisible until a user notices, and each is
enforced only where it can be measured: the ID at the catalog layer, the
asset at the binary layer.

**How to apply**: `canonical-entity-identity` carries the formula
rules, collision audits, and the lockstep migration protocol;
`image-cdn-discipline` carries the asset-side guard.

---

## 047 — Two backend postures: sync islands OR the hosted split — choose in M0
*Date: 2026-08-26 (reconciles 015; from BOBA Playbook)*

Decision 015's sync-islands posture (each ecosystem syncs on the user's
OWN cloud; no backend to run) is the default — but it only serves
per-user data. The moment users must see EACH OTHER'S data (public
profiles, shared collections, moderation, matching), the app takes the
hosted split instead: a hosted Postgres for auth + user data ONLY,
catalog as static published artifacts, media on a zero-egress CDN, and
small serverless workers for the seams. Never both for the same data.

**Why**: the two postures were sitting unreconciled in this log — 015
assumed no backend while 011's JWT-refresh rule assumed one. The real
rule is a fork on ONE question: is any user's data read by another user?
No → sync islands (zero infrastructure). Yes → the hosted split, kept
free-tier-viable by putting only genuinely shared state in the database.

**How to apply**: record the choice as an M0 decision.
`per-ecosystem-sync-islands` for the first path;
`zero-cost-hosted-backend` for the second (roles + RLS, worker fleet,
username/handle rules, account deletion).

---

## 048 — Next-OS APIs are adopted additively behind BOTH a runtime and a compile-time gate
*Date: 2026-08-26 (from BOBA Playbook, the iOS 27 adoption + the un-submittable build)*

While the deployment floor stays on OS N, every OS N+1 API is adopted
behind `if #available(OS N+1, *)` (runtime) wrapped in a compilation
condition that only exists when building against the N+1 SDK
(`OTHER_SWIFT_FLAGS[sdk=iphoneosN+1*] = -D OSNPLUS1_SDK`), with the OS-N
path in `#else` — and the gates live in ONE Compat wrapper file.

**Why**: `#available` alone still requires the symbol in the build SDK,
so the project silently compiles ONLY under beta Xcode — and App Store
Connect rejects every beta-Xcode build. The failure surfaces at submit
time, long after the build "worked" locally. The compile-time gate keeps
the GA toolchain shippable and the beta toolchain testable from the same
source. Never bump the floor as a shortcut, and never adopt an N+1 API
that regresses an existing affordance or has no real problem behind it.

**How to apply**: recipe in `cloud-appstore-submission` Rule 6. When the
floor rises to N+1, delete the flag and the `#else` branches, keep the
runtime `#available`.

---

## 049 — Marketplace-adjacent features never touch money
*Date: 2026-08-26 (from BOBA Playbook, TRADE-DESIGN.md)*

If the app introduces users who then trade/sell with each other, the
app processes, holds, escrows, or takes a cut of NOTHING. The
architecture is pure introduction: passive matching on explicit user
inputs, a deep link to an external messaging platform, block +
mailto-report + published contact for store compliance — and the app
steps out of the transaction entirely.

**Why**: the moment funds flow through the app, marketplace-facilitator
laws trigger (multi-state tax collection, 1099-K, money-transmitter
analysis, KYC/AML) — inoperable for a small team. Hosting user-to-user
messaging triggers per-message moderation obligations and creates an
archive of dispute evidence. Subscriptions via store IAP are NOT
touching money (you sell access to your features, not a cut of their
transactions).

**How to apply**: `marketplace-adjacent-design` + seed the binding doc
from `docs/templates/TRADE-DESIGN-template.md` BEFORE building any
trading surface. Kill any proposal with a Pay button, escrow, or
per-trade fee at proposal stage.

---

## 050 — Market data is provenance-honest, and the sold history is generated, not bought
*Date: 2026-08-26 (from BOBA Playbook, the pricing rebuild)*

Every price/valuation states what KIND of data it is; an asking price
or derived estimate is never presented as market value. When no sold
data exists, the honest label ("N active listings · no sales data yet")
IS the feature. When no API will sell you transaction history, snapshot
public active listings and infer sales from vanishings — after ~60 days
you own the history.

**Why**: asking prices run 10–25% above transacted; folding them into a
"market value" silently inflates every number, and a fabricated
"Market Est." teaches users to distrust the whole surface. The
structural insight: pipelines that depend on a third party for the
scarce data are broken by design — the durable asset is the history you
generate and own.

**How to apply**: `provenance-honest-market-data` — the signal
hierarchy, vanish-inference scoring, match-precision gates, the
audit-by-pattern discipline, and the UI rules.

---

## 051 — Every third-party data dependency is presumed revocable
*Date: 2026-08-26 (from BOBA Playbook, a partner's revocation email)*

Operate so that any single external data/image/API partner can revoke
authorization without killing the product: prefer data you generate or
that the community contributes, keep provenance per record, and design
the exit before the dependency is load-bearing.

**Why**: a partner who saw the app as a competitor revoked everything
by email — data, images, mappings, lookup logic, automation — leaving
one permitted use (an outbound link). The removal took a 24-tick
compliant teardown plus a multi-thousand-record provenance backfill.
The cost of independence is paid once; the cost of dependence recurs
with every partner's mood.

**How to apply**: `third-party-revocation-resilience` for both halves —
the prevention posture and the compliant-removal loop (prohibition list
first, replacement table before deletion, frozen legacy data vs live
automation, grep-verified end state). For the monetization side of IP
you don't own: `third-party-ip-monetization`.

---

## 052 — User-facing vocabulary is a render-layer contract over frozen schema names
*Date: 2026-08-26 (from BOBA Playbook, "Weapon" over `element`)*

Schema field names are frozen (renames are migrations); what users see
is a display-vocabulary mapping recorded in the data contract and
applied identically by every client. The community's own terms win over
schema language and over generic industry terms — including deliberate,
documented exceptions where one surface correctly uses a different
word.

**Why**: users learn and own their domain's vocabulary; leaking schema
language ("Element") or conflating two domain concepts under one
borrowed term ("Rarity") robs them of it and makes every platform
translate differently. The mapping table makes the vocabulary
enforceable in review instead of tribal.

**How to apply**: fill the Display Vocabulary section of
`docs/DATA-CONTRACT.md` (template §5.5); reject PRs that render a
schema name the mapping translates.

---

## 053: The look has one source, and every platform's tokens are generated from it
*Date: 2026-10-03*

`design-tokens.json` at the repository root holds the palette (light and
dark), the type ramp, spacing, and radius. `tools/design_tokens.mjs`
writes every platform's token file from it, and
`tools/test_design_tokens.mjs` fails when any of them differs from a
fresh run or a text pair falls below WCAG AA.

**Why**: the lockstep rule was a sentence, and the starter's own
placeholders broke it: the web was white with a blue accent, Android was
dark navy with an orange primary, Windows pinned orange, Apple's
AccentColor was blue, and each type ramp had different sizes. A student
whose agent changed the look in one file would see it on one platform
only. A rule that a test holds cannot drift that way.

**How to apply**: change the look in `design-tokens.json`, run the
generator, run the test, then build and look at every platform. Never
hand-edit a generated file or a `BEGIN design-tokens` block. Each
platform still maps tokens into its own idiom by hand (Android's
`Theme.kt` slots, Windows control styles, Apple views), and Apple keeps
system text styles for Dynamic Type. A deleted platform folder is
skipped, not recreated.

---

## 054: Ear Drama is its own app and repository, `app.eardrama`, at eardrama.org

*Date: 2026-10-22*

Ear Drama ships as a separate app from Archive Watch, made from the
Universal App Template in its own public repository
(`bhwilkoff/Ear-Drama`), with the identifier `app.eardrama` on every
platform and eardrama.org as its home, as archivewatch.org is Archive
Watch's.

**Why**: the owner, 2026-10-19: *"It is definitely a separate app."*
(`catalog/DECISIONS.md` 003). On 2026-10-22 they chose the identifier and
said of the domain: *"I purchased eardrama.org and that is what I would
like to use for this like we use archivewatch.org."* (eardrama.com and
eardrama.app are registered, but not as this app's home.) Public, like
Archive Watch, because GitHub's macOS runners are free for public
repositories and the cloud build is the default ship path.

**How to apply**: never reuse Archive Watch's bundle id, App Store record,
signing secrets, or Worker; App Store guideline 4.3(a) ("Don't create
multiple Bundle IDs of the same app") is the review risk for a second app
from one template, so the two apps must stay different in kind (films vs
radio). Cross-links between them go by archive.org id. A User-Agent names
Ear Drama and eardrama.org.

---

## 055: The catalog's rules are the owner's, carried from Archive Watch and the research

*Date: 2026-10-22*

The catalog in `catalog/` keeps its own decision log
(`catalog/DECISIONS.md`), and it binds the apps as much as this file does.
These rules came over with it (`docs/research/10-repository-move.md` §5):

| Rule | Source |
|---|---|
| Take-down model for audio and images: kept when unclaimed, hidden on a claim a reader can open, removed on request; never "public domain" for unclaimed | owner 2026-10-17; catalog DECISIONS 001 |
| No paid license (no SoundExchange statutory license) | owner 2026-10-17 |
| No review queue: an image is used when its own record carries the evidence | owner 2026-10-21 |
| No AI-written lists or copy in the product; only essential information on screen; US English; no emojis | Archive Watch, owner 2026-09-22 and 09-26 |
| Real devices only for testing | Archive Watch DEVICE-TESTING |
| Brand chrome and semantic genre accents never mix | Archive Watch Decision 013 |
| A photo is never reshaped: fit at its own aspect | Archive Watch Decision 097 |
| Public domain by age follows the calendar | Archive Watch Decision 137 |
| Never recommended, always findable (Nazi-state speeches) | Archive Watch Decision 149; catalog `no_recommend` |
| A synthetic voice is a live stand-in only, never stored | owner 2026-10-18; research 08a |
| Every catalog writer is additive and merge-guarded; a run that read nothing goes red | Archive Watch Decisions 020, 093, 107 |

**Why**: they were each decided once, with a reason, during six days of
research in Archive Watch; a new repository is exactly where they would be
silently re-litigated.

**How to apply**: the skills `evidence-gated-catalog-curation` and
`internet-archive-source` carry the general form; this table is the
Ear Drama form. A new rights bucket is a rule with a paired test in
`catalog/tests/test_audio_rights.py`, never a list of ids.


---

## 056: Version 1.0 is the core five, with every other platform as a stub

*Date: 2026-10-22*

Ear Drama 1.0 is the web app, iOS/iPadOS, macOS, tvOS, and Android at full
feature parity. CarPlay, Android Auto, Android TV and Fire TV, Roku,
webOS/Tizen, watchOS, and Wear OS each exist at 1.0 as a stub: a target that
builds in CI and launches, with its PARITY.md column marked ⏳, built out only
after the core five are complete. 1.0 is done when the web app is live at
eardrama.org with the full audited catalog and the four native apps are in
beta (TestFlight and Play's internal track) for the owner to play.

**Why**: the owner, 2026-10-22: *"I want the Core Five for 1.0, but I want each
of these other platforms as a stub that should be built out once we have the
full functionality built for the core platforms."* They chose "web live,
natives in beta" as the finish line, so public store releases are a 1.x step
taken after real-device play.

**How to apply**: a stub is never a second feature set; it grows from the
core's shared code once the core is done. Request the CarPlay audio
entitlement early anyway, because Apple's review of it is slow and asking costs
nothing. The full catalog means everything the two-layer audit keeps
(catalog DECISIONS 001, 004-007), unclaimed recordings included, which is why
the public web launch waits on the registered DMCA agent.

---

## 057: Signing in is optional; it syncs, and it is required to make plays with others

*Date: 2026-10-22*

Anyone can listen without an account, with history kept on the device. Sign
in with Apple and Sign in with Google, on all five platforms, add cross-device
sync of history, queue, and followed series, and are required to record,
cast, or publish a shared play. Accounts and every shared or synced record live
on a Cloudflare Worker with D1 (Decision 047's hosted split), the stack Archive
Watch's rooms already run; personal sync rides the same Worker, so no record
lives in two stores.

**Why**: the owner, 2026-10-22: *"I think we will likely need to think about
accounts pretty quickly. We already have accounts built out for using Apple and
Google logins on our other apps, so let's start there. ... it will be very hard
for people to collaborate upon the plays/dramas together without it being tied
to their accounts."* They chose optional sign-in and the Worker over Supabase.
This replaces the research's "no account" line (AGENTS.md "What this app does").

**How to apply**: the first launch plays with zero taps (bedtime is a use;
05 §1.4). Account deletion ships with sign-in on every platform (Decision 035).
Refresh the token before every Worker call. Port the sign-in from Archive Watch
(`docs/runbooks/google-oauth-setup.md`; its PARITY "Sign-in" row) rather than
writing it again.

**Who was in the room, who gains, who pays:** the owner decided. Listeners who
never make a play pay nothing; contributors give an identity to the Worker; the
owner carries the account-deletion and moderation obligations.

---

## 058: Listening features in 1.0: Radio evenings, Listen Together, transcripts

*Date: 2026-10-22*

Beyond Continue, Series, Search, Library, the sleep timer, speed, and
downloads, 1.0 carries the Radio tab (Tonight in 19xx and genre channels on one
clock), Listen Together (SharePlay on Apple devices; Worker rooms elsewhere),
and transcripts. Archive Watch cross-links wait for 1.x.

- **Tonight in 19xx** picks the same calendar date in the best-surviving year,
  offered only above a coverage floor, with gaps shown as gaps (R9); below the
  floor it falls back to the best evening for today's weekday.
- **Series pages group by broadcast season** ("1949-50", fall to summer);
  summer replacements are their own run.
- **Transcripts** are archive.org's existing speech-to-text, labeled automatic:
  always searchable, shown on screen only where they pass a measured quality
  check (R16).

**Why**: the owner chose these on 2026-10-22 (RESEARCH §7 Q10, Q12; 05 §10 Q3,
Q4, Q11, Q12) and left the film cross-links out of 1.0.

**How to apply**: the evening builder, the season grouping, and the transcript
quality gate are pipeline outputs every client reads (the data plane), never
client logic. The coverage floor is measured over real evenings before it is
fixed, and recorded here with its number.

**Measured 2026-10-22 (loop tick 15; `catalog/tools/measure_transcripts.py`)**:
184 episodes in 25 series carry both archive.org's `.autogenerated.txt` and a
Generic Radio Workshop script. Aligned word by word, the transcript's precision
(its words that match the script, in order) has a median of 0.934, a 25th
percentile of 0.891, and a 10th of 0.782; recall of the script is 0.752 at the
median, capped by what a performance changes. The handful near zero are a
script matched to the wrong broadcast, not a bad transcript. So the transcripts
are good enough to show; the gate, which must work for episodes with no script,
is calibrated against these 184 before it is fixed here. **The gate, fixed the same night**
(`catalog/tools/transcript_gate.py`): a transcript is shown when it runs 50-220
words per minute of audio and no more than 10% of its four-word runs repeat
three or more times. On the 184 it shows 183 and hides the one real failure (a
1955 Dragnet that looped on 45% of its runs at 70 words a minute); an 80 word
floor would also have hidden two good, music-heavy transcripts (Baby Snooks
0.90, Mercury Theatre 0.87), so the floor is 50. Every transcript stays
searchable; only the text on screen is gated.

---

## 059: Shared plays in 1.0: pass the phone and invite links, radio and stage scripts, CC0

*Date: 2026-10-22*

1.0 carries phases 1 and 2 of the collaborative plays (research 08): recording
role by role on one device, then invite-only shared productions by link through
the Worker, with report, block, and filter (guideline 1.2). Radio scripts and
public-domain stage plays can both be cast, each when its own record carries
the rights evidence, with no approval queue. Contributions are dedicated CC0
and uploaded to archive.org through one Ear Drama account. A teacher account
can run a class and give consent for students under 13 (the school-authorization
route); without one, under-13s record on a device only. A synthetic voice is a
live stand-in and is never stored (Decision 055).

**Why**: the owner, 2026-10-22, chose phases 1 and 2, radio plus stage plays,
archive.org storage, and teacher-managed classes. On the license they wrote:
*"CC0 is my preferred mode, but I don't want us to allow for anyone to take the
recordings and use them for AI training or coding."* Told that CC0 waives every
right and so cannot carry that condition, and that archive.org is open to every
crawler, they chose CC0 with a clear warning over a license that restricts AI use.

**How to apply**: the consent screen says, before a first recording is uploaded,
that the recording is permanent, public, and reusable by anyone, including for
AI training and voice cloning; those words are the owner's to approve. Teacher
classes need a privacy policy that covers school consent before they open.
Stage plays need their stage directions read for radio, by the people casting
them, never rewritten by a model.

**Who was in the room, who gains, who pays:** the owner decided. Families,
classes, and performers gain a stage; contributors give up control of their
recordings for good, which is why the warning is plain; teachers carry
consent for their students.

---

## 060: The look: the ring microphone, Big Shoulders and Public Sans, new genre hues

*Date: 2026-10-22*

The app icon is the CC0 Western Electric ring microphone, cut out on a flat
ground (09 §2.3, candidate 1). Big Shoulders sets display type and the
wordmark; body text is the system face on Apple and Android; Public Sans is
bundled only on the web, Roku, and store art, and the web may self-host the two
faces. Genres get a new hue set of Ear Drama's own rather than Archive Watch's
hues with new meanings. The brand palette is not chosen yet: it waits on
research that starts from the Human Shaped color work.

**Why**: the owner, 2026-10-22, chose B4/B5, B6/B7/B9, and Q11, and on the
palette (B10-B12) asked: *"Please do additional design research on color
combinations. There is some really good work done for picking the Human Shaped
colors and branding in here /Users/bhwilkoff/Documents/GitHub/UniversalAppTemplate
and in here /Users/bhwilkoff/Documents/GitHub/humanshaped-site"*. Store and
asset words: the agent drafts, the owner approves (B8, B15); nothing ships to a
listing unapproved. No trademark filing or clearance for now (B2, B3); no
outreach to RadioEchoes, Goldin, OTRR, or archive.org for now; harvests stay
polite.

**How to apply**: the palette and the genre hues are proposed together, as
rendered directions in light and dark on real screens, and the owner picks;
then `design-tokens.json`, the generator, and every platform. Brand colors stay
chrome, genre hues stay content (Decision 012).

---

## 061: Playback loudness targets -21 LUFS, reached by cutting

*Date: 2026-10-22*

Every client plays an episode at `gain = -21 - I` dB, clamped so the true peak
stays at or below -1 dBTP (`I` and `TP` measured per default copy by
`catalog/tools/measure_loudness.py`, EBU R128). The pipeline publishes the
measurement; the target lives in the clients and can change without measuring
again.

**Why**: the research proposed about -18 LUFS (04 §8.2) and asked for a
measured sample before fixing it. Measured 2026-10-22 over 183 usable episodes
streamed from archive.org, stratified by decade and rights: median -19.0 LUFS
(10th percentile -23.9, 90th -14.3), and every decade between -18.2 and -20.3.
But the transfers peak near full scale (median true peak -1.3 dBTP, 90th
percentile +1.1), so a boost almost always hits the clamp: at -18 only 54% of
episodes can reach the target, at -20 79%, at -21 90%, at -22 95%. The web can
only cut (Web Audio gain above 1 would clip), so a target reached by cutting
serves every platform alike. -21 levels nine episodes in ten while staying near
spoken-word practice.

**How to apply**: one constant per client, named the same everywhere; never
re-encode, trim silence, or limit. A boost beyond the clamp is not applied.
Sample failures to follow up: 11 of 15 measurement errors were LibriVox
sections whose URL was an item folder (fixed in `build_db`, tick 22), and two
episodes measured absurdly (+9.1 and -70 LUFS), which the measurement should
flag rather than publish.

---

## 062: One set of player numbers on every platform

*Date: 2026-10-22*

Every player uses the same numbers: the sleep timer fades over its last 10
seconds; speeds are 0.75, 1, 1.25, 1.5, and 2; the listening position saves
every 5 seconds and on pause; resuming after an interruption rewinds 3 seconds.

**Why**: the binding design docs, written from the code on 2026-10-22, found
three platforms disagreeing (a 10 s fade on Apple and Android against 20 s on
the web; a 0.8 speed floor on the web against 0.75; saves every 5 s against 10 s;
a 3 s rewind on Apple against 5 s on Android). Feature parity means the same
verb with the same feel; a listener who falls asleep on the phone and wakes to
the web should meet the same timer. Each value is the one most platforms
already used.

**How to apply**: one named constant per value in each client, the same names
everywhere, mirrored in each platform's design doc. What plays after an episode
ends (the queue rule) is not settled here: it is the owner's (SCRATCHPAD item 9).

---

## 063: Sign-in is verified at the Worker, which issues its own session; sync is last-write-wins per row

*Date: 2026-10-23*

Clients send the provider's identity token (Apple or Google) with a raw nonce to
`/v1/auth/{apple|google}`; the Worker checks signature (RS256 only), issuer,
audience, expiry and nonce against the provider's published keys, then issues its
own pair: a 1-hour access token and a 60-day refresh token replaced on every
refresh. Sync is last-write-wins per row by `updated_at`, clamped to the server's
clock; removals are markers.

**Why**: Archive Watch's sign-in never reached a server (CloudKit and Drive App
Data), so there was nothing to port and the Worker cannot trust a client's word
for who it is. Shared plays (M8) need one identity every platform can prove. A
replayed refresh token ends every session of that sign-in, and each call reads
the session row, so sign-out and deletion take effect at once.

**How to apply**: every call goes through each platform's one API client,
refreshed when under 5 minutes remain, one refresh at a time. After sign-in the
client sends its signed-out history to `/v1/sync/merge` once. Account deletion
sends a fresh Apple authorization code so the Apple token is revoked. Any new
table that holds a person's rows goes in `USER_TABLES`; the deletion test reads
the tables from D1 and fails otherwise. Apple and Google sign-ins for the same
person stay separate accounts until a linking decision is made. Setup steps:
`docs/WORKER.md` (owner: LOOP-PLAN Needs Ben).

---

## 064: The palette is On Air

*Date: 2026-10-23*

Ear Drama's colors are the On Air direction (`docs/research/palette/README.md`):
tally red (`#B0152F` light, `#E3384B` dark) for the one thing that is live (Play,
the progress line, the playing episode), and the blue of 1930s mirrored-glass
sets (`#0B6E99` / `#5AB4D6`, links `#6CC0E0` in dark) for links, the focus ring,
and the selected tab, on neutral grounds. Genres take On Air's eight hues.

**Why**: the owner, 2026-10-23: *"I really like the On Air colors and I think we
should be building with those in mind."* The research recommended Catalin and
named On Air's costs, which the owner accepted knowingly: red is already
iHeartRadio's and Pocket Casts' color (brand distance 4.5 and 7.8), and a
dark-mode red bright enough to read cannot carry white text, so the dark Play
button takes near-black type (4.66:1, APCA Lc 36).

**How to apply**: `design-tokens.json` holds the brand and semantic values plus
three new brand keys (`secondary`, `onSecondary`, `link`);
`tools/test_design_tokens.mjs` now checks their contrast. Red stays for what is
live and never decorates; blue does the wayfinding (Decision 012: brand is
chrome, genre hues are content). "Live" includes Start recording, because On
Air's red was the studio light that meant the microphone was live (an agent's
reading, kept on 2026-10-23; the owner may overrule). Genre hues are the
`color.genre` group, checked at 3:1 on every ground in both modes. The icon (the white ring microphone on tally red) waits on the
CC0 photo download (SCRATCHPAD item 2).

---

## 065: Listen Together rooms need no account; the host is a member and hands off

*Date: 2026-10-23*

Web and Android rooms are Archive Watch's D1-polled rooms, ported: the host
writes state on change, members poll every 2 to 10 seconds against the server's
clock, drift is corrected by speed before seeking, and every guest plays the
host's `archive_id`/`file` (Archive Watch Decision 143). Rooms need no sign-in.

**Why**: Decision 057 requires an account "to record, cast, or publish a shared
play"; listening together is none of those, and SharePlay asks for no account on
Apple. D1 polling, not Durable Objects, because Durable Objects are not on the
free plan (the zero-cost rule).

**How to apply**: a code lets someone join and listen, never drive. Each member
gets a random key, stored only as a hash, and only the current host's key writes
state; when the host leaves or is silent for 2 minutes, the member present
longest becomes host, and an empty room ends. Limits: 20 members; deleted after 6
idle hours by the hourly sweep; six-character Crockford codes (more than two
years to guess one of 1,000 live rooms at 20 joins a minute per address); rate
limits per address for create and join and per member. Every rule lives in
`worker/src/room-protocol.js`, which has no imports (a test fails if it gains
one); clients and SharePlay port it rather than re-derive it.

---

## 066: Shared plays live on the Worker, invite-only, with take audio in R2 behind the owner's switch

*Date: 2026-10-23*

A production is checked against a castable manifest (each castable cast
sheet's SHA-256) and seen only by its members, who join by an invite token
(256-bit, stored as a hash, revocable, expiring in 1 to 30 days). Takes are
immutable R2 objects checked from their own WAV or FLAC headers (mono, at most
300 s and 45 MB; a bleed-flagged take is refused). Reports, blocks, and a
server-side name filter answer App Store guideline 1.2. CC0 consent is recorded
by version id; publishing only queues a `pending_owner_account` job.

**Why**: Decision 057 requires an account to cast a shared play. D1's 500 MB
holds under an hour of 24-bit audio, while R2 has free egress but asks for a
payment method (research 08c Q8), so the take store waits on the owner. The
Worker never takes a client's word for what is castable.

**How to apply**: run `node worker/tools/castable-manifest.mjs` after every
castable rebuild (a test fails when the two drift). New consent words need a new
`CONSENT_VERSION`; the words themselves are the owner's (a placeholder starting
"OWNER:" until then). Every person table goes in USER_TABLES, and any person
column that is not `user_id` in OTHER_PERSON_COLUMNS. Owner items P1 to P8
(R2, consent words, a vetted deny list, report handling, school consent, the
archive.org account, C6/C7, class ownership) are in PLAYS-DESIGN §11.6.

---

## 067: The owner's rulings of 2026-10-23 on plays, Radio, playback, and the shell

*Date: 2026-10-23*

Answered in one sitting, replacing the defaults that stood in for them:

- **What plays next**: a serial plays to its arc's end and stops; the next arc
  is offered, never started (research R3). Until arcs exist: one episode, then
  anything queued.
- **Loudness**: no per-file measurement. The owner: *"There has to be a way to do
  this in software rather than as a metric for each recording ... Evening out
  volume on an app shouldn't be about knowing how loud an audio file is."* Each
  player levels volume on the device as it plays; the measuring workflow stops.
  Supersedes Decision 061's per-file gain.
- **Plays listen-through**: parts with human takes play those takes; parts
  without one are read live by the listening device's own voice (or an openly
  licensed voice generated on that device), so anyone can hear the whole play
  and choose to add their voice. Never stored or exported (the catalog rule
  holds); Export needs every speaking line human and is available any time
  then. C5 and C6 resolved so.
- **C7**: parts in any order, largest first suggested. **C9**: "the individual
  author died by 1955" is accepted as evidence. **C10**: commercials stay, each
  its own part. **Personal Voice**: offered, live only, never stored.
- **Recording needs an account**, always, even a play never shared.
- **Children and teachers**: plays are marked only by facts from their records
  (year, author, length); no invented age ratings.
- **Listen Together**: a guest may pause their own sound and catches up on resume.
- **Tonight in 19xx**: an evening shows when any program survives (the 0.25 floor
  goes); a gap shows its time and the program's name when the listing matched a
  series, never the newspaper's printed text; a listener may pick another
  published year for the same date.
- **Command Performance**: the AFRS rule stands.
- **Shell**: six sections; on an iOS 18 iPhone Search goes in More.
- **Listen**: a popularity shelf from data (archive.org's own download counts),
  not "Most episodes".
- **Sign-in** merges the device's history automatically. **No data export** for 1.0.
- **Fonts and the CC0 microphone photo** may be downloaded. **GRW**: ask before
  using any transcription (the owner sends the request). **Samsung**: not for
  1.0. **Store category**: Entertainment.

**Why**: these were the owner's calls (SCRATCHPAD "Waiting on you" 2, 4-9, 12-14
and PLAYS-DESIGN §9), each blocking a feature batch.

**How to apply**: each binding design doc gets the rule before its feature
changes; LOOP-PLAN "Feature batches" carries the work.

---

## 069: Volume is leveled by each platform's own dynamics processor, at one set of numbers

*Date: 2026-10-24*

Every player levels volume on the device as it plays, on by default, with one
switch ("Level volume") on the player that the person may turn off (kept on
the device). No client reads a per-file measurement. One compressor over the
whole signal, the same numbers everywhere: threshold -24 dBFS, ratio 4,
attack 3 ms, release 250 ms, makeup gain 10.8 dB (the Web Audio rule, 0.6 x
the compression at 0 dBFS, which the browser applies on its own), and a 12 dB
knee where the platform has one. Web: a `DynamicsCompressorNode` on the
`<audio>` element (`Player.LEVEL`). Apple: an `MTAudioProcessingTap` on the
item's audio track running Apple's DynamicsProcessor unit (`LevelNumbers`,
ratio stated as 6 dB headroom), holding samples inside full scale. Android:
`android.media.audiofx.DynamicsProcessing` on ExoPlayer's audio session, one
full-band compressor band and a limiter at -1 dBFS (`LevelNumbers`).

**Why**: the owner, 2026-10-23 (Decision 067): *"There has to be a way to do
this in software rather than as a metric for each recording."* A per-file gain
needed a 25 GB-a-day measuring run and still left a new or unmeasured copy at
unity; a compressor levels every copy, downloaded or streamed, the moment it
plays. Each platform's own processor was chosen over one hand-written
algorithm (`Native APIs, no workarounds`): the browser's node, Apple's unit,
and Android's effect are maintained by the platform and run off the main
thread. The numbers are the browser's defaults moved toward speech (ratio 4
rather than 12, so a voice is evened, not flattened), and the makeup rule is
the browser's own so the two platforms that set it by hand match the one that
cannot. Measured offline through the Apple unit on 2026-10-24: a -40 dBFS
passage followed by a -6 dBFS one, 34 dB apart, comes out 21 dB apart.

**How to apply**:
- The numbers live once per platform under the same names and are tested
  against these values (`js/player.test.js`, `VolumeLevelerTests`,
  `LevelingAndQueueTest`); change all three together.
- The web asks archive.org with `crossorigin` (it sends
  `access-control-allow-origin: *`, research 04 §5), builds the graph only once a
  tap has started the AudioContext, and loads a copy refused that way again
  without it, unleveled. Not on iPhone or iPad web (a page's AudioContext stops
  at the lock screen) or a TV engine (unmeasured): the switch says "Not in this
  browser".
- A track, tap, or effect that cannot be made plays unleveled; it never stops
  playback.
- The sleep timer's fade and the mute door stay on the player's own volume (on
  the web, the graph's output gain), after the leveler.
- `loudness_i` / `loudness_tp` stay in the projection, unread;
  `catalog-loudness.yml` runs only on dispatch.
- Not yet heard on a device: the agent never plays sound at the owner. The
  first device check listens to a quiet and a loud episode in turn with the
  switch on and off.
