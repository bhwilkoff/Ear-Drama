# How we engineer

For two days in 2026, a workflow in Archive Watch published the app's
catalog without the token it needed. It skipped its database build,
skipped every check, and reported success. The catalog in everyone's
hands went stale, and nothing turned red.

**A system that cannot say it is broken is the worst kind.**

I want every app built from this template to be able to tell us the
truth about itself. That means the pipelines, the tests, the dashboards,
and the notes we leave for the next session. So this page collects the
engineering disciplines Archive Watch paid for, each one with the
incident that taught it, so you can judge the rule by its evidence
rather than take it on trust. Archive Watch's own version of this page
held eleven of them. These are the ones that travel to any app.

Most of the expensive faults behind these rules were green. That is the
thread running through all of them.

## 1. Absence is not evidence

A reader that could not read must say so. It must never show up as a
zero, a blank, or a quiet gap.

Archive Watch's product dashboard (see `docs/PRODUCT-PULSE.md`) learned
this four ways in one week:

| What happened | What it looked like |
|---|---|
| The reviews reader failed in CI on a Python syntax error | "0 reviews", beside four healthy readers |
| A partial run overwrote the file for the parts it did not collect | Every mention CI had gathered, gone |
| A full run dropped the section of a reader that failed | Four reviews became a hole |
| A fuzzy search did not repeat its result | A real third-party mention disappeared |

Each one is the same lie told a different way. The fixes all live in the
collector: every source records its own failure, partial runs merge
rather than replace, a failed reader keeps its last value marked stale,
and mentions accumulate.

**Apply it:** when a function can return nothing, ask whether "nothing"
and "could not tell" look different to the caller. If they do not, that
is the bug, before any other behavior gets written.

## 2. A green run is not a working run

Every serious pipeline failure in Archive Watch's history was green.

- The catalog publisher described above ran for two days with no token,
  and the health auditor could not see it, because that workflow sat on
  a list that meant "skip entirely".
- A verification step passed an empty record to a function whose every
  branch began "if this field is present". So the empty record cleared
  nothing, while 266 items were marked cleared.
- A release upload deleted the old assets before uploading the new ones.
  The upload failed on a 1.17 GB file, took both assets with it, and a
  `|| echo "first run"` swallowed the evidence. That green run destroyed
  702,148 word timings.

**Apply it:** an exit code says the code ran. It does not say the work
happened. Assert the yield: rows written, files present, counts that
grew. `tools/sqlite_publish_guard.py` and `tools/audit_workflow_health.py`
exist for exactly this, and `docs/CI-FLEET.md` carries the rest.

## 3. A test is not a test until you have seen it fail

Write the check. Then break the code it guards, on purpose, and confirm
the check fails. Then record the failure count in the commit message.

This is not ceremony. Archive Watch had a function meant to recognize
the Apple TV home screen that returned False for every frame since the
day it was ported. The port had added a defensive branch the original
did not have, and a bare `except` hid it, so a guard built on it never
ran once. A test that has never failed might be asserting nothing at all.

The commit records the control like this:

```
test_pulse_collect      55 cases; 7 fail with relevant() stubbed to True
test_sw_bypass           9 cases; 2 fail with the /pulse bypass removed
CatalogCorruptionTest    6 cases; 4 fail when matching the bare word "corrupt"
```

**Apply it:** no new check lands without a line like one of those. If
you cannot make it fail, you do not yet know what it tests.

## 4. Verify on the glass, in the environment that ships

Compiling is not running. Running on a simulator is not running on the
device. And running the debug build is not running what people install.

- Google Play rejected an Archive Watch release because the release
  build's code shrinker stripped a database constructor that was only
  reached through a widget. Debug builds never shrink, so every debug
  install looked perfect. The Play submission script now refuses to
  upload if the release artifact crashes on a real device.
- A `| tail` on an `xcodebuild` once hid a `BUILD FAILED`, and a fix was
  nearly reported as verified. Always grep for the verdict.
- The dashboard looked stale while the deployed data was current. The
  viewer's service worker, registered at the root scope, was serving the
  dashboard from its cache.

**Apply it:** say plainly what was verified and where. "Compile-verified,
not run" is a complete and honest sentence. Claiming more than that is
the one thing that is never acceptable.

## 5. Measure before theorizing, and write down what you ruled out

Archive Watch's Android cold start went from 32 seconds to 6.3 seconds
only after five plausible theories were measured and reverted. One of
them, compressing each row, actually made the download bigger.

Writing down what was ruled out is worth as much as the fix, because it
stops the next session from walking the same ground.

**Apply it:** when a fix lands, the commit says what else was tried and
why it was wrong.

## 6. A negative finding needs a method and an expiry

But a note about what was ruled out can do harm of its own.

Archive Watch's Amazon submission tool once concluded, in its own
docstring, that a settings page "does not exist in this console", and
ended with: "Do NOT re-walk the console nav." The page did exist, one
menu over. Amazon's submission and reporting APIs then stayed
unreachable for five weeks over a two-click setting, and the note
written to save time is what stopped anyone from looking.

So, a negative finding never becomes a prohibition. It says **how** it
was found and **when** to check again. An absence you searched for once
is much weaker evidence than a measurement, and consoles change.

**Apply it:** write "not found under the console's Settings and Account
menus on <date>; re-check before building a workaround", never "do not
look again".

## 7. Search the decision log for the mechanism, not the symptom

Most of one evening in Archive Watch went into building a local media
server, a way to pass streaming video through a custom loader, and
rediscovering a platform error code that refuses one shape of it. All
three were already written down in the repository. The log had been
searched for the symptom (audio dropping out) and never for the thing
about to be built.

A symptom search finds nothing when the bug is new. A mechanism search
would have found all of it, and reusing the existing server took one
build.

**Apply it:** before you write any server, loader, wrapper, or
transport, grep `DECISIONS.md`, the code, and the memory folder for
that mechanism by name.

## 8. A decision's Consequences paragraph goes stale first

Archive Watch's Decision 119 ended by saying the Roku app still could
not share a playlist, and that fixing it was "a separate piece of
work". It was false within the same session: the fix landed an hour
later. A day after that, a photograph of the television decoded to the
full share link. Decision 121 exists only to correct 119, because the
log is append-only and a reader who stops at 119 would rebuild a
working feature.

The body of an entry and its closing paragraph are written at different
moments. The closing paragraph is where "still open" and "a separate
piece of work" live, and it is the part most likely to be wrong by the
time anyone reads it.

**Apply it:** before you repeat a "cannot" or a "not yet" from any
entry, check the code. When you find one that is wrong, write the
correction as a new entry and mark the old paragraph, rather than
deleting it. A wrong claim that was read and believed is worth seeing.

## 9. Popularity is not editorial judgement

Archive Watch's daily social posts once published *The Birth of a
Nation* as "Free to watch", with two cheerful hashtags. Every signal the
selector rewarded pointed at it: tens of thousands of votes,
professional artwork, a silent film. A movie database's own descriptor
tags for it included "inspirational" and "feel-good".

Nothing in the system was making an editorial decision, so ranking made
it.

Archive Watch now keeps a do-not-promote list that gates broadcast
only, never the app. Holding a work and recommending it are different
acts. An archive is valuable because it keeps difficult material, and a
daily post with two hashtags has no room for the context some films
require. (The `values-based-feed-ranking` skill carries the general
form.)

**Apply it:** any automated surface that recommends needs a place for a
human judgement that ranking cannot express.

## 10. A number needs a comparison, and a chart needs a reason

A figure on its own tells the reader nothing about whether to worry. So
every number on a dashboard is shown against something: a scale, its
siblings, its own past, or a whole. Charts encode by position first,
then length, then area, then color, which rules out pies, donuts, and
bubbles. Color means state, never quantity. And zero is drawn, while a
missing value is written out in words, which is rule 1 again.

**Apply it:** `docs/PRODUCT-PULSE.md` and the `product-pulse-dashboard`
skill carry the full set.

## 11. The owner's machine is not a build server

On 2026-09-09, the owner of Archive Watch asked why his Mac had slowed
to a crawl. There were two causes.

1. Two image-rendering scripts had been running at 98% CPU each for
   three and a half days, stuck in a text-wrapping loop from code that
   had already been fixed. A fix does nothing for a process already
   spinning.
2. Gradle's daemon had a memory cap, but the Kotlin compile daemon is a
   separate process whose memory was unbounded, and parallel builds had
   no worker cap.

A third case turned up later: three local preview servers, two of them
more than two days old. Nobody noticed, because an idle process is
invisible until something else needs the machine.

The lasting answer was not a smaller memory setting. Release builds
moved to CI, local ffmpeg runs got half the cores at a lower priority,
and a cleanup script now finds what a session left behind. The machine
resource policy in `docs/AUTONOMOUS-LOOPS.md` §8 has the specifics.

**Apply it:** anything that can saturate the machine gets a bound and a
CI path. A tool that is correct but can hang is not finished. Prefer a
test that runs in-process to a server left running. And run
`tools/dev_cleanup.sh` before walking away.

## 12. A red X means this run could not do its job

An alert channel that cries wolf is one the owner mutes, and then a
real break goes unread. Archive Watch learned this by being corrected
twice (its Decision 107).

An auditor never fails over somebody else's health: its findings go to
a report or an issue, never to its own exit code. A partial success is
a warning. A run cancelled because a newer one replaced it was never a
failure, since the workflow asked for exactly that.

**Apply it:** before a check exits non-zero, ask whether this run
failed at its own job. `docs/CI-FLEET.md` carries the full doctrine.

## 13. The instrument is the first suspect

Rule 2 is about a run that did no work. This one is narrower and
nastier: the test apparatus returning the wrong verdict about work that
did happen. Archive Watch's watch-together feature produced eight of
these in one session, and in four of them the verdict was the opposite
of the truth.

- An assertion judged the last recorded segment and passed over the one
  that mattered. An instrument that chooses which sample to judge will
  eventually choose the wrong one.
- A readiness probe became the first connection through a test proxy
  meant to cut a connection, so the proxy cut the probe and the test
  recorded a clean stream. A test instrument must not be visible to the
  test.
- A throttling proxy read from the client at full speed and only
  delayed the forward, so the app saw no congestion and truthfully
  reported none. Back-pressure comes from not reading.
- A comparison passed on 58.4 bytes against 58.3 while printing "0%
  smaller". A comparison is not a measurement, so demand a margin.
- Frame counts were compared as totals across a nine-second window and a
  six-second one. Compare rates.
- `print` goes to standard output, which is fully buffered when piped,
  so killing the app discarded everything it had said. That was twice
  reported as "zero health lines" from an app that was working. Send
  diagnostics to standard error.
- A test runner reported PASS over zero parsed results, then stopped
  silently mid-suite while returning exit 0. A runner that can lose its
  own result is the most expensive kind of green.

**Apply it:** before believing a verdict, run the control that should
obviously produce the opposite one. Report pass, skip, and fail as
three separate numbers, because a skip absorbed into green is how four
test cases went unrun for a whole session. And prefer evidence the
instrument cannot distort: a server's own byte counter, a recording
read back by a decoder that shares no code with ours, a photograph of
the screen. `docs/DEVICE-HARNESSES.md` holds the instrument-honesty
rules.

## What these rules cost

Every one of these is slower than skipping it. Breaking a test on
purpose takes a few minutes. Writing down what you ruled out takes a
paragraph. Moving a release build to CI means waiting on a runner
instead of watching your own terminal. And a page of rules like this one
can itself go stale, which is why each rule carries its incident: you
can check whether the evidence still holds.

But each incident above cost more than all of that combined, and most
of them cost it silently.

## The shape of a change

1. **Read** the binding doc for the surface and quote the rule the
   change implements (`binding-design-doc-discipline`).
2. **Search** the decision log for the mechanism you are about to
   build.
3. **Measure** before theorizing. Write down what you ruled out, and
   how.
4. **Write the test, then break it,** and record the failure count.
5. **Verify in the shipping environment,** and say exactly what you
   verified.
6. **Bump** the version in `AppVersion.xcconfig`.
7. **Commit** quoting the owner's words where they prompted the change,
   and naming what was tried and rejected.
8. **Log a decision** if the next person would get it wrong without
   knowing (`architectural-decision-log`).

## Where each discipline lives

| Concern | File |
|---|---|
| Product health, every channel | `docs/PRODUCT-PULSE.md`, `tools/pulse_collect.py` |
| Workflow health and alerting | `docs/CI-FLEET.md`, `tools/audit_workflow_health.py` |
| Workflow shape gates | `tools/check_workflow_gates.py` |
| Shared-index safety | `tools/sqlite_publish_guard.py` |
| Real-device observation | `docs/DEVICE-HARNESSES.md`, `docs/AUTONOMOUS-FLEET-TESTING.md` |
| Store submission | `docs/APPLE-SUBMISSION-CLI.md`, `docs/CLOUD-SUBMISSION.md` |
| Loops and working style | `docs/AUTONOMOUS-LOOPS.md` |
| Machine resource policy | `tools/dev_cleanup.sh`, `tools/ffmpeg_limits.py`, `android/gradle.properties` |

Pick the rule you broke most recently. Be ready to name its incident in
your own app.
