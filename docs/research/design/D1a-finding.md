# D1a: Finding an ear drama in a huge catalog

*Research date: 2026-10-29. Design loop phase D1a (`DESIGN-LOOP.md`). Status:
research and audit, nothing built. Skills followed: `mobile-first-density-design`,
`artwork-presentation-design`, `values-based-feed-ranking`,
`learning-orientation-design`.*

The owner, 2026-10-29: *"Almost everything in the app functions as a list of
items with sparse images/graphics and a lot more metadata being surfaced than
is necessary ... I'm not sure that is the right metaphor ... entirely new design
patterns and smart choices for what content to surface."*

This report answers the **Find** job: how a person gets from "something to hear
tonight" to one episode in a catalog of 107,369. It goes past
`docs/research/05-design-research.md` (which settled typographic cards, date-first
episode rows and the reconstructed evening) by measuring what the live data can
actually carry and by looking at collections that are not streaming apps.

## How to read the sources

Every external claim names the URL it came from. Most were read through web
search summaries, not by opening the page; the ones opened directly are marked
**(read)**. A claim from general knowledge is marked **UNVERIFIED**. Data
numbers come from the live web projection at `https://eardrama.org/data/`,
generated `2026-10-29T16:30:38Z`, measured by the scripts listed in
"Reproducing the measurements".

---

## Verdict

1. **The catalog is not 10,642 series. It is about 1,374 shows and a long tail
   of single recordings.** 7,189 "series" (67.6%) hold one episode each; the
   1,374 with ten or more hold 92,171 episodes (85.8% of everything). Browse
   counts, sorts and searches the tail as if it were the shows. Every finding
   pattern below starts by drawing that line.
2. **Faces belong to people, not to shows.** Only 271 series (2.5%) wear a
   portrait, but 613 of the 1,795 people heard on 20 or more episodes have one.
   A finding surface built on series will stay mostly letter tiles; one built
   on the voices can be mostly faces, within Decision 069's evidence rule.
3. **The date is the strongest key the data has.** 49% of episodes carry a full
   air date, every calendar day has surviving broadcasts (116 to 232 on the
   days measured; 43 on 29 February), and a single date in a busy year holds 12
   to 27 surviving programs. Radio's own finding tools (newspaper logs, Radio
   Times, BBC Genome, the Library of Congress's "Jukebox Day by Day") were
   organized by day and hour, not by shelf.
4. **List rows carry fields that mislead.** The series year range runs from the
   earliest to the latest copy, so rebroadcasts stretch Inner Sanctum to
   1941-1999 and The Adventures of Philip Marlowe to 1947-1977; the network
   field is a list of up to seven strings (279 distinct values, including
   "Bllue"). Both mislead more than they help in a row.
5. **Generous beats gated, and the evidence favors facets with counts over
   pickers.** Whitelaw's generous interfaces, Hearst's faceted studies (90% of
   32 users preferred facets over plain search for open tasks) and the Cooper
   Hewitt usage numbers (color browsing about 49% of visits, the random button
   about 2%) all point the same way: show the shape of the collection first,
   let people narrow it with counted choices, and keep chance *inside* a chosen
   scope.
6. **Shelves are not wrong, but they are the least informative overview.** A
   carousel shows six items of an unknown whole. The patterns ranked below
   replace "a row of things" with "a view of the whole you can enter anywhere":
   a calendar, a run strip, a face wall, a decade-by-genre map.

---

## §1 What the data can carry (measured)

### 1.1 Series (all 10,642, `index/series.json`)

| Series size | Series | Share of series | Episodes | Share of episodes |
|---|---:|---:|---:|---:|
| 1 episode | 7,189 | 67.6% | 7,189 | 6.7% |
| 2-4 | 1,416 | 13.3% | 3,775 | 3.5% |
| 5-9 | 663 | 6.2% | 4,234 | 3.9% |
| 10-49 | 994 | 9.3% | 22,139 | 20.6% |
| 50-199 | 287 | 2.7% | 25,831 | 24.1% |
| 200+ | 93 | 0.9% | 44,201 | 41.2% |

| Field | All series | Series with 10+ episodes (1,374) |
|---|---:|---:|
| genre | 2,122 (19.9%) | 897 (65.3%) |
| first air date | 4,213 (39.6%) | 649 (47.2%) |
| network | 1,036 (9.7%) | 489 (35.6%) |
| star portrait | 271 (2.5%) | 234 (17.0%) |
| archive.org download count | 8,503 (79.9%) | 1,032 (75.1%) |
| genre + date + network together | 800 (7.5%) | 429 (31.2%) |
| `scripts` > 0 | 0 | 0 |

- 3,969 one-episode series have no genre and no date: an archive.org item title
  promoted to a series (the first rows of the index are "01 03-02" and German
  speech excerpts).
- Downloads concentrate: 712 series hold 80% of all counted downloads.
  Of the 40 most downloaded, 23 wear a portrait and 31 name a network; of the
  top 200, 64 wear a portrait.
- Episodes by the decade their series began: 1920s 5,490; 1930s 20,952; 1940s
  33,650; 1950s 8,030; 1960s 2,244; 1970s 313.
- Genre by episodes: none 34,911; drama 25,080; comedy 17,783; mystery 11,304;
  serial 9,498; documentary 3,688; western 2,253; science fiction 1,588; news
  1,264.
- The median series of 10+ episodes spans 3 years, first to last air date; the
  spans that run decades are rebroadcasts or misdated copies.

### 1.2 Episodes (a 1/16 sample: 256 of 4,096 Detail shards, 6,669 episodes)

| Field | All | In series of 10+ | In one-episode series |
|---|---:|---:|---:|
| title | 96.3% | 96.9% | 89.5% |
| full air date (YYYY-MM-DD) | 49.1% | 51.6% | 50.4% |
| network | 31.6% | 35.7% | 2.1% |
| sponsor | 12.4% | 14.1% | 0.3% |
| any credit | 26.9% | 30.3% | 2.3% |
| a cast credit | 25.2% | 28.6% | 1.5% |
| a writer credit | 13.6% | 15.5% | 0.3% |
| a character name | 0.2% | 0.2% | 0 |
| a credited person with a portrait | 22.7% | 25.7% | 1.3% |
| an episode face (`star`) | 21.5% | 24.4% | 0.8% |
| transcript | 7.3% | 8.4% | 0.3% |
| arc (part of a serial story) | 3.1% | 3.2% | 0 |
| length | 99.9% | 99.9% | 99.5% |
| more than one copy | 32.6% | 33.8% | 35.2% |
| rights clean | 7.5% | 7.0% | 0.5% |

- A credited episode has a median of 9 credits (90th percentile 16): cast 9,035,
  writer 1,363, announcer 1,202, director 863, producer 764 in the sample.
- 130 distinct sponsors in 827 sponsored episodes; the most frequent are Lucky
  Strike, Reynolds Aluminum, Comic Weekly, Kellogg's Pep and Johnson's Wax.
- Lengths: median 23.8 minutes, 10th percentile 3.7, 90th percentile 37.
- Dates come from file names for 2,334 of the 3,274 dated sample episodes; 599
  from OTRR logs, 150 from the UIUC finding aid.

### 1.3 People (`search/people/`, all 262 files)

15,259 people; 2,184 with a served portrait. 4,012 are heard on 5+ episodes
(1,195 with a portrait), 1,795 on 20+ (613), 572 on 100+ (227). The most-heard
are Jack Benny 1,379, Don Wilson 1,368, Jim Jordan 1,187, Mary Livingstone
1,179, and Clayton "Bud" Collyer 1,158, who also appears as "Bud Collyer" 1,105
(a duplicate person, see "Seen on the way").

### 1.4 Days and evenings

- `index/days/`: 366 files. Measured days: 15 January 139 episodes in 109
  series over 28 years; 1 March 152; 25 May 140; 4 July 116; 21 September 145
  (21 of them from 1939, the WJSV day); 29 October 138 (21 from 1944); 24
  December 232 (27 from 1944); 29 February 43.
- `tonight.json` (newspaper-matched evenings, the Stations schedule): 15 days
  published, median coverage 0.31 of the slots; 9 picked by weekday, 6 by
  anniversary.
- `stations.json`: eight genre stations, 145 to 372 slots each.

### 1.5 What this means for a list row

A field earns a place in a row only if it is present on most rows of the
surface where it appears, and helps a person choose between those rows. By
that test:

| Field | Coverage where it shows | Helps choose? | Row or detail |
|---|---|---|---|
| Title | 96% | yes | row |
| Air date | 49-52% (series pages are mostly dated) | yes: in radio the date is the identity | row on episode lists; year only on mixed lists |
| Length | 99.9% | yes: bedtime and the car (05 §1.4) | row, as a caption |
| Series name | 100% | yes on mixed lists, no on a series page | row on mixed lists only |
| Episode count | 100% | yes: how much there is to explore | series row |
| Core years of a run | needs computing | yes | series row, computed (§4.2) |
| Network | 10% of series, 32% of episodes, often a list | rarely | detail |
| Sponsor | 12% | no, but it is a joy on the page | detail |
| Cast | 25-29% | yes when a famous guest is in it | row only as one name, only when it differs from the series' star |
| Writer, director, announcer | 13% and less | no | detail |
| Copies, formats, bitrate | 33% have more than one | no | detail |
| Rights line | 100% | no for choosing; required where it plays | detail |
| Transcript, arc | 7%, 3% | arc yes ("Part 2 of 5") | arc in row; transcript in detail |

---

## §2 Precedents: how big collections let people find

### 2.1 Generous interfaces (Mitchell Whitelaw)

- **What it is.** Whitelaw's 2015 *Digital Humanities Quarterly* paper argues
  that search "is ungenerous: it withholds information, and demands a query,"
  and calls for "rich, browsable interfaces that reveal the scale and
  complexity of digital heritage collections"
  ([DHQ 9.1](https://dhq.digitalhumanities.org/vol/9/1/000205/000205.html), read).
  He builds on Shneiderman's "overview first, zoom and filter, then
  details-on-demand" and prefers several partial overviews (he calls it
  parallax) to one definitive view.
- **His cases (read, same paper).** *Manly Images* clusters about 7,000 local
  photographs by decade and title words; each tile is both preview and
  overview. *Australian Prints and Printmaking* has three linked views: a
  sortable tile array of artists, a **decade summary** bar graph, and an
  artist's **network of collaborators**. *Discover the Queenslander* has a
  **mosaic by year** and a grid with cross-linked facets.
- **Why it works.** The overview answers "what is here, and how much" before a
  person has to name anything, which is exactly what a newcomer to radio
  drama cannot do (they do not know "Suspense" or "Lux").
- **Ear Drama's data.** Supports it: decades from dates (66% of episodes via
  their series, 49% directly), genre (67.5% of episodes), people and their
  co-credits, and an episode count everywhere. The decade summary and the
  collaborator network are both buildable from the projection as it stands.
- See also the Digital Treasures program at the University of Canberra
  ([canberra.edu.au](https://canberra.edu.au/research/news/news-listing/digital-treasures)).

### 2.2 Museum collections

- **Cooper Hewitt.** Browse by color arrived in February 2013: each image's up
  to five dominant colors snapped to the nearest of 121 CSS colors, because
  "our databases aren't set up for doing complicated color math"
  ([Labs, Feb 2013](http://labs.cooperhewitt.org/2013/02/), read). Late-2013
  usage reported 48.89% of visits using color navigation and 2.24% the random
  button ([Labs, Dec 2013](https://labs.cooperhewitt.org/2013/12/), via search
  summary). **Lesson:** a visible, playful facet that needs no vocabulary gets
  used; pure chance barely does. Ear Drama's equivalents of color are the
  genre hues (already content color, Decision 064) and the decade.
- **Rijksmuseum.** Rijksstudio opened about 125,000 works in 2012 and invited
  people to collect and make from them
  ([infoDOCKET](https://www.infodocket.com/2012/10/31/amsterdams-rijksmuseum-launches-digital-collection-of-125000-masterpieces-online/));
  the 2025 Fabrique and Q42 collection site won a European Design Award for
  "explore the collection online, collect your personal favorite objects"
  ([European Design Awards](https://awards.europeandesign.org/winner/261930)).
  **Lesson:** a person's own collection is a finding tool for the next person.
  Its crops are art-directed per image (`artwork-presentation-design`), which
  Ear Drama cannot afford; its idea of personal galleries it can.
- **The Met.** About 400,000 of over two million objects are viewable online
  ([UC Merced guide](https://libguides.ucmerced.edu/gasp156E-deprano/images));
  the Heilbrunn Timeline of Art History pairs **chronologies by region** with
  essays and works, keyed by period, place, material and subject
  ([Met, Timeline](https://www.metmuseum.org/toah)). **Lesson:** a timeline is
  an index into the collection, not a decoration. Ear Drama has no essays (and
  writes none, R13), but its chronology is data.

### 2.3 Libraries and archives

- **Library of Congress National Jukebox.** Browse All Recordings, Artists,
  Genres, and **"Jukebox Day by Day"**, what was recorded on each calendar day
  ([loc.gov](https://www.loc.gov/collections/national-jukebox/about-this-collection/browse-all-recordings/);
  [St. Thomas Libraries](https://blogs.stthomas.edu/libraries/?p=2829)), plus
  facets for place, date range, label, composer and performer
  ([infoDOCKET](https://www.infodocket.com/2011/05/10/lc-announces-the-national-jukebox-largest-collection-of-recordings-ever-made-available-to-public-free/)),
  and short staff-made playlists of 7 to 18 recordings
  ([Perspectives on History](https://www.historians.org/perspectives-article/national-jukebox-may-2011/)).
  The closest precedent to Ear Drama: an old audio collection, mostly
  unfamiliar names, found by day, by person, and by a few human selections.
- **Harvard StackLife.** A virtual shelf over 12.3 million items in 73
  libraries, ranked by "shelfrank" (community use), built for "structured
  serendipity"
  ([Harvard Gazette](https://news.harvard.edu/gazette/story/newsplus/stacklife-visually-browse-millions-of-harvard-library-materials/);
  [Zuckerman](https://ethanzuckerman.com/2010/11/09/kim-dulin-and-david-weinberger-hacking-the-library/)).
  **Lesson:** neighbors are a finding aid. A library shelf shows what sits
  beside the thing you came for; Ear Drama's neighbors are the same night, the
  same voice, the same script.
- **Unlocking the Airwaves (NAEB radio, University of Maryland).** Facets on the
  left; Browse Programs alphabetically; Browse People; Browse Organizations
  ([unlockingtheairwaves.org](https://www.unlockingtheairwaves.org/explore/),
  read). A competent but ungenerous radio archive: it demands that you know a
  program or person.
- **archive.org itself.** The `oldtimeradio` collection holds 9,014 items
  (advancedsearch `numFound`, measured 2026-10-29) shown as a tile grid of
  uploaders' covers sorted by views, with year, creator, subject and language
  facets (**UNVERIFIED** in this session: the page did not render to the
  fetcher). Its finding unit is the upload, which is why Ear Drama's tail of
  one-item "series" exists.
- **BBC Genome** puts every Radio Times listing from 1923 to 2009 online: pick a
  channel or station, then a date, or browse by printed issue
  ([Engadget](https://www.engadget.com/2014-10-16-bbc-genome-radio-times.html);
  [BSHS](https://bshs.org.uk/using-the-bbc-genome-project-for-cultural-history/)).
  The listing *is* the interface.

### 2.4 Period radio guides and logs

- **Newspaper logs** ran by station and hour; size varied from a single daily
  column to six on Saturday, with a separate "best bets" column, and the New
  York Times ran a full page of the week's programs on Sunday
  ([Variety Radio Directory 1939, Lantern](https://lantern.mediahist.org/catalog/varietyradiod19391940vari_1012)).
  JJ's Newspaper Radio Logs holds over 45,000 such logs from four papers,
  1930-1960 ([jjonz.us](https://www.jjonz.us/RadioLogs/)). **Lesson:** a
  listener in 1944 found a program by *when*, with an editor's "best bets"
  beside the grid. The human pick and the complete grid lived side by side.
- **Radio Times** went from three to four listing columns in January 1934
  ([Wikipedia](https://en.wikipedia.org/wiki/Radio_Times)); a dense, typeset
  page that people kept all week.
- **Collector logs.** Jerry Haendiges' 500-plus series logs list each series'
  broadcasts in date order with notes on date and time changes
  ([otrsite.com](https://otrsite.com/); [Quiet Please forum](https://quietplease.org/forum/general/-logs-compared-and-the-results-352.html)),
  and the OTRR's guide to compiling one says to record dates chronologically,
  number episodes, and trust dates over weekdays
  ([otrr.org](https://otrr.org/Files_Reference/HowToCompileASeriesLog.htm)).
  The series page is already a log (R1); the log's own visual form, a run of
  dates with its gaps, is the missing overview.

### 2.5 Streaming and audio apps

- **Criterion Channel.** Programmed like a repertory cinema: collections,
  double bills, director series, most with video introductions; Home is "Now
  Playing", with "see all" into each collection
  ([AP via KATV](https://katv.com/news/entertainment/at-criterion-channel-programming-a-movable-movie-feast);
  [TechHive](https://www.techhive.com/article/578344/criterion-channel-review.html)).
  **Works** because a named human stands behind every row. Ear Drama may only
  use a human editor (no AI-written lists), so this is a staffing choice, not
  a layout.
- **Apple Podcasts.** Browse: new, trending, and editorial collections; more
  than 100 categories; Home's "You Might Like" with Suggest Less on a show,
  category or channel
  ([Apple Support](https://support.apple.com/guide/podcasts/pod53101237/1.1.0/mac/15.0);
  [AppleInsider](https://appleinsider.com/articles/23/06/20/apple-podcasts-gets-big-improvements-with-expanded-categories-more)).
  **Lesson:** the person can correct the ranking. Ear Drama ranks nothing
  personally today, which is fine; anything it adds must carry the same
  inspectable correction (`values-based-feed-ranking` §2).
- **BBC Sounds.** Launched in 2018 with collections ("Funny Chat", "Dance
  Mixes") and categories, later grown from 12 to 40
  ([Engadget](https://www.engadget.com/2018-06-26-bbc-sounds-on-demand-radio-podcasts-app.html);
  [RAIN News](https://rainnews.com/?p=25816)); an early review faulted it for
  "no station scheduling", and a user called it designed "based upon podcast
  use rather than a radio station"
  ([Stuff](https://www.stuff.tv/?p=547848), via search summary). **Lesson:**
  even the BBC lost the schedule when it moved to shelves. Ear Drama's schedule
  (Stations) is its distinction; do not let shelves bury it.
- **Pocket Casts.** Discover = Featured (people at Pocket Casts), Trending, Top
  100, Popular in your country, Categories, guest lists, network highlights
  ([Pocket Casts support](https://support.pocketcasts.com/article/subscribing-to-podcasts/);
  [MacStories](https://www.macstories.net/?p=34785)). Editorial and data
  surfaces are labeled as such.
- **Spotify.** Home is "rows of cards grouped into shelves" chosen per person by
  machine learning
  ([Spotify Engineering](https://engineering.atspotify.com/2020/1/for-your-ears-only-personalizing-spotify-home-with-machine-learning));
  a 2026 preprint generates shelves from hypotheses with an optional LLM pass
  ([arXiv 2607.25823](https://papers.cool/arxiv/2607.25823)). Shelves work when
  a ranking model fills them for one person. Ear Drama has no such model and
  rejects AI-written lists, so a shelf here is a fixed rule over data: it
  shows the same six items to everyone, the "generic firehose" tell
  (`values-based-feed-ranking` §2).
- **Netflix** treats the homepage as page generation: rows ranked for utility
  and diversity under device limits, measured by how many relevant titles sit
  in the first M rows and N columns
  ([Netflix Tech Blog, archived](https://gwern.net/doc/www/netflixtechblog.com/2f5717e8bbdc98d2caf5c7a972359fbb7e7c0b28.html)).
  The metric admits the weakness: most of a row is never seen.

### 2.6 Catalogs of things people collect

- **Discogs.** Search filters by genre, style (a narrower tag under genre),
  year, country, label and format, combinable without a keyword
  ([Discogs support](https://support.discogs.com/hc/en-us/articles/360003622014-How-To-Browse-Search-In-The-Database)),
  and an artist page groups credits by role ("Production", "Remixes", "Appears
  On") ([Discogs credits guideline](https://support.discogs.com/hc/en-us/articles/360005006834)).
  **Lesson:** at catalog scale the facet *is* the browse, and a person's page
  is a filmography by role. Ear Drama's person page (WEB §4.14) already groups
  by series with roles; it lacks a way *in* from Browse.
- **Letterboxd.** Browse by year and decade, by genre, by popularity this
  week, month, year and all time, and people's lists
  ([Davenport Library](https://blogs.davenportlibrary.com/reference/2019/02/25/)).
  Lists made by people are the main finding surface.
- **Are.na.** Channels, blocks and connections; no feed algorithm; a block can
  live in many channels and connections are public
  ([Wikipedia](https://en.wikipedia.org/wiki/Are.na);
  [Are.na help](https://help.are.na/getting-started/channels)). **Lesson:**
  a person's collection, connected to others', is a discovery graph without
  ranking. For Ear Drama: a listener's station (their kept episodes, in an
  order they chose) that another person can open.

### 2.7 Maps and playful overviews

- **Radiooooo.** Pick a decade (1900 to now) and a country on a map; a random
  track plays; the map recolors to show where tracks exist for that decade
  ([Open Culture](https://www.openculture.com/2018/04/radiooooo-the-musical-time-machine.html);
  [Laughing Squid](https://laughingsquid.com/radiooooo-interactive-music-player/)).
  Chance inside a chosen scope, with the overview telling you which scopes
  are full.
- **Radio Garden.** A globe of about 14,000 live stations as dots; spin and
  tap ([Cesium](https://cesium.com/blog/2019/07/19/radio-garden/);
  [NPR](https://www.npr.org/transcripts/506045527)). Ear Drama has no
  geography worth a map (network and station call letters, not places), so
  the map metaphor transfers as a **decade-by-genre field**, not a globe.
- **Every Noise at Once.** A scatter of thousands of genres with meaningful
  axes; click to hear, click again for that genre's artists
  ([Wikipedia](https://en.wikipedia.org/wiki/Every_Noise_at_Once);
  [FlowingData](https://flowingdata.com/2016/07/05/graphing-all-the-music/)).
  Delightful, illegible at 375 px, and its axes come from audio analysis Ear
  Drama does not have. Refuse.

### 2.8 The techniques

- **Information scent.** Pirolli and Card model people as foragers who follow
  proximal cues (labels, pictures, counts) toward the patch most worth their
  time ([Wikipedia, Information foraging](https://en.wikipedia.org/wiki/Information_foraging)).
  Generic labels carry no scent. For Ear Drama, scent is a famous voice, a
  year, a genre hue, "516 episodes"; not a network list.
- **Faceting.** Hearst's Flamenco studies: in a 35,000-image collection, 90% of
  32 art history students preferred hierarchical facets to plain search;
  people browsed for open tasks and searched when they knew the target;
  multiple facets beat one hierarchy; simplicity wins unless complexity pays
  ([Yee et al., CHI 2003](https://courses.cs.washington.edu/courses/cse454/13wi/papers/yee-chi03.pdf);
  [Hearst, CACM 2002](https://bailando.berkeley.edu/papers/cacm02-final.html)).
- **Progressive disclosure** (`mobile-first-density-design` rule 5): a row with
  a chevron pushes, one without inlines; the row shows what decides, the page
  shows the rest.
- **Small multiples and word-sized graphics.** A sparkline is "a small intense,
  simple, word-sized graphic with typographic resolution"
  ([Tufte](https://www.edwardtufte.com/notebook/sparkline-theory-and-practice-edward-tufte/)).
  A run of a series across 1930-1960 is exactly that size.
- **Choice overload** is real only in context: the 24-jam table sold less than
  the 6-jam one ([PBS](https://www.pbs.org/newshour/economy/is-the-famous-paradox-of-choic)),
  but a meta-analysis of 50 experiments found a mean effect near zero with
  large variance ([Scheibehenne et al. 2010](https://abcwest.cogs.indiana.edu/pmwiki/pdf/scheibehenne.options.2010.pdf)).
  The design reading: a big catalog is not the problem; an unstructured one is.
- **Serendipity** is not chance alone: André, schraefel, Teevan and Dumais argue
  chance encounters must be "synthesized into insight," and that design has
  over-served the encounter and under-served the insight
  ([André et al. 2009](https://eprints.soton.ac.uk/267710/1/fp392-andre.pdf)).
  Surprise should hand a person a *reason* (the same night, the same voice),
  not just a random episode.
- **Editorial vs data-driven.** Every product above that people praise labels
  which is which (Pocket Casts' Featured vs Trending, Criterion's programmer,
  the Jukebox's staff playlists). Ear Drama's rule (no AI-written lists or
  copy) means editorial = a named human; everything else = a rule over data,
  shown as the rule.

---

## §3 Audit of today's Find surfaces (web, 375 px)

Shot 2026-10-29 against the live site and data (`https://eardrama.org`, data
generated 2026-10-29T16:30Z), light mode, through a 375 px iframe served on
port 8791 and captured by Chrome's DevTools protocol after a 9-second real
wait (virtual time left the data unfetched). Each image is the top 1,800 px.

| Surface | Image |
|---|---|
| Home | `/Users/bhwilkoff/Documents/GitHub/Ear-Drama/.claude/worktrees/agent-aea407cd9119f3de5/docs/research/design/img/d1a/home.png` |
| Browse | `/Users/bhwilkoff/Documents/GitHub/Ear-Drama/.claude/worktrees/agent-aea407cd9119f3de5/docs/research/design/img/d1a/browse.png` |
| Browse, Mystery | `/Users/bhwilkoff/Documents/GitHub/Ear-Drama/.claude/worktrees/agent-aea407cd9119f3de5/docs/research/design/img/d1a/browse-mystery.png` |
| Stations | `/Users/bhwilkoff/Documents/GitHub/Ear-Drama/.claude/worktrees/agent-aea407cd9119f3de5/docs/research/design/img/d1a/stations.png` |
| Search, "sorry wrong number" | `/Users/bhwilkoff/Documents/GitHub/Ear-Drama/.claude/worktrees/agent-aea407cd9119f3de5/docs/research/design/img/d1a/search.png` |
| Series, Gunsmoke (portrait) | `/Users/bhwilkoff/Documents/GitHub/Ear-Drama/.claude/worktrees/agent-aea407cd9119f3de5/docs/research/design/img/d1a/series-gunsmoke.png` |
| Series, Suspense (typographic card) | `/Users/bhwilkoff/Documents/GitHub/Ear-Drama/.claude/worktrees/agent-aea407cd9119f3de5/docs/research/design/img/d1a/series-suspense.png` |

The same files are committed under `docs/research/design/img/d1a/` (1.1 MB in
all).

### 3.1 What a person sees first

- **Home**: three sections that look the same (This day in radio, Most
  downloaded, Drama), each six identical rows and "Show all 20". In the first
  1,800 px: 15 rows, 15 play buttons, 9 letter tiles, 6 faces. No sense of how
  big the catalog is or what else exists. Most downloaded lists each series'
  *earliest* episode, so the most popular shows are introduced by their
  auditions ("Audition program", "CBS Forecast-The Lodger-Suspense audition").
  This day in radio repeats one broadcast under two series ("Wild West of 1933"
  in Front Page Drama and The Golden Age of Radio).
- **Browse**: five selects and a checkbox take the first 290 px; then "10,642
  series · 15 plays", a count dominated by single recordings. Rows are good on
  the famous shows and noisy on long network lists.
- **Series page**: the right bones (a log in date order, R1). The season chips
  ("1948-49") scroll sideways and hide how the run is shaped; at 1,101
  episodes (Suspense) there is no overview of where the gaps are.
- **Search**: the four "series" for "sorry wrong number" are uploads (a Decca
  record, a 1943-1949 compilation, an RTÉ copy, a one-file "series"), shown
  above the eight real Suspense performances; the episode list then shows
  "NETWORK", "NETWORK WC" and "East Coast" variants as separate results.
- **Stations**: eight equal "Listen live" buttons in ink, the primary action's
  color, form a column of eight primaries; "Tonight in 1945" appears twice
  (the row and the section heading); the schedule is mostly gap rows (10 of the
  first 13 slots "Not surviving").

### 3.2 Field inventory

Keep = stays in the row. Detail = moves to the item's page. Cut = removed from
this surface (the data stays).

**Home rows (This day in radio, Most downloaded, genre shelves)**

| Field | Example | Mark | Reason |
|---|---|---|---|
| Section heading | "This day in radio" | Keep | names the rule (R13), carries scent |
| Today's date beside the heading | "October 29" | Keep | the fact that makes the shelf make sense |
| Letter tile | "C" on the genre hue | Cut in rows (needs a rule change in `artwork-presentation-design` §3 first) | one letter is no scent; on a genre shelf every tile is the same hue, so it says nothing the heading did not |
| Face (series star) | Jack Benny | Keep | the strongest scent the data has |
| Full air date | "1933-10-29" | Keep as the year alone on This day ("1933"); Detail on genre and Most downloaded shelves | the month and day are already in the heading; on a genre shelf the date of a first episode is trivia |
| Episode title | "Miss Tucker Tells Cecil and Sally About the Letter pt2 (C)" | Keep (clean titles in the pipeline) | the identity of the item; the suffixes "(C)", "(OTR)", "pt2" are copy noise from file names |
| Series name | "Cecil And Sally" | Keep | needed on a mixed list |
| Length | "4 min" | Keep | bedtime and car decisions |
| Play glyph | the triangle | Keep | one-tap listening is the Listen job |
| "Show all 20" | | Keep | predictable disclosure |
| Most downloaded as episodes | Gunsmoke's audition | Cut as episode rows; show the series (face, name, years, count) | the rule ranks series; showing its first episode misrepresents the show |

**Browse controls and rows**

| Field | Example | Mark | Reason |
|---|---|---|---|
| Kind select | "Any kind" | Cut from the first screen (one filter sheet or one chip row) | 15 plays in 10,642 rows; a whole select for a 0.1% slice |
| Genre, Decade, Network selects | | Keep as one row of counted chips, or a filter sheet | facets with counts are the evidence-backed browse (Hearst); four labeled selects cost 220 px before any content |
| Sort select | "Popular" | Keep, smaller | |
| "Has a script (0)" under Mystery | | Cut when zero | WEB-DESIGN §4.3 says no offered choice yields zero rows; this one does |
| Total | "10,642 series · 15 plays" | Keep, counting shows (10+ episodes, §4.1) | the true count of what Browse means, with the rest one tap away |
| Face or letter tile | | Keep the face; letter tile as today until the rule changes | |
| Series name | "Gunsmoke" | Keep | |
| Network list | "NBC, NBC Red, Blue, NBC Blue, ABC Blue, AFRTS, Bllue" | Detail | 9.7% coverage, up to seven strings, misspellings; no chooser picks a show by "NBC Blue" |
| Year range | "1941–1999" | Keep, as the core run computed from dated episodes | today's range includes rebroadcasts and misdated copies |
| Episode count | "516 episodes" | Keep, as the bare number with the run strip (§4.2) | how much there is to explore |

**Series page**

| Field | Mark | Reason |
|---|---|---|
| Face or typographic card, caption with the star's name | Keep | Decision 069 |
| Genre link | Keep | the way back out to a facet |
| Networks, years, episode count | Keep (this is the detail page) | |
| Follow, Share | Keep | Find and Share jobs |
| Season chips | Keep, under a run strip that shows every year at once | chips hide the run's shape past the fourth |
| "516 episodes" above the list | Cut (repeated from the head) | said twice in 300 px |
| Row: date, title, length, play | Keep | the log |
| Row: a guest star's name when the episode's credited face differs from the series star | Add, candidate (§4.4) | the strongest scent in an anthology (Lux, Suspense) |
| Title noise ("Aud01 ... [modified]", "Ep004", "(Project Audion 2023)") | Cut in the pipeline | copy from file names; "RECREATION ... (Project Audion 2023)" is a modern recreation inside a 1942 run, which needs a curation call, not a display fix |

**Search**

| Field | Mark | Reason |
|---|---|---|
| Series results | Keep, ranked shows first, single recordings after episodes | uploads outranked the real series |
| Episode rows: tile, date, title, series | Keep | |
| Same script performed many times | Group (one row per performance date under the script's title, §4.7) | "Sorry, Wrong Number" is eight performances, shown as twelve rows |
| "25 episodes" count | Keep | |

**Stations**

| Field | Mark | Reason |
|---|---|---|
| Station name (genre) | Keep | |
| Now on: series, title | Keep | the live hook |
| Face or tile | Keep the face, letter tile per the rule | |
| "Listen live" button on every row | Change to one control per row in an outline or plain style; the whole row tunes | eight ink primaries in one column break "the primary action is ink" (one primary per view) |
| "Tonight in 1945" twice | Cut the duplicate heading | said twice on one screen |
| "Starts at 5:00 PM" | Keep | a fact the person cannot see |
| Local time and ET | Keep (ET only where they differ, as today) | |
| Consecutive gap rows | Merge runs of gaps into one row ("7:00-7:30 PM, not surviving") | R9 says draw the gap; it does not say draw it per quarter hour |
| The year select | Keep | |

---

## §4 Candidate patterns, ranked

Ranked by how much of the Find job each serves for how little data it needs
that does not yet exist. Costs are S (days), M (a week), L (more), per
platform, assuming the pipeline work is done once.

### 4.1 The two-tier catalog: shows first, recordings findable (rank 1)

**What it is.** Browse, its counts and its default sort cover the 1,374 series
with ten or more episodes (or a threshold the owner sets; 5 gives 2,037). The
other 9,268 rows are one counted scope, "Single recordings (7,189)" and
"Small series", reachable from the same filter row and always in Search, below
the shows. This is `values-based-feed-ranking` §5 applied to *structure*:
never hidden, never the default.

- **Surfaces:** a truthful total ("1,374 shows"); facets whose counts mean
  shows; Search that puts Suspense above a Decca record.
- **Hides:** nothing is removed; uploads leave the first screen.
- **Data:** exists (`episodes` per series). The threshold belongs in the
  pipeline (`shelves.py`-style rule, one predicate for every client).
- **Precedent:** Hearst (counts that mean something), Discogs (master release
  vs its pressings, UNVERIFIED as a layout), StackLife (rank by use).
- **Costs:** pipeline S (a `tier` field or a published threshold); web S;
  iOS/iPadOS S; macOS S (shares Core); tvOS S; Android S.
- **Learning test:** passes; it makes the domain legible ("shows" vs "copies")
  instead of hiding it.

### 4.2 The run strip: a word-sized history on every series row and head (rank 2)

**What it is.** Replace "CBS, NBC · 1949–1961 · 516 episodes" with the name, the
core years, the count, and a sparkline-sized strip of surviving episodes per
year across the golden age (1930-1962, one tick per year, height by count),
in the genre hue. On the series page the same strip, larger, is the season
scope: tap a year to jump. Tufte's sparkline; Whitelaw's decade summary; the
collector's log made visible.

- **Surfaces:** the shape of a run at a glance (Suspense's twenty years, Dark
  Fantasy's one), where the gaps are, which decade a show belongs to, without
  a network list.
- **Hides:** networks and exact first and last dates move to the page.
- **Data:** needs a per-series histogram (count of dated episodes per year)
  published in `index/series.json`; the dates exist for 71% of episodes in
  shows. The core years should be the 5th to 95th percentile of dated
  episodes, not first and last, which also fixes Inner Sanctum's "1999".
- **Costs:** pipeline S; web S (inline SVG or CSS grid); iOS/iPadOS M (Swift
  Charts or a Canvas; VoiceOver needs a summary label such as "aired 1942 to
  1962, most in 1948"); macOS S after iOS; tvOS M (the strip must read at ten
  feet: draw it only on the focused card); Android M (Compose Canvas, a
  semantics description).
- **Learning test:** passes strongly; it teaches the history while choosing.

### 4.3 Voices: a wall of faces as a way in (rank 3)

**What it is.** A Browse scope (and a Home section) of the most-heard people
with a served portrait, as a grid of faces at their own shape (crop at the
published face box for tiles, `artwork-presentation-design` §3), each with the
name and the episode count. Tapping opens the person page (WEB §4.14), which
becomes a Discogs-style filmography by series and role, plus "heard with": the
people most often credited on the same episodes. Whitelaw's "Works and
Networks"; Letterboxd and Discogs person pages.

- **Surfaces:** the 613 frequently heard people with portraits (227 of them on
  100+ episodes); the app goes from mostly letter tiles to mostly faces
  without loosening Decision 069.
- **Hides:** people without a portrait stay in Search and on credits; the wall
  is a rule over data ("most episodes, with a portrait") and says so in its
  heading.
- **Data:** exists (`search/people/` with episodes and art). "Heard with" needs
  a co-credit count per person in `people/{shard}.json` (pipeline M). Two
  defects block quality: duplicate people (Bud Collyer twice) and Goldin
  cast-list "people" (contract §4).
- **Costs:** pipeline S for the wall, M for "heard with"; web S; iOS/iPadOS S
  (LazyVGrid); macOS S; tvOS M (a face shelf is the native idiom there, with
  focus scale); Android S (LazyVerticalGrid).
- **Learning test:** passes; people are the domain's real vocabulary (who
  Virginia Gregg was is the kind of thing a listener learns here).

### 4.4 The day, not the shelf: a calendar into the archive (rank 4)

**What it is.** "This day in radio" becomes a **date you can move**: today by
default, with the years that day survives in shown as a strip (28 to 37
years; the busiest marked), and one tap into a single date ("October 29,
1944: 21 surviving broadcasts") laid out as that night's listings, by time
where known, else by series. Stations' newspaper evenings stay the gold
standard; this is the everyday, data-only version for any date. National
Jukebox's "Day by Day"; BBC Genome; the newspaper log.

- **Surfaces:** the date as identity (49% of episodes), the coincidences that
  make radio history vivid (a comedy and a war bulletin on the same night),
  an answer to "what was on the night I was born" for anyone born before 1962.
- **Hides:** undated episodes (51%) are absent from this view by definition;
  they stay in series and Search.
- **Data:** exists (`index/days/`, 366 files, each with date, series and
  length). A year-and-date route (`?date=1944-10-29`) needs a path twin
  (`/date/1944-10-29`, DEEP_LINKS.md) and a per-date index or a client filter
  over the day file. Hours of air are not in episode rows, so the night is
  ordered by series unless a matched evening exists.
- **Costs:** pipeline S; web M (a date picker plus the listing view);
  iOS/iPadOS M (a `DatePicker` constrained to dates with broadcasts, a new
  route); macOS S after iOS; tvOS M (a year strip as a focusable row; no free
  date entry); Android M (Material date picker, a new route). Each platform
  adds one deep link.
- **Learning test:** passes strongly; it is the radio evening idea (05 §4)
  extended to every date.

### 4.5 The decade-by-genre field: one overview of the whole (rank 5)

**What it is.** A small matrix, eight genre columns (their hues) by four or five
decade rows, each cell a count of shows, shaded by size; tap a cell to open
Browse with both facets set. It replaces Browse's empty first screen with a
picture of the archive's shape (the 1940s mystery boom, the 1950s science
fiction, comedy's 1930s), and it is the "map" the owner's ask suggests, built
from what Ear Drama actually has. Radiooooo's decade-and-place; Whitelaw's
parallax overviews; Cooper Hewitt's color as a no-vocabulary facet.

- **Surfaces:** the whole catalog in about 320 by 200 px; the genre hues earn
  their meaning.
- **Hides:** the 34,911 episodes with no genre need an honest "Unsorted" column
  or a count beside the field; never pretend the field is complete.
- **Data:** exists (genre and decade per series; decade should come from the
  core years of §4.2). Counts must be the published facet counts, so the field
  and Browse agree.
- **Costs:** pipeline S (publish the matrix); web S (CSS grid); iOS/iPadOS S
  (`Grid`); macOS S; tvOS M (a focus grid with a clear focused cell, each cell
  a button); Android S (LazyVerticalGrid of fixed columns).
- **Learning test:** passes; it is an overview a person reads, not a pick made
  for them.

### 4.6 Surprise inside a scope (rank 6)

**What it is.** Surprise draws within whatever the person has chosen: a cell of
the field, a decade, a person, a date. The pick arrives with its reason as a
fact ("Same night: October 29, 1944", "Also with Virginia Gregg"), never as
written copy. Cooper Hewitt's numbers (random 2%, facet 49%) and Radiooooo's
design say chance works inside a scope; André et al. say the encounter needs
a reason to become insight.

- **Surfaces:** serendipity people can steer.
- **Hides:** nothing.
- **Data:** exists; the draw stays `Math.random()` per platform (WEB §4.13).
- **Costs:** web S; iOS/iPadOS S; macOS S; tvOS S; Android S.
- **Learning test:** passes; it supports agency over the draw.

### 4.7 One script, many performances (rank 7)

**What it is.** Where the same title is performed on several dates or by several
series, Search and the series page show one row for the script with its
performances beneath as dates (and their stars): "Sorry, Wrong Number, 8
performances, 1943-1960". 05 §Verdict 3's Work, Broadcast, Recording model
made visible.

- **Surfaces:** the radio repertory (scripts that came back), a way to compare
  the 1943 and 1957 performances.
- **Hides:** copy variants ("NETWORK", "WC", "East Coast") fold into versions
  on Detail.
- **Data:** does not exist as a published key; it needs a work id from title
  normalization plus OTRR logs, checked per series, with
  `evidence-gated-catalog-curation`'s wrong-match discipline. Pipeline L.
- **Costs:** pipeline L; web M; iOS/iPadOS M; macOS S after iOS; tvOS M;
  Android M.
- **Learning test:** passes strongly, but only once the matches are trustworthy.

### 4.8 Listener-made stations and a named editor's picks (rank 8)

**What it is.** A person's kept episodes in their own order, shareable as a
station another person can open (Are.na channels, Rijksstudio galleries,
Letterboxd lists); and, separately, a small set of collections signed by a
named human editor, like the Jukebox's staff playlists or Criterion's
programmer. Both answer "where do I start" with a human, which the no-AI-copy
rule demands.

- **Surfaces:** the Share job inside the Find job.
- **Hides:** nothing; but an editor's collection with no editor is an empty
  promise, so this waits on a person to do it.
- **Data:** listener stations need the sync islands and a public share format
  (`per-ecosystem-sync-islands` or `zero-cost-hosted-backend`, Decision 047);
  editorial collections need a human-edited file in `catalog/`.
- **Costs:** backend M-L; web M; iOS/iPadOS M; macOS S; tvOS S (read only);
  Android M. Needs owner rulings (who edits; whether listener stations are
  public).
- **Learning test:** passes; participation is the point.

### Refused

- **A globe or network map.** Network and call letters are not places a person
  navigates by; Radio Garden's globe works because live stations are places.
- **An Every Noise-style scatter.** Illegible at 375 px; its axes need audio
  analysis Ear Drama does not have.
- **Personalized shelves.** No ranking model, no AI-written lists; a rule shelf
  shown to everyone is the generic firehose in miniature.

---

## §5 Which metadata belongs where (the rule for D2)

- **In a list row**: the face if one exists; the title; on mixed lists the
  series; the year (episode lists: the full date in tabular figures); length;
  for a series, the core years, the count, and the run strip; a part number in
  an arc; at most one guest name when it differs from the series' face.
- **Only on the item's page**: networks, sponsor, writer, director, announcer,
  the full cast, copies and formats, the rights line, the transcript, the
  download count.
- **Never in a row**: a field under about a third coverage on that surface
  (network on a series row, sponsor anywhere), a list of more than two values,
  anything that repeats the section heading.

## Seen on the way

| Where | Symptom | Proposed fix | Owner ruling? |
|---|---|---|---|
| `index/series.json` first/last | Escape's earliest episode is dated 1921-09-25 (it began in 1947, general knowledge, UNVERIFIED here) and is published as its `genreFirsts` and `mostDownloaded` pick; The Whistler starts 1931 (began 1942, UNVERIFIED here) | Core years from percentiles; audit dates before a series' known premiere | no |
| Series star (Decision 069 rule) | Boston Blackie wears Lesley Woods, The Adventures of Sam Spade and Philo Vance a supporting actress: the rule picks the most-heard face, which in a detective show can be the secretary | Prefer the credit role "star" or the title role when credits name one; else keep the card | yes (face rule) |
| `search/people/` | "Clayton 'Bud' Collyer" (1,158) and "Bud Collyer" (1,105) are two people | Merge on the Wikidata match in `enrich_db.py` | no |
| Browse, Mystery | "Has a script (0)" is offered | Hide a zero facet (WEB §10.5) | no |
| `index/series.json` `scripts` | 0 for every series, while Browse says "Has a script (15)" (plays only) | Check the web builder's `scripts` count | no |
| Home, This day in radio | "Wild West of 1933" listed twice, in two series | Dedupe by recording (same archive.org file) across series | no |
| Home, Most downloaded | Popular shows introduced by their auditions | Show the series, or its first regular episode | yes (what a shelf shows) |
| Suspense series page | "RECREATION ... (Project Audion 2023)" sits in the 1942 run | A modern recreation is a version or its own series, not a 1942 broadcast | yes (curation) |
| Stations | Eight ink "Listen live" buttons in one column | One primary per view; rows tune | no |

## Reproducing the measurements

Scripts, all in the session scratchpad
`/private/tmp/claude-501/-Users-bhwilkoff-Documents-GitHub-Ear-Drama/3500bd8e-5556-4177-ae20-9f6ead58871b/scratchpad/d1a/scripts/`:
`measure_series.py` (series index), `fetch_shards.py` and
`measure_episodes.py` (every 16th Detail shard), `measure_people.py`,
`measure_days.py`, and `cdp_shoot.mjs` (the screenshots: Chrome headless with a
debugging port, a real wait, a 375 px clip of an iframe page served from
`shots/frame.html` on port 8791). The data they read is under
`.../scratchpad/d1a/data/`. Numbers above are from the projection generated
2026-10-29T16:30:38Z; the tests rule (never pin catalog contents) applies to
anything built from them.
