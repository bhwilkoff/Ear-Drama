# R3d: Student privacy, so schools can say yes

*Research only, 2026-11-21. No code changed. Drafts for the owner in
`docs/research/design/R3d-drafts/`.*

## §0. The request, and the short answer

The owner, 2026-11-21, verbatim: *"Can you conduct student data privacy and
other EdTech privacy policies and pledges. EdSurge, Digital Promise, and the
electronic frontier foundation would be a good place to start. We want this to
work for the vast majority of school districts, schools, teachers and
students. The only way to do this is to build upon the work of the teachers
and other advocacy groups that have already shown how to allow schools to
create such great works of art (ear dramas) without compromising student
privacy."*

**Short answer.**

1. **Ear Drama's design already does what most school privacy rules ask
   for**, and more than most classroom apps: no student accounts or emails,
   teacher-typed first names, voices that pass through the server to the
   teacher's device and are never stored on it, no ads, no analytics, no
   trackers, no profiles, no ratings of readers, and a test that keeps
   students' names off published items (`worker/test/seats.test.js`, "the
   item carries the teacher's chosen name and no seat's name").
2. **What blocks schools today is paperwork and three missing controls**, not
   the architecture: the privacy page says nothing about classes, students,
   shared plays, or schools; there is no written retention policy or security
   program (both required by the amended COPPA Rule since April 22, 2026);
   and a teacher **cannot delete a class or a production** (no route exists;
   only deleting the whole account removes them), nor export a class's data,
   and nothing ever expires a class.
3. **The Student Privacy Pledge is gone.** The Future of Privacy Forum retired
   it on April 25, 2025, with no successor
   (<https://fpf.org/student-privacy-pledge/>;
   <https://www.edsurge.com/news/2025-05-14-edtech-s-privacy-pledge-is-going-away-that-doesn-t-mean-student-data-is-safe>).
   The brief's suggested first step cannot be taken. FPF itself now points
   vendors to the **SDPC National Data Privacy Agreement (NDPA)** and its
   **Exhibit E general offer**, which is the one instrument that reaches most
   US districts at once, and costs a non-member vendor nothing to sign.
4. **Recommended order:** (a) publish the privacy policy, the "for schools"
   page, the data inventory, the retention policy and a security summary
   (drafts here); (b) build Delete class, a class end date, and teacher
   export; (c) sign the NDPA (standard v2) with a first district and offer
   Exhibit E through the SDPC registry; (d) ask Common Sense to evaluate;
   (e) a vulnerability disclosure policy (and optionally CISA's K-12 Secure by
   Design pledge); (f) skip paid certifications (1EdTech, iKeepSafe) unless a
   large district or state requires one.

Legend for this document: **Meets** = the code does it today; **Gap** = it
does not; **Paper** = only a document is missing.

---

## §1. What schools and districts actually require

### §1.1 The sources that set the bar

Laws: COPPA as amended (in force; compliance due April 22, 2026), FERPA's
school-official exception, PPRA, and state student privacy laws (SOPIPA in
California and its many copies; California AB 1584's contract terms; New York
Education Law 2-d; Illinois SOPPA; Connecticut; Colorado; Texas). Contracts:
the SDPC NDPA v2 and its Exhibit E. Voluntary bars: the retired Student
Privacy Pledge's commitments, Common Sense's rating questions, 1EdTech's
rubric, EFF's recommendations to companies. Details and citations in §2.

Two findings shape everything below:

- **A teacher's choice is not enough for under-13 consent.** The FTC's COPPA
  FAQ N.3 says the decision to authorize collection should be made by the
  school or district, not an individual teacher, and N.2 asks the operator to
  use a method reasonably calculated to make sure it really is the school
  consenting (<https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions>).
  The current design has the teacher confirm consent with an optional
  reference (`play_school_consents.reference`). That is the right shape, but
  the words must say the **school or district** authorized it, and an NDPA
  signed with the district is the strongest evidence we can hold (§4.3 U1).
- **Districts treat free, teacher-chosen tools as the risk**, and want a
  signed agreement first. PTAC: free services should go through the same
  approval as paid ones; a teacher picking from a district-approved list is
  the model case
  (<https://studentprivacy.ed.gov/sites/default/files/resource_document/file/Student%20Privacy%20and%20Online%20Educational%20Services%20%28February%202014%29_0.pdf>,
  pp. 8-10). EdSurge, 2025: "Teachers signing up for free products do not get
  reviewed" and "Get a data privacy agreement in advance"
  (<https://www.edsurge.com/news/2025-11-07-breaking-up-with-edtech-is-hard-to-do>).
  So Ear Drama should make the approved-list path easy (the for-schools page,
  the NDPA), not route around it.

### §1.2 The checklist

Synthesized across the sources above. **Meets** = the code does it today;
**Gap** = it does not; **Paper** = only a document is missing.

| # | Requirement | Where it comes from | Ear Drama |
|---|---|---|---|
| C1 | A clear, public privacy policy before any login, in plain language, with a privacy contact | COPPA 312.4; Common Sense Fail line; EFF; SOPPA "public disclosure"; Colorado § 108 plain-language description | **Paper/Gap.** A policy exists, but it is silent on classes, students, schools, and shared plays, and says recorded plays never leave the device (false once shared plays and classes run). Draft: `privacy-policy-draft.md` |
| C2 | Use student data only for school purposes; no sale, rent, or trade | SOPIPA; TX 32.152; CO § 109; Pledge; NDPA | **Meets.** No sale, no data partners, nothing to sell |
| C3 | Collect the minimum | COPPA 312.7; EFF; NDPA Exhibit B; UK Code std 8 | **Meets, unusually well.** No student account, email, birth date, photo, device id; seat = teacher-typed label; takes pass through (`play_class_seats`, `take-relay.js`) |
| C4 | No targeted advertising; no profiling except for school purposes | SOPIPA; TX; CO; Common Sense Pass; Pledge | **Meets.** No ads, no analytics, no profile; the reader is never rated or labeled (PLAYS-DESIGN §12.4) |
| C5 | Reasonable security; a written security program; NIST CSF for New York | COPPA 312.8(b) as amended; NY 8 NYCRR 121.9; SOPIPA; SOPPA | **Paper.** Safeguards exist (hashed keys and tokens, rate limits per seat, no audio at rest, tested deletion); the written program does not. Draft: `security-program-draft.md` |
| C6 | Under-13: school authorization only for the school's use, with full notice to the school, school can review and delete and stop collection; decided by the school or district | COPPA FAQ N.1 to N.3 | **Partly.** The Worker refuses student voices in an under-13 class until consent is recorded (`plays.js:841`, `school_consent_required`), and under-13 work never publishes. **Gaps:** no policy version set; the confirmation must name the school or district; no delete-class route for "school can delete"; the notice to the school (for-schools page) does not exist |
| C7 | Publishing: nothing beyond school use for under-13; 13 and over with real consent | COPPA FAQ N.1 ("no other commercial purpose"); district media-release practice | **Meets for under-13** (no Publish). **Conflict for 13+ classes:** the teacher consents for seats (§12.11 item 6) where Decision 082 says each performer consents (§4.3 U3). Student names never reach archive.org (tested) |
| C8 | Delete on the school's request; the school can delete one student or all | SOPIPA; SOPPA; COPPA N.1; NDPA Exhibit D; AB 1584 | **Gap.** Teacher can remove a seat (`DELETE .../seats/:seat`) but **cannot delete a class or a production**; only deleting the whole account does |
| C9 | Written retention policy, posted in the notice; no indefinite keeping | COPPA 312.10 and 312.4(d) as amended; EFF; Colorado, Florida, Ohio deletion rules | **Gap.** No policy; classes, take details, and teacher notes never expire. Draft: `retention-policy-draft.md` |
| C10 | Delete or return data at the end of the contract or school year | AB 1584 item 7; Colorado; NDPA; EFF ("only while the student uses the service") | **Gap.** No end date; nothing expires a class |
| C11 | Return or export data to the school; students keep control of content they create | AB 1584 items 1-2; NDPA Exhibit D | **Partly.** Recordings are on the teacher's device; personal export exists (`docs/EXPORT.md`); **no class export** of roster, casting, notes |
| C12 | Parent and eligible-student access and correction, through the school | FERPA; AB 1584 item 4; NY Parents' Bill of Rights | **Partly.** The teacher sees and can rename or remove a seat; **no written process** for a parent who writes to us |
| C13 | FERPA school-official terms: the school's direct control over use and keeping | 34 CFR 99.31(a)(1)(i)(B); PTAC | **Paper.** The design fits (the teacher controls everything; no roster import), but nothing states it. Note PTAC: a service where students do not log in individually may not touch education records at all |
| C14 | List of subprocessors and third parties, kept current | SOPPA § 15; NDPA; COPPA 312.4 | **Paper.** Listed in `data-inventory.md` §3 |
| C15 | No third-party tracking or behavioral advertising | Common Sense; EFF; Pledge | **Meets, without a check.** No analytics; `PrivacyInfo.xcprivacy` declares no tracking and no collected data; web loads only sign-in scripts on demand, plus the ONNX runtime from jsDelivr for stand-in voices (`js/kokoro-worker.js:12`) |
| C16 | Breach notice to the school within a set time | NY 121.10 (7 days); IL SOPPA (30 days); NDPA; AB 1584 | **Paper.** No process. Proposed: 72 hours, one promise stricter than every state |
| C17 | No change to student data use without notice and agreement | Pledge; NDPA; AB 1584 | **Paper.** In the drafts |
| C18 | A signed agreement before student data flows (click-wrap often counts) | CT § 10-234bb; IL SOPPA; NY 2-d; CA AB 1584 | **Gap.** No agreement offered. NDPA (§3) |
| C19 | No biometric identifiers (voiceprints) | COPPA 312.2 item 10; BIPA; Texas CUBI; Washington | **Meets.** Audio is recorded and relayed only; nothing measures or matches a voice (§2.4) |
| C20 | Accessible notices | EFF (plain language); WCAG; UK Code std 4 | **Paper.** Drafts measured at about grade 4 to 5 |
| C21 | Age screen where a general service has a child-directed part | COPPA "mixed audience" definition, codified 2025 | **Open.** No age question at sign-in (§4.3 U4) |

---

## §2. Research

Web research on 2026-11-21. Several official state pages refused automated
fetches; where a mirror was used it is named. Analysis that is ours, not a
source's, is marked "Analysis". None of this is legal advice; the owner may
want a lawyer to read §2.1 and §4.3 before an under-13 class opens.

### §2.1 COPPA as amended (16 CFR Part 312)

- **Dates.** Published April 22, 2025; effective June 23, 2025; compliance by
  April 22, 2026, so it is fully in force now
  (<https://www.govinfo.gov/content/pkg/FR-2025-04-22/html/2025-05904.htm>).
- **Personal information** has included "a photograph, video, or audio file
  where such file contains a child's image or voice" since 2013 (FTC FAQ:
  <https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions>).
  The 2025 rule adds "a biometric identifier that can be used for the
  automated or semi-automated recognition of an individual"; the FTC dropped
  the proposed words "data derived from voice data" (Federal Register,
  p. 16927). A first name alone is not listed.
- **Written security program (312.8(b)):** a designated coordinator, an
  annual risk assessment, safeguards for the risks found, regular testing and
  monitoring, and an annual evaluation.
- **Written retention policy (312.10):** keep only as long as reasonably
  necessary for the purpose collected, never indefinitely; the policy states
  the purposes, the business need, and a deletion timeframe, and **312.4(d)
  puts it in the online notice**
  (<https://www.venable.com/insights/publications/2025/01/ftc-finalizes-coppa-rule-changes-in-the-biden>).
- **Separate consent for disclosure to third parties (312.5(a)(2))**, unless
  integral to the service
  (<https://www.skadden.com/insights/publications/2025/01/ftc-finalizes-long-awaited-child-online-privacy>).
  Analysis: relaying a student's take to their own teacher is the service
  itself, not a third-party disclosure; publishing to archive.org would be,
  which is one more reason under-13 work never publishes.
- **The audio exception is now in the rule (312.5(c)(9)) and is narrow**:
  audio with no other personal information, used only to answer the child's
  own request, and deleted immediately
  (2017 policy it replaced: <https://www.ftc.gov/news-events/news/press-releases/2017/10/ftc-provides-additional-guidance-coppa-voice-recordings>).
  Analysis: a performance relayed to a teacher and kept on the teacher's
  device is not covered. Under-13 class takes need school authorization.
- **School authorization was not codified.** The FTC declined to finalize
  its proposed ed tech provisions (Federal Register p. 16918), so FAQ Section
  N still governs: a school may consent in place of parents only for "the use
  and benefit of the school, and for no other commercial purpose"; the
  operator gives the school full notice, describes the data on request, lets
  the school review and delete a child's data and stop collection (N.1);
  the method must be reasonably calculated to make sure it is the school
  (N.2); the school or district, not an individual teacher, should decide
  (N.3) (<https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions>).
- **Mixed audience** now has its own definition: a service directed to
  children that does not target them as its primary audience may screen age
  neutrally before collecting personal information, and apply COPPA to those
  under 13 (<https://www.fenwick.com/insights/publications/coppas-coming-of-age-key-compliance-changes-in-ftcs-final-rule>;
  <https://www.wsgr.com/en/insights/new-federal-childrens-privacy-requirements-are-not-childs-play-ftc-amends-coppa-rule-imposing-new-obligations-on-child-directed-services.html>).
  Analysis: Ear Drama is a general listening app, but its under-13 class mode
  is plainly meant for children; whether that makes the app "mixed audience"
  is a question for counsel. The neutral age question in §4.3 U4 is cheap
  insurance either way.

### §2.2 FERPA and PPRA

- **School official** (34 CFR 99.31(a)(1)(i)(B)): an outside party may be one
  only if it does work the school would otherwise do, is under the school's
  direct control over use and maintenance of records, and follows the
  redisclosure limits (<https://www.law.cornell.edu/cfr/text/34/99.31>).
- **PTAC, "Protecting Student Privacy While Using Online Educational
  Services"** (2014;
  <https://studentprivacy.ed.gov/resources/protecting-student-privacy-while-using-online-educational-services-requirements-and-best>):
  whether FERPA applies "depends"; it protects information from education
  records, and a service where students do not log in individually may not
  involve FERPA at all. Directory information is often "insufficient" as a
  basis for a vendor. FERPA does not require a written agreement, but direct
  control is shown in practice by a contract. Teachers should not bypass
  approval for free tools; picking from an approved list is the model.
  PTAC's model terms (<https://studentprivacy.ed.gov/resources/protecting-student-privacy-while-using-online-educational-services-model-terms-service>)
  are the checklist the for-schools draft follows.
- Analysis, unresolved: whether recordings kept on a teacher's device become
  education records "maintained" by the school. No guidance found. Either
  way, the school controls them, which is what FERPA cares about.
- **PPRA** governs surveys and information collected from students for
  marketing or sale (20 U.S.C. § 1232h). Ear Drama has neither; not
  triggered.

### §2.3 State laws

- **California SOPIPA** (Bus. & Prof. Code § 22584): covers operators of
  services designed, marketed, and primarily used for K-12; bans targeted
  ads, non-school profiles, sale, and most disclosure; requires reasonable
  security and deletion on the school's request; no contract needed
  (<https://california.public.law/codes/ca_bus_and_prof_code_section_22584>;
  <https://fpf.org/wp-content/uploads/2016/03/SOPIPA-At-a-Glance.pdf>).
  Whether a class mode inside a general app is covered is unsettled; meeting
  it costs Ear Drama nothing.
- **California AB 1584** (Ed. Code § 49073.1): district contracts must say
  records stay the district's; **pupils keep control of content they create
  and can move it to a personal account**; no other use; a parent review and
  correction route; security; breach notice; no keeping after the contract;
  FERPA compliance; no targeted ads
  (<https://www.leginfo.ca.gov/pub/13-14/bill/asm/ab_1551-1600/ab_1584_bill_20140929_chaptered.htm>).
- **New York Education Law 2-d and 8 NYCRR Part 121**: each contract carries
  the Parents' Bill of Rights with supplemental information, a data security
  and privacy plan, NIST Cybersecurity Framework alignment, and breach notice
  to the district within **7 calendar days** of discovery
  (<https://regulations.justia.com/states/new-york/title-8/chapter-ii/subchapter-e/part-121/section-121-10/>;
  <https://www.nysed.gov/sites/default/files/programs/data-privacy-security/final-pbor-guidance-for-schools-on-2.24.25.pdf>).
  Accepting online terms counts as a written agreement, paid or not
  (<https://ogs.ny.gov/system/files/documents/2022/05/2022-15-how-your-contract-can-meet-school-vendor-responsibilities-for-protecting-student-information.pdf>).
- **Illinois SOPPA** (105 ILCS 85, amended 2021): a written agreement before
  receiving data (click-wrap permitted) naming the data, services, and
  school-official status; breach notice no later than **30 calendar days**;
  a published list of third parties; schools publish operators, data
  elements, and breaches
  (<https://codes.findlaw.com/il/chapter-105-schools/il-st-sect-105-85-15/>;
  <https://ilga.gov/legislation/ilcs/documents/010500850K27.htm>).
- **Connecticut** (Conn. Gen. Stat. §§ 10-234aa to dd): a written contract
  whenever a board shares student data; click-wrap counts; signing a pledge
  without complying can be an unfair trade practice
  (<https://portal.ct.gov/-/media/DAS/CTEdTech/publications/2022/2-22-22_DAS_SDP_FAQ.pdf>).
- **Colorado** (C.R.S. 22-16-101 et seq.): providers publish a plain-language
  description of data and keep a security program; no sale, ads, or
  profiles; districts are urged to stop using "on-demand" providers (no
  contract) that break the rules
  (<https://colorado.public.law/statutes/crs_22-16-109>;
  <https://www.cde.state.co.us/dataprivacyandsecurity/crs22-16-101>).
- **Texas**: Ed. Code § 32.152 is SOPIPA-style
  (<https://texas.public.law/statutes/tex._educ._code_section_32.152>). The
  SCOPE Act (HB 18) reaches services with public or semi-public profiles and
  posts others can see, and exempts education operators; a class with no
  public profiles likely falls outside it
  (<https://capitol.texas.gov/tlodocs/88R/billtext/html/HB00018F.htm>).
- **How many states:** about 40 states had passed 124 student privacy laws by
  2018 (<https://fpf.org/wp-content/uploads/2018/03/Learning-From-the-Accidental-Consequences-of-Student-Data-Privacy-Laws-Market-Brief.pdf>);
  FPF's 2025 retirement note cites "more than 40" state laws
  (<https://fpf.org/student-privacy-pledge/>). No current count of SOPIPA
  copies alone was found.
- **Age-appropriate design codes:** California's was narrowed but still
  partly enjoined by the Ninth Circuit on March 12, 2026
  (<https://cdn.ca9.uscourts.gov/datastore/opinions/2026/03/12/25-2366.pdf>);
  Maryland's Kids Code survived a motion to dismiss on November 24, 2025 and
  is in force
  (<https://www2.mdd.uscourts.gov/Opinions/Opinions/Memorandum%20Opinion_NetChoice%20v.%20Brown%20(RDB-25-0322).pdf>).
  Their themes (high-privacy defaults, no dark patterns, data protection
  impact assessments) are already Ear Drama's defaults.

**One breach number for every state.** The deadlines run from 7 days (New
York) to 30 (Illinois), and the NDPA sets its own. A single promise of 72
hours to the school satisfies all of them and is easy to keep for a service
with almost nothing to breach.

### §2.4 Voice and biometric laws

- **Illinois BIPA** names "voiceprint". Courts and the Illinois Attorney
  General distinguish it from a recording: "a voiceprint, which is a record of
  mechanical measurement, is not the same as a simple recording of a voice"
  (*Carpenter v. McDonald's*, N.D. Ill. 2022,
  <https://caselaw.findlaw.com/court/us-dis-crt-n-d-ill-eas-div/2167709.html>).
  The Amazon Alexa cases turn on Voice ID creating voiceprints
  (<https://blogs.duanemorris.com/classactiondefense/2023/11/04/illinois-federal-court-allows-amazon-alexa-privacy-class-action-to-proceed/>).
- **Texas CUBI** also names voiceprints
  (<https://texas.public.law/statutes/tex._bus._&_com._code_section_503.001>);
  **Washington** expressly excludes audio recordings
  (<https://app.leg.wa.gov/RCW/default.aspx?cite=19.375.010>).
- Analysis: recording and relaying a take, with no speaker recognition and
  no voice measurement, is on the "simple recording" side in all three.
  Any future feature that analyzes a student's voice (speaker ID, voice
  cloning, speech-following) must be checked again first (§4.4 T5). Kokoro
  stand-ins synthesize from text and never model a person's voice
  (Decision 055).

### §2.5 International classrooms

- **GDPR Article 8**: where consent is the basis for a service offered
  directly to a child, the child must be 16 (member states may lower it to
  13) or a parent consents (<https://gdpr-info.eu/art-8-gdpr/>). A school's
  use usually rests on its public task, not the child's consent.
- **UK Children's Code** (15 standards, among them best interests, impact
  assessments, transparency, high-privacy defaults, data minimization, no
  nudges;
  <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/age-appropriate-design-a-code-of-practice-for-online-services/>).
  The ICO's edtech guidance says a provider acting only on a school's
  instructions is less likely to be in scope, but one that also serves
  consumers is
  (<https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/the-children-s-code-and-education-technologies-edtech/>).
  Ear Drama is both, so the code likely applies to it as a whole. Its
  practice already meets most standards; the missing one is a written data
  protection impact assessment, which the security program's risk
  assessment can grow into.

### §2.6 Advocates, pledges, and how teachers vet apps

- **EdSurge.** The Pledge's retirement (May 2025): more than 400 signers;
  40-plus state laws went further; critics said AI and surveillance are the
  real gaps
  (<https://www.edsurge.com/news/2025-05-14-edtech-s-privacy-pledge-is-going-away-that-doesn-t-mean-student-data-is-safe>).
  "Student privacy needs a reset" (2023): schools access 1,400-plus products a
  month; 96% of school apps shared data with third parties; districts read
  policies for omissions
  (<https://www.edsurge.com/news/2023-05-17-as-number-of-edtech-providers-grow-some-say-student-privacy-needs-a-reset>).
  "Breaking Up With Edtech Is Hard to Do" (2025): free teacher sign-ups go
  unreviewed; get a DPA in advance; districts struggle to confirm deletion;
  Florida and Ohio require deletion within 90 days
  (<https://www.edsurge.com/news/2025-11-07-breaking-up-with-edtech-is-hard-to-do>).
- **Digital Promise** offers product certifications (Research-Based Design,
  Learner Variability, Practitioner-Informed Design, Responsibly Designed AI
  and others) but **no privacy certification**; privacy appears only inside
  Responsibly Designed AI
  (<https://digitalpromise.org/product-certifications/what-are-product-certifications/>).
- **EFF**, *Spying on Students* (2017): companies should collect only what
  education needs, build no profiles, default to privacy, encrypt, keep data
  only while the student uses the service or as the school says, disclose
  every third party, and write a plain-language policy apart from the terms
  with a privacy contact; schools should seek parents' written consent rather
  than consenting for them, and not rely on pledges
  (<https://www.eff.org/wp/school-issued-devices-and-student-privacy>).
  EFF's critique of Pledge 2020: circular definitions, loopholes, and no one
  checking compliance
  (<https://www.eff.org/deeplinks/2021/09/fpfs-2020-student-privacy-pledge-new-pledge-similar-problems>).
  Its work against monitoring tools (GoGuardian, Gaggle, proctoring) is a
  reminder of what Ear Drama must never become: no listening to students
  beyond the line they chose to record
  (<https://eff.org/deeplinks/2023/10/how-goguardian-invades-student-privacy>).
- **Student Privacy Pledge** (FPF and SIIA, 2014; Pledge 2020 effective
  December 2020): **retired April 25, 2025**, no successor; FPF points
  vendors to CISA's K-12 Secure by Design pledge, the SDPC NDPA, and PRIVO
  (<https://fpf.org/student-privacy-pledge/>).
- **SDPC / A4L NDPA.** Built so vendors need not sign one-off contracts with
  13,000-plus districts; it overrides a vendor's terms on student data.
  Version 2 (2024; A4L currently links v2.2 Standard,
  <https://privacy.a4l.org/national-dpa/>). Exhibits: A products, B schedule of
  data (required or optional per element), D disposition, **E general offer**,
  F cybersecurity frameworks, G state terms, H modifications
  (<https://files.a4l.org/privacy/NDPA/NDPAv2_Usage_Guide_and_Development_Process.pdf>).
  Standard v2 makes Exhibit E mandatory; districts subscribe in the registry
  by clicking, which emails the vendor
  (<https://a4l.freshdesk.com/support/solutions/articles/103000315808-ndpa-v2-key-changes-from-ndpa-v1>;
  <https://files.a4l.org/privacy/SDPC_Training_Guides/TRAINING_GUIDE_Exhibit-Es.pdf>).
  A vendor need not be a member to sign (one party must be); 35 state
  alliances, districts in 41 states (<https://privacy.a4l.org/>).
- **Common Sense Privacy Program**: Fail if no detailed policy before login;
  Warning on any of six (sale, third-party marketing, personalized ads,
  commercial tracking, cross-site tracking, ad profiles); else Pass; a score
  from a 35-question basic evaluation
  (<https://privacy.commonsense.org/resource/rating-questions>;
  <https://privacy.commonsense.org/resource/evaluation-questions>).
- **1EdTech TrustEd Apps**: rubric review, members only
  (<https://www.1edtech.org/certification/data-privacy/faq>). **iKeepSafe**:
  FTC-approved COPPA safe harbor and California badge; prices unpublished
  (<https://ikeepsafe.org/certification/coppa/>).
- **FPF for teachers**: the *Educator's Guide to Student Privacy* (with
  ConnectSafely, updated 2026) with a checklist on approved tools and
  click-through terms
  (<https://fpf.org/resource/educators-guide-to-student-privacy/>).
- **How districts approve**: teacher requests flow through LearnPlatform
  (Instructure) approval chains (school, curriculum, then privacy and
  security), and staff search an approved list
  (<https://community.canvaslms.com/t5/The-Product-Blog/LearnPlatform-Release-Request-Workflows-Simplify-and-Standardize/ba-p/585329>;
  <https://instructure.com/resources/case-studies/district-49>). Many
  approved lists were vetted for teaching, not privacy
  (<https://edweek.org/technology/districts-take-note-privacy-is-rare-in-apps-used-in-schools/2023/07>),
  and a Utah investigation found 52% of apps with agreements collected data
  the agreement did not permit
  (<https://www.schools.utah.gov/studentdataprivacy/files/Utah%20EdTech%20App%20Data%20Collection%20and%20Sharing%20-%202023-25%20Investigation.pdf>).

### §2.7 How classroom voice and media apps handle it

What the teachers' tools already show, the precedent we build on:

| App | Student voice and content | Consent for under-13 | Retention | Agreements and badges |
|---|---|---|---|---|
| Seesaw | Collects camera and microphone content; private to the class by default; family sharing only if the school enables it | The school authorizes and can withdraw | Deleted within 60 days of a school request | NDPA, SOC 2, Common Sense, Pledge 2020 (<https://seesaw.com/childrens-privacy-policy/>; <https://seesaw.com/privacy/>) |
| Book Creator | Books private by default; only teachers share wider | School or teacher | May delete after 12 months idle, with notice | Common Sense Privacy Verified (<https://bookcreator.com/childrens-privacy-notice/>) |
| Soundtrap for Education | Audio projects | "Relies on the school" | Not confirmed | State agreements on the SDPC registry (<https://www.soundtrap.com/legal/privacy/edu>) |
| Canva for Education | Student designs; not used to train AI | School obtains parental consent | Published COPPA retention schedule | iKeepSafe COPPA and FERPA; NDPA (<https://www.canva.com/policies/coppa-retention-schedule>) |
| Adobe Express for Education | Schools manage and delete accounts; no ad profiles | School | School-managed | None named (<https://www.adobe.com/privacy/student-policy.html>) |
| Padlet | Backups 30 days; not used to train AI | School or teacher | | Common Sense Pass 90%; SDPC agreements (<https://legal.padlet.com/privacy>) |
| Flip (Microsoft) | Video responses | | **Shut down 2024**; content deleted after a download window | (<https://boisestate.edu/oit/2024/06/20/flip-unavailable-beginning-july-1>) |

The common pattern: private to the class by default, the school as the
consenting party, the teacher as the only one who shares wider, a published
retention schedule, deletion on the school's request, an NDPA. Ear Drama
matches the first three and goes further on storage (none of these keeps
nothing); it lacks the last three. Flip's shutdown is the case for an export
that lets a school leave with its students' work.

---

## §3. Pledges, agreements, and certifications: what to join, in what order

"The vast majority of school districts" decide in one of three ways (§2.6):
a teacher uses a free tool unreviewed; a district reviews the tool against
its approved list (often in LearnPlatform), which asks for a signed data
privacy agreement; or a state alliance's NDPA with Exhibit E lets a district
subscribe without negotiating. What reaches the most districts for the least
cost is therefore: honest public documents first, then the NDPA.

| # | Instrument | Cost | Effort | What it unlocks | Recommendation |
|---|---|---|---|---|---|
| 1 | **Published privacy policy, for-schools page, data inventory, retention policy, security summary** | $0 | Owner reads and approves the drafts here; a day of web work | Common Sense's Fail line is "no detailed privacy policy available before login" (<https://privacy.commonsense.org/resource/rating-questions>). Every reviewer reads these first. COPPA requires the notice and retention policy. Teachers can send a reviewer one link | **Do first.** Blocks everything else |
| 2 | **Delete class, class end date, teacher export** (§4) | build time | Worker routes + three clients | Every DPA's deletion and disposition terms (NDPA Exhibit D, Colorado, Florida and Ohio deletion rules, §2.6); FERPA's "direct control" | **Do before signing anything that promises deletion** |
| 3 | **SDPC National Data Privacy Agreement, Standard v2, with Exhibit E** | $0 for a non-member vendor; one signing party must be an A4L member (a district is); A4L membership optional and revenue-based (<https://a4l.freshdesk.com/support/solutions/articles/103000345212-do-i-have-to-be-a-member-of-the-a4l-community-to-sign-a-data-privacy-agreement-dpa->) | Read the 30-page agreement; fill Exhibit A (products), Exhibit B (data schedule: from `data-inventory.md`), Exhibit F (cybersecurity framework: NIST CSF), state Exhibit G; sign with an "originating" district; the registry then offers Exhibit E | Districts in 41 states through 35 state alliances (<https://privacy.a4l.org/>); any district in a state with a signed agreement can subscribe by clicking (<https://files.a4l.org/privacy/SDPC_Training_Guides/TRAINING_GUIDE_Exhibit-Es.pdf>). Satisfies most state-law contract requirements (CT, CA AB 1584, IL SOPPA, NY 2-d with the NY addendum) | **Do third.** The single highest-reach step. Start with the owner's own state, or with a district a teacher-champion is in |
| 4 | **Common Sense Privacy evaluation** | No vendor fee found; no public request route found (contact the program) | Answer their questions; their reviewers read the public policy | A rating teachers recognize; Pass needs no sale, no third-party marketing, no personalized ads, no commercial tracking, no cross-site tracking, no ad profiles (<https://privacy.commonsense.org/resource/rating-questions>), all of which Ear Drama meets. Feeds Privacy Direct, which districts use to compare (<https://www.commonsense.org/education/privacy-direct-details>) | **Do fourth**, after the policy is live |
| 5 | **Vulnerability disclosure policy** (`/.well-known/security.txt` and a page) | $0 | An hour | One of CISA's K-12 Secure by Design commitments; reviewers ask for it | **Do.** Optionally then sign CISA's K-12 Secure by Design pledge (voluntary, unverified; its SSO and audit-log items barely apply to an app with no student logins) (<https://cisa.gov/k-12-education-technology-secure-design-pledge>) |
| 6 | **Student Privacy Pledge** | n/a | n/a | Retired April 25, 2025; no successor; signatories told to remove references (<https://fpf.org/student-privacy-pledge/>) | **Not possible.** Publish its commitments as our own promises instead (the for-schools draft does) |
| 7 | **1EdTech TrustEd Apps Data Privacy Certification** | Members only; supplier dues by revenue, unpublished (<https://www.1edtech.org/certification/data-privacy/faq>) | Rubric review of policy and terms | Listing in the TrustEd Apps directory, seen by member institutions | **Skip unless a state or large district requires it** |
| 8 | **iKeepSafe (COPPA Safe Harbor, FERPA, California)** | Unpublished pricing (<https://ikeepsafe.org/certification/coppa/>) | Assessment and annual review | A badge; a COPPA safe harbor | **Skip for now.** Our under-13 path rests on school authorization and collects almost nothing; a safe harbor is the remedy for a much bigger collection |
| 9 | **Digital Promise Product Certifications** | A submission fee is intended; amount unpublished (<https://digitalpromise.org/wp-content/uploads/2024/11/2024-07-10-PCP-Policies-and-Procedures.docx-1.pdf>) | Evidence portfolio | **No privacy certification exists** (<https://digitalpromise.org/product-certifications/what-are-product-certifications/>). Learner Variability or Practitioner-Informed Design could fit Ear Drama's teaching design later | **Not a privacy step.** Revisit for the teaching case, with teachers' evidence |
| 10 | **PRIVO Student Digital Privacy Assured** | Paid | Assessment | FPF names it as one compliance option (<https://fpf.org/student-privacy-pledge/>) | Skip, as 8 |

**Why the NDPA over badges.** EdSurge's reporting is consistent: districts
read the policy for omissions and want a signed agreement in advance, and
badges multiply (ClassLink lists 17) without settling the contract question
(<https://www.edsurge.com/news/2023-05-17-as-number-of-edtech-providers-grow-some-say-student-privacy-needs-a-reset>;
<https://www.edsurge.com/news/2025-11-07-breaking-up-with-edtech-is-hard-to-do>).
Connecticut found the Pledge did not satisfy its written-agreement law
(<https://www.edsurge.com/news/2018-03-12-states-issue-privacy-ultimatums-to-education-technology-vendors>).
EFF's critique of the Pledge was that nothing checked compliance
(<https://www.eff.org/deeplinks/2021/09/fpfs-2020-student-privacy-pledge-new-pledge-similar-problems>);
a contract a district can enforce answers that.

**The cost of the NDPA we should name.** It binds the owner to deletion
timelines, breach notice, audits on request, and state exhibits. The
promises are easy for Ear Drama to keep only because it holds so little;
every future feature that collects more makes them heavier. That is a
feature: the agreement becomes a check on scope creep.

---

## §4. Design changes the research implies

Each change names the requirement it answers (§1.2 line numbers), the code it
touches, and the decision it rests on or strains. Sizes are rough. None is
built in this round; each goes through `feature-shipping-discipline` and the
binding design docs first.

### §4.1 Deletion, retention, and export (the real gaps)

| # | Change | Answers | Code | Decisions |
|---|---|---|---|---|
| D1 | **Delete class.** `DELETE /v1/plays/classes/:id` (teacher only). The schema already cascades seats, productions, assignments, takes' rows, reviews, and the school consent from `play_classes` (migrations 0003, 0007); the route is all that is missing. Clients: the class screen on web (`js/class-ui.js`), Apple, Android, with a confirmation that names what goes. On the teacher's device, offer to delete the class's received takes too | C8, C9, C10 | `worker/src/plays.js` router (only `members`, `blocks`, `invites`, `seats` have DELETE today, `plays.js:927-951`, `plays-seats.js:270`); a test that counts rows after | 082 ("deleted with the class") assumes a delete that does not exist |
| D2 | **Delete production** (director only), with 059/073's rule that a published item's lines stay on archive.org | C8 | `plays.js` | 066, 073 |
| D3 | **Class end date and inactivity expiry.** Add `ends_at` and `touched_at` to `play_classes`; `sweepPlays` deletes classes past `ends_at` or idle past the owner's limit; the teacher's app shows the date and, 30 days before, offers Export and Extend. We hold no teacher email, so the notice is in the app only, and the policy says so | C9, C10 (COPPA retention), NDPA Exhibit D | migration 0010, `plays.js` `sweepPlays` (today it sweeps only claims and invites, `plays.js:1011-1017`), three clients | New; numbers are the owner's (§7) |
| D4 | **Teacher's class export**: one file with the roster (seat labels), casting, reviews and notes, take details, and the recordings already on the teacher's device. Extends `docs/EXPORT.md`'s format with a `class` block | C11 (return of data at end; FERPA access requests answered by the school) | `js/export.js`, `DataExport.swift`, `DataExport.kt`; a Worker read of the class (exists: `GET /classes/:id`) | Human-Shaped principle 11 (EXPORT.md) |
| D5 | **Student takes on shared school devices.** Today a seat's takes stay on the device that recorded them (written first, 082). On a shared device, the next student can find the last student's voice. Proposal: a take the teacher's device has received is removed from a device that is not the student's own when the seat session ends; plus "Clear this device" in the seat screen | C5, C9 | web IndexedDB store, Apple and Android take stores | **Tension** with "students' work is theirs" (California AB 1584 asks that pupils keep control of content they create and can move it to a personal account, §2.3) and with the seat's own take choice (`/seat/productions/:pid/chosen`). A middle way: before clearing, offer the student "Save my takes" (a file through the share sheet). Owner decides (§7 Q6) |
| D6 | **Expiry for home-relay seat keys** in Keychain/Keystore (083): delete the key once no take waits, or after the class ends | C5 | `ReadSeatKeys` (Swift, Kotlin), web store | 083 (keeps the rule; adds an end) |
| D7 | **Reports close and fade.** Closed reports lose their note and reporter after a set time; the take-removed fact stays | C9 | `play_reports`, `sweepPlays` | 066 (guideline 1.2) |

### §4.2 Honesty of the published words (Paper, but urgent)

| # | Change | Why |
|---|---|---|
| P1 | **Replace `privacy/index.html`** with the approved policy. Today it says "Recorded plays stay on the device" and "A finished play leaves it only when you export it yourself"; with shared plays and classes live, both are false | C1; COPPA notice; Common Sense Fail line |
| P2 | **Fix "Delete an account removes everything the server holds."** As built, a submitted production's takes move to an anonymous `deleted-account` row and stay, and a report about the person keeps its trail with the name cleared (WORKER.md "Account deletion"). The draft says this plainly | C1, C8 |
| P3 | **Publish the subprocessor list** (data-inventory §3) | C14 |
| P4 | **Publish the retention policy** in the notice (COPPA 312.10 as amended) | C10 |
| P5 | **Set `SCHOOL_CONSENT_POLICY`** to the approved policy's version id, only after the policy is live; until then the Worker refuses school consent (`plays.js:841`), which is correct | C6; Decision 059's P5 |

### §4.3 Under-13 classes, publishing, and age

| # | Change | Answers | Decisions |
|---|---|---|---|
| U1 | **School authorization that the school makes.** FAQ N.3 says the school or district, not a teacher alone, should decide, and N.2 asks for a method reasonably calculated to confirm it (§2.1). Proposal: the teacher records consent by confirming, in the owner's words, that **their school or district has approved Ear Drama for this class**, and names the school or district (make `reference` required for under-13). Two strengths of evidence: (a) the district has signed or subscribed to our NDPA (we keep the list of signed districts; a match is the strongest proof); (b) otherwise the teacher's attestation, and the for-schools page as the notice to the school, with a contact for the school to confirm or withdraw. Withdrawal by the school deletes the class (needs D1) | C6, C13 | 059, 082. **Strains** R3c §4.7's "the teacher confirms they act for their school"; this asks a little more of the teacher |
| U2 | **A one-page note a teacher can send home** (owner's words, on the website, not in the app): what Ear Drama is, what it keeps, that under-13 work is never published, and who to ask. Many schools send families notice of tools; this makes the school's job easy | C6, C12 | AGENTS.md: no AI-written copy in the product, so the owner writes it |
| U3 | **13-and-over class publishing: whose consent.** Decision 082 says publish "after each performer's CC0 consent"; PLAYS-DESIGN §12.11 item 6 says "A class seat's take stays the teacher's, credited to the seat (the teacher consents)". A teacher cannot dedicate a 13-to-17-year-old's performance to the public domain on their behalf, and districts usually require a parent media release before student work is posted publicly (§2.6). Proposal: Publish on a class production asks the teacher to confirm that each student performer (and, for students under 18, a parent, by the school's own media release) agreed to publication under CC0. The names still never leave (the test holds) | C7, C13 | **Conflict** between 082 and §12.11; owner decides (§7 Q4) |
| U4 | **Age where an account starts.** There is no age question at sign-in; the only age line is in the CC0 consent ("You're 13 or older, or your teacher has recorded your school's consent"). Ear Drama is a general-audience app with a part (classes) meant for children, which the FTC calls "mixed audience": such a service may age-screen neutrally before collecting personal information from a user, and treat under-13 answers by the COPPA rules (§2.1). Sign-in collects only a provider id, but a signed-in person can then share takes and a chosen name. Proposal: a neutral age question (birth year, no default) before a first share or invite, not before listening; under 13 is pointed to their teacher's class | C6 | 057, 079 (sign-in stays optional; the question comes only where sharing begins) |
| U5 | **Adult read rooms** take a typed name and relay takes to the leader with no account. A child could join one. Keep: nothing is stored but the name for 6 hours, and a credited take cannot publish without its maker's own consent (083) | C6 | 082, 083 |

### §4.4 Third parties and checks that hold the line

| # | Change | Why |
|---|---|---|
| T1 | **Self-host the ONNX runtime** (`js/kokoro-worker.js:12` loads it from `cdn.jsdelivr.net`), so the web app talks to no third party a reviewer has to ask about. Small change; same file, our origin | C14, C15 |
| T2 | **A check for "no third-party trackers."** A test that every page and script on the web loads code only from our origin, plus Apple's and Google's sign-in scripts and the Cast receiver page. AGENTS.md asks each value rule to name its check; "no analytics, no trackers" has none today | C15 |
| T3 | **Confirm Workers Logs is off** in the Cloudflare dashboard (no `[observability]` in `wrangler.toml`), or set a short retention, and say so in the security program | C5 |
| T4 | **Inventory drift check.** A test that fails when a migration adds a column not named in the published data inventory (the account test already finds person columns from D1's foreign keys; extend it to a column list) | C3, C5 |
| T5 | **Never extract voiceprints.** Write it as a rule in PLAYS-DESIGN: no speaker identification, voice matching, or speech analysis of a student take. The out-of-scope "speech-following cursor" (SCRATCHPAD) would have processed student speech; it stays out for this reason too | C4 (biometric) |
| T6 | **Vulnerability disclosure**: `/.well-known/security.txt` and a page | §3 row 5 |

### §4.5 Accessibility of the notices

Plain language at about an 8th-grade level, short sections, a summary first,
tables for "what we keep", and the same words on the website and in the apps
(EFF asks for a plain-language policy separate from terms, a privacy contact,
and one place to find it all;
<https://www.eff.org/wp/school-issued-devices-and-student-privacy>). The
privacy page already meets WCAG text-spacing through the site's CSS. A
reading-level measure of the drafts is in §5.

---

## §5. The drafts

All in `docs/research/design/R3d-drafts/`, each marked DRAFT, each sentence
checked against the code on 2026-11-21. Brackets mark owner choices and
promises the code does not keep yet (BUILD); a BUILD sentence is removed, or
the feature built, before publishing.

| File | What | Reading level |
|---|---|---|
| `privacy-policy-draft.md` | The whole privacy policy, replacing `privacy/index.html` | About grade 4 to 5 (rough Flesch-Kincaid over body text, tables excluded; target was 8) |
| `for-schools-draft.md` | The "for schools" page and student data addendum: a one-minute teacher version, then the reviewer's version mapped to NDPA, COPPA, FERPA, state laws | About grade 5 by the same count |
| `data-inventory.md` | Every field that can describe a person: table and column, who, what, why, how long; device storage; third parties. The source for NDPA Exhibit B | Reference |
| `retention-policy-draft.md` | The written retention policy COPPA 312.10 now requires, to be posted with the notice | Plain |
| `security-program-draft.md` | The written information security program outline COPPA 312.8 now requires, aligned with NIST CSF for NY 2-d | Plain |

The drafts say what the code does. Where a promise depends on D1 to D7
(§4.1), it is bracketed BUILD. The consent text is quoted from
`GET /consent`, never rewritten.

---

## §6. The learning test

Run on the recommendations as a whole (`learning-orientation-design`).

**Should it exist?** Yes. Without published terms and a signable agreement,
the teachers the owner wants to reach either use Ear Drama unreviewed (EdSurge:
"Teachers signing up for free products do not get reviewed") or cannot use it
at all. The alternative, doing nothing, leaves the risk with the teacher.

**Who does it touch, outside the screen?** Parents, who never open the app
but whose children's voices pass through it; district privacy officers, who
carry the legal duty; students on shared devices, who meet the last student's
takes; and the owner, who signs promises that bind every future feature. The
strongest case against the NDPA, on their behalf: a contract can look like
safety while the practice drifts (Utah found 52% of apps with agreements
collected data the agreement did not allow:
<https://www.schools.utah.gov/studentdataprivacy/files/Utah%20EdTech%20App%20Data%20Collection%20and%20Sharing%20-%202023-25%20Investigation.pdf>).
The answer is T2 and T4: checks in the code that fail when the practice
leaves the paper.

**What will people learn, and stop learning?** Teachers keep the judging:
they cast, review, approve, keep, export, delete, and decide whether to
publish. Nothing here grades, ranks, or labels a reader. Students' work stays
theirs in the room (they choose which take is offered), and the one proposal
that takes something from them (D5, clearing a shared device) is put to the
owner rather than decided.

The four questions:

1. **Deepens understanding?** Yes, for teachers and families: the
   for-schools page and data inventory explain exactly what happens to a
   voice, in words a 13-year-old can read, so the people affected can judge
   for themselves.
2. **Invites participation?** Yes: the teacher, not the app, decides
   authorization, publishing, and deletion; parents have a named route
   (through the teacher, or to us).
3. **Supports human agency?** Yes: export and delete put the class's work in
   the teacher's hands, and a school can leave without losing it.
4. **Clarity over cleverness?** Yes: the strongest privacy feature is the one
   already built (keep nothing), and the recommendations add documents and
   three plain routes, not a compliance platform.

---

## §7. Owner decisions

Only what our rules and the research do not already decide.

| # | Decision | Recommended |
|---|---|---|
| Q1 | **Approve the drafts' words** (privacy policy, for-schools page, retention policy, security program), and the school-authorization words the teacher confirms (U1) | Edit freely; the structure is what reviewers look for |
| Q2 | **The legal entity and privacy contact.** The current page names Learning is Change, Inc. and ben@learningischange.com. Is that the signing entity for the NDPA, is it a nonprofit, what postal address goes on the policy, and should there be a dedicated privacy address? | Learning is Change, Inc.; a dedicated alias that reaches the owner |
| Q3 | **Retention numbers**: class end date (proposed July 31 each year, extendable), inactive class expiry (12 months), inactive account expiry (3 years), deletion on a school's request (30 days), school consent record kept 1 year after the class, closed report notes (1 year), breach notice to schools (72 hours) | As proposed: one strict set satisfies every state |
| Q4 | **13-and-over class publishing consent** (U3): keep the teacher's sole consent (§12.11), or require the teacher to confirm each performer's agreement and the school's media release for students under 18 | Require the confirmation; Decision 082 and §12.11 then agree |
| Q5 | **Offer the NDPA?** Sign NDPA Standard v2 with Exhibit E, starting with which state or district | Yes, starting where a teacher-champion is |
| Q6 | **Shared-device takes** (D5): remove a student's delivered takes from a shared device when the seat session ends, or keep them until the student deletes them | Remove on shared devices, keep on a student's own; "Clear this device" either way |
| Q7 | **Age question before a first share** (U4) | Yes, neutral birth year, only where sharing begins |
| Q8 | **Common Sense evaluation**: ask them to evaluate once the policy is live | Yes |
| Q9 | **A lawyer's read** of the under-13 path (§2.1, §4.3 U1, U4) and the NDPA before the first under-13 class opens or the first NDPA is signed | Yes, once; this research is not legal advice |
