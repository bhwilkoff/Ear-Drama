# D2: Three directions for Ear Drama

*Design loop phase D2, 2026-10-29. Synthesis of D1a (`D1a-finding.md`),
D1b (`D1b-listening.md`) and D1c (`D1c-making-sharing.md`). Nothing in the
app changed. The rules every direction follows are now a skill,
`.claude/skills/catalog-experience-design/SKILL.md`; the three directions
differ only in which way in leads.*

The owner, 2026-10-29: *"We do this as beautifully crafted shelves on
Archive Watch, but I'm not sure that is the right metaphor for this
implementation ... entirely new design patterns and smart choices for what
content to surface."*

## How to look at them

Open `directions/index.html` (each screen is `<a|b|c>/index.html?s=<screen>`;
add `&theme=dark` for dark). All three read the same sample of the live
projection (`directions/shared/sample.js`, 150 KB, generated
2026-10-29T16:30Z, built by `shared/build_sample.py`) and draw with the real
tokens (`shared/tokens.css`, a copy of the generated block) and On Air's
roles: ink for Play and Listen through, red only on the record control,
blue for links, the selected section and every other control, genre hues as
content. Portraits are hot-linked from Commons through the app's own size
steps and crop formula. The shared production's cast (Pat, Sam, Ada) is
D1c's fixture, not real people. Every other word on screen is the
catalog's own data or the app's existing labels.

Screenshots: headless Chrome, 375 px through an iframe (full height to
2,400 px) and 1440 by 1,100 px, light mode, pngquant
(`shared/shoot.mjs`). All 66 are in `img/d2/<a|b|c>/<screen>-<375|1440>.png`
(2.5 MB in all); each direction's page has the table.

## The three

**A, The Almanac** (`directions/a/direction.md`). The date leads: Home is
today's date with the years it survives in and that night's listings;
Browse is a decade-by-genre field and shows with run strips; a series is a
run strip over a dated log; every dated episode carries **That night**.
Metaphor: the newspaper radio log and the collector's series log.

**B, The Company** (`directions/b/direction.md`). People lead: Home is a
wall of the most-heard voices with portraits; Browse has Voices and Shows
scopes; an anthology's log shows each night's guest face; Detail and Now
Playing open on who was on; the cast sheet and the finished production are
playbills. Metaphor: a stock company's playbill and face book.

**C, The Sleeve** (`directions/c/direction.md`). One cover per screen, then
the item's story in chapters made of data: the run (strip, first, busiest,
last), the season as a track list, who was on, the night it aired, the
booklet. Home is four features, not rows. Metaphor: the record sleeve and
its liner-notes booklet.

## Comparison

| | A, The Almanac | B, The Company | C, The Sleeve |
|---|---|---|---|
| Way in | when (a date, a decade, a run) | who (a voice, a star) | what's the story (one feature at a time) |
| Home | the day: years strip, that night's shows, Tonight on Stations | Most heard faces, then shows by their star | four covers: a night (Oct 29, 1939), a run (Suspense), a voice (William Conrad), a play |
| Browse | decade-by-genre field, 1,374 shows with run strips | Voices / Shows scopes, star prints or cards | a contents page: genres and decades as counted type, shows as small covers |
| Series | run strip as the season scope; log with guest names | heard-most faces; log with guest face tiles | cover beside chapters: the run, the season as tracks |
| Episode | event line, three faces, That night beside it | three faces lead, event line, booklet | face cover, event line, chapters: On the air, That night, booklet, copies |
| Bare record | the date line and That night give it neighbors | the typographic card; complete but thin | the large card as cover; That night |
| Now Playing | That night below the fold | On the air below the fold | the booklet below the fold |
| Create | parts as a log by reading time | parts as playbill cards with performer initials | the script's first page, then the cast list |
| Shared production | a listing with recording dates | a playbill | a premiere sleeve: poster, then the track list of parts |
| Density | highest (logs) | medium (grids) | lowest (one thing per screen) |
| Visual | least (faces only on Detail) | most (faces on Home and every list) | covers everywhere, faces where served |
| Who it fails | undated work (51% of episodes) never reaches Home | 97.5% of series have no portrait, so Shows is mostly cards | scanning: fewer items per screen |
| New pipeline work | histogram + core years, show tier, `sameDay` verb, field counts | merge duplicate people, guest and heard-most rule, billing rule | histogram + core years, `sameDay`, display titles, role map |
| Cost (web / iOS / macOS / tvOS / Android) | M / M / S / M / M | M / M / S / M / M | M / M / S / M / M |

Shared by all three (the skill's rules, no owner ruling needed): the two
tiers (shows, then a counted tail); core years instead of first-to-last;
the event line with the length on Play; up to three faces, then the booklet
grouped On the air / Writing / Production; copies as a count, named only by
what differs; one name field and parts sized in minutes; red only on the
record control; share pages made of facts. These can be built first,
whichever direction the owner picks, and they answer most of the audit's
anti-patterns (D1a §3, D1b §6, D1c §3).

Mixing is natural: B's faces fit A's Home below the day; A's That night
fits B's and C's Detail (C already has it); C's chapters can be A's series
page. The prototypes keep the shell of Decision 068 unchanged
(Home, Browse, Stations, Surprise, Search, Library); none needs a new
section.

## Questions only the owner can answer

1. **What may a signed-out invitee see?** The title, author and length; the
   part meant for them; who is already in, by their chosen names; and may
   they hear the takes before joining (takes reach only members today,
   Decision 072)? Every direction's invite assumes title, part and who is in
   (D1c Pattern 2); it needs a Worker change either way.
2. **Are finished ear dramas listed and credited on Ear Drama's own
   pages?** Each prototype draws a page for one finished production at its
   own link. Whether eardrama.org also lists them (a listing is a ranking,
   `values-based-feed-ranking`) and whether the cast's chosen names may
   appear on a page Ear Drama serves are your calls (D1c Pattern 5).
3. **Whose face leads a detective show, and an episode?** Today the
   most-heard face leads a series, so Boston Blackie wears Lesley Woods
   (D1a, Seen on the way), and an episode's first on-air credit with a
   portrait leads it, so The Black Curtain opens on Hans Conried, not Cary
   Grant (D1b §3). The prototypes use data order on Detail and a published
   guest rule in logs (a face not heard on a quarter of the season). The
   choice is data order, or a published billing rule (the star or title
   role first, then the night's guest).
4. **Does "That night on the radio" go on Detail?** 95% of dated episodes
   share their date with another surviving broadcast (D1b §1). A and C put
   it on Detail; B leaves it out. It is a new section on every platform and
   a new contract verb, `sameDay(id)`, with shows first.
5. **Which direction, or which mix?** And whether the show line is ten
   episodes (1,374 shows) or five (2,037) (D1a §4.1).

## What the prototypes do not show

Search, Stations, Surprise and Library were not redrawn (they follow the
same row rules); dark mode was not shot; nothing was tried on a device or at
ten feet; Continue listening is absent because the sample holds no personal
data. The share card images (Open Graph) are covered by build batch S1, not
here.

## Seen on the way

| Where | Symptom | Proposed fix | Owner? |
|---|---|---|---|
| `index/days/10-29.json` | The 1944 night lists a single "10 29 Jane William's Birthday Party..." upload and "Afrs053-ThisIsTheStory-..." beside the shows | The show tier on day rows (all three prototypes list shows first) | No |
| `index/days/12-02.json` | "The Suspense Project 02 The Black Curtain" is a separate series holding a copy of the same broadcast, so it is its own neighbor | Fold re-uploads of one broadcast into its copies | No |
| Suspense 1943-44 log | AFRS rebroadcasts ("Wet Saturday AFRS (from WC)") are rows of the log beside the broadcasts they copy | Treat a dated AFRS copy as a version of its broadcast | No |
| `search/people/` | Clayton "Bud" Collyer and Bud Collyer are two people (D1a, already listed) | Merge on the Wikidata match | No |
