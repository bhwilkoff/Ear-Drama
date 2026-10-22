# Case study: Archive Watch

On the evening of April 17, 2026, I started an app for watching old
public-domain films on an Apple TV. By September 30 it ran on iPhones,
iPads, Macs, Apple TVs, Android phones and tablets, Google TVs, Fire TVs,
Rokus and the web, from one repository, in 4,306 commits. 2,753 of those
commits carry Claude's name as co-author.

This page tells that story from the git history, for folks who have
never heard of the app. It is the clearest record I have of what
building human-shaped software with an agent actually looks like, day
by day, including the parts that went wrong.

## What Archive Watch is

The Internet Archive (archive.org) holds a huge collection of films,
television, cartoons, newsreels and old commercials that are in the
public domain, free for anyone to watch. Most of it is hard to browse.
Titles are inconsistent, posters are missing, and nothing tells you
what is worth your evening.

Archive Watch calls itself "a cinematheque for the Internet Archive.
Free, public domain, no account." It holds around 32,000 titles, each
with posters, cast and genres gathered from open sources like Wikidata
and the Library of Congress. It has no ads, no subscription, no account
and no tracking. Your favorites sync only through your own cloud.

I want it to feel like wandering a good repertory cinema, not scrolling
a feed. So you browse by decade, genre and collection, the way the
archive is actually organized, and a film ends with a choice of what to
watch next, never an autoplay.

## The numbers

| | |
|---|---|
| First commit | April 17, 2026, 5:31 pm |
| Commits through September 30 | 4,306 |
| With a Claude co-author line | 2,753 |
| By the GitHub Actions bot (the data pipeline refreshing itself) | 1,439 |
| Under my name with no Claude line | 108 |
| By Claude Code on the web, in the first two days | 6 |
| Days with at least one commit | 129 of 167 |
| Busiest month | September, 2,219 commits |

Leave out the pipeline's own commits, and 96% of what remains was
written with Claude. I wrote almost none of the code. I wrote the wish,
the values, the feedback and the decisions.

## The timeline

| Platform | Code first appeared | In a store |
|---|---|---|
| Apple TV (tvOS) | April 17 | App Store, June 10 |
| iPhone and iPad | June 9 | App Store (same listing) |
| Web, archivewatch.org | June 9 | Live at the site root, June 10 |
| Android phones and tablets | June 9 | Google Play production by June 29 |
| Mac | June 22 | App Store (same listing) |
| Android TV and Google TV | August 3 | Google Play (same listing) |
| Fire TV | August 3 | Amazon Appstore, live by September 7 |
| Google Cast receiver | August 4 | Published August 6 |
| LG and Samsung TVs | August 3 | Not submitted as of September 30 |
| Roku | September 3 | Roku Channel Store, live by September 10 |

There is no Windows version of Archive Watch. Windows was built for a
different app, Tidbits Trivia. The full data, with the commit behind
every date, is in `data/archive-watch-timeline.json`.

## April: one platform, and data before design

The first session ran in Claude Code on the web, partly from my phone.
Its first commit was not code. It was research: "Add research docs for
metadata sources and design reference." The second logged the first
decisions, including that the app would be for the Apple TV only.

The next morning I moved to the Mac, because, as I told the agent, "you
can do things that the desktop app cannot." By the third day the
catalog held 799 films. That day I sent 55 prompts, and the commit
subjects run "UI feedback pass," then "round 2" through "round 6." Each
round was a numbered list of what I saw in the simulator.

The same day the agent fought Apple TV's focus system for hours. I
stopped asking for fixes and asked for skill instead:

> I want an overall upgrade of skills and not just fixes for these
> individual items

The commit that followed, a tvOS design and engineering playbook, is
the seed of this template's `tvos-platform-patterns` skill.

**Lessons:** start with real data, look at the real app the first day,
and send feedback in numbered rounds (stage 01). When the agent keeps
guessing, ask for research, not another fix (stage 04).

## May: five weeks away

April has 65 commits. May has 29, almost all on its last day. I stepped
away. On May 31 I came back with this:

> It has been a while since we worked on this project, and I'd like to
> see what we can do to pick up where we left off as we look to get
> this app ready to submit to the app store (after testing on my own
> Apple TVs first). Please read through all documentation and recommend
> the best course of action

The agent could pick up where we left off only because the repository
remembered: the decisions, the scratchpad, the playbook. An agent has
no other memory.

**Lesson:** write things down, so you can leave and come back (stage
08).

## June: from one platform to five

On June 1 the app reached a real Apple TV for the first time, and
crashed within the hour. On June 9 the Apple TV app went to App Store
review after seven weeks alone. That same day I asked for an iPhone and
iPad app, a web app and an Android app, each built natively, with a
plan and a parity table first. All three started that day. They could,
because the catalog was already a published data plane that every app
could read.

On June 10 the web app took over archivewatch.org. I asked that every
share, from every app, use those links, so anyone could open a film
whatever device they had. On June 22 the Mac app began.

Shipping was still my hands. On June 28 I hit a wall: "I only have the
Xcode beta on my machine and App Store Connect doesn't take builds from
beta Xcode to get approved." The answer, in time, was a cloud build
that needs neither my copy of Xcode nor my Mac. On June 29 a commit records the "first
command-line Play production release."

**Lessons:** one data plane, many native apps (stage 02); each platform
feels native to its own people (stage 03); shipping from the command
line (stage 05).

## July: the data is the product

July was quieter in commits (322) and heavy in data. The commit on July
19 reads "Milestone: 98.3% playability coverage." The same day I
pushed back on a count that did not match what I knew:

> There should be thousands of documentaries. Why are you saying there
> are only 6?

**Lesson:** you judge the data by using the app and by clicking one real
item, then you ask the agent to look for the same problem everywhere
(stage 02).

## August: the agent stops grading itself

On August 3 the TV wave began: Android TV and Google TV, Fire TV, and
packages for LG and Samsung TVs, all from research written first. A
Google Cast receiver followed the next day.

And on August 14, a build reached my Apple TV with stuttering audio and
late captions after the agent had called it tested. I wrote:

> This version is a huge step backward and you keep claiming things are
> fixed and you have fully tested them, but I see no evidence of either.

From then on the agent tested on real devices with its own instruments,
reading screenshots of the actual screen. I bought a Fire TV and a
Google TV streamer, added an iPhone 12 for testing older hardware, and
read the agent pairing codes. The bench grew, one device at a time, to fourteen.

The same month I asked for my inbox back. Scheduled workflows were
emailing failures that were not failures:

> I want to stop getting alerts for failed GitHub actions. Can you fix
> it so that if it isn't broken, it doesn't fail?

**Lessons:** the agent is never the tester (stage 04); a red result must
mean something is broken (stage 06).

## September: nine platforms, and the values written down

September has more commits (2,219) than the four months before it put
together. Roku started on September 3 and was live in the Roku Channel
Store by September 10. Fire TV's Amazon listing was live by September
7. I dug out a Roku from 2011 and asked for a legacy version rather than
holding modern Rokus back.

Using the app every evening, I kept finding things the instruments
missed. On September 6, I asked why a 1990s cartoon was in a
public-domain app, and the commit that day reads "Rights: 1,952
copyrighted TV episodes removed; 203 shows off the app." On September 10
I tested the Samsung version on a real TV and wrote that it was designed
"for a web browser that you have full control over," not a television.
On September 11 I brought in comments from a public Reddit post about
the app and asked the agent to work from them.

Then the values. On September 20 the agent designed Watch Together
around a paid voice server, and I refused: "The goal of this app (and
all of my apps) is for them to cost $0 to run." By September 26, three
standing instructions had gone into the app's `CLAUDE.md`: only essential
words on screen, no AI-written lists or copy in the product, and side
doors (feeds for other apps) kept out of the app itself.

In April I had said the app "should absolutely require an Apple TV 4k."
By September a 2015 Apple TV HD sat on the bench as the floor. Living
with an app changes what you want from it.

**Lessons:** values climb from a reason, to a standing instruction, to a
test (stage 00); a low floor and a high ceiling (stages 03 and 07); the
people outside the screen, here the uploaders and the rights holders,
count (stage 00).

## What the history shows

1. **One platform first, for seven weeks.** Breadth came after the data
   was real.
2. **The pipeline is a third of the history.** 1,439 commits are the
   catalog refreshing itself in the cloud. The computer-shaped work ran
   without me.
3. **Feedback came from use.** Nearly every turn in this story starts
   with me using the app on a real device and saying what I saw.
4. **The method was learned, not planned.** Almost every rule in this
   template started as a correction in this history.

## How these numbers were made

The repository is public at github.com/bhwilkoff/Archive-Watch. I
counted every commit reachable from `main`, using each commit's author
date converted to Mountain time, where I live, through the end of
September 30:

```
TZ=America/Denver git log --date=format-local:%Y-%m-%dT%H:%M:%S \
  --format='%H|%ad|%an|%B'
```

A commit counts as Claude co-authored when its message has a line
beginning `Co-Authored-By:` that contains "Claude." A platform's start
date is the first commit that added its folder or manifest
(`git log --diff-filter=A --reverse -- <path>`), checked against the
commit subjects. Two cases needed judgment. The Apple TV date is April
17, when its first Swift code arrived, though the Xcode project itself
was committed April 19. The web date is June 9, when the public viewer
arrived, because the repository held only placeholder web files and an
editing tool before then.

Store dates come from the App Store's public data for the first
release, and otherwise from the commit that recorded a listing going
live, so several read "by" a date. Counting in UTC instead gives 4,302
commits. Earlier counts of 4,285 and 4,298 were made on other days, with
other cutoffs. The template now uses the numbers on this page.

## What it does not show

A commit count measures activity, not quality. The app's first public
reviews, its download numbers, and whether it made anyone's evening
better are not in the git history. The 2,753 Claude commits also hide
how many of my prompts each one took, and how many were reverted. And
this was one person with fourteen devices and six months. You do not
need any of that to start.
You need one device and one idea.

Archive Watch started as one Apple TV app and a page of research. Start
yours the same way.
