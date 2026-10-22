# 05. Shipping

<!-- Rebuilt by the method of curriculum research note 06
(docs/research/curriculum/06-instructional-design.md, section 4), which
Ben approved on October 7, 2026: designed backward from the "Be ready to"
line, with Ben's own release notes as criteria and a watched first use
with a real person. Written by Claude, awaiting Ben's review. -->

**Where you are.** Your app runs on your devices, and the agent can prove
its own fixes. Nobody else can install it yet, and it turns out that
those are two different kinds of done.

<!-- The question, the first two steps, the step labels, the last step,
the per-agent lines, and everything between the bar and the last line:
written by Claude, awaiting Ben's review (curriculum C8, the lesson page
template in docs/templates/LESSON-template.md). -->
**The question.** What happens when someone you did not build it with
holds your app, and what will they do first?

On September 13, 2026, the App Store version of Archive Watch was
1.42.53. The repository was at 1.42.94. That is 41 versions, including
the whole shared-playlist feature, all of it verified on real devices
and shipped to nobody. Google Play was further behind still, on 1.42.6.

Nothing had reported the gap. The loop had been writing "verified on
the glass" in its session log for days, and every word of it was true.
Stage 04 had done its job perfectly. The work simply sat.

**A feature nobody can install is unfinished.**

## What I want

I want shipping to be ordinary. Not a weekend, not a ceremony, not a
morning spent clicking through four store consoles. I want the agent to
be able to do the whole release from the command line, and I want to
be able to read, from the store itself, what is actually live.

That turned out to be possible for almost everything, but it took me
three months to get there. In June I was still creating App Store
versions by hand and uploading Android builds myself. By September my
whole release instruction for Tidbits Trivia was three words:

> Ship every platform

The places where a person still has to show up are listed below.

## One version number

Every platform in this template reads its version from one file,
`AppVersion.xcconfig`. The Apple apps use it directly. Android reads it
at build time. Windows has it stamped into its package.

That rule exists because of the same September 13. Android's version
name turned out to be typed by hand, under a comment claiming it
followed the shared file. It was 88 versions behind, so a crash report
from Google Play could not be matched to the code that caused it. Now
the agent bumps the one number on every release, and a test
(`tools/test_version_contract.py`) fails if any platform drifts from it.

## Apple, from a GitHub runner

The Apple apps are built, signed, and uploaded by a GitHub Actions
workflow (`appstore-build.yml`) running on a released version of macOS
with a released Xcode. There is a reason you do not do this from your
own Mac.

If your Mac runs a beta of macOS or Xcode, which is common when you are
building for the newest features, the App Store accepts the upload and
then rejects the build for review. TestFlight takes it happily, so you
find out late. The cloud runner never has that problem, and for a
public repository it costs nothing.

The workflow refuses a build number that was already uploaded, runs the
floor tests from stage 03, archives, and then hands off to
`tools/asc_release.py`, which does the rest:

- It creates or renames the App Store version for each platform (iPhone
  and iPad, Apple TV, Mac). Three platforms are three versions and three
  reviews. An earlier tool here only knew about the iPhone, and that
  mistake cost a release.
- It waits for Apple to finish processing the build.
- It refuses to submit without release notes.
- It submits for review.

When you ask whether a release is live, the agent reads the answer
straight from Apple (`tools/asc_release.py status`) rather than
guessing. The runbooks it follows are
`docs/CLOUD-SUBMISSION.md` (build, sign, upload) and
`docs/APPLE-SUBMISSION-CLI.md` (version, release, review).

## Google Play, and the other stores

Android ships through the Google Play Developer API: `play-release.yml`
in CI, or `tools/submit-play.sh` from your own machine. One trap is
worth knowing before you meet it. Play limits release notes to 500
characters but only checks at the very end, after a version code has
been used, so a long note burns a version number. The tools check first.

The other stores (Amazon for Fire TV, Roku, the Microsoft Store, LG and
Samsung televisions) each have their own path, and the
`store-submission-playbook` skill carries them. Roku and the TV stores
still need a browser for parts of the process. The skill says which
parts, and how to drive them without guessing.

## Sharing it for free

Before a store, there is a person: a classmate, someone in your family,
or the one friend who said they would try it. Getting the app onto their
phone does not have to wait for a store account, and on Android it does
not have to cost anything. What each free way costs is a limit instead:

- **Android, from a link.** Push a tag ending in `-share` (for example
  `v1.2.0-share`) and `android-build.yml` builds an APK and publishes it
  on your repository's Releases page, where anyone can download it and
  install it by allowing their browser to install apps. Every other
  build keeps its APK on the run's page for 30 days, which only people
  signed in to GitHub can download. Without your upload key saved as a
  secret, each share is signed by a key made fresh for that build, so
  the person has to remove the last one before installing the next.
- **Android, after September 30, 2026.** Google has started requiring
  that apps installed outside a store come from a registered developer,
  first in Brazil, Indonesia, Singapore, and Thailand, and everywhere in
  2027. Its free *limited distribution* account is meant for exactly
  this: students, teachers, and hobbyists sharing an app with up to 20
  devices, with only an email address and no fee. Installing over a USB
  cable with `adb`, the way your agent already does, is not affected.
- **Google Play, before the store.** Internal testing reaches up to 100
  people you name by email, and it can start right away, but it needs
  the $25 Play account. A personal account opened after November 13,
  2023 also needs twelve testers in a closed test for fourteen days in a
  row before the app can go to everyone.
- **Apple, on your own devices.** Signed in to Xcode with an ordinary
  Apple Account, you can install your app on up to three of your own
  devices, and it stops opening after seven days until it is built
  again. There is no free way to put an iPhone app on someone else's
  phone: TestFlight and the App Store both need the $99 Apple Developer
  Program.
- **The web, always.** The website version is a link, and it works on
  every phone today. If your app has a web version, it is the free way
  to reach an iPhone.

The cost of the free ways is that they are not the store. Nobody finds
your app by searching, a direct share asks the person to trust a file
from you, and none of it updates by itself. They are how someone else
uses your app this week, which is the point of this stage, and the store
can come after.

Sources: Google's [developer verification](https://developer.android.com/developer-verification)
and [rollout](https://developer.android.com/blog/posts/android-developer-verification-rolling-out-to-all-developers-on-play-console-and-android-developer-console)
pages, its [account types](https://support.google.com/android-developer-console/answer/16604405),
[Play testing tracks](https://support.google.com/googleplay/android-developer/answer/9845334),
and [new personal account testing](https://support.google.com/googleplay/android-developer/answer/14151465),
and Apple's [membership comparison](https://developer.apple.com/support/compare-memberships/),
all read on October 3, 2026.

## What stays human

Some things only a person can do, and the template does not pretend
otherwise:

- Creating the developer accounts, and paying for them.
- Agreeing to each store's terms, and answering its privacy questions.
- Declaring anything the store asks a person to declare. When Google
  Play wanted a foreground-service declaration for Archive Watch, its
  form rendered as an empty grey box, and the only working way in was a
  link that appeared partway through a manual release.
- Recording a demo video when a reviewer asks for one.

Everything else is the agent's. The rule in `AGENTS.md` is plain: the
full ship is the command line, and nobody is asked to press Submit.

## What it costs

An Apple developer account is $99 a year, and Google Play is $25 once.
The other stores are cheaper or free. The cloud builds are free for a
public repository, and so is sharing an Android app from a link.

It also costs patience. The first submission to every store takes
longer than any after it, because the first one is where you meet every
form.

## Working with your agent

This stage leads with publish. The steps are one round of write, play,
publish: the first two come before the agent is open, the middle ones
are play, with the agent and on devices, and the last one is someone
else holding your app.

1. **Write your first answer.** Before any prompt, answer this stage's
   question in two or three sentences in your note: who will hold it
   first, and what you think they will do. Being wrong is fine. Guessing
   first is what makes their real first move teach you something (the
   research on productive failure, gathered in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md)).

2. **Write your questions.** For five minutes, write as many questions
   as you can about someone else holding your app, without stopping to
   answer or judge any of them. Then mark the one you most want answered
   by the end of the stage. (These are the Right Question Institute's
   rules for asking your own questions, also in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md).)

3. **Play: find the free way that reaches one person.** Ask the agent for
   the free way that reaches the person you have in mind (a `-share`
   release for an Android phone, the web version for an iPhone). If they
   live in a country where Google now asks for a registered developer,
   open the free limited distribution account yourself first.

4. **Publish: open the accounts, when you are ready for a store.** Create
   the accounts yourself (Apple, and Google Play if you have an Android
   app), pay for them, and agree to their terms. Tell the agent when they
   exist. A store can wait until after this cohort; a person cannot.

5. **Play: ask for everything a submission needs.** In June, getting
   ready for Archive Watch's first iPhone release, this is how I started:

   > Let's get all of the info (screenshots, description, etc.) that we
   > need to submit the iPhone version to the app store.

   The agent drafts the listing, captures the screenshots from your app,
   answers what it can of the privacy questions, and tells you what only
   you can answer.

6. **Write: make the words yours.** Read the store description and the
   release notes out loud. Rewrite anything that sounds like a machine
   wrote it, and anything that is not true for that store. Your "no AI
   copy" rule from stage 00 applies to the store page too. In September
   the agent's release notes kept arriving with formatting that gave them
   away:

   > I really don't want to have to remove strange formatting every time
   > I want to submit to the app store that shows that it was AI
   > generated.

   And a few weeks later, when it wrote one set of notes for every
   platform:

   > The what's new text should be different by platform because the
   > features are different.

   Use those two complaints of mine as your test: does any line give
   away that a machine wrote it, and does each platform's text describe
   what that platform actually has? Read your listing against both, and
   change what fails.

7. **Play: do the credential step together.** The build and submission
   run in the cloud and need keys from your accounts. Ask the agent to
   take you to the exact screen for each one. This is how I did it in
   September, when Archive Watch's YouTube posting needed a token only I
   could create:

   > I'd like you to use Chrome to take me to the right screen to
   > generate the oauth token and I'd like you to walk me through that
   > process

   When a secret has to be saved, type it into the prompt yourself with
   a `!` in front of the command the agent gives you, so the value goes
   straight where it belongs.

8. **Publish: say ship.** Then ask whether it is really done. This was me
   on September 3, before moving Archive Watch on to its next piece of
   work:

   > Did you ship it fully? I'd like to move on to another scope of work.

9. **Play: paste the rejection whole.** If a store rejects the build,
   copy the entire message to the agent. It diagnoses, fixes and
   resubmits. If it says something cannot be done by the command line,
   and you know other apps do it, say so.

10. **Play: install it like a stranger.** Open your app's page, in the
    store or from your shared link, on a device you did not build it on,
    and install it. That, not the green checkmark, is shipped.

11. **Publish: watch one person you talked to in stage 00 hold it.** Send
    the link to one of the two people you talked to in stage 00, and
    watch them install it and use it. Ask them to say out loud what they
    are looking at, what they expect, and what surprises them, and do
    not help, even when they get stuck: their getting stuck is the
    finding. (This is the think-aloud method, which Nielsen Norman Group
    calls the most useful single tool in usability work,
    [Jakob Nielsen, "Thinking Aloud: The #1 Usability Tool," January 16, 2012](https://www.nngroup.com/articles/thinking-aloud-the-1-usability-tool/);
    Steve Krug's *Rocket Surgery Made Easy*, New Riders, 2010, makes the
    same case for doing it with one person at a time.) Write down what
    they did first, and what they said, in their words, beside the guess
    you wrote in step 1.

12. **Publish: show your group, then change one thing.** Show your group
    what the person did first and your guess beside it. Ask for feedback
    by Ron Berger's rules: be kind, be specific, be helpful
    ([Berger, "Fostering an Ethic of Excellence"](https://jaymctighe.com/wp-content/uploads/2011/04/Ron-Berger-Article.pdf)).
    Decide one change from what you saw and heard, ask the agent to make
    it, and ship it again. Then, with the agent closed, write two
    sentences in your note: one thing you decided in this stage, and what
    it cost.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** with Claude in Chrome, it can open the exact screen
  for a store key in your own browser, where you are already signed in,
  as in step 7.
- **Antigravity:** its browser is a separate, sandboxed one, so for step
  7 ask for the exact address and the steps instead, and open them in
  your own browser.
- **The open path:** the release workflows run on GitHub, not on the
  model, so they work the same; a small model cannot drive a browser, so
  ask it to write the steps for each screen
  ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are ready to move on,** someone else has your app on their
own device, from a link you shared or from a store, what they did first
is written in your note beside your guess, and one change you made
because of it has shipped. Once they have it, you
can no longer see everything that happens to it by using it yourself.
Stage 06 is about seeing the rest.

**Go deeper.** Ask the agent to read, from the store itself, which
version is live on each platform, and to compare it with the version in
your repository. My September 13 gap of 41 versions is what that check
is for. It is never required, and it is never counted.

**If you get stuck.**

- *It will not install on their device.* Ask yourself: which device is
  it, and which free way did I use? Try
  [I cannot get it onto someone else's device](../stuck/publishing/someone-elses-device.md),
  then ask your group.
- *You are not ready to show anyone.* Ask yourself: what would one person
  learn from it as it is? Try
  [I am not ready to show anyone](../stuck/publishing/not-ready.md).
- *A store form or a console will not cooperate.* Ask yourself: is this a
  step only a person can do? Try
  [the tools themselves are stuck](../stuck/playing/tools-stuck.md), then
  ask the teacher.

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to show your app installed on a device you did not build it
on, to say what that person did first, and, if it is in a store, to
explain one thing you rewrote in its listing, and why.
