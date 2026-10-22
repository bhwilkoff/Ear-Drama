# Contributing

This is the universal app template: web, iOS/iPadOS, macOS, tvOS and
Android in one repo, with Windows (`windows/`), the smart-TV web
platforms and Roku as optional additions. The contribution rules below
keep the platforms in lockstep. (The three Apple platforms, iOS, macOS
and tvOS, build from one universal target and one shared `Core/`.)

## The parity rule

Every user-facing change updates **PARITY.md** in the same PR.
- New feature → new row, with `✅` / `🚧` / `⏳` / `🚫` per platform.
- Feature shipped on one platform → either ship the others in the
  same change set OR mark them `⏳` with a target milestone and a
  reason.

Reject PRs that ship a user-facing change without touching PARITY.

## Before opening a PR

| | Web | iOS / macOS / tvOS (one target) | Android |
|---|---|---|---|
| Tests pass | `node js/api.test.js` | `⌘U` in Xcode | `./gradlew :app:testDebugUnitTest` |
| Build clean | open in any browser | `xcodebuild build` against the iOS, macOS, AND tvOS destinations. A shared `Core/` change that breaks any Apple platform is not done. | `./gradlew :app:assembleDebug` |
| Version bumped (if shipping) | n/a (GitHub Pages) | `AppVersion.xcconfig` | `app/build.gradle.kts` `versionCode` + `versionName` |
| Docs touched | `WEB-DESIGN.md` if UI/IA changed | `iOS-DESIGN.md` / `macOS-DESIGN.md` / `tvOS-DESIGN.md` if UI/IA changed | `ANDROID-DESIGN.md` if UI/IA changed |
| PARITY.md row | ✅ | ✅ | ✅ |

If the Windows column is enabled: tests via `cd windows && dotnet test`
on any OS, gated on `windows-repl.yml` (real `windows-latest` pixels;
copy it from `docs/windows/workflows/` into `.github/workflows/` first);
version via `AppVersion.xcconfig` + `tools/stamp_msix_version.py`;
`WINDOWS-DESIGN.md` if UI/IA changed; PARITY.md row like every platform.

**The template's own Android build must stay green.** Run
`cd android && ./gradlew :app:assembleDebug` before any PR that touches
`android/`, shared assets, or the Gradle catalog.

## Conventions

- **Commit messages quote the user's request verbatim** when
  applicable (see `feature-shipping-discipline` skill).
- **DECISIONS.md leads with WHY, not WHAT** (see
  `architectural-decision-log` skill).
- **No comments unless WHY is non-obvious.** What the code does is
  visible in the code.
- **No emojis in code or commits** unless explicitly requested.
- **Default to skill invocation over re-deriving patterns.** The
  bundled skills in `.claude/skills/` exist because the patterns
  came from real iteration.
- **Prose follows `docs/maintaining/WRITING.md`.** Every page a person
  reads first (READMEs, `docs/path/`, the catalogs) uses that voice:
  no em dashes, none of the words on its "do not use" list.
- **A new tool gets a row in `tools/README.md`.**
- **A new skill gets a row in `.claude/skills/README.md`**, and a
  trigger row in AGENTS.md (CLAUDE.md imports it) if it should fire
  without being asked for.
- **Lessons learned in an app repo are upstreamed here** per
  `docs/PROVENANCE.md`: the generic form lands in the template in the
  same session, and the coverage map is updated.

## Style

`.editorconfig` enforces indentation across editors. Per-language:

- **JavaScript**: no framework, no build step, no transpile.
  ES2022+ in the browser directly. JSDoc + `// @ts-check`
  comments cover what TypeScript would.
- **Swift**: Apple's API Design Guidelines. 4-space indent.
  Per-platform files end `_iOS.swift` / `_macOS.swift` / `_tvOS.swift`
  and wrap in `#if os(...)`; `Core/` files compile for every
  destination and never import per-platform UI.
- **Kotlin**: official Kotlin style (4-space indent). Apply with
  `./gradlew ktlintFormat` once ktlint is added.

## Setting up after clone

```sh
# 1. Web
python3 -m http.server 8080      # http://localhost:8080

# 2. Apple: generate the universal Xcode project from project.yml
#    (brew install xcodegen; steps in apple/README.md).
#    One target covers iPhone, iPad, Mac and Apple TV.
xcodegen generate

# 3. Android: first build downloads SDK + AGP + deps
cd android && ./gradlew :app:assembleDebug
```

If the web or Android step fails on a fresh clone, the template is
broken. That is a P0 fix.

## Reporting issues

When filing an issue, name the platform(s) it affects in the
title (`[ios]`, `[macos]`, `[tvos]`, `[web]`, `[android]`, `[windows]`,
or `[all]`). Use the verbs from PARITY.md so the report is cheap to
place: "this is a search bar issue on Find."
