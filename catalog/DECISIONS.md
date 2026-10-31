# Radio catalog — decisions

Append-only, lead-with-WHY (the Archive Watch format). This pipeline will move to
Ear Drama's own repository when it is created; these entries move with it.

## 001 — Unclaimed broadcasts are kept and removed on request; nothing is kept on a paid licence
*Date: 2026-10-17*

A pre-1972 radio recording with no claim a reader can open — no Copyright Office
schedule, no named claimant with a source, no take-down, no renewed script or
adapted film, not post-1972, not of non-US origin — is `keep_unclaimed`: shown,
and hidden the moment a claim appears. No recording is kept on a SoundExchange
statutory licence or any other paid licence.

**Why**: the owner, 2026-10-17: *"I like the idea of moving to a 'take down
request' model for this, but a licensed model at $1000 per year is definitely not
in keeping with our regular process."* Federal law protects nearly every pre-1972
recording until 2067 (17 U.S.C. §1401), so "public domain by age" frees almost no
radio drama; but §1401(f)(5) denies statutory damages and fees to an owner who
filed no schedule, and §1401(f)(3) applies the DMCA safe harbor — the reason
archive.org and RadioEchoes run on notice and takedown
(`docs/research/02-rights.md` §12).

**How to apply**: never label `keep_unclaimed` "public domain" in any client —
its rights line says no claim is known and that it is removed on request
(Archive Watch Decision 153's lesson). A take-down goes in
`editorial/takedowns.json` and takes effect at the next build. Every new claim
source becomes a hide bucket that runs BEFORE the rescues, with a test and a
control. Register a DMCA agent before launch.

## 002 — An uploader's licence tag neither admits nor hides a recording
*Date: 2026-10-17*

The archive.org `licenseurl` on an OTR item is recorded as provenance and plays
no part in the rights state. OTRR's CC BY-NC-ND sets are kept like any unclaimed
recording, and OTRR is credited (the licence's attribution term; the app is
noncommercial and makes no derivative copy — loudness gain is applied at
playback).

**Why**: measured 2026-10-17, ~1,000 OTR items carry CC BY-NC-ND/ND tags and
~1,490 PD marks on 1940s network broadcasts that uploaders could not own
(02-rights §8). As a rescue they are an uploader's word (Archive Watch Decision
140); as a hide they would remove OTRR's sets, the best-dated copies in the
corpus, on a claim over the compilation that the app already honors. This
departs from 02-rights §10's proposed `rec_uploader_cannot_license` hide, which
was written before Decision 001.

## 003 — The radio app is its own app, not a section of Archive Watch
*Date: 2026-10-19*

Ear Drama ships as a separate app with its own repository, bundle ids
and store listings. This catalog pipeline moves there when that repository is
created.

**Why**: the owner, 2026-10-19: *"It is definitely a separate app."* (Answering
RESEARCH.md §7 Q2.) App Store guideline 4.3(a) ("Don't create multiple Bundle
IDs of the same app") is answered by the app's different content and audio-first
design, which the research (`docs/research/04`, `05`) documents.

**How to apply**: nothing here imports Archive Watch code at runtime; the one
file this pipeline reads from Archive Watch (`shared/editorial/cce_renewals.json`)
is copied into the new repository when it moves. Cross-links to Archive Watch
films (RESEARCH §6) are links between two apps, by archive.org id.

## 004 — An unregistered network script follows the recording: kept while unclaimed
*Date: 2026-10-22*

A script with no registration, renewal, or sourced claim does not hide its
episode; the episode takes the recording layer's state. A script registered and
renewed (the CCE drama renewals, 679 of them radio) still hides it as
`work_script_claim`.

**Why**: the owner answered RESEARCH §7 Q4 on 2026-10-22 with the take-down
model rather than "protected: hide". Treating every unregistered script as
protected would remove most network drama on a claim nobody has made, while the
real script risk is the registered and renewed kind (*Lone Ranger*, 1984).

**How to apply**: the CCE renewals must be wired into the audit before any
old-time radio item is published (README: "not yet wired in"), with a test and
a control. A registration found later is a new hide bucket, never a list of ids.

## 005 — A named, sourced claimant hides a series; a sales listing alone does not
*Date: 2026-10-22*

A series hides when a claim a reader can open names it (The Shadow and Condé
Nast, The Lone Ranger, the Lum and Abner takedowns). A licensee selling the
series on CDs is not, by itself, a claim.

**Why**: the owner chose this for Q5 on 2026-10-22 over "hide anything sold" and
"keep until a takedown". It is the rule the audit already applies; a sales
catalog says what someone sells, not what they own.

**How to apply**: `rec_rights_holder_claim` needs a source on every row; a new
claimant enters through `editorial/audio_claims.json` with its evidence link.

## 006 — The remaining buckets, with a stricter rule for music
*Date: 2026-10-22*

These settle Q6-Q9 and 02-rights §11 items 5-10:

| Bucket | Rule |
|---|---|
| Non-US productions | hidden unless licensed |
| Post-1972 series (CBS Radio Mystery Theater) | hidden unless licensed |
| A general takedown naming no episodes | hides the whole series; the letter is kept in `takedowns.json` |
| 10+ live script renewals in a series | a series claim |
| CBS news broadcasts Sony scheduled | hidden; news is out of scope anyway |
| Music and variety shows built on popular songs | **hidden** (stricter than drama) |
| AFRS originals | kept as government work only when no commercial performer is credited |
| WWII and Cold War propaganda | never recommended, always findable (Archive Watch 149; `no_recommend`) |
| Racist caricature (Amos 'n' Andy, minstrel shows, Fu Manchu) | never recommended, always findable, on a source (013) |
| Noncommercial-use notices ($50 each) | not filed |

**Why**: the owner accepted the defaults on 2026-10-22, "but stricter music".
Song copyrights are the live risk in a variety hour: the music publishers are
active, and their works are registered, so a hidden variety show costs little
drama and removes the claim most likely to be made.

**How to apply**: music and variety need a `content_kind` from data (archive.org
subjects, log genres, Goldin's program type), never from a model's reading of a
title; a comedy-variety show whose songs are incidental stays with drama only
when its data says so. The AFRS rule reads the credits table. Each row above is
a bucket with a paired test and a broken control in `tests/test_audio_rights.py`.

## 007 — The default copy is the domestic network broadcast, commercials included
*Date: 2026-10-22*

When a domestic network copy and an AFRS disc of one broadcast both survive, the
domestic copy plays by default and the AFRS disc is a version a listener can
pick, even when the disc sounds better.

**Why**: the owner chose R5 for Q9 on 2026-10-22. The sponsor and the pitch are
the era's history (R8), and the domestic copy is what people heard that night.

**How to apply** (amended the same day, tick 8): `build_db.order_recordings` sorts
a complete copy before a partial one (under 60% of the median length), then the
domestic broadcast before an AFRS, AFRTS, or rehearsal variant, then OTRR's copy,
then the measured bitrate; never the format label. Completeness comes before kind
because a seven-minute fragment of the domestic broadcast is not the broadcast as
aired; the first wording here put kind first, which the test's control now refuses.

## 008 — Transcripts: archive.org serves the text; search indexes every one, without positions
*Date: 2026-10-22*

The projection indexes every fetched transcript in `episodes_fts` and sets
`has_transcript` (and `transcript_url`, archive.org's own `.autogenerated.txt`)
only where `transcript_gate.shown` passes; the text itself is never in a file
we publish to clients. `episodes_fts` is `detail=column`.

**Why**: DECISIONS 058 says always searchable, shown only past the gate. A
browser can fetch archive.org's text directly (measured 2026-10-22: `*` CORS on
the 302 and the storage node's 200, preflight allowed), so re-hosting about 181
MB of text would add a copy that can drift and buys nothing. Token positions
would have cost 8.6 KB compressed per transcript (about 78 MB, three times the
projection); `detail=column` costs 2.1 KB and keeps every query the clients
make (quoted prefix terms, column filters); only phrase and NEAR queries lose.

**How to apply**: the gate is re-run on the cached text at build time, so the
cache's stored verdict is evidence, not the decision. A transcript of a copy
that is no longer the default is neither indexed nor shown. A phrase search
feature would need positions back, measured against the size budget first.

## 009 — Genre stations: the genre's broadcasts in the order they aired, one published clock
*Date: 2026-10-24*

A genre station (R10, Decisions 058 and 068) is a published schedule in
`stations.json`: the genre's served, recommendable, complete episodes, 5 to 90
minutes, back to back on one UTC clock, in the order they first aired, each
build keeping every published slot and appending four days ahead. No episode
repeats in the window, and a series waits for six others before it airs again.

**Why**: everyone tuned to a station must hear the same episode at the same
moment (AGENTS.md: publish a computed value, never a seeded shuffle), and the
owner rules out AI-written lists, so the order has to be a fact of the data.
Broadcast order is one: a station walks its genre's surviving radio as it aired,
which mixes series the way a real evening did. Measured 2026-10-24 on the
2026-10-22 projection: eight stations, 1,905 slots for four days, 23 to 73
series per station in a window (drama spans 1936 to 1939 in four days, so a
pass through a genre takes months). With a three-slot wait, drama cycled four
1936 series for hours; six gives 23 series in the same window. A complete
default copy only: a partial one is a broadcast as it was not aired.

**How to apply**: never rebuild a schedule from scratch over a published one;
a change to the order rule applies to the slots appended after the kept ones.
A pass over a series the wait skipped is lost for that cycle, not deferred
(the file carries no cursor). A station that cannot fill three days without a
repeat fails the build rather than repeat.

## 010. A semicolon list of artists is credits, never one person

**Rule**: `enrich_db.parse_artists` splits Goldin's Artists string on top-level
semicolons first (when 2+ non-empty segments), then parses each segment as
before; the person id is the normal one for the name (`People.goldin`).

**Why**: Goldin types some cast lists with semicolons, and the comma-only
split made the whole list one person: 1,247 people rows with ';' in the name
(a whole cast under one name, shown in Search and as a person page).

**How to apply**: measured 2026-10-24 on the real database: people rows with
';' 1,247 to 7 (two are OTRR names, five are strings with an unbalanced quote
that cannot be split safely; counted as `goldin_compound_names_unparsed`),
people 53,925 to 53,101, episode credits 334,592 to 340,487. A ';' inside a
parenthesis is not a separator. Comma-only variants were measured (9 names)
and left alone.

## 011 — Story arcs come from what titles say, and any doubt leaves the episodes single
*Date: 2026-10-24*

A story arc (contract §3.3, `arcs` and `arc_parts`; `tools/arcs.py`) is the
parts of one serial story, in order. It is derived only from titled parts in
one series ("The Molly K Matter - Ep 3", "Space Station of Danger, Part 2",
"Chapter 4"), and kept only when the parts run 1 to n with no gap and no part
twice, n is at least 2 and no more than a stated "of N", and the dates, where
known, rise with the part, neighbors at most 45 days apart. A bare "Episode 7",
or the series' own name and a number, numbers a series, not a story. Same-titled
dated episodes without a part number are not arcs.

**Why**: Decision 067 plays a serial to its arc's end and stops, so an arc
decides what plays without being asked. A wrong arc plays the wrong thing on
its own; a missing arc only falls back to the rule that stood before (one
episode, then the queue). Measured 2026-10-24 on the 121,907-episode served
build: 1,988 candidate stories, 480 arcs over 3,886 episodes in 238 series
(Johnny Dollar's 1955-56 five-part stories make 49); 330 refused for a lost
part, 23 for a part twice (The Molly K Matter's "Ep 5" and "pt5"), 2 for parts
against the calendar. A gap is refused, not cut short: playing parts 1 and 2 and
then offering the next story would skip a part 4 that survives.

**How to apply**: loosen a rule only with a measurement of what it adds and a
sample read against the episodes. The web serves an arc only whole (a part the
gate holds back would be skipped), so its counts are smaller (198 arcs on the
clean-only web). `next_arc` is the series' following arc whose first part is
recommendable (`recommendAnd`: the offer chooses for the listener); parts inside
an arc play regardless, since the listener chose the story. No source marks a
commercial's start and end yet, so there are no chapters (R8); see contract §3.2a.

## 012 — Search finds only what Detail can show: transcripts past the gate, words without text
*Date: 2026-10-27*

Only a transcript that passes `transcript_gate.shown` is indexed: in the served
projection's `episodes_fts.transcript` column, and in the web projection's
`search/said/` files, which hold each transcript word's doc numbers and never
the text. A snippet is cut on the device from archive.org's own text at
`transcript_url`, verbatim. This narrows 008, which indexed every fetched
transcript.

**Why**: the 2026-10-27 brief asked that only transcripts above the gate be searchable
(Search by what is said and by air date). A search hit on a looped transcript would show a row whose text
Detail refuses, and a snippet from that text is exactly the garble the gate
exists to keep off screen. Shipping snippets instead of cutting them on the
device was measured and refused: one 80-character snippet per word per
transcript is 11 MB gzipped for the rarest words alone (those in at most 20 of
5,657 transcripts) and 30 MB for those in at most 110, against 4.7 MB for every
word's doc numbers.

**How to apply**: measured 2026-10-27 on the 2026-10-22 research database with
the transcripts-latest cache (5,657 shown of 5,889 fetched): the served
projection fell 59 KB compressed (32.55 to 32.49 MB) and the clean-only seed 3
KB (1.266 to 1.264 MB); the gate-open web projection gained `search/said/`
(91,535 words in 796 files, 12.8 MB raw, 4.7 MB gzip, the largest `co.json` at
387 KB raw, 144 KB gzip) and `search/dates/` (53 year files, the doc rows by air
date, for Search's dates). A word under three letters is not filed.

## 013 — Racist caricature is never recommended and always findable, on a source a reader can open
*Date: 2026-10-28*

`build_db.no_recommend_reason` sets `no_recommend` (the 006 mechanism) for three
kinds of evidence, in this order. A Nazi-state recording: the speech words now
include German compounds (Wahlkampfrede, Rundfunkansprache, Kundgebung), and a
title that opens with the speaker's full name in the German archive's form
("Adolf Hitler - Kulturtagung", "Adolf Hitler vor dem Reichstag"). A recording
whose archive.org item is in archive.org's own `deemphasize` collection. And
racist caricature, from `catalog/editorial/racist_caricature.json`: a series or
title pattern, each with a source that documents it as racial caricature
(Amos 'n' Andy, Beulah, Aunt Jemima, the minstrel show, the Mitchell Minstrels,
Fu Manchu); `not` exempts a program about the act with its reason. The reason
text names the source. Every surface that chooses for the listener already
skips the flag (contract §5 `recommendAnd`); Search, Browse and Detail keep
the episodes.

**Why**: the owner, 2026-10-28: *"If we don't yet have flags for offensive
materials we need to implement them. Archive watch has multiple different flags
for racist materials that allow them to be searched for but never recommended
on the surfaces we want users to leverage for discovery."* The flag existed
for Nazi speeches only, and that rule missed 87 of the regime's own recordings
because their titles name the speaker and the occasion, not a speech word.
archive.org's subject tags were measured and refused as evidence here: the 18
items tagged racism (11), stereotyping (4) or minstrels (3) are mostly programs ABOUT racism
(Pacifica reels, anti-apartheid journalism), and one "minstrels" tag sits on a
107-show variety collection. A guest spot where the Amos 'n' Andy act performs
in character is flagged with the show; an interview or history program about
it is not.

**How to apply**: measured 2026-10-28 on the local research database: 1,016
episodes flagged racist caricature (786 Amos and Andy Show, 89 The Shadow of
Fu Manchu, 59 Beulah, 20 Aunt Jemima, the rest guest spots and minstrel
episodes across 30 series), Nazi-state 97 to 184, 5 more on archive.org's
deemphasize alone; none lost its flag. Add a program with a source a reader can
open, never on a hunch or a bare keyword; exempt one in `not` with its reason.
Left for the owner: Charlie Chan; Frank Watanabe and the Honorable Archie (no
source found); The Goon Show's Fu Manchu parody (exempted); Jungle Jim's
wartime slurs in titles; coon songs and "darkies" in record titles; Blue Coal
Minstrels; Al Jolson's "Mammy".

## 014 — An id that leaves the catalog forwards, permanently: an alias by its recording, else a tombstone
*Date: 2026-10-28*

Every publish compares the new served projection with the one live on
`catalog-latest` (`catalog/tools/forwarding.py`, `build_projection.py
--previous`). Each id the live one served and the new one does not gets an
alias to the served episode now holding its default copy, matched by
archive.org item and file name, or a tombstone when no served episode holds
it. Aliases and tombstones are cumulative, chains collapse, an id served again
sheds both, and the build, the diff, and the publish lock each refuse what
breaks that (contract §3.5). Every client resolves through them in one place
and rewrites what it stored once.

**Why**: an episode id is the person's data, not ours: it sits in their
history, their place in an episode, their queue, their downloads, the rows
their other devices sync, and every link they shared. A parse fix changes ids
(C1, 2026-10-28: 984 served ids left when "43-11-21" stopped reading as
1921-03-11), and the `episode_aliases` table that was meant to catch this had
never been filled, so each fix would have silently broken those records. The
owner, 2026-10-28: *"Let's just get everything set up the way that we want it
to be. We don't have to worry about current users, but we do have to worry
about building for the future."* So this is the permanent mechanism, run on
every publish, not a one-off migration. The recording is the identity because
it is the one thing a parse fix does not change: a title guess would forward a
listener to a different broadcast, which is worse than a dead link. A
tombstone, unlike a missing id, tells a client the id is gone for good, so it
can drop it from a queue; an id a client merely does not know may come from a
newer catalog than the one it holds and is kept.

**How to apply**: measured on the C1 rebuild against the pre-fix rebuild (same
cache, PYTHONHASHSEED=0): 984 ids left, 899 aliased onto 895 episodes, 85
tombstoned (all now hidden under their corrected ids). A pipeline change that
moves ids needs nothing more: the next publish forwards them. Never hand-write
an alias; fix the parse and let the recording decide. Never reuse an id for a
different broadcast. A client rewrite keeps each row's own stamp and is never
uploaded as new, so a device on an older catalog is not overwritten by one on
a newer catalog. Series keys forward too (015).

## 015 — A series key that leaves forwards to the series holding more than half of its recordings, else a tombstone
*Date: 2026-10-28*

Every publish forwards series keys the way 014 forwards episode ids
(`forwarding.forward_series`, tables `series_key_aliases` and
`series_key_tombstones`, contract §3.5): a key the live projection served and
this one does not gets an alias to the served series now holding more than half
of the distinct recordings (archive.org item plus file) of every episode it
served, or a tombstone. Cumulative, chains collapse, a key served again sheds
both, the clean-only projection inherits them, the builder refuses a broken
forwarding, and `publish_diff.py` refuses a key that left with neither. Every
client resolves a key in the same one place as an episode id and rewrites the
follows it kept, once, by the newer stamp.

**Why**: a series key is the person's data too: their follows, the Worker's
follow rows, every series link they shared. 237 of the C1 rebuild's 899 episode
aliases changed series key, and 46 served keys left outright; without this,
each one is a follow that silently stops and a link that opens nothing. The
owner, 2026-10-28: *"Let's just get everything set up the way that we want it
to be. We don't have to worry about current users, but we do have to worry
about building for the future."* More than half, not a plurality: a follow is a
choice of one program, and a series that leaves by splitting ("Tube Talk" into
one series per month) has no single successor; forwarding it to the biggest
fragment would name a different program, which is worse than a dead follow.
The denominator is every recording the series served, so a series mostly taken
down is not forwarded on its remainder.

**How to apply**: measured on the same pair of builds as 014: 46 keys left, 20
aliased (each onto a series holding all of its recordings, the largest 139 of
139 onto Information Please), 26 tombstoned (24 with no recording served
anywhere; "Tube Talk" at most 4 of 26 in one series, "The Big Broadcast" 1 of
20). Any threshold above 15 % gives the same rows today; if a future parse
produces a borderline split, the rule stays at more than half and the split is
a tombstone. Downloads need no series rewrite: their series is read from the
episode id, which 014 forwards.

## 016 — A fact the source contradicts itself on is not shown; a name's digits are not a broadcast date

Q1 audit fixes (2026-10-29), each a builder rule with a fixture test.
(1) A date in a file name that is the item's own upload day (`otrt-9-25-21` on an item
uploaded 2021-09-25) is dropped, never read as 1921 (`otr_parse.is_upload_stamp`); a date
glued to more digits (`004-24-1-1437`, a Hijri year) is not a date. (2) `series - YYMMDD -
NNN - title` is its own family (F2d): F5 had read the YYMMDD as part of the series name and
dated the file by its number. (3) Two ids matched to one Wikidata person on a birth or death
date are one person in the served catalog (`build_projection.same_person`); a name-and-
occupation match alone never merges (Walter Brennan Jr.). (4) A length the file's size cannot
hold (under 8 kbps) is unmeasured: the same recording's derivative gives it, else it is
empty. (5) A copy over 2.5 times the median of three or more is a several-episode file and
is not listed as a copy. (6) A title naming another sponsor of its series shows no sponsor.
(7) A Goldin cast string with an unclosed parenthesis, a trailing `;` or a hedge
("possibly") is split per person, and an OTRR role that is the character the same person's
cast row names is dropped.

**Why**: each was a fact a listener can see and a reader can check: Escape's earliest
episode read 1921; Space Patrol ran 29 hr 46 min (archive.org's own record says 107,185.94 s
for a 4.1 MB file and 451.71 s for its Ogg); Jack Benny's "First show for Jell-O" named
General Tire; Johnny Dollar 1955-10-03 listed a 73-minute five-part file and two copies of
the 1955-08-29 episode; Bud Collyer was credited twice on 1,099 episodes. None is a rights
call and nothing is hidden: it is no longer asserted. Left as the source has them, reported
and not corrected: OTRRpedia's own names with a nickname in parentheses ("Richard (Dick)
Aurandt", 563 episodes; "Alan Reed (aka Teddy Bergman)", 481) are 980 of the 1,043 episodes
D1b counted as Goldin fragments; OTRRpedia's General Tire run (1934-04-06 to 1934-10-28)
overlaps Jell-O's start.

**How to apply**: measured against the main checkout's caches, served episodes 107,369 to
107,190 (179 fewer, 0.17 %; MAX_SHRINK is 2 %): 191 ids left, 12 appeared, 166 of the
departures are Johnny Dollar number-only episodes now filed under the date their file names
carry. 1,311 copies dropped as overlong, 21 impossible lengths removed, 11 upload-day dates
dropped, 51 fewer people, 63 episodes with a Goldin fragment credit down to 6.

## 017 — The picture that leads a show is the show's own, then its star, then who is heard most

*Date: 2026-10-29*

A series' picture (`series.picture`, `picture_kind`, `picture_source`; contract §3.3a) is,
in order: **show**, a file from the show's own record (its Wikidata item's image, logo, poster,
collage or related image; a Commons file whose Structured Data depicts the item; a file whose
own page lists the item's Commons category); **star**, a person the program's OTRRpedia record
marks (title role, Star, Host) heard on at least 3 and a tenth of its credited episodes, else
a regular whom a Wikipedia covers, scored share of credited episodes x `1 + ln(1 + Wikipedias)`;
**person**, the heard-most rule; else the typographic board. A show image needs a match on more
than the title (the item's years, or its description's, overlap ours ±2, or its broadcaster is
our network), an item its own description does not call a television program, a license class
a portrait is served under, a shorter side of 160 px, no television in its name or categories,
and no date of its own outside the run (±2 years of the earliest logged broadcast and our last
episode).

**Why**: the owner, 2026-10-29: *"images/graphics that show the full 'show' are better than
individual contributors. Images that show the star(s) are better than those that show folks that
are less recognizable."* An image is used when its own record carries the evidence (DECISIONS
055/069), and a title alone is no identity (`evidence-gated-catalog-curation` §7). archive.org
cover art is not a source: a sample of 60 shows found uploaded art on 26 items, whose only rights
statement is the uploader's license for the item (DECISIONS 002).

**How to apply**: `art_policy.show_served`, `series_identity`, `series_face`; harvest
`harvest_series_art.py` (`.cache/series_art/`); evidence tables from `enrich_series_art.py`, run
by `enrich_people_art.py`; guard `tests/test_projection_art.py`. MEASURED on the 2026-10-28
caches, 2,036 shows of 5+ episodes: before, 263 wore a person and 1,773 the board; after, 37
show, 261 star, 1 person, 1,737 board (all 10,641: 49 / 309 / 1 / 10,282). Of 251 identity-
checked matches a random 40 checked by eye held 1 wrong item (Twenty Questions, the TV program),
which the television rule now refuses; of the 55 show pictures first served, 1 was wrong (Hilltop House:
a Commons depicts statement on a 1914 photograph of the hotel), and the date rule now refuses it
with 5 more dated before their program (Pal as Lassie 1942, a 1928 Strange as It Seems strip,
George Raft's 1939 trailer, William Gargan 1933, Leon Janney as a child): 49 served. On 42 shows whose title-role
holder has a portrait, the heard-most rule and share x recognizability each pick the title role
32 times (raw sitelink counts: 28); the marks make the title role win, and the 25 shows that
gained a face had none before. Coverage is bounded by Wikidata: 268 of the 2,036 shows match an
item at all.


## 018 — A person is the picture of at most one show

*Date: 2026-10-29*

Of the shows that would be led by the same person's portrait (017's star and person kinds), they
keep one, by this order: a show whose title holds their full name (the Jack Benny Program); then a
marked role (the title role, Star, Host) in a show holding at least half as many of their credited
episodes as their biggest show; then the show with the most of their episodes; then the highest share;
then the series key. Every other show is decided again without
them (its next candidate, else the typographic card), and `series.star` follows. A show's own image is
never affected and never counts.

**Why**: the owner, 2026-10-29, to "one face per star": "Yes". William Conrad led both Gunsmoke
and Escape; 51 people led more than one show. The floor is there because a mark is a title role:
Jack Webb is the title role of Pete Kelly's Blues (7 episodes) and not marked in Dragnet (474), and
the plain "marked first" rule gave Webb to the 7.

**How to apply**: `art_policy.assign_faces`; guard: the contract query "a person's portrait leads at
most one show" (seen failing on the pre-rule projection: 51) and the unit cases in
`tests/test_projection_art.py`. MEASURED on the 2026-10-28 caches (10,641 shows): 82 shows changed their
star, 53 lost their picture to the card; by kind before and after: star 309 to 255 (with 019), person 1 to 1, show
49 to 49, none 10,282 to 10,336 (floor and own-work only). Webb leads Dragnet, Conrad Gunsmoke (Escape falls to Paul Frees),
Superman keeps Bud Collyer, The Whistler Marvin Miller, Perry Mason John Larkin. The named-show rule was
added after the first measure gave Jack Benny to The Grape Nuts Program (735 episodes, Host marked) and left the
Jack Benny Program (950) to Eddie Anderson; with it the star counts are star 258, person 1, show 49, none
10,333, Benny leads the Jack Benny Program, and The Grape Nuts Program falls to Eddie "Rochester" Anderson.
It also gives Mel Blanc the Mel Blanc Show, Dinah Shore her show, Walter Winchell, Frances Langford and
Charlie Ruggles theirs, and Boris Karloff the Karloff Collection (16 shows changed against the floor-only rule).


## 019 — An own-work license the picture's own date contradicts is not served

*Date: 2026-10-29*

A portrait (or a show image) whose file page gives the uploader's own license (`{{self|...}}`, PD-self,
PD-user, or a Creative Commons license with `source={{own}}`) is refused when the file's own date is
after the death of the person it is of (Wikidata's death; for a show image, the earliest death among
the people the program's record marks). A public-domain template on a scan the uploader calls their own
is not an own-work license and is unaffected.

**Why**: File:Kollmar.jpg led Boston Blackie: "a photograph I took of Richard Kollmar and his
fiancee", `{{self|cc-by-sa-4.0}}`, dated 2019; Kollmar died in 1971. An uploader's word is not
evidence (`evidence-gated-catalog-curation`), and here the word contradicts itself.

**How to apply**: `art_policy.implausible_own_work`, `enrich_people_art.own_work` (the `own_work`
column of `people_art` and `series_art`); guard: `retrace` in `tests/test_projection_art.py` (seen failing
on a projection built before the rule: it lists the removed files) and the unit cases. MEASURED: 177 of
3,875 person files and 39 of 288 show files are own work; 19 served portraits removed, none replaced, no
show image (2,174 to 2,155 portraits). Of five checked by eye, all five were period photographs no
uploader could have taken (Kollmar, Madge Evans and Billy Halop studio portraits, a Dick Elliott television
still, and Oliver Wakefield's file, a theatre programme page, not a portrait at all). Removed: Audrey Call,
Billy Halop, Dick Elliott, Don Albert, Eddie Arcaro, Gaylord Carter, Hugo Weisgall, Irve Tunick, Jack
Wilson, Joan Barton, Ken Carson, Madge Evans, Max Miller, Nathan Van Cleave, Norman Rose, Oliver Wakefield,
Richard Kollmar, Samson Raphaelson, Yoichi Hiraoka.


## 020 — A build's output never depends on the hash seed

*Date: 2026-10-30*

Two builds of one cache under different `PYTHONHASHSEED` values publish the same projection. Wherever
a set or a count's ties set an order a row can depend on (which spelling names a series alias, which
series key a Goldin record links through, the order of a series' networks), the order is sorted.

**Why**: CI pins `PYTHONHASHSEED=0`, which hid it; two local builds differed by about 400 credit rows
and 74 network rows (first run of `tools/check_build_determinism.py`, before the fix: 172 credit
rows, 49 episodes, 3 people and 4 series differed).

**How to apply**: `tools/check_build_determinism.py [seedA seedB]` runs the whole chain twice and compares
every table (about 20 minutes, so not in `run_all.sh`); run it after touching `build_db.py` or
`enrich_db.py`. Sorted: `build_db.build_registry` (names), `enrich_db.SeriesMap.by_dates`, the OTRR
program loop, a series' networks.


## 021 — A portrait under the size floor gives way to a larger file of the same person showing one face

*Date: 2026-10-30*

A person's portrait is still their own image (Wikidata P18) of the most permissive class, unless it fills
less than the largest window a client draws (`art_policy.LARGEST_SLOT`, 300: tvOS's show tile; `fill_px` is
the crop height every client's `windowFill` compares). Then a file of the same person that shows one face
and fills more is served, the one that fills most, an own image before a stand-in. A stand-in may be a file
whose Structured Data depicts the person, only when the detector read exactly one confident face on it, it
passes every other check `served` makes, and the person has a served own image. A group never replaces a
portrait, and nobody gains a face this way.

**Why**: the size floor (uniform-imagery-design §4) draws the title block under it, so the Jack Benny Program,
led by Jack Benny, drew "JB" on every tile: his own image, JackBenny1958Cropped.jpg, is 174 x 333 and its crop
147 px. NBC's 1938 photograph of him alone (1139 x 1479, a depicts file) fills 513. A depicts file was refused
because it is often a group (DECISIONS 069 in the app log); one face is the evidence that this one is not,
and the depicts statement is on the image's own record (owner 2026-10-21). Ranking by size alone was tried and
refused: it gave David Rose a photograph of him with three soldiers and Rod Cameron a theater program.

**How to apply**: `art_policy.pick`, `alternate`, `crop_rect`, `fill_px`, `face_count`; `people_art.faces`
(`enrich_people_art.py`); guard: `floor_misses` in `tests/test_projection_art.py` (seen failing on the
projection built before the rule: 12 people) and the fixture's controls. MEASURED on the 2026-10-29 caches:
12 of 2,155 portraits change, every one checked by eye a single, right person (Jack Benny, Gracie Allen,
Marian Jordan, Parkyakarkus, Jan Miner, Ona Munson, Charles Winninger, Bennett Cerf, Fay Wray, Ben Hecht,
George du Maurier, Gene Roddenberry). Led shows drawing the title block: at a 200 window 22 to 21, at 300
50 to 48 (the Jack Benny Program and Hilltop House). The rest have no larger file: 17 of the 22 at 200 would
fill if the clients' crop widened toward the largest square instead of the title block, a client rule.


## 022 — Display titles and names are derived from the data, and never reorder a series

*Date: 2026-10-30*

`episodes.title` and `series.name` are the display forms (`titles.display_title`, `display_name`); the
source's are kept in `raw_title` and `raw_name` where they differ, and search indexes both. Beyond the
2026-10-22 rules: a leading episode code (EP001, #257), a leading zero-padded number or run of numbers,
a duration (14m42s), a " - " part that is a code (32-22, xxxx) or a first part that is a lone number,
and the series' own name (two words or more, at the start before a separator or as a part) are stripped
where words remain. An all-capitals title takes the case the catalog's own mixed-case titles write each
word in (articles and short joining words lower), and a run-together word of ten letters or more is split
only when every piece is a word at least three titles spell on their own (three letters or more, a listed
two-letter word, never an acronym, never two short words in a row) and exactly one fewest-piece split exists.
A series whose order would change with a leading number dropped keeps the 2026-10-22 rules: with no date and
no number, "03 - Mrs. Hudson" is what lists it third. `sort_name` is the display name's key.

**Why**: the owner's catalog rule, no AI-written copy: a title is the source's words, so the rules only remove
and recase, and every word out is a word the raw title spelled. Upload habits put "EP001 TARZANSFIRSTBIRTHDAY",
"0005 - The Babe Ruth Collection - Harry The Hat - 32-22 - 14m42s" and "01 The Hobbit" on screen and at the
top of A to Z. A larger dictionary split real words ("BEAUTIES" to "Beau Ties", "CORSICAN" to "COR sic an",
"POSTTOASTIES" to "Post to as Ties"); each limit above is one of those refusals.

**How to apply**: `titles.py` (`Words` is built once per build from every title and name; no client
re-derives); `build_projection.py`; guards `tests/test_titles.py` (fixture vocabulary; four mutations seen
failing) and the contract checks in `tests/test_projection.py`. MEASURED on the 2026-10-29 caches: 3,125 of
107,190 served titles change beyond the 2026-10-22 rules (45 by a split), 902 of 10,641 series names, 41
series (794 episodes) keep the older rules for their order, and 116 all-capitals titles keep a long word
whole. Arcs: 451 to 455, the four new ones parts whose leading numbers had hidden a shared name ("Epilogue
Chapter 1, 2"). Known residue: a brand split on proven words ("MAYFIELD" to "May Field"), and a series named
for its work drops that name ("The Magic Flute - Mozart" to "Mozart").


## 023 — A display rule never deletes a letter, splits a spelled name, or drops a name said once

*Date: 2026-10-30*

Amends 022. On the iPad two Barbershop Quartet episodes read "ArbershopQuartet barbershopQuartet" and "Ouvenir
barbershopQuartet". The rules did not strip those letters: the archive.org files are named
`ArbershopQuartet_barbershopQuartet.mp3` and `Ouvenir_barbershopQuartet.mp3` (the item's own metadata title
reads "arbershop Quartet"), so the missing "B" and "S" are the source's and `raw_title` equals `title`. What the
rules owe the reader is only what the dictionary proves. Three changes: (1) a token with one lower-to-capital
hump is split when both halves (four letters or more) are words at least three titles spell on their own and
the whole is not spelled twice ("barbershopQuartet" waits for a third title to spell "barbershop"; "MacArthur"
stays whole); (2) a run-together split keeps joined any pieces a mixed-case title spells joined ("MAYFIELDCIGARETTES"
to "Mayfield Cigarettes", not "May Field Cigarettes"); (3) a series name is stripped from a title only when two
or more of that series' episodes carry it, so "The Magic Flute - Mozart" under the one-episode series "Magic
Flute" keeps its words.

**Why**: the owner's catalog rule, no invented words: a rule may remove and recase, and every word out is a word
the raw title spelled. "Mozart" lost the work; "May Field" split a name a title spells whole.

**How to apply**: `titles.py` (`Words.hump`, `Words._whole`, `Words.spelled`, `series_titles`); guard
`tests/test_titles.py` (five cases seen failing on the 022 code). MEASURED on the 2026-10-29 caches: 676 of
121,907 episode titles change from the 022 build (570 humps split, 106 series names kept) and 64 series names
(humps); no schema change, so no client change, and the apps see it with the next cache Release and catalog publish.


## 024 — Direction D's data: a genre from the records' own keywords, ranked voices, picture grades, and same-day as a query

*Date: 2026-10-30*

Four things direction D's design asked of the pipeline (`docs/research/design/directions/d/direction.md`, "Pipeline
work D needs"). (1) **A genre for a series no OTRRpedia label, RadioEchoes tag or LibriVox listing places**, only from
a word its own records carry: Wikidata's `genre` on an item matched on the years or the network, else the one genre
that more than half of the series' archive.org items name in their subject keywords or the genre tag of their default
copy's file (`genres.KEYWORD`, exact whole words; "drama" yields to a specific genre that also passes; two specific
genres, or none, leave it NULL). An item counts only when every served default copy in it belongs to the one series:
a day's broadcasts and a collector's compilation carry keywords for the item, not for any program in it (found by
looking: "NBC, WEAF, NY" read as a soap opera because its day-long item said so). A collection never counts
("audio_news" is where an uploader files everything that is not music: it put a Thanksgiving record show under
News). The source is stored: `series.genre_source` is `archive.org` or `wikidata:genre`. (2) **`voices`**, the 300 most
heard people, ranked by served episodes they are heard on (`art_policy.VOICE_ROLES`: on-air credits plus announcers
and commercial spokespeople; a writer or conductor is not a voice). (3) **`art.grade`**, `"k,o"` per picture, from
the luminance range of the picture inside the crop a slot shows (uniform-imagery-design section 2),
measured once (`measure_art_grade.py`, `.cache/art_grade.json`). (4) **`sameDay`** is not published: it is a
documented query (contract 3.3b).

**Why**: the owner's catalog rules (evidence or nothing; never a guess from a title) and the owner's picture rule
(2026-10-29: the pictures must read as one set). A genre only from the record, held to one program per item, loses
coverage and keeps the rule; a table of the other broadcasts that night costs 0.68 MB deflated for what an index
returns in 15 microseconds.

**How to apply**: `tools/enrich_genres.py` runs after `enrich_photo_archives.py` (the publish workflow does);
`build_projection.py` reads `series_genre`, `.cache/art_grade.json` (absent: no grades, every client takes the
identity) and writes `voices`; `build_web_projection.py` writes `index/voices.json` and the art arrays end with the
grade. Guards: `tests/test_genre_evidence.py`, `tests/test_projection.py` (voices, grade limits, same-day plan, each
with a broken control), `tests/test_web_projection.py`. MEASURED 2026-10-30 on the 2026-10-29 caches: of 8,519
served series with no genre, 1,543 get one (all `archive.org`; no unplaced series has a Wikidata genre) and 6,976
stay unassigned; of the 834 shows (five episodes or more) with none, 89 get one (47 drama, 14 science fiction, 13
mystery, 6 documentary, 5 comedy, 3 news, 1 serial), 745 stay on the neutral board; a version that let multi-series
items speak assigned 220 of the 834 and misread the day compilations, so the 131 it added are held back, not
guessed. Voices: 300 rows. Grades: 2,184 pictures measured, 1,461 graded (51 at the 1.6 cap), 723 the identity,
none unreadable. Size on the 2026-10-29 build: the app database 125,087,744 to 125,161,472 bytes (+74 KB) and its
download 25,433,689 to 25,463,104 (+29 KB, 0.12%); the web's `index/voices.json` 19.4 KB, 5.1 KB gzipped. A new
cache Release is needed for the grades (`art_grade.json` is a new harvest file); the genres and voices need none.


## 025 — Raw uploader text never reaches a display field: clean it from its source, compose it from data, or withhold it

*Date: 2026-10-31*

Audit: `audits/2026-10-31-display-text.md`. Owner, 2026-10-31: "I don't want raw text uploads to show at all. There is
no benefit to having raw text that is meaningless within the app ... Titles without context don't belong in the app ...
If it means writing with AI, based upon data, that is okay. The goal is to avoid AI writing titles that it doesn't know
(making them up)." Amends 022 and 023 (their protections stand: a rule removes and recases, never cuts a word) and the
"no AI-written copy" line (a title may be composed from the episode's own fields, never invented).

For every episode, in order: (1) the source's title, cleaned (`titles.py`, which now also drops rip tags, shelf and
track codes and doubled punctuation, and sets a title with no capital in the catalog's case); (2) a title composed from
data, "Series, April 26, 1952" (series name + air date) or "Series, episode 112" (series name + number), recorded with
the fields it used; (3) otherwise the episode is withheld from the apps. A series still named by an upload habit (a date,
an identifier, a file name, an uploader's grab bag, an item titled by an upload code) is withheld with its episodes.
Withheld rows stay in the research database untouched, with a reason code (`tools/display_text.py`; the build writes
`display_text.json` beside the projection and the counts into the projection's `meta.displayText`). Upstream, three
evidence rules (`tools/reattribute.py`, `build_db.improve_attribution`) put more of the catalog under a real name: a file
whose name BEGINS with a known program moves to it when the rest is a title that program has, or its own date is inside
the program's run (recorded in the episode's `identity.reattributed`); an unregistered series takes its name from the
item's own title when that spells the same letters, or from the ID3 album written on 80% of its files; a file's own ID3
title beats a title that only restates the file name. The parser also reads `YYYY MM DD` (spaces) as a date: it had read
"1959 10" as a series.

**Why**: the owner's catalog rule is no invented words, and her reading of it is that a meaningless raw string is worse
than a composed or absent one. The measured defects were uploader habits (297 series named for a date, 3,840 empty or
placeholder titles, 3,322 rip tags), not facts about the programs.

**How to apply**: a new display rule goes in `titles.py` with a fixture and a case seen failing; a new withhold reason in
`display_text.py` with a control; never read a file name, identifier or folder date into a display field. Guard:
`tests/test_display_text.py` (fixtures, and over `PROJECTION` the live artifact fails it: 297 date-named series).
`tests/test_reattribute.py`, `tests/test_titles.py`, `tests/test_otr_parse.py`. MEASURED on the 2026-10-29 caches, see the
audit for the table: series 10,641 to 8,740, episodes 107,190 to 103,027 (3.9%, so the publish needs a `shrink_reason`);
episode ids that changed are forwarded by recording (`forwarding.py`), no client change. A cache Release is not needed.
