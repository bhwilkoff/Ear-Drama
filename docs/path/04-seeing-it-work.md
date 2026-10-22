# 04. Seeing it work

**Where you are.** Two platforms run on your own devices, and so far you
have been the one checking every fix. That stops here. If you have not yet
done step 10 of stage 03, "Make it look like itself," do it before this
stage, because in a cohort the look is shown at the session that starts
this one.

<!-- The question, the first two steps, the step labels, the last step,
the per-agent lines, and everything between the bar and the last line:
written by Claude, awaiting Ben's review (curriculum C8, the lesson page
template in docs/templates/LESSON-template.md). -->
**The question.** How do you know your last fix is real?

On August 14, 2026, a version of Archive Watch reached my Apple TV with
stuttering audio and captions that ran late. The agent had called it
tested. I wrote back:

> This version is a huge step backward and you keep claiming things are
> fixed and you have fully tested them, but I see no evidence of either.

The same day came the sentence this whole stage is built on:

> You should be able to see stuttering and swallowed audio. You should
> be able to see the captions and measure their timing and their
> accuracy... I should not be the one testing your work.

## Why the agent cannot grade itself

An agent reports what it intended. "I fixed it" is a true statement about
the code, and it says nothing about the app. Everything short of the real
device lies a little, too.

- **The simulator lies about the filesystem.** tvOS lets a simulator
  write to folders a real Apple TV forbids. The app passes in the
  simulator and crashes on its first launch in a living room.
- **The app's own logs lie about the screen.** A log line that says
  "caption shown" tells you the code ran. It does not tell you a person
  could read the caption.

So the agent does the testing, and the evidence comes from outside it:
a picture of the actual screen, a number read from the device, or a
person holding it.

**The agent is never the tester.**

That rule is written into this template's decision log, and everything
below follows from it.

## What I want

I want to be able to read the word "fixed" in a session log and trust
it. That means every "fixed" points at something someone could look at:
a screenshot, a measurement, a test run that could have failed and did
not.

## The ladder

Evidence comes in rungs, from cheapest to most convincing. The agent
should use the cheapest rung that can actually see the bug.

1. **Doors.** Every starter in this template has small, debug-only entry
   points that open any screen directly: start on this tab, open this
   item, stay muted, go home after this many seconds. On the web they are
   ordinary URL parameters (`?view=`, `?item=`, `?mute=1`). Doors are how
   the agent's tests, and your store screenshots, reach a known screen
   without tapping through the app.
2. **Simulators and headless browsers.** Fast and free, and fine for
   layout and logic. A headless browser is also the only way to get a
   true 1920×1080 TV screen on a laptop.
3. **Real devices on a bench.** Screenshots of the actual glass, read
   with on-device text recognition, so the agent grades what a person
   would see.
4. **A person.** Some things only a person can judge: whether a
   transition feels right, whether a caption is readable from the couch.
   Those go on a short list for you, and the agent does not pretend to
   have checked them.

## The bench

A bench is the set of real devices the agent is allowed to drive. The
agent keeps the list in a file (`tools/bench.json`) and adds to it as
you connect each device. Every device on it has a **role**:

- **test**: the agent may use it freely.
- **floor**: the oldest hardware you support (Archive Watch keeps a 2015
  Apple TV HD for this).
- **os-control**: a device held on an older OS, to tell an OS bug from
  an app bug.
- **owner-watches**: a device a person actually uses. The agent refuses
  it unless you say yes for that run.
- **owner-personal-never-touch**: your own phone. The agent refuses it
  every time, even when handed its raw ID.

The last two roles exist because of what happened next.

## Leave the room as you found it

Handing the testing to the agent was the right move, and the first
months of it were rough in a very domestic way. On September 17, in the
middle of a run, I typed:

> Stop using the fireplace tv for testing. I'm actively watching on it
> now.

The agent had been driving the Apple TV in the room where I was
watching a film. Another run left a film playing unmuted on a different
Apple TV for about an hour, and because an Apple TV sends its sound to
every HomePod in the house, movie music came out of speakers all over
our home. Nobody knew why.

The fix was never to stop testing on real hardware. It was to test on
it the way a careful person would. Every run in this template now
follows the same manners:

- **One lease for the whole run.** Two agent sessions driving the same
  TV each find the other's app on screen and report it as a bug in
  their own. `tools/devlease.py` gives one session the device for the
  whole run, and the other waits.
- **Doors are muted and time-limited by default.** An audible run is
  opt-in, and the agent asks first. That is the HomePod lesson.
- **Teardown is checked, not assumed.** The agent stops the app, asks
  the device whether anything is still running, puts the TV back in the
  power state it found, and reads that back too.
- **The Mac is captured one window at a time.** A full-screen capture
  on my Mac once picked up personal documents that happened to be open
  beside the app. The capture tool now takes exactly one window, owned
  by exactly your app, and has no fallback to the whole screen.

## Instruments that tell the truth

A test rig is an instrument, and an instrument that cannot see must say
so. Archive Watch learned each of these the expensive way:

- A sleeping Apple TV returns a perfectly valid, perfectly black
  screenshot. So the agent asks the TV whether it is on before every
  capture, rather than guessing from the pixels.
- A screenshot left over from an earlier run looks exactly like a new
  one. So every capture deletes the old file first and refuses one more
  than a minute old.
- A check that returned "not on the home screen" whenever its text
  recognition failed was wrong for weeks, and nobody noticed, because it
  never said "I could not tell." Now it says so.
- **Pass, fail and skip are three numbers.** A skip is not a pass. A
  run that found zero results did not pass.
- **A test is not a test until you have seen it fail.** Break the code
  on purpose, watch the test catch it, then put the code back.

The full list, 26 of them, is in `docs/AUTONOMOUS-FLEET-TESTING.md`
and `docs/DEVICE-HARNESSES.md`, and the skills that carry them are
`device-observation-harness`, `autonomous-fleet-testing` and
`concurrent-agent-device-leases`.

## The same honesty, inside the app

Everything above is honesty you ask of the agent's instruments. Your app
owes the people who use it the same thing. Any part of it that runs on
its own (a computer opponent, a suggestion, a search that guesses, a
caption written by speech recognition) should say what it can do, say
how sure it is, step back when it is not sure, and never pass itself off
as a person. Tidbits Trivia's labeled computer opponent from stage 00 is
this rule. A reader that says "I could not tell" is the same rule,
turned toward you. The `learning-orientation-design` skill carries the
checklist.

## What it costs

A bench is hardware, and hardware is money and space. Archive Watch's
bench grew to fourteen devices, including two Rokus and a Samsung TV.
You do not need that. You need the device your people use and, if you
can find one, an old one. It also costs time: every run on a real device
is slower than a simulator run. That is why the ladder exists. Most
checks belong on the lower rungs, and only the ones that can fool the
lower rungs need to climb.

## Working with your agent

Start with what you have. My bench grew to fourteen devices, but it grew
one device at a time, months into building. One phone is enough for
this stage.

The steps are one round of write, play, publish. The first two come
before the agent is open, the middle ones are play, with the agent and
on your devices, and the last one publishes to your group.

1. **Write your first answer.** Before any prompt, answer this stage's
   question in two or three sentences in your note, about the last thing
   the agent told you it fixed. Being wrong is fine. Trying first, before
   you are shown, is what helps the rest of the stage stick (the research
   on productive failure, gathered in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md)).

2. **Write your questions.** For five minutes, write as many questions
   as you can about how you would know a fix is real, without stopping
   to answer or judge any of them. Then mark the one you most want
   answered by the end of the stage. (These are the Right Question
   Institute's rules for asking your own questions, also in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md).)

3. **Play: hand over the testing.** Tell the agent, in your own words, what I
   said on August 14: that it should see what you see, and that you
   should not be the one testing its work. Ask it to set itself up to
   test on your device. It will tell you the physical steps only you can
   do: turning on developer mode, trusting the computer, reading it a
   pairing code. Do those, and read it the codes.

4. **Play: say whose devices are whose.** Tell the agent which device is yours
   and must never be touched, which ones people in your home actually
   use and need asking about first, and which it may use freely. It
   writes those down as roles, and its tools refuse the devices you
   protected.

5. **Play: ask for proof with every "fixed."** From now on, when the agent
   says something works, ask to see it: a screenshot from your device, a
   measurement, a test that could have failed. Look at the screenshot
   yourself. If there is no way to prove the fix yet, ask for one. One
   of my earliest requests like that came in Bsky Dreams' first month,
   after three fixes for a doubled-up feed had not worked:

   > You have clearly not found the root cause of the issue, nor are you
   > actually testing to make sure that it is fixed before telling me
   > that it works. Please create a test for how you will determine if a
   > post is rendered a signgle time and continue to work until your
   > code passes that test.

6. **Play: when it guesses, stop it.** If a fix fails twice, ask for research,
   or for a way to see the problem, before the next attempt. On
   September 6, I was watching a film at home while the agent chased an
   audio dropout, and it kept blaming AirPlay. I checked the one thing I
   could check from the couch:

   > I just confirmed. The audio went out on the TV speakers as well. It
   > ISN'T Airplay. Please stop guessing and figure out the issue.

7. **Play: keep living with the app.** The agent's instruments will miss
   things. You will catch them by using the app, and each one you report
   becomes a check the agent adds, so it does not miss that one again.

8. **Play: correct its manners.** If it leaves something playing, drives a
   device someone is using, or wakes a TV in the wrong room, say so, and
   ask for a rule so it never happens again.

9. **Publish: show the proof.** Show your group (or, working alone, one
   of the two people you talked to) the screenshot that proved a fix,
   and say what it would have shown if the fix had not worked. Write down
   the first thing they asked. Then, with the agent closed, write two
   sentences in your note: one check you decided the agent must always
   run, and what it costs you in time.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** ask for the check by name, a test, a build, or a
  screenshot, which is Anthropic's own advice ("Give Claude a check it
  can run"), and use the desktop app's Browser pane to see a web fix.
- **Antigravity:** ask for `/browser`, which takes screenshots and
  records the browser as artifacts you can open and comment on.
- **The open path:** the model reads text only and cannot look at a
  screenshot, so you are its eyes: describe what you see or paste the
  error, which makes "the agent is never the tester" literal
  ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are ready to move on,** the agent has proven a fix to you
with a screenshot from your own device, your devices have roles, you
have stopped being the first person to find its mistakes, and someone
else has seen the proof and asked about it. The app
works, and you can prove it. Stage 05 puts it where other people can
install it.

**Go deeper.** Pick one check the agent added, and ask it to break the
code on purpose and show you the check failing, then put the code back.
That is the rule above, "a test is not a test until you have seen it
fail," done once with your own eyes. It is never required, and it is
never counted.

**If you get stuck.**

- *The agent says it is fixed, and you still see the bug.* Ask yourself:
  what would the proof look like, and has it shown me one? Then try
  [the agent fixes what I cannot see](../stuck/playing/cannot-see-the-fix.md).
- *The same fix fails twice.* Ask yourself: is it guessing? Then ask for
  research or a way to see the problem, the way step 6 does, and try
  [the same bug keeps coming back](../stuck/playing/same-bug.md).
- *The agent cannot reach your device.* Ask yourself: is this the app or
  the tools around it? Then try
  [the tools themselves are stuck](../stuck/playing/tools-stuck.md), and
  ask your group.

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to show the screenshot that proved a fix, to say what it would
have looked like if the fix had not worked, and to explain which of your
devices the agent may never touch, and why.
