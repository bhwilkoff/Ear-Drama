# The design loop: finding, listening, making, sharing

On October 29, 2026, Ben asked for a second loop, about design and display:
*"Almost everything in the app functions as a list of items with sparse
images/graphics and a lot more metadata being surfaced than is necessary. We
need to level up the individual content experience as well as the collection or
"list views" that show a series of items. We do this as beautifully crafted
shelves on Archive Watch, but I'm not sure that is the right metaphor for this
implementation. Can you do ensure that the loop does extensive research on how
to display large databases of content in pleasing and easy to use ways. I think
we may need entirely new design patterns and smart choices for what content to
surface to create an easy to use experience to find Ear Dramas, Listen to them,
Create them yourself, and share them with others."*

This file is the loop's memory. `LOOP-PLAN.md` still holds the build backlog;
this loop owns how the app looks and what it chooses to show.

## Starting and resuming

`/loop Read DESIGN-LOOP.md and run the next tick`. A tick runs when an agent
reports, with a 30-minute fallback. Each tick: `gh run list -L 10` (fix or
explain red first); read this file's **State** section; act on the current
phase; update **State**; log one entry in `AUTONOMOUS_PROGRESS.md`. When the
phase waits on the owner and nothing runs, the loop stops and says what
unblocks it (memory: no idle ticks). A fresh session about every ten ticks.

## The four jobs

Every design choice is judged against the four things a person comes to do:
**Find** an ear drama worth their evening, **Listen** to it, **Create** one
(record a part, alone or with others), and **Share** it. A surface that serves
none of them is cut; a field that helps none of them is hidden.

## Binding constraints (unchanged by this loop unless the owner says so)

- Decision 068's shell: Home, Browse, Stations, Surprise, Search, Library.
  The loop may propose changing it; only the owner changes it.
- Only essential words on screen; no AI-written lists or copy (data or a human
  editor); unclaimed recordings never called public domain.
- On Air (Decision 064): ink for actions, red only for recording, blue for
  wayfinding, genre hues are content.
- `artwork-presentation-design`: the box takes the picture's shape; faces from
  the pipeline; the typographic card is the default art.
- Feature parity, native idiom: web, iOS/iPadOS, macOS, tvOS, Android.
- Design runs through a design skill; research first, cited (AGENT-BRIEF).
- Values: `learning-orientation-design`, `values-based-feed-ranking` for any
  "what to surface" ranking; nothing that makes a person more passive.

## Phases

**D1. Research (three Opus agents in parallel, cited, no code).** Each writes
`docs/research/design/D1-<topic>.md`: what the best products and collections do,
why it works, what Ear Drama's data can actually support (read the catalog
contract and the live projection, not guesses), and what to steal or refuse.
- **D1a Finding in a huge catalog**: browsing 100,000+ items beyond shelves
  (Criterion Channel, Apple Music and Podcasts, BBC Sounds, Pocket Casts,
  Letterboxd, Discogs, Are.na, museum collections such as Cooper Hewitt and the
  Rijksmuseum, archive.org itself, library catalogs, radio guides and almanacs);
  timelines, calendars, maps of networks and decades, people graphs, faceting,
  progressive disclosure, information scent; which metadata earns a place in a
  list row and which belongs only on detail.
- **D1b The single item and listening**: episode and series detail, Now
  Playing, queue and continue (podcast and audiobook apps, liner notes, museum
  object pages, broadcast archives such as BBC Genome and the Paley Center);
  how to make a 1947 broadcast feel like an event (its date, its evening, who
  was on) without a wall of fields.
- **D1c Making and sharing**: collaborative creation and invitation (GarageBand,
  Voice Memos, Descript, LibriVox, Off Book, table reads, multiplayer invites),
  link previews and share cards, what a finished production's page should be.
Each also audits the current app: 375 px web shots of every surface it covers
(headless Chrome through an iframe), and an inventory of every field each
surface shows, marked keep / move to detail / cut, with the reason.

**D2. Synthesis (one Opus agent).** Reads the three reports and writes:
- a design skill, `catalog-experience-design` (generic, with Ear Drama as the
  worked example), the rules the build phase follows;
- three distinct **directions** for the app as a whole, each a clickable web
  prototype at 375 px and 1440 px of Home, Browse, a series, an episode, Now
  Playing, and the create flow, rendered to PNGs and published as one artifact
  for the owner; each names what it surfaces, what it hides, and its metaphor
  (shelves are one option, not the default).
**Owner gate:** the owner picks a direction or mixes them. The loop stops here
until they do.

**D3. Build, one surface per batch, every platform.** In the order the owner's
direction gives (default: Home and Browse, series and episode detail, Now
Playing and the queue, Library, Create, Share). Each batch: the binding design
doc rules first (`binding-design-doc-discipline`), then web, Apple, Android in
one worktree; Opus for the batch's design, Sonnet for straight ports; frames
read before merge; merged, pushed, shipped (the push-everything rule).

**D4. Review.** A `human-shaped-review` pass and a parity audit over the new
surfaces; the owner plays it on devices; their feedback opens the next round.

## Owner feedback on D2 (2026-10-29)

*"Unfortunately, I like elements of all three. Overall, I think the visual
approach of The Company makes the most sense. Images of people and of the shows
themselves are the most appealing for any user to use as a way of browsing and
selecting items. However, with no real way to standardize the images
(dimentions, quality, etc.), we will need to create skills to allow for
everything to look uniform even though it is not. I like the bulky blocks and
colors of The Sleeve and I like the data visualization options of the Almanac.
Overall, formatting and fitting things together could use some work on all three
(a share button that goes to the next line instead of being next to the other
buttons, poor word wrapping, etc.). In particular, the "Start an ear drama" on
the Company design is exactly what we are trying to avoid
(undifferentiated/undesigned lists of text without any visuals or colors
whatsoever). I also don't think we have gotten even close on the Record a Line
designs (on any of the designs). Can you create a cohesive design based upon
this feedback?"*

So **D2b** makes one cohesive direction, D:
- **Lead with images** (The Company): people and shows are the way in.
- **Uniform although the sources are not**: a new skill for making portraits and
  graphics of every size, quality and kind sit together as one set (it may revise
  `artwork-presentation-design`; fix the skill first, then the design).
- **Bulky blocks and color** (The Sleeve): genre hues and big type as structure.
- **Data visualization** (The Almanac): run strips, the day's years, the decade field.
- **No undesigned lists**: every list (including picking a play) has visuals and color.
- **Record a Line rethought from research**, not from the old flow.
- **Fit and finish checked mechanically**: button rows that never wrap apart, no
  orphaned or mid-word breaks, at 320, 375, 390 and 430 px.

## Owner feedback on D (2026-10-29)

*"This is looking much better so far, but the color combinations are looking
terrible, especially on dark mode. Can you use the tools we built for Human Shaped
(the universal app template) to better align on color combinations and making sure
it looks good on all differnet kinds of surfaces. Additionally, the design is still
not uniform for all different levels of content (some with images, some without,
some with more information, some with less). We need to a design approach that
evens out all of the inconsistencies and make the app look like one complete
thought. The images that should lead should always be ones that best represent the
whole Ear Drama. So, images/graphics that show the full "show" are better than
individual contributors. Images that show the star(s) are better than those that
show folks that are less recognizable. D is definitely the right approach to take
for design of the app, but we really need to work hard to make sure the colors are
working together instead of against each other and that all of the rough edges have
been smoothed out with better design."*

So **D is the direction** (the D2 gate is passed), and **D2c** refines it:
- **Color, with the Human Shaped tools**: `docs/research/palette/measure/palette_check.py`
  (APCA and WCAG, CIEDE2000, color-blind simulation, Simple Icons neighbors), the
  palette lessons in `docs/research/palette/README.md`, humanshaped-site's
  `research/notes/ai-design-anti-patterns.md`, `make-it-look-like-itself`, and the token
  generator and test. Every pairing on every surface (ground, surface, board, button,
  text, mark), light and dark, checked and rendered.
- **One grammar for every level of content**: an item with a picture, without one, rich
  or sparse, renders in the same structure, so the app reads as one thought.
- **The picture that represents the whole show leads**: the show's own image (title card,
  cast photo, logo) before any one contributor; the star(s) before less recognizable
  people; all from data with evidence.

## Owner rulings on the D questions (2026-10-29)

*"1. Having more shows is better, so 5.
2. On an invite link, they should be able to see everything. They just can't
contribute until they sign in.
3. Finished ear dramas should definitely be listed and credited. Why else would we
record them?
4. I think you should be able to have mutliple modes for recording your part. One
option should let you record and have the other parts play (either human voices or
generated voices for parts that haven't been taken yet) and it should play right
through with your opportunity to record your part as it shows up naturally within
the Ear Drama script. Another option should allow you to record each line
individually or re-record any lines again by tapping them and re-recording. Another
option could be a "wait for tap" to advance through the script as you are
describing."*

- **A show is 5 or more episodes** (2,037 shows; the rest is the counted tail).
- **An invite link shows everything signed out**: the play, its parts, who is in, and
  the takes (playable). Claiming a part and recording need an account.
- **Finished ear dramas are listed and credited** on Ear Drama's own pages (and the
  share page), performers by their chosen names.
- **Three recording modes**: *Run through* (the play plays straight through, other
  parts in human takes or live device voices, and the mic opens at each of your lines
  as it comes); *Line by line* (record any line, tap any line to re-record); *Step*
  (each cue waits for a tap to advance).

## State

- Phase: D2c done 2026-10-29 (1.0.109); **owner gate**: build D everywhere (D3)?
- Review page (updated): https://claude.ai/artifact/18ay3AKgXdN53V32TGTqMB
- Merged: D2c-1 colors (1.0.106), W1 (1.0.107, deployed), D2c-2 pictures (1.0.108),
  D2c-3 one grammar (1.0.109: catalog-experience-design rule 11; title blocks; three
  recording modes; invite, finished dramas, A to Z shelf; 29 screens, fit gate 0 problems).
- Open owner calls: build D everywhere; one face per star (William Conrad leads both
  Gunsmoke and Escape).
- Running: C2 (stage the cache Release with series_art) and W2 (a published production
  survives its last member's deletion).
