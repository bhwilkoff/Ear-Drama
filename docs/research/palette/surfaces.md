# Color on surfaces: D2c-1

October 29, 2026. The owner, on direction D: *"the color combinations are looking terrible, especially on dark mode. Can you use the tools we built for Human Shaped (the universal app template) to better align on color combinations and making sure it looks good on all differnet kinds of surfaces ... we really need to work hard to make sure the colors are working together instead of against each other."*

This page is the diagnosis, the new rules, and the numbers. Every number comes from `measure/palette_check.py --surfaces measure/pairings.json`, read against D2b-3's tokens (`measure/tokens-d2b-3.json`, a copy of `design-tokens.json` at 4c5195a) and the new `design-tokens.json`. The full reports are `surfaces/report.txt` and `surfaces/report.json`; the swatch sheets are `surfaces/swatches.html` (new) and `surfaces/swatches-d2b-3.html` (before), written by `measure/swatches.py`.

## Method

1. **Inventory what D draws**, from `directions/d/style.css`, `join.css`, `../record/style.css` and the D2b-3 frames: the four grounds (background, surface, surfaceAlt, the print ground), the eight genre boards (tile, series hero, bare episode card, play block, date block, the chip), what sits on a board (the name in display type, the fact line, the run strip and its empty years at 30%, the typographic card's 1 px edge, the print mount), the marks on the grounds (legend keys, the decade field, the day's stacked years, the evening timeline, the cast fingerprint, a part's face), the ink action, the wayfinding blue, and the record button next to drama. That list is `measure/pairings.json`: 20 pairing rules that expand to 72 pairs per mode, plus neighbor sets, bands, and colors kept apart.
2. **Measure each pair** with the Human Shaped tools, extended (`palette_check.py --surfaces`): WCAG 2 contrast; APCA Lc at the APCA readability criterion's bronze levels (Lc 75 body, 60 other text, 45 large bold display, 30 a spot mark, 15 the least a mark may be); CIEDE2000 between neighbors, in normal vision and under the Machado, Oliveira and Fernandes (2009) simulation at full severity; OKLCH lightness and chroma bands across a set; a vibration flag (two chroma above 0.14 at the same lightness, more than 100 degrees of hue apart); and distance from what must not be confused (recording red, wayfinding blue, the status colors, and Claude's clay, Human Shaped lesson 3).
3. **Name what fails**, then redesign from the evidence and the Human Shaped lessons, and measure again.

## The diagnosis

D2b-3 drew its boards in the genre **mark** colors. A mark is tuned to be seen at 10 px on the page (3:1); drawn as a card-sized block, the same color is a different thing. 46 pairings failed (14 light, 32 dark).

- **Dark mode boards were lamps.** The dark marks are light (OKLCH L 0.65 to 0.85, because a mark must read on black), so the dark boards glared at APCA Lc 38 to 78 against the page, brighter than most of the page's own text. Science fiction `#16E3F2`, comedy `#E2D32B` and news `#CECEC0` were the brightest things on every screen; text on them was ink, and on the mid boards ink read at only Lc 41 (serials), 47 (western) and 60 (mystery).
- **No two boards sat at the same lightness.** Light boards spread from L 0.37 (serials `#5D0087`) to 0.60 (comedy `#8D8300`), dark from 0.65 to 0.85, and chroma from 0.09 to 0.19. Side by side in a grid, each board fought its neighbor for attention, and three dark pairs vibrated (drama and science fiction, drama and documentary, western and serials).
- **Two text colors in light mode**, white on seven boards and ink on comedy, which read at APCA Lc 37 (it passed WCAG at 4.75:1; APCA showed why it looked muddy). Comedy's hue (100) at a dark lightness is olive.
- **Marks on boards had no rule.** Run strips on tiles fell back to black on blue and magenta boards whose text was white; an ink button on six of the eight light boards was under 3:1.
- **Drama was close to recording red in light mode**: 18.5 CIEDE2000 (the README's 39 was CIELAB distance, not CIEDE2000).

## The new system

Two tokens per genre, one hue (Decision 064, rewritten). The values are made from `measure/boards.json` by `palette_check.py --boards`; only `design-tokens.json` and the generator changed, and every platform's file was rewritten by `node tools/design_tokens.mjs`.

**Rules**

1. **A board is not a mark.** `color.board` is the block a tile, hero or play block stands on; `color.genre` is the small mark. Never draw a board in the mark color.
2. **Boards sit in one band per mode**: OKLCH L 0.48 and chroma 0.11 in light, L 0.37 and chroma 0.09 in dark (science fiction and western lower in chroma where sRGB or the clay check holds them). The band reads like a row of book spines from one publisher: every board equally heavy, the hue alone telling them apart.
3. **In dark mode a board is a surface, never a lamp**: at most APCA Lc 30 against the page (they sit at Lc 0 to 9, set off by hue), and the dark board is deeper than its mark.
4. **One color on every board** (`color.onBoard`: white light, the text color dark): the name, the facts, the run strip (its empty years at 30%), a typographic card's edge, and any button, which takes that color as its fill with the board's color as its label. No ink button, no blue link, no second text color on a board.
5. **Marks keep a lightness stagger** (spread 0.12 to 0.13) and chroma at most 0.135, so legend keys, the stacked years and the cast fingerprint stay apart for color-blind viewers without vibrating.
6. **Hues re-spaced around what is reserved**: drama plum (345), mystery indigo (260), science fiction teal (212), western rust (45), comedy gold (82, off olive), news a warm gray, documentary green (148), serials violet (300). Recording red, the wayfinding blue and the status colors keep their places (Decision 064).
7. **The name is always in words.** Boards in one band are nearly the same to a color-blind viewer (simulated CIEDE2000 about 2); that is accepted because every board carries its show's name and a genre's name sits beside every mark.
8. **One blue in dark mode**: `secondary` dark moved from `#5AB4D6` to the link blue `#6CC0E0`, so the selected segment's label reads Lc 63 (it was 57).

| Genre | Board light | Board dark | Mark light | Mark dark |
|---|---|---|---|---|
| Drama and anthology | `#86426F` | `#5F2A4D` | `#9D547C` | `#F89DC9` |
| Mystery and crime | `#375C9B` | `#223F6F` | `#2459A5` | `#8EBBFF` |
| Science fiction and fantasy | `#006A79` | `#004854` | `#007C88` | `#44D5D7` |
| Western | `#8B492A` | `#623018` | `#864E37` | `#C99580` |
| Comedy and variety | `#795700` | `#543B00` | `#816B01` | `#D4C27E` |
| News and wartime | `#615D53` | `#424038` | `#504C3E` | `#B4B3B3` |
| Documentary and education | `#296E38` | `#154C22` | `#2F6100` | `#7CB45A` |
| Serials and soaps | `#684D92` | `#473368` | `#5A3983` | `#AA87DE` |

## The numbers, before and after

| | D2b-3 light | D2b-3 dark | D2c-1 light | D2c-1 dark |
|---|---|---|---|---|
| Board lightness (OKLCH L) | 0.37 to 0.60 | 0.65 to 0.85 | 0.479 to 0.481 | 0.369 to 0.371 |
| Board against the page (APCA Lc) | 60 to 95 | **38 to 78** (glare) | 74 to 84 | 0 to 9 |
| Text on a board (APCA Lc) | **37** to 99 | **41** to 78 | 86 to 89 | 89 to 90 |
| Text on a board (WCAG, lowest) | 4.54:1 | 5.49:1 | 6.21:1 | 8.99:1 |
| Text colors on the boards | 2 | 1 | 1 | 1 |
| Boards side by side, min CIEDE2000 | 21.6 | 21.8 | 13.4 | 12.0 |
| Marks side by side, min CIEDE2000 | 21.6 | 21.8 | 18.4 | 18.6 |
| Marks, color-blind min (protan / deutan / tritan) | 8.4 / 8.4 / 10.2 | 10.4 / 9.7 / 11.2 | 6.5 / 5.8 / 7.6 | 7.0 / 5.3 / 8.7 |
| Marks on every ground (WCAG, lowest) | 3.19:1 | 4.49:1 | 4.05:1 | 5.39:1 |
| Vibrating pairs | 1 | 3 | 0 | 0 |
| Drama board from recording red (CIEDE2000) | **18.5** | 25.7 | 21.2 | 31.2 |
| Pairing checks failed | 14 | 32 | 0 | 0 |

The cost is honest and on purpose: boards in one band are closer to each other (12 to 13 apart instead of 22) and marks lost two to four points of color-blind separation, because the old separation came from the very lightness and chroma differences that made the boards fight. The one pair still under its APCA level is the dark record button's label (`onRecord` on `record`, Lc 36), which Decision 064 already accepts; it is reported as KNOWN, not counted.

## The test, seen to fail

`tools/test_design_tokens.mjs` §5c checks the board rules: one text color per mode at 4.5:1 and Lc 75, one lightness band (spread at most 0.04), no dark board over Lc 30 against background or surface, drama 20 and every board 15 CIEDE2000 from record, with five negative controls (D2b-3's dark drama board, a lighter board, a second text color, a drama board in recording red, white on a pale board). The generator now exports `oklch`, `apca` and `deltaE` for it. Put D2b-3's design back (each board set to the old genre hue, its text to the old on-genre color) and the test fails:

```
FAIL  the boards hold: ... (problems: light: 2 text colors on the boards; light: board lightness spread 0.230 > 0.04;
      light drama board is 18.5 from record (needs 20); light comedy: text 4.75:1, Lc 36.9 (needs 4.5:1, Lc 75);
      dark: board lightness spread 0.203 > 0.04; dark drama: text 9.20:1, Lc 63.1 ...; dark drama glares on background: Lc 61.5 > 30; ...)
2 design-token check(s) FAILED
```

With the new tokens: `all 14 token files match; contrast holds in light and dark`.

## The frames

D re-rendered with the new tokens (`directions/shared/tokens.css` re-copied from the generated block; `style.css` and `join.css` now draw boards in `--genre-board` and everything on them in `--genre-on`), every screen at 375 and 1440 px, light and dark, in `../design/img/d2c-1/`. D's fit gate: 18 of 18 screens, 0 problems, in light and in dark.

- `swatches.png`: every board on every ground, both modes, with each board's text Lc and its Lc against the ground; marks, the cast fingerprint, faces, Play, the selected segment, a link, and the record button beside drama under each.
- `before-after-home-375-dark.png`, `before-after-browse-1440-dark.png` (scaled to 60%), `before-after-episode-bare-375-dark.png`, `before-after-episode-rich-375-dark.png`: D2b-3 on the left, D2c-1 on the right.

## What was not verified

- Every frame is headless Chrome with Public Sans; nothing was drawn on a phone, a TV, or in the system faces. A phone's OLED black and its brightness will change how the dark boards read; look on the iPhone and the Pixel before D3 builds them.
- APCA is the 0.0.98G-4g formula and the bronze levels, simplified to four text kinds by size and weight; color-blind numbers are a simulation, not a test with people.
- Native platforms got the new marks and the dark `secondary` through the generator, but no native surface draws a board yet, so the board tokens are web only. No native build was run in this batch.
- The print ground (`#EDEDED` / `#2A2A2E`) is still a literal in D's CSS; it sits only 1.6 to 3.7 from the light grounds, and its 1 px edge, not its fill, separates it. Making it a token is left to D2c-3.

## Seen on the way

- `directions/d/style.css` `.bill li` and `directions/record/style.css` `.part`, `.next-part`, `.cue`, `.lt-ln.now`: a 4 to 6 px colored stripe on a card's top or left edge, the D6 anti-pattern in Human Shaped's list. D2c-3 should replace each with the part's face or a mark beside its name.
- `directions/record/style.css` line 21 to 28: the record prototype's own block colors (24% hue over the page in dark) are overridden by D's `join.css`; when D2c-3 folds the making screens into D, delete the overrides and the prototype's copy together.
