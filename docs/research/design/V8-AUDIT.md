# V8 visual audit (Round 3, 2026-11-20)

Owner's goal (2026-11-19): "The goal is to have the home view feel more cohesive and inviting from the
moment that you open the app." The audit looked at every Round 3 surface on every device it could reach,
against the binding design docs and the design skills (`artwork-presentation-design`,
`uniform-imagery-design`, `catalog-experience-design`, `mobile-first-density-design`,
`universal-feature-states`). All frames are muted door launches; nothing pressed Play. Frames are in
`img/v8/` (downscaled to 1400 px on the long side).

## Coverage

| Device | Build | Covered | Not covered, and why |
|---|---|---|---|
| Web, headless Chrome (muted, `?mute=1`) | worktree 1.0.150 | Home (evening, day, history), Record, series (picture, label, gallery fixtures), episode, person, play, finished ear drama, Stations, Search, Browse, the reader (all modes), studio and Takes, read room (reader, leader, screen), class page, casting board, review, TV pairing: 320-1440 px, light and dark (`web_fit_*`, `read_frames.mjs`, `T5=1`) | Now Playing frames (the gate passes but writes none) |
| Pixel 8a | 1.0.149 debug | Home, series (Gunsmoke, Lux, X Minus One), episode, person (portrait, label), Record, Library, finished drama (not listed), Your parts: light and dark | Read room, Now Playing (never press Play) |
| Google TV 10.0.0.55 | 1.0.149 debug | Home, series (Lux, Gunsmoke), episode, person, pairing screen | Read room screen with a live room |
| Open iPhone Duo (inner display) | 1.0.149 | Home (top and end, `APP_SCROLL_Y`), series (Lux, X Minus One), episode, person, Record; dark only | Outer display (off while open); light mode (no appearance door) |
| Apple TV Ben Bedroom | 1.0.149 | Home, series (Lux, Gunsmoke, Columbia Workshop), episode, person | Pairing screen with a live room |
| iPhone 12 | 1.0.149 | nothing: Screen Time "Time Limit" covers the app (`skip-iphone12-screen-time.png`); not tapped | everything, until the owner lifts the limit |
| iPad Pro 12.9 | n/a | nothing: locked (the developer disk image would not mount) | everything |
| Mac app | n/a | skipped: the owner may be at the Mac (no pointer or screen capture without them away) | everything |
| Android TV 10.0.0.139 | n/a | adb "unauthorized" | everything |

## Faults

| # | Platform | Screen | What is wrong, against which rule | Status | Frames |
|---|---|---|---|---|---|
| 1 | Web, iOS/Duo, tvOS, Android, Google TV (the shared label spec) | Home, On the air hero (label at tier L) | The evening's tick (r 35 to 47) struck through the rim's words: the N of "NBC · 1940s" on every platform. `artwork-presentation-design` §9: a tier shows only what reads; WEB-DESIGN §6 label constants. | **Fixed**: at L the tick starts at r 40, outside the rim's band (token `art.label.evening.r0` per tier; golden updated; JS, Swift, Kotlin) | `before-web-hero-label-tick.png`, `after-web-hero-label-tick.png`, `before-pixel-home-light.png`, `before-duo-home.png`, `before-atv-home.png` |
| 2 | Web, iOS/iPadOS/macOS, tvOS, Android, Google TV | Series head (kicker or facts), series rows, Apple and Android label rim | Every network in `series.networks`: "CBS · NBC · AFRS · NBC RED" over Lux, "CBS, NBC" over Gunsmoke (NBC only for rebroadcasts), "CBS · WCBS" over Columbia Workshop. Apple and Android also parsed `networks.first` for the rim, which CATALOG-CONTRACT §3.3 forbids. `catalog-experience-design` anti-pattern "raw network lists". | **Fixed**: the one primary network, `series.network`, everywhere (docs first: WEB-DESIGN §6.4d, iOS-DESIGN R11d, ANDROID-DESIGN R11d; tests on all three stacks, the web one seen to fail) | `before-web-series-networks-375.png`, `after-web-series-network-375.png`, `before-pixel-series-lux-networks.png`, `before-duo-series-lux.png`, `before-atv-series-cw-networks.png` |
| 3 | Google TV | Series page with a wide hero | Lux's 2:1 hero filled the first screen; the name and the buttons sat below it. `ten-foot-detail-design`; `artwork-presentation-design` §3 (the cap binds, the width shrinks). | **Fixed**: on a TV a plate is at most 30% of the screen's height (`ItemLead.window(plateMax)`, test) | `before-gtv-series-lux-plate.png` |
| 4 | Google TV | Episode page | Play's first focus scrolled the head's top (the show link, the label's rim) under the bar: Play was its own list item, outside `revealWhole()`. ANDROID-DESIGN TV focus rule. | **Fixed**: the button row joins the head's item, as on the series page | `before-gtv-episode-focus.png` |
| 5 | iOS (Duo, iPhone, iPad) | Home, Continue | Continue wore the List's small gray section title while every other Home section wears `SectionHead`: two heading styles on one first screen. `mobile-first-density-design` (six levels), R3a §4.1 (one Home). | **Fixed**: `SectionHead` on iOS; the Mac keeps its wide section | `before-duo-home.png` |
| 6 | iOS (Duo, iPhone, iPad) | Home, that night's tiles | Tiles in one row ended at two heights (a third facts line), and "All 11 shows that night" sat in a tinted box of its own. `catalog-experience-design` rule 11 (a row shares its slot tracks); density rule 1 (no tinted boxes). | **Fixed**: the Mac's row-fill rule now holds on iOS; the link is a clear row | `before-duo-home-end.png` |
| 7 | iOS/iPadOS, tvOS | Series and episode heads (own-span strip) | A show of three or four years drew three slabs a third of the board wide (X Minus One), where the web's strip reads as a strip. | **Fixed**: the own-span axis is at least twelve years (`Grammar.ownSpanAxis`, test seen to fail; iOS-DESIGN R11g) | `before-duo-series-x1-strip.png`, `before-atv-episode-strip.png` |
| 8 | All | Episode event line | "Season 1954-55" in the head. `catalog-experience-design` rule 6 says the season leaves the head; WEB-DESIGN §6.4d (binding, D3-3) lists it. | **Open**: the binding doc wins until the rule is changed; left as built | `before-duo-series-x1-strip.png` (episode), `before-atv-episode-strip.png` |
| 9 | All (data plane) | Stations, Home dial, tvOS season rows, Home day chart | Upload residue in episode titles: "(First Song - I Hate To Say Goodbye To The Prairie) #84 on list", "Earned Reward (Repeat of # 122)", "CBS World News Today, September 24, 1944" under the show of that name, "Lux Radio Theater 'Mr. Deeds Goes to Town' - Feb 1 1936". AGENTS.md: raw upload text never shows; a title may be composed from the record's data. | **Open**: a `catalog/tools/display_text.py` batch (drop "#NN on list" and "Repeat of # N" tags; a title that repeats the show's name and date becomes the composed date title), with the dry run and a publish, for the main thread | `open-web-stations-raw-titles.png` |
| 10 | Web 1440 | Home dial | Station show names truncate ("Columbia Work…", "The Fred Allen …") with room to wrap at 1440. | Open (minor) | `before-web-home-1440.png` |
| 11 | iOS (Duo) | Record | "Plays", its menus and count stand about 30 pt further in than "Record" and Today's scene above them. | Open (minor) | `before-duo-home.png` set; Duo Record frame not saved |

## Known faults rechecked

- Google TV Home hero size and focus scroll (fixed in code at tick 15): **fixed on the device**: the
  hero fills its board and Listen live takes focus with the whole hero on screen.
- Station dial letters: drawn on every platform (web, Pixel, Google TV, Duo, Apple TV).
- Person label arc: drawn on web, Android (Pixel) and Apple.
- The open Duo's floating tab bar over the last rows: at Home's end the last control ("All 11 shows that
  night") stands just above the bar and is reachable (`before-duo-home-end.png`); not a fault.
- Apple class review and Takes foot: **not seen** (no read room was opened on an Apple device in this
  audit). The web's casting board, review and Takes sheet are in `web-casting-board-1440.png` and
  `web-takes-375.png`.
- Raw upload titles: still present (fault 9).

## After (1.0.151, frames read)

- Web: `after-web-hero-label-tick.png` (the tick clears "NBC · 1940s"), `after-web-series-network-375.png`
  ("CBS" alone). `web_fit_home`, `web_fit_pages --only series`, `web_fit_label` pass.
- Google TV (debug 1.0.151 installed): `after-gtv-series-lux-plate.png` (hero capped, "DRAMA · CBS", the
  name and Follow on the first screen), `after-gtv-episode-focus.png` (Play focused, the whole head shown).
- Pixel (debug 1.0.151): `after-pixel-series-lux-network.png` ("DRAMA · CBS"), `after-pixel-home-light.png`.
- Open Duo (Debug 1.0.151 built and installed from this tree): `after-duo-home.png` (Continue wears the Home
  heading), `after-duo-home-end.png` (that night's tiles one height, the link a clear row),
  `after-duo-series-x1-strip.png` (three seasons on a twelve-year axis). `after-duo-series-lux.png` shows
  "DRAMA" alone: this local build carried the main checkout's October 22 seed, which predates the
  `series.network` column, so the honest blank shows; the published catalog carries the column (912
  series), and the Apple path is held by `SeriesHeadNetworkTests` and the fixture in `CatalogQueryTests`.
- Apple TV: not re-shot (tvOS generic build and tests only).

## Seen on the way (harness, not fixed)

- `tools/web_fit_cast.py` fails at every width: it reloads a production with no takes, which Decision 079
  deletes on load ("This production is not in this browser"). The gate predates 079.
- `tools/web_fit_library.py` fails a different set of widths on every run (20 of 64 frames, then others):
  an intermittent harness is a harness defect; its ready wait needs instrumenting.
- `tools/web_fit_reader.py` and the cast gate read `catalog/out` and fail in a worktree without it; pass
  `--data https://eardrama.org/data/` (the reader then passes).
- Google TV needs about 45 s after a cold start before Home draws (12 s showed the spinner only).
