# Direction D: one cohesive design

*D2c-3, 2026-10-29. Open `index.html?s=home` (screens: `home`, `browse`,
`shelf`, `series-rich`, `series-sparse`, `episode-rich`, `episode-bare`,
`now-playing`, `search`, `stations`, `library`, `production`, `invite`,
`invite-join`, `dramas`, `drama`) and `record.html?s=pick` for making
(`pick`, `part`, `preflight`, `ready`, `recording`, `review`, `run`,
`run-recording`, `run-review`, `lines`, `lines-recording`, `done`,
`listen`); add `&theme=dark` for dark. Shots:
`../../img/d2c-3/<screen>-<375|1440>[-dark].png`. Earlier rounds:
`../../img/d2b-3/` (D as first drawn) and `../../img/d2c-1/` (D on the
board tokens).*

## What D2c-3 changed, and why

The owner on D2c-1's frames: *"the design is still not uniform for all
different levels of content (some with images, some without, some with
more information, some with less). We need to a design approach that
evens out all of the inconsistencies and make the app look like one
complete thought ... make sure the colors are working together instead of
against each other and that all of the rough edges have been smoothed out
with better design."*

What was wrong, measured on the D2c-1 frames: a tile with a picture put
the show's name under the picture, a tile without one put it inside an
outlined box in the picture's place, so one wall held two objects; a run
strip appeared on some tiles and not others, so the facts sat at
different heights; a bare episode opened on a 2:1 board and a rich one on
three loose portraits, so the two pages did not share a single slot; the
cast bill, the cue card and the next part said their hue with a 4 to 6 px
stripe on one edge (Human Shaped's anti-pattern D6). And the data is
mostly bare: of 2,036 shows (the show line is now 5, the owner's ruling),
37 lead with the show's own image, 261 with a star, 1 with the person
heard most, and 1,737 (85%) with nothing; 65.5% of episodes carry no
credit, network or sponsor.

So the grammar is written first, as `catalog-experience-design` rule 11
(generic, with this as its worked example), and every surface follows it:

1. **One skeleton of fixed slots per object.** A show tile is *window,
   name, mark, facts*; a person is *window, name, episodes*; an ear drama
   tile is *window, title, voice strip, credits and date*; a row is
   *visual, title, sub, length, play*; a head board (series, episode,
   production, invitation, finished drama) is *window, kicker, name,
   credits, facts, mark*. Richer data fills more slots; it never adds,
   moves or resizes one.
2. **The window is always there, and the bare window is designed first.**
   It holds the picture that leads (contract §3.3a: the show's own image,
   then its star, then the person heard most; on an episode, the show's
   own image, then the episode's star), graded and mounted
   (`uniform-imagery-design`), or a wide graphic whole on the print
   ground, or the **title block**: the show's monogram (the initials of
   its first two words that start with a letter) cut large in Big
   Shoulders, outlined in the board's one on-board color, standing on the
   window's foot like a block of wood type. The name is never drawn twice;
   it stays in its own slot, so a picture tile is the same object with a
   picture added. Browse's A to Z (`shelf`, the catalog as it is: 5 of 24
   with a picture) is the test that the bare wall reads as intended.
3. **Slots collapse by a written rule.** Inside a tile, a row or a head
   board a missing value holds its slot: an undated show draws the run
   strip's flat baseline and says "Undated" where its years would be; a
   row without a sub line keeps its 64 px and centers the title. On a
   page an optional section (On the air, That night, Heard most, Cast and
   credits) goes whole and the sections after it close up in a fixed
   order. Tiles and faces in one grid row share their slot tracks (CSS
   `subgrid`), so a one-line name and a three-line name put both marks
   on one line.
4. **Rich and bare pages share one skeleton**, and the fit gate proves it
   (below): the rich episode and the 1945 news file, Suspense and Stay
   Tuned For Terror, the production in progress and its invitation and
   the finished drama, and the recorder in each of its three modes.
5. **Picture kinds get one treatment.** Show, star and person go through
   the same crop, grade and mount. A tile says nothing about the kind (its
   name is its label); Now Playing names a person under the picture, and
   an episode page names them first in On the air, directly under the
   head board that shows them.

## Color (D2c-1's system, applied everywhere)

Objects stand on **boards** (`color.board`, one lightness band per mode;
neutral `surfaceAlt` for the 834 shows with no genre); everything on a
board takes **onBoard**: the name, facts, run strip, the title block's
outline, the window's inner hairline. **Marks** (`color.genre`) are only
small: legend keys, the decade field's squares, the day's stacked years,
the evening's slots, a part's face, the cast fingerprint, the cue's
streamer. Pictures sit on the **print mount**, now tokens:
`color.print.ground` (`#EDEDED` / `#2A2A2E`) and `color.print.edge` (the
text color at 18% / 16%), emitted as `--color-print-ground` and
`--color-print-edge`; `tools/test_design_tokens.mjs` §5d holds them (a
ground at least 3 CIEDE2000 from the page, no dark glare over Lc 30, an
edge of at most 0.3 opacity seen at 1.3:1 on the page and the ground and
1.15:1 on every board), each rule with a negative control seen to fail.
The edge stripes are gone: the bill, the part card, the cue card, the
listen-through's current line and the next part say their hue with the
part's face; your line's box in the recorder is your part's board with
its one on-board color (no tints), and the red edge outside it appears
only while the microphone is armed or open. Red still means recording
and nothing else (Decision 064).

## Making: three recording modes (owner ruling 4)

One native control, a segmented radio group under the part strip
(`UISegmentedControl` / `Picker(.segmented)`, Material `SegmentedButton`,
a radio group on the web), holds its place in every state and is
disabled while the microphone is armed or open. The states are D2b-2's
(Ready, Cue playing, Your turn, Recording, Review, Kept, and every
refusal in its §4); the mode changes only what follows a take.

- **Run through** (`run`, `run-recording`, `run-review`): the play plays
  straight through from the chosen line, other parts in their human takes
  or the live device voice; your next line waits armed (the dashed red
  edge and "Next"), the microphone opens on it as it comes and the
  line-end detector closes it; the transport is ink Pause until the
  microphone opens (then the red Stop). Pausing ends the run and opens its
  review: the run's takes, each played with its cue, any one recorded
  Again, then **Keep 3 takes** (ink) or Discard the run.
- **Line by line** (`lines`, `lines-recording`): every line of your part
  in order with its state (`✓ Take 2` or "Not yet"); tap any line to open
  it with its cue above, then Record (red) or hear the Cue (blue).
- **Step** (`ready`, `recording`, `review`): each cue waits for a tap;
  Keep lands on the next line's Ready rather than playing its cue.

## New screens from the rulings

- **The invitation, signed out** (`invite`; ruling 2): the same page as
  the production, every slot filled: the play, who directs, the parts,
  who holds each, and their takes playable (a play control per held
  part); Listen through plays it all. The only ask for an account is at
  **Take part** (`invite-join`: "Taking a part needs an account." and the
  two sign-ins of Decision 057).
- **The finished ear dramas** (`dramas`, a third Browse scope, and New ear
  dramas on Home; ruling 3): newest first, each a tile in the show tile's
  grammar with the voice strip as its mark and the performers credited by
  their chosen names. The six are fixtures on real castable plays, cast
  with D1c's fixture names (Pat, Sam, Ada, and others); no real person.
- **A finished ear drama's page** (`drama`): the production's skeleton
  with the credits in the head board, Listen, and the bill as credits.

## Fit, checked mechanically

`shoot.mjs --fit` lays out every screen (29) at 320, 375, 390 and 430 px
and at 1440 px, light and dark, and fails on everything D2b-3's gate
caught (sideways scroll, a broken word, overflowing or clipped text, a
wrapped button row or label, a stray last word, a line opening on a
separator dot, two Share controls) plus D2c-3's: a card-edge stripe (one
border side of 3 px or more, or an offset inset shadow), a slot that goes
missing, jumps or changes its window's size within one grid row, a list
row without its 48 px visual or under 64 px, and a slot jump between the
variants of one skeleton (each common slot's left, width and gap above,
and the height of fixed slots: window, mark, actions, the recorder's top,
strip and mode control). Result: 29 of 29 screens at 0 problems, light
and dark, 7 pairs compared at every width. The negative control
(`--break`) fired every check: 2,063 problems on all 29 screens,
including 100 card-edge stripes, 60 slot jumps and 60 missing slots in a
row, 17 window-size mismatches, 125 rows without their visual, and slot
jumps in the episode, production and recorder pairs. The separator-dot
check is the one the control does not exercise. On the way it caught:
long single words ("Bauerngeselchtes", "Introduction") widening a tile
past its column, and the 38-part fingerprint of King Henry VI doing the
same (both now step down by rule), a title-block SVG sizing its window
at 150 px, and the Listen through and Invite row overflowing at 320 px.
Looking at the PNGs caught what it cannot: monograms with M or W cut by
the window (now sized from letter widths, capped so a capital stands
inside), the finished drama's full voice strip drawn as a wall of light
blocks (now 24 px), and the series log jammed against Follow at 1440.

## The data

`build_data.py <cache> <ear-drama.sqlite>` reads a projection built with
the D2c-2 picture columns (the live `eardrama.org` index did not carry
`picture` yet; this one was built from the main checkout's caches and read
only), and writes `data.js`: the 146 shows D draws with `picture` (url,
size, face box, kind, source, the person's name), the run (`hist`,
`core`) from every dated episode, the counts at the show line of 5
(2,036 shows, 7,189 single recordings, 834 with no genre), the decade
field, the 24 most downloaded, Browse's A to Z from B, and the measured
grade of all 143 pictures (55 identity, 3 at the cap).

## Open questions for the owner

1. **The monogram.** Two initials ("BR" for Babe Ruth Collection, "XM"
   for X Minus One) make a wall of title blocks read as a type specimen
   rather than a run of one letter; A to Z still repeats its letter in
   the first place. A single initial is the alternative.
2. **Where finished ear dramas live.** D puts them in Browse (a third
   scope beside Shows and Voices) and on Home (New ear dramas). Decision
   068's shell is unchanged.
3. **Run through's review.** D asks for review after the run (pause, then
   hear and keep). Keeping every take as it lands, with review optional,
   is the faster alternative.

## Pipeline work D needs (carried from D2b-3, still open)

`art.grade` per picture; `sameDay(id)`; run histograms on every show row;
display titles for file-name titles and upload-named series; the role
map; a genre for the 834 shows with none (they draw on the neutral
board).

## What the prototype does not show

Surprise and the Voices scope of Browse; Library is a fixture; Search's
episode rows are Gunsmoke's sampled episodes standing in for a credit
match. Nothing was tried on a device, at ten feet, with VoiceOver or
TalkBack, or at the largest text sizes; subgrid's native equivalents
(SwiftUI `Grid`, Compose) are named in the skill, not built.
