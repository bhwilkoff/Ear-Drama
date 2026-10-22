# 02. The shape of an app

**Where you are.** One platform is live, full of real data, and you have
sent it a few rounds of feedback from your own phone. Before a second
platform exists, it is time to decide what "the same app" means.

<!-- The question, the first two steps, the step labels, the last step,
the per-agent lines, and everything between the bar and the last line:
written by Claude, awaiting Ben's review (curriculum C8, the lesson page
template in docs/templates/LESSON-template.md). -->
**The question.** What has to be the same for every person who uses your
app, on any device, and what should feel different?

Here is why that decision matters, from much later in Archive Watch's
life.

In September 2026, Roku's store analytics showed Archive Watch crashing
16 times in two days, always on the same line:
`DetailScreen.brs:781`, a count over a film's cast list.

The Roku code was correct. The data was not. A cast member with no
profile photo was arriving as a bare string instead of a list, and a
string has no count. That was true of 2,798 cast entries across 1,716
films, 5.4% of the catalog. Open any one of them on a Roku and the
channel fell over.

But, the web app read the very same field and never crashed. Its code
happened to check `Array.isArray(c)`, without a comment explaining why,
and it quietly handled both shapes. The web looked fine, which
meant the data looked fine, and the only place the truth showed up
was a crash log from the one platform that trusted the documentation.

Here is how the decision record put it afterward:

> A second reader coping is not evidence of a correct contract; it is
> what hides an incorrect one.

That story is the shape of every app in this template. There is one
source of data and many readers of it, and the readers will disagree
quietly unless something makes them disagree out loud. Your app has one
reader today. This stage is about getting ready for the second.

## What I want

I want the person watching on a Roku in their living room and the
person watching on a phone on the bus to get the same film, the same
rights decision, the same search results, and the same saved list. I do
not want them to get the same screen. The Roku should feel like a Roku.
The phone should feel like a phone.

The film, the rights decision and the saved list are the same
everywhere. The way you reach them is not. That is the whole parity rule
in four words:

**Same verb, native idiom.**

The verbs (browse, search, save,
play, share) are identical everywhere. The idioms, meaning the controls
and gestures and layouts that carry each verb, are whatever each
platform's own people already know. Search on iOS is `.searchable`. On
Android it is a Material `SearchBar`. On the web it is
`<input type="search">` with the query in the URL. On a TV it is a
focusable field you reach with a remote.

The Archive Watch plan said it plainly before any port began: the tvOS
app "is *not* the definitive version to be shrunk onto other screens."

## Two layers

The rule has a structure underneath it. Every app built from this
template has two layers: one that holds what is the same everywhere, and
one that holds what is native to each platform. You build them
differently.

**The data plane is built once.** Whatever your app is about (films,
trading cards, trivia questions, posts), there is one pipeline that
decides what exists, what is allowed, and what it is called. It
publishes its result: a database file on a GitHub Release, JSON on
GitHub Pages, or a small hosted backend when people need to see one
another's data. Every app is a consumer of that result, and only a
consumer.

Archive Watch's contract states its one rule like this:

> No client re-implements or re-hosts any part of the pipeline.

So no app re-derives which films are for adults, or re-checks rights,
or re-matches a film to its poster. Those answers are baked into the
published database, and each app filters with a `WHERE` clause. When
the pipeline fixes a rights mistake, all nine surfaces inherit the fix
without a single app update.

**The apps are built natively, once per ecosystem.** There are three
main codebases, not nine:

- **Apple** (iPhone, iPad, Mac, Apple TV) is one Xcode target in Swift.
  A shared `Core/` folder holds the models, the networking, the query
  logic and the sync. In a media app, 60 to 70 percent of the Swift is
  in `Core/` and compiles for every Apple device. Only the views differ.
- **Android** (phones, tablets, Google TV, Fire TV) is Kotlin and
  Jetpack Compose. One app, with the TV experience chosen at runtime.
- **The web** is plain HTML, CSS and JavaScript with no build step. It
  is also the reach play: no install, every browser, and the canonical
  link that every native app's Share button points to. The smart-TV
  web platforms (LG, Samsung) reuse it.

A Roku channel, if you reach one, is a fourth: Roku has its own
language (BrightScript) and nothing to share with the others except the
data plane. That is exactly why the data plane matters.

## Why native, and what it costs

A cross-platform framework (Flutter, React Native, Compose
Multiplatform) would give you one codebase instead of three. That is a
real advantage, and a lot of good apps are built that way.

I chose native anyway, for two reasons. The first is that each
platform's newest ideas arrive in its own toolkit first: Liquid Glass
on iOS, the focus engine on tvOS, Material 3 Expressive on Android.
A framework reaches them late, or approximately. The second reason is
newer, and it is a guess I am willing to defend. With an agent writing
most of the code, I think the cost of a second and third codebase
dropped a great deal. The cost of an app that feels slightly foreign on
every device it runs on did not drop at all.

The price is discipline. Three codebases drift unless something holds
them together. This template holds them together with four things, and
you will not build any of them by hand. You will ask for them, and then
hold the agent to them.

1. **`PARITY.md`.** Every feature a person can use is a row. Every
   platform is a column. Every cell is honest: ✅ shipped, 🚧 in
   progress, ⏳ planned, 🚫 not doing it (with the reason), or n/a when
   the platform cannot have it at all. A feature ships with its row, in
   the same commit, or it did not ship. The agent writes it. Your job is
   to read it as a list of promises, and to not believe a cell until
   you have seen it on the device.
2. **The data contract** (`docs/DATA-CONTRACT.md`, seeded from
   `docs/templates/`). It names every published file, its shape, and the
   query verbs every app must reproduce. It is written the day the
   second app exists. And after the Roku crash, it is *tested*: a script
   asserts the documented shape over the real published file, so the
   producer breaks the build instead of a TV breaking in someone's
   living room.
3. **One client per app for every network call.** `js/api.js` on the
   web, a shared singleton in Swift, one Ktor client in Kotlin. Views
   never fetch on their own. That is where the contract is read, so it
   is the one place to fix when the contract changes.
4. **Deep links as a contract** (`DEEP_LINKS.md`). Every screen worth
   sharing has a web address, and every native app opens that same
   address. Share a film from an Apple TV and a friend on Android lands
   on the same film.

## The skills that carry this

When you (or your agent) reach this part of the work, these skills hold
the detail:

- `cross-platform-parity-discipline`: running `PARITY.md` and auditing it.
- `shared-data-plane-contract`: publishing the data plane, and what a
  browser can and cannot fetch.
- `multiplatform-expansion-method`: finding the seam and ordering the
  platforms.
- `native-platform-first`: exhausting the platform's own controls before
  building a custom one.
- `canonical-entity-identity`: one stable ID per thing, on every platform.

## Working with your agent

The steps are one round of write, play, publish. The first two come
before the agent is open, the middle ones are play, with the agent and
on your devices, and the last one publishes to your group.

1. **Write your first answer.** Before any prompt, answer this stage's
   question in two or three sentences in your note: what must be the
   same everywhere, and what should not be. Being wrong is fine. Trying
   first, before you are shown, is what helps the rest of the stage stick
   (the research on productive failure, gathered in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md)).

2. **Write your questions.** For five minutes, write as many questions
   as you can about what "the same app" means for yours, without
   stopping to answer or judge any of them. Then mark the one you most
   want answered by the end of the stage. (These are the Right Question
   Institute's rules for asking your own questions, also in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md).)

3. **Play: ask for the matrix.** Tell the agent every platform you plan to
   reach, even the ones that are months away, and ask it to write the
   parity matrix for everything your app already does. On June 10, the
   day after Archive Watch's iPhone, web and Android versions started,
   this is what I asked for:

   > continue working on our parity matrix across all platforms to make
   > sure we can launch on all platforms with the same features across
   > the board

   Read what comes back as a list of promises. Strike anything you do
   not actually want. Ask why about any cell you do not understand.

4. **Play: name the platform whose choices win.** When two platforms disagree
   about order, labels, or which shelves appear, one of them should be
   the reference. Say which. In late June the same shelves had
   different names and a different order on every Archive Watch
   platform, and I picked the Apple TV's:

   > the shelves across platforms should have the same titles + order...
   > I prefer the order and titles of the Apple TV app (replicate
   > everywhere).

5. **Play: move the answers into the data.** Ask the agent to make sure that
   every rule about what exists and what is allowed (what counts as
   appropriate, what a person can see, what is featured) is decided once
   in the pipeline and published, so no app decides it for itself. The
   `shared-data-plane-contract` skill carries how. The agent will ask you
   for the rules themselves. Those are yours.

6. **Play: make the web the address.** Ask that every Share button, on every
   platform, share a link to your web app, and that the web app open the
   native app when someone taps it on a phone. Archive Watch's Share
   buttons were sending people to archive.org, where the films come
   from, instead of to the app:

   > I would like the share functions inside each one of the apps [...]
   > to share the archivewatch.org links rather than the archive.org
   > links. I also think that the web app should redirect to the native
   > apps if you click on them on your phone/iPad/android.

7. **Play: distrust the cells.** A matrix says what should be true. Your eyes
   say what is. The first parity bug I ever caught came from reading
   one number on two screens, two days into BOBA Playbook:

   > Why does the iOS app say there are 17,838 items in the database but
   > the web app says it has only 12,036? I would like there to be parity
   > across both versions of the app and to have the most cards available
   > to be searched

   The agent proposed merging cards that shared a number. I decided what
   actually made a card a card:

   > You should always use the image file difference to determine if the
   > card is different and not the card number.

   That sentence became BOBA's rule for what makes a record unique, and
   later the template's `canonical-entity-identity` skill.

   Keep distrusting the cells for as long as the app lives. Ask for
   audits that read the code, and check the cells you care about against
   what people can actually install. On September 30, months into
   Archive Watch:

   > Is the "Join a Room" feature on the library section available in
   > the currently live 1.42.699 version on Google Play?

8. **Publish: show the matrix to someone else.** Bring your trimmed
   matrix, and the one cell your own eyes proved wrong, to your group (or,
   working alone, to one of the two people you talked to). Ask them
   which promise they would check first, and write down what they said.
   Then, with the agent closed, write two sentences in your note: the
   rule about your data that you decided, and what it cost.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** ask for the matrix in plan mode (`Shift+Tab`), so you
  read the promises before anything is built.
- **Antigravity:** use `/plan` and leave a comment on any row you want
  struck before it builds.
- **The open path:** a small local model holds only a few thousand words
  at once (8,192 tokens in this template's `.aider.model.settings.yml`),
  so ask for the matrix one platform's column at a time, and keep the
  rows you trimmed in your note
  ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are ready to move on,** there is a matrix you have read and
trimmed, one rule about your data that you decided and the pipeline now
enforces, every Share button points at your web address, and someone
other than you has read the matrix and asked about it. You know
what "the same app" means. Stage 03 builds it on a second platform.

**Go deeper.** Ask the agent to write a test that checks the shape of one
file your pipeline publishes against `docs/DATA-CONTRACT.md`, the way
Archive Watch's contract is tested after the Roku crash above. Then ask
it to break the data on purpose and show you the test failing. It is
never required, and it is never counted.

**If you get stuck.**

- *The matrix says a feature is done, and your device says it is not.*
  Ask yourself: which cell, on which device, and what did I see? Then
  try [the agent fixes what I cannot see](../stuck/playing/cannot-see-the-fix.md).
  Ask your group if it keeps happening.
- *The two platforms keep drifting apart in the same way.* Ask yourself:
  is this the same complaint I sent last round? Then try
  [the same bug keeps coming back](../stuck/playing/same-bug.md).
- *You do not know which platform should come second.* Ask yourself:
  where are the people who have this problem, and what do they already
  hold in their hands? Then try
  [I do not know what I want it to do next](../stuck/writing/what-next.md),
  and ask the teacher.

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to show your matrix and one cell the audit or your own eyes
proved wrong, and to explain the rule about your data that you decided,
and why you drew it where you did.
