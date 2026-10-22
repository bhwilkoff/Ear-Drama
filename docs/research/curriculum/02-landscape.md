# Who else is building software for people

*Written by Claude, awaiting Ben's review. Research for the curriculum,
part 2 of 5. Every source was read or searched on October 7, 2026, and
each entry says where it came from.*

On October 6, 2026, I wrote down what I mean by a human-shaped problem:
the gentle hum of worry about some part of your life, unsolved for
months or years, that you cannot solve with the tools you have now. And
I set it against the computer-shaped problem, which sees the world as
"disparate data points to be aggregated, quantified, and leveraged" (DECISIONS.md on
the `site` branch, "Human-shaped problems"). I want the cohort to teach
people to build for the first kind, and I do not believe we are the
first to want that.

**We are not alone in this, and we should learn from those who came first.**

This page gathers the people, essays, programs, and traditions that are
already doing some part of what Human Shaped does, even when they use
other words for it. For each one it says what they do, who it serves,
what we can borrow, what we should avoid, and exactly where it came
from. Then it pulls out how they teach, and a list of curriculum ideas
worth adapting, each traced back to its source. The last sections say
which of their pictures we are allowed to show and where we will have
to make our own.

The cost of a page like this is that it is a list of other people's
ideas, and a list can start to feel like a syllabus we copied. So the
ideas at the end are only the ones that fit what we already decided,
and each one names the decision or principle it serves.

## How each entry is laid out

**What** they do, **for whom**, what we can **borrow**, what to
**avoid**, and the **source**: author, date, and the exact address.
Quotes are short and exact. Where a fact came from a search summary
rather than the source itself, the entry says so.

## 1. Software made for a few people

These are the closest to what we mean. Each one is about building for a
small, known group of people rather than a market.

**Robin Sloan, "An app can be a home-cooked meal."**
- **What:** Sloan built BoopSnoop, a messaging app for his own family,
  and argues that programming freed from commercial demands is like
  cooking for people you love. He notes the app "already knows exactly
  who's using it," and that there will be "no sudden redesign, no flood
  of ads, no pivot."
- **For whom:** one family of four.
- **Borrow:** the idea that an app can be finished when it serves the
  people it was made for, and does not have to grow. This is the
  clearest outside statement of our first principle.
- **Avoid:** Sloan was already a capable programmer. The essay does not
  speak to people who are learning, so we should not present it as a
  model of how easy it is.
- **Source:** Robin Sloan, February 2020,
  https://www.robinsloan.com/notes/home-cooked-app/

**Clay Shirky, "Situated Software."**
- **What:** Shirky watched his students at NYU's Interactive
  Telecommunications Program build apps only for one another (a
  professor rating site, a group lunch orderer, a presence tracker) and
  named the pattern: software "designed in and for a particular social
  situation or context," which trades scale and longevity for fit and
  speed.
- **For whom:** a class of graduate students, building for the class.
- **Borrow:** the classroom itself as the first community an app is
  built for. A cohort is exactly that kind of small, known group, so
  classmates can be each other's first real users.
- **Avoid:** Shirky's examples lean on the community's tacit knowledge
  to cover missing features. That is fine for a class, and a risk for an
  app whose people include someone vulnerable.
- **Source:** Clay Shirky, March 30, 2004, archived at
  https://gwern.net/doc/technology/2004-03-30-shirky-situatedsoftware.html

**Maggie Appleton, "Home-Cooked Software and Barefoot Developers."**
- **What:** A talk at the Local-first Conference in Berlin arguing that
  language models could bring "a golden age" of software made locally
  by "barefoot developers," people with real technical skill but no
  professional training, who build for their own communities. The name
  comes from China's barefoot doctors. She ends on Ivan Illich's line
  that people need "the freedom to make things among which they can
  live."
- **For whom:** the long tail of needs that industrial software ignores
  because engineering time is expensive.
- **Borrow:** the barefoot developer as a picture of who our students
  become. It is respectful of what they know about their own community,
  and it does not pretend they are training to be professionals.
- **Avoid:** Appleton is honest that models produce disconnected pieces
  that still need someone who can "glue" them, and that this work can
  slide into cloud dependence and extractive business models. We should
  quote the warning along with the hope.
- **Source:** Maggie Appleton, May 20, 2024,
  https://maggieappleton.com/home-cooked-software (video and slides on
  the same page; the page states no license)

**Kevin Roose, "software for one."**
- **What:** A *New York Times* columnist who is not a programmer wrote
  about building small apps for his own life with AI tools, including
  one that suggests lunches from what is in his fridge, and called them
  "software for one."
- **For whom:** one person.
- **Borrow:** the phrase, and the honest report that a non-programmer
  can get something working that matters to them.
- **Avoid:** Roose also wrote that the results were limited and prone
  to errors. The article is behind a paywall; I read it only through
  summaries, so we should not quote it until someone reads the original.
- **Source:** Kevin Roose, "Not a Coder? With A.I., Just Having an Idea
  Can Be Enough," *The New York Times*, February 27, 2025; his post
  linking it: https://x.com/kevinroose/status/1895145106413625691

**Teresa Torres, running her work with Claude Code.**
- **What:** A product coach, not a programmer, who built a system of
  context files and commands in Claude Code to plan her day, write, and
  research. Her description: "Every morning, I type '/today' into Claude
  Code."
- **For whom:** herself and her own business.
- **Borrow:** proof that the agent can hold a person's own context and
  rhythms, which is close to how I keep `CLAUDE.md` and the session log.
- **Avoid:** her setup is about productivity. Human Shaped asks a
  different first question (what problem in your life is worth solving),
  so this is an example of a technique, not of a human-shaped problem.
- **Source:** Lenny Rachitsky's interview, "Automate your life with
  Claude Code," December 21, 2025,
  https://creatoreconomy.so/p/automate-your-life-with-claude-code-teresa-torres
  (read through a summary of the episode page)

## 2. Software people can reshape

These are about the relationship between a person and their software:
who controls it, where it lives, and how much of your attention it asks
for.

**Ink & Switch, "Malleable Software."**
- **What:** An essay by Geoffrey Litt, Josh Horowitz, Peter van
  Hardenberg, and Todd Matthews arguing for software that people can
  reshape, with a "gentle slope" from using a tool to changing it, tools
  rather than locked apps, and communities building together. They say
  plainly that "AI code generation alone does not address all the
  barriers to malleability."
- **For whom:** anyone who has been told to "submit feedback and hope
  for the best."
- **Borrow:** the gentle slope is a shape for our extensions: every
  lesson works for a beginner, and each one has a next step for someone
  who wants to go further.
- **Avoid:** their own prototypes are research systems. We should not
  promise our students malleable environments we do not offer.
- **Source:** Ink & Switch, June 2025,
  https://www.inkandswitch.com/essay/malleable-software/ (no license
  stated on the site)

**Geoffrey Litt, "Malleable software in the age of LLMs."**
- **What:** Litt argues that language models will be "a step change" for
  end-user programming, while chat alone is a poor interface, so the best
  results come from direct manipulation combined with an AI that acts
  like a local developer who helps you grow your skill.
- **Borrow:** the image of the agent as a "local developer" sitting
  beside you, which fits how we already teach: the student decides, the
  agent builds, and the student learns to read what it built.
- **Source:** Geoffrey Litt, March 25, 2023,
  https://www.geoffreylitt.com/2023/03/25/llm-end-user-programming

**Ink & Switch, "Local-first software."**
- **What:** Martin Kleppmann, Adam Wiggins, Peter van Hardenberg, and
  Mark McGranaghan set out seven ideals: no spinners, work not trapped on
  one device, the network optional, collaboration, the long now,
  security and privacy by default, and ultimate ownership and control.
- **Borrow:** a vocabulary students can use when they decide where their
  app's data lives, and a reason to ask "what happens to this when the
  company is gone?"
- **Avoid:** local-first sync is hard engineering. For most cohort apps
  the honest lesson is "keep the data on the person's device unless you
  have a reason not to," not "build a sync engine."
- **Source:** Ink & Switch, 2019,
  https://www.inkandswitch.com/essay/local-first/

**Calm technology.**
- **What:** Mark Weiser and John Seely Brown at Xerox PARC argued that
  good technology moves between the center and the periphery of our
  attention, so it can inform without overburdening. Amber Case carried
  the idea forward into eight principles, the first being that
  "technology should require the smallest possible amount of attention,"
  and in May 2024 started a certification through the Calm Tech
  Institute.
- **Borrow:** the periphery as a design question every student can ask
  of their app: does it need to interrupt anyone at all?
- **Avoid:** the certification is a paid trademark program. We can teach
  the principles without sending students to buy a badge.
- **Source:** Mark Weiser and John Seely Brown, "Designing Calm
  Technology," December 21, 1995 (published in *PowerGrid Journal* v1.01,
  July 1996), https://people.csail.mit.edu/rudolph/Teaching/weiser.pdf ;
  Amber Case, https://calmtech.com/

**The IndieWeb.**
- **What:** A community built on owning your domain, publishing on your
  own site first, and owning your content, with tools and protocols to
  do it.
- **Borrow:** "publish on your own site first" maps directly onto how a
  student shows their app: in their own repository, which they own, not
  inside our hub.
- **Source:** https://indieweb.org/

## 3. Building with agents, and the people who question it

**Andrej Karpathy, "vibe coding."**
- **What:** On February 2, 2025, Karpathy described "a new kind of
  coding I call 'vibe coding', where you fully give in to the vibes" and
  "forget that the code even exists." The term spread fast.
- **Borrow:** the honesty that it is fun, and that the barrier to
  starting is now almost gone.
- **Avoid:** forgetting the code exists is the opposite of what a
  student who wants to own their app needs. We teach people to read what
  the agent made, even when they did not write it.
- **Source:** Karpathy's post on X, quoted in "Vibe coding,"
  https://en.wikipedia.org/wiki/Vibe_coding (I did not reach the
  original post directly)

**Simon Willison, "Not all AI-assisted programming is vibe coding."**
- **What:** Willison separates vibe coding (not reviewing what the model
  writes) from AI-assisted programming, and gives his rule: "I won't
  commit any code to my repository if I couldn't explain exactly what it
  does to somebody else." He also says vibe coding is fine for low-stakes
  personal projects and "shaves that initial barrier down to almost
  flat."
- **Borrow:** his rule, nearly as written, as the bar for the end of the
  cohort: by week five, a student can explain what each part of their
  app does, even if the agent wrote all of it.
- **Source:** Simon Willison, March 19, 2025,
  https://simonwillison.net/2025/Mar/19/vibe-coding/

**METR's study of experienced developers.**
- **What:** In a randomized trial, 16 experienced open-source developers
  working on 246 real tasks in projects they knew well were 19 percent
  slower when allowed AI tools, yet believed afterward that AI had made
  them about 20 percent faster.
- **Borrow:** the gap between how fast it feels and how fast it is. It
  is a strong reason to teach students to keep a session log and check
  their own sense of progress.
- **Avoid:** the study was about experts in code they already knew, and
  METR says so. It does not tell us how beginners fare, so we should not
  use it to discourage anyone.
- **Source:** METR, July 2025,
  https://metr.org/Early_2025_AI_Experienced_OS_Devs_Study-paper.pdf

**Apps built without access rules.**
- **What:** A researcher who scanned 1,645 live apps made with the
  Lovable builder reported 170 of them exposing their database to anyone,
  because tables were created without Supabase's row-level security.
  It was given the identifier CVE-2025-48757.
- **Borrow:** a real, concrete reason for the "prove it" move: an app
  that holds anyone's data needs someone to check who can read it.
- **Avoid:** I found this only through security vendors' write-ups, not
  the original disclosure, so the numbers should be checked before we
  teach with them.
- **Source:** https://vibeappscanner.com/lovable-vulnerability-cve-2025-48757
  (secondary source)

## 4. Courses and cohorts that teach building

**Stanford CS146S, "The Modern Software Developer."**
- **What:** Mihail Eric's course teaches the whole cycle of building
  software with AI tools (Cursor, Claude Code, and others), from how
  coding agents work to testing, security, and running what you built,
  with students designing workflows "in which humans and agents plan,
  build, evaluate, and improve software together."
- **For whom:** Stanford computer science students, not novices.
- **Borrow:** the order of topics, especially that testing and security
  get their own week rather than an afterthought.
- **Avoid:** it assumes programmers. Our cohort cannot start from coding
  agent internals.
- **Source:** Mihail Eric, Fall 2025 and Fall 2026,
  https://themodernsoftware.dev/

**Harvard CS50's duck.**
- **What:** CS50's AI tutor, the "duck," is built to guide students
  toward answers without handing them over. The team filters its
  replies against course policy, and found that early versions still
  produced code in a large share of answers.
- **Borrow:** the stance that an AI in a learning setting asks before it
  tells. It matches what we decided for students' own agents: the review
  skill asks the method's questions and never grades.
- **Avoid:** the duck runs on one company's model behind Harvard's own
  server. We cannot copy its setup, only its stance.
- **Source:** Harvard SEAS, "'Quacking' into computer programming,"
  January 2024,
  https://seas.harvard.edu/news/2024/01/quacking-computer-programming ;
  Liu et al., "Exploring Student Behaviors and Motivations using AI TAs
  with Optional Guardrails," 2025, https://arxiv.org/pdf/2504.11146

**buildspace, "Nights and Weekends."**
- **What:** A free six-week online program for people building in their
  spare time. Season 5 ran week by week from an idea in one line, to a
  toy, to getting others to care, to iterating with others, to growth,
  to a demo, with a weekly update submission.
- **Borrow:** the weekly update as a habit, and the toy in week two: get
  something small working early, before it is good.
- **Avoid:** its finale was a ranked competition with prize money and
  its frame was startups. We decided against ranking anyone, and our
  apps are not businesses.
- **Source:** Cory Trimm, "Reflecting on Buildspace Nights & Weekends,"
  https://corytrimm.com/posts/reflecting-on-buildspace-nights-weekends-season-5/ ;
  buildspace's announcement,
  https://x.com/_buildspace/status/1526672744053542912

**The Recurse Center.**
- **What:** A free, self-directed programming retreat with no
  curriculum, where each person sets their own structure, and a motto of
  "Never Graduate." Its four social rules are no feigning surprise, no
  well-actually's, no back-seat driving, and no subtle-isms, and breaking
  one calls for a short apology, not punishment.
- **Borrow:** the social rules, nearly as they are, for live sessions and
  the cohort's discussions; and "never graduate" as the spirit of our
  mentors who come back.
- **Source:** https://www.recurse.com/ and https://www.recurse.com/faq

**The School for Poetic Computation.**
- **What:** An artist-run school in New York, founded in 2013, with the
  motto "More Poetry, Less Demo." Its showcases share the learning
  process rather than finished work.
- **Borrow:** a showcase that shows how something was made, not only
  what it does, which is close to the "show the thinking" part of our
  week five.
- **Source:** https://sfpc.io/ and
  https://en.wikipedia.org/wiki/School_for_Poetic_Computation

**Hack Club, "You Ship, We Ship."**
- **What:** A nonprofit for teenagers where, if you build and ship a
  project and log your time, Hack Club ships you something real, such
  as hardware. It is free, runs on your own schedule, and has no race
  for a single prize.
- **Borrow:** "ship" as the one rule that matters, and logged time as
  quiet evidence of work.
- **Avoid:** rewards for shipping can turn the project into a means to a
  prize. Our evidence should be the app and the reflection, not a
  reward.
- **Source:** https://ysws.hackclub.com/

**Paid "build with AI" programs.**
- **What:** University and private programs teach non-programmers to
  build with AI tools: the University of Texas McCombs School's 13-week
  program in AI agents for business, Turing College's "Building with AI
  Agents," and Coursera's "Vibe Coding Essentials."
- **Borrow:** almost nothing in content, but they show the demand is
  real.
- **Avoid:** they are framed around business productivity and charge
  tuition. Human Shaped is free and starts from a person's life, not a
  workflow.
- **Source:**
  https://onlineexeced.mccombs.utexas.edu/post-graduate-program-in-ai-agents-and-generative-ai-for-business-applications ,
  https://www.turingcollege.com/building-with-ai ,
  https://www.coursera.org/specializations/vibe-coding

## 5. Learning by making

**Constructionism.**
- **What:** Seymour Papert and Idit Harel described learning that
  happens best when a learner is building "a public entity, whether it's
  a sand castle on the beach or a theory of the universe."
- **Borrow:** the word *public*. A cohort app is learned through because
  someone else will use it and see it.
- **Source:** Seymour Papert and Idit Harel, "Situating Constructionism,"
  in *Constructionism*, Ablex, 1991,
  https://archive.org/details/papert-harel-situating-constructionism

**Mitchel Resnick's creative learning spiral, and the four P's.**
- **What:** Resnick describes learning as a spiral in which people
  imagine, create, play, share, reflect, and imagine again, and he
  later named its conditions projects, passion, peers, and play.
- **Borrow:** the spiral as the shape of a week. A cohort week can run
  exactly this way: imagine (the question), create (with the agent), play
  (try it on a device), share (bring it back), reflect (what changed).
- **Source:** Mitchel Resnick, "All I Really Need to Know (About Creative
  Thinking) I Learned (By Studying How Children Learn) in Kindergarten,"
  2007, https://web.media.mit.edu/~mres/papers/kindergarten-learning-approach.pdf ;
  *Lifelong Kindergarten*, MIT Press, 2017

**Critically conscious computing.**
- **What:** Amy J. Ko and Mara Kirdani-Ryan's open book gathers teaching
  methods, many of them dialogue, that help students question how
  computing shapes society.
- **Borrow:** discussion prompts that ask who is helped and who is
  harmed by an app, which fits our principles about the people around
  the user, not only the user.
- **Source:** https://criticallyconsciouscomputing.org/ and Amy J. Ko's
  announcement,
  https://medium.com/bits-and-behavior/critically-conscious-computing-a-new-book-for-the-critical-secondary-cs-educator-c7ec9fa4a45e

## 6. Public interest, justice, and care

**Civic tech brigades.**
- **What:** Code for America's brigades were local volunteer groups,
  techies and non-techies, who met regularly to build tools for their
  communities; Code for America ended its affiliation with them, and an
  Alliance for Civic Technologists formed to gather the former chapters.
- **Borrow:** the regular local meetup, with people who are not
  programmers in the room, as a model for the meetups our toolkit
  already describes.
- **Avoid:** the brigades' dependence on one national organization, and
  what happened when it pulled back. Our community should not need us to
  survive.
- **Source:** Code for America, "You Don't Have to Be a Techie to Do
  Civic Tech,"
  https://codeforamerica.org/news/you-dont-have-to-be-a-techie-to-do-civic-tech/ ;
  StateScoop, "Cut loose, Code for America's former local brigades look
  to regroup,"
  https://statescoop.com/code-for-america-former-brigades-regroup/

**Design justice.**
- **What:** The Design Justice Network's ten principles, written by many
  people from 2015 to 2018, center the people most affected by a design
  and put impact ahead of the designer's intentions. Sasha
  Costanza-Chock's book develops the framework.
- **Borrow:** "impact over intention" as a question in our review skill.
- **Source:** https://designjustice.org/ ; Sasha Costanza-Chock, *Design
  Justice*, MIT Press, 2020, open access through OAPEN,
  https://library.oapen.org/bitstream/handle/20.500.12657/43542/1/external_content.pdf

**Inclusive design.**
- **What:** Microsoft's toolkit, led by Kat Holmes, rests on three
  principles: recognize exclusion, learn from diversity, and "solve for
  one, extend to many," with a persona spectrum of permanent, temporary,
  and situational disabilities.
- **Borrow:** "solve for one, extend to many" is close to how a
  human-shaped app starts with one person and may later help others.
- **Source:** https://inclusive.microsoft.design/

## 7. Open models, built in the open

These matter for the cohort pathway that avoids the large AI companies
(part 4 of this research covers the tools in depth).

**Ai2's OLMo.** The Allen Institute for AI publishes its OLMo models with
their training data, training code, and checkpoints, not only the
weights. Source: https://allenai.org/olmo2 ; Simon Willison, "Olmo 3 is
a fully open LLM," November 22, 2025,
https://simonwillison.net/2025/Nov/22/olmo-3/

**Apertus.** EPFL, ETH Zurich, and the Swiss National Supercomputing
Centre released Apertus on September 2, 2025, in 8B and 70B sizes under
the Apache 2.0 license, with its data and architecture open and 40
percent of its training text in languages other than English. Source:
https://ethz.ch/en/news-and-events/eth-news/news/2025/09/press-release-apertus-a-fully-open-transparent-multilingual-language-model.html

**Public AI.** A nonprofit inference utility, fiscally sponsored by
Metagov and funded by Mozilla and others, that serves public models like
Apertus and SEA-LION as public infrastructure, "a BBC for AI." Source:
https://publicai.co/

**Te Hiku Media.** A Māori media organization that built speech
recognition for te reo Māori from recordings its own community gave,
under a Kaitiakitanga license that treats data as something cared for,
not owned, with its benefits flowing back to the people it came from.
Source: IEEE Spectrum, "Māori Data Sovereignty Inspires New AI Voice
Models," https://spectrum.ieee.org/indigenous-ai-voice-models-maori

**Borrow from all four:** for a student who will not use the large
companies, these are real, named alternatives with stated values, which
is better than telling them "use an open model." **Avoid:** promising
that an open model on a laptop will build an app as well as a frontier
agent. Part 4 has to test that honestly.

## 8. People who already drew the line between human and computer problems

My distinction between human-shaped and computer-shaped problems has a
long family. None of these people uses my words, and each sharpens them.

- **Joseph Weizenbaum** argued that deciding is a computational
  activity, while choosing, which needs judgment, compassion, and
  wisdom, should stay human. Source: *Computer Power and Human Reason:
  From Judgment to Calculation*, W. H. Freeman, 1976,
  https://en.wikipedia.org/wiki/Computer_Power_and_Human_Reason
- **Ursula Franklin** separated what she called holistic technologies, where a maker
  controls the work from start to finish, from prescriptive ones that
  split work into supervised steps and breed "a culture of compliance."
  A home-cooked app is a holistic technology in her sense. Source: *The Real World of
  Technology*, Massey Lectures, 1989,
  https://en.wikipedia.org/wiki/Ursula_Franklin
- **Ivan Illich** described convivial tools, which extend a person's
  autonomy and creativity, against industrial tools that grow until they
  take autonomy away. Source: *Tools for Conviviality*, 1973,
  https://en.wikipedia.org/wiki/Tools_for_Conviviality
- **Evgeny Morozov** named solutionism: recasting complex human
  situations as neatly defined problems with computable solutions. It is
  the sharpest description I have found of a computer-shaped problem
  dressed up as a human one. Source: *To Save Everything, Click Here*,
  PublicAffairs, 2013,
  https://www.publicbooks.org/the-folly-of-technological-solutionism-an-interview-with-evgeny-morozov/
- **Neil Postman** asked "What is the problem to which this technology is
  the solution?" and then "Whose problem is it?" Those two questions
  could open week one almost as they are. Source: *Building a Bridge to
  the 18th Century*, 1999, read through secondary summaries,
  https://talk.restarters.net/t/neil-postmans-six-questions-about-technology-plus-two-more/849
- **Ethan Mollick** gives the most widely read case for working beside
  AI, including "be the human in the loop." He is useful as the fair
  voice on the other side, since his rules are about using AI for
  everything. Source: *Co-Intelligence: Living and Working with AI*,
  Portfolio, 2024,
  https://www.goodreads.com/book/show/198678736-co-intelligence

## How they teach

Across these programs, a few structures come up again and again.

- **A short, fixed run, with a weekly rhythm.** buildspace ran six weeks
  with a lecture, a workshop, and one update each week. Our five weeks
  with one session each already fit this.
- **Something small working early.** buildspace's "toy" in week two,
  and Resnick's create and play steps, both get a person to a working
  thing before it is good.
- **A public thing at the center.** Papert's "public entity," Shirky's
  classmates as users, and Hack Club's "ship" all make the work visible
  to someone else.
- **Showcases of process, not polish.** SFPC shares how work was made;
  buildspace ended on a ranked demo. We want the first and not the
  second.
- **Social rules said out loud.** The Recurse Center's four rules are
  short, specific, and forgiving.
- **Self-direction with structure available.** The Recurse Center has no
  curriculum and asks each person to set their own; most others give a
  weekly shape. A cohort can offer the shape and let each person's
  problem choose the content.
- **An AI that asks first.** CS50's duck refuses to hand over answers by
  design.
- **Evidence from the work itself.** Hack Club's logged time and
  buildspace's weekly updates are records of work made while working,
  not tests taken afterward.

## Curriculum ideas worth adapting

Each idea names where it came from and what it would do for us.

1. **Week one opens with Postman's two questions.** "What is the problem
   to which this is the solution? Whose problem is it?" asked of the
   student's own problem, before any building. (Postman, 1999.)
2. **A sorting activity: human-shaped or computer-shaped.** Students sort
   short problem statements, including my own examples from October 6,
   and then Morozov's solutionism is named after they have felt it.
   (Ben's piece; Morozov, 2013.)
3. **The spiral as the shape of every week.** Imagine, create, play,
   share, and reflect, with each live session landing on share and
   reflect. (Resnick, 2007.)
4. **A toy by the end of week one.** The smallest thing that runs on the
   student's own device, before it is good. (buildspace, Season 5.)
5. **Classmates as first users.** Each student names one classmate who
   will try their app in week three. (Shirky, 2004.)
6. **Willison's rule as the week-five bar.** The student can explain what
   each part of their app does, even though the agent wrote it, and that
   explanation is evidence for the credential. (Willison, 2025.)
7. **A session log that checks the feeling of speed.** Students note
   what they asked for, what they got, and how long it really took,
   because METR found people think AI saves time even when it does not.
   (METR, 2025.)
8. **A "who can read this?" check before anything is shown.** Every app
   that stores data names who can see it, with the Lovable exposure as
   the case study. (CVE-2025-48757, secondary sources.)
9. **A calm design question.** "Does this app need to interrupt anyone?"
   asked in the week the app gets its look. (Weiser and Brown, 1995;
   Case.)
10. **Social rules for live sessions.** The Recurse Center's four,
    adapted and said out loud in the first session. (Recurse Center.)
11. **A showcase of process.** Week five shows how the app was made and
    what changed in the person, not only what it does. (SFPC.)
12. **The barefoot developer as an identity, with its warning.** We call
    graduates builders for their own people, and we teach Appleton's
    caution about cloud dependence alongside it. (Appleton, 2024.)
13. **Impact over intention, in the review.** The review skill asks who
    the app could affect beyond its builder. (Design Justice Network.)
14. **Solve for one, extend to many, as an extension.** For students who
    want to go further, a step that asks how their app might serve a
    second person with a different need. (Microsoft Inclusive Design.)
15. **A named open path.** The open pathway names OLMo, Apertus, Public
    AI, and Te Hiku's license as real alternatives with values the
    student can check. (Ai2; ETH and EPFL; Public AI; Te Hiku Media.)

## Pictures we can show, and pictures we must make

Most of these sources state no license for their images, so we can link
to them and quote briefly, and nothing more.

- **No license stated, so link only:** Robin Sloan's essay, Maggie
  Appleton's talk and slides, Ink & Switch's essays, Simon Willison's
  posts, and the course pages for Stanford CS146S and buildspace.
- **Open, with conditions to check:** Scratch projects have been shared
  under Creative Commons Attribution-ShareAlike 2.0, which allows reuse
  with credit under the same license, though a 2025 forum thread asks
  whether that still holds (https://scratch.mit.edu/discuss/topic/866892/),
  so each project's terms need checking. Wikimedia Commons hosts a
  template for Scratch images under that license
  (https://commons.wikimedia.org/wiki/Template:Cc-by-sa-2.0-Scratch).
  The *Design Justice* book is open access through OAPEN, and its
  specific license should be read before we reproduce any figure.
- **Open models' own pages:** Apertus is released under Apache 2.0,
  which covers the model, not necessarily the press photos.
- **What we have to make ourselves:** every screenshot of an agent
  session (Claude Code, Antigravity, and the open-model tools), every
  picture of a student's app on a device, and every example of a
  human-shaped problem worked through from start to finish. None of the
  sources above shows a non-programmer's session in a form we may
  reuse, and our own apps and sessions are the only examples we can show
  freely.

## What I could not verify

- The text of Kevin Roose's article, which is behind a paywall; I relied
  on summaries and his own post.
- Karpathy's original post, which I read only as quoted on Wikipedia.
- The Lovable exposure's numbers, which came from security vendors'
  pages rather than the original disclosure.
- Postman's exact wording and its first appearance, which came from
  secondary summaries.
- Teresa Torres's setup, which I read through a summary of the episode
  page, not the recording.
- Whether buildspace still runs; I found only accounts of past seasons.

## What to bring back

Read the fifteen ideas and mark the ones that sound like you. The ones
you keep become the first draft of the cohort's weekly shape.
