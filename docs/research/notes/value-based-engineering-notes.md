# Value-Based Engineering (VBE): research notes

Compiled 2026-10-01. Every factual claim carries a source. Lines marked **[Interpretation]** are my own reading, not something a source states.

## Source quality and access notes

- **Primary texts read in full or near-full:**
  - Spiekermann & Winkler, "Value-based Engineering with IEEE 7000" (IEEE Technology & Society Magazine, Sept 2022; arXiv preprint): https://arxiv.org/pdf/2207.07599
  - Spiekermann & Winkler, "Value-based Engineering for Ethics by Design" (2020 preprint): https://arxiv.org/pdf/2004.13676. This is the most detailed public process description, with 14 requirements and 20 recommendations.
  - Spiekermann, "From Value-lists to Value-based Engineering with IEEE 7000" (IEEE ISTAS 2021): https://vbe.academy/wp-content/uploads/2025/04/2021_ISTAS_Spiekermann.pdf
  - Spiekermann's IEEE 7000 launch slides (Vienna, 16 Nov 2021): https://gsis.at/wp-content/uploads/2021/12/VBELaunch_Spiekermannpptx_circ.pdf
  - Bednar & Spiekermann, "The Power of Ethics" (BISE 2023): https://d-nb.info/1315314770/34 (open-access copy; DOI 10.1007/s12599-023-00837-4)
  - Bednar & Spiekermann, "Eliciting Values for Technology Design with Moral Philosophy" (ST&HV): https://vbe.academy/wp-content/uploads/2025/04/2022_Bednar_Eliciting-Values-for-Technology-Design-with-Moral-Philosophy_-An-Empirical-Explorat_.pdf
  - Till Winkler's PhD thesis, which compares VSD and IEEE 7000: https://vbe.academy/wp-content/uploads/2025/04/Thesis_TW_.pdf
  - The Austrian Standards certification scheme P90: https://cdn.austrian-standards.at/asset/dokumente/produkte-loesungen/Zertifizierung/schemata/P-08.90_Value_Based_Engineering_Ambassador_2024-04-10.pdf
- **The standard itself (IEEE Std 7000-2021 / ISO/IEC/IEEE 24748-7000:2022):**
  - The front matter and table of contents come from the official ISO preview: https://cdn.standards.iteh.ai/samples/84893/fa41581591e741259f69516e0adfbb34/ISO-IEC-IEEE-24748-7000-2022.pdf
  - I verified clause text for clauses 1.2–1.4, 4, 6, 7.3–7.5, 8.5, 9.5, 10.5 and 11.5 against a full-text copy I found online. I cite these by clause number. The canonical record is https://ieeexplore.ieee.org/document/9536679/.
  - IEEE makes IEEE 7000-2021 free to download (account required) through the IEEE GET Program: https://www.businesswire.com/news/home/20230117005108/en/IEEE-Introduces-New-Program-for-Free-Access-to-AI-Ethics-and-Governance-Standards
- **Not accessible:**
  - Bärbel Bohr, "How to Turn Ethical Values Into System Requirements: Lessons Learned from Adopting a New IEEE Standard in the Business World" (IEEE Software 42(1), Jan/Feb 2025, pp. 9–16): https://ieeexplore.ieee.org/document/10777892/. It is paywalled. I have only the metadata and the search-snippet abstract: an "Insights" article in which Bohr and interviewees reflect on building and adopting IEEE 7000.
  - Spiekermann's 2023 De Gruyter book. I have only its table of contents (https://www.degruyter.com/document/isbn/9783110793383/html), not the full text.
  - The vbe.academy "tools" page returned 404. Tool names below come from the method page instead.
- **Wikipedia caveat:** the Wikipedia article (https://en.wikipedia.org/wiki/Value-based_engineering) is flagged as an "orphan." Its adoption claims (City of Vienna, European Defence Agency) are second-hand, and I did not verify them beyond what vbe.academy shows.

---

## 1. What VBE is

### Definition and its relation to IEEE 7000

- **Wikipedia** calls VBE "a practical implementation of IEEE 7000, condensing and structuring its methodology into actionable steps."
- **Spiekermann & Winkler (2022)** describe it as "a transparent, clearly-structured, step-by-step methodology combining innovation management, risk management, system and software engineering in one process framework" that "embeds a robust value ontology and terminology." (https://arxiv.org/pdf/2207.07599)
- **The 2021 launch slides** put the relationship directly: "VBE is a tested way to implement IEEE 7000." (gsis.at slides)
- **VBE is not identical to the standard.** Spiekermann (ISTAS 2021) names two differences:
  1. "Unlike IEEE 7000TM, VbE encourages the active consideration of foregoing a technology for ethical reasons."
  2. On VBE's agile path: "IEEE 7000TM does not distinguish between a rigorous or agile derivation of system requirements."
- **Caveat on the first difference.** IEEE 7000 clause 7.3(h)(2) Note does say that an organization unable to control the system "can modify the project scope of work to exclude the EVR; or alternatively terminate the project."
- **[Interpretation]** So the standard allows walking away, but VBE turns it into a stated principle ("Willingness to Renounce Investment").

### Origin and timeline

- **2015/2016.** VBE grew out of Spiekermann's textbook *Ethical IT Innovation: A Value-Based System Design Approach* (CRC Press, 2016). Spiekermann & Winkler (2022) write that VBE "was first sketched out in primitive form in 2016 … and then diligently evolved over a five-year standardization process."
- **2016–2021: IEEE P7000.** The standards work ran in three phases (technologyandsociety.org, https://technologyandsociety.org/what-to-expect-from-ieee-7000-the-first-standard-for-building-ethical-systems/):
  - 2016–17: kickoff, with Spiekermann's textbook as the baseline, plus VSD, participatory design and risk assessment.
  - 2017–18: four subgroups.
  - 2018–21: three ballots and more than 1,000 comments.
  - About 154 experts took part, 34 of them formal working-group members.
- **16 June 2021.** The IEEE SA Standards Board approved IEEE 7000 (ISO preview front matter).
- **15 Sept 2021.** IEEE 7000 was published (ISO preview).
- **November 2022.** ISO/IEC JTC 1/SC 7 adopted it by fast-track as **ISO/IEC/IEEE 24748-7000:2022**, first edition 2022-11 (ISO preview Foreword; https://www.iso.org/standard/84893.html). It now sits in the 24748 "Life cycle management" series alongside 12207 and 15288.

### People

- **The working group:** Ali Hessami (Chair), Sarah Spiekermann (Vice Chair), Zvikomborero Murahwi (Secretary) and Annette Reilly (Technical Editor). Other members include Lewis Gray, Ruth Lewis, Robert Schaaf, Gisele Waters, Lee Barford, Jacob Metcalf, Till Winkler and Barbara (Bärbel) Bohr. John C. Havens is acknowledged. (ISO preview, Participants page)
- **Sarah Spiekermann** chairs the Institute for IS & Society at WU Vienna and was "co-initiator and vice-chair of IEEE 7000 from 2016–2021" (author bio in arXiv 2207.07599).
- **Her PhD students** Kathrin Bednar and Till Winkler supplied case-study and empirical work (https://www.wu.ac.at/en/information-systems-and-society/projects/ieee-p7000-standard).

### Institutions

- **WU Vienna, Institute for IS & Society.** Hosts the research portal: https://www.wu.ac.at/value-based-engineering/research
- **VBE Academy (vbe.academy).** Lists Sarah Spiekermann and Mario Tokarz as founders.
  - Partners: Austrian Standards Academy, IEEE, Innovethic (CEO Lukas Madl), RightMinded.ai (Tokarz) and GRAIL Lab (https://vbe.academy/, https://vbe.academy/people/).
  - It is "an Authorized Education Center of Austrian Standards" (https://vbe.academy/academy/ambassador-training/).
- **Austrian Standards plus Certification.** Runs the personal certification described in §4.
- **Adoption claims on Wikipedia:**
  - The City of Vienna announced VBE adoption in October 2024.
  - The European Defence Agency recommends VBE.
  - Austrian Standards launched certification in July 2024.

### Relation to Value Sensitive Design (VSD)

**What the VBE authors say:**

- VSD "has accumulated over 200 case studies," but "has been unable to put forth a stringent process model that companies would be able to follow in a consistent and structured manner." (Spiekermann & Winkler 2022)
- VBE differs in three ways (same source):
  - It "ensures that through a traceable, replicable and iterative process value harms and benefits are systematically and technically addressed and monitored."
  - It integrates value requirements with the functional roadmap.
  - It grounds its value ontology "in a post-phenomenological account of value actualization."
- VBE borrows VSD's "conceptual analysis" and its direct/indirect stakeholder distinction (Spiekermann & Winkler 2020, §3.2 and §4.1.4).
- VBE differs from VSD on elicitation. VSD "does not commit to a singular ethical theory," and in practice its users tend to elicit values only by asking about benefits and harms ("intuitively following a form of utilitarian ethics"). VBE "requir[es] the use of guiding questions derived from three grand ethical theories." (2020, §4.1.1)
- VBE differs from VSD on value conflicts. VSD treats "value tensions" as a balance. VBE draws on Scheler's value *hierarchy* instead. (2020, §4.1.3)

**Winkler's thesis (2023) — the closest thing to a balanced comparison, though written inside Spiekermann's group:**

- IEEE 7000 has "a more explicit ethical foundation," and is "a more cohesive or streamlined framework."
- VSD is "much more flexible and open to incorporating methodologies from other fields." He judges that "when it comes to industry implementation, VSDs could have an edge."
- "There is no known attempt to apply IEEE Std. 7000 to agile development practices, which do exist for VSD."
- Strengths of IEEE 7000 relative to VSD:
  - It "provides a process to ensure transparency and traceability … while VSD is surprisingly vague."
  - It "provides a fairly clear idea of organizational conditions and required competencies, while VSD remains vague."

**Other comparisons:**

- The Delft Design for Values Institute presents VBE as a practical, standardized way to put Design for Values into practice (https://www.delftdesignforvalues.nl/2023/training-on-value-based-engineering-with-iso-iec-ieee-24748-7000/).
- **Not to be confused with "value engineering."** Wikipedia notes that traditional value engineering is about optimizing cost versus function, which is a different thing.

---

## 2. The process in detail

### Two vocabularies

There are two closely related descriptions of the process:

- **(a) The normative IEEE 7000 clauses.** These are four primary processes plus Transparency Management (clauses 7–11).
- **(b) Spiekermann's VBE presentation.** Three phases with sub-steps, plus parallel activities.

They map onto each other as follows (launch slides; Wikipedia; vbe.academy method page https://vbe.academy/value-based-engineering/):

| VBE phase (Spiekermann) | Sub-steps (slides) | IEEE 7000 clause |
|---|---|---|
| 1. Concept & Context Exploration | SOI context, SoS analysis, stakeholder analysis, external partner analysis | Cl. 7: ConOps and Context Exploration Process |
| 2. Value Exploration | Value elicitation and clustering, core value prioritization, conceptual analysis | Cl. 8: Ethical Values Elicitation and Prioritization Process |
| 3. Ethically Aligned Design | EVR identification, then either simple risk-based system design or impact-assessment-led system design, then system development and launch | Cl. 9: Ethical Requirements Definition; Cl. 10: Ethical Risk-Based Design |
| Parallel throughout | Transparency management, stakeholder management, top-management involvement, value-driven continuous monitoring | Cl. 11: Transparency Management Process |

Other structural facts about the standard:

- **Each clause has the same shape:** Purpose, Outcomes, Activities and tasks, Inputs, Outputs (ISO preview TOC).
- **Annexes:**
  - A: mapping to 12207 and 15288
  - B: value concepts
  - C: ethical theories
  - D: legal, social and environmental feasibility
  - E: control in systems of systems
  - F: control over AI systems
  - G: typical ethical values, informative only
  - H: organizational-level values
  - I: Case for Ethics
- **Life cycle stance.** The standard "is compatible with many existing development practices, including iterative and incremental life-cycle models and agile methods" (cl. 1.4).

### Phase 1: Concept of Operations (ConOps) and Context Exploration (IEEE 7000 cl. 7)

**Activities (cl. 7.3):**
- Describe the context of the operations being replaced and the possible use contexts.
- Identify stakeholders. The list is long:
  - organizational representatives
  - a "diverse spectrum of stakeholders that are both critical and widely distributed across technical ability and ethical value orientation"
  - advocates for indirect stakeholders
  - social-context and technical experts
  - "stakeholder advocates selected in a transparent way"
  - end-users from the deployment regions
  - affected institutions
  - civil society and legal advocates
- Analyze technical and organizational control over the system and its system-of-systems (SoS): aggregate the SoS elements, identify their owners, analyze control, record the controls needed. A RACI matrix is suggested.
- Obtain access to the enabling systems.
- Gather social, legal and environmental feasibility information. Identify initial value harms and benefits.
- Represent the ConOps and resolve gaps between alternative ConOps.
- Decide whether ethical benefits and harms need further treatment. If control cannot be expected, the organization can rescope the work or terminate the project.

**Inputs (cl. 7.4):** a potential problem, an initial product idea, organizational ethical principles, an initial ConOps.

**Outputs (cl. 7.5):** context description; lists of stakeholders to consult and of direct and indirect affected stakeholders; refined SOI ConOps; outcomes of feasibility studies.

**VBE elaborations (Spiekermann & Winkler 2020, §3):**
- **Requirement 1:** embrace responsibility for the SoS ecosystem. Include at least all first-tier partners (Recommendation 1). Classify partners using the ISO 15288 SoS types (virtual, collaborative, acknowledged, directed). Seek "acknowledged" or "directed" partnerships that give access (Recommendation 2).
- **Requirement 2:** design with an extended group of direct and indirect stakeholder representatives. Include representatives from every deployment region (Recommendation 3).
- **Discourse conditions:** borrowed from Habermasian "ideal speech situations" — equal participation, freedom to question claims.
- **AI components.** The slides quote IEEE 7000 (Annex F): control over an AI service should be presumed only where there is "control over … the quality of the data used in the AI system; the selection processes feeding the AI; the algorithm design; the evolution of the AI's logic; and the best available techniques (BATs) for a sufficient level of transparency." (launch slides)
- **Scope.** The standard is "most applicable to organizations that are building a system for a known context." It "can be less usable for building a generic product … for which the deployment context is indefinite" (cl. 1.3–1.4).

### Phase 2: Ethical Values Elicitation and Prioritization (cl. 8)

**Purpose:** "to obtain and rank values and value demonstrators for approval by management and other stakeholders" (cl. 8.1).

**Elicitation through three ethical theories, plus a cultural fourth question:**

- The standard: "Consequences, virtues, and duties are identified with the help of ethical theories; specifically, utilitarianism, virtue ethics, and duty ethics, along with other culturally appropriate value systems or ethical theories" (cl. 1.4).
- The questions as VBE words them (Spiekermann & Winkler 2020, Requirement 5a):
  1. **Utilitarian:** "What are all thinkable positive and negative consequences you can envision from the system's use for direct and indirect stakeholders?"
  2. **Virtue ethics:** "What are the negative implications of the system for the character and/or personality of direct and indirect stakeholders––that is, which virtue, harms or vices could result from widespread use?"
  3. **Duty ethics:** "Which of the identified values and virtues would you consider as so important (in terms of your personal maxims) that you would want their protection to be recognized as a universal law?"
  4. **Requirement 5b:** a fourth question grounded in a culture-specific philosophical or spiritual framework of the deployment region.
- **The 2022 wording** frames the questions "if that system were used at scale" (arXiv 2207.07599). The 10 principles add: "consider monopoly scenarios" (https://www.wu.ac.at/value-based-engineering/principles/).
- **Requirement 6:** stakeholder representatives must "always name the values they care about when they describe an issue."

**Clustering:**
- The Value Lead (called the "value expert" in the 2020 paper) distills the raw material into core value clusters (Recommendation 9).
- One way is to count values that recur. But "a value expert should always trust his or her own judgment of relevance," then reconfirm with stakeholders (Recommendation 10).
- **Scale of the raw material in the telemedicine (TM) case:**
  - 467 positive and negative "value potentials" (214 negative, 253 positive) were distilled into 14 core value clusters.
  - Naming, refining and grouping them "took several days of analysis." (2020, §4.1.2)
- **Case-study totals from the slides:** digital toy 534 value ideas; Foodora delivery 263; telemedicine 467; UNICEF Yoma 56. The first three were mostly student-lab cases; TM was a real company.
- **Per stakeholder:** each stakeholder identified on average 16–19 values (2022).

**Prioritization:**
- Clusters are "presented to executives and stakeholder representatives to rank them." VBE "does not envision that core values will be pitted against each other. They will not be treated as trade-offs." (2022, citing IEEE 7000 p. 41)
- **The seven ranking criteria (IEEE 7000 p. 41, quoted in 2022):**
  1. Stakeholders agree the SOI is good for society and avoids unnecessary harm.
  2. The organization does not use people merely as a means.
  3. Leaders can accept responsibility for the priorities "according to their own personal maxims."
  4. The organization respects its own stated ethical principles.
  5. The organization can commit to the priorities in its business mission.
  6. "The environment is maximally preserved."
  7. Existing ethical guidelines are considered.
- **Three complementary analyses (2020, §4.1.3):** (i) resonance with the business mission; (ii) a duty-ethics check by leaders, who should "support only those core values … that they would want to become universal" (Recommendation 11); (iii) a check against corporate principles, law and human-rights agreements, which form "the outermost boundary condition" (Requirement 9).
- **Consent:** prioritization "should not be taken by top executives' 'brute force'" and needs "the true consent of the stakeholder representatives" (Recommendation 12).
- **Option not to invest:** "This active consideration to not invest in a SOI on ethical grounds must be seen as a critical part of Value-based Engineering" (Requirement 10).
- **Public statement:** a signed "public ethical mission statement" (Recommendation 13). Wikipedia calls this the "Ethical Policy Statement."

**Conceptual analysis:**
- After elicitation, value qualities are completed "in line with the law and the philosophical literature." For example, privacy qualities are completed from the GDPR (Requirement 11; 2022 Fig. 2).

**Outputs (cl. 8.5):**
- "Value Register or case for ethics with selected and prioritized value clusters, core values, and value demonstrators"
- risks and improvements per value cluster
- ConOps updates
- an updated stakeholder list

### The value ontology (terminology used throughout)

The ontology has three layers, derived from Max Scheler (2022, Fig. 1; 2020 §3.4):

- **Core value.** "a high intrinsic value 'that is identified as central in the context of a SOI'"
- **Value quality,** called a **value demonstrator** in IEEE 7000. "a potential manifestation of a core value, which is either instrumental to the core value or undermines it"
- **Value disposition.** "system characteristic that is an enabler or inhibitor for one or more values." The SOI is then a **value bearer**.

Key points:
- "Value dispositions can be built into an SOI, while core values and value qualities cannot." Systems "'bear' or 'carry'" values rather than "have" them (2020).
- Engineering example (2020): security (core value) → confidentiality, integrity, availability (value qualities) → encryption (value disposition).

### Phase 3a: Ethical Requirements Definition (cl. 9)

**EVR definition (IEEE 7000 p. 18, quoted in 2022):** "organizational or technical requirement catering to values that stakeholders and conceptual value analysis identified as relevant for the SOI." An EVR is the "bridge" between values and system requirements. The 2020 paper calls them "Ethical Value Quality Requirements."

**Mechanics:**
- Each (core value, value quality) pair yields one or more EVRs (Requirement 12).
- EVRs carry qualifiers and, ideally, "concrete, quantified and testable thresholds" usable "for certification and testing" (2022; Recommendation 14b).
- **Example EVR:** "Ensure that a user can give consent to his/her data processing in an easy and informed way, whereby 'informed' means that the information provided is instantly accessible and comprehensible for laypeople." (2022)
- **Many EVRs are organizational, not technical.** For the retailer's indoor-tracking app, "one indispensable measure … is to hire sufficient staff to deal with customer help-calls." In the TM case, none of the five example EVRs under "equality" were technical. (2022; 2020 §4.2)
- **Traceability.** The chain core value → value quality → EVR → threat → control is recorded "through a numbered chain documented in the Value Register" (2022).

**Outputs (cl. 9.5):** EVRs and value-based system requirements traceable to prioritized core values; risks and opportunities for each EVR; ConOps improvement ideas; an updated Value Register or Case for Ethics with full traceability.

### Phase 3b: Ethical Risk-Based Design (cl. 10)

**Purpose:** "to realize ethical values and required functionality in the system or software design," with controls that mitigate risks to EVRs (cl. 10.1). Controls "are system requirements or organizational policies and procedures" (cl. 1.4).

**VBE adds three paths (2022 Fig. 4; 2020 §4.2):**

- **Path I — organizational.** EVRs met by management action alone.
- **Path II — "Standard Risk-based Design" / low-risk.** "asks how each EVR could be put at risk of not being fulfilled." Threats are met with "controls." The 2020 paper recommends four activities:
  1. indirect-stakeholder personas (Recommendation 15)
  2. a light risk logic (Recommendation 16)
  3. a "holistic prototype" that merges value-risk-control requirements with functional requirements (Requirement 14)
  4. a "first viable product" from Design Thinking, with continuous stakeholder feedback (Recommendation 17)
- **Path III — "Impact assessment-led" / high-risk.** Required "when particularly critical values are at stake (such as health or security), when particularly risky systems are built or when the regulator mandates" it. Also required where harm to "life or health" is reasonably likely (Requirement 13). Steps:
  - Determine the protection demand: "What would happen if … the EVR was not met?"
  - Analyze threats. For social values, "it suffices to judge whether a threat to an EVR is realistic or not."
  - Choose controls proportionate to the protection demand.
  - Document the residual risk.
  - The model is BSI IT-Grundschutz / NIST-style security risk analysis.
- **Why risk framing:** "by conceiving of values as 'being-at-risk,' development teams are put into a spirit of care" (2022).
- **The agile path in Spiekermann's words:** for values like "compassion" in a voice assistant, rigorous risk-driven design "seems literally like 'shooting methodical cannons at sparrows'." Instead, ordinary iterative and agile development is used, "ethically guided by EVRs," and before each sprint "EVRs have been run through a simple threat-control analysis" (ISTAS 2021).

**Outputs (cl. 10.5):** an ethically aligned design; a refined ConOps; an updated Value Register; an updated Case for Ethics.

### Transparency Management (cl. 11)

**Purpose:** "to share with internal and external, short-term, and long-term stakeholders sufficient and appropriate information about how the developer has addressed ethical concerns." It is "linked to accountability." Shared information "should include the roles and the affiliations of the people involved in the project decisions." It prefers "explainability" over raw transparency (cl. 11.1).

**Outputs (cl. 11.5):** Value Register; Case for Ethics (contents in Annex I).

**VBE elaborations (2020 §4.3):**
- The register should record the clusters, the priorities, the stakeholders involved and "their agreements and disagreements," plus "names and personal signatures" of the executives who endorse priorities (Recommendation 19).
- Engineers sign off on the risk levels and controls they choose (Recommendation 20).
- The rationale: "the power of the performative act that is putting one's good name on the line … When no one wants to put down his or her name for a system design choice … this is also a good indicator … for rethinking."

### Roles (IEEE 7000 cl. 6.2)

| Role | Main responsibilities |
|---|---|
| **Top Management Champion** | Sets strategic policy and resolves value-priority conflicts. "In the case of a Very Small Entity, the role … may be filled by the entity's owner." |
| **System Expert** | Develops the system requirements that enable EVRs. "Listens to stakeholders … rather than jumping to a readily available technical solution." |
| **Value Lead** | "focuses on the identification, analysis, and prioritization of ethical values." Is "not 'the person in charge of ethics' … but contributes subject matter expertise and facilitative skills." Organizes and records value work, facilitates, "builds compromises through practices like participatory design." |
| **Risk Lead** | Identifies, evaluates and treats risks to values, EVRs and dispositions. |
| **User Advocate** | "Represents stakeholder groups that cannot be directly involved." Advocates reducing impacts on indirect stakeholders. |
| **Senior Product Manager** | Applies market and context knowledge to value-based ConOps and design decisions. |
| **Moderator** | Runs stakeholder meetings so that no one person dominates; mediates toward consensus. |
| **Transparency Manager** | Records decisions and who is accountable; "Maintains the Case for Ethics." |

**Combining roles (cl. 6.1):** "The roles may be combined and delivered by one person … There are no requirements for independence of roles … Nothing in this standard … should be understood to require or even suggest the need for a group of specialists whose workflow is separate from the organization's chosen engineering workflow."

**What a Value Lead needs (Spiekermann & Winkler 2022):** "substantial ethical knowledge," knowledge of widely accepted value principles, and enough understanding of "Material Value Ethics and moral philosophy." Value Leads "must ensure that organizations are not primed by any existing value-principle lists."

**The 2020 paper on staffing this role:**
- It is "a new kind of employee."
- It should ideally be permanently embedded — "someone who has the longer-term 'power user,' 'scrum master' or 'system engineering' role" — not an outside consultant.

### Artifact summary

| Step | Artifacts (source) |
|---|---|
| Concept and context | Context description; stakeholder lists (direct, indirect, to consult); SoS control analysis and RACI; feasibility-study outcomes (legal, social, environmental); refined ConOps (cl. 7.5). Wikipedia: "Stakeholder Register." |
| Value exploration | Value Register / Case for Ethics with prioritized value clusters, core values and value demonstrators; risk and improvement list; ConOps updates (cl. 8.5). Signed ethical mission statement (VBE Recommendation 13). |
| Requirements | EVRs and value-based system requirements with traceability; updated Value Register (cl. 9.5). |
| Risk-based design | Ethically aligned design; threat and control analysis; residual-risk record; updated Value Register and Case for Ethics (cl. 10.5). |
| Transparency | Value Register; Case for Ethics (cl. 11.5). |
| VBE Academy tool kit | Stakeholder Mapping Canvas, Stakeholder Workshop Guide, Value Language Cards, Value-Related Risk Overview, Impact & Context Mapping, Value Register, EVR Starter Template (https://vbe.academy/value-based-engineering/). Contents not public. |

### Verification and monitoring

- **Thresholds.** EVR thresholds are used to "validate whether the system lives up to the EVRs" (2020 Recommendation 14b). "As EVRs are instantiated in the system design, the value dispositions are validated" (cl. 1.4).
- **After launch (2022):**
  - The register "records whether the system's validation period confirmed value creation and/or effective value breach prohibition."
  - "When value qualities don't actualize as planned or unexpected ones appear," a new EVR analysis is triggered.
  - Feedback cycles after launch are Requirement 8 in the 2020 paper.
- **Reiteration.** The standard ties reiteration to "performance monitoring and maintenance" and to "adverse user or operator feedback" (cl. 5.7 end).
- **Measuring "ethicality" (2020 §5.5).** The authors concede it is "hard to prove at the end of a project that the value mission … has actually been achieved."
  - They recommend "narratives and experiences."
  - They propose an "ethical maturity" level based on how many core value clusters are addressed.
  - "The documentation in the Ethical Value Register is the objective proof of that intent."

---

## 3. The ethical theory underneath

### Material value ethics (Scheler, Hartmann)

- **The core ontology comes from Max Scheler.** "It is derived from Max Scheler's opus magnum, 'Formalism in Ethics and Non-formal Ethics of Values'… It considers everything surrounding us––other people, nature, technology, relationships, or activities––as potential carriers of value." (2022)
- **The launch slides** say it plainly: "IEEE 7000TM has a built-in value ontology taken from Scheler's Material Value Ethics."
- **Hartmann appears in the references.** The 2020 paper cites Nicolai Hartmann's *Ethik* and Eugene Kelly's *Material Ethics of Value: Max Scheler and Nicolai Hartmann*.
- **Act-related value.** It uses Hartmann's "act related value" to argue that engineers' documented effort can itself be called ethical (2020 §5.5).
- **Barford (2021).** Lee Barford's paper in IEEE Technology & Society 40(3), pp. 42–49, states that IEEE P7000 "explicitly adopts Material Value Ethics (MVE) as its axiology" (https://www.researchgate.net/publication/354328378_Material_Value_Ethics_in_a_Model_Process_for_Values-Based_Design).
- **Value feelings.** Stakeholders reach values through "value feelings" (Scheler's term). Feelings alone are "not enough to fully conceptualize a core value," which is why conceptual analysis follows (2022).
- **Value hierarchy (2020 §4.1.3):** "Material value ethics does not emphasize the conflict among values, but rather sees them being in a natural hierarchy. It claims that ethical behavior is constituted by choosing and realizing higher values over lower ones."
  - Scheler's ranking criteria: relative endurance, depth, indivisibility, independence from value-bearers and degree of intrinsic value.
  - Worked example: "Efficiency, however, is a lower value than respect."
- **Bias toward the positive.** VBE "develops positive, value-rich visions" and "embeds positive psychology" (2022). It aims at "the good," not just avoiding harm.
- **WU's framing:** "While rooted in virtue ethics, it incorporates multiple ethical frameworks" (https://www.wu.ac.at/en/information-systems-and-society/projects/ieee-p7000-standard).

### Pluralist elicitation

- **Theories used:** utilitarianism (Mill), virtue ethics (Aristotle) and duty ethics (Kant), plus Habermas's discourse ethics for the stakeholder dialogue (2022 references).
- **Answer to the "Western canon" objection (2020 §4.1.1).** Virtue ethics has counterparts in other traditions — the Confucian *junzi* and Buddhist *śīla* — and Requirement 5b adds a culture-specific question.
- **What the empirical studies found:**
  - The utilitarian question yields the most ideas.
  - Virtue ethics yields the most original ones, on character and relationships.
  - Deontology gives the "most critical perspective," but tends to bring back "mainstream" values such as privacy.
  - Sources: 2020 §4.1.1; Bednar & Spiekermann ST&HV and BISE 2023.

### How values are prioritized (summary)

1. Executives and stakeholder representatives rank the core value clusters against the seven IEEE 7000 criteria. Two of these are Kantian: not using people merely as means, and leaders' own maxims.
2. They check the clusters against the business mission, against corporate principles, and against law and human rights. Law and human rights act as hard boundaries, so legally protected values such as privacy can be moved up "to ensure the system's compliance" (2022).
3. Scheler's hierarchy guides the choice of "higher" values over "lower" ones.
4. There is no explicit trade-off calculus. Winkler: "IEEE Std. 7000 … considers all values to be equally important and merely sets development priorities based on seven ethical criteria … which does not regard that values can be in conflict with each other, practice must show whether it is possible to develop a successful system in this way" (thesis p. 146).

---

## 4. Compliance and certification

### What can be certified

**Persons only (Austrian Standards P90 scheme):**
- The scheme certifies "ausschließlich die Kompetenz natürlicher Personen" — only the competence of natural persons — under ISO/IEC 17024.
- The title is "Certified Value-based Engineering Ambassador (VbE-A)" "for Ethical IS & AI."
- **Competences tested:**
  - the content of 24748-7000
  - value terminology and prioritization mechanisms
  - ConOps per ISO/IEC/IEEE 29148
  - contributing to a Value Register
  - VBE as a risk-assessment method
  - basic knowledge of ISO/IEC 42001 and how it relates to 24748-7000
- **Exam:**
  - 30 multiple-choice questions in 60 minutes; 15 of them on a case.
  - Open book, internet allowed.
  - Pass mark 60% (108 of 180 points).
- **Prerequisites:** 24 hours of training or one year of relevant experience.
- **Validity:** 3 years. Recertification needs 24 hours of further training plus evidence of continued relevant activity.
- Source: P90 PDF.

**Cost:**
- Exam only: €490 excl. VAT (€588 incl.). Recertification: €289 excl. VAT (https://www.austrian-standards.at/en/products-solutions/apply-standards/certification/personal-certification/vbe-ambassador).
- Course and certification bundle at Austrian Standards: €2,949 excl. VAT (€3,538.80 incl.). 4 days, hybrid, taught in German by Mario Tokarz (https://www.austrian-standards.at/en/shop/academy/certified-value-based-engineering-ambassador-nach-iso-iec-ieee-24748-7000~p5063365).
- VBE Academy's 3.5-day Ambassador training (English and German sessions in late 2026): price "on request." It includes the De Gruyter handbook and "200+ PowerPoint slides and implementation tools" (https://vbe.academy/academy/ambassador-training/).
- VBE Academy also offers a 1-day intro (price on request) and a "Certified Digital Humanism Professional" pathway (https://vbe.academy/).

**Recognition:** Austrian Standards' VbE-A certification took second place in a Digital Humanism award, 21 Jan 2025 (https://www.cencenelec.eu/news-events/news/2025/newsletter/ots-59-austrian-standards/).

**Systems and organizations: conformance is a claim, not a third-party certification:**
- "Conformance to this standard can be achieved in two ways: a) conformance to outcomes … b) conformance to tasks" (cl. 4). An organization can also claim both.
- "IEEE Standards cannot guarantee or ensure ethical system design, and conformance … does not imply conformance with any particular ethical principles or value system" (cl. 4).
- "The use of IEEE Std 7000 cannot guarantee that the system as designed and subsequently built is ethical, because the ethicality achieved … depends on the moral capabilities and choices of those who use the standard" (cl. 1.3).
- The standard does make value choices transparent "to auditors, potential certifiers, or governmental agencies" (cl. 1.3).
- I found no organizational or system certification scheme for 24748-7000. arc42's quality page says the same: "conformance appears process-based rather than third-party certified" (https://quality.arc42.org/standards/ieee-7000).
- **[Interpretation]** IEEE CertifAIEd is a separate IEEE AI-ethics mark (https://standards.ieee.org/products-programs/icap/ieee-certifaied/). It should not be conflated with IEEE 7000 conformance.

**What an auditor would look at.** The sources point to the Value Register / Case for Ethics, with its numbered traceability from value to EVR to control, plus signatures and records of stakeholder involvement (2020 §4.3; cl. 11).

### Who it targets

- **The standard:** "all sizes and types of organizations (e.g., large, small, for profit, non-profit)." It names "small and innovative organizations" (Introduction; cl. 1.4).
- **The standard works best with these organizational conditions:**
  - readiness to include a wide group of stakeholders
  - an open, inclusive project culture
  - a commitment to quality
  - "a dedication to ethical values from the top"
  - "a commitment to allocate sufficient time and resources for ethical requirements definition" (Introduction)
- **VBE Academy's audiences:** corporate leaders, the public sector, developers and product teams, worker representatives and corporate compliance (https://vbe.academy/).
- **Published uses:** the City of Vienna (mein.wien platform); Austria's public employment service AMS (GPT-based "Berufsinfomat" counseling); UNICEF Yoma; a Viennese telemedicine start-up; ERP rollouts; defence (EDA white paper; Bundeswehr "Innere Führung" AI study).
  - Sources: vbe.academy insights posts; Wikipedia; https://vbe.academy/value-based-engineering/resources/

### Relation to the EU AI Act and other regulation

**VBE Academy's mapping (https://vbe.academy/insights/post/eu-ai-act-compliance-with-vbe/):**
- **Art. 9 (risk management):** teams "identify ethical risks to stakeholder values, assess likelihood and impact, design mitigations, and verify residual risk."
- **Art. 17 (QMS):** EVRs are "traceable, testable requirements."
- **Art. 27 (fundamental-rights impact assessment):** covered through stakeholder analysis and value exploration.
- It stresses VBE's "non-list approach."

**Madl, Bargu & Cuhadaroglu (2025), "Bridging Ethics and Regulation…":** make the same argument for high-risk and general-purpose AI (https://link.springer.com/chapter/10.1007/978-3-032-11108-1_15). All three authors are from Innovethic, a VBE consultancy.

**Spiekermann's own claim (launch slides):** "IEEE 7000TM can help companies to comply with the EU AI Regulation."

**The standard's disclaimer (front matter):** "Compliance with the provisions of any IEEE Standards document does not constitute compliance to any applicable regulatory requirements."

**[Interpretation]** As of this research, 24748-7000 is not among the CEN-CENELEC JTC 21 harmonised standards that give a presumption of conformity under the AI Act.
- Those are prEN 18286 (QMS) and prEN 18228 (risk management). Publication is expected in 2026 (https://labs.cloudsecurityalliance.org/research/csa-research-note-eu-ai-act-pren-18286-iso-42001-20260428-cs/; https://digital-strategy.ec.europa.eu/en/policies/ai-act-standardisation).
- So VBE's AI Act value is supporting evidence and method, not legal presumption.
- The compliance mappings above come from VBE vendors, not from regulators.

**ISO/IEC 42001:** the P90 scheme requires candidates to explain how 42001 (AI management system) relates to 24748-7000. arc42 frames 7000 as complementing 42001 and the NIST AI RMF.

---

## 5. Strengths and criticisms

### Strengths, as claimed by the sources

- **It bridges principles and practice.** It answers Mittelstadt's complaint that "the truly difficult part of ethics … is kicked down the road like the proverbial can," via EVRs and traceability (2022; ISTAS 2021).
- **It does not depend on value lists.** In a WU student exercise:
  - Students primed with a list of value principles fixated on privacy.
  - A control group that visited the store and talked to elderly customers found "helpfulness" was the core value.
  - Source: 2022; ISTAS 2021.
- **More ideas, and more harms found, in a classroom study (Bednar & Spiekermann, BISE 2023):**
  - Ethics-based planning produced "more and higher value principles … more diverse value classes … more original values."
  - The 2022 paper summarizes this as "10 times more value harm detection than in today's ordinary development approaches."
  - Sample: 71 IS master's students, each given about 6 hours of instruction on the ethical theories.
- **A coherent engineering backbone.** Winkler (thesis): IEEE 7000 provides "a logical chain of system requirements to values" and clear organizational conditions, where VSD is vague.
- **It changes products when applied early.**
  - UNICEF Yoma went from "an AI-driven talent calculation machine" to "a community platform for mutual and local support of African youth" (slides).
  - Yoma's CTO estimated an "80–85% change in terms of how you design a system" but would "definitely use it again" (2022).

### Criticisms and limitations

Most of these come from the VBE authors themselves. Independent critique specific to IEEE 7000 is thin; see the note at the end.

**1. Overhead, cost and time**
- "VbE requires … more time, more money, more cooperation and care for stakeholders" (ISTAS 2021).
- "Time must be taken to think about value requirements and risk management, and also to write the necessary documentation. This time often goes beyond the scope of tight budget plans" (2020 §5.1).
- "The documentation effort has of course the disadvantage of costing extra time and effort that is not en vogue in times of low-cost and agile system development" (2020 §4.3).
- In the TM case, clustering alone took "several days." Stakeholders may need "financial compensation" (2020 §5.2).
- **Brownfield use:** the organization "must be prepared to heavily invest … often requiring an adapted architecture" (2022).

**2. Timing and the readiness of leaders**
- The TM case: when VBE came "one year into the project," the CEO "did not want to hear" findings about doctor competition and distrust. He lost another year and eventually abandoned the ranking feature.
- Hence: "Value-based Engineering therefore seems to be advisable only in an early innovation phase" (2020 §5.4).
- "Investors need to be ready to give their money for the stakeholder 'good' and not every capital provider is likely to embrace this" (2022).

**3. Top-down dependence**
- The process needs a Top Management Champion. Executives rank the values and sign the priorities.
- The standard is "most effectively applied when organizational leaders and top management are involved" (Introduction).
- **[Interpretation]** This makes VBE strong where leaders are committed and weak where they are not. The criteria also rest heavily on leaders' "personal maxims," which places a lot of normative authority with management, even though Recommendation 12 asks for stakeholder consent.

**4. Who represents stakeholders**
- **Winkler (thesis):**
  - "IEEE Std. P7000 does not suggest a methodology for identifying these [stakeholders]."
  - "neither VSD nor IEEE Std. 7000 provide the theoretical foundation or methodology to meaningfully limit the number of stakeholders."
  - He warns against "overestimat[ing] the experts' findings," citing authority bias and the Dunning-Kruger effect, and prefers direct engagement to representation through personas.
- **The 2020 paper** concedes that the critical NGO-style stakeholders VBE wants "might not be so easily attracted and maintained."
- **Generic critique of ethics standardization (not specific to IEEE 7000):** it is "a technical discourse and tends to exclude non-expert stakeholders and the public at large" (search summary, PMC7618411; https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7618411/).

**5. Compliance capture and ethics-washing risk**
- The standard and its authors take care to say that conformance does not equal ethics (cl. 1.3, cl. 4).
- Spiekermann insists ethics "cannot be delegated or outsourced to any corporate niche function" such as compliance or CSR (ISTAS 2021).
- In the opposite direction, the 2020 paper notes that engineers already treat ethics "more as a compliance necessity than as a positive challenge."
- **Commercial positioning.** Austrian Standards and VBE Academy market VBE largely as a route to EU AI Act compliance and "audit readiness" (developer page: "products ready for scrutiny").
- **[Interpretation]** That positioning pulls toward the compliance framing the founders criticized.
- **Outcomes cannot be measured.** The authors admit the "positivist problem" (2020 §5.5). Winkler: "The inability to measure the claims made by VSD and IEEE Std. 7000 … is a gap that should be addressed."
- **No organizational certification exists**, so "conforming" is self-declared (cl. 4).
- A search summary of an IEEE 7000 explainer (sustainability-directory.com) raises the "risk that the process could be used to legitimize designs that meet procedural ethical checks but still perpetuate fundamentally unsustainable models." That is a secondary, non-academic source.

**6. Environmental blind spot**
- Bednar & Spiekermann (ST&HV): "all three ethical perspectives failed to inspire value ideas that relate to the natural environment … a combination of three ethical theories can still fail to see the most pressing value issue in a technology assessment study."
- The same study found "a focus on mainstream values and individual values."

**7. Philosophical contestability**
- **[Interpretation]** Scheler's objective value hierarchy (e.g., "efficiency is a lower value than respect") is a substantive and contestable position, not a neutral procedure.
- VSD treats tensions as balancing. Winkler notes the two "value flavors" drive "huge differences" in how values are prioritized and negotiated.

**8. Agile fit, as judged by outsiders**
- Kapferer, Stocker & Zimmermann (ISTAS 2024): process-centric initiatives such as IEEE 7000 "explain what should be done but not how to get there… A proactive, lightweight integration into existing agile practices, providing tangible on-the-job advice for developers … is missing."
- Winkler (2023) observed there was "no known attempt to apply IEEE Std. 7000 to agile development practices." The ESE project (2024) is a later response.

**9. Distributed architectures and control**
- IEEE 7000 needs partners "who are ready to give access to their systems, which is often not the case in today's highly distributed service architectures" (2022).
- Smaller companies "tend to copy requirements from established applications." Less than 30% of software is custom-built (2020 §5.3).

**10. Thin evidence base**
- Most evidence is from student labs and a handful of cases run by the creators.
- Winkler: case studies "only demonstrate applicability and rarely utilize the entirety of a framework," and even IEEE 7000 cases "do not use the full theoretical and methodological range."
- Bednar & Spiekermann acknowledge "a student sample is a potential weakness."
- Spiekermann & Winkler (2020): "Whether such an endeavor … can become successful is unknown… History will show."
- Practitioners report that "a marketplace of auditors and verification processes has yet to develop" (WRAL op-ed, May 2025; https://www.wral.com/business/technology/ethical-software-ai-standards-necessary-ieee-7000-may-2025/).

**Note on independent critique.** I found no peer-reviewed paper by authors outside the WU/IEEE 7000 circle that critiques IEEE 7000 or VBE specifically and in depth. The criticisms above are mostly self-critique, Winkler's internal comparative evaluation, the OST Switzerland agile group, and general critiques of ethics standardization. Bohr's IEEE Software lessons-learned piece (2025) is the most likely practitioner source, but it is paywalled and I could not read it.

---

## 6. Small teams, solo developers, education, and AI-assisted development

### Small teams and solo developers

- **The standard explicitly allows it:**
  - "organizations of all types and sizes, including small and innovative organizations" (cl. 1.4).
  - "In the case of a Very Small Entity, the role of the top-management champion may be filled by the entity's owner" (cl. 6.2.1).
  - "The roles may be combined and delivered by one person … There are no requirements for independence of roles" (cl. 6.1).
  - No separate specialist workflow is required (cl. 6.1).
  - **[Interpretation]** So a solo developer can formally hold every role. But the methodology's safeguards against bias — the Moderator, the User Advocate, stakeholder discourse, executive sign-off — all assume several people. For a solo developer, the stakeholder engagement and the external Value Lead perspective are what is hard to reproduce.
- **The VBE authors on small companies (2020 §5.3):**
  - TM had "only … a five-person budget" and depended on third-party video and cloud services it could not control.
  - "The ethical necessity to forgo data sharing agreements is not easy for such a small company."
  - VBE's demand for SoS control is harder for small teams that build on off-the-shelf services.
- **Lightweight entry points that exist:**
  - **VBE's own low-risk path:** EVRs plus a "light risk logic" before sprints, a "first viable product," and continuous stakeholder feedback (2020 §4.2.1; ISTAS 2021).
  - **ESE (Ethical Software Engineering)** by Zimmermann, Stocker and Kapferer at OST Switzerland: an open-source mapping of IEEE 7000 onto agile practices (https://github.com/ethical-se/ese-practices).
    - Practices: Story Valuation, which adds "individual, societal and environmental values to the business and user values in the 'so that' part of epics, user stories"; Ethical Review; value-enhanced Definition of Ready and Definition of Done; Value Retrospective.
    - Story Valuation "populates the Value Register and yields Ethical Value Requirements (EVRs)."
    - Published at ETHICOMP 2024 and ISTAS 2024.
    - A sibling project, Value-Driven Analysis and Design (VDAD), has a seven-step process (https://ethical-se.github.io/value-driven-analysis-and-design/).
  - **Wohlrab et al., PROFES 2024:** "value tactics" and traceability for value-aware software engineering (https://link.springer.com/chapter/10.1007/978-3-031-78386-9_27).
- **Cost of entry for an individual:**
  - The standard is free to download through IEEE GET.
  - Personal certification costs about €490 for the exam, or about €2,949 for course plus exam.
  - The book is published by De Gruyter (https://www.degruyter.com/document/isbn/9783110793383/html).

### Education and teaching VBE

- **WU Vienna** has used the method in teaching for years. "5 generations of WU students were involved in various case studies" (slides).
- **The BISE study protocol** is a ready-made teaching design:
  - roughly 6 hours of lectures on innovation planning and roadmapping, then a roadmap exercise
  - then a 6-hour introduction to the three ethical theories
  - then teams apply utilitarian, virtue and deontological analysis in that order, label the underlying values, and derive product characteristics
  - The order "was the result of two small pilot studies … utilitarianism triggers the highest number of ideas … while deontology provides the most critical perspective."
- **The book is a "De Gruyter Textbook"** (Amazon listing).
  - Chapters: 10 principles; what values are; the three phases; transparency; an epilogue, "dormant values versus gadgetism."
  - Appendix case study: **"the rate your teacher app."**
  - **[Interpretation]** That case is directly relevant for education-sector teaching.
- **Training formats:**
  - WU's 3.5-day "pioneer training" (March 2023; Delft DfV page).
  - VBE Academy's 1-day intro and 3.5-day Ambassador course.
  - VBE Academy's Digital Humanism Professional modules: computer ethics, and value principles and fundamental rights.
- **Gap:** "Although both VOFs recognize the importance of training, there does not appear to be a curriculum that enables SE teams to acquire the necessary competencies and skills" (Winkler 2023).
- **Videos:** VBE Academy lists free videos, including on the 10 principles and "What are values?" (https://vbe.academy/value-based-engineering/resources/).

### AI products and AI-assisted development

- **AI products:**
  - The standard is "applicable to all kinds of products and services, including artificial intelligence (AI) systems" (Introduction).
  - Example given: "an AI chat system that is employed in a specific use context, such as medical advice, teaching a language" (cl. 1.4).
  - Annex F sets out control conditions for AI components: data quality, data selection, algorithm design, evolution of the AI's logic, and best available transparency techniques.
  - **[Interpretation]** Teams building on third-party foundation models usually cannot claim control over most of these. Under VBE's "Ecosystem Responsibility" principle ("abstain from partnerships or external services over which they have no control and which they cannot access"), that is a significant tension.
- **The AMS Berufsinfomat case:** VBE's "value language" was applied to a GPT-based career-counseling chatbot, looking at "not only the functional values of the AI's (GPT-based) dialogues but also its social and ethical implications." Fairness and attentiveness were the emphasis (https://vbe.academy/insights/post/vbe-at-the-ams-berufsinfomat/). No timeline or EVR details are public.
- **AI-assisted development (AI coding agents writing the software):**
  - I found nothing from the VBE or IEEE 7000 community specifically on this.
  - The closest related work is Treude, Baltes & Cheong (May 2026), "Operationalizing Ethics for AI Agents: How Developers Encode Values into Repository Context Files" (https://arxiv.org/abs/2605.05584).
    - It finds developers writing fairness, accessibility, sustainability, tone and privacy directives into AGENTS.md-style files.
    - It calls these files "a governance layer within development workflows."
    - It does not mention IEEE 7000 or VBE.
  - **[Interpretation]** A Value Register and EVRs could be expressed as such repository context files, so an agent "sees" the EVRs. Nothing in the sources tests whether agents follow them. The paper itself lists that as an open question.

---

## Other sources consulted

- VBE Academy pages:
  - method: https://vbe.academy/value-based-engineering/
  - developers: https://vbe.academy/vbe-for/developers/ ("Surface risks early – when they're still easy to fix"; claims VBE works "without slowing you down")
  - Vienna case: https://vbe.academy/insights/post/value-based-engineering-workshop-with-the-city-of-vienna/ (a single workshop, values: fairness and equal access, transparency, privacy, accessibility, sustainability)
  - certification launch: https://vbe.academy/insights/post/austrian-standards-launches-first-european-certification-for-ethical-ai/
- WU 10 principles: https://www.wu.ac.at/value-based-engineering/principles/ — Ecosystem Responsibility, Stakeholder Inclusiveness, Context-Sensitivity, Value Identification with Moral Philosophy and/or Spiritual Tradition, Understanding Values at Depth, Leadership Engagement, Respect for Regional Laws and International Agreements, Willingness to Renounce Investment, Transparency of the Value Mission, Risk-based System Design.
- Spiekermann & Winkler TM case report (2019): https://vbe.academy/wp-content/uploads/2025/04/IEEEP7000TMCase_vs2_.pdf (downloaded, not analyzed in depth).
- Mökander et al., ethics-based auditing — "not … sufficient to guarantee morally good outcomes" (general, not specific to IEEE 7000): https://arxiv.org/pdf/2110.10980
