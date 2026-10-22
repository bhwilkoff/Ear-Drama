# Three palette directions for Ear Drama

October 22, 2026. I want Ear Drama to have a look of its own that still sits beside Archive Watch as a sibling, and Decision 060 left the brand palette open until it could be chosen from rendered screens rather than from a list of hex values. So this folder holds three directions, each a brand palette with its own set of eight genre hues, drawn on the same four screens in light and dark. Open `index.html` in a browser to compare them; the PNGs in `shots/` are the same page rendered by headless Chrome, and every number below comes from `measure/palette_check.py` reading `measure/directions.json`. The owner picks; nothing here touches `design-tokens.json` or any platform.

## What we took from Human Shaped

The humanshaped.org palette went through three rounds before Ben chose forest and thistle on October 6, and the way it was chosen matters more for Ear Drama than the colors themselves. Five lessons carried over.

1. **Choose from the subject.** The anti-patterns research (`humanshaped-site/research/notes/ai-design-anti-patterns.md`) found that AI-made design looks the same because a default nobody chose stands in for a decision. Every direction here starts from a physical thing a 1940s listener saw (a studio lamp, a tuning eye, a cast-resin cabinet), and the idea paragraph names its source.
2. **Check the pairing against real brands, not the single color.** Human Shaped found that every bright single color already belonged to someone, so it checked pairings against 3,465 Simple Icons colors. The script does the same against the current Simple Icons set and names the nearest audio brand for each chrome color, because the neighbors that matter for a radio app are iHeartRadio, Audible, Pocket Casts, and Spotify.
3. **Stay out of the two tasteful defaults.** A cream ground with a clay accent (the Claude look) and a near-black ground with one acid accent are both named as AI tells. Every ground here is white or a near-neutral black (OKLCH chroma at most 0.0072), and the script measures each chrome color against Claude's clay `#D97757`.
4. **Keep grounds near neutral and check APCA as well as WCAG.** On October 9 Ben found the green dark ground clashed with thistle even though every pair passed AA, and the fix was a green-black ground and muted text raised to APCA Lc 72. The first run of this script found the same trap in all three dark modes (muted text at Lc 52 to 58), so dark muted text was raised to Lc 68 to 73 before anything was drawn.
5. **A colored ground is never under small text, and color never carries meaning alone.** Thistle is a fill on humanshaped.org, never a paragraph ground. Here the genre hue is a short mark beside the genre's name, never a card edge stripe (anti-pattern D6) and never text, and the name is always there in words.

## How the genre hues were made

The owner chose a new hue set (Decision 060): Ear Drama's genres must not reuse Archive Watch's eight hues (`#FF5C35`, `#2D5BFF`, `#7C5BBA`, `#C9A66B`, `#FF4D8D`, `#8A8F98`, `#3FA796`, `#E8A317`, read from Archive Watch's `css/whats-new.css` and `Discover_macOS.swift`) with new meanings. Every hue around the wheel is near one of those eight, so distance has to come from lightness and chroma as well as hue. I placed each genre's hue family by hand in OKLCH (the brand color's own hue is left empty in each set), and a small search then nudged each one within a narrow window until every check below held, in both modes. The checks are these:

- **Marks at 3:1** (WCAG 1.4.11) against background, surface, and surfaceAlt, with a light variant for light mode and a dark variant for dark mode.
- **CIEDE2000 of at least about 20** between any two genres in normal vision.
- **Color-blind separation**, measured as CIEDE2000 under the Machado, Oliveira and Fernandes (2009) simulation at full severity for protanopia, deuteranopia, and tritanopia.
- **CIEDE2000 of at least 12 from every Archive Watch genre hue**, in both variants.
- **CIEDE2000 of at least 10 from the direction's own chrome and status colors**, so a genre never reads as a button or an error.

Eight hues cannot all stay 20 apart for a viewer with deuteranopia; the best sets here hold 8 to 11, and the worst pair is listed below. That is why the genre's name always sits beside its mark.

## On Air

A studio's red light meant the microphone was live: a WEEI studio photograph in the Digital Commonwealth collection shows a sign that silence is required while the red light is on, and Australia's National Film and Sound Archive holds a 1940 lightbox lit so no one would interrupt a session. Red is kept for the one thing that is live (Play, the progress line, the playing episode's lamp), and the blue of 1930s mirrored-glass sets carries the links, the focus ring, and the selected tab.

| Token | Light | Dark |
|---|---|---|
| primary | `#B0152F` | `#E3384B` |
| onPrimary | `#FFFFFF` | `#120708` |
| secondary | `#0B6E99` | `#5AB4D6` |
| onSecondary | `#FFFFFF` | `#06141B` |
| link, focus | `#0B6E99` | `#6CC0E0` |
| background | `#FFFFFF` | `#0F0F11` |
| surface | `#F4F4F5` | `#19191C` |
| surfaceAlt | `#E8E8EB` | `#232327` |
| text | `#131316` | `#F2F2F4` |
| textMuted | `#5C5C66` | `#C4C4CC` |
| border | `#D8D8DD` | `#34343A` |
| success | `#1D7A4A` | `#5CC593` |
| warning | `#8A5300` | `#E8B04B` |
| error | `#C2410C` | `#FF9466` |
| errorSurface | `#FDEEE8` | `#3A1F16` |

| Genre | Light | Dark |
|---|---|---|
| Drama and anthology | `#B42575` | `#FF91C3` |
| Mystery and crime | `#3753A2` | `#8DACFA` |
| Science fiction and fantasy | `#03838C` | `#16E3F2` |
| Western | `#A06841` | `#D97E37` |
| Comedy and variety | `#8D8300` | `#E2D32B` |
| News and wartime | `#44420E` | `#CECEC0` |
| Documentary and education | `#217500` | `#81CB70` |
| Serials and soaps | `#5D0087` | `#AE6DDC` |

The icon is the white ring microphone on tally red, and the dark icon is a red microphone on the studio black. The cost is in the brand check. Research doc 09 proposed `#C8102E`, which the script finds 1.0 from iHeartRadio's `#C6002B`, close enough to be the same color, and even this deeper red is only 4.5 away; in dark mode the red is 7.8 from Pocket Casts. Red is the color radio apps already use. A red bright enough to work in dark mode also cannot carry white text, so the dark Play button takes near-black type, which passes WCAG at 4.66:1 but reads at only APCA Lc 36.

## Tuning Eye

RCA's 6E5 tuning indicator, introduced in 1935 (sources differ on 1935 or the 1936 line), glowed green behind the dial, and the gap in its eye narrowed as a station came in; Bakelite cabinets of the same years were brown or black because the wood-flour filler that made them strong limited them to dark colors (V&A, FADA model 115). Green means tuned in (Play, progress, the selected tab, links, and focus), and walnut brown is the microphone mark.

| Token | Light | Dark |
|---|---|---|
| primary | `#0F6B55` | `#56D6A8` |
| onPrimary | `#FFFFFF` | `#06120D` |
| secondary | `#5B3A29` | `#A88B76` |
| onSecondary | `#FFFFFF` | `#160C06` |
| link, focus | `#0F6B55` | `#6EDDB4` |
| background | `#FFFFFF` | `#0D100F` |
| surface | `#F3F5F4` | `#161A18` |
| surfaceAlt | `#E6EAE8` | `#202522` |
| text | `#111614` | `#E9EEEB` |
| textMuted | `#56605B` | `#C1CAC5` |
| border | `#D5DBD8` | `#2F3632` |
| success | `#3B6E14` | `#A6D46A` |
| warning | `#8A5300` | `#E8B04B` |
| error | `#B42318` | `#FF8A80` |
| errorSurface | `#FDECEA` | `#3A1D1B` |

| Genre | Light | Dark |
|---|---|---|
| Drama and anthology | `#960023` | `#CE3D4A` |
| Mystery and crime | `#1336A4` | `#5F88E8` |
| Science fiction and fantasy | `#B14CB2` | `#DC8DDB` |
| Western | `#9B603D` | `#F78D4D` |
| Comedy and variety | `#998100` | `#F4D025` |
| News and wartime | `#53574A` | `#A3B37D` |
| Documentary and education | `#116880` | `#55D6FF` |
| Serials and soaps | `#B66F7E` | `#FCC8D1` |

The icon is a white microphone on tuning green, and the dark icon is a phosphor microphone on near-black. This direction has the strongest dark mode (Play reads at APCA Lc 70) and the best color-blind separation in light mode (11.1). It is far from every audio brand in light mode (Spotify is 36.9 away), but the phosphor green is 12.8 from Spotify in dark mode, and the light green is only 10.3 from Human Shaped's forest, which reads as family or as a borrowed look depending on what we want. Green also took the success color's place, so success moved to an olive `#3B6E14`. Its dark genre set is the least even: deuteranopia brings science fiction and documentary to 6.7, and its dark walnut was moved away from Claude's clay (it measured 9.8 before the change, 15.0 after).

## Catalin

Catalin was cast without filler, so late-1930s sets came in colors Bakelite could not reach, and collectors report that red, black, and maroon held their color while the lighter shades yellowed toward what is now called butterscotch (Collectors Weekly). Oxblood leads in light mode and butterscotch in dark, the pairing of a 1939 DeWald set in butterscotch with oxblood trim, the way thistle took over from forest in Human Shaped's dark mode.

| Token | Light | Dark |
|---|---|---|
| primary | `#7A1F2B` | `#E2A13B` |
| onPrimary | `#FFFFFF` | `#1A1206` |
| secondary | `#B7791F` | `#D06470` |
| onSecondary | `#1A1206` | `#120607` |
| link, focus | `#7A1F2B` | `#EBB45A` |
| background | `#FFFFFF` | `#110E0D` |
| surface | `#F5F4F3` | `#1B1716` |
| surfaceAlt | `#EAE7E5` | `#26201F` |
| text | `#17120F` | `#F1ECE9` |
| textMuted | `#615955` | `#CBC1BC` |
| border | `#DCD7D4` | `#3A3230` |
| success | `#1E7A4F` | `#5CC593` |
| warning | `#8A4B00` | `#F2C57A` |
| error | `#C0261A` | `#FF8A80` |
| errorSurface | `#FDECEA` | `#3A1D1B` |

| Genre | Light | Dark |
|---|---|---|
| Drama and anthology | `#CA2F7C` | `#F8A0C2` |
| Mystery and crime | `#0353AD` | `#70ABFE` |
| Science fiction and fantasy | `#058DA1` | `#43DEFA` |
| Western | `#AB5D47` | `#CC8773` |
| Comedy and variety | `#8F8400` | `#E1D32B` |
| News and wartime | `#3C4333` | `#C5CEB9` |
| Documentary and education | `#206F05` | `#72C660` |
| Serials and soaps | `#64266C` | `#C269CE` |

The icon is a butterscotch microphone on oxblood, and the dark icon is the same microphone on onyx. Oxblood is the most distinctive color in this set (its nearest audio brand, iHeartRadio, is 15.1 away), and the light butterscotch is the aged tone `#B7791F` so that it passes 3:1 as a mark; it never carries text. The cost is dark mode: butterscotch is 6.4 from Audible's orange, an audiobook app the same people may use. Warm red and warm yellow are also one step from the cream and clay Human Shaped warns about, which holds only while the grounds stay neutral (surface chroma 0.0017 in light).

## The measured summary

Every chrome pair passes in both modes in all three directions: 120 checks (20 text and mark pairs per mode), plus 48 genre marks against three grounds each, with no failures. The token test's own pairs (`tools/test_design_tokens.mjs`) are a subset of these. The lowest text pairs are On Air's light error on its banner (4.58:1) and its dark Play button (4.66:1, APCA Lc 36). The lowest genre marks sit just over 3:1 on surfaceAlt in light mode (3.11 to 3.19: comedy in every direction, and Tuning Eye's serials).

Minimum CIEDE2000 between any two genres, and from the nearest Archive Watch hue and the nearest chrome or status color:

| Direction | Mode | Normal | Protan | Deutan | Tritan | From Archive Watch | From own chrome |
|---|---|---|---|---|---|---|---|
| On Air | light | 21.6 | 8.4 | 8.4 | 10.2 | 12.1 | 11.3 |
| On Air | dark | 21.8 | 10.4 | 9.7 | 11.2 | 12.1 | 10.3 |
| Tuning Eye | light | 19.5 | 11.1 | 11.1 | 7.9 | 12.0 | 10.8 |
| Tuning Eye | dark | 20.7 | 7.5 | 6.7 | 7.5 | 12.5 | 11.6 |
| Catalin | light | 22.0 | 10.9 | 10.2 | 7.7 | 12.0 | 11.5 |
| Catalin | dark | 20.3 | 9.5 | 8.2 | 9.7 | 13.8 | 10.2 |

Nearest brands for each primary (CIEDE2000; under 10 is close, under 3 is the same color to most eyes):

| Direction | Light primary | Nearest audio brand | Dark primary | Nearest audio brand |
|---|---|---|---|---|
| On Air | `#B0152F` | iHeartRadio 4.5 | `#E3384B` | Pocket Casts 7.8 |
| Tuning Eye | `#0F6B55` | Castro 26.7 | `#56D6A8` | Spotify 12.8 |
| Catalin | `#7A1F2B` | iHeartRadio 15.1 | `#E2A13B` | Audible 6.4 |

## My recommendation

I would choose **Catalin**, and the reason is the icon. A dark oxblood ground with a butterscotch ring microphone is the one combination here that no audio app on a home screen already wears, it holds the brand check best in light mode, and its dark mode is warm rather than cold, which suits a player built for bedtime and the car. I would accept its one real cost, the dark butterscotch's nearness to Audible, because it shows up only as a button fill inside the app and never as the icon ground. If the owner would rather Ear Drama sit visibly beside Human Shaped, Tuning Eye is the honest second, with the best dark-mode readability and a weaker genre set in dark. I would not choose On Air, even though it tells the clearest radio story, because red is already iHeartRadio's and Pocket Casts' color and a dark-mode red button cannot carry readable text.

## What was not verified

- The WEEI photograph and the NFSA lightbox were read through search summaries only; both pages refused an automated reader. The 6E5, Bakelite, and Catalin claims were read on the pages themselves (Wikipedia's magic eye article, the V&A's FADA record, and Collectors Weekly), and the DeWald pairing comes from a dealer listing, not an archive.
- The mirrored-glass blue in On Air comes from the SFO Museum radio gallery's description, read through a search summary.
- Color-blind numbers are a simulation, not a test with people.
- The screens were rendered in headless Chrome only; nothing was drawn on a phone, a TV, or with the system faces on Apple and Android, where Public Sans gives way to SF Pro and Roboto.

## Sources

- WEEI studio photograph, Digital Commonwealth: https://www.digitalcommonwealth.org/search/commonwealth-oai:ff36nv21p
- Recording studio "on air" lightbox, NFSA: https://www.nfsa.gov.au/collection/curated/asset/103027-recording-studio-air-lightbox
- 1930s mirrored-glass radios, SFO Museum: https://www.sfomuseum.org/exhibitions/radio/gallery
- Magic eye tube: https://en.wikipedia.org/wiki/Magic_eye_tube and RCA 6E5: https://www.industrialalchemy.org/articleview.php?item=1065
- FADA model 115, V&A (Bakelite fillers, Catalin cast): https://collections.vam.ac.uk/item/O369377/fada-model-115-radio-fada-radio/
- Catalin radios, Collectors Weekly: https://www.collectorsweekly.com/stories/236836-catalin-radios-of-the-1930s-and-40s
- DeWald Aria, butterscotch with oxblood trim: https://radio-guy.com/product/aria-catalin-radio-yellow-oxblood/
- Brand colors, Simple Icons: https://github.com/simple-icons/simple-icons
- Machado, Oliveira and Fernandes, "A Physiologically-based Model for Simulation of Color Vision Deficiency" (2009)

## Rerunning the numbers

From `measure/`, fetch the Simple Icons colors once (`mkdir -p si && curl -sSL -o si/si.json https://raw.githubusercontent.com/simple-icons/simple-icons/develop/data/simple-icons.json`), then run `python3 palette_check.py` for the full report. `python3 palette_check.py --search` reruns the nudge from the hand-placed seeds and rewrites `directions.json`. Once a direction is chosen, its values go into `design-tokens.json`, the generator runs, and every platform is built and looked at in light and dark (Decision 053).
