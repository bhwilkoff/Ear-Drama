# R3b: Real images for every kind of Ear Drama, and where they can come from (research, 2026-11-19)

Research only. No app code, no catalog code, no publish changed. Measurement scripts and their
outputs are in `docs/research/data/r3b/` (`probe_sources.py`, stdlib only; responses cached under
`cache/`, which is gitignored). The drawn art for everything that stays without a picture is R3a's
track (`R3a-visual-cohesion.md`, "the label"). This doc covers the other half: finding real pictures.

The owner, 2026-11-19: *"We have very few images that represent only a few Ear Dramas (radio shows,
plays, news programs, and real recorded Ear Dramas). We need to do much better research for images
and designs that could represent all of the different Ear Dramas throughout the app. On Archive Watch,
we pull 'hero images', posters, and many other types of visual representations of the movies. We
should be able to do that for this app too (from wikipedia or any other public repository)."*

The binding rules this doc works inside (AGENTS.md "Ear Drama's catalog rules", catalog DECISIONS
017-021, app DECISIONS 055/069): **an image is used when its own record carries the evidence, with
no review queue**; no paid license; a title alone is no identity; an uploader's word is not evidence
(`evidence-gated-catalog-curation` §2, §7); graphics count as much as photographs (owner,
2026-10-28); the box takes the image's shape (`artwork-presentation-design`).

---

## 0. Verdict

1. **Archive Watch's art waterfall doesn't carry over.** TMDb, Fanart.tv, OMDb and TheTVDB
   have no radio, and their posters are studio marketing art whose own record carries no free
   license, so they fail the catalog rule. What does carry over is the shape: a ranked waterfall,
   matching on a strong id, liveness checks, and art shown at its own aspect (§2).
2. **For radio, the open web has few free pictures, and the pipeline already has most of them.**
   The top 300 shows by downloads are measured below. 36% wear a picture today. With every
   open source in this doc, about **37%** would wear a picture, and about **13%** (up from 6%)
   would wear a picture *of the show* rather than a star. The 100 random shows found **0** images
   from any source. Commons' network publicity categories hold only 75 CBS and 71 NBC radio files
   (§4.1).
3. **The best source by far is Commons by name**: 27 of the top 100 shows have a file that names
   the show, carries PD/CC evidence and is dated inside the run, at **86% precision** (§4.1, §4.3).
   The next lever is a rule question, not a source. 87 of the 124 Wikidata items found for the top
   300 are undated radio stubs. Their enwiki articles carry the run's years, and reading them from
   there would make most of these items servable (V10).
4. **Plays are the easy case.** Of 50 sampled, **88%** can have a real image: 70% have a scanned
   edition dated 1930 or earlier on archive.org, 56% an author portrait with evidence, and 10% a
   Wikidata work image. Precision is 91% on the editions (§4.2).
5. **Some sources set aside:**
   - **Wikipedia infobox images**: 57% of radio articles' lead images are local non-free files.
   - **LoC search by show name**: 0 of 35 usable hits were the right subject.
   - **Openverse and Europeana**: no usable evidence.
   - **Modern corporate logos**: nearly every network and sponsor P154 is a present-day logo.
     Period advertisements (Lux 24, Lucky Strike 12, Chesterfield 10 on Commons, no notice) are
     the better sponsor picture.
6. **Most of the catalog stays drawn.** The long tail, every user-made ear drama and most news
   rows go to R3a's label, so the label should be built as the default artwork (§6). Owner
   answers V2-V5 (LoC, Federal Theatre Project, NPG, magazine pages) are the largest untapped
   pools. V7-V10 are new: a CDN mirror, logos, user pictures, and enwiki years (§7).

---

## 1. What the pipeline does today

Ear Drama already has a careful, evidence-gated picture pipeline. It is narrow because it was built
for **people**, and show art reaches it only through Wikidata.

| Stage | File (`catalog/tools/`) | What it does |
|---|---|---|
| Wikimedia client | `harvest_ext_wm.py` | Polite, caching client for SPARQL, the Action API, enwiki and Commons. Its UA names the project and its site, which is what Wikimedia's policy asks for (§4.0). |
| Radio items | `harvest_ext_wikidata.py` | Every Wikidata item typed radio program (Q1555508) or a subclass, plus enwiki's American radio categories: 9,851 items (local cache, 2026-10-19). Matched to our series in `enrich_external.py` (`series_wikidata`). |
| Commons radio files | `harvest_ext_commons.py` | The NBC/CBS/ABC/Mutual/Blue publicity-photo categories, a CirrusSearch for PD templates inside `deepcat:"Radio programs from the United States"`, and the P18/P154 and P373 category of each radio item. 2,004 files in the 2026-10-19 cache. Records the file page's license template and `|source=` links; never judges the scan. |
| People | `harvest_people_wikidata.py`, `enrich_people_art.py` | Credited people to Wikidata humans, matched on an agreeing birth or death year (the undated rule is not served, RESEARCH §12 V1); each matched person's P18 page read for its license class; width/height (`--phase dims`); face boxes from Apple Vision (`face_boxes.swift`, `--phase faces`). |
| Show pictures | `harvest_series_art.py`, `enrich_series_art.py` | For a series matched to Wikidata: the item's P18, P154, P3383, P2716, P6802, files whose Structured Data depicts the item (P180), and files in its P373 category; license class re-read; faces. |
| Policy | `art_policy.py` | The one predicate. Served license classes: `pd_us`, `pd_us_gov`, `cc0`, `pd_release`, `free_use`, `cc_by`, `cc_by_sa`. A show image needs identity beyond the title (years ±2 or the network, DECISIONS 017), no television in its item or file, a shorter side of 160 px, no own date outside the run, and no own-work license its date contradicts (019). Crop, `fill_px`, the 300 px floor and the one-face stand-in (021). One face per star (018). |
| Other archives | `harvest_loc_photos.py`, `harvest_smithsonian.py`, `photo_match.py`, `enrich_photo_archives.py` | Library of Congress P&P (12,091 records, 5,116 usable on their own rights statement) and Smithsonian Open Access (14,671 CC0 NPG portraits). **Matched to 179 people, served to none**: RESEARCH §12 V2 (LoC "no known restrictions") and V4 (NPG CC0) are open owner questions. Track F found **no usable series photograph**: every LoC print naming a show is a World-Telegram or Look file marked "Publication may be restricted". |
| Magazines | `harvest_magazine_rights.py` | Radio Guide, Radio Mirror, Radio Stars, Tune In and others: where the scans are (worldradiohistory PDFs, archive.org MHDL) and each title-year's renewal status from the Online Books Page and our own CCE reading. Not served (V5). |
| Grade | `measure_art_grade.py` | Tonal levels inside the crop, so mixed photos read as one set. |

**What reaches the projection** (live manifest, 2026-11-19): 4,842 series, of which **303 wear a
picture**: 255 a star's portrait, 47 a show image, 1 the heard-most person (285 carry the `art`
array). 2,144 people portraits; 158 of the 300 `voices` have one. Plays, networks, sponsors and
episodes carry no image field at all. Every served file is hot-linked through Commons'
`Special:FilePath`, with its file page as the `evidence` URL and a `credit` where the license needs one.

The ceiling is visible in DECISIONS 017's own measure: "coverage is bounded by Wikidata: 268 of the
2,036 shows match an item at all." Everything below is about raising that ceiling without
loosening a rule.

---

## 2. Archive Watch's image pipeline, and what carries over

Archive Watch (`/Users/bhwilkoff/Documents/GitHub/Archive-Watch/tools/`) runs a waterfall of
**designed marketing art**, each pass filling only what earlier passes left
(`enrich_artwork.py`): TMDb `/find/{imdb_id}` (poster, backdrop, cast) → Fanart.tv (community
posters, key) → OMDb (Amazon-hosted IMDb poster, key) → the LoC record's own poster → Wikidata P18
in batches by archive id → TMDb title+year search. Then `resource_posters_tmdb.py` re-sources rotted
or frame-still posters by the stored IMDb/TMDb id (year ±2 corroboration, B&W vs 1970+ guard);
`resource_posters_secondary.py` reaches films TMDb lacks via TheTVDB, the **enwiki film infobox
`| image =`** (preferred over P18, because Nosferatu's P18 is a photo of Wismar market square) and
Wikidata P18; `fill_backdrops_tmdb.py` adds the TMDb backdrop as the hero; `enrich_cast_images.py`
fills cast photos from TMDb person search; `frame_cover.py` makes a last-resort cover from the
video's own frames; `validate_posters.py` demotes dead URLs (62% of OMDb posters had rotted).
Decision 097: the hero fits the art at its own aspect.

| Archive Watch piece | Here? | Why |
|---|---|---|
| TMDb / Fanart.tv / OMDb / TheTVDB posters, backdrops, cast photos | **No** | Film and TV only (radio is not in them), and the art is the studios' copyrighted marketing material used under each API's terms. Its own record carries no free-license evidence, so it fails Ear Drama's catalog rule outright. |
| Frame covers from the video | No | Audio has no frames (06-archive-watch-reuse already said: no spectrogram art). R3a's label is the counterpart. |
| Wikidata P18 by stored id | **Yes, already** (`harvest_series_art.py`) | Same idea; Ear Drama adds the license read and the identity check AW does with years. |
| Infobox-before-P18 for the lead image | **Partly** | The enwiki lead image is the right *candidate*, but on radio articles it is often a local non-free file (§4.2), which is not evidence. Use it only when the file lives on Commons with a free class. |
| Year ±2 corroboration, B&W-vs-modern guard | **Yes, already** (DECISIONS 017 years/network, the television rule) | The same reject-on-contradiction shape. |
| `validate_posters.py` liveness + TTL | **Yes, adapt** | Commons files get deleted and renamed; a served file needs a liveness check and a durable "wants" marker (06 §ADAPT). |
| Two-tier image CDN (thumbs/full) | **Yes, new** | Today every picture is a hot-linked `Special:FilePath` redirect (§3, hotlinking). |

So the transferable part of Archive Watch is the **shape** (a ranked waterfall of sources, strong-id
matching, liveness, art at its own aspect), not its sources. Radio's equivalent of "the poster" is
the network press photograph, the program's title card or logo, and the period magazine page, and
those live in public-domain archives, not in commercial databases.

---

## 3. Sources, and the evidence each one's own record carries

"Evidence" means the field on the image's **own** record that a reader can open and that states its
status. Where a source only relays someone else's word, it says so. Rate limits marked *measured*
were observed from this machine on 2026-11-19 with the research UA (`EarDramaResearch/1.0`, no
contact details); the others are the source's published terms as of my knowledge, to re-read before
a production harvest.

| Source | API | Evidence on the record | Rate limit | Attribution | Hotlink / CDN | Kinds it serves |
|---|---|---|---|---|---|---|
| **Wikidata** | `wbgetentities` (50 ids a call), `wbsearchentities`, SPARQL `query.wikidata.org` | None for the image itself: Wikidata is CC0 data that *points* at a Commons file (P18 image, P154 logo with P580/P582 dates, P3383 poster, P2716 collage, P6802 related image, P996 scanned document, P373 Commons category). The evidence is the Commons file page. | *Measured*: SPARQL answered `429 "Aggressively rate-limiting to 1 req / min - this rule was created during active wdqs outage"` with Retry-After up to 1,000 s; the Action API 429'd after a few calls at 1.5 s spacing (Retry-After 5-20 s). | None (CC0) | n/a | Identity and the image pointers for series, networks (P154), sponsors (P154), people (P18), plays and authors (P18, P996) |
| **Wikimedia Commons** | Action API `imageinfo` with `extmetadata` (40-50 titles a call), CirrusSearch (`list=search`, `incategory:`, `deepcat:`, `haswbstatement:P180=Q…`), `categorymembers` (500 a call) | The license template on the file page, readable as `extmetadata.License`, `LicenseShortName`, `Copyrighted`, `NonFree`, `Restrictions` (e.g. `trademarked`) and the hidden license categories in `extmetadata.Categories` (`PD US no notice`, `PD US not renewed`, `PD-USGov…`, `CC-BY-SA-4.0`). A PD-US template states its reason (no notice, not renewed) and usually links the source (the back of the print, the CCE). | *Measured*: 429 with Retry-After 30-45 s once several requests were in flight; serial at one per 1.5-3 s mostly works. | Per license: none for PD/CC0; author + license + link for CC BY / BY-SA (already in `art_policy.credit`) | Hotlinking `upload.wikimedia.org` is allowed but it is a shared, rate-limited service; Wikimedia now serves a fixed ladder of standard thumbnail widths best, so ask for those. Better: copy the bytes to our own CDN (`image-cdn-discipline`); free licenses permit it. | Press photos, title cards, logos, ads, magazine covers, portraits, play scans |
| **English Wikipedia** | REST `page/summary/{title}` (`originalimage`); Action API `prop=pageimages|pageprops` (50 titles a call; `pageprops.page_image_free` names the lead image only when it is free) | The lead image's own file page. **A file under `upload.wikimedia.org/wikipedia/en/` is local to enwiki and is usually non-free (fair use)**: not evidence, never served. Only Commons-hosted lead images count. | *Measured*: the Action API 429'd (Retry-After 16-20 s) after two quick calls; REST summary throttled after a burst. | As Commons | As Commons | Candidate show images and identity (the article's description carries years) |
| **Library of Congress** (loc.gov) | JSON: any loc.gov URL + `fo=json`; `/photos/?q=…&c=50&at=results,pagination`; item JSON lists every file incl. the TIFF; IIIF image server | `rights_advisory` on the record, verbatim: "No known restrictions on publication" (Bain, Harris & Ewing, Gottlieb, FSA/OWI) vs "Publication may be restricted" (World-Telegram, Look, NBC prints). `photo_match.rights_class` already classes it. | Published: 20 requests/min with a one-hour block that restarts on any request during it. *Measured*: responses take 5-50 s each, so ~1-3 a minute in practice. | LoC asks for a credit line: "Library of Congress, Prints & Photographs Division, [collection], [reproduction number]" | IIIF / `tile.loc.gov` URLs are stable; mirror to our CDN rather than hotlink a slow server | Stars at the microphone, studios, government radio (OWI), news subjects (FDR, Elmer Davis), Federal Theatre Project productions |
| **NYPL Digital Collections** | `api.repo.nypl.org` v2 | Per capture: a rights statement and a public-domain flag; NYPL's public-domain release marks items it believes are PD in the US. | Needs a token (*measured*: "HTTP Token: Access denied" without one); 10,000 calls/day on a token. | Requested, not required, for PD items | Image URLs are stable; mirror | Billy Rose Theatre Division: playbills, production photos, radio stars, stage play first editions |
| **Smithsonian Open Access** | `api.si.edu/openaccess/api/v1.0/search` (api.data.gov key; *measured*: `DEMO_KEY` answered today, it was over limit on 2026-10-21) or the keyless S3 bulk files Track F already reads | Each media item's own `usage.access`: `CC0` vs "Usage conditions apply" | api.data.gov: 1,000/hour on a real key, DEMO_KEY 30/hour | None (CC0) | `ids.si.edu` delivery URLs; mirror | NPG portraits (114 of our people), a few radio objects |
| **DPLA** | `api.dp.la/v2/items` | `rights`: a rightsstatements.org or CC URI from the contributing institution (DPLA relays it; the institution's record is the evidence) | Needs an API key requested with an email address (*measured*: `invalid_api_key`) | Per item | Thumbnails are the provider's; link to the provider's record | Aggregates state archives and libraries: local radio stations, regional performers |
| **Flickr Commons** | `flickr.photos.search` with `is_commons=true` | The institution's "No known copyright restrictions" flag on the photo | Needs an API key (*measured*: "Invalid API Key") | Per institution | Flickr allows embedding with a link back; mirror | Mostly the same institutions (LoC, Smithsonian, national archives) already reachable directly |
| **Openverse** | `api.openverse.org/v1/images/` (anonymous, throttled; OAuth for more) | `license` per result, but Openverse states it does not verify licenses: for a Flickr result it is **the uploader's own choice**, i.e. an uploader's word | Anonymous: low burst and daily caps | Per license | Links to the source | Little: see §4.6 |
| **Europeana** | `api.europeana.eu/record/v2/search.json` (`wskey`; the public `api2demo` key worked) | `rights` (edm:rights URI from the holding institution: PDM, CC0, CC BY …) with `reusability=open` | Free personal key by email | Per license | Provider URLs | European collections; almost no American radio (§4.6) |
| **Internet Archive scans** (Radio Guide, Radio Mirror, Radio Life, Broadcasting Yearbook, first editions of plays) | `advancedsearch.php`, item metadata, IIIF (`iiif.archive.org`) and BookReader page images | Item fields `possible-copyright-status`, `licenseurl`, `rights`, and `date`. **The MHDL `NOT_IN_COPYRIGHT` field is wrong for Radio Mirror 1944-1963** (Track F): the evidence must be the issue-year's renewal record (`magazine_rights`), or a publication year of 1930 or earlier, which is PD in the US by age. | No published cap; keep to ~1 req/s | None for PD | Page images are stable; mirror the one page used | Magazine covers and photo pages (V5), play title pages |
| **Old Time Radio Researchers** (OTRR) sets and archive.org cover art | archive.org items | The uploader's license for the item, nothing about the image. | | | | **Not a source** (catalog DECISIONS 017: 26 of 60 sampled shows had uploaded art with only the uploader's word) |
| **Project Gutenberg covers** | `cache/epub/{id}/pg{id}.cover.medium.jpg` (listed in every book's RDF) | "Public domain in the USA" on the ebook record. Most covers are Gutenberg's own generated typographic covers; a scanned original appears only where the transcriber kept it, and the RDF does not say which. | *Measured*: gutenberg.org answered 503 "Temporarily Down for Maintenance" with Retry-After 21,600 s all afternoon | None | Mirror if ever used | A generated cover is typography, the job R3a's label already does better; not a picture source |
| **Folger Shakespeare Library** (LUNA / Miranda) | Collection search per record | A license statement per image (Folger publishes much of its digital image collection under CC BY-SA) — re-read the record before use | Not measured | CC BY-SA credit | Mirror | Shakespeare (41 of our 803 plays) and early modern drama: quarto/folio title pages, playbills |
| **HathiTrust** | Bibliographic API (`catalog.hathitrust.org/api/volumes/…`), page images | The rights code on the volume record (`pd`, `pdus`) from HathiTrust's copyright review | Not measured | None for pd | Page images downloadable for pd volumes | Play first editions where IA has none |
| **NARA catalog / presidential libraries** | `catalog.archives.gov` API (key) | Use restriction "Unrestricted" on the record; federal works are PD-USGov | Key required (V6) | Courtesy credit | Mirror | Speeches and wartime news: FDR, Truman, OWI |


---

## 4. Measured coverage and precision

### 4.0 Sample and conditions

- **Series**: the top 300 by `downloads` from the live `index/series.json` (2026-11-19), 100 drawn at
  random from the rest (seed 20261119), and the 40 most-downloaded news and documentary series. The
  live baseline: **108 of the top 300 (36%) wear a picture today** (90 star, 17 show, 1 person), **4 of
  the random 100 (4%)**, 6 of the 40 news/documentary (15%).
- **Plays**: 50 drawn at random from the 803 in `plays/library/index.json` (799 stage, 4 radio; all
  Project Gutenberg).
- **Wikimedia throttled this research UA hard.** With no contact address in the UA (as briefed),
  the query service applied an outage rule of one request a minute (Retry-After up to 1,000 s), and
  the Action APIs answered 429 with Retry-After 15-50 s after a few calls. The probe therefore batched
  (one SPARQL `VALUES` lookup of 1,058 name variants in 5 requests; `wbgetentities` and `imageinfo`
  50 at a time; enwiki pages 50 titles a call) and **measured the Commons per-name search and the LoC
  search on sub-samples** (Commons: top 100 and 50 random; LoC: top 60 and 15 random). Every
  denominator below says which. A production harvest should keep `harvest_ext_wm.UA` (it names the
  site), which is what Wikimedia's UA policy asks for.
- **Matching** follows DECISIONS 017: exact label or alias; "strong" means the item's years overlap
  ours ±2 or its broadcaster is our network; "title-only" is counted but would never be served.
- **Evidence** is the license class read from each file's own Commons page (`extmetadata` and its
  hidden license categories): `pd_us`, `pd_us_gov`, `cc0`, `pd_release`, `cc_by`, `cc_by_sa` count;
  `pd_other` (e.g. PD-old-70 alone, not a US reason), `loc_nkr` (Commons files whose only statement
  is LoC's "no known restrictions", owner V2), `pd_textlogo` (logos, V8) and enwiki-local files do not.

### 4.1 Series: % with at least one evidence-carrying candidate image, by source

| Source (route) | Top 300 | Random 100 | News/doc 40 |
|---|---|---|---|
| Live today (any picture) | 108 (36.0%) | 4 (4.0%) | 6 (15.0%) |
| Live today (a show image) | 17 (5.7%) | 0 | 0 |
| Wikidata: item found by exact name | 124 (41%): 35 years, 2 network, 87 title-only | 8: 1 network, 7 title-only | 3 title-only |
| Wikidata: image statement with evidence (any identity) | 16 (5.3%) | 0 | 0 |
| Wikidata: same, strong identity (servable today) | 5 (1.7%) | 0 | 0 |
| Wikipedia: article found (sitelink or radio-titled page) | 132 (44%) | 8 | 4 |
| Wikipedia: free Commons lead image, strong identity | 8 (2.7%) | 0 | 0 |
| Commons search, name in file title/categories + evidence | 33 of top 100 | 3 of 50 | 2 of 40 |
| **Commons search, + file dated inside the run ±2** | **27 of top 100 (27%)** | **0 of 50** | 1 of 40 |
| LoC photos, usable record naming the show | 0 of 60 | 0 of 15 | 0 of 4 |
| LoC photos, a record naming the show that is restricted | 6 of 60 | 1 of 15 | 1 of 4 |
| Openverse, title names the show (any license) | 9 of 60 (2 right subject, 0 with evidence) | | |
| Europeana, title names the show | 8 of 60 (0 right subject) | | |
| News/doc subject is a person with an evidence portrait | | | 1 of 40 |

**Union, top 300, after the precision check (§4.3)**: 37 series have at least one right-subject,
evidence-carrying show-level candidate. Only **4 of them have no picture today** (Sherlock Holmes
1932, Columbia Workshop, Suspense, NBC News); 19 wear a star portrait today and would gain a picture
of the show itself (a cast photo, a press still naming the program); 14 already wear a show image.
So the open sources move the top 300 from 36% to about **37%** with any picture (112), and from 5.7%
to about **13%** (40) with a picture *of the show*. The random 100 (the long tail) gained **nothing from any source**.

Two findings explain the numbers:

1. **The free picture universe for old-time radio is thin, and the pipeline already holds most of
   it.** Commons' network publicity categories hold **75 CBS Radio, 71 NBC Radio and 3 ABC Radio
   files** today (`categoryinfo`, 2026-11-19); Mutual and Blue have no such category. Most of what the
   by-name search found is already a served star portrait.
2. **The identity rule, not the supply, is the biggest lever on the head.** 87 of the 124 Wikidata
   items found for the top 300 are radio stubs with no dates and no broadcaster ("US radio program"),
   so the years/network rule cannot pass them; 11 of the 16 Wikidata image statements sit on such
   items. Their enwiki articles usually carry the run in the short description or infobox
   ("American radio docudrama series (1953–1954)"). Reading the years from the item's own enwiki
   article (§5.2, H1) would make most of these servable without loosening the rule's logic.

**Wikipedia lead images**: of the 138 articles reached, 70 have a lead image, and **40 of those 70
(57%) are enwiki-local non-free files** (fair-use title cards and publicity stills). PageImages
returns only free lead images by default (`pilicense=free`), which is why the first pass saw only
the 30 free ones. The infobox image Archive Watch prefers is, for radio, usually the one we may not use.

### 4.2 Plays (50 of 803)

| Route | Plays | Share |
|---|---|---|
| Work item found on Wikidata (title + author in P50 or description) | 16 | 32% |
| Work item image with evidence (P18: frontispiece, title page, production photo) | 5 | 10% |
| Free Commons lead image of the play's enwiki article | 7 | 14% |
| **Scanned edition on archive.org dated 1930 or earlier** (title + author surname) | **35** | **70%** |
| Any work-level image (any of the three above) | 38 | 76% |
| Author matched to a Wikidata human | 44 | 88% |
| Author portrait (P18) with evidence | 28 | 56% (3 more are LoC "no known restrictions" only, V2; 6 more PD-old without a US reason) |
| **Any image (work-level or author)** | **44** | **88%** |
| Gutenberg cover | not measured | gutenberg.org was down for maintenance (503, Retry-After 6 h) all afternoon; covers are mostly generated typography anyway |

Plays are the opposite of radio: they are old enough that almost everything is public domain by
age, and the evidence is the publication date on the scan's own record. Examples found: Chantecler's
P18 is a 1911 Broadway production photograph of Maude Adams (LoC), The False One's frontispiece,
Tartuffe's 1739 English edition, Timon of Athens and Major Barbara images, Hecuba's Latin edition,
and a 1910 pictorial edition of Chantecler on archive.org. The Library of Congress search also
surfaced **Federal Theatre Project production photographs** of stage plays (The Show-Off, 1934;
Whistling in the Dark, 1934): a real source for play pictures, behind owner question V3.

### 4.3 Precision: wrong subjects, judged by eye on title, caption, categories and years

| Route | Judged | Right subject | Wrong (and why) |
|---|---|---|---|
| Commons by name, dated in run (top 100 + news) | 28 series | **24 (86%)** | The Saint: a photo of Italian journalist Gianni Bisiach; Franklin D Roosevelt: a Federal Art Project radio photo and "Girl listening to radio"; Father Knows Best: a `.ogg` audio file (needs a mime filter); Dragnet: a Dutch photograph whose caption contains "dragnet" (its "Dragnet promo card" is uncertain radio vs TV) |
| Wikidata image statements | 16 series | 13 (81%) | The Cisco Kid: the item is the fictional character, the photo a 1950s TV still; Perry Mason: a file dated 2009 (a book/radio composite); A Day in the Life of Dennis Day: a 1960 photo, after the run (the date rule refuses it) |
| Wikidata title-only items (no image needed to be wrong) | 15 read | 13 | Escape → a Sirius XM channel; Case Closed → a podcast |
| LoC usable records found by name | 35 records | **0** | The Saint → the 1904 St. Louis World's Fair; Escape → Air Force launch facilities; The Whistler → FTP's "Whistling in the Dark" |
| Openverse by name | 9 | 2 (X Minus One, Our Miss Brooks: uploaders' own CC choices, one non-commercial) | Gunsmoke → a film set; Great Gildersleeve → 1942 film frames; Dragnet, The Saint, The Whistler → unrelated; "Dark Fantasy" → a reposted 1943 OWI photo whose Flickr caption borrowed the title |
| Europeana by name | 8 | 0 | Every hit is the common noun (a dragnet, a "Suspense" print, Box 13 as an address) |
| Plays: work items | 16 | 15 | In Honour Bound → a 1925 radio play, not Grundy's 1885 stage play |
| Plays: first pre-1931 archive.org scan | 35 | 32 (91%), of which about 8 are collected editions | A Duologue → a different Sutro duologue; Tartuffe → "Ninon, Molière et Tartuffe" (1815); The Humourous Lieutenant → an unrelated 1800 item |
| Organizations by name | 50 | 48 | NPR → National Prison Radio (UK); AT&T → Aircraft Transport and Travel |

Lessons, each turned into a rule in §5.2: a title is a common noun more often than not (Escape,
Suspense, The Saint, Dragnet, The Whistler); TV and film twins sit beside radio files; a file's own
date catches what a name cannot; a search engine matches captions, so the name must be in the file's
own title or categories; organizations must be matched by QID.

### 4.4 Image shapes (the box takes the image's shape)

| Set | Portrait | Landscape | Square |
|---|---|---|---|
| Series, Commons by-name files | 39 | 14 | 5 |
| Series, Wikidata image statements | 10 | 5 | 1 |
| Plays, author portraits | 32 | 2 | 2 |
| Plays, work images | 1 | 3 | 1 |

About a quarter of show images are landscape. A wide hero for every show is not on offer: most press
photographs are upright 8x10s. `series.hero` (§5.5) is therefore optional, and the page header keeps
`artwork-presentation-design`'s upright print beside the heading.

### 4.5 Networks, sponsors, episodes, people

- **Networks** (13 distinct items for 15 names; 1 wrong): 10 carry a logo (P154); their files are
  23 `PD-textlogo` and 13 `pd_us`. **Nearly every logo is modern** (ABC 2013/2021, NBC 2022, BBC 2021,
  CBC 1992): only the Blue Network's and the "CBS classic" logo are of the period; Mutual and NBC Red
  have none. Only ABC, NBC and a few sponsors date their logos with P580/P582. A period network mark
  needs a Commons search of the era's files (e.g. NBC chimes and microphone flags in the publicity
  photos), not P154.
- **Sponsors** (35 names; 25 matched, 1 wrong; 20 with P154): again modern logos (27 `PD-textlogo`
  files). The better sponsor picture is the **period advertisement**: Commons holds no-notice ads that
  name the brand (search `"<brand>" advertisement incategory:"PD_US_no_notice"`): Lux 24, Lucky
  Strike 12, Chesterfield 10, Maxwell House 8, Jell-O 4 (one is a 1937 Life ad with Jack Benny),
  Wildroot 0. Those carry their own evidence (an ad with no notice) and often a radio star.
- **Episodes**: not measured live. Wikidata's radio-episode class holds 5,620 items worldwide in the
  catalog's own cache (2026-10-19), mostly not American radio; an episode keeps wearing its series'
  picture, and `episode.picture` stays NULL except where an episode item has its own image.
- **People**: 2,144 portraits served; 158 of the 300 voices have one. Track F already matched 179
  more people to LoC/NPG photographs that are not served (V2, V4).

### 4.6 Sources measured and set aside

Openverse and Europeana add almost nothing for American radio and carry no evidence we can use
(Openverse relays an uploader's license; Europeana's hits were common nouns). DPLA, NYPL, Flickr and
NARA need keys the owner would have to request (V6). The OTRR and archive.org cover art remain out
(DECISIONS 017).

---

## 5. Harvest plan

The plan adds sources and slots; it changes no rule. Every stage writes a cache (resumable), every
image row records **where it was found, how it was tied to the thing, and the evidence URL**, and
`art_policy.py` stays the one predicate every builder imports. Stages are ordered by measured yield
per request.

### 5.1 Stages

| # | Stage | Source | New tool (proposed) | Feeds |
|---|---|---|---|---|
| H1 | **Wider identity.** Look series up by every name variant in one SPARQL `VALUES` batch (label or alias, `The`/no-`The`, `&`/`and`) as well as the radio-class harvest, and take an enwiki article's `wikibase_item` when the article's own short description names radio and years | Wikidata, enwiki `pageprops` | extend `harvest_ext_wikidata.py`, `enrich_external.py` | every later stage |
| H2 | **Show images from the item** (today's stage), plus P996 for plays and dated P154 for networks/sponsors | Wikidata → Commons | `harvest_series_art.py` (exists) | `series.picture` (kind show) |
| H3 | **Commons lead images of the enwiki article**, only when `page_image_free` is set and the file is on Commons | enwiki → Commons | new phase in `harvest_series_art.py` | `series.picture`, `series.hero` |
| H4 | **Commons by name**: CirrusSearch `"<series name>" incategory:"PD US no notice"` (and `not renewed`, `PD-USGov`, `CC-BY*`), plus the publicity categories crawled by `categorymembers` | Commons | extend `harvest_ext_commons.py` | `series.picture`, `series.gallery` |
| H5 | **Archive photographs through people** (owner V2/V4): an LoC/NPG photograph of the matched star at a microphone becomes the series' star picture when the person rule already picked that star | LoC, Smithsonian | `enrich_photo_archives.py` (exists) → `art_policy` | `series.picture` (star), `person.art` |
| H6 | **Organizations**: networks and sponsors matched by QID (a hand-kept QID table is data with sources, not curation), P154 with P580/P582 so a 1940s show gets its 1940s logo | Wikidata → Commons | new `harvest_org_art.py` | `networks[].logo`, `sponsors[].logo` |
| H7 | **Plays**: the work's P18/P996, its author's P18 (dated person match, as for radio people), and a pre-1931 scanned edition's title page | Wikidata, Commons, archive.org, HathiTrust | new `harvest_play_art.py` | `play.titlePage`, `play.authorArt` |
| H8 | **Magazine pages** (owner V5): an unrenewed issue's cover or a photo page naming the show, from an issue whose title-year is `not_renewed` or `pd_by_age` in `magazine_rights` | archive.org MHDL, worldradiohistory scans | new `harvest_magazine_pages.py` | `series.gallery` |
| H9 | **Liveness and mirror**: HEAD every served file on a TTL; copy each served image to the app's CDN at two tiers; a deleted Commons file falls back to the next candidate, never to a broken box | our CDN | port of AW `validate_posters.py` | all |

### 5.2 Matching rules (reject wrong subjects before they are counted)

1. **A title is never enough.** A series↔item tie needs the item's own years (P580/P582/P571 or
   years in its description) to overlap our run ±2, or its broadcaster (P449) to be our network
   (DECISIONS 017). Title-only matches are measured (§4) and never served.
2. **Television, film and adaptations are refused** on the item (description or P31) and on the
   file (name, categories). The same words recur: Gunsmoke, Dragnet, Our Miss Brooks, The Life of
   Riley and The Great Gildersleeve all have TV or film twins whose stills sit next to the radio
   photos.
3. **The file's own date must sit inside the run** (±2) or before the earliest marked star's death
   (019); a 1914 photograph of a hotel is not Hilltop House.
4. **A topic is not a show.** A P18 that depicts the program's subject (Hello Americans' P18 is an
   orthographic map of the Americas; a news program's P18 is often its host's city) is refused
   unless its categories or caption name the program or a marked person. Rule: a show image needs
   the program's name, a marked person's name, or the network's publicity category in the file's own
   name or categories.
5. **A depicts file is a group until one face says otherwise** (021): it may lead only through the
   one-face rule.
6. **Commons search hits need the name in the file's own title or categories**, not just in the
   description the search engine matched, and the dated check in 3.
7. **Organizations match by QID, not by name**: "Blue" and "Mutual" are words before they are
   networks; the sponsor table's names ("Philip Morris and Company (Cigarettes)") are normalized to
   a QID table kept in the repo with each row's source.
8. **Plays**: the work item must name one of our authors in P50 (or its description must), and an
   edition scan must be a dated text item whose creator field holds the author's surname. A
   collection ("The Best Known Works of Ibsen", 1940) is not a first edition.

### 5.3 The evidence each image carries

Each published art row keeps today's shape `[url, width, height, credit, evidence, face, grade]`
and adds nothing a client must interpret, except that `evidence` may now point outside Commons:

| Source | `evidence` URL | Class required |
|---|---|---|
| Commons | the file page | `pd_us`, `pd_us_gov`, `cc0`, `pd_release`, `free_use`, `cc_by`, `cc_by_sa` (unchanged; `pd_other` such as PD-old-70 is refused, it is not a US reason) |
| LoC | the item page (`loc.gov/pictures/item/…`) | `no_known_restrictions` or `government` (V2, V3) |
| Smithsonian | the record page | per-media `CC0` (V4) |
| archive.org magazine page | the item + `magazine_rights` row | issue-year `not_renewed`/`pd_by_age`, and no separate notice on the page (V5) |
| archive.org / HathiTrust play edition | the item + its date | published 1930 or earlier (PD in the US by age) |
| A logo | the file page | a free class, or `PD-textlogo` (V8; trademark is a separate question from copyright) |

### 5.4 Focal points and crops: reuse, don't redo

`face_boxes.swift` and `art_policy.crop_rect` already compute a face box once in the pipeline for
portraits and show images; every client crops from it. Extend the same `face` field to every new
row: press photos (one or more faces; the box of the marked star, else the union), magazine covers
(the cover face), title pages and logos (no face: `face` NULL, and the client fits rather than
crops, as `artwork-presentation-design` requires for type and graphics). Grades (`measure_art_grade`)
run on the same crop. No client ever computes a crop.

### 5.5 Where it publishes (proposed projection fields)

Additive, `schemaVersion` stays 1, each field NULL when nothing passes. Proposed for the contract
(`docs/CATALOG-CONTRACT.md` §3.3a) and the web manifest's `fields`:

| Field | Meaning | Shape |
|---|---|---|
| `series.picture` | unchanged: the one image that leads the show (show → star → person) | art row |
| `series.hero` | a **landscape** show image (aspect > 1.15) for page headers and Home's lead, when one passes; never a portrait stretched | art row |
| `series.titleCard` | the program's own logo, title card or sponsor-period ad (graphics: fit, never crop) | art row |
| `series.gallery` | up to 6 further passing show images (press photos, magazine pages), each with its own evidence | art rows |
| `networks` index: `logo`, `logos[]` | the network's P154 file(s) with `from`/`to` years, so a row can show the logo of the episode's year | `{qid, name, logo: art row, logos: [[from, to, art row]]}` |
| `sponsors` index: `logo` | the sponsor's period logo or a no-notice ad | as networks |
| `episode.picture` | NULL by default: an episode wears its series' picture; filled only when Wikidata has an episode item with its own image (rare, §4.5) | art row |
| `play.titlePage` | a scanned title page or first-edition cover | art row |
| `play.authorArt` | the playwright's portrait (dated person match) | art row |
| `play.picture` | the one that leads: work image → title page → author → R3a label | art row |

`pictureKind` gains `titleCard`, `press`, `magazine`, `titlePage`, `author` so every surface can
caption honestly ("CBS press photograph, 1953").

---

## 6. What stays without a real picture (feeds R3a's label)

Measured, the answer is **most of the catalog**. Even with every source in this doc, a real picture
reaches about 37% of the top 300 (V2, V4 and V5 would add more; not measured here) and close to 0% of the long tail (0 of the random 100 from any
source). These stay on R3a's drawn label, and the label should be designed as the default, not
a fallback:

| Kind | Real picture expected | What carries it instead |
|---|---|---|
| Long-tail series (syndicated, local, AFRS, transcription libraries, foreign) | ~0% | R3a label: genre board, run arc, monogram, network and decade |
| Head series without a show image | star portrait where one passes (today's rule) | label behind the star? No: one picture per box; the label when no star passes |
| Episodes | inherit the series picture | the label with the date block (R3a) |
| News and documentary | a subject person's portrait (FDR, Churchill, Kaltenborn) where the series names one person; otherwise none | the label; news may show the subject's portrait only when the series name *is* that person (measured 1 of 40) |
| Speeches | the speaker's portrait (PD-USGov for a president) | as news |
| Networks | a period logo rarely (Blue, CBS classic) | a typographic network mark drawn from the name, never a modern corporate logo on a 1940s row |
| Sponsors | period ads for the big brands | the name in type |
| Stage plays | 88% have an image (title page, edition scan, author) | the label for the 12%, with the author line |
| **User-made ear dramas** | **none** (no archive holds them, and a stock photo is refused) | R3a's disc with the cast's part hues on the rim; the title and the players' names are the art. A user photo is possible only as a deliberate feature with consent and moderation (V9) |

The handoff to R3a: every object in the projection either has a `picture` (with evidence) or a
NULL that the client draws as the label from data the row already carries (genre, `years`,
`networks`, title, date, cast). No new field is needed for the label.

---

## 7. Questions only the owner can answer

The first five are RESEARCH §12's, still open; the measures above say what each would buy.

| # | Question | What it unlocks (measured) |
|---|---|---|
| V1 | Serve undated person matches (about 1 in 30 wrong)? | More star portraits; unchanged from Track E |
| V2 | Library of Congress "No known restrictions on publication" (Bain, Harris & Ewing, Gottlieb, FSA/OWI), and Commons files whose only statement is that LoC line: usable? | Track F's 73 people with LoC photos; here 3 of 50 play authors (Colum, Maugham, Pinero) and 12 Commons files in this sample |
| V3 | Federal Theatre Project photographs, whose records carry no rights sentence: usable on the WPA credit alone? | Production photos of stage plays (The Show-Off, Whistling in the Dark, 1934) and FTP radio division pictures |
| V4 | Smithsonian NPG CC0 on post-1930 portraits: accept as is? | 114 people (Track F) |
| V5 | A page from a magazine issue whose title-year was not renewed (Radio Guide 1931-43, Radio Mirror 1933-43, Tune In): usable on the issue's evidence alone, given contributions can carry their own notice? | Covers and photo pages naming shows: the one source that scales to the head *and* the middle of the catalog. Note: Commons already hosts Radio and Television Mirror pages from December 1950 marked no-notice, a year Track F found renewed. That conflict is exactly V5. |
| V6 | Free API keys for NYPL, DPLA, NARA (and Flickr) need an account or an email address, which is yours to give | Billy Rose Theatre Division playbills and photos (plays), state archives (regional radio), presidential libraries (speeches) |
| V7 | **Copy free images to our own CDN** (R2 or similar, two tiers) instead of hot-linking `Special:FilePath`? It costs storage and a publish step; it removes the dependency on Wikimedia's rate limits and on files being renamed | Faster grids, no broken boxes, the image-cdn-discipline layout |
| V8 | **Logos**: a corporate logo marked `PD-textlogo` is free of copyright but still a trademark. Show network and sponsor logos as identification, or draw names in type only? And may a *modern* logo ever stand for a 1940s network? (Recommendation: period marks only, else type.) | Networks and sponsors index art |
| V9 | **User-made ear dramas**: drawn label only, or let a production upload one picture of its own (consent, moderation, removal on request)? | Art on every shared play |
| V10 | **Read a series' run from its enwiki article** when its Wikidata item has no dates (the article is the item's own sitelink): count it as the "years" identity? | Most of the 87 title-only matches in the top 300; 11 of 16 Wikidata image statements become servable |

---

## 8. Method, and how to rerun

All in `docs/research/data/r3b/`. Python stdlib only; `photo_match.rights_class` is imported from
`catalog/tools` for LoC. Responses are cached by request under `cache/` (gitignored), so every
command below reruns offline and gives the same numbers.

    python3 probe_sources.py sample        # live projection -> sample.json (seeded)
    python3 probe_sources.py lookup        # SPARQL VALUES lookup of every name variant -> lookup.json
    python3 probe_sources.py wikidata      # wbgetentities + identity -> wd.json
    python3 probe_sources.py plays         # works, authors, archive.org editions -> plays_probe.json
    python3 probe_sources.py orgs          # networks + sponsors -> orgs.json
    python3 probe_sources.py wikipedia     # enwiki pages 50 a call -> wp.json
    python3 probe_sources.py wp_any        # lead images incl. non-free -> wp_any.json
    python3 probe_sources.py commons       # Commons by name (top 100, random 50) -> commons.json
    python3 probe_sources.py commons_cats  # publicity categories -> commons_cats.json
    python3 probe_sources.py loc           # loc.gov photos (top 60, random 15 reached) -> loc.json
    python3 probe_sources.py openverse     # top 60 -> openverse.json
    python3 probe_sources.py europeana     # top 60 -> europeana.json
    python3 probe_sources.py licenses      # each file's class from its own page -> files.json
    python3 probe_sources.py report        # tables -> report.json (matches list for the precision read)

`sponsor_ads.json` holds the eight sponsor ad searches. Limits of the measurement: the Commons and
LoC routes are sub-samples; the license classifier reads Commons' hidden license categories, not the
wikitext template the production pipeline reads, so it is slightly stricter (PD-old without a US
reason stays out); precision was judged from file names, captions, categories and dates, not by
opening every image; the LoC run was stopped at 75 of 110 queries after its usable hits were all
wrong subjects.
