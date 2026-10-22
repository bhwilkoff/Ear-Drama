# Project Scratchpad: [APP NAME]

> Active working notes, loaded into every session, so keep it small.
> Keep only the two most recent session-log entries; roll older ones
> word for word into `docs/SESSION-LOG.md` (create it on the first roll).
>
> See `PARITY.md` for the cross-platform feature matrix (the single
> source of truth; don't duplicate rows here).
>
> New to this template? Start with `docs/path/00-why-we-build.md` and
> `docs/path/01-first-prototype.md` before filling anything in.
>
> The Current State block below is injected at every session start.
> If it drifts behind the code, fix it FIRST, then work. A stale
> scratchpad is worse than none.

## Current state

- **Status**: NOT STARTED
- **Active milestone**: M0
- **Last session**: none yet
- **Next actions**:
  1. Read `docs/path/00-why-we-build.md` and
     `docs/path/01-first-prototype.md`
  2. Decide the platform set (all five? skip tvOS? add Windows?)
     → DECISIONS.md
  3. Fill in AGENTS.md project identity sections (CLAUDE.md imports it)
  4. Rename the app in `project.yml`, then the agent runs
     `xcodegen generate` and builds iOS, tvOS, and macOS unsigned,
     per apple/README.md
  5. Open `android/` in Android Studio, rename `com.example.appname`
  6. Enable GitHub Pages on main branch (+ `.nojekyll` if serving
     `/.well-known/`)
  7. Drop verification files in `/.well-known/` once the
     `appID` / `package_name` / fingerprints are known
- **Open questions**: none yet

---

## Milestones

### M0: Project setup

- [ ] Platform set decided + logged in DECISIONS.md
- [ ] AGENTS.md filled in with project identity (app name, what it
      does, tech-stack specifics, design tokens)
- [ ] PARITY.md skeleton sections filled in with intended verbs
- [ ] **Web**: runs locally out of the box
      (`python3 -m http.server 8080`, then http://localhost:8080);
      `index.html`, `css/styles.css`, `js/app.js` render your first
      view; GitHub Pages enabled
- [ ] **Apple (universal)**: the project is generated from
      `project.yml` by the agent, never clicked through Xcode. Rename
      `AppName` and the bundle ids in `project.yml` (no spaces), run
      `xcodegen generate`, then build unsigned for iOS Simulator,
      tvOS Simulator, and macOS and run the Core tests, per
      `apple/README.md`. ONE target, four destinations; sources stay
      in `apple/`; `AppVersion.xcconfig` is already wired
- [ ] **Android**: `cd android && ./gradlew :app:assembleDebug`
      builds out of the box; open `android/` in Android Studio; rename
      the package from `com.example.appname` to your reverse-DNS and
      rebuild; smoke-test on a device or emulator
- [ ] **CI / submission**: `.github/workflows/appstore-build.yml`
      (one workflow covers iOS + macOS + tvOS) with the seven signing
      secrets seeded per `docs/CLOUD-SUBMISSION.md`;
      `.github/workflows/android-build.yml` for CI builds and
      `.github/workflows/play-release.yml` to publish to Play (internal
      track first, then promote)
- [ ] First commit pushed

### M1: [First user-visible capability]

<!-- One sentence: what can a user DO after this milestone? -->

Before implementing, run the `learning-orientation-design` skill:

- [ ] Deepens understanding
- [ ] Invites participation
- [ ] Supports agency
- [ ] Clarity over cleverness

**Acceptance criteria** (observable by users, not developers):

- [ ] Web: …
- [ ] iOS: …
- [ ] macOS: …
- [ ] tvOS: …
- [ ] Android: …

**Parity check**: update PARITY.md row(s) for this capability in
the same change set. Reject the PR if PARITY.md is silent.

### M2: [Second user-visible capability]

- Learning-orientation check passed
- **Acceptance**:
  - [ ] Web: …
  - [ ] iOS: …
  - [ ] macOS: …
  - [ ] tvOS: …
  - [ ] Android: …

---

## When to add a binding design doc

When a platform crosses ~5 views OR you find yourself making
inconsistent UI choices, create that platform's binding doc
(`tvOS-DESIGN.md`, `iOS-DESIGN.md`, `macOS-DESIGN.md`, `WEB-DESIGN.md`,
`ANDROID-DESIGN.md`), seeded from the matching per-platform template
in `docs/templates/` (start from `PLATFORM-DESIGN-template.md`, the
index). Invoke
`binding-design-doc-discipline` for the workflow. Treat as binding
from the moment it exists.

The sibling docs share a shape: the **principles** are identical;
the **idioms** they reference diverge per platform. Deliberate
rule inversions between platforms (tvOS auto-focuses Play; iOS
never steals focus) are stated explicitly so they don't get
"harmonized" away.

---

## Open questions

<!-- Add questions as they arise; remove when resolved. Don't
     accumulate. Every question should have a path to resolution. -->

---

## Out of scope (intentionally)

Document explicitly-rejected ideas so future sessions don't
re-litigate them. "We thought about this and chose not to design it
now" is far more useful than silently re-arriving at the same answer.

When a request gets declined, write a row. Format:
`**Idea**: Why declined. Revisit when …` (revisit condition lets
the entry retire when circumstances change).

| Idea | Why declined | Revisit when |
|---|---|---|
| <!-- e.g. Web push notifications | Too-inconsistent UX across browsers; APNs/FCM cover the need on mobile | iOS + Android push ship and a real cross-platform request appears --> | | |

---

## Session log

<!-- Append-only. Format: state found → work done → state left.
     Keep entries short: one paragraph per session. -->

**2026-08-24: Windows scaffold + Tidbits lessons ported.** Found: sixth-gen
template with docs/windows/ present but no `windows/` source scaffold, a
WINDOWS-STORE-SUBMISSION.md that was an unadapted Tidbits copy (real Store
IDs), a playbook describing a pre-ship layout, and no vendored Windows skill.
Done: committed the `windows/` scaffold (AppName.Core / .App / .HeadlessTests /
.Windows: the as-shipped Tidbits architecture with every version gotcha
pre-solved; builds clean, 11 headless tests pass, shell PNGs verified light +
dark at 1180×760 and the 900×680 floor, versions stamped from
AppVersion.xcconfig); generalized WINDOWS-STORE-SUBMISSION.md (placeholders +
§0 checklist, all 12 gotchas + IAP §7 kept); rewrote WINDOWS-PLAYBOOK.md to the
as-built flat layout (.NET 10, TFM-isolation, DPAPI, narrow-width shell
renders, network-race flag); added the `windows-production-gotchas` skill;
added a `## Windows app` CLAUDE.md section + Windows columns in both design
tables; appended DECISIONS 035–039 (anonymous-account deletion, query-not-load,
generator merge guards, randomness-outside-selection, per-store billing
shapes); README tree/step-12 + CONTRIBUTING now name the scaffold. Left: green;
Store assets (7 PNGs) intentionally not generated (per-app branding);
first-Windows-run baselines armed via `-f update_baselines=true` as documented.

**2026-08-24 (second pass): parity + store-approval hardening.** Found: the
scaffold wave left three lesson families unported: multi-store IAP release
choreography, Play pre-launch/publish traps, and the parity-audit method
lessons. Done: new `docs/store/IAP-RELEASE-CHOREOGRAPHY.md` (financial
paperwork as owner-only critical path, one-review-submission-per-IAP-product /
ship serially, the Ready-to-Submit trap, per-platform License Agreement,
empty-success vs thrown-error, per-store query shapes, real-provisioning-only
purchase verification, the launch-order checklist); store-submission-playbook
gained the IAP section + the internal-track-has-no-pre-launch-report /
Test-Lab-yourself / refused-to-auto-submit / all-or-nothing-submit bullets;
play-cli-submission gained Rules 7–8 (Console stalls, testlab-android.sh);
cross-platform-parity-discipline gained the degenerate-outcome audit pass
(tie/zero/empty/cold-quit), the both-directions stale-⏳ check (false docs vs
false cells), and the failure-class organization for whole-platform-port
audits; tvos-platform-patterns gained the SignInWithAppleButton-in-Form
swallowed-click gotcha; CLAUDE.md table + README tree point at the new doc.
Left: green.
