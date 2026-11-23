# Backlog loop: all documented work (started 2026-11-23)

Owner, 2026-11-23: "Yes, let's get started on all documented work via an autonomous loop. Please make
sure we aren't going to override any of the cleanup work we did in this repository from the other
sessions."

Each tick: read this file, check CI (`gh run list -L 10`), check the Mac (below), run the next open
batch, merge only verified work, then update State. The loop wakes on results, 30-minute fallback.

## Guardrails: never undo another session's work

Other sessions committed cleanup today; it stays. Before touching any of these, read the commit:

- `b6bed5b3` Worker read room long poll, one row per cursor move; `012d458d` clients' long poll on web,
  Apple, Android; `3103868e` relay: hidden or idle tab holds no pickup, RelayWatch 5-minute empty wait;
  `cc301d92` read room alarm never in the past; `17d31ad7` archive cron picks only jobs with work.
- `f1a29bfb` CI: the Gradle cache is written only from main and cleaned; concurrency on three workflows.
  Never re-add a cache write, remove a `concurrency:` block, or edit an App Store workflow.
- SCRATCHPAD "a $0.00 stack" entry: no polling loop, timer, alarm or long-held request without a
  test that counts its requests or writes. Free-plan limits are a design constraint.

Mechanics:
- `git fetch` and rebase or merge onto `origin/main` before every merge; resolve conflicts by keeping
  both sides' intent, never "ours" over a file another session changed today. Never force-push.
- Stage explicit paths; never `git add -A`. Never revert a commit that isn't this loop's.
- Before editing a file, `git log -3 --since=midnight -- <file>`: if another session changed it in the
  last 30 minutes, skip that item this tick (it may still be working).
- Worktrees and branches: remove only ones this loop created, or ones merged into main, not locked,
  and not modified in the last 24 hours. Never delete `.claude/worktrees/*` another session may hold.
- Never `wrangler deploy` while another session has a Worker commit less than 30 minutes old; deploy
  only from a clean `worker/` at `origin/main` with the full suite green.

## Resource and device rules (standing)

- `uptime; memory_pressure | tail -1` first; wait if the 1-minute load is over 8 or free memory under
  20%. One build-heavy agent at a time; `nice -n 15`; gradle `--max-workers=2` then `./gradlew --stop`;
  xcodebuild `-jobs 4`. Prefer CI for lint. Kill only our own leftovers.
- Real devices only, never simulators. Muted; ask before anything audible. Never sleep a device, never
  kill the owner's running app. Check the device lease.
- Store cadence: after a verified Apple or Android merge, bump, then dispatch
  `appstore-build-x27.yml` (platform=all, submit=false) and `play-release.yml` (track=internal).

## Batches (in order)

- [ ] **B1 Quick fixes** (a, c, d done 2026-11-23; b running). (a) Apple Library foot shows two Export rows: one. (b) N8 Android's stall
  watchdog counts a slow seek as a stall (fixed on Apple and web; mirror). (c) N10 housekeeping:
  `.wrangler/` in `.gitignore`; prune merged `worktree-agent-*` branches under the worktree rule above.
  (d) SCRATCHPAD Current State brought up to date.
- [ ] **B2 Worker deploy.** The $0.00 stack Worker changes (SCRATCHPAD "The Worker needs a deploy"),
  under the deploy rule above; then watch `wrangler tail` for a minute for errors.
- [ ] **B3 Relay rules on Apple and Android.** Mirror the web's receiver and sender rules (hidden or idle
  holds no pickup, 30 idle minutes stops, Keep receiving takes, RelayWatch 5-minute empty wait) in
  Apple `ClassInbox`/`RelayHub` and Android `RelayAcrossTime.kt`; tests that count asks; PARITY row.
- [ ] **B4 Web voice labels.** Browsers that name voices only by locale get measured labels like
  Android's (PLAYS-DESIGN 2.8 rule 12); PARITY ⏳ cleared.
- [ ] **B5 Library and read-along on devices.** New-user Library on the Pixel (without wiping the
  owner's data: a second user profile or a DEBUG door) and the Duo; Apple TV frames; run the Library
  UI tests; press read-along pause, step and speed on an Apple device (muted).
- [ ] **B6 Round 3 leftovers.** Class-room takes end on silence (adult rooms do); Duo Record "Plays"
  indent; Apple class review screen seen on a device.
- [ ] **B7 Harness.** N7 three intermittent checks (instrument, never rerun until green); N12 the tap
  tier draws its shows from the data, not the same two.
- [ ] **B8 Catalog.** N13 remaining raw titles: `tools/catalog_dryrun.sh` on real data first.
- [ ] **B9 PARITY gaps.** Apple TV share as a QR code; Android Auto library tree beyond the stub.
- [ ] **B10 Parity audit (N9).** Every shipped feature a row, every cell honest; last, after B1-B9.

## Waiting on the owner (never blocks the loop)

Kokoro re-export for Android and web word marks; a read-only Cloudflare analytics token for a usage
check; N5 Stations day switcher (ask first); SCHOOL_CONSENT_POLICY; OPERATOR_TOKEN; H1-H4 sessions;
store words; radio-script rights rule; GRW request.

## State

- 2026-11-23 14:20: loop started. main at origin/main after 17d31ad7.
- 2026-11-23 15:10, tick 1: B1a Apple foot one Export row (92006763; built macOS/iOS/tvOS, Mac frame
  read, menu not opened by hand). B1c: .wrangler/ already ignored; 187 merged idle agent branches and 11
  clean merged worktrees removed (locked, dirty and unmerged kept). B1d SCRATCHPAD (47656289). B1b N8
  running in an agent (Sonnet, worktree). B2 waits for load (17.7 during the agent's Gradle run). Disk 94%.
