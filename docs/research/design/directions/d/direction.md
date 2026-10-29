# Direction D: one cohesive design

*D2b-3, 2026-10-29. Open `index.html?s=home` (screens: `home`, `browse`,
`series-rich`, `series-sparse`, `episode-rich`, `episode-bare`,
`now-playing`, `search`, `stations`, `library`, `production`) and
`record.html?s=pick` for making (`pick`, `part`, `ready`, `recording`,
`review`, `done`, `listen`); add `&theme=dark` for dark. Shots:
`../../img/d2b-3/<screen>-<375|1440>[-dark].png`.*

The owner on D2: *"Overall, I think the visual approach of The Company
makes the most sense. Images of people and of the shows themselves are the
most appealing for any user to use as a way of browsing and selecting items
... I like the bulky blocks and colors of The Sleeve and I like the data
visualization options of the Almanac. Overall, formatting and fitting
things together could use some work on all three (a share button that goes
to the next line instead of being next to the other buttons, poor word
wrapping, etc.). In particular, the 'Start an ear drama' on the Company
design is exactly what we are trying to avoid (undifferentiated/undesigned
lists of text without any visuals or colors whatsoever)."*

Skills followed: `catalog-experience-design` (rows, event line, booklet,
copies, two tiers, That night), `uniform-imagery-design` (crop, grade,
mount, floor, originals on Detail), `artwork-presentation-design` (slot
shapes, the typographic card), `mobile-first-density-design` (six type
levels, one canonical cell, 375 first), and Decision 064 (ink for Play,
Listen live and Listen through; blue for every other control; red only in
the recorder; genre hues are content). The shell is Decision 068's,
unchanged.

## The design in one paragraph

Every list is pictures on colored boards. A show is one **tile**: a board
in its genre hue, the show's star graded to one neutral gray and mounted
on it, the name in display capitals on the board below the picture, a
run strip in the board's own text color, and its core years and count. A
person is a **graded circle**. A show without a picture, or with one too
small for the slot, is the same board with its name set in the picture's
place, so a wall where a third are names still reads as one set. Big
**boards** head every series, episode, station and production; data that
the catalog really carries is drawn as marks: the run strip, the day's
years stacked by genre, the evening as a timeline, the decade-by-genre
field, the part fingerprint. Rows that are not tiles carry a visual too: a
date block in the genre hue (or the log number on an undated show), a
guest's face, a hatched block for a slot that does not survive.

## What D takes, and what it drops

| From | Takes | Drops, and why |
|---|---|---|
| **B, The Company** | Faces as the way in: the Most heard wall on Home, Heard most on a series, On the air under Now Playing, a guest's face in the log, Voices as a Browse scope and a Search group; three faces on Detail. | The text-only lists ("Start an ear drama", the shows list with a 56 px thumb and two lines of gray): every list is now tiles, faces or blocked rows. The print-as-tile grid with no mount, which made a color snapshot, a sepia halftone and a typographic card three different objects. |
| **C, The Sleeve** | Bulky genre boards as structure: the series hero, the bare episode's card, the production poster, the play blocks; display capitals; the booklet behind one control; copies named by what differs. | One feature per screen: Home is a page of real lists again (the day, faces, shows), because the Sleeve's four covers held four items. The very large display size: D stays inside the six levels (the board name is L1, 28 px), the bulk comes from full-width blocks. |
| **A, The Almanac** | The day's years strip (now stacked by genre, from the series index), That night on the radio on Detail and Now Playing (shows first, copies folded, the tail counted), the run strip on every tile and as the series scope, the decade-by-genre field, the evening as Stations. | The log of text rows as the main list, the field as tinted cells with ink numbers (a cell's tint failed AA under its number at the high counts): D's field draws a genre square sized by the count and sets the number in muted text below it. |
| **D2b-2, Record a Line** | The whole making flow, as designed: play blocks with the cast fingerprint, the playbill, the duet recorder, red only while armed or recording. | Nothing redesigned. Joined only where it had to be (`join.css`): text on a hue block takes the new on-genre tokens, dark mode keeps blocks at full hue as D's boards do, and the listen-through cast rail wraps instead of scrolling sideways. |

## The pictures (uniform-imagery-design, measured)

`build_data.py` is the skill's proposed pipeline step run on this
prototype: it reads the 500 px Commons thumbnail of every picture D draws
in a repeated slot (127 of them), measures luminance inside the crop the
slot shows, and writes `[k, o]`, the tone class and the crop's side in
source pixels to `data.js`. Result: 45 identity grades, 3 at the 1.6 cap,
79 stretched; 93 monochrome, 11 sepia, 23 color. The page applies each as
one SVG filter in sRGB (saturate 0, then the linear map); Detail and Now
Playing show the originals ungraded. The floor (`cropPx >= slot`) sends 6
of 127 to the typographic card at the 160 px tile (Jack Benny's 174 by 333
portrait is why Jack Benny Program and Grape Nuts Program are cards) and
none at the 76 px face or 48 px row. Wide pictures without a face would
show whole on the print ground; none occur in this sample.

## Color and contrast

*Superseded in D2c-1 (`docs/research/palette/surfaces.md`, Decision 064):
boards now draw in `color.board`, one lightness band per mode, with one
on-board color (`color.onBoard`) for everything on them; `color.onGenre`
is the text on a mark used as a fill. Shots: `../../img/d2c-1/`. What
follows is D2b-3's record.*

New tokens, `color.onGenre` in `design-tokens.json`: the text color on
each genre board, white or ink, whichever holds 4.5:1 (lowest 4.54:1,
light science fiction). Light comedy is the one ink board (white was
3.90:1). The generator emits them for the web (`--color-on-genre-*`, and
`--genre-on` beside `--genre-accent` under `[data-genre]`);
`tools/test_design_tokens.mjs` checks the keys, the 4.5:1, and catches
white on light comedy as its negative control. Apple, Android and Windows
emission waits for the first native board (D3). The print ground and edge
(`#EDEDED` / `#2A2A2E`) are still prototype CSS; they should become tokens
with D3.

**The near-magenta risk.** Light drama `#B42575` and record `#B0152F`
are 39 apart in CIELAB (dark: `#FF91C3` and `#E3384B`, 47), about 36
degrees of hue: distinct side by side, but the same family, and drama is
the most common board (every Gutenberg play but the comedies is drama).
D holds the line by shape and place, not hue: red is only ever the round
record control with its microphone and label, inside the recorder; drama
is never a part hue there (the recorder's rule); no drama board is ever a
circle or sits in the recorder's dock. If the owner wants more distance,
move drama toward violet (about hue 340), not record.

## Fit, checked mechanically

`shoot.mjs --fit` lays every screen out at 320, 375, 390 and 430 px
(through an iframe) and at 1440 px, light and dark, and fails on a page
that scrolls sideways, a word broken inside itself, text past its box or
clipped, a button row that wraps, a button label that wraps, and a heading
whose last line is a stray word. Words never break (`word-break`,
`hyphens` off); headings balance; secondary buttons drop their labels to
icons under 600 px so Play, Queue and Share always share a row. The
negative control, `--break`, was run and every check fired (63 sideways,
2 broken words, 786 overflows, 20 wrapped rows, 52 wrapped labels, 50
stray words); then every screen passed. It caught real defects on the
way: show-card names at 28 px overflowing ("MUSIC DEPRECIATION"),
five-column tiles inside a two-column page at 1440, and the listen-through
cast rail scrolling sideways. Looking at the PNGs caught three it cannot
see: nested links that pushed every play button to its own line, a Listen
live label inherited into invisibility on a neutral board, and a separator
dot stranded at the end of a wrapped fact line (each dot now travels with
the fact after it; tile facts sit on their own lines).

## Open questions for the owner

1. **That night on Detail.** D puts it on Detail and Now Playing as tiles
   (95% of dated episodes share a night). It needs the `sameDay(id)` verb.
2. **Whose face leads.** D uses data order on Detail (The Black Curtain
   opens on Hans Conried, then Cary Grant) and the published-guest rule in
   logs (not heard on a quarter of the season). The same star leads two
   shows (William Conrad on Gunsmoke and Escape; Jack Benny on two), so a
   billing rule would also decide which tile gets which face.
3. **What a signed-out invitee sees.** The production page shows title,
   author, recording dates, the cast by chosen names and the voice strip;
   whether takes play before joining is still Decision 072's question.
4. **Whether finished dramas are listed** on Ear Drama's own pages, and
   credited by chosen names. D draws one production at its own link and
   lists none.
5. **Show line 10 or 5.** D's counts use 10 (1,374 shows; 7,189 single
   recordings).

## Pipeline work D needs

- **`art.grade`** per picture: `[k, o]`, tone class and crop side in
  pixels, from the faces phase's 500 px read (`build_data.py` is the
  formula); clients apply it, never measure.
- **`sameDay(id)`**: the night's other broadcasts, shows first, copies of
  one broadcast folded (the 1944 day lists Gildersleeve three times across
  re-uploads, and the 1945 news broadcast twice); D folds by title in the
  client only for the prototype.
- **Run histograms** (`hist`, `core`) on every show row, not only the
  sample's 24; and the day's per-year genre counts.
- **Display titles**: file-name titles ("Ep004 Dodge City Killer",
  "Hanson's Ghost (406)") and series names that are uploads
  ("Afrs053-ThisIsTheStory-...").
- **The role map**: credit roles to On the air, Writing, Production, so
  "the man in black" and "commercial spokesperson" group the same way on
  every platform.
- **A genre for every series a tile shows**: 477 shows have none and
  would be neutral boards; and `subjects` on the castable plays so a play
  can be more than drama or comedy.

## What the prototype does not show

Surprise (a reason-bearing draw inside a chosen scope) and the Voices
scope of Browse were not drawn. Library is a fixture (the sample holds no
personal data): two Continue listening rows, the D2b-2 production in
progress, six followed shows. Search's episode rows are Gunsmoke's sampled
episodes standing in for a credit match on "Conrad". Nothing was tried on
a device, at ten feet, with VoiceOver or TalkBack, or at the largest text
sizes.
