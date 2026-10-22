# More than asking an AI for an app

On June 16, 2026, I made a new repository at 6:12 in the evening. By
11:41 that night, Tidbits Trivia played on an iPhone, the web, an Apple
TV and an Android phone, with more than ten thousand real questions. I
sent four prompts. I did not write a line of code.

That sounds like vibe coding. In one important way, it is. So, what
makes this a different thing, and why should anyone build the slower
way this template teaches?

## What vibe coding is, fairly

Andrej Karpathy named it in early 2025, as Willison quotes him: a way of coding where you "fully
give in to the vibes, embrace exponentials, and forget that the code
even exists." Simon Willison, who writes carefully about these tools,
narrowed it to "building software with an LLM without reviewing the
code it writes"
([Not all AI-assisted programming is vibe coding (but vibe coding rocks)](https://simonwillison.net/2025/Mar/19/vibe-coding/),
March 19, 2025).

And he defends it. "For low stakes projects and prototypes why not just
*let it rip*?" He argues that it shaves the steep first barrier to
programming "down to almost flat," and that "everyone deserves the
ability to automate tedious tasks in their lives with computers." I
agree with every word of that. If you want a tool for yourself this
weekend, ask an agent for it and enjoy it.

Willison's line between vibe coding and real development is review: if
you "reviewed it, tested it thoroughly and made sure you could explain
how it works to someone else," it is "software development." Addy Osmani
draws the same line in
[Vibe coding is not the same as AI-Assisted engineering](https://addyo.substack.com/p/vibe-coding-is-not-the-same-as-ai)
(August 30, 2025): in AI-assisted engineering the human stays "firmly in
control, responsible for the architecture, reviewing and understanding
every line of AI-generated code."

Here is the honest part. I do not read the code. Across four apps, I
judged everything by what the app did, never by reading what the agent
wrote. By Willison's definition, that is vibe coding. And the folks
this course is for are adults who have never built an app, so most of
them will not be reading code either.

**The difference is where the judgment lives.**

Code review is one place to put a person's judgment. It is not the only
one, and for an adult who has never built an app, it is not the one
they can do well. This template puts judgment in six other places, each
one something a person who cannot read Swift can still do. Each one
exists because of a specific thing that went wrong.

## Six places the judgment lives

### 1. Values written where the agent reads them

An agent does whatever satisfies the request most cheaply. In September,
the agent designed Archive Watch's Watch Together feature around a paid
voice server. I stopped it on September 20:

> It is absolutely not acceptable. The goal of this app (and all of my
> apps) is for them to cost $0 to run.

Six days later I added a second line: "I don't want AI making lists
and writing copy." Both
are now standing instructions in the app's `CLAUDE.md`, the file Claude
Code reads at the start of every session, with the date and my words.

**What it prevents:** an app that quietly becomes the cheapest thing to
build instead of the thing you meant. The paid server was designed
before my rule stopped it, because the rule was not yet written down.
Written rules get read at the moment of the choice. (Stage 00.)

### 2. The agent is never the tester

An agent reports what it intended. On August 14, a build of Archive
Watch reached my Apple TV with stuttering audio and late captions,
after the agent had called it tested:

> You should be able to see stuttering and swallowed audio. You should
> be able to see the captions and measure their timing and their
> accuracy... I should not be the one testing your work.

From then on, every "fixed" had to point at evidence from outside the
agent: a screenshot of the real screen, a number read from the device,
a test that could have failed. The habit started earlier. In March,
after three failed fixes for a doubled-up feed in Bsky Dreams, I asked
the agent to "create a test for how you will determine if a post is
rendered a signgle time and continue to work until your code passes
that test."

**What it prevents:** believing "it works" because the thing that wrote
it says so. (Stage 04.)

### 3. Living with the app

I use every app I build, every day, on every device I own. On September
11 I told the agent, "I actually watch on every device." On the evening
of September 6, I narrated an audio dropout from the couch for two hours
while the agent measured it ("Audio went out." "Audio just went out
again."), and when its fix turned out to be a workaround, I said so:
"That is not a solution."

**What it prevents:** an app nobody has actually used. The agent's
instruments miss things. A person using the app catches them, and each
catch becomes a check the agent adds. (Stages 01 and 04.)

### 4. Parity: the same verbs on every platform

I want the person on a Roku and the person on an iPhone to be able to do
the same things, each in a way that feels native to their device. The
template keeps that promise in one file, `PARITY.md`, a table of every
feature on every platform.

Parity is also a way of seeing. In September, Roku's analytics showed
Archive Watch crashing 16 times in two days. The cause was a data shape
the web app had quietly tolerated: 2,798 cast entries across
1,716 films. One platform hid the bug, and another one surfaced it.

**What it prevents:** one platform silently falling behind or breaking,
and the people on it finding out first. (Stage 02.)

### 5. A low floor and a high ceiling

I want the app to open on the old device in the drawer, and I want the
newest devices to get everything they can do. Archive Watch keeps a
2015 Apple TV HD on its test bench as the floor. In September I dug out
a Roku from 2011 and asked for the code to be split rather than held
back:

> There is no reason to do a bunch of work pushing the platform on for
> modern Roku users if it is going to be hamstrung by the older devices
> that are mostly stuck in 2014. (September 11)

**What it prevents:** two opposite failures. An agent left alone picks
a floor by default, which can drop people with older hardware without
anyone deciding to. Or it holds every device to the oldest one.
The floor is chosen by measuring which hardware each choice reaches.
(Stages 03 and 07.)

### 6. The memory ratchet

Every session with an agent starts fresh. It remembers only what the
repository remembers. So when a correction could happen again, it gets
written down: as a memory with a "Why" line, a rule, a decision, and
when possible a test. On September 22 I found "programme" on a label
and assumed we already had a spelling rule. We did not. Now there is a
rule and a test (`tools/test_us_english.py`) that checks every string a
person can see.

**What it prevents:** fixing the same thing twice. The ratchet can also
turn the wrong way. A memory the agent wrote itself, that AirPlay did
not work, carried a wrong claim across sessions until I caught it on
August 31: "You keep on saying (for many different sessions) that
AirPlay doesn't work, but it does work." Memories are claims, and they
get checked like any other claim. (Stage 08.)

## Side by side

| | Asking an AI for an app | Building human-shaped software |
|---|---|---|
| Where values live | In your head, if anywhere | In `CLAUDE.md`, dated, in your words, read every session |
| Who says it works | The agent | The real screen, a measurement, or a person |
| How you review | Whatever you have time for | Use it every day, on every device you own |
| Other platforms | Whatever got built | A parity table, kept honest by audits |
| Old devices | Whatever compiles | A floor chosen by measurement, held by a test |
| Mistakes | Fixed when noticed | Fixed, then written down so they stay fixed |
| What you learn | How to ask, and what the tools can do | What your app is, and what it should never do |

## What it costs

This way is slower, and it asks more of you. Archive Watch's test bench
grew to fourteen devices. The six habits above came from many
corrections over six months, not from a plan. And judging by behavior
has limits that reading code does not: you will not see a security flaw
by using your app. The template's rules and skills carry some of that
for you, and a person who can read code is still worth asking.

But, the slower way is the only one I have found that leaves the person
building more capable at the end. Vibe coding gets you an app. This
gets you an app, and it gets you a builder who knows what the app is
for.

## Where to go next

- `computer-shaped-problems.md` explains the shorthand behind all of
  this.
- `case-study-archive-watch.md` follows one app through six months.
- `../path/talking-to-your-agent.md` has the moves, in the words I
  actually typed.

Try the slower way for one feature. Compare.
