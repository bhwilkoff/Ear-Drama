---
name: product-pulse-dashboard
description: Build a daily product-health dashboard that reads every channel a shipped app has — store submissions and reviews, downloads and installs, crashes, search, server-side usage tallies, social posts, mentions across the open web, CI health. Use when someone asks for "one place to see how the app is doing", a metrics or KPI page, an ops dashboard, a Needs attention list, drill-downs, or wants to track store performance and user feedback over time; also when a Pulse reading is stale, refused, or shows a suspicious zero.
---

# Product Pulse: one page that knows how the product is doing

A shipped app scatters its signals: reviews in App Store Connect, installs in a
Cloud Storage bucket, crashes in Play Console, engagement in five social APIs,
mentions nowhere at all. Nobody visits six consoles daily, so nobody sees the
2★ review that says the app will not play anything.

This skill builds the page that collects them, and — more importantly — the
three rules that decide whether anyone can trust it.

## The three rules

### 1. A reader that cannot read SAYS SO. Never a zero.

This is the whole skill. Everything else is presentation.

Wrap every source. A failure is recorded **in the output** and rendered as
"could not read — no credential in this environment", never as `0`. A confident
zero from a broken reader is worse than no dashboard: it reads as good news and
nobody checks again.

There are four routes to that lie and a real dashboard hits all of them:

| Route | Symptom | Fix |
|---|---|---|
| The reader threw | "0 reviews" beside healthy panels | isolate per source; record `{ok, note}` |
| A partial run overwrote | Yesterday's mentions vanish | `--only` MERGES; it replaces only what it collected |
| A full run dropped a failed section | Four reviews become a hole | a failed reader keeps its last value, marked `stale` |
| A fuzzy search did not repeat | A real mention evaporates | mentions and reviews ACCUMULATE, deduped by identity |
| A health key missing from the carry map | A section silently vanishes when its reader fails | `HEALTH_OWNS` covers every `state["health"][k] =`, asserted by a test |
| A missing column defaulted to 0 | "0 installs" for a platform with 112 (the rows came from a different report) | `num_or_none`: a missing cell is NULL; series keep only days that carry the column |
| An unknown vendor code skipped silently | macOS read ZERO for weeks (Mac product codes are a different family) | record every skipped code WITH its units, on the page |
| A tool that "succeeded" at nothing | "0 findings" from an auditor that audited nothing | positive test: require "Checked N" with N > 0 |

**Not configured is not broken.** A reader the app has not set up (no App
Store id in the config) records `off: true` and the page says "not configured"
— a third state, never merged with "could not read". Config is identical on
every machine; credentials are not.

**Refuse a reading you cannot trust.** A laptop holds a few credentials, CI
holds all of them. A local `--apply` with many readers dark still carries each
dark section forward (correct), and committing it replaced CI's fresh numbers —
a platform vanished hours after being fixed. If a THIRD or more of the
configured readers that ran were dark, `--apply` refuses (exit 0, says why;
`--force` overrides). The guard is on the shape of the run, not the machine.

**A dry run must not consume.** A reader whose source deletes what it acks (a
drop box) acks only on `--apply`, and never acks a payload it could not parse —
that payload is the only evidence of the shape that broke it.

And one more, from the workflow rather than the code: **a secret that exists but
is never passed to the step is indistinguishable from one that was never made.**
Assert it — read every `os.environ` name out of the collector and check the
workflow carries it. That test caught its own omission the day it was written.

### 2. Every number carries a comparison, and colour never carries quantity

Follow Few and Cleveland & McGill, in that order:

- **A bare number means nothing.** Show it against a scale, its siblings, its
  own past, or a whole. "4.4" is a fact; "4.4 of 5, target 4.5, up 0.03 since
  yesterday" is a finding.
- **Encode by accuracy**: position, then length, then area, then colour. So
  there is no pie, no donut, no bubble. Ever.
- **Colour means STATE** — live, in flight, needs you, nothing yet. A bullet
  graph's qualitative bands are one hue at three intensities so the chart
  survives colour-blindness and spends no colour on a number.
- **No gauges.** `bullet()` carries measure, scale, bands and target in 22px;
  a gauge carries one number in a quarter of the screen.
- **Zero is DRAWN; absence is WRITTEN.** A server tally that writes a row
  only on an active day (rooms opened, say) must be zero-filled for every
  day since it began, whenever its source ANSWERED; otherwise a quiet week
  reads as a stale reader.

`pulse/charts.js` implements exactly this: `bullet`, `bars`, `spark`, `stack`,
`legend`, `dots`, `ratio`, `cadence`, plus the question-driven forms —
`runChart` (series against its own ±2σ: "is this normal?"), `calendarHeat`
("did it keep coming?"), `dotPlot` (many ranked categories), `pareto` ("what do
I fix first?"), `timeChart` (dated, with a keyboard/pointer readout), `spans`
(when each version was seen). Hand-rolled inline SVG, no library.

The look rules that came later, each from a real complaint:

- **Sparks in a row share ONE scale** (`max`/`min`), or 3/day and 300/day draw
  the same picture. Small multiples on one calendar grey the days a series
  does not cover, so a stalled reader looks different from a quiet week.
- **A chart over time shows WHEN**: first/last date, top of scale, a readout.
  Instants in the owner's time zone, never UTC.
- **A change names its period**, always, from one function: "+18% vs prior
  7 days". A day still in progress is never compared; no comparison against
  a prior period the vendor never measured.
- **Stale says "as of"**: past a source's MEASURED lag, an amber chip and a
  Needs-attention line.
- **Only essential words**: a caption is a refusal, a warning, or a fact the
  reader cannot see. Reasons live in the doc and code comments.
- **The page writes no style**; the one exception is a computed length, set
  as a custom property.

### 3. Every panel opens, and every number links to where it came from

A number you cannot open is a number you have to take on trust, which is the
opposite of what the page is for. Each panel gets a `detail` list and an
outbound `href`: the rating opens to the reviews, followers to the actual
profiles, a crash cluster to its Console issue with the exception, *your own*
stack frame, the build range and whether it is on the live build.

Progressive disclosure stays predictable: a chevron expands in place, a link
leaves, and nothing does both.

## The one list that asks for a decision

The Overview opens on **Needs attention / Going well**, and every item comes
from ONE `RULES` table (id, JSON path, threshold, tier: decide / watch / good).
A new signal is a new row, never a new rendering branch — and the doc carries
the same table. Each item: a sentence, a number, its comparison, its period,
and a drawer. Tier colours down the left edge; six shown, then "N more".

What goes in it is a judgement worth getting right:

- **Filter by whether the USER's problem is live, not by whether you replied.**
  A first version filtered low-star reviews to unanswered ones, which put the
  app's one 2★ — *"Broken: latest update will not play any films"* — underneath
  a green "Nothing is asking for you."
- **Filter crashes by the build that is LIVE.** Twelve clusters where eleven
  were last seen two releases ago is a list nobody reads. Compare each cluster's
  `lastAppVersion` to what is actually in production.
- **A crash with a fix written but not shipped is a RELEASE task, not a fix
  task.** Record the Android `versionCode` carrying it (`ops/fixed-in.json`);
  at or below Play's live build = shipped, at or below in-flight = in review,
  otherwise "fix in repo, not released". Never compare an Apple build number.
- **Usage fell / rose** = the last 7 COMPLETE days vs the 7 before, with a
  floor (≥10) so tiny counts do not scream. A series older than its lag is
  "stale", never compared.
- **When it is empty, say so in words.** "Nothing is asking for you" plus what
  was checked beats a blank panel, which is indistinguishable from a broken one.

## Views, drawers, and what the page may not do

- **One view per audience/question**, from ONE `VIEWS` list the tabs and the
  router both read (they disagreed once; a tab looked dead): Overview, Reach,
  Engagement, Health, Voice, Search, Program, Ops, plus a section per platform.
  The social program is its own view — posting next to installs invites a
  causal reading neither supports. Moving a SECTION without moving its PANELS
  is a half-measure that looks complete. Never combine engagement units across
  platforms into one "engaged users" number.
- **One drill-down**: a native `<dialog>` drawer routed in the hash
  (`#health/crash/<id>`), carrying a dated chart with its change, the COMPLETE
  sortable table (never silently capped), and the source link.
- **A code error is not a data failure.** Draw each part in its own
  try/catch and report a throw as "a bug in pulse.js, not a data problem" —
  a fetch chain whose `.catch` said "Could not load the readings" sent the
  owner to check data that was fine.
- **Nothing about the app in the page code.** Name, site, repo, time zone and
  profiles ride in the reading's `app` block.

## Counting usage without breaking the privacy promise

A usage number comes from something a server ALREADY receives to provide the
feature (a room it opens, a feed it serves), or from a vendor's own reporting
(Cloud Monitoring's count of the app's API calls) — never from an app sending a
new count. A first-party counter stores `day | shape | count` only; a VISIT and
a ROUTE VIEW are separate keys and never summed. If a question cannot be
answered that way, the answer is a privacy-page change the owner makes, not a
reader.

## Getting it running

1. Copy `ops/pulse.config.example.json` to `ops/pulse.config.json`; identity
   the template already knows falls back to `tools/app_config.py`. Blank =
   that reader is off. Credentials are env only.
2. `python3 tools/pulse_collect.py` — dry run: `ok`, `--` (dark, with the
   reason) or `off` (not configured) per reader. `--only a,b` MERGES.
3. `--apply` writes `ops/pulse.json`; open `/pulse/`. `/pulse/?fixture`
   renders a synthetic reading (`tools/pulse_make_fixture.py`) with no
   credentials at all.
4. `.github/workflows/pulse.yml` ships DORMANT; uncomment its triggers once
   configured. Tests: `tools/test_pulse_collect.py`,
   `tools/test_pulse_charts.mjs`, `tools/test_pulse_render.mjs`.

Things that bite in deployment:

- **Crons run late.** GitHub ran one account's schedules 4–5 h late,
  consistently. Measure your lag from run history and schedule for
  "ready by" minus the lag. Add a `workflow_run` re-read of the STORE readers
  only after each release workflow, so a release is on the page in minutes.
- **Alarm past the MEASURED lag, never a default.** Play's acquisition data
  runs 6–8 days behind (lag 8); its install export ~6 days plus a monthly-file
  delay (alarm at 14). A 3-day default called every normal day stale, and a
  page that cries stale teaches its reader to ignore the word.

- **The daily commit carries `[skip ci]`** — correct, or a reading sets the
  whole fleet running — which also means its push triggers **no deploy**. Add
  the collector to the deploy workflow's `workflow_run`, or the site serves
  yesterday's numbers forever.
- **A service worker registered at root scope will cache the dashboard.** Ours
  showed yesterday's panels beside today's timestamp. Exclude the ops paths, and
  assert both halves: the ops pages are never cached AND the app still is,
  because a bypass that swallows the site breaks the PWA offline.

## What "over time" needs

`history` is one compact row per day, forever, and **nothing in it may grow** —
scalars only. That series is the only part that answers "are we getting
anywhere". Text (reviews, mentions) is a capped window, newest first.

The panels fill themselves in from the second day. Say that on the page rather
than rendering an empty chart.

## The reporter rule

This workflow **never fails because something it read is unhealthy**. Findings
go to the page and to a `::warning::`. It fails only when it could not write or
push its own file — and that step carries an explicit
`# reporter-may-fail: <why>` marker that `tools/check_workflow_gates.py`
enforces.

An alert channel that cries wolf gets muted, and then a real break goes unread.

## See also

- `docs/PRODUCT-PULSE.md` — the reference: what each source needs and returns
- `pulse/worker-example/` — optional $0 Cloudflare Worker: counter, tallies,
  and the vendor drop box
- `store-metrics-pipelines` — how each store actually exposes its numbers, and
  the trap in each one
- `mobile-first-density-design` — the density rules the panels obey
- `architectural-decision-log` — log why a source was chosen or rejected
