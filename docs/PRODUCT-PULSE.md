# Product Pulse

`pulse/` is a daily page that reads every channel a shipped app has and
tells you how it is doing: the stores, search, the app's own server, the
open web, and the CI fleet. `tools/pulse_collect.py` fills one file,
`ops/pulse.json`, and the page draws it. There is no framework and no
build step. There is no tracking in the app.

This page is the reference: why it is built the way it is, the rules it
lives by, how to adopt it, and what every reader needs. The shorter
teaching version is stage 06 of the method (`docs/path/06-keeping-it-running.md`).
The reasoning an agent needs lives in the `product-pulse-dashboard` and
`store-metrics-pipelines` skills.

## Why it exists

By September 2026, Archive Watch was live on nine surfaces. Knowing how it was doing meant opening App Store Connect, the
Play Console, the Amazon developer console, the Roku dashboard, Search
Console, three social networks and GitHub, every morning, and holding
the numbers in my head. So, I asked for one page.

I wanted two things from it. I wanted the problems to come to me: a
crash with a fix already written, a two-star review nobody had answered,
a workflow that failed overnight. And I wanted to trust every number on
it, which turned out to be the harder of the two.

**A reader that cannot read says so, and never renders as a zero.**

That is the governing rule. A confident zero from a broken reader reads
as news. Nobody checks it again. A line that says "Roku: not read today,
and here is why" gets fixed that morning.

## How it was built

Pulse was built in Archive Watch over about three weeks, and nearly
every rule below arrived as a specific morning when the page was wrong.

- **September 9.** The first version: 23 readers, one file, one page. Its
  first run in CI found three bugs, including counting Archive Watch's
  own Mastodon posts as mentions of itself. The chart kit and the
  binding look rules (below) arrived the same day, then drill-downs, and
  a rule that a partial run merges into the last reading instead of
  replacing it. That day also concluded that Play's install export was
  dead. It was not, and that conclusion cost a week.
- **September 14.** I wrote: "No macOS or Roku items on Reach." The Mac
  had been reading zero because Apple files Mac sales under a different
  family of product codes. The Roku was drawing a four-day flat line of
  zeros for a platform with 112 installs, because a missing column was
  read as zero. That day produced the three rules the collector is now
  built around: a missing column is null, a run with a third of its
  readers dark refuses to write, and every section a reader owns is kept
  when that reader fails. It also split one page into seven views, one
  per audience.
- **September 15.** The daily run moved earlier, after measuring that
  GitHub's scheduled runs start four to five hours late.
- **September 25.** Search Console arrived, and the page was redesigned
  around two lists, **Needs attention** and **Going well**, with one
  drawer for every drill-down. I asked for it to be "much more
  action-oriented ... better drill downs, more information overall." The
  alarm thresholds were retuned to the lags each store actually has.
- **September 30.** Ported into this template: every Archive Watch name
  and number replaced by one config file, a third reader state (not
  configured) added, and each part of the page drawn inside its own
  error guard, so a bug in the page can never look like missing data.

The dated record, with every commit, is in
`docs/maintaining/PULSE-PORT-2026-09-30.md`.

## Adopting it

1. Copy `ops/pulse.config.example.json` to `ops/pulse.config.json` and
   fill in what your app is: its name, site, repository, time zone,
   App Store ID, Play package, and whichever other channels you have.
   Anything `tools/app_config.py` already knows is used as a fallback.
2. Run `python3 tools/pulse_collect.py`. It is a dry run. Every reader
   prints `ok`, `off` (not configured, with the config key to set), or
   `--` (configured but could not read, with the reason).
3. Open `pulse/?fixture` to see the page drawn from a synthetic reading,
   then `pulse/` for yours.
4. Add credentials one store at a time, as repository secrets. Every
   secret you skip stays on the page as a named step, never a wrong
   number.
5. When the dry run looks right, uncomment the `schedule:` block in
   `.github/workflows/pulse.yml`. Add `Pulse` to your Pages deploy
   workflow's `workflow_run` trigger, or the site keeps serving
   yesterday's reading.

Optional: `pulse/worker-example/` is a small Cloudflare Worker (free
tier) that keeps privacy-preserving daily tallies (`day | kind | count`,
never a person) and a drop box for stores that deliver reports by
webhook, which is how Roku's reports arrive.

## The collector's rules

Each of these has a test in `tools/test_pulse_collect.py`, and each test
was checked to fail against a broken version of its rule.

1. **Every reader runs on its own.** A failure is recorded in `sources`
   with its reason and shown on the page.
2. **Three states, not two.** `ok`, `dark` (could not read), and `off`
   (not configured). Off does not count against the day.
3. **A bad day is refused, not saved.** If a third or more of the
   configured readers are dark, `--apply` will not write. Yesterday's
   good reading stays up.
4. **A failed reader keeps its last value, marked stale.** `OWNS` and
   `HEALTH_OWNS` must cover every section a reader writes. Three sections
   once vanished on a run without their credentials; a test now asserts
   the map is complete.
5. **A missing column is null, never zero.**
6. **`--only` merges.** A partial run never deletes what it did not read.
7. **Reviews and mentions accumulate**, deduplicated by identity, because
   a fuzzy search that does not repeat a result is not evidence that the
   post was deleted.
8. **Staleness comes from the source's own update time**, not from the
   newest row, and the alarm waits for each store's measured lag (Play
   installs up to 14 days, acquisitions 8).
9. **Count only what servers and stores already see.** No new ping from
   the app, ever. Visits and route views are never summed together.
10. **A crash with a fix in hand asks to be shipped.** `ops/fixed-in.json`
    names the build that fixes a crash cluster; Pulse puts it in Needs
    attention until that build is live.

## How it LOOKS

These rules are binding. A new panel cites one, and if none fits, the
rule set gets a new entry before the panel gets written. `pulse/pulse.js`
and `pulse/charts.js` cite them by number.

1. **A number alone means nothing. Give it a comparison:** against a
   scale, against its siblings, against its own past, or as a share of a
   whole. "4.4" is a fact. "4.4 of 5, target 4.5, up 0.03 since
   yesterday" is a finding.
2. **Encode in Cleveland and McGill's order.** Position first, then
   length, then area, and color last. No pie charts, no donuts, no
   bubbles.
3. **Color means state, never quantity.** Teal is live, amber is in
   flight, red needs you, grey is nothing yet.
4. **No gauges, no dials.** A bullet graph shows the measure, the scale,
   the bands and the target in a strip 22 pixels tall.
5. **Word-sized graphics sit beside their number.** A sparkline is read
   in the same glance as the figure it belongs to.
6. **Zero is drawn, absence is written.** A source that returned zero
   gets a bar of length zero. A source that could not be read gets the
   words "not read" and the reason.
7. **The panel is the cell, not a card.** Separation comes from the
   grid's own hairlines. No tinted boxes, no shadows.
8. **Every number opens, and it opens the same way.** One drawer (a
   native `<dialog>`), routed in the URL hash so it can be linked. Every
   drawer carries a dated chart with its change, the complete table
   behind the figure, and a link to the source.
9. **A chart over time shows when.** First and last dates, the top of
   the scale, and every value under the pointer or the arrow keys.
   Instants are shown in the configured time zone, never UTC. Series
   side by side share one calendar and one scale.
10. **A change names its period.** "+18% vs prior 7 days", never a bare
    arrow. A day still in progress is never compared.
11. **A panel standing on an old reading says "as of".**
12. **Only essential words.** A caption is a refusal, a warning, or a
    fact the reader could not find by looking. The reasons for a chart's
    shape live here, never under the chart.
13. **The page writes no style declarations.** Presentation lives in
    `pulse.css`. The one exception is a computed length inside
    `charts.js`.

The chart kit (`pulse/charts.js`) is hand-drawn SVG with no library:
bullet, bars, spark, stack, dots, run chart, calendar heat, dot plot,
pareto, and a dated time chart for the drawers.

## The readers

39 readers, in the order they run. "Needs" is what makes a reader
answer instead of reporting itself `off`.

| Reader | Reads | Needs |
|---|---|---|
| `apple_stores` | versions and review state, per platform | `apple.appStoreId`; `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` |
| `apple_reviews` | customer reviews, paged | same |
| `apple_rating` | public rating | `apple.appStoreId` only |
| `apple_performance` | launch, hang, and memory metrics | App Store Connect key |
| `apple_downloads` | units from the sales report, filtered to your Apple ID | `ASC_VENDOR_NUMBER`, a Sales and Reports key (`ASC_REPORTS_KEY_ID`) |
| `play_stores` | tracks and releases | `play.package`; `PLAY_SERVICE_ACCOUNT_JSON` |
| `play_reviews` | reviews (Play keeps 7 days) | same |
| `play_vitals` | crash and ANR rates | same, with the Reporting API enabled |
| `play_crashes` | crash clusters, judged against the live build | same |
| `play_users` | distinct users by dimension | same (withheld below an audience floor) |
| `play_reports` | installs from the reports bucket | `PLAY_REPORTS_BUCKET` and a bucket grant |
| `play_daily_exports` | the daily export files | same |
| `play_rating` | public rating | `play.package` |
| `play_acquisition` | store listing acquisitions | the reports bucket |
| `amazon_vitals` | Fire TV vitals | `amazon.package`; `AMAZON_CLIENT_ID`, `AMAZON_CLIENT_SECRET`, a profile mapped to the Reporting API |
| `amazon_installs` | installs, as $0 rows in the sales report | same |
| `amazon_live` | the live version, read through an edit | same, plus `AMAZON_APP_ID` |
| `roku_engagement` | Roku's reports, from the webhook drop box | `web.ingestOrigin`; `PULSE_INGEST_ORIGIN`, `PULSE_INGEST_TOKEN` |
| `manual_stores` | stores you declare by hand | `ops/stores-manual.json` |
| `social_program` | your own posting ledger | `social/posted.json` |
| `social_reach` | followers per platform | `social.profiles` and tokens |
| `social_replies` | replies on Bluesky | `BLUESKY_HANDLE` and an app password |
| `social_liveness` | whether each post is still up | the posting ledger |
| `youtube_channel` | channel statistics | `YOUTUBE_*` with `youtube.readonly` |
| `mentions_reddit` | Reddit search (RSS) | `mentions.query` |
| `mentions_hn` | Hacker News (Algolia) | `mentions.query` |
| `mentions_lemmy` | Lemmy search | `mentions.query` |
| `mentions_news` | Google News RSS | `mentions.query` |
| `mentions_bluesky` | Bluesky search | Bluesky credentials |
| `mentions_mastodon` | Mastodon search | `MASTODON_INSTANCE`, `MASTODON_ACCESS_TOKEN` |
| `github` | stars, traffic, issues | `product.repo`; `GH_TOKEN` (traffic needs repo admin) |
| `workflows` | the CI fleet auditor | `product.repo`; `GH_TOKEN` |
| `web_usage` | daily visit tallies | `web.counterOrigin` |
| `counter_tallies` | other daily tallies | `web.counterOrigin` |
| `cloud_api_usage` | a Google Cloud API's usage | `cloudUsage.project`, `cloudUsage.service` |
| `search_console` | clicks, impressions, queries | `search.site` |
| `search_index` | pages Google cannot index | `search.site` |
| `distribution` | where the app is live, combined | nothing |
| `asks` | requests and praise, drawn from reviews and mentions | nothing (runs last) |

## Traps the code does not show

- **Apple's sales report covers every app on your account.** Filter by
  Apple Identifier, or another app's units get counted as yours. Mac
  products use their own codes (`F1`, `FI1`); unknown codes are recorded,
  never dropped.
- **Amazon's `invalid_scope` is a missing mapping, not a denial.** Attach
  the security profile under My Settings, API Access. A 404 means the
  route is real with no data; a 400 means no such route. Never delete an
  edit you did not open: it is someone's submission in flight.
- **Roku delivers reports to a webhook.** Store each payload raw,
  acknowledge it only on `--apply` (a dry run once consumed the only
  copy), and never acknowledge one you could not read. Cloudflare
  answers the default Python user agent with a 403 that looks exactly
  like a bad token.
- **Google Cloud Monitoring needs the `x-goog-user-project` header**, or
  it fails with a message about billing.
- **Reddit's JSON search is 403 without login; the RSS of the same
  search works.** It is fuzzy. The relevance filter is what makes it
  usable.
- **YouTube statistics need `youtube.readonly`.** A posting token is
  usually upload-only on purpose. Report that as a choice, not a fault.
- **GitHub traffic needs a token with repo admin.** "0 views" and "not
  permitted to ask" are different claims.
- **A hand-kept store row is not a store without an API.** Give each row
  an `api` key saying what is machine-readable, and let the renderer
  believe it.
- **GitHub's cron runs late**, often four to five hours. Schedule for the
  lag.

## The shape of `ops/pulse.json`

```
generatedAt, repoVersion, repoBuild, app { name, site, timezone, ... }
sources    { name: { ok, off, note, at } }   read this before believing a zero
stale      { section: lastGoodTimestamp }
stores[]   ratings[]  reviews[]  mentions[]  distribution{}
social     { posts[], byPlatform{}, reach{}, ... }
health     { workflows[], issues[], playVitals{}, playCrashes[], playInstalls{},
             playUsers{}, appleDownloads{}, applePerf{}, ... }
github     { stars, views14d, uniques14d, openIssues }
asks[]  loves[]
history[]  one compact row per day, scalars only, kept forever
```

## Tests

| File | Covers |
|---|---|
| `tools/test_pulse_collect.py` | every collector rule above, with no network; the drop box is a local server that refuses the default Python user agent |
| `tools/test_pulse_charts.mjs` | a bar's length is proportional, a bullet clamps, a stack sums to 100%, a one-point series draws nothing, sparklines share a scale |
| `tools/test_pulse_render.mjs` | the real `pulse.js` against the fixture (or any reading), including that a code error is reported as a code error |

Run all three before changing the page. A test that has never failed may
be asserting nothing.
