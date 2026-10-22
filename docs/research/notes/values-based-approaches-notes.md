# Values-based approaches to designing software: a research brief for Ben's template and course

Researched 2026-10-01. Every claim has a source next to it. "Translation" sections are my own analysis, written for (a) a solo or small-team builder working with an AI agent, using Ben's template (CLAUDE.md, skills, DECISIONS.md, PARITY.md), and (b) teaching.

How to read this: Sections 1 to 10 cover the approaches in depth. Section 11 covers shorter entries. Section 12 is the ranked shortlist.

---

## 1. Value Sensitive Design (VSD)

**Origin and people.** VSD came out of information-systems and HCI work by Batya Friedman and Peter Kahn at the University of Washington, starting in the late 1980s ([Wikipedia: Value sensitive design](https://en.wikipedia.org/wiki/Value_sensitive_design)). Friedman and David G. Hendry wrote *Value Sensitive Design: Shaping Technology with Moral Imagination* (MIT Press, 2019). The second edition came out on April 7, 2026. It adds 8 hands-on "instructional studios" for professional development and classroom use, 16 Envisioning Cards, and 5 new methods (data statements, diverse voices, values hierarchy, Metaphor Cards, Security Cards), for 22 methods in total ([Penguin Random House listing](https://www.penguinrandomhouse.com/books/798075/value-sensitive-design-second-edition-by-batya-friedman-and-david-g-hendry/); [VSD Lab](https://vsdesign.org/)).

**Core principles.** The VSD Lab says VSD seeks "to provide theory, method, and practice to account for human values in a principled and systematic manner throughout the design process," by "engaging our moral and technical imaginations" ([vsdesign.org](https://vsdesign.org/)). It defines values as "what is important to people in their lives, with a focus on ethics and morality," and notes that values sit "in a delicate balance with each other" ([vsdesign.org/vsd](https://vsdesign.org/vsd/)). Today's VSD commits to "human well-being, justice and dignity" ([Wikipedia](https://en.wikipedia.org/wiki/Value_sensitive_design)).

**Methods and how they are done.**
- **Tripartite methodology.** Three kinds of investigation, repeated in cycles: *conceptual* (who are the stakeholders and what are their values), *empirical* (qualitative and quantitative study of people in context), and *technical* (how the properties of an existing or proposed technology support or hinder those values) ([Wikipedia](https://en.wikipedia.org/wiki/Value_sensitive_design)). A 2023 systematic review is pointedly titled "what happened to the technical investigations?", which suggests the technical leg is the one practitioners tend to drop ([Springer, Ethics and IT 2023](https://link.springer.com/article/10.1007/s10676-023-09700-2)).
- **Direct and indirect stakeholders.** Direct stakeholders interact with the technology. Indirect stakeholders are affected by it without using it ([Wikipedia](https://en.wikipedia.org/wiki/Value_sensitive_design)). The lab's "stakeholder tokens" help teams identify "direct, indirect, excluded, and other stakeholders as well as the relationships among stakeholder groups" ([vsdesign.org/vsd](https://vsdesign.org/vsd/)).
- **Value scenarios.** Developed by Nathan, Klasnja and Friedman (CHI EA 2007), these extend scenario-based design to envision *systemic* effects. A value scenario has five elements: stakeholders, pervasiveness, time, systemic effects and value implications ([Semantic Scholar entry](https://www.semanticscholar.org/paper/Value-scenarios:-a-technique-for-envisioning-of-new-Nathan-Klasnja/f9acf607b858ac110c1bf83bf62835bcc1820e83); [ACM DL](https://dl.acm.org/doi/10.1145/1240866.1241046)). In practice you write a short narrative: who is affected, what happens when everyone uses the tool, what happens over years, and which values are helped or hurt.
- **Envisioning Cards.** A deck built on four criteria: Stakeholders, Time, Values and Pervasiveness. Stakeholders can include "past and future generations, nonhuman species." Time covers "initial phases of novelty as well as the later phases." Pervasiveness covers "systemic interactions that follow from the widespread adoption" ([ResearchGate, Friedman and Hendry 2012](https://www.researchgate.net/publication/239761334_The_Envisioning_Cards_A_toolkit_for_catalyzing_humanistic_and_technical_imaginations)). Each card has a title and image on one side and a focused design activity on the other. There are three ways to use them: draw a random card, do its activity, then draw another; pin the relevant cards up and annotate your progress; or pick cards that fit the project ([Improving Everyday Ethics: Envisioning Cards](https://everydayethics.uxp2.com/methods/envisioning-cards/)). A free print-and-play deck (2024) is at [vsdesign.org](https://vsdesign.org/ecdocs/Envisioning_Cards_Single_Sided_Print-07-2024.pdf).
- **Value dams and flows** (Miller et al. 2007). A *value dam* is a "technical feature or organizational policy strongly opposed by even a small set of stakeholders." A *value flow* is one that "a large percentage of stakeholders would like to see included... even if [it is] not absolutely necessary." Steps: (1) list the value-based harms and benefits of each design option; (2) ask stakeholders how they feel about them; (3) classify each as a dam or a flow; (4) when a dam and a flow collide, treat it as a value tension and resolve it. The worked example is a developer Q&A system. "System could log what and how users search" is a privacy dam. "Users could post anonymously" sets trust against reputation ([TU Delft teaching slides, "Value Dams and Flows based on Miller et al. (2007)"](https://teachingforvaluesindesign.eu/assets/materials/ta_20/20_Value%20tensions-Value_dams_and_flows_slides.pdf)). The ethical rationale on those slides: "it is good practice to consider the rights and harms of persons in the minority."
- **Values hierarchy** (from van de Poel). Three layers: *values*, then *norms* ("restrictions on or prescriptions for action"), then *design requirements* (specific, checkable criteria). It can be built top-down or bottom-up ([search summary of van de Poel, "Translating Values into Design Requirements"](https://www.semanticscholar.org/paper/Translating-Values-into-Design-Requirements-Poel/ffff65c533cb9ae6210d6fbd2046040806a793b3)).
- **Diverse Voices** (UW Tech Policy Lab, 2015). Short, targeted panels of "experiential experts" from under-represented groups review a draft document. The steps are to select the document, identify the relevant groups, run the panels, synthesize the feedback, and return it to the authors. There is a free how-to guide ([Tech Policy Lab](https://techpolicylab.uw.edu/news/diverse-voices-guide/); [guide PDF](https://techpolicylab.uw.edu/wp-content/uploads/2017/10/TPL_Diverse_Voices_How-To_Guide_2017.pdf)).

**Strengths.** It is the most fully developed methodological toolkit in this list, with decades of case studies, and the 2nd edition is explicitly organized for teaching (the instructional studios).

**Critiques.** Borning and Muller (CHI 2012) argue that VSD overclaims. They say it should temper its stance on universal values, put value lists in context (whose culture made the list?), strengthen the participants' voice, and make the researchers' own voice explicit instead of substituting it for informants' ([Borning and Muller PDF](https://homes.cs.washington.edu/~borning/papers/borning-muller-chi2012.pdf); [ACM DL](https://dl.acm.org/doi/10.1145/2207676.2208560)). Other critics call VSD's definition of value "nebulous" and say it risks treating preferences as moral values ([Wikipedia](https://en.wikipedia.org/wiki/Value_sensitive_design)). There is also a "WEIRD" critique arguing for norm-sensitive design ([Springer 2023](https://link.springer.com/article/10.1007/s10516-023-09689-9)).

**Translation, (a) solo builder plus agent.**
- *Values hierarchy maps directly onto CLAUDE.md.* Ben's template already has the shape without naming it: a value ("human agency"), a norm ("no AI-written copy inside the product"), a requirement ("every user-visible string is human-authored; the agent may draft copy only in a PR comment for the human to rewrite"). Naming the three layers lets students see why "be learning-oriented" is too vague for an agent to act on. Claude Code's own docs say instructions should be "concrete enough to verify" and that vague ones are followed less reliably ([Claude Code memory docs](https://code.claude.com/docs/en/memory)). A values hierarchy is a disciplined way to get from a value to a verifiable instruction.
- *Indirect stakeholders as a standing question.* Add to the `learning-orientation-design` skill: "Who is affected who never opens the app? (the parent, the student whose teacher uses it, the person named in a shared collection)."
- *Value dams and flows as a feature gate.* A solo builder has no stakeholder survey, but the agent can produce the harms and benefits table, and the builder then asks 3 to 5 real people. A single dam (for example, "I would stop using it if it logged my searches") vetoes or reshapes the feature. This can be a section in DECISIONS.md entries.
- *Value scenarios run by the agent.* A prompt pattern: "Write a value scenario for this feature 5 years out, at 1 million users, from the perspective of an indirect stakeholder." The agent is good at producing these, and the human's job is to judge them.

**Translation, (b) teaching.** Use the free Envisioning Cards as a weekly ritual: draw a card at the start of each build session. Use the 2nd edition's instructional studios as ready-made lesson plans. Teach Borning and Muller alongside VSD so students learn to ask whose values a list encodes.

---

## 2. Design Justice

**Origin and people.** The Design Justice Network's principles were drafted in summer 2018 ([DJN principles](https://designjustice.org/read-the-principles)). Sasha Costanza-Chock's *Design Justice: Community-Led Practices to Build the Worlds We Need* (MIT Press, 2020) is open access ([OAPEN PDF](https://library.oapen.org/bitstream/handle/20.500.12657/43542/1/external_content.pdf)). The book shows how "universalist design principles and practices erase certain groups of people—specifically, those who are intersectionally disadvantaged or multiply-burdened under the matrix of domination" ([Web Science Trust summary](https://webscience.org/project/design-justice-community-led-practices-to-build-the-worlds-we-need-2/)).

**Core principles (the 10 DJN principles, abridged).** Use design to "sustain, heal, and empower"; "center the voices of those who are directly impacted"; "prioritize design's impact on the community over the intentions of the designer"; change is "emergent from an accountable, accessible, and collaborative process"; the "designer as a facilitator rather than an expert"; "everyone is an expert based on their own lived experience"; "share design knowledge and tools"; "sustainable, community-led and -controlled outcomes"; "non-exploitative solutions"; and "before seeking new design solutions, we look for what is already working at the community level" ([DJN](https://designjustice.org/read-the-principles)).

**Methods.** Design justice is more a lens than a procedure. Its central diagnostic is three questions: "Who participated? Who benefitted? Who was harmed?" It frames design as something that "distributes benefits and burdens between various groups of people" ([Wikipedia: Sasha Costanza-Chock](https://en.wikipedia.org/wiki/Sasha_Costanza-Chock)). There is classroom adaptation work, for example at Phillips Academy's Tang Institute ([Bringing Design Justice to the Classroom](https://tanginstitute.andover.edu/blog/2021/bringing-design-justice-to-the-classroom)).

**Strengths.** It names power, which VSD tends to treat as neutral. Principle 10 ("look for what is already working") is a strong antidote to building for the sake of building. "Impact over intention" is a useful corrective for any builder.

**Critiques and tensions.** Taken seriously, its demands (community-led and community-controlled) are hard for a solo builder to meet, and they can turn into tokenism. "Participation is not a design fix for machine learning" makes a similar warning about participation-washing ([arXiv 2007.02423](https://arxiv.org/pdf/2007.02423)).

**Translation, (a).** Put the three questions into every DECISIONS.md entry that touches users: "Who participated in this decision? Who benefits? Who could be harmed?" When a solo builder answers "only me participated," that honest answer is itself the point: it flags the decision for outside input. Principle 10 also maps to a pre-build check: "Is there an existing tool, practice or community norm that already does this? Can we support it instead of replacing it?" That fits Ben's "not to replace" value.

**Translation, (b).** "Impact over intention" works as a review rubric: students test their app with someone unlike themselves and report impact, not intent. "Designer as facilitator" also fits the teacher identity Ben brings.

---

## 3. Humane technology (Center for Humane Technology)

**Origin and people.** The Center for Humane Technology (CHT) was founded in 2018 by Tristan Harris, Aza Raskin and Randima Fernando. It grew out of Harris's 2013 Google deck and the "Time Well Spent" idea (TEDx 2014). It became widely known through *The Social Dilemma* (2020) and is credited with influencing Apple Screen Time and Google Digital Wellbeing ([Wikipedia: CHT](https://en.wikipedia.org/wiki/Center_for_Humane_Technology)). "Time Well Spent" was co-created with James Williams and Joe Edelman ([Wikipedia: Tristan Harris](https://en.wikipedia.org/wiki/Tristan_Harris)).

**Core principles.** CHT's free *Foundations of Humane Technology* course (2022, self-paced, about 4 to 8 hours) teaches six tenets: Respect Human Nature (treat attention and intentions as sacred), Minimize Harmful Consequences, Center on Values (over metrics), Create Shared Understanding, Support Fairness and Justice, and Help People Thrive ([humanetech.com/course](https://www.humanetech.com/course); [summary blog](https://blog.koalie.net/2023/10/23/4-the-foundations-of-humane-technology-centering-values/)). In 2019 CHT released design guides for assessing products across "human sensitivities" ([PR Newswire, April 2019](https://www.prnewswire.com/news-releases/center-for-humane-technology-s-tristan-harris-and-aza-raskin-launch-humane-a-new-agenda-for-tech-300836096.html)).

**Strengths.** Clear public framing (the attention economy, "persuasive technology"). A good on-ramp course. The idea that attention is something to protect is directly relevant to "only essential words on screen."

**Critiques.**
- *It came late and did not engage existing scholarship.* Critics say *The Social Dilemma* left out Safiya Noble, Sarah T. Roberts and Siva Vaidhyanathan, and gave reformed insiders "an easy ride to redemption" ([Librarian Shipwreck, "They meant well"](https://librarianshipwreck.wordpress.com/2021/04/28/they-meant-well-or-why-it-matters-who-gets-to-be-seen-as-a-tech-critic/); [Slate 2020](https://slate.com/technology/2020/09/social-dilemma-netflix-technology.html)).
- *Structural limits.* L.M. Sacasas: "Tinkering with the apparatus to make it more humane does not go far enough if the apparatus itself is intrinsically inhumane." He also argues that modern technology "tacitly conveys an anthropology, an understanding of what it means to be human" ([The Frailest Thing, 2018](https://thefrailestthing.com/2018/03/11/why-we-cant-have-humane-technology/)).
- *Co-optation.* Quartz argued that "Time Well Spent" had turned from a movement into a marketing strategy ([Quartz](https://qz.com/1347231/technologys-time-well-spent-movement-has-lost-its-meaning)).

**Translation, (a).** The most useful borrowing is "center on values over metrics." Ben's template has a `product-pulse-dashboard` skill. A humane version names the metrics it refuses to optimize (time-in-app, streaks) and the ones it tracks instead (tasks finished, things made, people helped). Sacasas's critique backs Ben's structural choices ($0, no tracking, user-owned data): those change the apparatus, not just the interface.

**Translation, (b).** Assign the CHT course as pre-work, then pair it with Sacasas and the Social Dilemma critiques so students learn to critique the critics. This also shows the difference between values as messaging and values as architecture.

---

## 4. Calm Technology

**Origin and people.** Mark Weiser and John Seely Brown (Xerox PARC) wrote "Designing Calm Technology" (December 21, 1995). Key ideas are *center vs. periphery*: "Calm technology engages both the center and the periphery of our attention, and in fact moves back and forth between the two." "By placing things in the periphery we are able to attune to many more things." The "locatedness" outcome is a sense of connection to one's surroundings. The example is Natalie Jeremijenko's "Dangling String," which showed network traffic by moving ([calmtech.com paper](https://calmtech.com/papers/designing-calm-technology.html)). Amber Case formalized the principles in *Calm Technology* (O'Reilly, 2015) ([Wikipedia: Calm technology](https://en.wikipedia.org/wiki/Calm_technology)).

**Amber Case's eight principles** ([calmtech.com](https://calmtech.com/)):
1. Technology should require the smallest possible amount of attention.
2. Technology should inform and create calm.
3. Technology should make use of the periphery.
4. Technology should amplify the best of technology and the best of humanity.
5. Technology can communicate, but doesn't need to speak.
6. Technology should work even when it fails.
7. The right amount of technology is the minimum needed to solve the problem.
8. Technology should respect social norms.

The site lists "calm communication" patterns (haptic alerts, status lights, status tones, trend graphs, delays) and a "Calm Tech Certified" program run by the Calm Tech Institute.

**Critique that matters most for Ben.** Yvonne Rogers' "Moving on from Weiser's Vision of Calm Computing: Engaging UbiComp Experiences" (UbiComp 2006) argues for "engaging rather than calming people." People are resourceful, so technology should help them "combine, adapt and use" tools instead of acting invisibly on their behalf ([Halfway to the Future summary](https://www.halfwaytothefuture.org/2019/programme/rogers-moving-on-from-weiser-s-vision-of-calm-computing-engaging-ubicomp-experiences/); [Springer](https://link.springer.com/chapter/10.1007/11853565_24)). This is the exact tension in a learning app. Calm is right for chrome, notifications and status. *Engagement* is right for the learning itself, because the point is to make people think.

**Translation, (a).** Case's #5, #6 and #7 already sit near the template's values: "only essential words," "a reader that cannot read says so," and the minimum technology. A useful rule to write down: **"Calm in the chrome, effortful in the core."** The interface stays out of the way, and the learning task asks for real effort. This settles the Weiser vs. Rogers debate as an explicit design rule that an agent can apply. #6 ("work even when it fails") matches the template's `universal-feature-states` skill (loading, empty, error, offline).

**Translation, (b).** Teach Weiser and Rogers as a paired debate. Then have students sort every element of their app into "periphery" or "center" and defend the choice.

---

## 5. Small Technology and Ethical Design (Aral Balkan, Laura Kalbag)

**Origin and people.** Aral Balkan and Laura Kalbag founded Ind.ie (2014) and then the Small Technology Foundation, based in Ireland ([small-tech.org/about](https://small-tech.org/about/)).

**Ethical Design Manifesto.** Balkan's "3 Rs" (April 20, 2015) are respect for human rights and dignity, respect for human effort, and respect for human experience, which "collapse into one overarching principle: respecting the human." The pyramid replaces Aarron Walter's emotional-design pyramid (functional, reliable, usable, pleasurable) with an ethical base. Quote: "Design without ethics is manipulation" ([ar.al, The 3 Rs of Ethical Design](https://ar.al/notes/the-3-rs-of-ethical-design/)). As usually described: *human rights* at the base (decentralized, private, open, interoperable, accessible, secure, sustainable), *human effort* in the middle (functional, convenient, reliable), and *human experience* at the top (delightful) ([P2P Foundation Wiki](https://wiki.p2pfoundation.net/index.php/Ethical_Design_Manifesto); [Small Tech video](https://small-tech.org/videos/ethical-design-manifesto/)).

**Small Technology principles** ([small-tech.org/about](https://small-tech.org/about/)): easy to use; personal ("everyday tools for ordinary people, not enterprises or startups"); private by default; zero knowledge; peer to peer; share alike (copyleft); interoperable; non-commercial; non-colonial ("development teams should reflect target demographics"); inclusive.

**Strengths.** This is the closest existing match to Ben's stack values ($0, no tracking, user's own cloud, open source). The pyramid makes a useful *ordering* claim: delight cannot make up for violated rights.

**Critiques.** It is absolutist about business models ("non-commercial") and about architecture (P2P and zero-knowledge are hard, which conflicts with "easy to use"). Balkan's rhetoric ("Most mainstream technology today is malware") can put off mainstream audiences ([ar.al](https://ar.al/notes/the-3-rs-of-ethical-design/)).

**Translation, (a).** Use the pyramid as a *priority order for the agent*: when values conflict, rights beat effort, and effort beats delight. Anthropic's constitution uses the same move: a short ordered list of priorities, explained with reasons (see section 10). Write it into CLAUDE.md: "When a design choice trades privacy for polish, privacy wins; say so in the PR." Ben's "people's data in their own cloud" also fits the Small Tech principles better than full P2P does, and it is a reasonable middle path.

**Translation, (b).** Have students draw their app's pyramid and mark which layer each feature serves. If a feature sits only at the "delight" level and no support from the lower layers is visible, it is suspect.

---

## 6. Local-first software and data sovereignty

**Origin and people.** Martin Kleppmann, Adam Wiggins, Peter van Hardenberg and Mark McGranaghan, Ink & Switch, April 2019 ([Ink & Switch, "Local-first software"](https://www.inkandswitch.com/essay/local-first/)).

**The seven ideals** (same source):
1. No spinners: your work at your fingertips.
2. Your work is not trapped on one device.
3. The network is optional.
4. Seamless collaboration with your colleagues.
5. The Long Now: "Your work should continue to be accessible indefinitely, even after the company that produced the software is gone."
6. Security and privacy by default.
7. You retain ultimate ownership and control.

**Practices.** The essay suggests you "score your current application against these seven criteria," then improve the weak areas. Its concrete guidance: export to standard formats (JSON, SQLite), offline via service workers, CRDTs (Automerge) for collaboration, and end-to-end encryption when syncing through servers.

**Related work: Malleable software** (Litt, Horowitz, van Hardenberg, Matthews, June 2025). It argues for a "gentle slope from user to creator," "tools over apps," and communal creation by "local developers." On AI: "Bringing AI coding tools into today's software ecosystem is like bringing a talented sous chef to a food court" ([Ink & Switch, Malleable software](https://www.inkandswitch.com/essay/malleable-software/)).

**Data sovereignty: CARE.** The CARE Principles for Indigenous Data Governance (Global Indigenous Data Alliance, 2019) are Collective benefit, Authority to control, Responsibility and Ethics. They were drafted by Stephanie Russo Carroll, Maui Hudson, Tahu Kukutai and others as a "people-and-purpose" complement to the data-centric FAIR principles ([Wikipedia: CARE Principles](https://en.wikipedia.org/wiki/CARE_Principles_for_Indigenous_Data_Governance); [Data Science Journal 2020](https://datascience.codata.org/articles/10.5334/dsj-2020-043); [Ada Lovelace Institute on operationalizing CARE](https://www.adalovelaceinstitute.org/blog/care-principles-operationalising-indigenous-data-governance/)). The key move is that sovereignty can be *collective*, not just individual. That matters for classroom and community data, where "the user owns it" is not the whole story.

**Critiques.** CRDT conflict resolution can be "technically consistent but semantically unexpected to users." Engineers with experience are scarce, and the industry is moving toward server-authoritative sync engines (for example, ElectricSQL's 2024 pivot) ([search summary; Loro, "CRDTs are not enough"](https://loro.dev/blog/crdt-is-not-enough); [RxDB on limitations](https://rxdb.info/articles/local-first-future.html)).

**Translation, (a).** Ben's per-ecosystem sync (iCloud and similar, "people's data in their own cloud") already meets ideals 1, 2, 3, 6 and 7 without CRDTs. Two borrowings:
1. Add a **seven-ideals scorecard** row to PARITY.md, or a one-time audit, scored per platform. The agent can run it.
2. **The Long Now as a standing rule:** every app ships a human-readable export (JSON or Markdown) and states what happens to your data if the developer disappears. This is honesty about durability, which fits the "a reader that cannot read says so" value.

Malleable software's "gentle slope" is the software-architecture version of "low floor, high ceiling." It is a strong bridge into Ben's course.

**Translation, (b).** Students score an app they use every day against the seven ideals, then score their own. CARE gives a way to discuss classroom data ("whose data is a class's shared work?").

---

## 7. Participatory design (Scandinavian tradition)

**Origin and people.** The UTOPIA project (1981 to 1985), run by the Nordic Graphic Workers' Union with researchers including Susanne Bødker, Pelle Ehn and Morten Kyng. Its goal was to "give the end users a voice." Its lasting result was the methodology, not the software: "low-tech prototyping, early design sessions with users." Methods included "low tech mock-ups of equipment (wooden mouses, cardboard laser writer...), material and menus (paper)," a "technology laboratory" where graphic workers carried out page make-up on simulation equipment, and "a tool kit (box with waxed cards) for modelling and experimenting with work organisation" (Bødker, Ehn et al., "Co-operative Design: perspectives on 20 years with the Scandinavian IT Design Model," [PDF](https://www.lri.fr/~mbl/ENS/DEA-IHM/papers/Utopia.pdf)). Ehn and Kyng's "Cardboard Computers" (1991) is the classic citation (same source).

**Core principles.** Simonsen and Robertson's *Routledge International Handbook of Participatory Design* lists equalizing power relations, democratic practices, situation-based action, mutual learning, tools and techniques, and alternative visions about technology. It defines *genuine participation* as users going from "merely informants" to "legitimate and acknowledged participants" ([ResearchGate: PD and Design for Values](https://www.researchgate.net/publication/278713757_Participatory_Design_and_Design_for_Values); [Handbook](https://www.researchgate.net/publication/235994472_Routledge_International_Handbook_of_Participatory_Design)). *Mutual learning*: designers learn the users' realities while users learn "appropriate technological means."

**Critique from inside.** Bødker and Kyng (2018) argue that today's PD has shrunk to "small issues... products and technological solutions that the users like," with user involvement as "a one-way process: Requirements are elicited from, usability tested upon, and systems are delivered to users." They also note that participants often experience participation as "a tiresome addition... with no relation to goals that are important to the users." They call for alliances, working prototypes and democratic control ([Bødker and Kyng, "Participatory Design that Matters," ACM TOCHI 2018](https://csethics.nd.edu/assets/503108/bodker_kyng_2018_participatory_design_that_matters.pdf)).

**Translation, (a).** AI changes the economics of PD. UTOPIA needed cardboard because real prototypes were expensive. With Claude Code, a working prototype costs an afternoon, so the *working prototype becomes the cardboard computer*. The borrowed practice is **co-design sessions around disposable working prototypes**: bring 2 or 3 throwaway variants to the actual users (teachers, students), watch them work, and let *them* pick and reshape. Then record what they said in their own words. Bødker and Kyng's warning applies: give participants something they get back (the tool itself, credit, control). Do not just extract requirements from them.

**Translation, (b).** "Mutual learning" is a teaching value in itself. A course assignment: each student must have one non-technical co-designer, and the deliverable includes what *each* party learned.

---

## 8. Constructionism and learning-centred design (Papert, Resnick)

**Origin and people.** Seymour Papert (Logo, *Mindstorms*), and Mitchel Resnick (MIT Lifelong Kindergarten, Scratch).

**Core principles.**
- *Constructionism* (Papert and Harel, 1991): it shares constructivism's view of learning as "building knowledge structures" and adds that this happens "especially felicitously in a context where the learner is consciously engaged in constructing a public entity, whether it's a sand castle on the beach or a theory of the universe" ([EduTech Wiki](https://edutechwiki.unige.ch/en/Constructionism); [Situating Constructionism PDF](https://archive.org/download/papert-harel-situating-constructionism/papert-harel-situating-constructionism.pdf)).
- *Low floor, high ceiling, wide walls.* Papert's low floor and high ceiling date from Logo. Resnick added "wide walls." In his own words (2008), these are "technologies that have not only a low floor (easy to get started with) and a high ceiling (opportunities for increasingly complex explorations over time), but also what I have come to call 'wide walls' — that is, technologies that are accessible and inviting to children with all different learning styles and ways of knowing." He ties wide walls to Papert and Turkle's *epistemological pluralism*, and also credits Papert's "Hard Fun" (activities "playful but at the same time engage learners in serious and sustained and challenging explorations") (Resnick, "Falling in Love with Seymour's Ideas," AERA 2008, [PDF](https://web.media.mit.edu/~mres/papers/AERA-seymour-final.pdf)). Other sources describe wide walls as "many different paths one can take" ([search summary; ScratchEd](https://scratched.gse.harvard.edu/stories/creative-computing-all.html)).
- *Creative Learning Spiral:* imagine, create, play, share, reflect, then imagine again ([EdWeek 2017](https://www.edweek.org/leadership/opinion-the-creative-learning-spiral-starting-with-your-imagination-in-design-thinking/2017/03)).
- *The 4 Ps:* Projects, Passion, Peers, Play (Resnick, *Lifelong Kindergarten*, MIT Press 2017) ([Scratch.by](https://scratch.by/en/about/news/mitchel_resnick_the_four_ps_of_creative_learning/)).

**Critiques.** Kirschner, Sweller and Clark (2006) argue that minimally guided instruction "is less effective and less efficient" than guided instruction for novices, and that the advantage of guidance fades only when learners have high prior knowledge ([ERIC](https://eric.ed.gov/?id=EJ736299)). A CUNY essay argues that Scratch has "High Floors, Low Ceilings, and Narrow Walls" for music, which shows the metaphor depends on the domain ([JITP](https://jitp.commons.gc.cuny.edu/music-making-in-scratch-high-floors-low-ceilings-and-narrow-walls/)).

**Translation, (a).**
- Ben already uses "low floor, high ceiling." **Add "wide walls" explicitly** as a feature test: "Does this feature allow more than one valid way of doing and knowing, or does it funnel everyone down one path?" This works especially well against AI features that hand out one "correct" output.
- "Hard fun" names the "effortful core" idea from the Calm Tech section, and it has an education pedigree.
- The Creative Learning Spiral can serve as the template's *feature lifecycle for learning features*. Every feature should support at least the *share* and *reflect* steps, not just *create*. Constructionism's "public entity" maps to Ben's open-web and share-URL values: what learners make should be shareable as a real artifact.
- Kirschner et al. give a guardrail: low floors need scaffolding (guidance for novices), not emptiness.

**Translation, (b).** The course itself can be constructionist. Students build a public artifact (their app), and each unit follows the spiral. The Kirschner critique should be taught honestly. Ben's AI-agent context is a live example: an agent that does everything is "maximal guidance," which removes the learning. The course can teach where on that range each lesson should sit.

---

## 9. Responsible Research and Innovation (RRI) and the AREA framework

**Origin and people.** Stilgoe, Owen and Macnaghten (2013) define responsible innovation as "taking care of the future through collective stewardship of science and innovation in the present," with four dimensions: anticipation, reflexivity, inclusion and responsiveness. EPSRC (UK) turned this into AREA: **Anticipate, Reflect, Engage, Act** ([search summary; UKRIO RRI intro](https://ukrio.org/wp-content/uploads/UKRIO-RRI-webinar-Jan25-v2.pdf); [Online Ethics Center: RI subject aid](https://onlineethics.org/cases/oec-subject-aids/responsible-innovation-subject-aid)).

**Strengths and critiques.** It is lightweight and cyclical, and it applies *throughout* a project rather than as a gate. Critics note that it was designed for publicly funded research institutions and that it can turn into box-ticking. The "Seeing Like a Toolkit" study (below) makes a related point.

**Translation, (a).** AREA works as a four-line block in DECISIONS.md: *Anticipate* (what could this become at scale?), *Reflect* (what am I assuming?), *Engage* (who did I ask?), *Act* (what did I change because of it?). "Act" is the important part: it forces evidence that the reflection changed something. **(b)** AREA is a simple acronym for a reflection journal that students keep alongside their commits.

---

## 10. Values written where the agent reads them: constitutions, specs, CLAUDE.md

**Anthropic's constitution.** Published January 21, 2026 ([YourStory](https://yourstory.com/ai-story/anthropic-claude-new-constitution-jan-2026); [Anthropic on X](https://x.com/AnthropicAI/status/2014005798691877083?lang=en)). It is released under CC0, written primarily *for Claude*, and used directly in training. It orders four priorities: broadly safe, then broadly ethical, then compliant with Anthropic's guidelines, then genuinely helpful. Its central method: "We generally favor cultivating good values and judgment over strict rules and decision procedures." The aim is for Claude to "have such a thorough understanding of its situation and the various considerations at play that it could construct any rules we might come up with itself." A small set of *hard constraints* remain as bright lines ([anthropic.com/constitution](https://www.anthropic.com/constitution); [Oxford AI Ethics commentary](https://www.oxford-aiethics.ox.ac.uk/blog/claudes-new-constitution-two-evaluative-continua)). The earlier "Constitutional AI" paper (Bai et al. 2022) used about 16 short natural-language principles for self-critique and revision, plus AI feedback ([arXiv 2212.08073](https://arxiv.org/pdf/2212.08073)).

**Claude Code's guidance on CLAUDE.md** ([code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory)):
- CLAUDE.md is "context, not enforced configuration." To block an action for certain, use a PreToolUse hook.
- "Write instructions that are concrete enough to verify." Target under 200 lines. Contradictory instructions mean "Claude may pick one arbitrarily."
- Multi-step procedures belong in *skills*. Path-specific rules belong in `.claude/rules/` with `paths:` frontmatter.
- Add to CLAUDE.md when "Claude makes the same mistake a second time."
- `/doctor prompt-audit` checks instruction files for outdated or conflicting content.

**Synthesis: what this means for "values in the prompt".** There are three layers, and Ben's template already uses all three without naming the split:
1. **Constitution layer (judgment).** The "Why we build" paragraph, written as reasons, with an *ordered* priority list. Following Anthropic's approach, explain *why* each value matters so the agent can generalize to cases nobody anticipated.
2. **Norm layer (checkable rules).** Standing instructions phrased so they can be verified ("no AI-written copy in user-facing strings").
3. **Enforcement layer (hooks and CI).** Wherever a value can be checked mechanically, check it mechanically, for example a hook that rejects a commit adding a tracking SDK or analytics domain, or a lint rule that flags emoji in UI chrome. Values that matter most should not depend on the agent remembering.

This gives the course a precise lesson: **a value moves down the stack as it becomes more certain.** It starts as a reason, becomes a norm, and finally becomes a hook. VSD's values hierarchy (value, norm, requirement) is the academic name for the same move.

**Critique.** Wong, Madaio and Merrill's "Seeing Like a Toolkit" (CSCW 2023) analyzed 27 AI-ethics toolkits. They found a mismatch between the imagined work of ethics and what toolkits support, with a tendency toward the technical and the individual ([ACM DL PDF](https://dl.acm.org/doi/pdf/10.1145/3579621)). The same risk applies here: writing values into a file can feel like doing ethics. The DECISIONS.md "Act" line (from AREA) and real co-design (from PD) are the counterweights.

---

## 11. Shorter entries

- **Microsoft HAX: Guidelines for Human-AI Interaction** (Amershi et al., CHI 2019). 18 guidelines in four phases. The most relevant to Ben: **G1** "Make clear what the system can do"; **G2** "Make clear how well the system can do what it can do"; **G8** "Support efficient dismissal"; **G9** "Support efficient correction"; **G10** "Scope services when in doubt"; **G11** "Make clear why the system did what it did"; **G17** "Provide global controls" ([Microsoft Research blog](https://www.microsoft.com/en-us/research/blog/guidelines-for-human-ai-interaction-design/)). G2 and G10 are, almost word for word, Ben's honesty value ("a reader that cannot read says so"). The free HAX Toolkit has a workbook and a playbook ([ACM CHI EA 2023](https://dl.acm.org/doi/fullHtml/10.1145/3544549.3574191)). *Use*: run G1, G2, G10 and G11 as a checklist on any feature that involves a bot or automation.
- **Ethical OS** (Institute for the Future and Omidyar Network, 2018). Eight risk zones: Truth/Disinformation; Addiction and the Dopamine Economy; Economic and Asset Inequalities; Machine Ethics and Algorithmic Biases; Surveillance State; Data Control and Monetization; Implicit Trust and User Understanding; Hateful and Criminal Actors. Plus 14 scenarios and 7 future-proofing strategies ([Ethical OS PDF](https://mediaethics.ca/wp-content/uploads/2019/11/Ethical-OS-Toolkit-2.pdf); [OECD OPSI](https://oecd-opsi.org/toolkits/ethical-os-toolkit/)). *Use*: a one-time pre-launch checklist.
- **Tarot Cards of Tech** (Artefact, 2018). Provocation cards, for example *The Backstabber* ("What could cause people to lose trust in your product?") and *The Scandal* ("What's the worst headline about your product you can imagine?") ([GeekWire](https://www.geekwire.com/2018/seattle-studios-tarot-cards-tech-help-users-see-future-slow-ask-better-questions/); [Artefact PDF](https://www.artefactgroup.com/wp-content/uploads/2018/10/Artefact-Tarot-Cards-of-Tech_downloadable.pdf)). *Use*: quick, fun, good for teaching. Lighter than the Envisioning Cards.
- **Consentful Tech** (Allied Media Projects). Applies FRIES consent (Freely given, Reversible, Informed, Enthusiastic, Specific) to data ([consentfultech.io](https://www.consentfultech.io/)). *Use*: a five-point test for every permission prompt and every data-sharing flow. "Reversible" maps to a delete or export path.
- **Slow Technology** (Hallnäs and Redström, 2001). "A design agenda for technology aimed at reflection and moments of mental rest rather than efficiency." "When we use a thing as an efficient tool, time disappears... Accepting an invitation for reflection... time will appear" ([Springer, Personal and Ubiquitous Computing 5](https://link.springer.com/article/10.1007/PL00000019)). *Use*: a counterweight to speed metrics. Some learning moments *should* be slow.
- **Feminist HCI** (Shaowen Bardzell, CHI 2010). Six qualities: pluralism, participation, advocacy, ecology, embodiment, self-disclosure ([ResearchGate](https://www.researchgate.net/publication/221513596_Feminist_HCI_Taking_stock_and_outlining_an_agenda_for_design)). A 2020 citation analysis found the qualities widely cited but rarely put into practice. *Use*: "self-disclosure" (software that makes its own assumptions about the user visible) fits Ben's honesty value. "Pluralism" echoes wide walls.
- **Permacomputing.** Ten principles, including "Observe first," "Not doing" (refusal), "Expose the seams," "Build on solid ground" (mature, open standards), "Care for all hardware" ([permacomputing.net/principles](https://permacomputing.net/principles/)). *Use*: "Not doing" and "Build on solid ground" justify the template's vanilla-JS, no-build-step, no-third-party-packages stance as a values choice, not just a technical taste. "Expose the seams" fits honesty.
- **Convivial tools** (Ivan Illich, *Tools for Conviviality*, 1973). Tools that let users "exercise their human autonomy and creativity," as opposed to industrial tools that become "destructive to human autonomy" ([Wikipedia](https://en.wikipedia.org/wiki/Tools_for_Conviviality)). This is the philosophical root of "support, not replace." It suits a course reading list, especially since Illich also wrote *Deschooling Society*, which a teacher audience will find provocative.
- **Home-cooked software** (Robin Sloan, 2020). He built BoopSnoop for four family members: "I am the programming equivalent of a home cook." "It won't change unless we want it to change. There will be no sudden redesign, no flood of ads" ([robinsloan.com](https://www.robinsloan.com/notes/home-cooked-app/)). *Use*: makes legitimate the small, for-my-people app that AI agents now make possible. This is a strong opening framing for Ben's course.
- **Doughnut Design for Business** (Doughnut Economics Action Lab). Asks whether an enterprise is "regenerative by design" and "distributive by design" across five layers: Purpose, Networks, Governance, Ownership, Finance ([DEAL tool](https://doughnuteconomics.org/tools/doughnut-design-for-business-core-tool)). *Use*: in Ben's terms, "$0 to run" and open source are Ownership and Finance choices. This tool gives students a way to see business model as a value decision. It is mainly for the course, less for the template.

---

## 12. Ranked shortlist: the most useful ideas for Ben's template and course

1. **Values hierarchy: value, then norm, then requirement, then hook** (VSD / van de Poel, plus Anthropic's constitution and the Claude Code docs).
   *Practice to borrow:* restructure "Why we build" plus the standing instructions into three explicit tiers. (1) Ordered values *with reasons*, so the agent can judge cases nobody anticipated, as in Anthropic's constitution. (2) Verifiable norms. (3) Mechanical enforcement through hooks and CI for the values that must never slip (no tracking SDKs, no emoji chrome, no unreviewed AI copy in UI strings). *Course:* the central lesson. "A value travels down the stack as you become sure of it."

2. **Value dams and flows, plus Design Justice's three questions, in every DECISIONS.md entry** (VSD; Costanza-Chock).
   *Practice:* add a short block to the decision template: *Who participated? Who benefits? Who could be harmed? Any dam (one stakeholder strongly opposed)? Any flow?* The agent drafts it, and the human checks it with 3 to 5 real people. A single dam reshapes the feature.

3. **Working prototypes as cardboard computers: AI-enabled participatory design** (UTOPIA; Bødker and Kyng).
   *Practice:* for any substantial feature, the agent builds 2 or 3 disposable variants, and a real user (teacher, student) uses them and chooses or reshapes one. Log their words verbatim, and make sure they get something back. *Course:* every student has a non-technical co-designer, and the "mutual learning" log is a graded artifact.

4. **Add "wide walls" and "hard fun" to the low-floor/high-ceiling test** (Papert, Resnick), together with **"calm in the chrome, effortful in the core"** (Weiser and Case vs. Rogers).
   *Practice:* extend the `learning-orientation-design` skill with two questions. "Does this allow more than one valid path or way of knowing?" "Is the effort we ask for the learning itself (keep it) or friction in the chrome (remove it)?" This settles a real tension in "only essential words" without stripping out the productive struggle.

5. **Honest capability disclosure** (Microsoft HAX G1, G2, G10, G11; Feminist HCI self-disclosure; permacomputing "expose the seams").
   *Practice:* a short checklist for any automated or bot feature: says what it can do, says how well, degrades openly when uncertain, can explain itself. This turns Ben's "a reader that cannot read says so" into a named, citable standard.

6. **Local-first seven-ideals scorecard plus "The Long Now" export rule** (Ink & Switch; CARE for the collective case; Consentful Tech FRIES for permissions).
   *Practice:* score each platform once against the seven ideals and record the result in PARITY.md. Make "human-readable export plus a stated data-after-we're-gone promise" a parity row. Run every permission prompt through FRIES (especially *Reversible* and *Specific*).

7. **Envisioning Cards or Tarot Cards as a session ritual** (VSD; Artefact).
   *Practice:* begin each build session, or each course class, by drawing one card and spending five minutes applying it to the current feature, with the agent as the sparring partner ("argue the indirect-stakeholder case against this feature"). It is cheap and repeatable, and it builds moral imagination over time instead of as a single compliance gate.

**Honorable mentions for the course reading list:** Sloan's "home-cooked meal" as the opening framing; Illich for the "support, not replace" lineage; Sacasas and the Social Dilemma critiques so students learn that interface-level humane design is not enough without structural choices (which Ben's $0, no-tracking and user-owned-data architecture actually makes); Kirschner, Sweller and Clark as an honest counterpoint about how much guidance novices need, which is directly relevant to how much the agent should do for learners.
