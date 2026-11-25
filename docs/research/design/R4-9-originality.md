# R4-9: publishing a script you wrote (design, 2026-11-24)

A design and a measurement. Nothing in the product changed.

**The ask**, owner, 2026-11-24, verbatim: *"yes, we can accept new scripts but we
would have to make sure that they don't violate copyright (i.e., perform a title
and content search for existing plays)."* On the declaration: *"You should be able
to research the kind of wording we need ... I don't need to approve either of
those directly given their very specific scope."* Decision 088.5 sets the rest: 13
and over, never in a class, a search before anything uploads, a match goes to the
owner, finding nothing is recorded as what was searched and never as proof, and
the Worker refuses until a planted copy has been caught.

**In short.** The director agrees to a declaration. An hourly GitHub Actions job
reads that one script, compares it with 12,291 texts we hold, sends six short
phrases to the Internet Archive's full-text search, and looks up its title. Clear:
they may publish. Words found elsewhere: it waits for the owner. A title alone:
it asks the person one question. Copies are caught nearly always and unrelated
scripts almost never are; **an adaptation in new words is not caught at all**, and
a play that nobody scanned is not either (§2.5).

Measurement: `docs/research/data/r4-9/` (`fingerprint.py`, `measure.py`,
`report.py`, `results.txt`: counts only, no text). 55 requests went to public
search services, at 2 to 3 seconds apart.

---

## 0. A defect found first: the Workshop's text is already public

Our rule is that the Generic Radio Workshop's text is for "SEARCH and matching
only" (`catalog/tools/harvest_grw.py`) and that parsed cues are "never published"
(`script_cues`' own comment). Both are in a public Release of a public repository:

| Asset of `catalog-2026-11-21` | What it holds |
|---|---|
| `harvest-cache.tar.xz` | `grw/text/`: 1,028 whole scripts (listed, not guessed) |
| `radio-catalog.sqlite.xz` | `script_cues`: 251,775 rows, 654 scripts, 17 MB of their words |

Older dated Releases were cut the same way and need the same check (they were not
opened). It is how the publish job gets them, so nobody decided it. `build_db.py`
needs the text only to write `text_cached` (a yes or no) and `script_cues`, which
nothing published reads. **Fix (batch R4-9a, first)**: the harvest cache carries a
list of ids in place of `grw/text`; the published database drops `script_cues`;
one new dated Release is cut; the old assets are replaced the same way or deleted;
a test refuses either name in a staged folder (`cut_catalog_release.sh`). Deleting
a Release asset cannot be undone, so it is done after the new one has published.

This also answers "how could CI have them": today it does, wrongly. §2.2 says how
it should.

---

## 1. The flow

### 1.1 Who, and when

| Rule | Where it is held |
|---|---|
| 13 and over | the device's age answer (084), as sharing is today; the declaration says it |
| Never in a class | the Worker: a production with a `class_id` is `403 class_never_publishes_own` |
| Only the person who wrote it | the Worker: `play_scripts.user_id` must be the director (a passed-on production is refused) |
| Never a cast transcript | the Worker: `episode_id` set is `422 script_from_episode`. A pasted one is caught by content (§2.4) |
| One text | the search is of a revision. A shared script is frozen (R4 §3.2), so a verdict cannot go stale |
| A whole production | the same test as any Publish: every part done, every performer's CC0 consent |
| Not a flood | 3 checks a week an account; two refusals as copied, or one upheld take-down, and the account publishes no more own scripts (the take-down page already promises to act on repeat infringers) |

### 1.2 Steps

1. The director of a complete own-script production presses **Publish**. The
   declaration (§4) comes first, then the recording consent everyone already gives.
2. **The Worker** writes one row, `waiting`. Nothing is sent anywhere. `422` as before
   until it is `clear`.
3. **The workflow** (`originality.yml`, hourly, OIDC, its own pin) asks for the count;
   at zero it ends in seconds and downloads nothing. Otherwise: it restores the
   index, **tests itself with planted copies** (§5.4; a failed self-test judges
   nothing), reads one script, searches, and posts the verdict. Up to 10 a run.
4. The status shows on the production (§1.3). **Clear does not publish**: the director
   presses Publish again, since their device must send the files anyway (082).
5. **A match** is the owner's. The job keeps one issue, opened by the Actions bot and
   assigned to the owner: "1 script is waiting." A number and how to read it, as
   `reports.yml` does. `tools/originality.py` (the owner's wrangler login, refused in
   CI): `list`, `show ID` (the works matched, how many words, which lines), `read ID`
   (the script), `allow ID --yes`, `refuse ID --work "<title>" --yes`.

### 1.3 What the person sees

| State | Words |
|---|---|
| `waiting` | **Checking the script.** "This can take a few hours." |
| `asks` (a title only) | "There is a play called *Fences*, by August Wilson. Is yours based on it?" **No** / **Yes**. Title and author are the source's data, linked |
| `held` | **Someone is reading this script.** |
| `clear`, `allowed` | **Ready to publish.** The button is Publish |
| `refused` | "This script matches *The Crucible*, so it can't be published." (the work the owner named, or "other work"), **Ask about this** |
| could not be searched for a day | `held` |

Recording, sharing and Export are untouched in every state. **Withdraw** is there
while it waits and deletes the row and its findings. The exact findings are never
shown: they would be instructions for rewording.

**Yes** to the title question is an adaptation: if the named work is one of ours
with a castable bucket it goes to the owner as that; otherwise held. **No** is kept
with the row and passes, unless the content search matched.

**Appeal.** Ask about this opens a mail to ben@learningischange.com with the
production's id (the published contact; no new form, nothing stored). The owner may
`allow` after `refuse`. A refused revision is remembered by its 12 hex digits in
`play_removed_scripts` (no person) so the same text is refused at once elsewhere.

### 1.4 What is kept, and for how long

| | Kept | Until |
|---|---|---|
| The declaration: version, date, revision, "based on" | `play_originality` | with the production; when its account goes and the item stays, the row stays with `user_id` cleared |
| What was searched: index date, number of works, each service and whether it answered | the same row | the same |
| Findings (work ids, word counts, line ids, titles; never words) | `findings`, at most 8 KB | erased at `clear`; 90 days after the owner answers; at Withdraw |
| The script on the runner | memory only; no file, artifact or cache | the job's end |
| Phrases and title at the public services | theirs | their logs. Our requests carry a generic agent and the runner's address: no name, account, or production |

### 1.5 The public log

It prints `checked 1`, the verdict's word, service names with ok or failed, and the
index date. Never a title, phrase, id, work, count of words, or error body
(exceptions print their class only). `set +x`; nothing in `env:`; a planted-data
test like `test_reports_issue.py` runs a full fake job and fails on any planted
word. The production id is not printed: it is the archive.org identifier later.

### 1.6 Afterward

A take-down notice or a `copyright` report on a published one: the owner's
`unshare` already removes every line; `refuse` then records the revision. The
take-down form learns an `archive.org/details/eardrama-<pid>` link (it reads only
series and episode links today). A complete notice removes on its own (074).

---

## 2. The content search

### 2.1 The method

Words only: lowercase, no accents, no apostrophes, brackets and labels dropped,
speeches run together. Every 5 words in a row become a number (47 bits of a hash).
A known text keeps the least number of every 12 in a row (winnowing: Schleimer,
Wilkerson and Aiken, 2003), so **any 16 words in common are sure to share one**;
the script being checked keeps all of its own. Shared numbers within 16 words of
each other are a run; a run needs three; each number counts once, so a transcript
stuck on "I'm a man I'm a man" is not a copy (loops like that were most of the
first run's false matches). A spelling table (thou/you, colour/color) was built, measured, and
**dropped**: modernized copies were found 12 of 12 without it.

**The rule: a run of 40 words, or 2% of the script (and 40 words) from one work, holds.**

### 2.2 The index

| Source | Texts | Words | Numbers kept |
|---|---|---|---|
| Gutenberg plays and drama books | 1,721 | 68.2 M | 10.3 M |
| Generic Radio Workshop scripts | 1,028 | 4.3 M | 0.65 M |
| archive.org's automatic transcripts | 9,542 | 31.6 M | 4.8 M |

126 MB, 78 MB compressed (the Workshop's part is 5 MB). It builds in 112 s at low priority and answers a
30,000-word play in 0.6 s with 133 MB, in plain Python (a sorted file and a binary
search): no package. The published play library (803) is inside Gutenberg's.

**Where it lives**: a rolling Release, `originality-index`, one asset per source,
dated and never overwritten, built on the Mac beside the caches (as
`refresh_play_library.sh` is) and sha-checked. The transcripts' part can be rebuilt
in CI from `transcripts-latest`.

**May the Workshop's numbers be public?** The choices:

| | Works | Cost |
|---|---|---|
| **A. Publish the numbers** (recommended) | one asset, no secret | See below |
| B. Keep them in D1, served in 400 KB pieces to the OIDC job | yes: about 18 reads a run | a table and an upload step for a small gain |
| C. Actions cache | no | GitHub: "Anyone with read access can create a pull request on a repository and access the contents of a cache"; unused for 7 days it is gone |
| D. Encrypt the asset | a key to keep | against 085 |
| E. Rebuild in CI | 1,028 requests a build to someone else's small site | impolite |

A is acceptable: the numbers are one in seven five-word windows, cut to 47 bits,
in hash order, so no text can be read out of them; someone who already has a phrase
can ask whether it is there, which is what they are for. Someone could guess common
phrases one by one and confirm some; never order, never a scene. US courts have
held the use fair on facts that went further: *A.V. v. iParadigms*, 562 F.3d 630
(4th Cir. 2009), where whole papers were archived to detect copying; *Authors Guild
v. HathiTrust*, 755 F.3d 87 (2d Cir. 2014), a full-text search index,
"quintessentially transformative". It fits our rule ("search and matching only"):
it is a search index. Work numbers are listed as our own script ids, whose titles
the site already links. If the Workshop answers no to the pending request, its
asset is deleted and the search says it did not look there.

### 2.3 Planted copies (552)

40 scripts (20 plays, 20 radio), parsed as an own script is, then disguised. Held =
the rule above. "Copied" is the median share of the script found in the source.

| Disguise | n | Held | Right source named | Copied |
|---|---|---|---|---|
| Verbatim | 40 | 40 | 40 | 97% |
| One act (a third) | 40 | 40 | 40 | 97% |
| 30% excerpt in other text | 40 | 40 | 40 | 29% |
| Characters renamed | 40 | 40 | 40 | 90% |
| Spelling and old words modernized | 12 | 12 | 12 | 84% |
| Half the lines cut | 40 | 40 | 40 | 89% |
| OCR noise, 1% of letters | 40 | 40 | 40 | 79% |
| OCR noise, 3% of letters | 40 | 40 | 40 | 46% |
| Synonyms, 10% of words | 40 | 40 | 40 | 51% |
| Synonyms, 21% of words | 40 | 40 | 40 | 18% |
| Modernized, renamed, and synonyms (21%) | 40 | 40 | 40 | 13% |
| 150 words inside 2,000 | 40 | 40 | 40 | 7% |
| 60 words inside 2,000 | 40 | **36** | 40 | 3% |
| **Real**: archive.org's transcript of a broadcast, against its human script | 60 | 58 | 56 | 71% |

Of the last row's four without the right source, all four share under 0.2% of their words with the
script they were paired with: the pairing is wrong, not the search (two of them
matched another broadcast's script of the same story). The 56 right pairs were all held.

### 2.4 Unrelated scripts (180)

Each was scored against every text not by its author, not of its title, and not of
its series. "New" scripts of the right kind do not exist to test on, so old ones
stand in, and old ones get quoted and remade; every hold was read.

| | n | Held | By coincidence | What the holds were |
|---|---|---|---|---|
| Stage plays | 50 | 4 | 0 | 3 quoted at length in another book, 1 the same publisher's advertisement |
| 800 words of a stage play | 50 | 0 | 0 | |
| Radio scripts | 40 | 10 | 0 | 7 the same script performed on another show, 2 commercials, 1 a scene of the same play on another show |
| Transcripts | 40 | 4 | 0 | 3 commercials or announcements, 1 a famous poem read aloud |
| **All** | **180** | **18 (10%)** | **0** | every one shares the words |

Below the rule the longest run seen was 37 words, and those were quotations too
(the Declaration of Independence, a poem, Shakespeare). So a new script that quotes nothing at
length has, on this evidence, a false hold near zero (0 of 180; at 95% confidence,
under 2%). One that reads a famous poem aloud will be held, correctly, and the
owner allows it.

### 2.5 What it cannot catch, measured

| | n | Held |
|---|---|---|
| The same story by another author (Faust, Medea, Lear, Joan of Arc, ...) | 11 | 0 |
| Another translation of the same play | 6 | 1 |
| (the same translation in another edition) | 1 | 1 |
| A retelling that borrows lines | 2 | 2 |
| A radio adaptation of an indexed play, or of the novel it came from | 8 | 6 |
| The same title, another work | 7 | 0, rightly |

- **An adaptation, sequel, or translation in new words**, including of a protected
  work, is invisible to it. Only the declaration and the title question ask.
- A sentence-by-sentence paraphrase by a patient person, or by a model. A fifth of
  the words swapped is caught; all of them swapped is not, and was not tested.
- Characters and plots. Copyright protects some; no search here sees them.
- **In-copyright plays we do not hold**, which is nearly all of them: §2.6.

### 2.6 Plays we do not hold: the Internet Archive's full-text search

It searches inside scanned books, lending library included, and needs no key. Six
phrases of 7 or 8 words, one from each sixth of the script, picked by rule: the
rarest words in one sentence, no part's name, every word seen before in radio
speech (so a typing error is not "rare").

| Test | Result |
|---|---|
| 10 protected plays (Miller, Williams, Beckett, O'Neill, Wilder, Hansberry, Stoppard, Wilson, Kushner), one hand-picked short phrase or pair each (4 to 8 words) | **9 of 10 named in the first 20 answers** (playwright or title). The miss (Kushner) ran across two sentences; archive.org has scans of it |
| Phrases picked by the rule from two plays (6 each) | **12 of 12 found**; one item held all six, 57 and 59 items held two or more |
| 6 sentences written for this test | 0 of 6 found |
| 2 ordinary sentences of 8 words | 41 and 788 items: a phrase alone proves nothing |

**The rule: two or more of the six in one item holds.** One or none is nothing. The
answers took 1 to 2 seconds each. Only the number of hits and the item's id and
title are read; its text snippets are dropped unread and never stored. Caution: these plays are famous and much
scanned. An unpublished play, a script on someone's website, a film or television
script that was never a book, and a play from the last few years are likely absent,
and none was tested.

It is the search box's own service (`/services/search/beta/page_production/`,
`service_backend=fts`), not a documented API, so it may change; the batch first
checks whether the `ia` tool's full-text mode serves instead. Six requests, 3
seconds apart, only after a person asks to publish. archive.org's terms (31
December 2014, read in the Wayback Machine's 2023 copy since the live page needs a
browser) grant access "for scholarship and research purposes only" and ask that use
be "noninfringing or fair use": six short queries a script is within both. **When it
does not answer, the script waits; a search that did not run never clears anything.**

---

## 3. The title search

Normalized as `script_rights.norm_title` (article, case and punctuation dropped),
plus the part before a colon or "; or,". Asked of, in order:

| Source | Real query, 2026-11-24 | Terms and limits | Use |
|---|---|---|---|
| Ours: the library, Gutenberg's list, matched radio titles, 11,166 drama renewals | local | ours | **yes** |
| Wikipedia search (`intitle:` with `play`) | *Fences*, *The Visitor*: the play found each time, 0.3 to 0.7 s | one request at a time, a named agent (API:Etiquette) | **yes** |
| Wikidata label search | *Fences*: "1983 play by August Wilson". *The Visitor*: none. A typed SPARQL query found neither | as Wikipedia | **yes**, descriptions that say play |
| Open Library (title, subject drama) | *Fences*, *The Glass Menagerie*, *Death of a Salesman* found, 2 to 4 s; 2 of 5 calls failed (reset, 45 s timeout) | 1 a second, 3 when identified; no bulk | **yes**, with one retry |
| Copyright Office public records | *Death of a Salesman*: 188 records in 0.8 s, 9 of them dramatic; *Fences* with its author: 7 | the site's own service; no published API, terms or limits found | **best effort**, never required |
| Library of Congress | 18 and 38 s; the first answer to *The Glass Menagerie* was an 1874 book by another name | 20 a minute, an hour's block | no |
| Google Books | `429`: the keyless daily quota is shared and spent | a key, against 085 | no |
| HathiTrust | its search answers a program `403`; its open API looks up numbers, not titles | | no |

A title is not protected (Copyright Office Circular 33, "Names, titles, and short
phrases"), so **a title never refuses and never goes to the owner by itself: it
asks** (§1.3), naming at most three plays, those whose author is known first. A title
of one common word that matches four plays or more asks nothing. **Title and
content together** go to the owner with both, and so does **a title plus two part
names** found in that play's Wikipedia article (a same-named play with Troy, Rose and
Cory in it is an adaptation). That last rule is unmeasured: R4-9c measures it on 30
pairs, 8 of them innocent, before it is on.

The claimed author's name is not sent or matched: we hold a chosen name, and two
people share one.

---

## 4. The declaration

### 4.1 What the research says

| Source (read 2026-11-24 unless said) | What we take |
|---|---|
| **CC0 1.0 legal code**: the affirmer, "to the extent that he or she is an owner of Copyright"; a waiver made "permanently, irrevocably and unconditionally"; §4(b) "makes no representations or warranties of any kind"; §4(c) "disclaims responsibility for clearing rights of other persons" | CC0 itself promises **nothing** about who wrote it. The promise has to be ours, separate and first |
| **CC0 FAQ**: the affirmer "is not guaranteeing anything about it, including whether she owns the copyright"; and "you are still responsible to any third parties" | the same |
| **archive.org terms**: "not to infringe any copyright"; no statement of authorship at upload; a license is trusted as far as "the declaration and declarer" | nothing upstream checks for us |
| **Wikimedia Commons, Own work**: works "that you have created yourself, that are not substantially representations of works by others"; reading "someone else's written text" aloud is a derivative. Its own research (Phabricator T347596): "uploaders often select the own work option ... even if is it not their own work" | say "I wrote", never "own work", and name what does not count |
| **itch.io terms**: publishers "affirm, represent, and warrant that they own or have the rights"; over 18 "or possess legal parental or guardian consent" | the parent line for 13 to 17 |
| **AO3 terms**: no account or upload under 13; "does not prescreen Content" | age in the words; our search is more than the norm |
| **LibriVox** (its site answered 522; from a search's summary of its wiki): volunteers release to the public domain and record only public-domain texts | why new text needs its own step |
| **Copyright Office, Circular 14**: "Only the owner of copyright in a work has the right to prepare, or to authorize someone else to create, an adaptation of that work"; new material alone is protected in a version of a public-domain work | translation, adaptation and new version are named; public-domain sources are allowed and named |
| **Copyright Office FAQ**: "Minors may claim copyright ... but state laws may regulate the business dealings involving copyrights owned by minors" | a 13-year-old is an author; a parent agrees to the giving-away |

### 4.2 The words

Consent id **`own-script-2026-11-24`**. Served by the Worker beside the CC0 consent,
drawn as that screen is. The title is **Publishing a script you wrote**; the button
**I agree**.

> Publishing a script you wrote
> - You wrote this script. If other people wrote it with you, they agree to all of this.
> - It isn't copied, translated, or adapted from someone else's play, book, show, film, game, or song, unless that work is in the public domain and you name it here.
> - Nobody else owns it: not a school, an employer, a publisher, or a contest.
> - You dedicate its words to the public domain (CC0). Anyone may copy, change, perform, or sell them, for any purpose and without credit, including training AI. This can't be undone.
> - Before it publishes, its title and words are searched for in other works. GitHub's computers read the script, and its title and a few short phrases are sent to public search services. If they're found, a person reads it.
> - If it turns out not to be yours to give, it comes down.
> - You're 13 or older. If you're under 18, a parent or guardian agrees.

Under it, one field, **Based on (public domain)**, optional, 200 characters, through
`wordsRefusal`. When filled it goes to the owner only if a match names a different
work; it becomes a line in the item's description, "Based on ...".

Each line is true of what happens: the search reads words, a person reads a match,
and "comes down" is `unshare`. It says **found**, not **copied**, and nothing claims
the search proves anything. It does not mention AI-written scripts: "You wrote this"
already answers it.

**Stored**: version, time, production, revision, account (cleared when it goes), the
based-on line. Not: age, a parent's name, an address, a signature.

### 4.3 To paste under DECISIONS 088

> *Sources of the own-script declaration for 5* (the owner left the wording to
> research, 2026-11-24). CC0's own code warrants nothing ("makes no representations
> or warranties of any kind", §4(b)) and "disclaims responsibility for clearing rights
> of other persons" (§4(c); creativecommons.org/publicdomain/zero/1.0/legalcode), so
> authorship is declared separately. Wikimedia Commons (Commons:Own_work): "works that
> you have created yourself, that are not substantially representations of works by
> others"; its research found "own work" is often picked wrongly (phabricator
> T347596), so ours says "You wrote this script". itch.io's terms: "affirm, represent,
> and warrant that they own or have the rights", and parental consent under 18. AO3's
> terms: 13 and over, no prescreening. Copyright Office Circular 14: "Only the owner
> of copyright in a work has the right to prepare ... an adaptation"; its FAQ: "Minors may claim
> copyright ... but state laws may regulate". archive.org's terms (2014-12-31) ask no
> authorship statement. The id is `own-script-2026-11-24`; the words are R4-9 §4.2.

Privacy page, after the own-script phrase: "If you ask to publish a script you
wrote, GitHub's computers read it to look for the same words elsewhere, and its
title and a few short phrases are sent to the Internet Archive, Open Library,
Wikipedia, Wikidata and the U.S. Copyright Office. We send no name." Data inventory:
a row for `play_originality`, one for GitHub as a processor. Privacy labels: B23's.

---

## 5. Worker, data plane, batches

### 5.1 Schema (`0014_originality.sql`)

`play_originality`: `production_id` (key; goes with the production), `user_id`
(nullable; in `USER_TABLES` as cleared, the way `play_reports.target_user_id` is),
`revision`, `version`, `declared_at`, `based_on`, `status` (`waiting`, `asks`, `held`,
`clear`, `allowed`, `refused`), `title_answer`, `lease_until`, `searched` (JSON: index
date, works, each service's answer), `searched_at`, `findings` (JSON, 8 KB),
`decided_at`, `work` (the owner's named work). One index, `(status, declared_at)`. A
refused revision adds `unpublishable:<rev>` to `play_removed_scripts` (the key is its
own kind; sharing does not read it, publishing does).

### 5.2 Routes

| Route | Who | Answer |
|---|---|---|
| `GET /consent` | anyone | adds `own: { version, text, open }` |
| `POST /productions/:pid/originality` | the director who brought it | `{ version, based_on? }`: `202` the status; `403 class_never_publishes_own`, `403 not_the_writer`, `422 script_from_episode`, `422 not_complete`, `409 consent_version_mismatch`, `410 script_removed`, `409 script_reported`, `429 too_many_checks`, `422 script_refused`, `503 own_publishing_closed` |
| `POST /productions/:pid/originality/answer` | the same | `{ based_on_it: true or false }` at `asks` |
| `DELETE /productions/:pid/originality` | the same, before a job exists | `204` |
| `GET /v1/operator/originality` | `originality.yml` | `{ waiting, held }` |
| `POST /v1/operator/originality/next` | `originality.yml` | one `waiting` row, leased 30 minutes: `{ key, title, parts, text }`, or `204`. `key` is random for the lease and answers for nothing else, so the runner never knows the production |
| `POST /v1/operator/originality/verdict` | `originality.yml` | `{ key, verdict, searched, findings }`; `409 lease_gone`, `422 bad_verdict` (a `clear` needs the index and archive.org's search answered) |

`GET /productions/:pid` adds `originality: { status, plays?, work? }`. `isPublishable`
does not change. A second test, `isCleared(production)`, stands beside it: an own
script with a `clear` or `allowed` row **at this revision** and at the current
declaration. `publish`, `archive/files` and the cron each ask it, so a hole in one
is closed by the next. The item's metadata: title as given, `rights` "Dedicated
CC0 by its author", no `source`, `description` with "Based on ...". The text itself
is not uploaded: the item is the recording, as today. **No listing, search or
gallery** (R4 §2.8): `plays-open`'s finished listing goes on leaving own scripts out.

`OWNER_WORKFLOWS` gains `originality` (schedule and dispatch) with refused-claims
tests and an `oidc:` mutant per check (085). Its token reads exactly one script at a
time and only one whose writer asked.

### 5.3 Free-plan budget

Idle: 24 requests and 24 one-row reads a day. One check: 1 write to ask, 1 to lease,
1 for the verdict, at most 3 more; one 400 KB read (1.1 ms measured, WORKER.md). Fifty
a day is 300 of the 100,000 daily writes. Actions minutes are free on a public
repository; a run with work is about 2 minutes, most of it the 78 MB download.

### 5.4 Batches

| Batch | What | Size | Must fail first |
|---|---|---|---|
| **R4-9a** | §0: the Workshop's text and cues out of public Releases | S | `cut_catalog_release.sh` refuses a staged `grw/text` or a `script_cues` table; the publish builds without them |
| **R4-9b** | The index: `catalog/tools/originality_index.py`, its Release, `refresh_originality_index.sh` | M | 16 shared words always share a number (property test); an index missing a source is refused; **the planted-copy gate** |
| **R4-9c** | The search: content, phrases, titles, verdict; the part-name rule measured | M | every service down, one at a time: never clear; title alone never holds; the log's planted-data test |
| **R4-9d** | Worker: 0014, routes, `isCleared` in three places, retention | L | a class, a transcript, a passed-on production, an old revision, an old version, a refused revision; withdraw; account deletion; a mutant each |
| **R4-9e** | `originality.yml`, the issue, `tools/originality.py`, its runbook | M | refuses in CI; the issue holds only a number; `refuse` then the same text elsewhere |
| **R4-9f** | Web, then Apple and Android: declaration, states, question, Withdraw; privacy page, inventory, PARITY | L | Node tests; 375 and 1440 frames; the tap tier; the Pixel |
| **R4-9g** | Open it: one planted copy through the real Worker and Actions is held, the issue's email arrives, one clear script of a bench account passes and is removed | S | `own.open` stays false until both are seen |

**The gate** (in 9b's tests and at the start of every run with work): from three
published library plays fetched from our own site and one control, build verbatim,
renamed, OCR 3%, 21% synonyms, one act, and 150-in-2,000 plants. All must hold and
name the source; the shuffled control must not. Seen failing with the index emptied,
`k` changed, and the threshold at 400.

### 5.5 Risks, worst first

1. **An adaptation of a protected work in new words passes** (§2.5). The
   declaration, the title question and take-down are all there is. The page must never
   say "original" or "verified", and does not.
2. **The exposure in §0** undercuts every claim here until R4-9a.
3. **archive.org's full-text search is not a promised API.** Without it nothing
   clears, so a long change there stops publishing own scripts (safely) until mended.
4. **The owner's time.** On this evidence holds are rare and are real; a flood is
   capped at 3 checks a week an account.
5. **Someone tests rewordings against the public index.** It is open, so they can. What
   a patient paraphraser beats, they beat anyway.
6. **A prank script in a public log.** The runner prints no field, and a test plants one.
7. GitHub's hourly schedule runs late or not at all; "a few hours" allows for it.

---

## 6. Owner decisions

**None.** 088 settles who decides a match, the search, the age and the wording; 085
the route; 074 removal; the Workshop rule already says its text is not to be
public, so §0 is a repair. Two things the owner will notice, for information: the
declaration asks a parent to agree for 13 to 17 (084's media release for classes is
the same idea), and if the Workshop refuses, its numbers are deleted.
