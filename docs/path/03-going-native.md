# 03. Going native

**Where you are.** One platform is live with real data. There is a
parity matrix listing what every other platform must do, and the rules
about your data live in the pipeline. Now the app gets a second home.

<!-- The question, the first two steps, the step labels, the last step,
the per-agent lines, and everything between the bar and the last line:
written by Claude, awaiting Ben's review (curriculum C8, the lesson page
template in docs/templates/LESSON-template.md). -->
**The question.** What would your app feel like if it had been born on
this second device, and how old a device should it still reach?

On June 9, 2026, Archive Watch's Apple TV app went to App Store review.
It had spent seven weeks as the only version of the app. That same day
I asked for three more (the iPhone and iPad, Android, and the web), each
built natively for its own platform, with a plan and a parity matrix
first. All three started that day.

They could start that fast because of stage 02. The data plane was
already published, so each new app was only views and a reader. What
was left to decide was not how to share the data. It was what the app
should feel like on each new platform, and how old a device it should
reach. Those are the two decisions in this stage.

## What I want

I want each platform to feel like it was the first one. The iPhone app
should feel like an iPhone app, not a shrunken television. The Mac app
should feel like a Mac app, with menus and windows, not a stretched
iPad. As I put it once for Tidbits Trivia:

> Yes. Each platform should feel like a first class native experience.

And I want the hand-me-down phone, the 2015 Apple TV and the Fire TV
stick someone got for free to run the app, and run it well, without
holding back what the newest devices can do. Those last two wants only
look like they conflict, and the second half of this page is about why.

## The order of the platforms

Archive Watch arrived on its platforms in this order, and the order is
the method:

1. **Apple TV, April 17.** The platform where its people were. Seven
   weeks alone, with the data pipeline growing underneath it.
2. **iPhone and iPad, the web, and Android, all on June 9.** Three
   platforms in one day, because the seam between data and views was
   already clean.
3. **Mac, June 22.** Thirteen days later. The Mac is the cheapest
   platform to add, because it shares the entire Apple `Core/` with the
   iPhone and the Apple TV. It still needed its own shell: pointer,
   keyboard, menu bar, and resizable windows. It is never the iPad app
   stretched out (`macos-platform-patterns` carries the traps).
4. **Roku, September 3.** A different language (BrightScript) and almost
   no ready-made controls. Everything it shares with the others is the
   data plane.

The `multiplatform-expansion-method` skill turns that order into steps:
find the seam between data and views, then add platforms in order of how
much they can reuse.

## One Apple target, one Android app

On Apple, one Xcode target builds for iPhone, iPad, Mac and Apple TV.
Shared code lives in `Core/` and compiles for all four. The views live
in `iOS/`, `macOS/` and `tvOS/`, each behind an `#if os(...)` guard.
There is one version number (`AppVersion.xcconfig`) and one CloudKit
database, so a film saved on the iPhone is saved on the Apple TV.

On Android, one app serves phones, tablets, Google TV and Fire TV. The
TV experience is chosen at runtime from the device itself, never forked
into a second app (`androidtv-compose-focus`).

## How old a device

The second decision took me longer to learn. Late in September, an
iPhone 6 Plus prompted a question I put to the agent: "The current
native app requires iOS 26, but we are investigating if we can make it
work on older hardware."

The agent measured instead of guessing. It test-built the app at lower
and lower deployment targets and counted what broke. Nothing native
could reach the iPhone 6 Plus at all. Apple's current tools stop at iOS
15. Below iOS 17, the app's data layer fell apart: 428 errors. At iOS
18, the whole app needed changes in two files. And iOS 26 was exactly
the release that dropped the iPhone XS and XR, so moving the floor to 18
brought those phones back for the cost of two files. The iPhone 6 Plus
got something too: a pointer to the website, which is where a device
that old belongs.

Here is how I said it to the agent during the Android version of the
same work:

> Remember, you are trying to keep the floor low for Android, but we
> aren't trying to hamstring modern devices that are capable of doing
> many more things. If you have to make it so that certain features can
> only be utilized on more modern devices, that is okay.

**The floor is a floor, not a ceiling.**

A floor is where the app starts working. It is never the limit on what
the app can do. Choosing one is a measurement, not an opinion, and this
is what the agent does when you ask:

1. **What hardware each candidate floor reaches.** iOS 18 and 17 run
   on the same phones, so 17 buys nothing that 18 does not. iOS 26 lost
   the XS and XR, so 18 buys them back. tvOS 27 dropped the Apple TV HD
   and the first 4K, so the Apple TV floor stays at 26.
2. **The cost of each candidate, measured.** The agent test-builds at
   each one without keeping the change, and counts what breaks. Two
   files is a yes. 428 errors is a no.
3. **A test that holds the floor.** `tools/test_ios_floor.py` and
   `tools/test_tvos_floor.py` run before every Apple archive and refuse a
   target above the floor you chose. On Android, `lint NewApi` stays
   clean at the floor for every build flavor.
4. **Newer features gated by capability.** On Apple, `#available`. On
   Android, `Build.VERSION.SDK_INT`. Live captions in Archive Watch are an
   iOS 26 feature, and the iOS 18 phone simply does not show the button.
5. **The web for everything older.** The website is the floor below the
   floor.

Some traps showed up along the way, and the skills carry them. Android 6
and 7 do not trust the certificate authority behind most of the web
(Let's Encrypt), so the app installed and then could not download its own
catalog until those roots were bundled. A library pinned for the floor
but only half-pinned crashed the Google TV at runtime on a build that
compiled cleanly. The fix was to pin everything that library was built
against, with the reason written beside the pin.

## What it costs

Every gated feature is two paths to keep working, and the older path
only gets tested if you own an older device. Archive Watch keeps an
Apple TV HD on the bench for that reason. It does not have an iOS 18
phone yet, which means the iOS 18 path is tested less than it should be.
Stage 04 is about why that matters.

## Working with your agent

Do the human part first. Putting the app on your own phone or tablet
costs nothing (stage 05 says how long each free way lasts), but a store
needs a developer account: Apple's is $99 a year, Google Play's is $25
once. Create the account yourself when you need it, and tell the agent
when it exists. Everything after that is a conversation.

The steps are one round of write, play, publish. The first two come
before the agent is open, the middle ones are play, with the agent and
on your devices, and the last one publishes to a person.

1. **Write your first answer.** Before any prompt, answer this stage's
   question in two or three sentences in your note: how your app should
   feel on its second device, and the oldest device you guess it should
   reach. Being wrong is fine. Trying first, before you are shown, is
   what helps the rest of the stage stick (the research on productive
   failure, gathered in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md)).

2. **Write your questions.** For five minutes, write as many questions
   as you can about your app on its second device, without stopping to
   answer or judge any of them. Then mark the one you most want answered
   by the end of the stage. (These are the Right Question Institute's
   rules for asking your own questions, also in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md).)

3. **Play: give the app a name of its own.** Every app made from the template
   starts out as `com.example.appname`, and a phone keeps only one app
   with a given identifier, so if you and a classmate both install apps
   still carrying that name, the second one replaces the first. No
   store will take it either. Before the first native build, ask the
   agent to give your app its own reverse-domain identifier (something
   like `org.yourname.birdlog`, which is yours for as long as the app
   lives, so choose it with care) and the name people will see under the
   icon:

   > Give the app its own identity with tools/set_app_identity.py. Its
   > name is Bird Log, and its identifier should be under org.yourname.
   > Then show me where the name appears on each platform.

   The agent changes every platform at once, and from then on a check in
   the Android build fails if the placeholder ever comes back. Look for
   the new name under the icon on your device, because that is where a
   missed platform shows.

4. **Play: ask for the native version of everything.** Name the platforms and
   ask for every feature, built the way each platform's people expect,
   with a plan and a parity matrix first. This is the June 9 prompt
   from the top of this page:

   > Alright, now that we have submitted the first version of the Apple
   > TV app to the app store, it is now time to start building out a
   > pathway to creating versions of Archive Watch for the other three
   > platforms that would be hugely beneficial for making it as widely
   > accessible as possible: iOS, Android, and a fully working version on
   > the web. [...] I would like you to write up a fully formed
   > implementation plan for what is possible on each platform (complete
   > with a full parity matrix that keeps track of each feature) as well
   > as the approaches you will take to use ONLY NATIVE DESIGN for each
   > of the platforms. You should not build a plan to make the Apple TV
   > version into the definitive version, but rather to build the
   > features for the specific platform

   The agent sets up each project, builds the app, and puts it on your
   device. In my first months I made the Xcode projects myself and
   pasted every compiler error back into the chat, one at a time. You
   do not have to. By June 23, starting the Mac app, I pushed back when
   the agent handed me a setup list:

   > a lot of the instructions in the readme ... seem like things that
   > you can do programatically rather than having me do them in Xcode

5. **Play: hold the native bar on the device.** Use the new app and say where
   it feels borrowed from the first platform. Two of mine, from
   Archive Watch on the iPad and Tidbits Trivia on the Mac:

   > The iPad should not just be a blown up version of the phone, but
   > rather a distinct and first class experience.

   > within the MacOS native app, nearly everything in the app should be
   > accessible via menus and hardly anything is. That is the design for
   > desktop-class apps and it should be so for ours as well.

6. **Play: when it says the platform cannot, show it an app that does.**
   Agents give up on platform features too early. In March, the agent
   told me an iPhone share sheet could not open Bsky Dreams with a
   shared image, and I answered with the apps on my own phone:

   > NO! This is absolutely 100% not the case. When I share an image
   > from the photos app to Bluesky, it launches the Bluesky app with the
   > image contained within the Bluesky compose window. [...] I can do
   > this for Facebook, Discord, Gmail, Notion and many others. Please
   > stop telling me it isn't possible and implement it the same way that
   > these other apps have.

   An hour later: "It worked!!! Thank you."

7. **Play: ask what the oldest device could be, and what it would cost.** The
   agent measures it with throwaway test builds and tells you which
   devices each choice reaches. The choice is yours. If you have an old
   device in a drawer, bring it in. In September I dug out a Roku 2 XD
   from 2011, got it into developer mode, and asked:

   > I was able to get developer mode to work on the box. It is
   > restarting. I think there are ways of making it thinner for older
   > hardware, right? If the videos can run on a web browser, surely
   > they can run on old hardware.

8. **Play: keep the modern devices modern.** When the floor starts holding
   back newer devices, say so, and ask for newer features behind a
   capability check instead of dropping them for everyone. I said this the
   day before, when supporting old Rokus started to look like it would
   hold back the new ones:

   > There is no reason to do a bunch of work pushing the platform on for
   > modern Roku users if it is going to be hamstrung by the older
   > devices that are mostly stuck in 2014.

9. **Play: check the matrix against your hands.** Ask the agent to update the
   parity matrix for the new platform. Then open one feature on both
   platforms and see whether they really do the same thing.

10. **Write, then play: make it look like itself.** Until now, your app has been wearing
   the template's look, which is a placeholder, and every app made from
   the template starts out wearing the same one. Tell the agent who the
   app is for and how it should feel to them, and name three to five
   things you love the look of. Then ask it, using the
   `make-it-look-like-itself` skill, to research real apps in your
   subject and come back with three different directions, each shown on
   your app's real core screen. Choose one (or take parts from two), ask
   for another round on it, and then ask for it on every platform at
   once, so the look holds the same way the features do. The agent makes
   that change in one place, `design-tokens.json`, which every
   platform's colors, type, and spacing are written from, and a test
   fails if any platform drifts from it. The cost is that a color someone
   changes by hand in one platform's file gets undone the next time the
   tokens are written, so ask for every change to the look through that
   one file. If you are in a cohort, bring the three directions to your
   classmates before you choose.

11. **Publish: put the second platform in someone's hand.** Give the
    second platform to one of the two people you talked to, or to
    your group, and ask them to do the one thing your app is for. Write
    down what they did first, and anywhere it felt borrowed from the
    first platform. Then, with the agent closed, write two sentences in
    your note: the floor you chose, and what it cost.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** ask for the plan and the parity matrix in plan mode
  (`Shift+Tab`) before it creates any project, and read both.
- **Antigravity:** use `/plan`, and comment on the platform order before
  it builds.
- **The open path:** building a native app while a model is loaded can
  run a laptop out of memory, so close the model during builds, and on 8
  or 16 GB make the installable web app your second platform instead of
  Xcode or Android Studio
  ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are ready to move on,** the second platform is on your own
device, it does the same things as the first in its own idiom, it looks
like your app rather than the template, you have chosen its floor
from a measurement, and one other person has used it, with what they did
first written in your note. So far, you have been the one
checking that it all works. Stage 04 hands that job to the agent.

**Go deeper.** Ask the agent to show you the same screen in both
platforms' code side by side, and to point at the shared part and the
native part. Write down one thing you would move from one side to the
other, and why. It is never required, and it is never counted.

**If you get stuck.**

- *The agent tells you the platform cannot do something.* Ask yourself:
  have I seen another app on this device do it? Then show it that app,
  the way step 6 does, and try
  [the agent keeps stopping](../stuck/playing/agent-stops.md).
- *Xcode, Android Studio, or a build keeps failing.* Ask yourself: is
  this my app, or the tools around it? Then try
  [the tools themselves are stuck](../stuck/playing/tools-stuck.md), and
  ask your group before you lose an evening to it.
- *It works on the new device, and still feels wrong.* Ask yourself:
  where exactly does it feel borrowed from the first platform? Then try
  [it works, and it still feels wrong](../stuck/playing/feels-wrong.md).

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to name the oldest device your app will run on and why you
chose it, the newest feature it will not show there, and why its new
look fits the people it is for.
