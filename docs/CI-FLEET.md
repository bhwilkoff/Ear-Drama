# CI Fleet Engineering: running 30+ scheduled workflows without losing work or crying wolf

Distilled from Archive Watch (2026-06 → 2026-08), where a data pipeline grew to
~35 scheduled workflows sharing one repository, and every rule below was paid
for by a real incident. The tools named here ship in `tools/`; the workflow
shapes ship in `docs/templates/`. Decision numbers refer to Archive Watch's
DECISIONS.md, kept so the full incident write-ups stay findable.

The one-sentence doctrine: **a green run must have done something, a red run
must mean something, and no run may destroy work, its own or another's.**

---

## 1. The shared lock is the scarcest resource (D018/D057/D066)

Workflows that mutate a shared accumulator (a catalog JSON, a published DB)
must serialize through one concurrency group. Two facts about GitHub's
concurrency model then dominate everything:

- **GitHub keeps ONE pending run per group.** A newer arrival does not queue
  behind an existing pending run. It DESTROYS it. Archive Watch measured 7
  scheduled runs destroyed in a single 12-hour window while one job held the
  lock for 4 hours.
- **The same rule applies at JOB granularity** for job-level concurrency: a
  pending `apply` job is destroyed by a newer pending `apply` from another
  workflow (D095).

**The fix is to make lock holds short, not to make the queue smarter:**

- **Split every writer into compute + apply (D066).** The long half (probing,
  classifying, downloading) holds NO lock and emits a field-level delta as it
  goes (`tools/catalog_delta.py`: `snapshot` → run tool → `extract`). A short
  apply job takes the lock for ~2 minutes: fetch FRESH, merge the delta,
  publish. Measured: a 52-minute hold became 21 seconds.
- The merge is the load-bearing part, not the speed: republishing a whole
  accumulator read hours earlier silently REVERTS whatever another writer
  published meanwhile. A field-level merge composes; a snapshot republish
  does not.
- The lock is declared at WORKFLOW level by default. Splitting into two jobs
  changes nothing until the top-level `concurrency:` is removed and
  re-declared on the apply job alone.
- Gate every apply step on a "Stop if nothing changed" check, and validate
  with `tools/check_workflow_gates.py` in CI. An ungated step after the gate
  runs against a catalog that is not there.
- Long whole-run holders that also push to git (ingest pipelines) need care:
  convert them last, deliberately.

## 2. Budgets that PUBLISH, never timeouts that kill (D057/D091/D093)

A job killed by `timeout-minutes` never reaches its publish steps; the run's
work is computed and then discarded. Archive Watch had a workflow that hit its
330-minute wall on all 15 of its first 15 runs: 15 "cancelled", zero
publishes, every day's work thrown away.

- Every long tool takes `--max-minutes` and **stops starting new items** past
  it, returning 0 so the caller publishes what finished.
- **Measure the budget from process start (D091)**, not from the start of the
  expensive loop. A network-bound setup phase before the deadline computation
  once made the effective budget 204 minutes against a 180-minute timeout.
- **The budget must be able to fire inside one item.** A between-items check
  is defeated by a single expensive item: a 2,500-cue film was an hour of
  inference with no check, and one adversarial network item was 14 bounded
  calls × 429 backoffs ≈ 56 minutes. Check the deadline inside the item loop,
  or give the low-level request function a hard deadline it fails fast past.
- Keep a step-level `timeout-minutes` as a BACKSTOP above the budget, marked
  `continue-on-error`, and let a final **verdict step** decide the run
  (section 5).
- On a mid-item abort, either discard that item's partial output or make the
  resume marker transactional. Partial rows without the "done" marker get
  re-inserted in full next run and duplicate.
- **What a run learns must outlive the runner.** Archive Watch's remux job
  was killed at its 301-minute wall seven runs in a row, because the same
  poison items came first every day: its list of failures lived on the
  runner and died with it. Record a per-item failure ON THE ITEM
  (`failedAt`, `reason`, retried after N days), so tomorrow's run starts
  with new work.
- **Cap each download as a whole, not only per read.** A `requests` timeout
  is per read, so a server trickling bytes kept one download alive for 3.5
  hours. Give each transfer a total deadline, and stream large uploads from
  disk with a per-operation timeout rather than reading them into memory
  under one.
- **Adopt work that is already hosted.** Before regenerating an artifact,
  list the hosting target and re-point to a copy that is already there and
  probes the same. Then a lost publish (a GitHub 500) costs minutes, not a
  172-minute recompute. And run the publish step `always()` whenever
  anything was hosted or marked.

## 3. Restores never swallow; publishes never shrink (D020/D089)

The deadliest green run: `gh release upload --clobber` DELETES the asset
before uploading, a large raw upload 422'd (2 GB asset cap), both assets
vanished, and the next run's restore had `|| echo "first run"`, so it
rebuilt the shared index from zero and republished over it. 702,148 rows
destroyed by a run that reported success.

- **Only a NON-EXISTENT release is a first run.** A release that exists whose
  asset cannot be fetched is an emergency: fail the step. Never `|| true` a
  restore.
- **Snapshot row counts immediately after restore and refuse a shrunken
  publish** (`tools/sqlite_publish_guard.py snapshot` / `check`). Growth and
  equality pass; any table shrinking is a hard failure naming the numbers.
- Never upload a raw multi-hundred-MB member nothing consumes. Publish the
  compressed form only (raw DEFLATE `.zz`, wbits=-15, matches Apple's
  Compression framework on device).
- Gate the publish on the restore: `if: always() &&
  steps.restore.outcome == 'success'`. `always()` exists so a killed compute
  still publishes; it must never let a failed restore publish garbage.
- Rebuild-style workflows must MERGE into the fetched accumulator and abort
  if the result shrinks (D020). Never publish a from-scratch build as the
  whole dataset.
- Wrap every `gh release upload` in `tools/gh_retry.sh` (retries transients,
  refuses to retry the deterministic 422-too-large), and every fire-and-forget
  dispatch in `tools/gh_dispatch.sh` (warns and exits 0, because a failed dispatch of
  an idempotent, self-scheduled pipeline must not fail a clean run).

### A push that loses the race resolves it

Two runs of one workflow can commit the same generated file seconds apart.
`git pull --rebase || true` then hits a conflict, leaves the rebase
half-done, and every later push attempt fails (Archive Watch's Pulse,
2026-10-07, proven in a two-clone repro). In the retry loop, `git fetch`
and `git rebase`; on a conflict, a GENERATED file takes this run's copy
(`git checkout --theirs`, the newer reading), a HAND-EDITED file takes
main's (`--ours`) or stops the run with an error naming it, and a rebase
that still cannot continue is aborted. `pulse.yml` and `play-release.yml`
carry both shapes.

### New items pass the gate before they ship

Discovery that publishes straight away serves each night's new items
before the audits that judge them have run: Archive Watch's newly
ingested titles were visible for about a day before the nightly rights
confirm. Chain it instead: discovery dispatches the audit
(`then_publish=true`), and the audit dispatches publish. A shelf of "new"
items takes the strictest evidence bar for the same reason: the newest
items have had the least time in the audits.

### One source must not starve a shared queue

A work queue with a ceiling, refilled nightly by one prolific source, is
never drained by the others: one collection refilled a 4,000-item ceiling
every night, and 29 of 39 collections were never mined. Give each source a
fair share, and let low-value sources wait until the backlog is through.
(Archive Watch's owner: *"Council meeting collections are not going to
yield anything useful ... only look at them once the full backlog has been
run through."*)

## 4. Dropped work heals itself (D048/D057/D095)

`tools/retry_infra_failures.py` runs on a 30-minute cron and re-runs exactly
three shapes, each carrying a no-side-effect proof:

1. **Never-started runs**: runner-allocation failures where no step of ours
   reached a conclusion. Nothing ran, so nothing can repeat.
2. **Whole-run queue displacement**: a cancelled run where NO job has any
   steps (GitHub records displacement as zero jobs, or one job with zero
   steps). Re-run in full, only when the group is idle, one per group per
   sweep.
3. **Displaced apply jobs (D095)**: some jobs succeeded, and every
   non-successful job has ZERO steps. `rerun-failed-jobs` re-runs only the
   displaced jobs against the artifact the compute banked.

Rules that keep it safe: never retry a cancelled job that ran any step (a
human or timeout stopped real work); never retry when a later run already
succeeded; cap attempts and re-runs per sweep; **sit out a declared GitHub
Actions outage** (retrying into one burns the whole attempt budget in 90
minutes) but treat an unreachable status page as "proceed". Verify any gate
change with `DRY_RUN=1` against real history before shipping it.

## 5. A red X is reserved for broken (D093)

GitHub emails on failed runs. An alert channel that cries wolf daily is one
the owner mutes, and then a real break goes unread.

- **A backstop timeout on a run whose work still published is a warning, not
  a failure.** Pair every backstopped compute step with a verdict step:
  backstop fired + output grew → `::warning::` annotation, exit 0; backstop
  fired + nothing grew → `::error::`, exit 1. Measure growth from evidence
  (guard row counts, file counts, delta non-emptiness), never assume it.
- **A legitimately-empty run is not broken.** A tool that hard-fails on
  "nothing to do" (e.g. an apply step with no manifest) will eventually meet
  a run that legitimately produced zero; make nothing-to-do a printed no-op.
- **Best-effort steps are never silent.** `cmd || true` is how a workflow sat
  green for weeks with an EMPTY repo secret. Capture the exit code and emit a
  `::warning::` instead.

## 6. An auditor for the failures nothing else alerts (D090/D093/D107)

Red gets noticed; the dangerous failures are green. `tools/audit_workflow_health.py` runs daily
(`.github/workflows/workflow-health.yml`) and judges what each workflow's last completed SCHEDULED
run actually PRODUCED:

- **BROKEN**: green, took real time, produced nothing (zero-yield summary)
- **KILLED**: cancelled with publish steps skipped
- **FAILED**: red (reported, but GitHub already emailed about it)
- **DROPPED**: displaced in the queue before any step ran, at run OR job granularity
- **STALE**: the schedule stopped firing (absence needs its own verdict)
- **SILENT**: no yield line at all, which is its own problem
- **DRAINED**: genuinely finished its backlog (informational)

The rules that took iteration to get right:

- **Judge each workflow against its own cadence** (~2.5 periods), never a fixed lookback. A fixed
  36 h window made every weekly and monthly workflow structurally unauditable.
- **Judge the newest scheduled run that actually ran**, never a manual dispatch: a green experiment
  must not mask a broken schedule. A newer successful dispatch is reported as "fix in flight", not
  urgent.
- **A workflow that asks to be superseded is not KILLED.** The auditor reads
  `concurrency.cancel-in-progress: true` from the workflow file itself (workflow or job level), so a
  deploy cancelled by a newer deploy is the rule working.
- **Workflows that print no yield line are still judged.** `NO_YIELD_LINE` (extend it with the env
  of the same name) skips only the yield analysis for builds, deploys and submits. Their failures
  still count. It used to be a `NOT_PRODUCERS` list that skipped them entirely, and that is how the
  workflow shipping an app's catalog failed every hour for two days, completely unreported.
- **The auditor does not judge itself** (`SELF`). Judging its own last run makes one failure
  permanent: it fails, reports the failure, and fails again.

**The auditor never fails.** Reporters never fail (D107). A workflow going red says "I could not do
my job", and the auditor did its job the moment it looked. Failing it to signal somebody else's
problem is a category error, and an alert channel that cries wolf is one the owner mutes. So
`audit_workflow_health.py` exits 0 whenever the audit ran, and the urgent findings (BROKEN and
KILLED, the classes nothing else alerts for) go to **one self-closing GitHub issue** through
`tools/report_workflow_health.py`:

- nothing urgent: any open "Workflow health: attention needed" issue is closed with a note;
- something urgent: the issue is opened, or its body **updated in place**. The body always holds
  what is wrong NOW, and its existence is the alert.

The report step runs `if: always()` and needs `issues: write` and `GH_TOKEN`.

**Reporters are held to it statically.** `tools/check_workflow_gates.py` runs three checks and
exits 1 on any violation:

1. Every split workflow's `apply` job is fully gated on `steps.gate.outputs.go` after its "Stop if
   nothing changed" step.
2. **Every step that runs `gh`** (or the `gh_retry.sh` / `gh_dispatch.sh` wrappers) **has
   `GH_TOKEN` in scope**, at step, job or workflow level. A runner has no ambient credential: a
   publish step without it fails, everything after it is skipped, and one catalog publisher shipped
   nothing for two days that way.
3. **A reporter workflow never exits non-zero on its findings.** For every workflow listed in
   `REPORTERS` (add your dashboards and auditors), a step that can `exit 1`, `sys.exit(1)` or
   `raise SystemExit(1)` must carry a `# reporter-may-fail: <why>` comment saying the failure is
   over its OWN mechanics. Whether a step fails over what it read or over its own plumbing is not
   something a regex can judge, so the author states it in words.

Regression tests: `tools/test_workflow_health.py` (the auditor, plus negative controls for the
gate checker's reporter and token checks) and `tools/test_workflow_health_gate.py` (what reaches
the issue). Run the gate checker itself after touching any workflow.

## 7. Markers, evidence, and freshness (D055/D056/D084/D088)

The silent-failure class underneath everything above is a flag whose meaning
drifted:

- **"Already attempted" markers record the SOURCE.** A bare boolean shared by
  two providers means the second provider never sees a target. Coverage
  plateaus and reports "backlog drained" in 94 seconds.
- **A verification expires.** "Verified" without "when" means a check made in
  June looks identical to yesterday's; give every liveness/validation marker
  a timestamp and a TTL **tiered by visibility** (14 days for anything that
  can lead the home screen, 90 for the tail), and spend the re-check budget
  oldest-first.
- **Persist the MEASUREMENT, not just the verdict.** A stored classification
  ("bw") without its evidence (saturation 8.1) makes a coin-flip
  indistinguishable from a certainty downstream; consumers making destructive
  choices must be able to abstain on weak evidence.
- **Transient ≠ dead.** A 429/5xx leaves the item UNMARKED for retry; only a
  404/410 condemns. Never demote on a throttle.
- **A tool that drops user-referenced records leaves a forwarding address**
  (an alias table chased transitively), or saved favorites/progress silently
  vanish.
- **Shared reversible flags are registered state (D083).** When several tools
  write one `excluded` flag and one reconcile restores it, every tool's
  marker must be registered with the reconcile or its work is undone on the
  next build, and the reconcile should NAME any unregistered
  exclusion-looking marker it un-hides.

## 8. Reading CI honestly

Hard-won measurement discipline, each learned by being fooled:

- **Run duration ≠ job duration.** `createdAt→updatedAt` includes queue time;
  a "673-minute run" was a 1-minute job behind a lock. Always check job-level
  `startedAt/completedAt` before diagnosing slowness.
- **Step conclusions are unfakeable; log grep is not.** Grepping a run log can
  match the SCRIPT TEXT in the `##[group]Run` header rather than output.
- **`bash -e` does not see through pipes.** `python tool.py | tee log` masks
  the tool's exit code without `set -o pipefail`, and the run goes green while
  the tool crashed. A storage-bucket probe hid its own crash exactly that way.
  Every step that pipes a tool into `tee` starts `set -o pipefail`, or reads
  `${PIPESTATUS[0]}` when it must keep going.
- **A retry that succeeded is not a failure.** Check the attempt count before
  declaring a push failed.
- **A suspiciously low count from a new rule means the selection upstream
  never handed it the population**. Check what was offered before believing
  what was found (resume markers and pre-filters both do this).
- **One experiment per process** when measuring platform behavior. State
  leaks between probes in one process attributed one shape's result to
  another and cost three shipped "fixes".

## 9. Runner facts worth knowing

- Public repos get free macOS (Apple Silicon) runners, so heavy Apple-only work
  (Vision scoring, Swift builds) can leave the dev machine entirely (D039a).
  Scale by SHARDS across runners, never by workers on one machine.
- Hosted runners have **no Apple speech models and cannot install them**.
  Benchmark a pipeline on a machine that represents where it RUNS (D060).
- Datacenter IPs are second-class citizens: loc.gov 403s them, Wikimedia
  throttles spoofed UAs, WDQS 504s them. Some feeds only run from a
  residential IP; design those steps to skip cleanly in CI.
- Conversely, sweeps that hammer an external host belong IN CI, not on the
  dev machine. archive.org rate-limits per IP, and a local sweep degraded
  playback for every device in the house.
- `gh release upload --clobber` = delete-then-upload; assets over 2 GB 422.
- A cron'd workflow always runs the default branch's HEAD version; a RE-RUN
  of an old run uses the OLD commit's workflow definition, so mind that window
  when changing publish formats.

## 10. Shell and scheduler traps

Four more, each paid for by a run that did the wrong thing quietly:

- **`[ -n "$X" ] && ARGS+=(...)` is a trap under `bash -e`.** The test returns 1 when `X` is empty.
  Mid-script, `-e` ignores it. As the LAST line of a step (or of a function), that 1 becomes the
  exit status and the step goes red over an optional input nobody filled in. Write every optional
  flag as `if [ -n "$X" ]; then ARGS+=(...); fi`.
- **Inputs arrive as environment, never pasted into the script.** `${{ inputs.notes }}` inside a
  `run:` block is text substitution: a double quote in release notes closes the shell string, and
  free text pasted into a shell line is an injection route. Map each input to `env:` and read
  `"$NOTES"`.
- **Crons run late: plan for four to five hours.** GitHub queues scheduled runs behind its own load,
  and Archive Watch's daily dashboard cron measured four to five hours after its scheduled time.
  Schedule for the lag (and off the hour), and when a report must follow a release, trigger it with `workflow_run` on the release
  workflow instead of hoping the cron lands after it.
- **`[skip ci]` skips more than you meant.** A bot commit marked `[skip ci]` (a version bump pushed
  back by a release workflow) triggers no `push` workflows at all, including the deploy you wanted.
  Chain the deploy with `workflow_run` on the workflow that made the commit, and use `paths-ignore`
  for commits that genuinely should not deploy.
