# D1c: Making and sharing (design loop research, 2026-10-29)

The owner, 2026-10-29: *"an easy to use experience to find Ear Dramas, Listen
to them, Create them yourself, and share them with others ... entirely new
design patterns."* This report covers the last two jobs, **Create** and
**Share**. It reads what the best collaborative and sharing products do, audits
today's web app at 375 px, and ranks seven candidate patterns for D2. No code
changed. The binding rules it works inside are DESIGN-LOOP.md's constraints,
PLAYS-DESIGN §2, §5, §8 and §11.7, Decisions 059, 067, 068, 072 and 073, and
DEEP_LINKS.md.

The verdict in three lines:

1. **Sharing is broken today, not merely plain.** Every https link the apps
   send (`/series/`, `/episode/`, `/invite`) answers a crawler with HTTP 404
   and a bare `<title>Ear Drama</title>`; the site root carries only
   `og:title` and `og:type`. No link Ear Drama sends makes a preview card.
2. **An invitation does not say what it invites you to.** Signed out, it
   shows "Invitation · Sign in to join · Not now" with no title, no part, and
   no inviter. Signed in, it shows the whole cast sheet with a name field on
   every open row.
3. **The making flow works and is honest, but it is shaped like a database
   form.** Twelve "Your name" fields on one cast sheet, a part named by its
   printed abbreviation, and no view of who still owes what. The relay, the
   consent, and the line-by-line archive item are sound and stay.

---

## 1. Ear Drama's actual material (measured, not guessed)

Read from `catalog/plays/castable-scripts.json` and
`worker/src/castable-manifest.json` on 2026-10-29. Fifteen castable scripts:
four Carlton radio plays (NBC *Great Moments in History*) and eleven stage
plays.

| Script | Kind | Parts | Lines | Words | Minutes at 150 wpm | Largest part | Smallest parts (lines, words) |
|---|---|---|---|---|---|---|---|
| Caesar Rodney's Ride | radio | 12 | 350 | 3,894 | ~26 | URIAH 97 | BOTH (1, 1), VOICE (7, 33), HANCOCK (10, 108) |
| The Landing of the Pilgrims | radio | 10 | 294 | 4,083 | ~27 | JONES 71 | MOB (1, 14), ALL (3, 16), VOICE (7, 32) |
| The Story of Nathan Hale | radio | 13 | 408 | 4,399 | ~29 | HALE 146 | ALL (1, 3), BOS'N (7, 44) |
| The Tree That Saved Connecticut | radio | 10 | 355 | 4,124 | ~27 | TREAT 95 | WILLYS (9, 45), VOICE (14, 72) |
| A Tender Attachment | stage | 7 | 297 | 3,882 | ~26 | EBEN 62 | LOOP (17, 183) |
| The Albany Depot | stage | 6 | 166 | 7,202 | ~48 | CAMPBELL 62 | BOTH LADIES (4, 4) |
| Hamlet | stage | 31 | 1,201 | 27,034 | ~180 | HAM 339 | ALL (5, 16), PLAY (5, 33) |
| The Tenth Man | stage | 14 | 1,720 | 22,826 | ~152 | GEORGE WINTER 431 | ALL (1, 5) |
| (seven more) | stage | 10-38 | 148-992 | 7,658-22,129 | 51-148 | | |

What this means for design:

- **The radio four are the evening-sized plays**: 10-13 parts, under half an
  hour, one large lead and a handful of walk-ons. They are the natural first
  ear drama for a family or a class.
- **Walk-on parts are common**: 47 of the 243 speaking parts have 60 words or
  fewer. A first-timer can finish a whole part in under a minute of reading.
  That is the answer to "from I'd like to try to a recorded line in under a
  minute": not a shortcut around the relay, a small part inside it.
- **Group parts exist in most scripts**: ALL, BOTH, MOB, OMNES, WOMEN, BOTH
  LADIES. Today one person takes each like any other part.
- **Names are printed abbreviations** in several stage plays (HAM, HOR, COL,
  DOR, RUT, ARN, O'DOGH, MRS. DIG). The parser keeps them as printed (§3,
  "stored as printed for an alias table to expand later"). On an invite card
  "Play HAM" reads as a typo. The script's own dramatis personae is the source
  for the full name; no model may expand it (§8 rule 2).
- **One manifest title carries a trailing space** ("The Albany Depot "), and
  The Albany Depot lists both CAMPBELL and MRS. CAMPBELL (a possible alias the
  parser flagged class of, §3).

---

## 2. Findings from other products, with sources

### 2.1 Inviting people into a shared piece of work

- **LibriVox dramatic readings** run casting as a public table, the Magic
  Window: "Look in the Magic Window for the list of available roles", one row
  per role, and readers claim by posting; recordings are "generally due within
  2 months" or the role may be reassigned. The coordinator is a named human
  per project. ([Information on coordinating dramatic readings](https://wiki.librivox.org/index.php/Information_on_coordinating_dramatic_readings);
  [How To Become A Book Coordinator](https://wiki.librivox.org/index.php/How_To_Become_A_Book_Coordinator);
  research 08c §1.1.) **Steal**: the table of parts as the single shared
  picture of the production, with a due date as a fact. **Refuse**: forum
  bookkeeping.
- **Off Book! Pro LineSync**: "Invite your actors by email; they sync
  everything to their own phone ... As castmates record their lines, the
  director hears them show up automatically — no nagging." The director pays;
  the cast never does. ([App Store listing](https://apps.apple.com/app/id1072004273).)
  **Steal**: the director's view fills in by itself. Ear Drama already does
  this by re-reading the record on return (§11.7 rule 7).
- **BandLab** invites collaborators by username or email from the project's
  menu ([BandLab help](https://help.bandlab.com/hc/en-us/articles/48010528581529-How-do-I-invite-other-users-to-collaborate));
  **Soundtrap** offers both a named invite and "a simple link" from the studio,
  and an invitee gets "a link on top of their own project page allowing them to
  accept" ([Leeds guide](https://desystemshelp.leeds.ac.uk/podcasting-student/collaborating-in-soundtrap/);
  [Soundtrap blog](https://soundtrap.com/content/blog/collaboration)).
  **Steal**: the accept sits where the person already looks (Library's Ear
  dramas, as today).
- **Anchor / Spotify for Podcasters "Record with friends"**: the host shares a
  direct link and guests "can join via the link you send them" without an
  account; the feature is being withdrawn ([Spotify help](https://help.anchor.fm/hc/en-us/articles/115002381311);
  [Engadget, 2020](https://www.engadget.com/2020-03-24-anchor-record-with-friends-update.html)).
  **Lesson**: account-free joining lowers the door but leaves the service no
  way to act on abuse, which App Store guideline 1.2 requires; Ear Drama's
  owner rule (recording needs an account, 2026-10-23) stands, so the door must
  be lowered elsewhere: let the invite be read before sign-in.
- **Jackbox**: players join from a phone's browser at jackbox.tv with a room
  code, and "we do not offer or require" an app
  ([Jackbox support](https://support.jackboxgames.com/hc/en-us/articles/15794771245975-How-do-I-get-started-playing-Jackbox-Games),
  403 to our fetcher; quoted from the search result). **Steal**: the invite
  opens a page that works with nothing installed. Ear Drama's web app can be
  that page.
- **Discord invite embeds** show the server's name, icon, member count, how
  many are online, and one Join button
  ([discord-guildpeek README](https://unpkg.com/discord-guildpeek@1.2.3/README.md);
  [Discordeno invite type](https://discordeno.js.org/api_reference/generated/@discordeno/bot/interfaces/DiscordInvite)).
  **Steal**: an invite is a card of facts about the group, readable before
  joining.
- **Figma multiplayer**: "every user in the document gets an avatar in the top
  right corner", and clicking one follows that person; the post says
  multiplayer "reduced the overall complexity" of the UX
  ([Evan Wallace, Figma blog 2016](https://madebyevan.com/figma/multiplayer-editing-in-figma/)).
  **Steal**: presence is a row of names, not a feed. **Refuse**: live cursors;
  Ear Drama's relay is asynchronous and the owner chose re-read over a socket
  (§11.8, clarity).
- **Google Docs assignees**: a checklist item or comment can be assigned to a
  person, highlighted in the document, and badged on the home screen as
  needing their attention ([Assign tasks from Google Docs](https://support.google.com/docs/answer/12048749);
  [Workspace Updates 2022](https://workspaceupdates.googleblog.com/2022/07/tasks-integration-in-google-docs.html)).
  **Steal**: "who still owes" is shown on the item they owe, and the owing
  person sees a mark on their own home.

### 2.2 From "I'd like to try" to a recorded line

- **Voice Memos** is one red button to start and a red square to stop
  ([guide](https://voicenotes.com/blog/record-voice-memo-iphone)). Ear Drama's
  prompter already has the one control (07-prompter); what stands between a
  newcomer and it is everything before it.
- **GarageBand Live Loops**: tap a cell, Record Into Cell, a count-in, and the
  take lands in that cell ([Cult of Mac how-to](https://www.cultofmac.com/how-to/how-to-use-live-loops-garageband);
  [Apple guide](https://support.apple.com/guide/garageband-ipad/chs371e72c01/ipados)).
  **Steal**: the unit you record is small and visible in a grid of what
  others recorded. Ear Drama's unit is the line, already.
- **Duolingo** runs the first lesson before asking for an account; moving the
  sign-up "back a few steps led to about a 20% increase in DAUs"
  ([Taplytics on the A/B test](https://taplytics.com/blog/duolingo-ab-test-onboarding);
  [Appcues](https://goodux.appcues.com/blog/duolingo-user-onboarding)).
  **Steal**: everything up to the first take is open (read the invite, pick a
  part, hear the scene); the account is asked at Start recording, which is
  exactly where PLAYS-DESIGN §2.3 already puts it. Today the invite asks
  earlier than the rules require.
- **Descript** edits audio by editing the transcript
  ([The Podcast Host review](https://www.thepodcasthost.com/editing-production/descript-review/)).
  **Steal**: the text is the interface (the script is Ear Drama's timeline).
  **Refuse**: Overdub, which types new words in a cloned voice: a stored
  synthetic voice, forbidden (§5, Decision 055).

### 2.3 What a finished piece's page is

- **YouTube Premieres**: before the start time the watch page offers a
  reminder and chat, a countdown runs, and then everyone watches together;
  afterward it becomes an ordinary upload ([YouTube Help](https://support.google.com/youtube/answer/9080341)).
  **Steal**: a first listening at a time, together, then the page stays.
  Ear Drama has Listen Together rooms (Decision 065) to carry it.
- **LibriVox's Cast Coder** builds a cast list from data, each reader linked
  to their reader page (08c §1.1). **Steal**: credits from records only.
- **archive.org** is where a published production lives today, one file per
  line in Community Audio (Decision 073). It is the durable store, not a
  premiere: its page is the archive's, and nothing on eardrama.org points at a
  finished ear drama for anyone outside the cast.

### 2.4 Share cards and link previews

- **Open Graph** names four required properties, `og:title`, `og:type`,
  `og:image` and `og:url`, plus `og:image:alt` and `og:audio`
  ([ogp.me](https://ogp.me/)). Ear Drama's root page has two of the four; every
  deep path has none.
- **Messages rich links**: Apple shows `og:image` "at a fairly large size", so
  it should be representative; generic logos belong in the icon
  (`apple-touch-icon`), not `og:image`; images should not carry text
  ([TN2444, Best Practices for Link Previews in Messages](https://developer.apple.com/library/archive/technotes/tn2444/_index.html);
  [WWDC19 session 262 notes](https://wwdcnotes.com/notes/wwdc19/262/)). The
  current note, TN3156, would not render for our fetcher
  ([TN3156](https://developer.apple.com/documentation/technotes/tn3156-create-rich-previews-for-messages)),
  so its deltas are UNVERIFIED. A note on the text rule: Apple's advice is
  about photos; Ear Drama's default art is the typographic card
  (`artwork-presentation-design`), which is text by design, so the card's
  words must be few and large.
- **Crawlers read static HTML.** A 404 status and tags written by script are
  the common reasons a preview fails ([link.boo guide](https://link.boo/guides/facebook-link-preview-not-updating);
  [Webflow thread](https://discourse.webflow.com/t/404-page-previews-and-errors-on-facebook-debugger/314940/1)).
  Ear Drama's own DEEP_LINKS.md rule 4 already says it: "GitHub Pages serves
  `404.html` with an HTTP 404 status, and several link-preview crawlers refuse
  to preview a 404 ... Generate `/list/index.html`". The rule was written for
  Archive Watch's playlists and never applied to Ear Drama's paths. X's card
  documentation answered 402 to our fetcher and is not cited.
- **Strava** shares an activity as a transparent "stats sticker" to Instagram
  Stories, available only for activities visible to followers or everyone
  ([BikeRadar](https://www.bikeradar.com/news/strava-sticker-stats-spring-2025-updates);
  [Tom's Guide](https://www.tomsguide.com/wellness/fitness/stop-screenshotting-your-runs-this-hidden-strava-feature-looks-much-cleaner-on-instagram)).
  **Steal**: the share is a picture of facts the person earned, and private
  things cannot be shared. **Letterboxd** has no documented first-party story
  card; the market filled it with third-party card makers
  ([Stories For Letterboxd](https://justuseapp.com/en/app/1547107511/stories-for-letterboxd/reviews);
  [boxdp](https://awesome.ecosyste.ms/projects/github.com%2Flinuxdotexe%2Fboxdp)),
  which says people want the card enough to pay for it.
- **Wordle's grid** shares "how you did without ruining the game", in plain
  Unicode that pastes anywhere ([Know Your Meme](https://knowyourmeme.com/memes/subcultures/wordle);
  [The Spinoff](https://thespinoff.co.nz/media/13-01-2022/those-coloured-boxes-on-twitter-are-new-zealands-fault)).
  **Steal**: a share made entirely of facts and structure, no copy, works in
  every app.

### 2.5 Sharing a listening moment

- **Spotify** added "share from" the current time in 2021, then Podcast Clips;
  the share menu now offers the episode, a chapter, a timestamp, or a clip
  ([9to5Mac](https://9to5mac.com/2021/05/10/spotify-for-ios-now-lets-you-share-timestamped-podcasts-heres-how/);
  [iGeeksBlog](https://www.igeeksblog.com/spotify-podcast-clips-share-links/)).
- **Apple Podcasts** shares from a timestamp by selecting text in the
  transcript, "Share from [timestamp]" ([Apple Podcasts guide](https://support.apple.com/guide/podcasts/pod96aaf8353/mac);
  [Gadget Hacks](https://apple.gadgethacks.com/how-to/how-to-use-apple-podcasts-settings-playback-sync/)).
- **Apple Music lyric cards**: long-press a line of live lyrics, choose up to
  five lines, and the card goes to Stories or Messages, where it plays the
  clip of those lines ([iMore](https://imore.com/you-can-share-apple-music-lyrics-instagram-and-imessage-new-beta);
  [RouteNote](https://routenote.com/blog/apple-music-adds-the-ability-to-share-lyrics-and-music-clips-on-instagram-stories-or-imessage/)).

**This is the strongest fit for Ear Drama's rules.** A production's script is
the play's own printed words, already line by line with stable ids. "Share
this line" puts the printed line, its speaker, and its performer on a card and
links to that line. Every word on it is the script's or the person's; none is
the app's or a model's. Catalog episodes have transcripts on some records
(`#transcript` in `js/app.js`), and a timestamp link serves the rest.

---

## 3. Audit of today's Create and Share (web, 375 px)

**How the shots were made.** Headless Chrome (public release) over the
DevTools protocol, a 375 px iframe in a 420 px window, served from a scratch
copy of this worktree on port 8917 with the main checkout's clean web
projection and this worktree's castable scripts. A fixture script replaced
`fetch` for the Worker's origin only (sign-in, one shared production of
*Caesar Rodney's Ride* with Pat, Sam and Ada, consent, an invite); the app's
own code ran unchanged. The microphone was Chrome's fake device; nothing was
audible (`--mute-audio`). The server and Chrome were stopped after; `pgrep`
found neither. Shots are 1x, full height of the scrolling `main`.

| Shot | What it is |
|---|---|
| `img/d1c/01-play-page.png` | A play's page, signed out |
| `img/d1c/02-cast-sheet-signed-out.png` | Cast sheet after Start an ear drama |
| `img/d1c/03-record-needs-account.png` | Take part, signed out, at the recorder |
| `img/d1c/04-library-ear-dramas.png` | Library, Ear dramas, signed in |
| `img/d1c/05-record-headphones.png` | Recorder start: the headphones refusal |
| `img/d1c/06-room-tone.png` | Room tone countdown |
| `img/d1c/07-prompter.png` | The prompter: cue, your line, the next line, one control |
| `img/d1c/08-cast-sheet-signed-in.png` | Local cast sheet with Share |
| `img/d1c/09-shared-cast-sheet-director.png` | Shared production, director, mid-relay |
| `img/d1c/10-invite-link-made.png` | Invite made: the link field and Share link |
| `img/d1c/11-complete-waiting-on-consent.png` | Complete; the agreed list and Publish |
| `img/d1c/13-published.png`, `13b-published-lines-open.png` | Published; Lines opened |
| `img/d1c/14-invitation.png` | Invitation, signed in |
| `img/d1c/15-invitation-signed-out.png` | Invitation, signed out |
| `img/d1c/12-episode-share-button.png` | An episode page's Share (the OS share sheet cannot be shot headless; it receives the title and URL below) |

### 3.1 The link preview a shared https link produces today

Fetched 2026-10-29 with the user agents `facebookexternalhit/1.1`,
`Twitterbot/1.0` and `Slackbot-LinkExpanding 1.0` (the same answer for all
three):

| URL (who sends it) | Status | What a crawler gets |
|---|---|---|
| `https://eardrama.org/` | 200 | `<title>Ear Drama</title>`, `og:title` "Ear Drama", `og:type` website. No `og:image`, `og:url`, or description |
| `https://eardrama.org/series/suspense` (iOS, macOS, Android Share) | **404** | `<title>Ear Drama</title>` only (the `404.html` forwarder) |
| `https://eardrama.org/episode/{id}` (iOS, macOS, Android Share) | **404** | the same |
| `https://eardrama.org/invite#{token}` (every platform's Invite) | **404** | the same |
| `https://eardrama.org/?series=suspense` (the web's Share) | 200 | the root's generic two tags |

So a series shared from an iPhone previews, at best, as a bare
"eardrama.org" line, and Facebook-family crawlers may show nothing. Two
shapes for one link also exist: the web shares `?series=` and `?item=`
(`js/app.js` `share()`), the apps share `/series/` and `/episode/`
(`apple/Core/Store/SiteLinks.swift`, `android/.../navigation/SiteLinks.kt`).

### 3.2 Inventory: every field and step, keep / move / cut

**A play's page** (01)

| Field or step | Mark | Reason |
|---|---|---|
| Title | keep | The thing itself |
| Author with years | keep | Decision 067: plays are marked by facts from the record |
| "12 parts · 350 lines" | keep, reword as time | A newcomer asks "how long", not "how many lines"; "~26 min · 12 parts" is computable from words (150 wpm is an estimate, so say "about") |
| Rights evidence and source, linked | keep | §2.1, catalog rules; never "public domain" on our authority (the link text is Gutenberg's own claim) |
| Start an ear drama | keep | The verb (Decision 068). Spacing defect: it touches the Parts header |
| Parts list with line counts | keep, enrich | It is the cast; add each part's size as time and mark walk-ons by fact (pattern 3) |
| Group parts ALL, BOTH as ordinary rows | move | See pattern 7 |

**Cast sheet, one device** (02, 08)

| Field or step | Mark | Reason |
|---|---|---|
| "0 of 350 lines recorded" | keep | The relay's progress, a fact |
| A "Your name" field on every open row (12 on Rodney) | **cut to one** | The person typing is the same person on every row; ask once per production on this device (or take it from the account), and let the relay's "pass the phone" ask the next person at Take part |
| Take part, the largest highlighted | keep | C7: suggested, never forced. Color: the highlight is the filled blue accent; Decision 064 gives ink to the primary action and blue to links, focus and the selected tab. Owner to rule whether Take part is a primary action (ink) or a wayfinding one |
| Leave silent (sound, directions) | keep | §2.2 |
| "Listen through" heading and a "Listen through" button | cut the heading | Says the same thing twice |
| Share with "Your name" | move | Into the director's first Invite; "Share" as a word means publishing to most people, but here it means "make this production multi-device" |
| Sharing needs an account. | keep | A refusal |
| Discard unused takes, Delete production | keep, move down | Rare; Delete is drawn as a blue link, which reads as wayfinding (064) |

**Recorder** (03, 05, 06, 07)

| Field or step | Mark | Reason |
|---|---|---|
| Recording needs an account. + Sign in | keep | Owner rule 2026-10-23; a refusal |
| Headphones refusal + "My headphones are on" | keep | §4.3; the web cannot see the route |
| Room tone countdown | keep | §2.3 |
| Cue line dim, your line large, next line dim | keep | The teleprompter; clear |
| One record control, previous and next | keep | §7 one action |
| Run-up, Hear it read, speed, Keep | keep, group | Four equal buttons; Keep is the frequent one and belongs beside the record control |
| Done with this part + "97 lines to go" | keep | A fact |
| Part title as the page title ("URIAH") | keep, expand | The printed name, plus the dramatis personae's full name where the script has one |

**Shared production, director** (09, 10, 11, 13)

| Field or step | Mark | Reason |
|---|---|---|
| Parts with "Recorded · Pat" | keep | Who did what, from the record |
| Who holds an open claim, and since when | **add** | Today a claimed part shows only "n of m recorded · Name"; the 7-day lapse (§11.2) is not on screen, so a director cannot see who still owes and until when (pattern 4) |
| Open part on others' finished parts | keep | Director's right (§11.2) |
| Upload N takes, Done with this part | keep | §11.7 rule 5 |
| Listen through | keep | C5 |
| Agreed list (names with check or circle), no heading | keep, label | Unlabeled it reads as a second People list; the director is shown with a circle although the director agrees at Publish (`waitingOn` excludes them) |
| Publish, disabled while waiting | keep | Rule 6 |
| People with Report and Block on a line of their own each | keep, compact | Guideline 1.2 needs them; the row wastes a full line per member |
| Invite: link field, Share link, "Works for 7 days." | keep, enrich | The fact is right; the link carries no part and no inviter, and the preview it makes is a 404 (3.1) |
| On archive.org link | keep, and add the premiere | Rule 9; but nothing on eardrama.org shows the finished play to anyone outside (pattern 5) |
| Lines (Replace, Remove) in a disclosure | keep | P12, Decision 073 |

**Invitation** (14, 15)

| Field or step | Mark | Reason |
|---|---|---|
| Signed out: "Invitation", Sign in to join, Not now | **change** | No title, no part, no inviter: the person is asked to sign in to an unknown thing. The facts should come first (pattern 2) |
| Signed in: the play's title, then every part with a name field and Take part | **change** | The invite should lead with the part the director meant, or the suggested one, and one name field |
| "Recorded" with no performer's name | add the name | Who is already in it is the main reason to say yes |
| Not now | keep | |

**Library, Ear dramas** (04)

| Field or step | Mark | Reason |
|---|---|---|
| Each production with its progress or "Shared" | keep, enrich | "Shared" hides the one fact a member needs: whether it is waiting on them |
| Classes, with Make a class and Join a class forms, shown to everyone signed in | move | A teacher's tool takes two forms of space from every listener; a "Classes" row that opens them is enough |

**Sharing an episode or series** (12)

| Field or step | Mark | Reason |
|---|---|---|
| Share button on episode and series pages | keep | |
| What it sends | fix | Title and a URL that previews as nothing (3.1) |
| A moment in the episode | add | Only the whole episode can be shared (pattern 6) |

---

## 4. Candidate patterns, ranked

Ranked by how much each serves the Create and Share jobs per unit of cost,
and by the four questions of `learning-orientation-design`. Costs are S (a
day or less), M (a few days), L (a week or more) per platform, from reading
the code paths named.

### 1. Real share pages: every link previews as itself

Generate a static HTML page per shared path at publish time, as DEEP_LINKS.md
rule 4 already prescribes for lists: `/series/{key}/index.html`,
`/episode/{id}/index.html` (or one page per series that the forwarder serves),
`/play/{id}/index.html` for each castable script, and `/invite/index.html` and
later `/drama/{pid}/index.html`. Each carries `og:title`, `og:type`,
`og:url`, `og:image` (the typographic card, rendered at build time from the
series name and genre hue, `artwork-presentation-design`), `og:image:alt`,
`og:description` from the record's own fields only (date, network, "12 parts
· about 26 minutes"), and a script that hands off to the router. One URL
shape everywhere (the path form); the web's `share()` switches to it.

- **Surfaces**: what was shared, before anyone taps. **Hides**: nothing new.
- **Rules**: data only (no blurb); unclaimed recordings get no rights claim;
  the invite page is generic on purpose, since its token rides the fragment
  and no server sees it (DEEP_LINKS.md rule 3).
- **Learning test**: clarity; a preview tells the receiver what they are
  being handed, so the choice to open it is theirs.
- **Cost**: web M (a generator in `catalog/tools` or `tools/assemble_site.sh`,
  ~624 series and their episodes; page count to measure against Pages' 1 GB
  site limit, one page per series with the episode in the fragment if needed);
  iOS/iPadOS, macOS, Android S (change nothing but confirm their links
  already use the path form; add `LPLinkMetadata` from data to the share item
  on Apple, `EXTRA_TITLE` is set on Android); tvOS S (its QR codes encode the
  same URLs).

### 2. The invitation card: facts first, sign-in at the first take

The invite opens a card, signed in or not: the play's title, author and
length; the part the director invited you to (or the suggested one); who is
already in and in which parts ("URIAH · Pat, RODNEY · Sam"); how many parts
are open; "Works for 6 more days." Actions: **Take MCKEEN** (or pick another
open part), **Hear the scene** (a listen-through of the takes so far, which
C5 already allows), **Not now**. Sign-in is asked at Start recording, where
the owner's rule puts it, not at the door. The director's Invite may name a
part (`/invite#{token}` plus a part id inside the fragment), which is casting:
a person's judgment, not the app's.

- **Surfaces**: who, what, how big, how long. **Hides**: every other part's
  name field; the whole cast list behind "Other parts".
- **Needs**: a Worker change so `POST /invites/view` answers with facts
  without an account (the 256-bit token is the secret; it already rides the
  fragment). Owner rulings: whether a signed-out person may read the cast's
  chosen names, and whether listening to members' takes before joining is
  allowed (takes reach only members today, Decision 072).
- **Learning test**: participation and agency; the invitee chooses with the
  facts in front of them, and hears whom they would play opposite.
- **Cost**: Worker M (an unauthenticated view, its tests and mutations);
  web M; iOS/iPadOS M (the inbox already opens Library's invitation);
  macOS S (shares the view); Android M; tvOS n/a (invites stay off the TV,
  DEEP_LINKS.md).

### 3. First line in a minute: one name, walk-on parts, time not lines

Ask the performer's name once per production on a device (or from the
account), not on every row. Show each part's size as reading time from its
word count ("about 1 min", "about 7 min") beside its lines. Mark parts of 60
words or fewer as small by fact (47 of 243 parts today), so a first-timer, a
shy child, or a guest at the table can take VOICE in *Caesar Rodney's Ride*
(7 lines, 33 words) and be done before the kettle boils. Put **Keep** beside
the record control. Suggesting the largest part first stays (C7); a newcomer's
path is a filter, never an assignment.

- **Surfaces**: effort, in the unit people think in. **Hides**: eleven name
  fields; the four-button row behind two.
- **Learning test**: participation with a low floor and a high ceiling (the
  lead is still there); no automation, no model.
- **Cost**: web S; iOS/iPadOS S; macOS S; Android S; tvOS n/a (records
  nothing). The word counts are in the bundle (`roles[].words`).

### 4. The call sheet: who still owes a part, and until when

Turn the shared cast sheet into a call sheet, grouped by state: **Waiting on**
(claimed: the performer's name, "12 of 44 lines", "claimed Oct 25 · open
again Nov 1", the 7-day lapse as a date), **Open** (with the suggested one
first), **Done** (name, date of the last take). On the member's own Library
row: "Waiting on you: MCKEEN, 32 lines" in place of "Shared". The director's
**Send the invite again** opens the share sheet with the invite link and the
part's name, words the director types or leaves; the app writes none.

- **Surfaces**: the one fact a group needs ("who still owes") on the item
  owed and on the owing person's own list, as Docs badges a file.
  **Hides**: nothing; it reorders.
- **Needs**: the record already holds claims; a claim's start time (to compute
  the lapse date) may need adding to `GET /productions/:pid`.
- **Learning test**: clarity and connection; no nagging notifications, no
  streaks, no shaming (LibriVox: "Make only positive comments").
- **Cost**: Worker S (expose `claimed_at`); web M; iOS/iPadOS M; macOS S;
  Android M; tvOS S (read-only call sheet on its playback screen).

### 5. The premiere page: a finished ear drama as an event

Once a production is on archive.org, it gets a page at
`eardrama.org/drama/{pid}`, built from data: the title and author; the cast as
part, then performer's chosen name; who played opposite whom (from each
take's `heard`, PLAYS-DESIGN §4.2); "recorded Oct 23 to Oct 29"; the script's
source and rights evidence; the archive.org item; one **Listen** that plays
the line files in script order from archive.org (no mixed file is published,
Decision 073); and **Listen together** at a time the director picks, through
the existing rooms (Decision 065), which is the premiere. The poster is the
typographic card with the title and the cast's names, which is also the
page's `og:image`. A line removed from the item drops from the page at the
next build; a performer whose last line leaves leaves the credits, as on the
item.

- **Surfaces**: the people, the play, and when it was made; this is the
  thing a family wants to send grandparents. **Hides**: every control of the
  making flow.
- **Rules**: names only as people chose them; under-13 productions never
  reach archive.org without a school's consent (§11.5), so they never reach
  this page either. The premiere page lists only published productions,
  never in-progress ones, and never ranks them (no likes, no counts, 08c §7).
- **Owner rulings**: whether finished productions are findable on
  eardrama.org beyond their own link (a listing is a feed decision,
  `values-based-feed-ranking`), and whether the cast's chosen names may be on
  a page Ear Drama itself serves.
- **Cost**: web L (a static generator reading the Worker's published list,
  the in-order player); Worker S (a public list of published productions with
  data fields only); iOS/iPadOS M (a Library and deep-link destination that
  plays the line files); macOS S; Android M; tvOS M (it plays back already,
  §11.7 rule 12; the premiere room is the new part).

### 6. Share a line: the play's own words as the card

While listening through a production or an episode with a transcript, a
long-press (or the line's menu) on the line on screen offers **Share this
line**: a card with the printed line, its speaker, its performer (for a
production) or the episode's date and network (for a catalog episode), and a
link that opens at that line (`/drama/{pid}#line=L0042`) or at a time
(`/episode/{id}#t=1312`). Without a transcript, "Share from 21:52" works on
any episode. Apple Music's lyric cards and Apple Podcasts' "Share from
[timestamp]" are the models; every word is the script's or the record's.

- **Surfaces**: a moment, not a whole evening. **Hides**: nothing.
- **Rules**: no excerpt audio is cut and stored on the server; the link
  points into the item. A card for an unclaimed recording carries no rights
  claim. Lines of a production that is not published cannot be shared
  (Strava's rule: private things cannot be shared).
- **Cost**: web M (line and time fragments in the router, a card image drawn
  on a canvas); iOS/iPadOS M (`ImageRenderer` card, `ShareLink`); macOS S;
  Android M (Compose to bitmap); tvOS S (a QR code of the same link).

### 7. Group lines as everyone's part

ALL, BOTH, MOB, OMNES and WOMEN are crowd lines in the printed script. Let any
member record them, and play every member's take of a group line together,
as a crowd does. A walk-on that every member of the cast can join, and a
reason for the whole room to speak at once.

- **Surfaces**: the play's ensemble moments. **Hides**: nothing.
- **Needs**: the mix and listen-through to layer several takes on one line
  (the timeline is plain data, §4.2, but the renderer, the golden timeline
  test on every platform, and the Worker's one-chosen-take-per-line rule all
  change); the archive item's one-file-per-line naming would need a suffix
  per performer (Decision 073). Owner ruling.
- **Cost**: web M; iOS/iPadOS M; macOS S (shared Core); Android M; Worker M;
  tvOS S (plays back the layered plan).

Considered and refused:

- **Account-free recording behind an invite** (Anchor's model): contradicts
  the owner's rule that recording needs an account (2026-10-23) and leaves no
  way to act on abuse (guideline 1.2).
- **A feed of finished productions with plays or likes**: 08c §7's "no feeds
  of trending takes, no likes"; a listing, if the owner wants one, is a
  ranking decision under `values-based-feed-ranking`.
- **Live cursors or live presence**: the relay is asynchronous; re-reading on
  return is the chosen clarity (§11.8).
- **Generated share copy or summaries**: no AI-written copy.
- **A clip editor for vertical video** (social-clip-creation.md): Archive
  Watch's film problem, not Ear Drama's; audio-first sharing is a line card
  with a link.

---

## 5. Seen on the way (not fixed)

| File | Symptom | Proposed fix | Owner? |
|---|---|---|---|
| `404.html`, `index.html` | Every shared deep link is a 404 with no preview; the root has two of four required OG tags | Pattern 1 | No |
| `js/app.js` `share()` vs `SiteLinks.swift`, `SiteLinks.kt` | Web shares `?series=`/`?item=`, the apps share `/series/`/`/episode/` | One path form | No |
| `js/plays-ui.js` `inviteBox` | Signed out, the invitation shows no title or part | Pattern 2 (needs a Worker change) | Yes, what a signed-out person may read |
| `js/plays-ui.js` `renderProduction`, `inviteBox` | A name field on every open part | Ask once per production | No |
| `js/plays-ui.js` `listenThrough` | Heading and button both "Listen through" | Drop the heading | No |
| `js/plays-ui.js` `sharedListen` | Agreed list has no heading; the director is shown "not yet" though they agree at Publish | Label it; omit the director | No |
| `js/plays-ui.js` `peopleBox` | Report and Block take a full extra row per member at 375 px | Inline them, or one menu per member | No |
| `js/plays-ui.js` `renderScript` | Start an ear drama touches the Parts header | Spacing token | No |
| `js/plays-ui.js` `deleteButton` | Delete production is drawn as a blue link | Ghost destructive style, never red (064) | No |
| `js/plays-ui.js` Take part `btn-accent` | Filled blue on the suggested part; 064 gives ink to the primary action | Owner to rule whether Take part is primary | Yes |
| `js/plays-ui.js` `renderMine` | Classes' two forms show to every signed-in person | A Classes row that opens them | No |
| `catalog/plays/castable-scripts.json` | Title "The Albany Depot " has a trailing space; CAMPBELL and MRS. CAMPBELL may be one part | Trim in the builder; the alias is an editing call | Alias: yes |
| `catalog/tools/script_parse.py` | Abbreviated speakers (HAM, COL, RUT, O'DOGH) are what people see on cast sheets and would see on invites | An alias table from each script's own dramatis personae (§3 already plans it) | No |

---

## 6. What D2 should take from this

- The **Create** surface's metaphor is already right and literal: a cast
  sheet, a call sheet, a teleprompter. Make it lighter, not new.
- The **Share** surface needs building, not restyling: real pages, one URL
  shape, cards from data, and a page for a finished ear drama.
- Patterns 1, 3 and the defects above need no owner ruling and are cheap on
  every platform; patterns 2, 4 and 5 need the small Worker changes and the
  rulings named; pattern 7 is a later round.
