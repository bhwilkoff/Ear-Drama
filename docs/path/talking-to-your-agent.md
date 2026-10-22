# Talking to your agent

<!-- The screenshots on this page, and the one-line notes under them, were placed by Claude on October 7, 2026, from docs/images/agents/, and await Ben's review. -->

On June 16, 2026, at 6:12 in the evening, I made a new repository from
an earlier version of this template. At 7:05 I pasted in a description
of the game I had been drafting in my notes. By 11:41 that night,
Tidbits Trivia played on an iPhone, the web, an Apple TV and an Android
phone, with more than ten thousand real questions built from Wikidata.
I sent four prompts that evening. The first was the description. Two of
the other three were some version of this:

> keep pushing forward with the next round of work to fully build out
> this game/app

I did not write code that night, or type in a single question, or open
a file. That is not a trick. It is the job, now: say what you want, say
where the truth lives, look at what comes back, and say what is wrong
with it. Over and over, until it is right.

**The prompt is the work.**

This page is the set of moves I actually use, each with the words I
typed. Every stage points back here.

## Say what you want before what it does

Start with the wish, in plain words, in the first person. Two of mine
from Archive Watch: the first about its scheduled workflows emailing me
failures that were not real, the second while building a live-stream
studio into the Mac app.

> I want to stop getting alerts for failed GitHub actions. Can you fix
> it so that if it isn't broken, it doesn't fail?

> I'd like to be able to move my camera around the preview window AND
> crop the video (to only capture my face, etc.).

A wish gives the agent room to find a better answer than the one you
would have specified. A specification only gets you what you already
thought of.

## Keep a running note for each app

Most of my best prompts were not typed into Claude Code. They were
written in a plain note I kept for each app, while I was using the app,
and pasted in when they were ready. I opened a note on the first day of
every app and kept it for as long as the app lived. The Archive Watch
note runs from the April feature ideas to the September Roku work.

Each note grew downward in the same rough order:

1. **The wish at the top.** One sentence, then a numbered list of what
   the app should do, then what to research, then what the first
   session should produce. (Stage 01 has the whole Tidbits one.)
2. **Rounds.** A heading like "Next:" or "Next feedback:", and under it
   a numbered list, one observation per item, written while I used the
   app: where it is, what is wrong, what it should be, on which
   platforms.
3. **A ledger.** "Done:", "Fix:", "Outstanding:", "Future:". Ideas left
   there are not lost. Three one-line Archive Watch ideas became
   features months later.
4. **Loop prompts, drafted ahead.** Whole `/loop` prompts, written days
   before I sent them.
5. **Answers to the agent's questions,** numbered to match its
   questions.
6. **Other people's words.** A friend's feature request, testers'
   messages with my draft replies underneath, a partner's email.
7. **The steps the agent handed back to me,** kept until I did them.

A round from my Archive Watch note, collected while I used the Android
TV version and sent on September 3:

> We need to work on a few things within the Android TV version of the
> app:
> 1. The home loading is much quicker than it has ever been, but even
> though the home screen loads within a couple of seconds, the posters
> still take about 10 seconds longer to load, so it looks like it is
> stuck/frozen.
> 2. The first item on each shelf is inaccessible. If you try to access
> it, it will take you directly to the sidebar items. This needs to be
> fixed.

When I pasted a round, I typed one line in front of it to set the
scope. From Tidbits Trivia, July 1:

> Please work on the following ten tasks as a set of large updates for
> Tidbits Trivia across all platforms. However, before you start please
> read through your documentation for how we build and where we are in
> the progress of each platform:

And from BOBA Playbook in April, where I had only tested the web app:

> Here are the intitial pieces of feedback for the two new features.
> Although they were written while only looking at the web app version
> of the features, some of them also have implications for how the iOS
> version is built, so please pay attention to both

If you are not sure a round landed (a session compacted, or it went
quiet), paste it again and ask. I did.

One habit of mine not to copy: my notes mixed keys and passwords in
with the feedback. Keep secrets out of your notes and out of the chat.
They belong in a password manager or your platform's secret store, and
the agent can be told where to find them.

The note is where you think. The prompt is where you send it.

## Name where the truth lives

Never type data in. Say where it comes from and let the agent build the
pipeline that brings it. This was the first prompt of Tidbits Trivia, on
June 16:

> A fully realized multi-player trivia game based entirely upon facts
> pulled from the open Wikipedia API ... The final outcome of this
> session should be a working iOS version with all v1 versions of the
> features fully implemented.

That one prompt has all three things a kickoff needs: the wish, the
source, and what "done" means for this sitting.

## Say what you see, where, on which device

Your review is using the app. Report it the way you would to a friend
who built it. Two from Archive Watch: one on the iPhone, two days after I
had asked for playlist sharing, and one while browsing the live
website.

> I'm looking at the latest version of the iphone app and I don't see
> any way to share playlists

> Why does https://archivewatch.org/item/shakedown-1950 have actors
> names in the title?

One concrete item is worth ten general complaints. Then ask the agent
to generalize: "Can you look for this issue anywhere else in the app?"

## Send feedback in rounds

After a stretch of real use, send a numbered list. The agent works
through it and tells you which items are done. This is the start of
twenty items I sent about Archive Watch's Roku app on September 5,
after a few days of using it:

> 1. There are more animated movies/videos in the hero row than I would
> like. At most, there should only be one animated feature. 2. There
> are multiple shelves that only have 4 or 5 items. No shelf should
> display as less than a full row. 3. The same shelves should show up
> across all platforms.

In Archive Watch's first week, the commit history runs "UI feedback
round 1" through "round 7" in a single day. That is what a first week
looks like.

## Correct with a reason, and point at the bar

When the agent is wrong, say so, say why, and point at something that
already works: the platform's own feature, another app, a thing you
already built. In June, the agent proposed its own subtitle overlay on top
of the video instead of using the player's built-in one:

> NO CUSTOM OVERLAYS... You can do this if every other video app on the
> market can do subtitles with the ability to skip. This is native
> functionality. Search better through the APIs.

In August, when automatic captions on the Apple TV still lagged the
speech after several attempts:

> Automatic captions happen perfectly within the Photos app on my phone
> for any video that has even a little bit of audio. I want it to be
> this simple and fluid

The corrections are where the method lives. Most of what is written in
this template's skills started as one of them.

## Refuse a limit that is not real

Agents give up too early, and they say so with confidence. When a claim
does not match what you know, say that. On August 31, the agent
concluded that Amazon's reporting API needed special permission to use:

> That cannot be the way in which you have to get API access enabled.
> Amazon is a huge company and there is no way that they require every
> developer to ask for API access. You need to keep looking for ways to
> do this

The same day, after several sessions had told me AirPlay did not work
in Archive Watch:

> You keep on saying (for many different sessions) that AirPlay doesn't
> work, but it does work. And it is documented.

## Ask for the truth about the state

"Fixed" is a claim. Ask for the evidence. After a morning of workflow
fixes on Archive Watch, August 24:

> Can you confidently say that I will not receive another error from
> GitHub for any of the workflows we have for Archive Watch?

And before moving on to the next piece of work, September 3:

> Did you ship it fully? I'd like to move on to another scope of work.

## Research first, then build

For anything new, or anything that has failed twice, ask for research
before code. When the answer is yes, say build it. Just after midnight
on September 1, on Tidbits Trivia:

> Can you research the feasibility of creating a version of Tidbits
> Trivia as an iMessage game that you could play in a direct iMessage
> conversation or even in a group conversation?

Ten minutes later:

> Please fully build out and enable a tidbits trivia iMessages app and
> prepare the App Store Connect settings to submit for review

Both tools have a way to hold the agent to research before it builds.
In Claude Code, plan mode changes nothing until you say go (`Shift+Tab`
in the terminal, or **Plan** in the desktop app's selector,
[permission modes](https://code.claude.com/docs/en/permission-modes)).
In Antigravity, `/plan` writes the plan as an artifact you can comment
on, line by line, before it starts
([slash commands](https://antigravity.google/docs/slash-commands/)).

![Antigravity's plan open beside the conversation, with a User Review Required section](../images/agents/antigravity-plan-document.png)
Anthropic's own rule for when to skip it is a good one: "If you could
describe the diff in one sentence, skip the plan"
([best practices](https://code.claude.com/docs/en/best-practices)).

And when a correction does not take, twice, stop correcting. Start a
fresh session (`/clear` in Claude Code), or `/fork` in Antigravity, and
send one better request that says what you learned from the two that
failed. Anthropic puts it plainly: "A clean session with a better prompt
almost always outperforms a long session with accumulated corrections"
([best practices](https://code.claude.com/docs/en/best-practices)).
*(These two paragraphs were written by Claude, awaiting Ben's review.)*

## Ask it to argue the other side

When you work alone, nobody disagrees with you. Before a big feature, ask
the agent to make the strongest case against it on behalf of the people
outside the screen (stage 00 says who they are): the folks whose work
the app shows, whose data it uses, or whose lives it changes without
their opening it. Ask it to say what the feature would cost them, and
whether the app should build it at all.

Read the answer the way you would read a friend's objection. Some of it
will be wrong. The rest is the part you would not have thought of
alone. It is not a substitute for asking real people. It is a second
voice where there was only yours.

## Ask for a human-shaped review

Before you show your app to anyone, ask your agent for a human-shaped
review. It walks the fifteen [Human-Shaped Principles](../human-shaped/PRINCIPLES.md)
one at a time, looks through your repository for evidence of each, says
plainly what it could not see (it cannot hold your phone or watch a
person use the app), and ends each principle with a question that only
you can answer. It never gives you a grade, because a grade would turn
the principles into a checklist to game rather than a way to see your
own work more clearly.

The review lands in a file in your repository, and what happens to it is
up to you: keep it to yourself, commit it, or bring it to your cohort
beside the feedback from your teacher and classmates, which it is never
meant to replace. The `human-shaped-review` skill carries the details,
and it works the same way in Claude, Gemini, or any agent that reads the
template's instructions.

![Antigravity's slash menu offering plan, grill-me, and human-shaped-review](../images/agents/antigravity-slash-menu.png)

In Antigravity, typing `/` shows the skills the template carries, the review among them.

## Give standing permission

Once you have decided something, stop being asked about it. In the
middle of fixing Archive Watch's workflows, August 23:

> Fix everything. I don't want you to ask me. Just fix it.

And on September 29, when an audit I had started kept pausing to ask
whether it should fix what it found:

> The goal of the audit is to fix every incorrect thing you are
> finding. Why are you asking me if you should fix things?

![Claude asks "Allow Claude to edit index.html?" and shows the one-line change, with Deny, Always allow, and Allow once](../images/agents/claude-allow-edit.png)

**Allow once** keeps you deciding each time; **Always allow** is the standing permission, for the kinds of change you have already decided about.

## Make it write things down

When a correction could happen again, have the agent keep it. After
Archive Watch's loop kept re-arming without saying when it would next
wake, August 29:

> Can you make a memory so that after every tick when you re-arm the
> loop, you give a time when the next tick should occur?

And at the end of a long day in September, before the session ran out
of room:

> Document everything we have done today, as we are needing to compact.
> (create any new skills necessary)

## Let it drive, and do the one human step

Some steps belong to a person: a login, a pairing code, a payment. Ask
the agent to take you right to them. Setting up Archive Watch's YouTube
posting on September 8:

> I'd like you to use Chrome to take me to the right screen to generate
> the oauth token and I'd like you to walk me through that process

(Antigravity's browser is a separate, sandboxed one, so in Antigravity
ask for the exact address and the steps, and open them in your own
browser, where you are already signed in.)

And adding two more Apple TVs to the test bench on September 11:

> Let's get connected to all of the Apple TV's in my house via the known
> pathway through Xcode. Add the fireplace tv and the movie room tv and
> I'll read you the connection codes.

## Decide when asked, in as few words as it takes

When the agent needs a decision, ask it to lay out the options. On
September 25, six product decisions had piled up waiting on me:

> Can you ask me the owner items as a series of questions where I can
> see the options and choose from among them?

Then answer briefly. "Do 2 and 3." "Great. Go for it."

![Claude says it has not changed anything yet, shows the one-line edit it would make, and asks whether to change only the heading or the other places too](../images/agents/claude-shows-change-first.png)

## Put big work on a loop, and hold it to real work

A scope too big for one sitting goes on `/loop`, with the goal and the
point where it should stop. The day I added an old iPhone 12 to
Archive Watch's bench, August 28:

> /loop let's start with some robust testing on the iPhone 12 to ensure
> that everything is working as it should. [...] Please make a
> systematic list and then run through it to check everything. Don't
> stop until you have completed the full list.

Then watch whether each tick does something new, and stop it when it
does not. A Tidbits loop on August 26 kept repeating the same checks:

> Stop the loop until you can tell me what you are actually doing with
> it.

In Antigravity, the same prompt starts with `/goal`, which keeps working
until the goal is met, and `/schedule` runs one on a timer.

## What stays yours

Across four apps, these were the only things I kept doing myself:

- The wish and the values, and the lines the app will not cross.
- Choosing the source, and judging what is true.
- Devices, accounts, money, logins, pairing codes.
- Using the app, every day, on every device I own.
- Taste: what looks right, what reads right.
- Refusing claims that do not match what I know.
- Bringing in other people: testers, a Reddit thread, a trivia night.
- Deciding when to stop, and when to ship.

Everything else, I asked for.
