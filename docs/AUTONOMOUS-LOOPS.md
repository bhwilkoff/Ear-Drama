# Autonomous development loops

On 2026-09-04, partway through a long Archive Watch loop, the owner
wrote to the agent: "I need you to always write down when the next tick
should begin so I can determine if you are actually doing it." The loop
had been running. From his side of the screen, he could not tell.

**A loop is only as good as what it lets you see.**

I want to be able to walk away from an agent working on an app and come
back to work I can trust: shipped where it says shipped, verified where
it says verified, and honest about what is still open. This page is what
hundreds of loop ticks across Archive Watch (tvOS first, then the
caption and playback campaigns), BOBA Playbook (the original
multi-platform loop), and Tidbits Trivia (six platforms, store
submissions mid-loop) taught about getting there. Most of it is about
verification, because every expensive loop failure was a loop that
believed its own reports.

The `autonomous-loop-cadence` skill carries the tick-by-tick mechanics.
`docs/ENGINEERING-PROCESS.md` carries the engineering disciplines every
tick relies on. This page sits between them.

## 1. The prime rule: the agent is never the tester

The loop's output is claims. The costliest pattern on record: builds
890 to 906 of Archive Watch each "verified" a tvOS caption fix on
circular self-reports, while the actual television kept failing. The
code's own logs said the captions were correct, because the code that
drew them and the code that reported them shared the same wrong
assumptions.

The standing directive that fixed it: a change ships only on
**external observation**, meaning evidence gathered by an instrument
that does not share the app's assumptions.

- **A screenshot or OCR of the actual glass,** not the view hierarchy's
  claim.
- **Tap-audio metering** for sound, not the player's state flag.
- **The published artifact downloaded again,** not the local file that
  was uploaded.
- **The store's own record, read through its API,** not your own
  submission notes. `tools/asc_release.py status` reads every Apple
  platform, and Pulse reads the Play tracks. ("Docs drift; consoles
  don't," as Tidbits put it.)

When the target device cannot be observed directly (a TV across the
room, a device whose console you cannot read), the loop's first job is
to build the instrument. See `docs/DEVICE-HARNESSES.md`. Do not iterate
blindly on behavior you cannot observe. Diagnostics come before another
attempt, always.

## 2. Trust nothing you did not measure, including your own tools

One session logged four distinct ways the loop's own instruments lied,
all in two days: `head -N` cutting off the evidence; a log grep matching
the script text in a `##[group]Run` header instead of the output;
calling a push failed when it was attempt 1 of a retry that succeeded;
and a check that tested a property true by construction. The standing
habits:

- **Step conclusions and exit codes over log greps.** Conclusions cannot
  be faked. Text matching can.
- **A verification run must identify its own configuration.** A "fix"
  was once validated by re-running the old binary after an install
  nobody checked. Make tools print their version and flags. Check the
  build number before diagnosing a report: a "still broken" filed eight
  minutes after an upload finished is a report against the previous
  build.
- **A fault that comes and goes needs repeated trials per arm,** not one
  run each. A race that failed about half the time made a change that
  did nothing look like a fix.
- **When two instruments disagree, build the control experiment** that
  removes variables wholesale (serve the file from localhost; run one
  shape per process) rather than iterating on correlations. An
  instrument must never disturb what it measures, and must say when it
  is blind.
- **A check whose "nothing to do" arrives suspiciously fast is a claim
  to verify.** "Backlog drained" in 94 seconds was a flag that could not
  see the provider. "0 posters to verify" was a boolean that never
  reset. Ten of ten such clearings in one audit were bugs.

## 3. Loop cadence and shape

- **Diagnose, fix, verify, log: that is one tick.** Never stack
  unverified fixes. A second fix on top of an unverified first is how
  regressions compound.
- **Three strikes means change mode.** Pushback after three or more
  rounds of "still broken" means stop fixing and start instrumenting:
  the `3d-feature-debug-loop` reset, with research agents, observable
  evidence, and on-screen debug overlays for what you cannot attach to.
- **Wake-up pacing matches the thing awaited.** Poll external state (CI,
  a store review) at the rate it actually changes. Use long fallback
  heartbeats when a notification will arrive. Never busy-poll something
  that will tell you when it is done.
- **One version convention, written down.** Every commit that touches
  app source bumps the PATCH of `MARKETING_VERSION` and the build number
  in `AppVersion.xcconfig`. MINOR goes up by one (PATCH to 0) only when
  a release carries something a person would call new since the last
  released version: a feature, a new surface. A fix-only release keeps
  its minor and ships at its patch, and a store upload never bumps the
  minor by itself. (Archive Watch's owner corrected an over-correction
  on 2026-09-30: *"we shouldn't be pushing a new minor release for each
  new version ... I want to make sure that we are doing it in a way that
  makes sense each time."*) Both numbers
  only ever go up, which is what every store requires. Pipeline, CI,
  and docs-only commits do not bump. Commit messages quote the owner's
  request verbatim. Commit and push each verified unit, because an
  unpushed tick is work the next session cannot see.
- **Session logs are the loop's memory.** SCRATCHPAD.md gets a dated
  entry per session: what shipped, what was measured (numbers, not
  adjectives), what is **verified** and what is merely **fixed**, what
  waits on an outside event (with the date), and what the owner must
  do. That distinction carries weight: a "fixed" workflow nobody has yet
  watched run is a different claim from a green one.
- **A long submission or migration mid-loop gets a dated RESUME doc**
  (the Tidbits pattern): a disposable, self-contained handoff written to
  survive context compaction, separate from the rolling scratchpad.

## 4. Research comes before architecture

No architecture change to a subsystem other things depend on ships from
pattern-matching or memory. Commission a full best-practices research
pass first (current-year sources, with verified and inferred claims
marked). Check the decision log for approaches already rejected, since
building one again without new evidence is the worst mistake a loop can
make. Then encode the findings as a skill or binding doc, so the next
session inherits the conclusion rather than the search.

The one time Archive Watch skipped this, three caption architectures in
a row were built on a premise that had been measured wrong. And when
the platform vendor documents a capability, measure it on the target
device before building on it: the documentation's claim and the
device's behavior disagreed four separate times.

## 5. Sources of work, in order

- Mine the owner's actual words first. Verbatim requests in commit
  history, session logs, and research notes outrank polish the agent
  thought of itself.
- **Audit before polish.** Do a parity-matrix or feature audit (every
  button, every filter, on the device) before cosmetic iteration.
  Archive Watch's full audit found six shipped regressions, and two
  patterns worth checking on any multi-platform app: **create paths
  ship without their inverse** (create-channel without delete,
  playlist-add without remove), and **parity lands on the new platforms
  without returning to the one it started on.**
- An unapplied binding rule is not an open question. Check the design
  doc and decision log before deciding anything again (Tidbits D053).
- Fix data problems in the pipeline, never per client. A data fix
  reaches every platform on the next publish, with no app release.

## 6. The owner and the agent split the work

The agent does the whole ship. The owner does what only a person with
an account, a signature, or a body in the room can do.

That line moved in 2026. The App Store submission, including the
review submission itself and reading its state afterward, is now CLI
work: `tools/asc_release.py ship` and `status`, driven by the workflows
in `docs/APPLE-SUBMISSION-CLI.md`. Google Play publishes and promotes
through its API (`play-release.yml`, `tools/play-publish.py`,
`tools/play_promote.py`, see `docs/CLOUD-SUBMISSION.md`). The agent
never asks the owner to press Submit, and never reads ship state from
its own notes.

What stays with a person, kept in a standing OWNER section of the
scratchpad or backlog:

- creating accounts and paying enrollment fees;
- accepting agreements, tax, and banking forms;
- answering privacy and data-safety questionnaires;
- declarations that only exist in a console (content ratings, some
  permission declarations);
- recording demo videos a reviewer asks for;
- physical-device QA that needs hands, DNS, signing authority, PIN
  pairing.

The loop never blocks on these silently. It surfaces them, continues
elsewhere, and checks again later.

- **Never re-cut a version for platforms already in review** just to
  align a number.
- **Secrets never enter the tree.** `Secrets.xcconfig` is gitignored;
  keys live in the environment or in CI secrets; an `AuthKey_*.p8` in a
  repo root is an incident, not a convenience. And verify that CI
  actually receives the secrets, because a shipped build silently
  missing an API token is a green-build failure.

## 7. The loop touches stores and real people

- **Cloud submission is the default** (`docs/CLOUD-SUBMISSION.md`). A
  dev box on a beta OS is rejected after upload; the cloud runner has
  the released toolchain.
- **The CI Xcode is not your local Xcode.** Archive Watch's local Release
  builds passed on all three Apple platforms, then the store build
  (a released Xcode 26) failed to archive the Mac app: a `.commands`
  block had twelve entries, and the released result builder takes at
  most ten, while the local beta took more. Never report "the store
  build will compile" from a local build. Run the cloud workflow with
  `submit=false` first whenever anything in the build is new.
- **Verified is not shipped.** On 2026-09-13, Archive Watch's live Apple
  version was 41 versions behind the repo, including a whole feature
  verified on the glass and shipped to nobody. Play was further behind.
  Nothing reported either gap. When a feature is called done, read what
  is live, not what is committed.
- **Batch trivial releases.** Apple ships without asking once builds are
  valid. But after a spelling-only commit went to review hours after
  the previous approval, the owner asked to "hold off on submitting new
  apple versions because of such a small change." So a wording fix, a
  comment, a CI change, or a doc gets committed and waits for the next
  release that carries a real change worth a What's New.
- **No new Play upload while one is in review** (owner, 2026-09-29). Keep
  committing Android fixes, but do not build, upload, or promote until
  the version in review reads approved. A new upload can reset or
  complicate the review.
- **App Review is part of the loop's feedback.** Read rejections as
  data. Keep the review-facing surfaces (account deletion, attribution,
  the privacy manifest) as launch requirements, not polish.
- **Capture tooling enforces its own rules.** A capture script that
  refuses to run with a premium flag set beats a checklist, and
  captures go to a lasting path: "a capture you cannot return to is a
  capture you have to take twice."

## 8. Working style: what the owner had to say more than once

Each of these came from a correction. Every one of them cost the owner
time before it was written down.

- **Read the runbook first.** On 2026-09-24 the owner wrote, twice in
  one day: "All of this is documented and you are re-learning how to do
  everything multiple times," and then, about device testing, "Please
  stop trying to reinvent things you already know how to do." Before
  any operational task (a store submission, a device run, a demo
  recording), grep `docs/`, `tools/`, and the memory folder for its
  runbook and read the hits before planning.
- **An audit loop fixes what it finds without asking.** When the agent
  asked whether to delete wrong records its own tests had left on a
  device, the owner answered: "The goal of the audit is to fix every
  incorrect thing you are finding. Why are you asking me if you should
  fix things?" Find, fix, verify, commit, then report. Still ask for
  real owner calls: content and rights decisions, product direction no
  rule settles, and anything outward-facing (email, store text, public
  posts). Fix bad data carefully: copy it first, change only the rows
  proven wrong.
- **Report times in the owner's local time.** CI, cron, and log times
  are UTC. Convert before writing them to the owner
  (`TZ=<their zone> date`), and when a UTC cron value stays in a
  workflow file, say the local equivalent beside it.
- **Announce the next tick before scheduling it.** The scheduling call
  ends the turn, so any text after it never reaches the owner. The last
  line of a re-arming turn is "Next tick: 5:06 PM" in local time,
  computed from the delay you are about to pass, and then the call. If
  the loop is stopping instead, say so plainly.
- **Warnings are defects.** Asked "shouldn't warnings be fixed instead
  of ignored?", the loop found 53 distinct warnings, 32 of which had
  printed locally for days because every build was grepped for `error:`
  only. Several were real thread-safety bugs. Report the warning count
  from a clean build on every platform, and aim for zero.
- **Commit messages go through `-F` with a quoted heredoc.** Backticks
  inside `git commit -m "..."` run as commands and silently delete the
  word. Write `cat > msg.txt <<'EOF'` (the quotes around EOF turn
  substitution off), then `git commit -F msg.txt`. Fix a damaged message
  forward rather than force-pushing over a branch CI also writes to.
- **"Unable to type-check this expression in reasonable time" usually
  means a wrong argument.** A call inside a SwiftUI view that passes a
  label the function does not have, or the same label twice, sends the
  type checker into a search it abandons, and it blames the whole view.
  In one session Archive Watch split a view four times chasing the
  error before anyone checked the callee's signature. Grep for
  `func <name>` and compare the labels first.
- **Credentials go where the tool looks.** Every tool that signs or
  uploads reads its credentials from one known place: an env file under
  `~/.config/<tool>/`, a named environment variable, a CI secret the
  workflow names. Put them there, with the private key outside the repo.
  Pass values to scripts through the environment rather than pasting
  them into a shell command, and never automate generating a signing
  key that cannot be replaced.
- **The owner's machine is not a build server.** This is the machine
  resource policy, from the incident in `docs/ENGINEERING-PROCESS.md`
  §11:
  - `tools/dev_cleanup.sh` reports stray preview servers, Gradle and
    Kotlin daemons, and ffmpeg runs this repo started; `--stop` ends
    them. Run it before walking away.
  - `tools/ffmpeg_limits.py` is the one prefix every ffmpeg call starts
    from: the whole runner in CI, half the cores at `nice 10` locally.
  - `android/gradle.properties` caps the Kotlin compile daemon
    (`kotlin.daemon.jvmargs=-Xmx2g`), which is a separate process from
    Gradle's and is unbounded by default, and caps parallel workers
    (`org.gradle.workers.max=4`).
  - Release builds run in CI, not on the laptop.

## 9. Context hygiene: what loads every session stays small

Archive Watch measured what every session loaded before its first
prompt: about 382 KB, most of it a scratchpad whose session log went
back to April and a decision log well past its own limit. That crowded
out the code being worked on. Rolling it down to about 80 KB lost
nothing, because everything moved verbatim.

- **SCRATCHPAD.md keeps only the two most recent session-log entries.**
  When you add one, move the oldest into `docs/SESSION-LOG.md`
  (you create it the first time), verbatim, newest first. Rewrite
  Current State when it is wrong rather than appending to it.
- **Ship state is read from Pulse, not typed.** What is live on which
  store comes from the product dashboard (`docs/PRODUCT-PULSE.md`),
  which reads each store directly. A version number written into the
  scratchpad by hand goes stale the day after.
- **MEMORY.md is one line per entry:** a link and a short hook. The
  detail lives in the memory file itself.
- **DECISIONS.md rolls at about 50 KB.** It keeps an index and the recent
  entries in full; older entries move verbatim to archives under
  `docs/decisions/` (you create it at the first roll). Nothing is
  summarized in place, and the append-only rule binds in the archives
  too.

## 10. The pre-push checklist

From a loop of more than 175 ticks: each of these broke CI at least
once. The check is cheap, and missing it costs a second push and
another CI cycle.

- **Unused-import sweeps carry special risk.** A `\bSymbol\(` style
  search misses trailing-lambda calls (no parentheses), function
  references passed without parentheses (`action: save`), and fully
  qualified references. Grep for the bare symbol, and run a sweep
  through CI on a branch before merging it.
- **Removing a symbol while leaving a call site** is the most common
  self-inflicted compile break. After deleting symbols, grep for each
  one across the repo and confirm only the definition is gone.
- **Adding a construct often needs an import you would not guess,** such
  as a concurrency-scope extension that lives in a different module
  from the type it extends.
- **Framework migrations change what can be bound.** Swapping an
  observation mechanism can quietly remove two-way binding (`$store`)
  and break every input call site. Re-bind locally at the top of the
  consuming scope.
- **`git add -A` sweeps up build artifacts** in paths that are not
  gitignored. Check `git status` and `git diff --stat` for surprising
  sizes before pushing, and gitignore artifact patterns ahead of time.
- **When a deprecation warning recommends a new overload, read the new
  signature.** Reordered lambda parameters compile at the declaration
  (the names are positional) and fail confusingly at the call sites.
- **Write recurring replacements down as standing rules** (a blocking
  `alert()` becomes the app's toast, for example) so the loop applies
  them the same way every time rather than finding them again each tick.

## What this costs

Every rule here slows a tick down. Announcing the next tick, reading the
runbook, running a clean build to count warnings, checking what is live
before calling something done: each is a minute or two the loop could
have spent building. And the owner still has to read the session log.

But the owner of Archive Watch asked, on 2026-09-04, only to be able to
tell whether the loop was working. Everything above is how the answer
stays yes.

Start your next loop from this page.
