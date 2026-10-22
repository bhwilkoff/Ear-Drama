# Pulse port (2026-09-30)

Source material for docs/PRODUCT-PULSE.md and path stage 06.

## Report: AW Pulse is ported into the template (nothing committed)

All pulse tests pass: 103 Python, 53 chart and 39 render cases. Every file I own is generic. A leak scan of those files for Archive Watch names, the App Store id, the vendor number, the Roku channel id, the owner's handles and "Mountain" came back empty. Nothing outside my ownership was edited; `check_workflow_gates.py` (read-only run) reports "no reporting workflow fails on its findings".

### One deviation from the brief
The config file is `ops/pulse.config.example.json`, which the adopter copies to `ops/pulse.config.json`. I did not use `ops/pulse.example.json` because `ops/pulse.json` is the collector's output, and the two names would be confused. Identity the template already knows (App Store id, Android package, repo, product name, site, mention terms, Play bucket) falls back to `tools/app_config.py`, and placeholder values there count as blank. Credentials come from the environment only. The collector copies the identity into the reading as an `app` block, so the page hard-codes nothing.

### Files added or changed
- **`tools/pulse_collect.py`** (2,634 lines): a full port of the AW 3,101-line collector, config-driven, 39 readers. It adds a third reader state, "not configured" (`off: true`), separate from "could not read".
- **`tools/test_pulse_collect.py`**: 103 cases, with no network use. The drop box is a local HTTP server that 403s the default Python user agent, and `main()` runs against stubbed sources.
- **`tools/test_pulse_charts.mjs`**: the 31 AW cases plus new ones for the shared-scale sparkline, run chart, calendar heat, dot plot, pareto and dated time chart.
- **`tools/test_pulse_render.mjs`** (new): runs the real `pulse.js` against the fixture in a DOM shim, or against any reading passed as an argument.
- **`tools/pulse_make_fixture.py`** and **`pulse/fixture.json`** (new): a seeded synthetic reading. It includes a dark reader, an unconfigured reader, a stale section, a null column, a fix in review and an unreplied 2★ review.
- **`tools/pulse_play_bucket_probe.py`** (new): lists the Play reports bucket by object update time, with the bucket name redacted.
- **`pulse/pulse.js`**: ported from AW's 2,541 lines to 2,445.
  - Identity is read from the reading. `?fixture` renders the synthetic reading.
  - AW's Watch Together, feeds and web-titles panels are replaced by a generic server-tally panel and a Cloud API usage panel.
  - Each part of the page draws inside its own error guard.
- **`pulse/charts.js`**: the AW kit with a generic header comment.
- **`pulse/pulse.css`**: all colours are tokens, with a light theme added. AW's page was dark only.
- **`pulse/index.html`**: generic; the product name comes from the reading.
- **`pulse/worker-example/`** (new, optional): a Cloudflare Worker (`index.js`), a D1 `schema.sql` and `wrangler.example.toml`. It provides the beacon, `/views`, `/tally-daily`, `/ingest/<vendor>` and `/drops`. The AW repo never committed a schema for these tables, so one was written.
- **`ops/pulse.config.example.json`** (new).
- **`ops/stores-manual.json`** and **`ops/fixed-in.json`**: both still contained Archive Watch data. They are now empty, with generic example rows.
- **`.github/workflows/pulse.yml`**: still dormant. Both crons and a store-only re-read after releases (`workflow_run`) are written but commented out. It also adds a dispatch input for running named readers only, `set -o pipefail`, a summary step that survives a refused reading, and every secret the collector reads.
- **Both skills** (`product-pulse-dashboard`, `store-metrics-pipelines`): updated with the lessons below. Frontmatter is valid YAML; the descriptions are 520 and 432 characters.

### Verification
- **No config, no credentials:** 35 readers print "not configured" with the config key to set. `manual_stores`, `workflows`, `distribution` and `asks` answer. No zeros anywhere.
- **Identity configured, no credentials:** 29 of 37 configured readers are dark, each with its reason. `--apply` then refused to write.
- **Fleet auditor:** the first run exposed a false zero. The auditor exits 0 after printing "nothing audited", and the reader reported that as "0 findings". It now requires "Checked N workflows" with N above 0.
- **Negative controls:** each of 14 rules was broken and its test confirmed to fail: the Mac codes, `HEALTH_OWNS`, the dry-run ack, the degraded guard, the vendor filter, unconfigured-is-not-dark, audited-nothing, run flags leaking, the user agent, the shared scale, the grey gap, code-versus-data errors, the no-API sentence and Roku's missing column.
- **Headless Chrome against `?fixture`:**
  - At 1280px the Overview shows 11 Needs attention items (live ANR, the unreplied 2★, Roku crashes 2.6% against 2%, a page Google cannot index, a fix in review, a failed workflow) and 6 Going well items.
  - The last-7-days list, estate stack, store rows and trend panels all render; the crash drawer opens from its hash route with every fact.
  - At 390px the page measures exactly 390 wide. Only the tab strip overflows, and it scrolls sideways by design. The first 390px screenshot looked clipped, but that was headless Chrome's minimum window width, not the layout.

### Lessons embodied (with AW sources)
1. **A reader that cannot read says so, never a zero** (Decision 108). Every reader is isolated; failures are recorded in `sources` and shown on the page.
2. **Not configured is a third state** (new in the template). It is excluded from the degraded guard, because config is the same on every machine and credentials are not.
3. **Refuse `--apply` when a third or more of the readers are dark** (a6be38509, Decision 123). A local run once put CI's pre-fix reading back and macOS vanished. In the port, only configured readers that ran this time are counted.
4. **`HEALTH_OWNS` must cover every health key, with a test** (Decision 123). Three sections were silently deleted by a run without their credentials.
5. **Record unknown Apple product codes** (ae3fac8b3). Mac codes are a separate family (F1, FI1), and macOS read zero for weeks. Skipped codes are kept with their units.
6. **Apple's sales report is vendor-wide; filter by Apple Identifier.** Another title's 15 units were once counted as ours.
7. **Staleness comes from the object's update time, not the newest row** (f6bdb78ca, PULSE-ANALYTICS §9). The collector now records the install file's write time, and the probe lists the bucket.
8. **Alarm past the measured lags** (05b81eba9). Android installs alarm at 14 days and acquisitions at 8; a 3-day default flagged every normal day as stale.
9. **Amazon installs are $0 `Charge` rows in the sales report** (8ac0806a7, §3a). The two different 400 errors distinguish "no data yet" from "no such route".
10. **Amazon's live build is readable only through an edit, and you never delete someone else's edit** (e947ce45f, Decision 123). An existing edit is an in-flight submission.
11. **Roku delivers its reports to a webhook drop box** (670be000e, f941b7e45, §3b/§7/§8).
    - The body is stored raw, oversized payloads are refused, and a bad token gets a 404.
    - Deliveries are acked only on `--apply`; a dry run once consumed the only copy.
    - An unreadable payload is never acked, since it is the only evidence.
    - Cloudflare 403s the default Python user agent, which looks exactly like a token failure.
    - Days, headline tiles and versions merge across readings. A version appearing in the crash logs proves it shipped. A quiet feed alarms after 4 days.
12. **A missing column is null, never zero** (08ad533f5). Roku once drew 0 installs for a platform with 112.
13. **Search Console and Cloud Monitoring readers** (f290a51a4, 53b92c7de, Decision 142, §11). Monitoring reads need the `x-goog-user-project` header or they fail with "requires billing". No comparison is made against a prior period Google never measured.
14. **Privacy: count from what servers and vendors already see** (Decision 142). A tally is `day | kind | count`, and visits and route views are never summed (f4d9c128c).
15. **Chart forms** (d05be5ccd, 51d1be20d): run chart, calendar heat, dot plot, pareto, dated time chart, and sparklines on a shared scale. There is one `VIEWS` list (04a455208) and one `RULES` table for Needs attention and Going well. The page carries look rules 7–13 from AW `docs/PULSE.md`; code comments cite them by number.
16. **A code error must not look like a data failure** (PULSE-ANALYTICS §10). AW still had this bug: its fetch `.catch` reported render errors as "Could not load the readings". In the port each section draws separately, and a throw is reported as "a bug in pulse.js, not a data problem".
17. **The workflow is a reporter that never fails on what it reads** (Decision 107). Crons run 4–5 hours late (b0ca09f8d), and a release triggers a store-only re-read.
18. **A crash with a fix in hand asks to be shipped** (978aaa516). It is judged by Android versionCode only.
19. **Also fixed in the port:** an AW bug where `_apply`/`_force` leaked into `ops/pulse.json` (visible in the live reading), and `--only play_stores` dropping the Apple and hand-declared store rows.

### Skipped as app-specific
- **Film and catalog readers** (`catalog`, `web_titles`, the catalog-index title lookup): Archive Watch's film catalog.
- **Watch Together and feeds** (`together_rooms`, `feeds_usage`): generalized into `counter_tallies`.
- **YouTube usage** (`youtube_usage`): generalized into `cloud_api_usage`, with event names and per-method units coming from config.
- **Worker code:** Xtream, MCP, rooms and live were skipped. The AW worker's `titleOf`, route shapes and hourly room sweep are not in the example.
- **Owner-step history:** AW's key IDs, grants and vendor-number history; the principles are kept.
- **Not done:** the service-worker bypass test (the template has no Pulse service worker) and AW's hand-typed Amazon units row, which AW itself removed.

### How AW Pulse was developed
- **2026-09-09, first build (8711f3d8c, Decision 108):** 23 readers.
  - The first CI run found three defects (520d1e45e): an f-string that broke Python 3.11, our own Mastodon posts counted as mentions, and a YouTube 403 that was a deliberate scope choice.
  - Charts and the binding look rules arrived the same day (9dfa4eb53), then drill-downs (e5e5d93df) and merge-not-clobber for partial runs.
  - Next came the second Sales-and-Reports key, fixed-in.json (978aaa516), and per-platform sections with seven chart forms plus the web counter (d05be5ccd).
  - "Play export dead" was concluded that day (0602f473c) and later disproved. Amazon went from "no API" to one mapping away (f5197c9fd, Decision 111).
- **2026-09-14, analytics push (PULSE-ANALYTICS.md, Decision 123):**
  - Fire TV installs from the sales report (8ac0806a7).
  - The $0 drop box (670be000e) and Roku live end to end, including the dry run that consumed its own delivery (f941b7e45).
  - "Play installs were never broken" (f6bdb78ca) and the Mac product-code fix (ae3fac8b3).
  - Seven views, one per audience (04a455208); the degraded-run guard (a6be38509); no-reading-is-written-not-drawn (08ad533f5); a copy and accuracy sweep (0a69a33b0); Roku versions read from crash logs (e873065b9).
- **2026-09-15:** cron moved earlier for the measured 4–5 hour lag (b0ca09f8d).
- **2026-09-25:**
  - Search Console, Watch Together and YouTube readers, plus re-reads after releases (f290a51a4, Decision 142).
  - The redesign into Needs attention / Going well, the RULES table and the single drawer (51d1be20d).
  - Search indexing (53b92c7de) and read-never-typed store rows (c7e965d03).
  - Lags retuned to measured values and Roku crashes fixed (05b81eba9).
- **2026-09-27:** feeds and MCP tallies (0b00c6ccb).
