---
name: store-metrics-pipelines
description: Read downloads, installs, active devices, ratings, reviews and crash clusters out of App Store Connect, Google Play, the Amazon Appstore and Roku, plus Google Search Console and Cloud Monitoring. Use when wiring store analytics into a dashboard or report, when a store API returns 403/406/400/invalid_scope, when a platform reads zero or an export looks "broken", or when someone says a store "has no API" for the numbers they need.
---

# Getting the numbers out of the stores

Every store exposes its data differently and **none of them the way you would
guess**. Each entry below cost a debugging round; the traps matter more than the
endpoints, because most of them look exactly like a permissions problem and are
not.

The meta-rule: **when a store's numbers are missing, the question is never "is
there an API". It is "what route does this store actually offer, and what shape
does the data come in".**

---

## App Store Connect

Auth is a JWT from a `.p8` key. The client reads the key **off disk** at
`~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` — passing the key material
as an env var looks right and reads nothing.

| Want | Endpoint | Note |
|---|---|---|
| Version state per platform | `v1/apps/{id}/appStoreVersions` | filter by `platform`; three platforms are three states |
| Every review, all territories | `v1/apps/{id}/customerReviews` | paged; `include=response` says whether you replied |
| Rating + count | `itunes.apple.com/lookup?id=` | **no auth**, works anywhere |
| Daily downloads | `v1/salesReports` | see below |
| Launch time, hangs, memory | `v1/apps/{id}/perfPowerMetrics` | empty until enough devices opt in |

### Two endpoints do not speak JSON

`salesReports` wants `Accept: application/a-gzip`; `perfPowerMetrics` wants
`Accept: application/vnd.apple.xcode-metrics+json`. Through a client that sets
`Accept: application/json` both answer **406 NOT_ACCEPTABLE**, which reads
exactly like a permission failure. It is not.

### Downloads need a SECOND key, and you cannot widen the first

`salesReports` answers `403 … The API key in use does not allow this request`
for an App Manager key. Apple puts report download under **Finance, Sales,
Admin, Account Holder**; App Manager is "pricing, App Store information, and app
development and delivery".

And the key page says a key **"can't be modified to access more services once
created"** — which its own UI confirms: Edit enables only **Revoke**. There is
no role editor.

So generate a **second** key whose only role is **Sales and Reports**, and keep
it separate from the release key. Widening the credential that ships builds so a
dashboard can read a download count is the wrong trade.

You also need the **vendor number** — App Store Connect → Payments and Financial
Reports, printed beside the legal entity. It is an account identifier, not a
secret.

Rule out first, because the forums are full of Admin keys hitting the same 403:
**agreements** (a missing or expired one produces it) and a wrong vendor number.

Filter the TSV by `Product Type Identifier` — `1`, `1T`, `1E`, `1EP`, `1EU`,
`IA1` are iOS/tvOS first-time downloads, and **Mac apps are a different
family: `F1` (free), `FI1` (in-app)**. Nothing about the first family hints the
second exists; macOS read ZERO for weeks while App Store Connect showed
installs. **Record every code you skip, with its units**, on the page — an
unknown code is the only way this reader under-reports, and it does so
silently.

**The report is VENDOR-wide, not per app.** Filter on `Apple Identifier` (the
numeric App Store id), or another title's units are counted as yours (15 of
201 units once belonged to a different product). The `Device` column (iPhone,
iPad, Apple TV, Desktop) is the only per-platform install split Apple gives —
build per-device country/version splits from it, never the account's.

---

## Google Play

Google's data is the richest of the three, and the good half is in no API.

### Vitals and crashes: `playdeveloperreporting`

Enable the API first (`gcloud services enable
playdeveloperreporting.googleapis.com`); a service account cannot enable it for
itself. Then:

- `vitals.crashrate` / `anrrate` — rates, plus `distinctUsers`
- `vitals.errors.issues.search` — **the crash clusters**: cause, location, first
  and last app version, API range, last seen, and a Console URL
- `vitals.errors.reports.search` with `filter='errorIssueId = "<id>"'` — the
  actual stack trace, from which you want *your own* first frame

Three traps:

1. **A metric set advertises the window it holds** — `freshnessInfo`, the
   `DAILY` entry's `latestEndTime`. Querying past it is a **400** that reads
   like a malformed request. Ask, then query to that date; never guess at
   "today".
2. **`sampleErrorReportLimit` accepts only 0 or 1.**
3. **Rates and `distinctUsers` are WITHHELD below a minimum audience.** The
   queries are accepted and return nothing. "The reader works and Play will not
   publish it yet" is a completely different sentence from "the reader is
   broken", and a dashboard must say the first.

### Installs and active devices: a Cloud Storage bucket

There is no API. The Console writes monthly CSVs to
`gs://pubsite_prod_rev_<id>/stats/`.

- **That id is NOT the developer id in the Console URL** and cannot be derived
  from it. Play Console → Download reports → Statistics → *Copy Cloud Storage
  URI*.
- Grant the service account **"View app information and download bulk reports
  (read-only)"** in Play Console → Users and permissions. Play cascades three
  implied read-only permissions with it, and the save is behind a confirmation
  dialog that is easy to miss.
- **The grant takes HOURS to reach the bucket's ACLs.** A correctly-permitted
  service account reads 403 in the meantime. Fall back to the developer's own
  `gcloud` locally and the reader works today.
- The objects are **gzip-encoded**: `gcloud storage cp` decompresses on download
  and `cat` does **not**, so the same object arrives differently depending on
  how you fetched it — and gzipped bytes parse as a one-column CSV of mojibake
  rather than failing.
- They are **UTF-16 with a BOM and CRLF**. Assume UTF-8 and you get mojibake
  headers; leave the CRLF and `csv` reports "new-line character seen in unquoted
  field" for the whole file.
- **Two lags, stacked — not a broken export.** Install data runs ~6 days
  behind, AND the current month's file does not exist until part-way through
  the month. Early in a month the newest data can be ~3 weeks old and correct.
  Alarm at **14 days**, not 3. Acquisitions (`store_performance`) run 6–8 days
  behind: lag 8. Prefer the plain `store_performance_*` files over the
  `total_*` rollup, which can stall while the plain one is current.
- **The acquisitions export can stop while the installs export keeps going.**
  Measured 2026-10-07: Google last wrote `store_performance` on 09-30 (rows to
  09-24, against a documented 3-7 days) while the installs export in the same
  bucket was rewritten that day. Google had moved store-listing reporting to
  **install clicks**. Dead ends, each measured: the Play Developer Reporting
  API is vitals only, and the Console's statistics service needs the
  `play_console` scope, refused to a service account and to OAuth alike.
  Record the export's own write time and name it in the alert; keep install
  clicks as their OWN series (clicks are not acquisitions: 37 vs 27 on one
  day), read by hand into a manual file with a 7-day staleness until an
  export carries them. Never splice the two.
- **Staleness comes from the OBJECT's update time, never the newest row.** A
  row cannot tell "stopped being written" from "moved", "renamed" or "behind";
  the object metadata (`updated`) can. List the bucket
  (`tools/pulse_play_bucket_probe.py`) before calling an export broken — it
  was called broken twice, wrongly, from rows.
- **A missing column is NULL, never 0.** Parse with a helper that returns
  None for an absent/blank cell and sum only what exists.
- The bucket holds **other apps'** reports. Scope every object name to the
  package.

Files per month: `overview`, `country`, `device`, `os_version`, `app_version`,
`language`, `carrier`. `overview` carries Daily Device Installs, Uninstalls,
Upgrades, **Active Device Installs**, and the user-level equivalents.

### Reviews

`androidpublisher.reviews.list` returns roughly the **last week only**. An empty
answer is normal and is not "no reviews exist" — say so.

### Rating and tracks

Play has no ratings API and prints no listing rating below a minimum audience.
Scrape the listing, and fall back to the `ratings` export's `Total Average
Rating` — saying which source it came from. For tracks, a track can hold a
`completed` release AND a newer in-progress one: live = the completed one,
`inFlight` = the other. Reading `releases[0]` showed whichever Google listed
first. Never compare to the repo's version file (it moves every commit).

---

## Amazon Appstore

There **is** a Reporting/Vitals API — `POST
developer.amazon.com/api/appstore/vitals/apps/{pkg}/{metricSet}:query`, the same
shape as Google's, with `crashMetricSet`, `anrMetricSet` and `lmkMetricSet`.
Scope `adx_reporting::appstore:marketer`, token from
`https://api.amazon.com/auth/o2/token` by client credentials.

### `invalid_scope` means the profile is not MAPPED — it is not a denial

This is the single most expensive trap in this file, because it reads exactly
like an account permissions problem and is not.

A security profile must be **attached to each API individually** at
**My Settings → Enterprise Security Features → API Access**
(`/apps-and-games/console/api-access/home.html`). Creating the profile and
enabling Login with Amazon is *not* enough — the page will read "No Security
Profile Attached" while every scope answers `invalid_scope`. Attaching is two
clicks and grants the scope immediately.

Do not look for `/settings/console/apiaccess` (404). The Vitals **API Explorer**
is separately at `/reporting/console/appstore/apiaccess`, and it is the fastest
way to see the exact request shape for your app.

### The 404-vs-400 route discriminator

Amazon does not document its route list, so probe it:

| Answer | Meaning |
|---|---|
| `404 NOT_FOUND` | the route is **real**; there is no data for this app |
| `400 "Unable to fetch the request scope for uri = ..."` | **no such route** |

That is how you establish the API's real surface — and the sales route has a
second pair: `400 "Report not found"` = real route, no data that month;
`400 "Unable to fetch the request scope"` = no such route.

### Installs are in the SALES report (an earlier "console-only" was wrong)

`/download/report/acquisition/<y>/<m>` does not exist (the scope 400). But
`GET /download/report/sales/<y>/<m>` answers 200 with a **5-minute presigned
S3 URL to a CSV zip**, and for a FREE app **every install is a `$0.00`
`Charge` row** with `Transaction Time` and `Country/Region Code` — a daily
series by country. Count only `Charge`; keep a histogram of transaction types
so a new type is never miscounted.

### The live build: read it from an EDIT, and never delete someone else's

No live-version route exists. Amazon seeds a new edit from what is live, so
`GET /v1/applications/{appId}/edits` → if none, `POST` one, read its `/apks`,
and DELETE ONLY THE EDIT YOU CREATED (with its ETag as `If-Match`). An edit
that already exists is somebody's in-flight submission: read it, report
"submission in flight", touch nothing. Two scopes, two APIs:
`adx_reporting::appstore:marketer` (vitals, sales) and
`appstore::apps:readwrite` (edits); a token for one is refused by the other.

### An empty answer is not a broken reader

A young app has no vitals: all metric sets answer 404 and the console's own App
Health page is equally blank. Report "authenticated; the store holds no vitals
for this app yet", never a zero and never a failure.

## Roku: no API, but it DELIVERS

Roku's dashboards are Looker; there is no analytics API and there will not be.
Looker **scheduled delivery** targets email, webhook, S3, SFTP. S3 means real
AWS (no custom-endpoint field, so R2 cannot stand in); a **webhook to a free
Worker + D1 drop box** costs nothing (`pulse/worker-example/`). Measured shape:
JSON with `scheduled_plan.title` and `attachment.data` = **base64 of a zip,
one CSV per dashboard tile** (tile names are the schema).

- **Store the body RAW; parse offline.** An ingest that guesses a schema fails
  silently on the one delivery that matters. Refuse (never truncate) >900 KB.
  Answer 404, not 403, to a bad token.
- **Ack (delete) only on `--apply`** — a dry run consumed the only copy once —
  and never ack a payload you could not parse.
- **Cloudflare 403s a bare `Python-urllib` UA**, which reads exactly like the
  token being refused. Send your own User-Agent on every request.
- **Three tile shapes**: dated series (date column in ANY case), tables
  (multi-row; crash logs are dated AND textual — keep both), single-row
  headlines. Record EMPTY tiles: forty empty device tiles = nothing crashed.
- Four dashboards, four schedules: keep reports apart by plan title, and
  MERGE days, headline tiles and versions across readings (a rolling window
  drops days that still happened; a crash-only delivery must not blank the
  install headline).
- Crash logs carry `App Version`: a version APPEARING proves it shipped (close
  the stale "declared" row with it); absence proves nothing.
- "Nothing waiting" is normal between runs AND looks like a deleted schedule —
  alarm on the age of the newest row you already HOLD (past ~4 days).

## The stores with no API at all

LG Content Store and Samsung Apps TV expose nothing. Keep them in a hand-edited
file (`ops/stores-manual.json`) with a `route` per row, and show them beside the
machine-read ones — a dashboard showing only the machine-readable half of the
estate quietly forgets the rest. **A read fact beats a declared one**: Amazon's
edit, Roku's field versions and the web's newest deploy run replace typed rows.

## Google Search Console and Cloud Monitoring

- **Search Console** (`webmasters.readonly`, the robot added as a Restricted
  user): `dataState: "final"` lags 2–3 days, so `through` = Google's newest
  finished day and compare 28 days to `through` vs the 28 before. A prior
  period Google never measured is NULL, not zero — no "+263 vs prior" against
  nothing. URL Inspection: 2,000/day per property; sample a date-seeded slice
  of the sitemap, 8 in parallel, call the share an ESTIMATE, and name the
  faults you can fix (redirect, noindex, Google choosing another canonical).
- **Cloud Monitoring** `serviceruntime.googleapis.com/api/request_count` gives
  a vendor's own count of your app's API calls (e.g. broadcasts started) with
  no client telemetry. It answers "requires billing" unless the request
  carries **`x-goog-user-project: <project with billing>`**. Grant the robot
  Monitoring Viewer + Service Usage Consumer on that project.

---

## Recording what you ruled out

Every entry above was found by an assumption that looked like a permissions
problem. When one is settled, write the trap down next to the reader — a
disproven hypothesis in a docstring is worth as much as the fix, because it
stops the next session re-walking it.

## See also

- `product-pulse-dashboard` — the page these feed
- `apple-app-store-cli-submission` — the submission side of the same APIs
- `architectural-decision-log` — log the route chosen and the ones rejected
