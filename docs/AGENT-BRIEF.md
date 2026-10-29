# Agent brief: the standing rules for every Ear Drama batch agent

Read this, `AGENTS.md`'s hard rules, and only the design docs your feature
touches. Your brief adds the feature's goal, decisions, and acceptance tests.

## How to work
- First, check it isn't built (owner, 2026-10-28: "Are we being as economical with
  tokens on this loop as we can be?"): `git log --grep`, grep the code and PARITY for
  the feature. If most of it exists, stop and report what is missing before building
  (M8a spent a full Opus run rediscovering batch 1's invite client).
- Your own git worktree; commit on your branch with `git commit -F` and a quoted
  heredoc ending in the two attribution lines the brief gives; never push; stage
  explicit paths.
- Doc first: quote the binding design doc's rule, change the rule if the feature
  needs it, then build (`binding-design-doc-discipline`).
- Design runs through a design skill (owner, 2026-10-28: "anything that needs to be
  designed will require a design skill and you need to either research or build
  that skill"). Name the skill you follow; if none covers the problem, research
  real references and write the skill in `.claude/skills/` first, then design.
- One feature on every platform it belongs on, in one run: web (`js/`), Apple
  (`apple/`, iOS/iPadOS/macOS/tvOS), Android (`android/`), and the data plane
  (`catalog/`) or Worker (`worker/`) it needs. Same verb, native idiom.

## Verification (judge by logs, never a trailing exit code)
- Web: `node --check` every js; the `js/*.test.js` you touch; `tools/test_web.sh`;
  bump `SHELL_VERSION` in `sw.js` when the shell changes. Screenshots at 375 px
  only through a 375 px iframe (headless Chrome will not lay out narrower),
  on a port of your own; stop the server and Chrome after.
- Apple: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`;
  `xcodegen generate`, then `xcodebuild test -project EarDrama.xcodeproj -scheme
  EarDrama -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` (set
  `CATALOG_SEED_PATH` to the main checkout's `catalog/out` seed if your worktree
  lacks one) and report the "Test run with N tests" line; generic iOS and tvOS
  Simulator builds, one at a time, in the background, 0 compiler warnings;
  `tools/test_apple_design_rules.py`. NEVER boot a simulator.
- Android: `./gradlew --no-daemon :app:testDebugUnitTest :app:assembleDebug` in
  the background (`ANDROID_HOME=~/Library/Android/sdk` if no local.properties),
  judged from the test XML, 0 `w:` lines. NEVER an emulator or device.
- Catalog: `bash catalog/tests/run_all.sh`. A change under `catalog/tools/`
  also runs any client suite that reads that file (`git grep` its name).
- Worker: `cd worker && npm ci && npm test && npm run test:mutations`. Never
  deploy, never create cloud resources.
- A changed workflow step is RUN before it merges: extract its `run:` script and
  execute it under a fake `gh`/`curl` on the real inputs it will see (A1's live
  check was never run and failed both publishes on 2026-10-28).
- Every guard you add is broken once and seen to fail. `tools/test_us_english.py`.
- Tests never pin real catalog contents: fixtures, or shape-only real checks.

## Rules that are easy to cross
- Only essential words on screen: a refusal, a warning, or a fact the person
  cannot discover by looking. No AI-written copy or lists (data or a human).
- On Air (Decision 064, owner 2026-10-29: "Red means recording."): red only for recording; ink for the primary action (Play, Listen through, Listen live); blue for links, focus,
  the selected tab; genre hues are content.
- Unclaimed recordings are never called public domain; a synthetic voice is a
  live stand-in only, never stored or mixed.
- The owner's calls, never made by an agent: what plays next (the queue rule),
  consent and store words, anything in SCRATCHPAD "Waiting on you".
- The owner may be on a call on this Mac: builds one at a time, short commands.

## Report (under 400 words)
What now exists that did not, per platform; the evidence (commands and counts);
what is not verified; what needs the owner. Then **Seen on the way** (owner,
2026-10-28: "proactively looking for things to fix and design"): each defect
or design gap you noticed outside your feature, as file, symptom, proposed
fix, and whether it needs an owner ruling. Fix none of them unless it blocks
your feature.
