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

## State

- Phase: D2 (synthesis), started 2026-10-29; D1 done (three reports merged).
- Running: D2 (skill catalog-experience-design and three clickable directions);
  build batches S1 (share pages) and Q1 (catalog and display defects from the audits).
  D1b: 65.5% of episodes carry no credit, network or sponsor; design for the bare page.
- Owner rulings collected for D2: what a signed-out invitee may see (title, part,
  who is in); whether finished dramas are listed and credited on Ear Drama's own
  pages; a detective show's face (lead vs a supporting actress).
- Waiting on the owner: nothing yet (the D2 gate comes next).
