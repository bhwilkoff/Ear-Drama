# R2: Home, entry points, and making Create visible (research, 2026-11-14)

Round 2, tracks **H** (Home and entry points) and **C** (Create, found and exciting) in
`DESIGN-LOOP.md`. Research only: no code changes. Direction D stays as the visual language. This
doc changes what Home *does* and where Create sits. It does not change how either looks.

The owner, 2026-11-14: *"It is entirely unclear what the app is or how to use it easily ... Right
now, it just shows as a database of old content ... we can provide multiple entry points for
users"* and *"The ability/functionality for recording new Ear Dramas is significantly buried ... I
would like for people to get excited about recording new Ear Dramas and the perusal of public
domain plays and radio dramas should be available and easy to access."*

Track **S** (script reader and studio) has its own research. This doc only decides where reading
and recording are *entered*, not how the reader or the recorder works.

---

## 0. Verdict

1. **Home answers "what is this" with pictures and data. It never answers "what do I do".** The
   first thing on screen is a bar chart. The first sound is two taps away. Recording is not on
   Home at all.
2. **Audio apps that make their purpose obvious lead with one thing you can play right now.** On
   radio apps that thing is what is on the air (NTS, Radio Garden, BBC Sounds' live strip). On
   on-demand apps it is "continue" (Spotify's shortcuts grid, Apple Podcasts' Up Next). Those
   need history, which a newcomer does not have. Ear Drama
   has both, and its live evening is its most distinctive thing. That evening sits in tab 3.
3. **Creation stays visible when the verb sits on the thing being consumed and carries the source
   along.** Examples: TikTok and Shorts' "Use this sound", Instagram's "Remix", BandLab's fork
   mark, LibriVox's open cast lists, Smule's open duet seeds. It disappears when it lives in a
   separate product or section (Anchor, later Spotify for Podcasters, removed 2024).
4. **Ear Drama's real blocker for Create is supply, not layout.** It ships **15 castable plays**
   (11 stage, 4 radio) out of 1,722 the rights test already clears. **No broadcast episode** links
   a castable script. 598 episodes link a Generic Radio Workshop script that the app may only
   *link to* until GRW answers (C8). No layout makes 15 plum monograms feel like a library.
5. **Recommendation: Concept B, "Listen live, find, record".** Home opens on what is on the air.
   Below it are three verb doors (listen, find, record), then rule-named entry rows. The shell
   becomes **Home · Browse · Record · Search · Library**. Stations' page is reached from Home's live
   block, and Surprise moves to Home's toolbar, as it already does on iPhone. Record is an action
   tab (Decision 068's verb test: no other section owns *record*). It opens on your productions,
   then the play library browsed by cast size and length. Every page that has a castable script
   carries **Record this** beside Play.

---

## 1. Audit: today's Home and Create path (web, 375 px, live site, 2026-11-14)

Shot with `tools/webdrive.py` (muted headless Chrome, CDP device metrics 375×812 @2x, inner
scroller stepped 700 px). The frames are not committed: this research writes one file. To
re-shoot, run the same driver against `https://eardrama.org/?view=home|browse&script=1|library|surprise|stations`
and `?play=gut-28051`. I read every frame myself.

### What a newcomer sees on Home, top to bottom

| # | On screen | What it tells a newcomer |
|---|---|---|
| 1 | "Home" heading | nothing |
| 2 | Board: THIS DAY IN RADIO / November 14 / "118 surviving broadcasts · 29 years", a stacked bar chart 1928-1966, a 7-genre legend | that this is a *dataset*. The first interactive object is a chart, and pressing a bar changes the grid below. |
| 3 | "November 14, 1948", six show tiles (Ozzie and Harriet, Author Meets the Critics, Blackstone, Box 13, Jack Benny, Mr President) with title and minutes, "All 13 shows that night" | good material, but the tiles open pages. **There is no Play on Home.** |
| 4 | "Most downloaded · All 1,311 shows": a rail of 12 (Gunsmoke, Dragnet, Johnny Dollar, Suspense ...) | the catalog's popularity, the same for everyone |
| 5 | "Most heard voices · All voices": 12 faces, with a large empty gap below the rail | people, but not why you would tap one |
| 6 | Credits · Privacy · Take-down requests · Delete an account | chrome on the front page |
| — | "New ear dramas" | **absent**: it draws only when finished dramas exist, and none do |

The tab bar holds six items at 375 px (Home, Browse, Stations, Surprise, Search, Library). Decision
068 puts Surprise behind a Home toolbar button on iPhone, but the web tab bar shows all six.

### Why a newcomer is lost (specific)

1. **No statement and no primary action.** Nothing says "radio drama", "listen" or "record". The
   most prominent object is an almanac chart (`catalog-experience-design` §4's overview, which
   belongs in Browse and is wrong as a front door). A first sound takes tile, then episode page,
   then Play.
2. **The live radio evening is hidden.** "Tonight in 1949 · Starts at 5:00 PM" and eight genre
   stations playing now are Ear Drama's clearest "what this is" (BBC Sounds lost its schedule when
   it moved to shelves; D1a §2.5). They are one tab away, and Home never mentions them.
3. **Rows are named by statistics, not by what you would do.** "Most downloaded" and "Most heard
   voices" are honest rules (§5 of the catalog skill). But they are the only rows, so Home reads as
   a leaderboard of an archive: the owner's "database of old content".
4. **Create is not on Home in any state.** No row, door, or word. It cannot be seen from the
   first screen.
5. **The path to recording is 3 to 4 taps through controls that don't say "record".** There are
   three ways in:
   - Browse, then the **Has a script (15)** checkbox, or the **Ear dramas** chip, which lists
     *finished* dramas, not plays, then a play, then **Start an ear drama**.
   - Surprise's third card, "A play".
   - Nothing from an episode page: zero broadcast episodes link a castable script, so no episode
     shows Start.

   The word "record" and a microphone appear nowhere before the recorder. "Ear drama" names both
   the content type and the thing you make.
6. **The play library looks thin and unfinished** (`browse-script-0`, `play-0`):
   - 15 tiles, all drama plum, each a two-letter outline monogram (AT, AD, CR, CC).
   - Raw Gutenberg author strings ("George M. (George Melville) Baker").
   - Headed **"Most downloaded first"** although plays carry no download counts: a rule label that
     isn't true of the list.
   - The page count reads "0 shows · 15 plays".

   The play page itself is strong: a board with the cast fingerprint, a parts playbill with
   presence strips, and one Start button. It is just hard to reach.
7. **Broadcast scripts send you away.** 598 episodes show "Read the script · Generic Radio
   Workshop", a link out of the app. That is the moment a listener is most ready to try a line,
   and the app sends them to another site.
8. **Library on a new device is a utility page.** It shows the Continue tab's empty line, a
   Browse button, then "Sign in", "Join a room", "Export my data", "History (CSV)". Nothing
   explains that recordings you take part in will appear here.

### What the data can feed (measured 2026-11-14 on the live projection, `generatedAt` 16:16 UTC)

| Data | Count | Feeds |
|---|---|---|
| Episodes / series / shows (5+ episodes) | 73,642 / 4,842 / 1,311 | everything |
| Show pictures | 214 star portraits, 37 show pictures, 1 person, **1,059 typographic** (of 1,311) | tiles. Most doors must look good bare. |
| `tonight.json` | 15 evenings, each with paper, station and witness URL | the live block |
| `stations.json` | 8 genre stations, slots on one clock | the live block, "Listen live" |
| `listenShelves` | `onThisDay`, `mostDownloaded`, 8 × `genreFirsts` (20 each) | "Start a show", the day board |
| Arcs | 411 stories over 3,033 episodes | "Stories in parts" |
| Voices with portraits | 300 (2,144 portraits) | Voices |
| Shown transcripts | 8,525 episodes | read along (track S) |
| Series `about` | 317 | detail only |
| Episode lengths (1,357 dated, 12 sampled days) | 28% under 16 min, 65% 16-35 min, 7% over 35; median 28 min | length doors |
| Castable plays bundled | **15** (11 stage, 4 Carlton radio) | Record |
| Rights-castable Gutenberg drama records | 1,722 (PLAYS-DESIGN §3) | Record, once harvested and parsed |
| Episodes linking a castable script | **0** | "Record this" on episodes |
| Episodes linking a GRW script (read-only) | 598 | "Record this" on episodes, if GRW says yes |
| Plays also read by LibriVox | 146 texts, median cast 16 | "Hear it, then make it" |
| Finished ear dramas | none listed on the live site | "Made here" |

There is no mood, theme, or "for bedtime" data, and inventing one breaks the no-AI-copy rule. Mood
entry points (Calm, Headspace) are refused here. Genre and length are the honest stand-ins.

---

## 2. Findings by pattern

### 2.1 Purpose in the first ten seconds

- **Radio apps lead with what is on now, and how far in.** BBC Sounds' 2018 web launch put
  "Listen Live" at the top of the homepage: what each national station was playing and how far
  through the programme, with links to every station and schedule
  ([Seenit](https://www.seenit.co.uk/bbc-launches-new-personalised-app-bringing-together-live-radio-podcasts-and-music/);
  [RadioToday](https://radiotoday.co.uk/2018/10/bbc-sounds-branding-replaces-iplayer-radio/)).
  The launch complaints were about *losing* schedule, live rewind and playlist features, not
  about too much live ([inkl](https://www.inkl.com/news/listeners-and-stars-up-in-arms-as-bbc-sounds-app-backfires)).
  The BBC added pause and restart for live radio in 2019
  ([Wikipedia](https://en.wikipedia.org/wiki/BBC_Sounds)).
  - NTS: two live channels and 16 always-on "Infinite Mixtapes"
    ([App Store](https://apps.apple.com/gb/app/nts-radio/id1204567739)).
  - Radio Garden: a globe of live stations, where hovering previews and a click plays
    ([Radio World](https://www.radioworld.com/global/radio-garden-turns-earth-into-radio-tuner);
    [AppleInsider](https://appleinsider.com/articles/21/02/16/how-to-use-radio-garden-to-bring-global-radio-stations-to-your-iphone)).

  The pattern: a small fixed set of always-on things, and one tap to sound. Ear Drama has
  exactly that in its evening plus eight stations ("Tonight in 1949 · 7:45 PM, 12 minutes in").
- **The on-demand shortcut grid is for resuming, not for newcomers.** Spotify's 2020 Home: a
  time-of-day greeting, then six shortcut tiles from your regular listening
  ([iMore](https://www.imore.com/spotifys-new-home-layout-makes-it-easier-pick-where-you-left)).
  It rolled out only to users with 30+ days of history
  ([TechCrunch](https://techcrunch.com/?p=1956169)), so it is not a cold-start design. The
  2022 Music / Podcasts feeds split Home so people can "scroll through the type of content
  they're looking for at that moment"
  ([TechCrunch](https://techcrunch.com/2022/08/09/spotify-updates-home-screen-with-new-personalized-discovery-feeds-music-podcasts)).
  **For Ear Drama:** Continue earns the top only once a person has history (B's one ordering
  rule). For a newcomer, the big tap targets come from stated rules.
- **With no history, apps either ask or fall back on editors.**
  - Apple Music asks for genres and artists the first time Listen Now opens
    ([Apple Support](https://support.apple.com/en-kg/guide/iphone/get-personalize-recommendations-iph2b1748696/15.0)).
  - Apple Podcasts' Up Next is built from subscriptions
    ([Cult of Mac](https://www.cultofmac.com/news/apple-adds-100-podcasts-with-improved-access);
    [9to5Mac](https://9to5mac.com/2023/06/06/apple-podcasts-ios-17/)).
  - Pocket Casts' "You Might Like" needs a signed-in playback history
    ([Pocket Casts blog](https://blog.pocketcasts.com/recommendations)).

  Every one of these rests on subscriptions or history, and Ear Drama has none on day one. So its
  Home is rule-ruled. The visible genre chips in "Start a show" are the honest version of Apple's
  "pick what you like": the person chooses, and nothing is inferred.
- **The clock can shape Home without a model.**
  - Headspace's Today tab switches its Essentials to wind-down content in the evening
    ([Headspace help, June 2026](https://help.headspace.com/hc/en-us/articles/51443842967195-Refreshed-Today-Tab-Experience-June-2026)).
  - Calm makes Sleep a top-level place
    ([Calm blog](https://www.calm.com/blog/new-look-more-calm);
    [Calm Sleep help](https://support.calm.com/hc/en-us/articles/36451062992027-Using-the-Home-tab-in-the-Calm-Sleep-app)).

  Ear Drama's clock is a fact, not a mood: in the evening tonight's broadcast leads, and during
  the day the stations do. No mood shelf (there is no mood data).
- **Sample before you commit; show length on every item.** Libby lets people sample titles
  without a library card, and its "Inspire Me" targets a first book
  ([OverDrive](https://company.overdrive.com/?p=68446);
  [Marin Library](https://marinlibrary.org/blogs/post/libbys-new-look/)). Storytel shows a
  duration on every title and keeps mood storefronts
  ([Storytel](https://www.storytel.com/in/books/moods-1573520)). **For Ear Drama:** Play on the
  tile with its minutes, and Listen through before Take a part.
- **No onboarding wall: teach through the first action.**
  - NN/g's study of 70 people: tutorial readers did no better than skippers (91% vs 94% success)
    and rated tasks harder. NN/g advises skipping onboarding where possible and using contextual
    help ([NN/g mobile tutorials](https://www.nngroup.com/articles/mobile-tutorials/);
    [NN/g onboarding](https://www.nngroup.com/articles/mobile-app-onboarding/)).
  - Apple's HIG: "teach through interactivity"
    ([HIG onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)).
  - Duolingo asks for sign-up after the first lesson
    ([Screens Design](https://screensdesign.com/articles/duolingo-onboarding-design/)).

  The first screen should play something, and the gate goes at the first take.
- **Put the primary action first.** More choices take longer to decide among (Hick's law;
  [NN/g](https://www.nngroup.com/videos/hicks-law-long-menus/)). No controlled study was found for
  a particular row count or a single hero Play. This is general UX, not audio-specific evidence.

### 2.2 Creation inside a consumption app

- **The verb sits on the piece and carries the source along.**
  - TikTok: the sound title on a video opens a sound page with every public video using it and
    **Use this sound**, which opens the recorder with the audio loaded
    ([Influencer Marketing Hub](https://influencermarketinghub.com/tiktok-sounds/);
    [NapoleonCat](https://napoleoncat.com/blog/tiktok-sounds/); secondary sources).
  - YouTube Shorts: the audio box carries "Use this sound", and a remix credits the source video
    ([TechCrunch](https://techcrunch.com/2024/02/15/youtube-now-lets-you-integrate-music-videos-into-your-shorts);
    [Engadget](https://www.engadget.com/youtube-shorts-now-lets-you-chop-up-and-remix-music-videos-180655627.html)).
  - Instagram: "Remix this video" is in the menu on any public video
    ([TechCrunch 2022](https://techcrunch.com/2022/01/20/instagram-now-allows-creators-to-remix-any-public-videos-not-just-reels)).

  **For Ear Drama:** put **Record this** on the script's and the episode's page. A script's page
  doubles as the gallery of ear dramas made from it.
- **An unfinished recording with an open part is itself an invitation.** Smule's group invites let
  others add their parts to a started performance
  ([Smule help](https://smule.zendesk.com/hc/en-us/articles/15507046642196-Moments-FAQ)). Smule
  limits turning a join into an invite to paying members
  ([Smule help](https://smule.zendesk.com/hc/en-us/articles/31018793346964-Turn-a-Join-into-an-Invite)),
  a paywall Ear Drama declines. **For Ear Drama:** a production with open parts is a shareable
  invitation (D1c Pattern 2 already designs the card).
- **Creation kept apart from listening did not last.** Anchor's "Record with Friends"
  ([TechCrunch](https://techcrunch.com/?p=1964589)) moved into Spotify for Podcasters
  ([The Podcast Host](https://www.thepodcasthost.com/websites-hosting/spotify-for-podcasters/)).
  The mobile recording tools there were removed in 2024 in favor of Riverside
  ([podcastvideos.com](https://www.podcastvideos.com/articles/spotify-riverside-integration-legacy-tools-shutdown)).
  No post-mortem says why. Read it as a caution, not proof.
- **Start from a filled template, not a blank page.** GarageBand's Live Loops templates and Remix
  Sessions open with cells already filled
  ([Apple Support](https://support.apple.com/guide/garageband-iphone/chs371e72c01/ios);
  [Apple Education](https://education.apple.com/learning-center/T022034A-en_US)). Ear Drama's version
  is already built: a parsed play with every part voiced by the device. **Listen through first,
  then take a part.**
- **Fork marks and personal invites are cheap and human.** BandLab marks a forkable song with a
  symbol. A fork leaves the original untouched, and invites carry a written message
  ([BandLab help: forking](https://help.bandlab.com/hc/en-us/articles/48041963115033-What-is-Forking);
  [invites](https://help.bandlab.com/hc/en-us/articles/48010528581529-How-do-I-invite-other-users-to-collaborate)).
  **For Ear Drama:** a finished ear drama's page gets **Make your own** (a new production of the
  same script).
- **Act on the content itself.** Genius: select lines, then Annotate
  ([Genius guidelines](https://rapgenius.com/contributor_guidelines)). Wattpad puts Write in the
  main navigation beside reading
  ([Wattpad](https://www.wattpad.com/575664729-how-to-use-wattpad-wattpad-icons-what-they-mean)).
  **For Ear Drama:** in the reader, a tap on a part's line can start recording that part (track S).
- **LibriVox is the closest model, and it is welcoming without being pushy.** Projects titled
  "Open" list their parts. A newcomer claims a character or asks the coordinator to suggest one.
  Each reader records only their lines, with gaps, and states a voice credit
  ([LibriVox wiki: Dramatic Readings and Plays](https://wiki.librivox.org/index.php/Dramatic_Readings_and_Plays)).
  **For Ear Drama:** "Open parts" is a list worth putting on Home. Suggesting a part (C7, largest
  open) mirrors the coordinator.
- **Rehearsal apps all reduce to "my part, voices for the rest."** Script Rehearser, Run Lines,
  ReadThru and Off Book import a script, then voice the other characters
  ([Script Rehearser](https://apps.apple.com/us/app/script-rehearser/id1441908800);
  [ReadThru](https://apps.apple.com/gb/app/readthru/id6759448565);
  [Off Book! Pro](https://apps.apple.com/lb/app/id1072004273)). Importing is their slow,
  error-prone step. Ear Drama starts from already-parsed scripts, which is a head start worth
  showing off.
- **No published study** was found showing that remix buttons raise creation rates, or on how to
  avoid nagging creation prompts. The no-nag rule rests on the catalog skill's §5 and §8 and on
  `learning-orientation-design`, not on evidence.

### 2.3 Making a play library browsable

- **Cast size is the main way people browse plays; length comes second.**
  - Concord Theatricals filters by Play/Musical, Genre, Performance Group and Cast Size, as a total
    or by gender and age ([Concord](https://concordtheatricals.co.uk/resources/cast-size-filter)).
  - Playscripts filters by length and cast size ([Playscripts help](https://playscripts.com/help/website)).
  - Drama Online searches by cast size and roles and has a Play Finder for length or cast size
    ([Drama Online](https://www.dramaonlinelibrary.com/about-drama-online)).
  - New Play Exchange adds subject, genre and production history
    ([NYU guide](https://guides.nyu.edu/Theatre); [UCI guide](https://guides.lib.uci.edu/drama/118)).

  For friends, "how many of us are there?" *is* the question. Ear Drama can answer it from data:
  speaking parts and minutes per part are already computed.
- **No catalog found draws a cast visually.** All use text ("7f, 14m") or sliders. Ear Drama's cast
  fingerprint and presence strips (D2b) are a real distinction and should lead the play tile.
- **Shelves by form are the cheap win.** Gutenberg keeps "Plays/Films/Dramas" and a separate
  "One Act Plays" shelf ([bookshelf 642](https://www.gutenberg.org/ebooks/bookshelf/642);
  [bookshelf 55](https://dev4.gutenberg.org/ebooks/bookshelf/55)). Standard Ebooks makes a public
  domain set look curated with a written cover-art rule and one typography manual
  ([Standard Ebooks](https://standardebooks.org/about/what-makes-standard-ebooks-different);
  [manual §10](https://standardebooks.org/manual/1.8.7/10-art-and-images)). **For Ear Drama:**
  kind (radio play, one-act, full-length) and cast size come from data. The tile follows one
  written rule, the board with the fingerprint, instead of 15 identical monograms.

---

## 3. Three concepts for Home and the shell

The rules hold in all three:

- Every heading is a verb or a named data rule.
- No blurbs: descriptions come from data or a named human.
- Ranking is the same for everyone and published by the pipeline (`recommendAnd` applied).
- Personal rows come only from the person's own actions on the device.
- No counts of other people's attention on making surfaces.
- Red only inside the recorder.

### Concept A: "On the air" (radio as a place)

**Metaphor:** a radio set. Home *is* the dial. **Shell:** Listen (Home, the dial) · Browse · Search ·
Library, with Record reached only from content pages and Library. Stations stops being a tab;
Surprise is a dial position.

| Section | Job | Data |
|---|---|---|
| Now on the air | One large block: the slot playing now on tonight's evening ("Tonight in 1949 · CBS · WJSV"), the show tile, **Listen live** | `tonight.json`, current slot |
| The dial | 8 genre stations as a horizontal band. Each tile shows what is playing now; one tap plays from the clock. | `stations.json` |
| Continue | resume cards | device history |
| That night | the day board's grid (the chart moves to Browse) | `onThisDay` |
| Make one | one play block with **Record this**; the list is in Library | castable scripts |

**Strength:** the purpose is instant and unique (NTS, Radio Garden). **Weakness:** on-demand
finders and would-be makers get one row each, and Create stays secondary. That is the owner's
complaint unsolved.

### Concept B: "Listen live, find, record" (three doors, then entry rows) — recommended

**Metaphor:** a broadcasting house's front desk: what is on air, what's here, where the studio is.
**Shell:** **Home · Browse · Record · Search · Library**. Stations' full page opens from Home's live
block ("All stations"); Surprise sits in Home's toolbar on every platform. TV keeps a sidebar, and
there Record is n/a: no microphone. A five-item tab bar fits iOS and Android limits.

Home, top to bottom:

| # | Section | Job | Entry point | Data |
|---|---|---|---|---|
| 1 | **On the air** | say what this is by playing it | the current slot of tonight's evening, or of the first genre station when the evening has not started, with **Listen live** (ink) and "All stations" | `tonight.json`, `stations.json` |
| 2 | **Three doors** (one row of three equal blocks, verbs only) | the app's three jobs, visible on every visit | **Listen** (opens Stations) · **Find a show** (opens Browse) · **Record a play** (opens Record) | none (navigation) |
| 3 | **Continue** | come back | resume cards with Play on the card, first when the person has history | device history (`Store.inProgress`) |
| 4 | **Start a show** | where to begin with 1,311 shows | genre chips (the eight names) over first episodes, each tile with **Play** on it | `genreFirsts` |
| 5 | **By length** | fit the evening | three chips, *Under 15 min · About 30 min · An hour*, each a rule-ordered list | new shelf rule `byLength` over `length` (pipeline, §5.1) |
| 6 | **Record a play** | make Create exciting from the front page | **Today's play**: one big play board (fingerprint, parts, minutes) with **Listen through** and **Take a part**. Below it, **Open parts** from your own productions and invites. | castable scripts. The daily pick is a deterministic date rotation (`cross-platform-determinism`). Productions come from the Worker. |
| 7 | **This day in radio** | the almanac, kept and moved down | the existing day board and night grid | `onThisDay` |
| 8 | **Stories in parts** | serials from part one | arc first parts | arcs (411) |
| 9 | **Voices** | people as a way in | faces rail | voices (300) |
| 10 | **Made here** | finished ear dramas, credited | newest first; each page carries **Make your own** | Worker finished list |

The order shifts by one published rule: when the person has history, Continue moves above the
doors. Nothing else is personal. The footer links leave Home for Library's foot.

**Record tab** (phone/tablet/Mac/web; n/a on TV):
1. **Yours**: productions as a call sheet (Waiting on you, Open, Done; catalog skill §8). The empty
   state teaches by being a real play, with no explanation text.
2. **Plays**: the library, faceted by **How many voices** (1-2, 3-5, 6-10, 11+ speaking parts),
   **Length** (minutes from words), and **Kind** (radio play, one-act, full-length). Sorted by a
   stated rule ("Fewest parts first", "Shortest first"); never "Most downloaded".
3. **Broadcast scripts**: episodes whose script is castable, with **Record this** (empty until
   the GRW or USDA supply exists, so it is hidden when empty).
4. **Made here**.

**On content pages:**
- **Record this** (outline) sits beside **Play** (ink) on any episode or play with a castable script.
- A script's page lists the ear dramas made from it (TikTok's sound page).
- An invite link opens the playbill signed out (owner ruling 2026-10-29). The account gate comes
  at the first take.

### Concept C: "The script is the hinge" (minimal shell change)

**Metaphor:** a reading room where any script can be heard or performed. **Shell:** Decision
068's six, unchanged. Create stays an action, as the owner ruled.

| Change | Data |
|---|---|
| Home gains a **Record a play** board (as B's §6) and a **Read along** row (episodes with a shown transcript or an in-app script) | castable scripts; transcripts (8,525) |
| Browse's chips become **Shows · Plays · Voices · Ear dramas**, so Plays is a scope, not a hidden checkbox | castable scripts |
| Every episode, play, and finished drama carries **Record this** / **Make your own** | as B |
| Library's empty state names its tabs, including Ear dramas | none |

**Strength:** the smallest change, and it honors 068 exactly. **Weakness:** Home still has no "what
is on now" lead, and Create is again one row among many with no home of its own. The owner's
"designed, not bolted on" asks for more.

### How Create becomes visible and exciting (all concepts, strongest in B)

1. **Supply first.** Publish the castable library beside the catalog instead of a 15-play
   bundle (PLAYS-DESIGN §3 already plans the move). Harvest and parse the 1,722 rights-castable
   Gutenberg drama records, keeping only parse-clean texts. Add the Carlton-style radio class as
   GRW or USDA allow.
2. **Hear it first, then make it.** Listen through (device voices) is the first button on a play.
   It is the GarageBand template moment: you hear the ear drama before you commit.
3. **Record this** wherever a script exists, carrying the source. **Make your own** on every
   finished drama.
4. **Invitations are the social loop.** Open parts are shareable cards, and a friend lands on the
   playbill signed out (D1c Patterns 2 and 4). No streaks, no counts of other people.
5. **The play tile shows its cast**: the fingerprint and the "how many voices" fact lead, with
   the title in Big Shoulders on the board. No more monogram wall.

---

## 4. Recommendation

**Build Concept B.**
- It is the only concept where a newcomer can play something live in one tap from the first
  screen (the radio-app lesson).
- It names all three jobs in the first viewport (the Calm and Spotify lesson: a few verbs up top,
  rows below).
- It gives recording a place of its own *and* puts the verb on every content page (the
  TikTok/BandLab and LibriVox lessons together).
- It keeps the almanac, the voices, and direction D intact, just lower down.

Build order:
1. **Supply** (pipeline): the castable library beside the catalog, with cast-size and length
   facets.
2. **Home B** on web.
3. **Record tab** and **Record this**.
4. Port to Apple and Android in the same batch (`cross-platform-parity-discipline`).
5. Change the binding docs' shell rule first (WEB, iOS, macOS, tvOS, ANDROID), plus PARITY.md and
   a DECISIONS entry superseding 068's tab list.

Learning test (`learning-orientation-design`):
- **Understanding:** live evenings and the almanac teach how radio was scheduled.
- **Participation:** recording is invited on every script.
- **Agency:** rows are stated rules a person can read.
- **Clarity:** three verbs.

Case against: a Record tab can push making on people who came to listen. The answers are that it
is one tab, never a badge or prompt; Home's record block is one board, below listening; and
nothing nags.

---

## 5. Decisions only the owner can make

The rules already decide the account gate (at the first take, D1c), what ranks (stated rules
only), and that moods are refused (no data). Those are not asked again.

**Q1. The app's sections.**
- A. **Home · Browse · Record · Search · Library**: Stations opens from Home's live block, and
  Surprise sits in Home's toolbar *(recommended)*
- B. Home · Stations · Record · Search · Library: Browse folds into Search's empty state, as in
  Apple Music and Spotify
- C. Keep Decision 068's six sections, and add the Record board and Record this buttons only

**Q2. What opens Home.**
- A. **What is on the air now, with Listen live** (tonight's evening, else a genre station)
  *(recommended)*
- B. Continue first, then the live block
- C. The day board, as today

**Q3. A sentence saying what Ear Drama is, on the first screen.**
- A. **No sentence: the live block and the three doors (Listen, Find a show, Record a play) say
  it** *(recommended; only essential words)*
- B. One sentence you write, shown until the first play, then gone
- C. Reuse the App Store subtitle

**Q4. Growing the play library past 15.**
- A. **Publish the castable library beside the catalog, and harvest and parse every
  rights-cleared Gutenberg play that parses clean** *(recommended)*
- B. A hand-picked set of about 50, chosen by you as named editor
- C. Keep the 15 in the bundle for now

**Q5. Radio scripts on real broadcasts (598 episodes link a Generic Radio Workshop script).**
- A. **Ask GRW now for permission to perform their scripts, so Record this appears on those
  episodes** *(recommended)*
- B. Skip GRW, and build the USDA typescript harvest first (OCR repair and per-script authors)
- C. Stage plays and the four Carlton radio plays only, for now

**Q6. The play on Home's Record board.**
- A. **Today's play: a date rotation through the library, the same on every device**
  *(recommended)*
- B. The play with the fewest parts first
- C. The most recently added play

**Q7. Length doors on Home (Under 15 min · About 30 min · An hour).**
- A. **Yes, as a published shelf rule over episode length** *(recommended)*
- B. No: genre chips only
