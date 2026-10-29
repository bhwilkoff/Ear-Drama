# D1b: The single item and listening

*Research date: 2026-10-29. Design loop phase D1b (`DESIGN-LOOP.md`). Status:
research, no code changed. Skills followed: `mobile-first-density-design`,
`artwork-presentation-design`, `ten-foot-detail-design`,
`learning-orientation-design`.*

> **How to read this file.** Every number about Ear Drama was measured on
> 2026-10-29 from the live web projection at `https://eardrama.org/data/`
> (manifest `generatedAt` 2026-10-29T16:30:38Z, `cleanOnly: false`, so the web
> now serves the whole catalog: 107,369 episodes in 10,642 series). All 4,096
> Detail shards were downloaded and read, so these are counts, not samples.
> External claims cite the URL they came from. Most product pages refused a
> direct fetch from this session (BBC, Criterion, Discogs, the Met answered
> 403, 429, or "unable to fetch"), so most external facts come from web-search
> result summaries of the cited page, as in research 05. A claim marked
> **OBSERVED** is from general product knowledge and was not confirmed by a
> source in this session.

The owner's ask (2026-10-29): *"a lot more metadata being surfaced than is
necessary ... smart choices for what content to surface to create an easy to
use experience to ... Listen to them."*

---

## Verdict

1. **The catalog is mostly bare, and the screens are designed for the rich
   tenth.** 65.5% of episodes carry no credit, no network and no sponsor; only
   48.4% are dated; 5.1% carry all five of date, network, sponsor, cast and
   writer. A Detail page built around the Suspense case (16 credits, six copies,
   a transcript) is a wall for that tenth and a stub for the rest. The design
   has to look finished at both ends: **the bare page is the common page.**
2. **What people play is much richer than the average.** The 100 most-downloaded
   series hold 23,899 episodes; there 76% are dated, 65% carry a network, 56% a
   cast, 34% a writer, 30% a sponsor, 15% a transcript. So the listening screens
   should spend their care on the date, the network and the cast, which the
   played catalog actually has, and treat sponsor, writer and transcript as
   welcome when present.
3. **The broadcast is an event, and the data already says when and where.** A
   1943 Suspense reads as an event in one sentence ("CBS, Thursday, December 2,
   1943, for Roma Wines"), not in a facts line of five dot-separated fields
   with a season and a log number. And 95% of dated episodes share their air
   date with a surviving broadcast of another series (median three series a
   day), 28% with a news or documentary broadcast. "That night on the radio" is
   supported by data Ear Drama already publishes.
4. **Credits are liner notes, not the page.** 2,821 distinct role strings, a
   median of 9 credits on a credited episode (p90 16), and garbled or doubled
   entries mean the raw list should never be the page's body. Apple Music's
   three credit groups and a faces row do the job; the full list is one tap
   away.
5. **Copies are the archivist's view, not the listener's.** 31.7% of episodes
   have more than one copy, 20.4% three or more; the page lists every one with
   its archive.org identifier and bit rate. A listener needs one fact from that
   list: whether another copy is different (an Armed Forces rebroadcast, a
   different length, an incomplete copy). 7.3% of episodes have copies whose
   lengths differ by more than two minutes, and some of those are wrong matches.
6. **Now Playing is already calm; it is calm about the wrong things.** It shows
   the face, the series, the title and the date, then four equal-weight option
   buttons. It drops the network (the web only; iOS and tvOS show it), and it
   never shows who is on. Radio's picture is its people (research 05 §3.4).

---

## §1 Measured: what an episode and a series actually carry

Scripts: `measure.py` and `measure2.py` to `measure4.py` in the session
scratchpad; method above. Percentages are of all 107,369 served episodes unless
the row says otherwise.

| Field (contract §3.1, §4) | Episodes | Share | Top-100 series by downloads |
|---|---:|---:|---:|
| Air date (`date`, always a full `YYYY-MM-DD` when present) | 51,987 | 48.4% | 76% |
| Log number (`num`) | 60,589 | 56.4% | |
| Network | 33,813 | 31.5% | 65% |
| Any credit | 29,037 | 27.0% | 58% |
| Cast | 26,876 | 25.0% | 56% |
| A credit with a portrait | 24,644 | 23.0% | |
| An episode face (`star`) | 23,233 | 21.6% | 51% |
| Announcer | 17,594 | 16.4% | |
| Writer | 14,572 | 13.6% | 34% |
| Sponsor | 12,824 | 11.9% | 30% |
| Director | 12,655 | 11.8% | |
| Automatic transcript (gate passed) | 7,623 | 7.1% | 15% |
| Story arc part | 3,225 | 3.0% | 1% |
| A linked castable script | 0 on the web row | | |
| A character name on any credit | 216 | 0.2% | |
| Alternate title (`aka`) | 78 | 0.1% | |
| None of credit, network, sponsor | 70,363 | 65.5% | |
| All of date, network, sponsor, cast, writer | 5,491 | 5.1% | |

**Copies.** 1 copy: 73,286 episodes; 2: 12,160; 3: 7,044; 4: 5,151; 5 or more:
9,728. 34,083 (31.7%) have more than one; 7,823 (7.3%) have copies whose
lengths differ by more than 120 s. Variants among all copies: AFRS 3,000,
AFRTS 822, rehearsal 2. 1,657 episodes have an Armed Forces copy as the
default (no domestic copy survives); 1,561 have one as an alternate. No default
copy is marked partial.

**Credits.** Median 9 credits on a credited episode (p90 16, max 54); median 5
cast (p90 10, max 44); median 5 distinct roles (p90 8); median 3 portraits
(p90 7). 2,821 distinct role strings; the top: cast 143,958, writer 22,063,
announcer 19,553, director 13,922, producer 12,479, conductor 5,859, composer
4,934, creator 4,010, commercial spokesperson 3,753, adaptor 3,636, host 3,630,
doubles 3,277, music 3,170; also "tobacco auctioneer" 707 and "?" 535. 1,043
episodes carry a credit whose name is a fragment of a Goldin cast list (it
contains "(" or ";"), the problem contract §4 already names.

**Titles.** 3,784 episodes have an empty title, 2,173 a title equal to the series
key, 1,721 a date inside the title, 5,786 a title over 60 characters. The
series pages read the noise aloud: "Aud RobtWPerryCase", "Jacks1st Paying
McJob", "Who Killed Mr.XPt2Sherlock Holmes", "(OTR)" on half of Jack Benny's
1930s rows.

**Re-performances.** 6,552 episodes (6.1%) share a normalized title with another
dated episode of the same series: the proxy for "other performances of this
script" until the Work layer of research 05 §Verdict 3 exists. Not on the web
Detail row today.

**Series.** 10,642 served; 7,189 hold one episode, 190 hold 100 or more; 8,520
carry no genre; 271 carry a star portrait; 8,503 a download count.

**The same night.** Of 51,987 dated episodes, 49,413 (95%) share their date
with an episode of another series, and 14,767 (28%) with a news or
documentary episode. 11,029 distinct air dates; median 3 series a date (p90
10). Dated episodes by decade: 1920s 156, 1930s 6,432, 1940s 26,145, 1950s
16,769, 1960s 2,238, 1970s 247.

**Evenings.** `tonight.json` holds 15 days; each evening has 8 to 13 slots, of
which 1 to 3 carry a surviving episode (coverage 0.125 to 0.438). An evening
is mostly gaps: the "event" of a broadcast night is mostly the schedule, not
the audio.

**What the played catalog looks like** (selected series, share of its episodes):

| Series | Eps | Date | Network | Sponsor | Cast | Writer | Transcript | Copies >1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Suspense (anthology) | 1,101 | 88% | 88% | 45% | 81% | 61% | 64% | 85% |
| Gunsmoke | 516 | 95% | 95% | 0% | 87% | 85% | 75% | 93% |
| Lux Radio Theater | 747 | 74% | 71% | 0% | 68% | 1% | 0% | 72% |
| Yours Truly Johnny Dollar (serial arcs) | 939 | 81% | 80% | 8% | 76% | 53% | 0% | 78% |
| Jack Benny Program (comedy) | 950 | 92% | 91% | 90% | 70% | 60% | 0% | 80% |
| Fibber McGee and Molly | 1,599 | 79% | 79% | 79% | 73% | 67% | 1% | 76% |
| Cavalcade of America | 753 | 99% | 99% | 0% | 94% | 43% | 75% | 94% |
| Tarzan (all runs) | 269 | 84% | 80% | 0% | 2% | 2% | 0% | 14% |

Lux's 0% sponsor is a gap in the dated sponsor runs (Lux was Lever Brothers'
show by name), not a fact about the broadcasts; Gunsmoke's 0% may be the same
gap or its sustained years, which are never published (contract §3.1). A page
must never imply "no sponsor" from a missing field.

---

## §2 Precedents: what works, and whether Ear Drama's data supports it

### 2.1 Podcast and audiobook apps (episode, Now Playing, queue, continue)

| Product | What it does | Why it works | Ear Drama's data |
|---|---|---|---|
| **Apple Podcasts** transcripts (iOS 17.4, 2024) | Automatic transcripts by default for new episodes, back catalog over time; the transcript opens from Now Playing, and the current word is highlighted as it plays; chapter titles become the transcript's section headers ([MacRumors](https://macrumors.com/2024/01/26/ios-17-4-podcast-transcripts), [Apple Podcasters support](https://podcasters.apple.com/support/5316-transcripts-on-apple-podcasts), [iMore](https://www.imore.com/podcast/apple-podcast/transcripts-for-apple-podcasts-is-now-available-read-your-favorite-shows-as-you-listen-in-ios-174)) | The transcript is a second way into the same moment, reached from the player, not a page of its own; files that fail a quality bar are not shown, which is Ear Drama's transcript gate (Decision 058) | 7.1% of episodes (15% of the played top 100; Suspense 64%, Gunsmoke 75%). archive.org's `autogenerated.txt` is plain text (contract §3.1): **no timings**, so word highlighting is not possible from it. Whether archive.org also serves a timed file for these items is **to measure** |
| **Apple Podcasts** Up Next split (iOS 27.2) | "Up Next" splits into New Episodes and **Continue Playing**, a hub for every episode started and not finished ([9to5Mac](https://9to5mac.com/2024/12/10/ios-182-improves-apples-podcasts-app-but-my-biggest-complaint-is-unchanged)); iOS 18's mixed queue drew complaints of random episodes queued and played ([Apple Community](https://discussions.apple.com/thread/255770923), [Apple Community](https://discussions.apple.com/thread/256019629)) | Separating "what I started" from "what the app proposes" is what listeners asked for; an app that queues for them loses trust | Ear Drama already separates them: Continue on Home, Queue in Library, and the owner's queue rule (Decision 067) never starts anything the person did not ask for. Keep it |
| **Pocket Casts** Now Playing (v7, 7.6) | One page: art, transport, then show notes and chapters as swipeable tabs; Up Next its own screen, reached by swiping up or the queue counter ([MacStories](https://www.macstories.net/reviews/pocket-casts-7-a-host-of-improvements-make-the-app-feel-brand-new/), [Pocket Casts blog](https://blog.pocketcasts.com/2019/12/09/7-6-up-next-changes/), [support](https://support.pocketcasts.com/knowledge-base/playing-episodes-and-managing-your-queue/)) | The listening screen keeps the transport alone above the fold and puts reading (notes, chapters) one swipe away | Ear Drama has no show notes and no chapters (contract §3.2a: no source marks segments). Its second page would be **who is on** and the transcript |
| **Pocket Casts** chapters | Chapters from the file; for episodes without them, AI-generated chapters added automatically ([support](https://support.pocketcasts.com/knowledge-base/chapters/)) | Navigation inside a long file | **Refuse** the generated half: Ear Drama's rule is segment times are never estimated (contract §3.2a) and no AI-written lists |
| **Overcast** (2024 rewrite) | Rebuilt for speed and accessibility; reviewers manage listening through Recent episodes plus one Queue playlist ([MacStories](https://www.macstories.net/reviews/overcast-redesign-enhances-podcast-navigation-with-an-emphasis-on-playlists-and-recent-episodes/), [TechCrunch](https://techcrunch.com/2024/07/16/overcasts-rebuilt-version-does-away-with-streaming), [Michael Tsai](https://mjtsai.com/blog/2024/07/18/overcasts-new-foundation/)) | One queue, one list of recent: few places to look | Ear Drama's Library has the one queue. Smart Speed stays refused (research 05 Verdict 8) |
| **Audible** player | Sleep timer, speed and chapters moved onto the bottom of the player to cut clutter (2018, [Android Police](https://www.androidpolice.com/2018/07/24/audible-app-gets-new-ui-via-server-side-update/?amp)); a 2026 report says the app now opens to a mini player that VoiceOver users struggle to expand ([AppleVis](https://applevis.com/comment/202617)) | The bedtime controls belong on the player; the mini player must be reachable by every input | Ear Drama's sleep timer is on the player (R20). The 2026 AppleVis report is a warning for any redesign of the mini player |
| **Spotify** Now Playing view | Art, then cards below: "About the artist" with its image and a Follow button, and Credits showing three creators with an expanded view of all ([Spotify for Artists](https://artists.spotify.com/blog/making-the-most-of-the-now-playing-view-to-encourage-discovery)); Canvas guidelines tell artists not to repeat the song and artist name the app already shows ([Spotify support](https://support.spotify.com/gd/artists/article/canvas-guidelines/)) | **Three credits, then "all"**: the short list is the label; the full list is liner notes. Discovery sits below the transport, never over it | Supported: 23% of episodes have a credit with a portrait, median 3 portraits per credited episode. Three faces is the measured median |
| **BBC Sounds** | Launched 2018 replacing iPlayer Radio, with personalization from listening habits ([Engadget](https://www.engadget.com/2018-06-26-bbc-sounds-on-demand-radio-podcasts-app.html), [Mother Design](https://www.motherdesign.com/work/bbc-sounds/)) | A broadcaster's archive presented as programs and episodes, not files | No UX write-up of the episode page was found; Genome is the stronger BBC precedent (§2.4) |

### 2.2 Liner notes and album pages

| Product | What it does | Why it works | Ear Drama's data |
|---|---|---|---|
| **Apple Music credits** (iOS 17, 2023) | Behind "View Credits" in a menu, grouped as Performing Artists, Composition and Lyrics, Production and Engineering; not every song has them ([9to5Mac](https://9to5mac.com/2023/07/05/apple-music-song-credits-ios-17/), [Apple support](https://support.apple.com/en-gu/guide/music-web/apdm3b93fb16/web), [Apple delivery spec](https://itunespartner.apple.com/music/support/5542-deliver-credits)) | Three groups any listener understands, behind one control; the main screen never lists them | Maps cleanly: **On the air** (cast, host, announcer, narrator, guest, commercial spokesperson), **Writing** (writer, adaptor, author, creator, screenwriter), **Production** (director, producer, conductor, composer, music, sound effects). Needs a role map in the pipeline over 2,821 strings (the top 30 cover the great majority) |
| **Discogs** release and master pages | A master release is a display folder over two or more releases; each version carries only the credits printed on it; the master's main release is often the earliest ([Discogs master guideline](https://support.discogs.com/hc/articles/360005055493-Database-Guidelines-16-Master-Release), [Discogs credits guideline](https://support.discogs.com/hc/en-us/articles/360005006834), [nodecogs](https://npmjs.com/package/nodecogs)) | The work is the page; versions are a table under it, compared by what differs (format, country, year) | Ear Drama's broadcast is the master and the copies are versions (R5). What differs between copies: variant (AFRS), partial, length, bit rate. The archive.org identifier is not a difference a listener can use |
| **MusicBrainz** model | Release group, release, recording, work: four levels, and the commonest mix-ups are release group with release and recording with work ([Picard glossary](https://picard-docs.musicbrainz.org/en/about_picard/glossary.html), [schema docs](https://musicbrainz.readthedocs.io/en/latest/musicbrainz_database/schema/_schema.html)) | Separating the composition (work) from the performance makes "other performances" possible | Ear Drama has Broadcast and Recording; the Work layer (script) is research 05's proposal, not published. 6.1% of episodes are a likely re-performance within their series |
| **Criterion Collection** | Each release carries a booklet with a commissioned essay plus cast and credits listings (Rebecca's 22-page booklet with Robin Wood's notes; Judex's booklet with cast, credits and Geoffrey O'Brien's essay) ([Project MUSE](https://muse.jhu.edu/article/381485), [Criterion Forum](https://criterionforum.org/video/letters-from-fontainhas-supplements-the-criterion-collection-dvd), [Spellbound](https://spellboundwithbethann.com/2015/11/22/criterion-blogathon-judex-1963/)) | Context is written by a named person and set apart from the film; credits live in the booklet, not on the cover | Ear Drama writes no essays (no AI copy). The human-editor door exists (R13: "data or a human editor"); nothing is written yet. The lesson that survives: **credits belong in the booklet** |

### 2.3 Museum object pages

| Product | What it does | Why it works | Ear Drama's data |
|---|---|---|---|
| **The Met** | Open Access images carry a CC0 or OA mark on the object page; provenance sits in an expandable panel, which the Met's own guide tells researchers to open ([The Met, Open Access](https://www.metmuseum.org/perspectives/open-access-at-the-met), [Provenance research](https://www.metmuseum.org/about-the-met/provenance-research-resources)) | The tombstone (what, who, when) is the page; rights are one small mark on the picture; provenance is there in full for whoever opens it | The rights line already does the mark's job. Ear Drama's provenance (which witness dated it, `dateSource`, `networkSource`; which archive.org item each copy is) is the panel, closed |
| **Cooper Hewitt** | Square thumbnails cropped by a computed measure in small repeated slots, the object whole on its page ([Labs](https://labs.cooperhewitt.org/2013/b-is-for-beta/)); Object of the Day ([Smithsonian](https://dashboard.si.edu/es/newsdesk/releases/cooper-hewitt-launches-object-day-expand-collection-access)); people records with their own pages ([people record](https://www-3.collection.cooperhewitt.org/people/68735135/bio)) | Every name is a door; the object is never cropped on its own page | Already Decision 069 and §4.14 (people pages). Every credited name is a link today |
| **Rijksmuseum** | Object pages list title, maker, object number, dimensions, dating, copyright status and a persistent URL for citing ([example](https://www.rijksmuseum.nl/en/collection/RP-F-00-1076)); large crops are art-directed per image ([Q42](https://q42.nl/en/work/rijks-website1), via the `artwork-presentation-design` skill) | A plain, ordered tombstone and a citable link; the picture first | The tombstone order for a broadcast: series, title, when and where, who. The persistent URL is the https twin (DEEP_LINKS.md) |

### 2.4 Broadcast archives

| Source | What it does | Why it works | Ear Drama's data |
|---|---|---|---|
| **BBC Genome** | Every Radio Times listing 1923-2009 from OCR: date, time, title, synopsis, credits and channel; browse by day, by issue, by station; links from a listing to the scanned page ([BSHS](https://bshs.org.uk/using-the-bbc-genome-project-for-cultural-history/), [The Next Web](https://www.thenextweb.com/news/bbc-debuts-genome-database-covering-radio-times-listings-1923-2009), [Luke McKernan](https://lukemckernan.com/2014/10/26/the-genome-project/)) | **The day is the unit.** A program is found in the evening it aired in, beside what came before and after; the scan is the witness | Ear Drama has the evenings for 15 days ahead in `tonight.json`, the measured logs in the pipeline, and a date for 48% of episodes. The day view exists only in Stations; Detail never shows its evening |
| **Paley Center** | 160,000+ television and radio programs, radio back to the 1920s, played at consoles in its libraries ([Paley](https://paleycenter.org/collection), [Wikipedia](https://en.wikipedia.org/wiki/Paley_Center_for_Media)) | Curated access; the catalog record is a research tool | No public record layout found this session |
| **American Radio Archives** (now UCSB) | 23,000 radio and TV scripts, 10,000 photographs, 5,000 recordings; moved from Thousand Oaks to UCSB in 2021 ([Wikipedia](https://en.wikipedia.org/wiki/American_Radio_Archives), [UCSB News](https://news.ucsb.edu/2025/021774/bringing-radio-history-life)) | The script is the archive's object | A future source for the Work layer and for scripts; a rights question first (`evidence-gated-catalog-curation`) |
| **OTRR series logs** | One line per broadcast: number, title, date, sometimes cast; placeholders (a guest star, the first song, a description) until a title is known; "First Episode", "Last Episode", "(repeat)" in notes; dates beat days of the week when they conflict ([OTRR how-to](https://otrr.org/Files_Reference/HowToCompileASeriesLog.htm), [OTRR Primer](https://www.otrr.org/FILES/Times_Archive_pdf/2018_03.pdf), [Whistler log](https://www.otrr.org/FILES/Synopsis_txt/W_Series/Whistler_The.txt)) | The collectors' own format: date, number, title, and nothing else in the row | Ear Drama's series rows already match (date, title, length). The placeholder rule is a model for the 3,784 untitled episodes: a guest star from the credits is a better name than "No. 90" |
| **American Archive of Public Broadcasting** | Machine transcripts corrected by volunteers (FIX IT+), shown time-stamped beside the broadcast, with reviewed sections color-coded by how often they were checked ([AAPB blog](https://blog.americanarchive.org/2020/06/05/how-to-fix-it-and-why-crowdsourcing-to-save-public-media/), [AAPB blog](https://blog.americanarchive.org/2017/04/20/aapb-launches-crowdsourcing-game/)) | An automatic transcript is labeled as such and invites a person to fix it: participation, not passivity | Ear Drama labels "Automatic transcript" (R16). Correction is a Create-adjacent idea for D1c, not this phase |
| **WJSV, 1939-09-21** | A whole broadcast day recorded at the National Archives' request, on the National Recording Registry ([National Archives](https://www.archives.gov/press/press-releases/2004-35), [Wikipedia](https://en.wikipedia.org/wiki/National_Recording_Registry)) | The evening is the artifact | Research 05 §4 already built on it; Stations is the result |

---

## §3 Making a 1947 broadcast feel like an event, without a wall of fields

**What the precedents agree on.** Genome makes the day the unit; Discogs and
the Met make the object the page and the rest a table or a panel; Spotify and
Apple Music keep credits to three names and a door. None of them prints the
log number, the season, and the copy's bit rate in the header.

**The event sentence.** A broadcast's identity is *who aired it, when, and for
whom*. Today the web prints "Thursday, December 2, 1943" and then "CBS · Roma
Wines · 30 min · Season 1943-44 · No. 68". Read as a listener: the season
repeats the date, the number is a collector's index, the length belongs beside
Play. The same data as one line of type, at most three facts: **"CBS ·
Thursday, December 2, 1943 · Roma Wines"**, with the length on the Play button
("Play · 30 min"). On the 65% of bare episodes the line is just the date, or
"Undated", and the page still looks complete because nothing else was promised.

**Who was on.** In radio the people are the picture (research 05 §3.4).
Measured: median 3 portraits on a credited episode. A row of up to three faces
with names ("Cary Grant, Hans Conried, Bea Benaderet") says more than the
heading "Cast and credits" and sixteen rows. The open question is **order**:
credit order in the data is not billing (Jack Benny is sixth on his own show,
below "Don Bestor and His Orchestra"; Cary Grant is second on his Suspense, and
the episode's face is Hans Conried, the first on-air credit with a portrait).
Two data-only rules are possible, and the owner should choose: (a) the
episode's own credits with portraits, in data order, which is honest and
sometimes wrong-looking; (b) a billing signal computed in the pipeline (the
series star first when heard, then the person credited on the fewest of this
series' episodes, which picks the guest star). Rule (b) is a ranking, so it
goes through `values-based-feed-ranking` and is published, never computed on a
device.

**The evening it aired in.** 95% of dated episodes have a same-date neighbor
from another series. "That night" is a short strip under the credits: the other
surviving broadcasts of the same date, by series, and when the pipeline holds
that evening's log, a link into it ("The evening on CBS" opening Stations at
that date). What was in the news is told only by the catalog's own news and
documentary broadcasts of that date (28% of dated episodes have one); never
the newspaper text (Decision 067 keeps JJ's OCR unpublished), never a written
blurb. The precedent is Genome's day view, not a "This day in history" essay.

**What not to do.** No generated "context" paragraph about 1943; no headline
feed from a third party; no inferred "first broadcast after Pearl Harbor"
labels unless a dated human source carries them (a human editor may add them
later, R13).

---

## §4 A calm listening screen that still informs

What the precedents share (Pocket Casts' single page with notes one swipe away;
Apple's transcript reached from the player; Spotify's cards below the
transport; Audible's bedtime controls on the player):

- **Above the fold**: the picture, the series, the title, the event line, the
  scrubber, the transport. Nothing else competes.
- **One row of player options**, not four equal buttons: speed and the sleep
  timer are the two the measured reviews ask for (research 05 §1.4: bedtime 47
  reviews, the car 24); Level volume, Listen together and AirPlay/Cast are
  icons with labels for assistive technology, or one "More" menu.
- **Below the fold, a second page**: who is on (faces), the transcript when the
  gate passed, and Up next. Reading is one gesture away, never on top.
- **No animation that says nothing** (research 05 §3.4: no fake waveform).

Today's web Now Playing (§6.3) gets the top half right and stops: no network,
no people, and the options take as much room as the transport.

---

## §5 Transcripts, chapters and versions

- **Transcripts.** Keep R16's label and gate. A transcript without timings can
  be read, searched (already, `search/said/`) and opened from the player; it
  cannot follow along. Before any "current line" design (research 05 §3.4
  proposed one), **measure** whether archive.org serves a timed file
  (`.srt`/`.vtt` or a JSON with times) beside `autogenerated.txt` for the 7,623
  shown items. If it does not, a follow-along line would need time alignment
  in the pipeline, which is a new data product, not a client feature, and a
  candidate for the owner.
- **Chapters.** None exist and none may be estimated (contract §3.2a, R8).
  Every pattern below works without them. A radio program's natural chapters
  (open, first act, commercial, second act, close) are exactly the segments R8
  wants shown, so the first source of real segment times should land as
  chapters on every platform at once.
- **Versions.** Discogs' lesson: list what differs. Ear Drama's copies differ
  by four published facts (variant, partial, length, bit rate) and one the
  pipeline could publish (how far the length is from the broadcast's other
  copies). The archive.org identifier is provenance: it belongs behind the
  Source link, not as the copy's name.

---

## §6 Audit of today's web app at 375 px

**Method.** A small Python server on port 8794 served this worktree's web app
and forwarded `data/` to `https://eardrama.org/data/`, so the code under test
is the worktree's (commit `e070bb7`) and the data is the live projection. A
wrapper page held the app in a 375 px iframe; headless Chrome was driven over
DevTools (`tools/webdrive.py`, ports 9871 and 9872, private profiles) at a
375 px viewport, 812 px tall for the first screen and 2,600 px for the whole
page. Playback used the `?mute=1` door. The server and both Chrome instances
were stopped afterward. Three series of different kinds: Suspense (anthology),
Yours Truly Johnny Dollar (a serial with story arcs: 245 of its episodes are in
arcs), Jack Benny Program (comedy), plus one bare episode (1945 Radio News).

**Screenshots** (`docs/research/design/img/d1b/`, 0.52 MB in all, pngquant):

| File | Surface |
|---|---|
| `ep-suspense.png`, `ep-suspense-full.png` | Episode: Suspense, "The Black Curtain", 1943-12-02 |
| `ep-dollar.png`, `ep-dollar-full.png` | Episode: Johnny Dollar, "The Macormack Matter - Ep 1", 1955-10-03 (arc part 1 of 5) |
| `ep-benny.png`, `ep-benny-full.png` | Episode: Jack Benny, 1934-10-14 |
| `ep-bare.png` | Episode: 1945 Radio News, 1945-10-22 (no credit, network or sponsor) |
| `series-suspense.png`, `series-suspense-full.png` | Series: Suspense |
| `series-dollar.png`, `series-dollar-full.png` | Series: Johnny Dollar |
| `series-benny.png`, `series-benny-full.png` | Series: Jack Benny Program |
| `now-playing.png` | Now Playing: Suspense, with two episodes queued |
| `now-playing-arc.png` | Now Playing: Johnny Dollar part 2, "Next part:" |
| `now-playing-bare.png` | Now Playing: the bare episode, typographic card |
| `queue.png` | Library, Queue tab, two episodes |
| `home-continue.png` | Home after 4 s of play (Continue needs 10 s, WEB-DESIGN §5.7, so it is absent) |

### 6.1 Episode detail: every field, keep / move / cut

| Field as shown | Example | Mark | Reason |
|---|---|---|---|
| Portrait print with its name caption | Hans Conried | **Keep, revisit whose face** | The picture is the point (Decision 069), but the face is the first on-air credit with a portrait, not the star of the night (Cary Grant). See §3, "Who was on" |
| Series name (link, blue) | Suspense | Keep | Wayfinding (Decision 064 blue) |
| Title (page heading) | The Black Curtain | Keep, clean at the source | The heading; 3,784 empty and 2,173 series-named titles need a pipeline display title (Pattern 3) |
| Long date | Thursday, December 2, 1943 | Keep, as part of the event line | The broadcast's identity |
| Network | CBS | Keep, in the event line | When and where it aired |
| Sponsor | Roma Wines | Keep, in the event line, third | "For whom"; a period fact a person cannot discover by looking. Never infer its absence |
| Length | 30 min | **Move** to the Play button | It answers "do I have time", which is a question asked at Play |
| Season | Season 1943-44 | **Cut** from Detail | Restates the date; it is the series page's scope, where it stays |
| Log number | No. 68 | **Move** to the provenance panel | A collector's index; a fact for finding, not for listening. Keep it as the title fallback ("No. 90") |
| Play | Play | Keep | Primary action, ink |
| Add to queue | Add to queue | Keep | The second verb of Listen |
| Share | Share | Keep, as an icon in the header row | A Share verb is D1c's; it does not need a full-width row on a phone |
| Automatic transcript (closed disclosure) | | Keep, move under the faces | A reading door; it is not the next thing after Play for 93% of episodes, which have none |
| "Cast and credits" heading | | **Replace** with the faces row | The heading names a section; three faces and names are the content |
| Cast list, each name a link, faces where served | 8 names | **Move** to the credits disclosure, after the three faces | Liner notes (Pattern 2) |
| "as {character}" | as The Man In Black | Keep inside credits | Rare (0.2%) and valuable |
| Role groups, one heading per role | Adaptor, Conductor, The man in black, Commercial spokesperson, Composer, Director, Producer, Writer | **Move and merge** into three groups (On the air, Writing, Production); one line per person with all their roles ("William Spier, director, producer") | Nine headings for nine people is the wall; "The man in black" repeats a cast line |
| Recordings list: radio, archive.org identifier as the name, format, kbps, length, Source link | 6 rows | **Move** to a closed "Copies" disclosure, named by difference | The default plays; a listener needs only "Armed Forces rebroadcast", "Incomplete copy", or a length that differs. Identifiers move behind Source |
| Rights line | No rights claim known. Removed on request. | Keep | Required, published words (contract §5.5) |
| Footer: Credits, Privacy, Take-down requests, Delete an account | | Keep | Site pages (WEB-DESIGN §4.8) |
| Start an ear drama (when a script is linked) | not seen | Keep | The Create door; D1c's question where it sits |
| Arc position | **absent** | **Add** | The Detail row carries `arc` (part, parts, next), and the page never says "Part 1 of 5" (Pattern 5) |

### 6.2 Series page

| Field | Example | Mark | Reason |
|---|---|---|---|
| Star portrait print and caption | Bob Bailey, Jack Benny | Keep | Decision 069; Suspense has none and draws no print, correctly |
| Series name | Yours Truly Johnny Dollar | Keep | |
| Genre (link) | Mystery | Keep | Wayfinding into Browse |
| Networks | CBS, NBC; "NBC, CBS, NBC Red, NBC Blue" | Keep, **shorten** | Four networks for Benny is accurate and noisy; "NBC, CBS" with Red and Blue folded under NBC, by a pipeline rule |
| Year range | 1948-1962 | Keep | The run is the series' event |
| Episode count | 939 episodes | Keep once | It prints twice (meta line and again above the list); cut the second |
| Follow | Follow | Keep | |
| Share | Share | Keep, as an icon | As Detail |
| Season chips | All, 1948-49 ... Undated (27 for Benny) | Keep, **reconsider for long runs** | 27 chips in a scroll rail is a rail of noise at 375 px; a decade-then-season picker, or the year as a sticky index in the list, scales (D1a's question) |
| Row: air date in tabular figures | 1948-12-06 | Keep | R1, OTRR's own row |
| Row: title | Aud RobtWPerryCase | Keep, clean at the source | Pattern 3 |
| Row: length | 29 min | Keep | Small, useful for picking at bedtime |
| Row: play button | | Keep | |
| Arc grouping | absent | **Add** | Five rows of "The Macormack Matter - Ep 1" to "Ep 5" read as one story with five parts |

### 6.3 Now Playing

| Field | Mark | Reason |
|---|---|---|
| Close (chevron) | Keep | |
| Art at its own shape | Keep | V3/V4 already right (`now-playing.png`) |
| Series (link) | Keep | |
| Title | Keep | |
| Date | Keep, **add the network** | The web prints the date alone (`js/app.js` `np-meta`); iOS §5.3 and tvOS §5.2 print date and network: a parity gap |
| Scrubber, elapsed, remaining | Keep | |
| Back 15, Play/Pause, forward 30 | Keep | R18 |
| Speed (select with a "Speed" label) | Keep, **compact** | One of the two options people use |
| Sleep timer | Keep, prominent | Bedtime is the main use (research 05 §1.4) |
| Level volume | **Move** into a "More" menu or an icon | A set-once switch, not a per-episode control |
| Automatic transcript | Keep, as the second page | Reading lives below the transport |
| Listen together | Keep, smaller | Share-adjacent (D1c); one icon |
| AirPlay or Cast | Keep, as an icon | Shown only when a target exists (§5.10) |
| "Next part:" / "Next in queue:" caption | Keep | A fact the person cannot see otherwise (§5.4) |
| Next story | Keep | Owner's queue rule |
| Who is on | **absent; add** | The faces row, below the fold |

### 6.4 Queue (Library)

| Field | Mark | Reason |
|---|---|---|
| Art tile | Keep | |
| Date | Keep, **fix the layout** | At 375 px it wraps "1955-10-" / "03" |
| Title | Keep, **fix the layout** | It wraps mid-word ("Macormac / k Matter") in a column squeezed by four controls |
| Series and length | Keep | |
| Play, up, down, remove (four icon buttons in every row) | **Move** up/down to drag (the platform's reorder) or a row menu; keep remove as a swipe or menu | Four controls per row leave the title 70 px; iOS already drags and swipes (iOS-DESIGN §4.6) |

---

## §7 Candidate patterns, ranked

Ranked by how much noise each removes for the most listening, against its cost.
Costs: **S** a day or less on that platform, **M** a few days, **L** a week or
more; "pipeline" names a projection change, which lands once and every client
reads (contract §1).

### 1. The broadcast line (one event sentence, length on Play)

- **Surfaces**: network, long date, sponsor as one line ("CBS · Thursday,
  December 2, 1943 · Roma Wines"); length on the Play button; the arc position
  before the line when there is one ("Part 2 of 5").
- **Hides**: season and log number from Detail (season stays the series page's
  scope; the number moves to the provenance panel and stays the title fallback).
- **Data**: in hand on every row that has it; a bare row degrades to the date
  or "Undated" (48% dated, 31% network, 12% sponsor).
- **Cost**: web S (`js/app.js` episode view, `np-meta`); iOS/iPadOS S
  (`EpisodeScreen` facts line); macOS S (same screen); tvOS S (facts line
  already holds date, network, sponsor, length); Android S. Design docs: WEB §4.5,
  iOS §4.4, tvOS §4.4, ANDROID §4.4 rewritten the same day.
- **Learning test**: clearer, not shallower; nothing is removed that the
  person cannot open.

### 2. Liner-notes credits: three faces, then the booklet

- **Surfaces**: up to three people with portraits as a faces row under the
  event line, each a link to the person (§4.14); the rest in a closed "Cast and
  credits" disclosure grouped On the air / Writing / Production, one line per
  person with all their roles.
- **Hides**: nine role headings, doubled entries ("Joseph Kearns as The Man In
  Black" and again under "The man in black"), fragments of Goldin cast lists.
- **Data**: median 3 portraits on a credited episode (23% of all episodes, more
  in the played catalog). Needs **pipeline**: a published role-to-group map
  (the 2,821 strings, top 30 first), merging a person's roles, and the Goldin
  split contract §4 already calls for. The faces' order is an owner choice
  (§3: data order, or a published billing rule).
- **Cost**: pipeline M; web M; iOS/iPadOS M (`DisclosureGroup` in the List);
  macOS S after iOS; tvOS M (faces as one focus section, the booklet as its
  own); Android M.
- **Learning test**: passes: every name is a door to a person's whole career
  (participation through exploration), and the grouping teaches how a radio
  show was made.

### 3. Display titles from the pipeline

- **Surfaces**: a clean title on every surface: "(OTR)" and file artifacts
  dropped, "Ep 1" read as the arc part, run-together words split only where a
  rule is sure, an untitled episode named by the OTRR placeholder rule (a guest
  star from the credits) before "No. 90" or "Untitled".
- **Hides**: the collector's filename noise that fills series pages.
- **Data**: 3,784 empty, 2,173 series-named, 1,721 dated titles; the raw title
  stays in the provenance panel and in search.
- **Cost**: pipeline M (a `display_title` column and its golden tests; the
  `ten-foot-detail-design` §4 episode-name derivation is the start); every
  client S (read the new field, fall back to `title`).
- **Learning test**: clarity; the original stays findable.

### 4. That night on the radio

- **Surfaces**: on Detail, under the credits, the other surviving broadcasts of
  the same date (series and title, at most a short row, news and documentary
  first when present), and a link into that evening on Stations when the
  pipeline holds the log.
- **Hides**: nothing; it replaces no field.
- **Data**: 95% of dated episodes have a same-date neighbor (median 3 series);
  28% a news or documentary one. The web already publishes a year's dated docs
  (`data/search/dates/{yyyy}.json`); natively it is a query on `air_date`. It
  should be a named verb (`sameDay(id)`, contract §5) so every client returns
  the same rows in the same order, with `recommendAnd` not applied (the person
  drives it).
- **Cost**: contract S; web S to M; iOS/iPadOS M; macOS S; tvOS M (a shelf
  below Detail); Android M.
- **Learning test**: the strongest of the eight: it turns one program into a
  place in history, and every row is a real broadcast, not a written blurb.

### 5. Story-aware serials

- **Surfaces**: "Part 2 of 5" in the event line; on the series page, an arc's
  parts as one row with its part count that opens to the parts; in the queue,
  an arc shown as one story.
- **Hides**: five near-identical rows per story.
- **Data**: 451 arcs over 3,225 episodes (3%), Johnny Dollar's 26%, already on
  the Detail row (`arc`). The series page rows need the arc id (**pipeline** S:
  add `arc` to `fields.episode`).
- **Cost**: web S (Detail) plus M (series grouping); iOS/iPadOS S plus M; macOS
  S; tvOS M; Android S plus M.
- **Learning test**: follows the story as it was told; respects the owner's
  queue rule (the next part plays, the next story is only offered).

### 6. Now Playing with a second page

- **Surfaces**: above the fold the art, series, title, event line, transport,
  and one compact options row (speed, sleep timer, a More menu with Level
  volume, Listen together, AirPlay or Cast); below it, the faces row (Pattern
  2), the transcript when shown, and Up next.
- **Hides**: four equal-weight option buttons.
- **Data**: all in hand. A "current line" waits on the timed-transcript
  measurement (§5).
- **Cost**: web M (the dialog becomes a scroll with a second section); iOS/iPadOS
  M (the sheet gains a scroll below the transport); macOS M; tvOS M (a second
  focus section below the transport, the page-title type rule holding); Android M.
- **Learning test**: keeps the listener's attention on the play; reading is one
  gesture away, never pushed.

### 7. Copies named by what differs

- **Surfaces**: one line under Play only when it matters ("Also an Armed Forces
  rebroadcast", "Another copy runs 9 min longer"); a closed "Copies" disclosure
  whose rows are named by difference, the identifier behind Source.
- **Hides**: six rows of identifiers and bit rates on 20% of episodes.
- **Data**: variant, partial, length and bit rate are published. **Pipeline**:
  flag a copy whose length is far from its siblings (7.3% of episodes have a
  spread over 2 min; the Johnny Dollar 1955-10-03 copies include a 1 h 13 min
  file and a 1958 episode, which are wrong matches to fix, not to show).
- **Cost**: pipeline M (a `mismatch` check, `evidence-gated-catalog-curation`
  §"a cleared match scrubs what it filled"); web S; iOS/iPadOS S; macOS S; tvOS
  S (Versions is its own focus section today); Android S.
- **Learning test**: honest about provenance without making the listener an
  archivist.

### 8. Continue as a resume card

- **Surfaces**: Home's Continue listening rows say where the person stopped
  ("12 min left"), with the episode's face; the Library history keeps the rest.
- **Hides**: nothing new.
- **Data**: the person's own position (on the device, synced when signed in).
- **Cost**: web S; iOS/iPadOS S; macOS S; tvOS S (the first shelf, §4.1);
  Android S. Proposing a "next in series" beside it touches the owner's queue
  rule, so it is listed as a question, not a pattern.
- **Learning test**: neutral; it serves agency (the person resumes what they
  chose).

---

## §8 Seen on the way (outside this phase; none fixed)

| Where | Symptom | Proposed fix | Owner ruling? |
|---|---|---|---|
| Web Library queue row (`queue.png`) | At 375 px the date wraps ("1955-10-" / "03") and the title breaks mid-word ("Macormac / k Matter") beside four controls | Reorder by drag or a row menu; let the title take the row (§6.4) | No |
| Johnny Dollar 1955-10-03 copies (`ep-dollar-full.png`) | The 15-minute part lists a 1 h 13 min copy (`ytjd19551121266theamybradshawmatter`) and two copies of the 1958 Rolling Stone Matter as versions | A length and title check in `build_db.order_recordings`' matching; drop or demote mismatches | No |
| Jack Benny 1934-10-14 | Titled "First show for Jell-O", sponsor shown as General Tire (the dated run that ended before it) | Check the OTRRpedia run boundary in `catalog/tools/sponsors.py`; a title naming a sponsor contradicts the computed one | No (accuracy, `summary_accuracy_not_form`) |
| Home, Science fiction shelf | Space Patrol 1952-10-04 shows "29 hr 46 min" | A length sanity bound in the projection (a copy over, say, 4 h is not one episode) | No |
| Credits (`ep-suspense-full.png`, Family Theater 1948-09-30) | Joseph Kearns appears as cast "as The Man In Black" and again under the role "The man in black"; Goldin fragments such as "Max Terr (music (music), Tony La Frano (announcer), Norman Field" credited as cast (1,043 episodes) | The Goldin split contract §4 names; collapse a character role into the cast line | No |
| Web Now Playing | Date only; iOS and tvOS show date and network | Add the network (Pattern 1) and update PARITY.md | No |
| Web Detail | The `arc` field is read only by the player; Detail never says "Part 1 of 5" | Pattern 5 | No |
| Series page | The episode count prints twice | Cut the second | No |
| Episode face | The face is the first on-air credit with a portrait in data order, not billing (Hans Conried over Cary Grant; Benny sixth on his own show) | A published billing rule, or accept data order | **Yes** (a ranking) |
| Data fetch | Two of 4,096 shards (`c8f`, `d5a`) came back as non-JSON once under 16 parallel requests and loaded on retry | Probably a rate limit at Pages; a client's single fetch is unaffected, but `API` could retry once on a parse failure | No |

---

## §9 Questions for the owner (from this phase)

1. Whose faces lead an episode: data order, or a published billing rule that
   puts the series star, then the night's guest, first (§3)?
2. May "That night on the radio" appear on Detail (Pattern 4)? It is a new
   section on every platform and a new contract verb.
3. Should a follow-along transcript line be pursued if archive.org serves no
   timings, which would make time alignment a new pipeline product (§5)?

---

## Sources

Ear Drama (read in this repository): `DESIGN-LOOP.md`, `docs/AGENT-BRIEF.md`,
`docs/research/05-design-research.md`, `DECISIONS.md` 064, 069, 070,
`docs/CATALOG-CONTRACT.md`, `docs/WEB-DESIGN.md`, `docs/iOS-DESIGN.md`,
`docs/tvOS-DESIGN.md`, `docs/ANDROID-DESIGN.md`, `js/app.js`, and the skills
named at the top. Live data: `https://eardrama.org/data/manifest.json`,
`data/episodes/*.json` (all 4,096), `data/index/series.json`,
`data/tonight.json`, fetched 2026-10-29.

External (each opened through a search summary unless noted):

- Apple Podcasts transcripts: https://macrumors.com/2024/01/26/ios-17-4-podcast-transcripts ; https://podcasters.apple.com/support/5316-transcripts-on-apple-podcasts ; https://www.imore.com/podcast/apple-podcast/transcripts-for-apple-podcasts-is-now-available-read-your-favorite-shows-as-you-listen-in-ios-174 ; https://laptopmag.com/phones/iphone/what-did-they-say-ios-174-gives-you-full-podcast-transcripts-in-apple-podcasts
- Apple Podcasts queue: https://9to5mac.com/2024/12/10/ios-182-improves-apples-podcasts-app-but-my-biggest-complaint-is-unchanged ; https://discussions.apple.com/thread/255770923 ; https://discussions.apple.com/thread/256019629
- Pocket Casts: https://www.macstories.net/reviews/pocket-casts-7-a-host-of-improvements-make-the-app-feel-brand-new/ ; https://blog.pocketcasts.com/2019/12/09/7-6-up-next-changes/ ; https://support.pocketcasts.com/knowledge-base/playing-episodes-and-managing-your-queue/ ; https://support.pocketcasts.com/knowledge-base/chapters/
- Overcast: https://www.macstories.net/reviews/overcast-redesign-enhances-podcast-navigation-with-an-emphasis-on-playlists-and-recent-episodes/ ; https://techcrunch.com/2024/07/16/overcasts-rebuilt-version-does-away-with-streaming ; https://mjtsai.com/blog/2024/07/18/overcasts-new-foundation/
- Audible: https://www.androidpolice.com/2018/07/24/audible-app-gets-new-ui-via-server-side-update/?amp ; https://applevis.com/comment/202617 ; https://applevis.com/forum/ios-ipados/trouble-skipping-chapters-audible-app
- Spotify: https://artists.spotify.com/blog/making-the-most-of-the-now-playing-view-to-encourage-discovery ; https://support.spotify.com/gd/artists/article/canvas-guidelines/
- BBC Sounds: https://www.engadget.com/2018-06-26-bbc-sounds-on-demand-radio-podcasts-app.html ; https://www.motherdesign.com/work/bbc-sounds/
- Apple Music credits: https://9to5mac.com/2023/07/05/apple-music-song-credits-ios-17/ ; https://support.apple.com/en-gu/guide/music-web/apdm3b93fb16/web ; https://itunespartner.apple.com/music/support/5542-deliver-credits ; https://appleinsider.com/articles/23/07/05/apple-music-gets-full-performer-composer-credits-in-ios-17-beta-3
- Apple Music lyrics: https://9to5mac.com/2023/10/11/apple-music-mac-fullscreen-lyrics/
- Discogs: https://support.discogs.com/hc/articles/360005055493-Database-Guidelines-16-Master-Release ; https://support.discogs.com/hc/en-us/articles/360005006834 ; https://npmjs.com/package/nodecogs
- MusicBrainz: https://picard-docs.musicbrainz.org/en/about_picard/glossary.html ; https://musicbrainz.readthedocs.io/en/latest/musicbrainz_database/schema/_schema.html
- Criterion: https://muse.jhu.edu/article/381485 ; https://criterionforum.org/video/letters-from-fontainhas-supplements-the-criterion-collection-dvd ; https://spellboundwithbethann.com/2015/11/22/criterion-blogathon-judex-1963/
- The Met: https://www.metmuseum.org/perspectives/open-access-at-the-met ; https://www.metmuseum.org/about-the-met/provenance-research-resources
- Cooper Hewitt: https://labs.cooperhewitt.org/2013/b-is-for-beta/ ; https://dashboard.si.edu/es/newsdesk/releases/cooper-hewitt-launches-object-day-expand-collection-access ; https://www-3.collection.cooperhewitt.org/people/68735135/bio
- Rijksmuseum: https://www.rijksmuseum.nl/en/collection/RP-F-00-1076 ; https://q42.nl/en/work/rijks-website1
- BBC Genome: https://bshs.org.uk/using-the-bbc-genome-project-for-cultural-history/ ; https://www.thenextweb.com/news/bbc-debuts-genome-database-covering-radio-times-listings-1923-2009 ; https://lukemckernan.com/2014/10/26/the-genome-project/
- Paley Center: https://paleycenter.org/collection ; https://en.wikipedia.org/wiki/Paley_Center_for_Media
- American Radio Archives: https://en.wikipedia.org/wiki/American_Radio_Archives ; https://news.ucsb.edu/2025/021774/bringing-radio-history-life
- OTRR logs (opened directly): https://otrr.org/Files_Reference/HowToCompileASeriesLog.htm ; via search: https://www.otrr.org/FILES/Times_Archive_pdf/2018_03.pdf ; https://www.otrr.org/FILES/Synopsis_txt/W_Series/Whistler_The.txt ; JJ's logs: https://www.jjonz.us/RadioLogs/index.htm
- AAPB: https://blog.americanarchive.org/2020/06/05/how-to-fix-it-and-why-crowdsourcing-to-save-public-media/ ; https://blog.americanarchive.org/2017/04/20/aapb-launches-crowdsourcing-game/
- WJSV and the Registry: https://www.archives.gov/press/press-releases/2004-35 ; https://en.wikipedia.org/wiki/National_Recording_Registry
- Podcast chapters: https://james.cridland.net/blog/2025/apple-podcasts-chapter-support/
- Now Playing on Apple platforms: https://developer.apple.com/videos/play/wwdc2022/110338 ; https://developer.apple.com/videos/play/wwdc2026/312/
