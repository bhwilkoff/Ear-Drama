# Evenings: rebuilding a network's night from period radio listings (2026-10-22)

The data behind the Radio tab's **Tonight in 19xx** (05-design-research §4;
rules R9 and R10; DECISIONS 058; CATALOG-CONTRACT §8). Every number below is
MEASURED with the command beside it on 2026-10-22 unless marked UNVERIFIED.
Requests were sequential, slow (2-5 s apart), with the User-Agent
`EarDrama/0.1 (+https://eardrama.org)`.

## Verdict

1. **The Washington Post's daily radio grid, read from JJ's Newspaper Radio
   Logs, is the schedule source.** It is the only listing found that prints one
   column per station and one row per quarter hour in Eastern time, and
   Washington's network stations stand for their networks (WRC = NBC, WJSV and
   later WTOP = CBS, both network-owned). One PDF per day, 1930-1959, with an
   OCR text layer `pdftotext -bbox` can place word by word.
2. **The catalog's own OTRR logs (`program_runs`) cannot measure coverage.**
   They list only series that have recordings (a survivor-biased schedule), so
   an evening built from them has no gaps by construction. They are used as an
   independent check on the times the grid gives.
3. **Coverage is low and lumpy** (numbers in §4): most network evenings have
   nothing that survives; a minority are rich. The floor is proposed from that
   distribution in §5.
4. `catalog/tools/build_evenings.py` builds an evening, measures coverage over
   a sample, and writes a `tonight.json` prototype; `catalog/tests/test_evenings.py`
   holds R9 and R10 with broken controls.

## 1. Sources: what can be read programmatically, and on what terms

| Source | Form of a day's evening | Coverage (MEASURED) | Access and terms |
|---|---|---|---|
| **JJ's Newspaper Radio Logs** (jjonz.us/RadioLogs) | One scanned page per paper per day as a PDF with a CVISION OCR layer: NYT, Washington Post, Chicago Daily Tribune, LA Times | Month index pages list **39,347 logs** for 1930-1959 (WaPo 9,913; NYT 10,184; CDT 9,139; LAT 10,111); about 355-366 per paper per year; 1933 and 1948 month pages use a different file name (`1933 _01Jan.htm`); 1960 under `logs_pages_months/1960/` | No `robots.txt` (404), no terms page; the notes page lists incomplete days only. The logs are page images of copyrighted papers: we keep **facts only** (station, time, program as printed) and link the page as the witness, never re-host it |
| **Chronicling America** via loc.gov JSON | Full-page OCR of a whole issue; the radio column must be found by keyword | The **Evening Star** (Washington, same stations) is in it to the 1960s: `q=WTOP&dates=1955/1963&fa=partof_title:evening star (washington, d.c.) 1854-1972` → 7,299 pages | Keyless JSON; loc.gov's published limit for the JSON API is **20 requests a minute, a one-hour block if exceeded**; robots `Crawl-Delay: 5`. The collection's rights page returned 403 to our client (its "no known copyright restrictions" statement is UNVERIFIED this session). OCR of the grid is poorer than JJ's (e.g. "BBBNews") |
| **Radio Guide** scans (worldradiohistory.com) | Weekly magazine; each day's listings print network and time ("NBC-Horlick's Lum & Abner, CBS-Lux Radio Theater"), Chicago edition in Central time | The master page links **612 issues**; one weekly PDF is ~8.7 MB, 48 pages, with a text layer (1938-01-15 measured) | `robots.txt` disallows only site furniture; terms not found (UNVERIFIED). Per-issue copyright needs a renewal check (03 §1.13). A weekly guide is a plan, not a day's witness, and 8.7 MB per week is heavy |
| **OTRR `program_runs`** (in `radio-catalog.sqlite`) | Network, weekdays, time, start/end per series run | 4,981 rows; CBS 1,600 (1,239 with day and time), NBC 1,263, NBC Red 265, NBC Blue 399 | Ours. **Survivor-biased**: a series with no recordings has no row, so it cannot show a gap |
| Shapiro, *Radio Network Prime Time Programming 1926-1967* | Month-by-month grids per network and night | — | Print; a reference to check against, not a feed |

How the four JJ papers print an evening (measured on 1947-10-16 and
1937-10-14, 1942-10-15, 1952-10-16, 1955-10-13):

- **Washington Post**: a grid. Header row of call letters (from 1952 with the
  network: "WMAL (ABC) WRC (NBC) WWDC (MBS) WTOP (CBS)"), dial positions under
  them, a gutter of quarter-hour labels (":00 :15 :30 :45" with the hour beside
  one of them), cells that repeat the name or print ditto marks. 1937 prints
  "Eastern Standard Time" in the header. 1955 sets the radio grid beside a TV
  grid and its labels are the poorest OCR of the sample.
- **New York Times**: a time-ordered list, "8-8:30 Suspense: 'Self Defense,'
  With Marsha Hunt WCBS", plus highlights; multi-column, Eastern time, network
  by flagship station (WCBS, WNBC, WJZ, WOR). A good second witness.
- **Chicago Daily Tribune**: station + program + network letter
  ("WBBM Suspense [C]"), **Central time** ("Programs are listed in central
  standard time"), heavy OCR noise ("WBBAISuspense").
- **LA Times**: Pacific time; network shows often at delayed hours.

## 2. The station stands for the network

The grid's header names stations. `DC_STATIONS` and `DIAL` in the tool map
them by date; a header that prints the network wins over the table.

| Station | Network | Dial (kc) |
|---|---|---|
| WRC | NBC (Red), NBC-owned throughout | 950, then 980 after the 1941 NARBA move |
| WMAL | NBC Blue, then Blue (1942), then ABC (1945) | 630 |
| WJSV → WTOP (1943) | CBS, CBS-owned | 1460, then 1500 |
| WOL | Mutual until about 1950 | 1310, then 1260 |
| WWDC | Mutual from about 1950 (1952 header: "WWDC (MBS)") | 1450, then 1260 |

The month edges of the WMAL, WOL and WWDC changes are UNVERIFIED (station
histories, not measured); WRC and WTOP, the two the measurements use, do not
change network in 1935-1955. An evening is therefore "CBS's evening as
Washington heard it on WTOP", and its witness names the paper, the station and
the page. A Washington station could delay or pre-empt a network program; the
grid records what WTOP aired, which is what we claim.

## 3. The builder (`catalog/tools/build_evenings.py`)

    python3 tools/build_evenings.py index --years 1935-1955
    python3 tools/build_evenings.py fetch --sample 320 --anniversaries 2026-10-21 --days 14
    python3 tools/build_evenings.py evening 1947-10-16 CBS
    python3 tools/build_evenings.py measure --sample 320 --anniversaries 2026-10-21 --days 14
    python3 tools/build_evenings.py report
    python3 tools/build_evenings.py tonight --today 2026-10-22 --previous live/tonight.json --out tonight.json

`EARDRAMA_CACHE`, `EARDRAMA_PROJECTION` and `EARDRAMA_REGISTRY` point a
worktree at the main checkout's cache and databases.

1. **Grid.** The header is the band holding three or more Washington call
   letters (or their dial numbers when the OCR mangles the letters: "WFIC",
   "1VM AL"); a lost column keeps its place so its programs are not read into a
   neighbor's. A Sunday page prints the day as two grids side by side, so a
   call letter seen twice in the header starts a second panel with its own
   gutter. Labels are the gutter tokens that read as `[h]:mm` (or, in the
   1950s, a bare `00`/`15`/`30`/`45` with the colon lost); the quarter
   between two labels is the one congruent with their minutes and nearest
   their spacing (a dropped label leaves a taller gap, not a lost hour), or
   the printed clock itself when both labels print their hour; the hour comes
   from the printed hours by majority; a printed clock that jumps back or
   ahead by more than two hours starts a new block; the grid is the longest
   block plus the blocks that continue its clock; the last block ends between
   10 PM and 3 AM, earlier blocks are placed before it, and a block whose
   clock restarts (the small-station lists below the grid) is not the grid.
   A cell of ditto marks or nothing continues the program above.
2. **Health.** An evening is *readable* only when its grid has at least 13 of
   the 16 prime-time quarter hours, at most 3 printed hours disagree with the
   rows, and the grid ends between 10:45 PM and 2 AM. Unreadable evenings are
   counted, never offered.
3. **Match (R9).** A slot's candidates are only the served episodes whose
   `air_date` is the evening's date, never `no_recommend` (contract §9.4), and
   not recorded as another network's broadcast. A series name must appear in
   the printed cell (whole for names under nine letters; in order, allowing
   OCR damage and the paper's short forms, for longer ones), read across up to
   three rows where the grid wrapped it. An `assert` at the point of use
   refuses any episode whose date is not the evening's. A matched recording's
   length absorbs a stray fragment the grid read inside its half hour. A name
   the OCR placed in two columns at the same hour stays with the column that
   reads it better; on a tie only a station of the episode's recorded network
   keeps it, else both are gaps (`refuse_bleed`).
4. **Coverage** = minutes of 7-11 PM Eastern whose slot plays a surviving
   episode of that night, over 240.
5. **Tonight (DECISIONS 058).** For each calendar date from yesterday, the
   same month and day in its best-covered year (either network) when that
   evening clears the floor; otherwise the best readable evening for that
   weekday. One evening per day, never stitched. Each slot carries its printed
   Eastern time (`et_start`), the replay instant (`utc_start`: the same
   Eastern wall clock today, `America/New_York`), and its witness. A day
   already in the published file keeps its value.

## 4. Coverage, measured

MEASURED 2026-10-22: `build_evenings.py fetch` then `measure --sample 320
--anniversaries 2026-10-21 --days 14` then `report`. The sample is 320 random
dates 1935-1955 (seed 1947) plus the 14 calendar dates Oct 21-Nov 3 in every
year 1935-1955, each for CBS and NBC: **1,180 network-evenings** from 575
Washington Post logs (15 dates have no WaPo log on JJ's).

**Parse yield.** 869 grids parsed; **586 readable** (50%). Not parsed: 96
with no station header the OCR could read, 57 with no CBS/NBC column found,
about 150 with too few time labels, 30 with no log. The readable share falls
after the war: unreadable parsed evenings are 2-11 a year in 1935-1941 but
23-42 a year in 1945-1948 and 1954-1955 (the postwar grids drop labels and
print hours the OCR misreads). The measurement therefore **under-samples the
late 1940s, the years with the most surviving recordings.** A second witness
for those years (the NYT list, or the Evening Star via loc.gov) is the next
step.

**Coverage over the 586 readable evenings** (share of 7-11 PM ET with a
surviving episode of that night):

| | n | zero | median | p75 | p90 | max | mean | >= 0.25 | >= 1/3 | >= 0.5 |
|---|---|---|---|---|---|---|---|---|---|---|
| all | 586 | 356 (61%) | 0 | 0.125 | 0.25 | 0.56 | 0.075 | 74 (13%) | 25 (4%) | 6 (1%) |
| CBS | 279 | 172 | 0 | 0.125 | 0.25 | 0.56 | 0.082 | 46 | 18 | 6 |
| NBC | 307 | 184 | 0 | 0.125 | 0.19 | 0.44 | 0.068 | 28 | 7 | 0 |
| 1935-37 | 133 | 118 | 0 | 0 | 0.125 | 0.31 | 0.019 | 5 | 0 | 0 |
| 1938-40 | 130 | 82 | 0 | 0.125 | 0.25 | 0.50 | 0.069 | 16 | 6 | 1 |
| 1941-43 | 116 | 70 | 0 | 0.125 | 0.25 | 0.50 | 0.072 | 13 | 4 | 1 |
| 1944-46 | 73 | 34 | 0.06 | 0.19 | 0.25 | 0.44 | 0.098 | 13 | 2 | 0 |
| 1947-49 | 86 | 31 | 0.125 | 0.19 | 0.375 | 0.56 | 0.137 | 19 | 11 | 4 |
| 1950-52 | 23 | 13 | 0 | 0.125 | 0.31 | 0.44 | 0.092 | 4 | 1 | 0 |
| 1953-55 | 25 | 8 | 0.125 | 0.19 | 0.25 | 0.375 | 0.112 | 4 | 1 | 0 |

Histogram (tenths): 0.0-0.1: 369, 0.1-0.2: 143, 0.2-0.3: 35, 0.3-0.4: 31,
0.4-0.5: 2, 0.5-0.6: 6, above: 0. By weekday, Sunday is richest (median
0.125, mean 0.139, 23 of 77 at >= 0.25) and Saturday poorest (mean 0.025,
2 of 91).

**Anniversaries.** For the nine calendar dates measured in ten or more
readable years, the best year's coverage is 0.25-0.44 (Oct 22 1941 CBS 0.25;
Oct 29 1952 NBC 0.44; Nov 1 1945 NBC 0.44; Nov 3 1938 CBS 0.38 ...). Floors
cleared: >= 0.25 by **9 of 9**; >= 1/3 by 6 of 9; >= 0.4 by 2 of 9; >= 0.5 by 0.

**Precision.** Each readable evening's matched slots against OTRR's logged
regular time for that series (`program_runs`, same network and weekday):
**203 agree, 63 differ, 71 have no OTRR time**. The commonest difference is
+15 minutes (22), then -15 (7) and +/-60 (11): the grid's row placement is
right about three times in four and otherwise usually one quarter late.
OTRR's own times have errors (it logs Abbott and Costello's 1943-47 show at
"10:00 AM"), so this is a floor on agreement. Network attribution was spot
checked, not measured: one case (1938-10-14, "Wonder Show" read into WRC's
column; Jack Haley's Wonder Show was CBS that season, UNVERIFIED) shows the
risk, which `refuse_bleed` reduces only when the name also appears in the
right column. Coverage is a **lower bound**: an OCR-damaged name that matches
nothing counts as a gap.

## 5. The floor

**Proposed: 0.25** (at least one hour of the four, 60 of 240 minutes, plays a
recording of that night). The median evening has nothing; a floor of 0.25
passes the top 13% of readable evenings and every one of the nine
anniversary dates measured in depth, so "same date, best year" is the normal
case and the weekday fallback the exception (1 of the 14 prototype days). At
1/3 a third of anniversary dates fall back; at 0.5 all of them do and the
fallback pool is six evenings in 586. Revisit when the postwar grids are read
(the richest years and the worst parsed), and record the number in DECISIONS
058 once the owner agrees.

## 6. The prototype `tonight.json`

`catalog/prototypes/tonight.json`, from
`tonight` (then `--start 2026-10-21 --days 14 --floor 0.25`): 14 days, 13
anniversaries (coverage 0.25-0.44) and one weekday fallback (2026-10-25, a
Sunday: CBS 1949-02-20, 0.56: Jack Benny, Amos 'n' Andy, Our Miss Brooks).
Shape:

    {"schemaVersion": 1, "zone": "America/New_York", "floor": 0.25,
     "window_et": ["19:00", "23:00"], "rule": "...",
     "days": {"2026-11-03": {"evening": "1949-11-03", "picked": "anniversary",
        "network": "CBS", "station": "WTOP", "coverage": 0.375,
        "witness": {"paper": "Washington Post", "station": "WTOP",
                    "network_from": "station table", "url": "https://www.jjonz.us/...pdf",
                    "via": "JJ's Newspaper Radio Logs (jjonz.us)", "printed_zone": "ET"},
        "slots": [{"et_start": "21:00", "et_end": "21:30", "length_min": 30,
                   "printed": "Suspense", "utc_start": "2026-11-04T02:00:00Z",
                   "episode": {"id": "suspense|1949-11-03", "...": "..."}},
                  {"et_start": "19:00", "...": "...", "gap": true, "known_series": "Beulah"}]}}}

`printed` is the newspaper's text as OCR'd: a fact, and ugly, so it is the
witness detail, never on-screen copy (AGENTS.md: only essential words). A
gap's `known_series` is set only when that text reads clearly as a catalog
series active that year, so the station card can say "*Beulah* aired here; no
recording of this night is known", else "a program aired here". A gap that
`refuse_bleed` emptied carries `refused`. Replay: `utc_start` is the printed
Eastern wall clock on the replay date in `America/New_York` (R10); a slot
after midnight belongs to the same night.

## 6a. Publishing (2026-10-22)

`catalog-publish.yml` builds `tonight.json` every run: it restores
`radiologs.tar.xz` from `radiologs-latest`, measures only the window's
anniversaries it has not measured (`measure --window --max-fetch 120`,
nearest day first, 3 s between PDFs), writes `tonight.json` merged onto the
published file, and keeps the grown cache. MEASURED on a copy of this
session's cache: a run whose window adds one new calendar date fetched 20
PDFs (one of 21 years had no log) of about 66 KB each, about 1.3 MB, in 87
s, and measured 40 network-evenings; a new month adds up to 21 month pages
the first time (kept as links in `log-urls.json`, not as pages). One JJ PDF
(1951-11-04) crashes poppler; it is recorded as `pdf unreadable`, not
retried. The floor is `FLOOR` in the tool, provisional. On the clean-only
web projection (gate closed) the 15-day window has 0 playable slots: every
surviving recording in it is unclaimed, so the web draws them as "Not in
the catalog" until the gate opens; with unclaimed rows the same window
plays 36.

## 7. Verified and unverified

- **Verified (MEASURED, commands above)**: JJ's index counts; the WaPo grid
  form in 1937, 1942, 1947, 1952, 1955; loc.gov's 20/min limit and the
  Evening Star's presence; Radio Guide's text layer; the yield, coverage and
  OTRR-agreement numbers; zero R9 violations in the prototype (every filled
  slot's episode id carries the evening's date);
  `python3 tests/test_evenings.py` 39/39 with the real page (37/37 without),
  its controls seen to fail (removing the R9 guard and the `no_recommend`
  filter fails 3 checks).
- **Unverified**: the month edges of the WMAL/WOL/WWDC network changes;
  Chronicling America's rights statement (403 to our client); JJ's and
  WorldRadioHistory's terms (none published); network attribution of single
  slots beyond the spot check; whether a Washington station delayed a network
  program on a given night (the evening claims what the station aired).
- **Not done**: a second witness (NYT) per slot; better reading of the
  postwar grids; the 1956-1959 logs; Mutual and ABC evenings.
