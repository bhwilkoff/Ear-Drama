# Track F — photo and graphic archives beyond Commons (2026-10-21)

Measured in this session; every count is from the caches and from
`out/radio-catalog.sqlite` after `tools/enrich_photo_archives.py`.
Owner rule for images: no human review queue. An image is used when its OWN
record carries public-domain or free-licence evidence a reader can open, and it
is removed on request (the take-down model the audio follows). Facts and
rights evidence only: no caption is written by us; titles, dates and rights
statements are the holders' own words. No image binary was downloaded.

## What was built

| File | Does |
|---|---|
| `tools/photo_match.py` | Rights classes from a record's own statement; conservative series, person and portrait matching (shared by the harvester and the enrich step) |
| `tools/harvest_loc_photos.py` | Library of Congress Prints & Photographs via the keyless loc.gov JSON API: topic queries, named collections, and a quoted-name query per top series and person; then item JSON (every file, TIFF master) for usable matched records. Cached per page under `.cache/loc/`; a 429 or CAPTCHA stops the run (exit 3) |
| `tools/harvest_smithsonian.py` | Smithsonian Open Access bulk metadata from the public S3 bucket (no key), streamed and filtered per shard; one cache file per shard under `.cache/smithsonian/` |
| `tools/harvest_magazine_rights.py` | Radio magazines: Online Books Page periodical-renewal inventory, our own reading of the CCE Part 2 renewal entries 1958-1977, worldradiohistory.com issue inventory, archive.org Media History Digital Library volumes. Cache `.cache/magazines/` |
| `tools/enrich_photo_archives.py` | POST-BUILD: adds only `archive_photos`, `archive_photo_links`, `magazine_rights`, `magazine_scans`; drops and rebuilds them each run; writes `out/enrich_photo_archives_report.json` |
| `tests/test_photo_archives.py` | 42 checks on synthetic data; 13 mutation controls in its docstring |

Re-run (all resumable from cache):

    python3 tools/harvest_loc_photos.py --phase all      # 185 queries / 568 pages, ~2.5 h at the measured 3-5 req/min, then
                                                         # item JSON for usable matched records (150 a run); exit 3 = blocked: re-run after an hour
    python3 tools/harvest_smithsonian.py                 # 1,024 shards, ~3 GB streamed, ~25 min; cached shards skipped
    python3 tools/harvest_magazine_rights.py             # ~75 MB of CCE OCR first run; then cached
    python3 tools/enrich_photo_archives.py               # ~15 s, no network
    python3 tests/test_photo_archives.py                 # 42/42

## Rights classes (`photo_match.rights_class`)

| Class | When | Usable |
|---|---|---|
| `no_known_restrictions` | the record says "No known restrictions" (LoC) | yes |
| `government` | a federal creator is named on the record (OWI, FSA, WPA Federal Theatre Project, a federal department) and the record does not say publication is restricted | yes |
| `cc0` | the holder marks the image file itself CC0 (Smithsonian per-media `usage`) | yes |
| `restricted` | the record says publication may be / is restricted, copyright, permission required; or (SI) "Usage conditions apply" | no |
| `unknown` | anything else: "Rights status not evaluated", no statement, no image online | no |

A restriction always beats a government creator: when a record names a
federal creator and also says "Publication may be restricted" (World-Telegram
prints of OWI photos do), the record's own restriction wins. `usable` also
needs an image URL online.

## 1. Library of Congress Prints & Photographs

**Access, measured.** loc.gov's JSON API is keyless; its published limit
(loc.gov/apis/json-and-yaml/working-within-limits, read 2026-10-21) is **20
requests a minute, with a one-hour block that restarts on any request made
during it**. The first run, at one request per 4 s and after ~15 probes, was
blocked (429) after ~30 requests in five minutes on this shared egress IP; the
harvester now paces at 6 s, stops on a 429 or a CAPTCHA page instead of
retrying into the block, and resumes from its page cache. Responses took 5-15 s
each, so the effective rate was 3-5 requests a minute. Search pages of 100
results were cut mid-body by the proxy (IncompleteRead at 81 KB of 2.4 MB);
`c=50` with `at=results,pagination` (~380 KB a page) reads cleanly. A search
page already carries each record's title, date, rights advisory, subjects,
contributors, call number and preview URLs, so one request reads 50 records.

**Queries run** (`/photos/?q=...&fo=json`): 17 topics dated 1920-1965 (radio,
microphone, broadcasting, radio station / program / announcer / receiver / set /
actors / studio, sound effects, the four networks by name, network broadcast,
transcription); 8 collection queries (`fa=partof:bain collection`,
`harris & ewing collection`, the FSA/OWI black-and-white negatives,
`federal theatre project, 1935 to 1939`, and text queries for the World-Telegram
— `radio world-telegram`, `radio NYWTS` — and `radio look magazine`, which are
not facets on /photos/); and a quoted-name query for the top 60 series and the
top 100 people by credited episodes. 185 queries, 568 pages, 0 failed.
Not run (budget): the next 160 series and 300 people the harvester can list;
they resume with the same command after raising the two slice limits in
`db_terms()`.

**Records: 12,091 photographs** (other formats dropped).

| Rights class | Records | Usable (image online) |
|---|---|---|
| no_known_restrictions | 2,488 | 2,471 |
| government | 2,735 | 2,645 |
| restricted | 1,721 | 0 |
| unknown | 5,147 | 0 |
| **total** | **12,091** | **5,116** |

By collection, as the statements read:

- **Harris & Ewing** (243 radio records) and **Bain** (57): "No known
  restrictions on publication."
- **FSA/OWI** (377): "No known restrictions. For information, see U.S. Farm
  Security Administration/Office of War Information Black & White Photographs"
  -> government. This is the wartime-radio set: OWI's own radio shows *You
  Can't Do Business With Hitler* and *Three Thirds of a Nation* in rehearsal,
  Elmer Davis at a line of microphones, Marian Anderson broadcasting from the
  Interior Department (1943).
- **Federal Theatre Project, 1935-1939** (1,730, Music Division): **no rights
  sentence at all in the API record**; classed government on the creator
  (Federal Theatre Project (U.S.), a WPA unit). Includes FTP portraits (Orson
  Welles, Ian Keith) and the FTP radio division. Owner question below.
- **New York World-Telegram & Sun** (~170 by text query): almost all
  "Publication may be restricted. For information see 'New York World-Telegram
  & ...'" -> restricted; a few staff prints say "No known restrictions".
- **Look** (149): mixed — 19 no known restrictions, 76 restricted, 30 unknown.
- **William P. Gottlieb** (jazz, 1938-48): "Mr. Gottlieb has dedicated these
  works to the public domain, but rights of privacy and publicity may apply"
  -> no_known_restrictions, with the publicity caveat in the statement itself.
- Theodor Horydczak (211), Herbert Block and NBC-credited press prints:
  "Publication may be restricted" -> restricted.
- Veterans History Project and American Folklife Center card files: no
  statement -> unknown (and mostly not photographs of broadcasts).

**Largest image**: the search page lists the 640-px reference JPEG (`r.jpg`)
or, for FSA/OWI and Bain, the 1,024-px `v.jpg`; the item JSON lists every file,
including the TIFF master (`u.tif`). Item JSON was fetched for **122 of the 165
usable matched records** (112 with a TIFF master) before loc.gov answered 429
on the item endpoint; the other 43 resume with `--phase all` after an hour and
keep the preview URL meanwhile. The FTP prints are served through IIIF at full
size (up to 6,385 px wide).

## 2. Smithsonian Open Access (bulk, keyless)

`api.si.edu` with `DEMO_KEY` answered `OVER_RATE_LIMIT` on the first call from
this egress IP (shared). The same EDAN records are public on
`smithsonian-open-access.s3-us-west-2.amazonaws.com/metadata/edan/<unit>/`, 256
line-delimited JSON shards a unit, read at ~10 MB/s. Filter: a `radio` word AND
a broadcast word (broadcast, program, microphone, announcer, studio, station,
receiver, network, NBC, CBS ...) in the record's text — except the National
Portrait Gallery, where every record whose image is CC0 is kept, because a
portrait rarely says "radio".

| Unit | Shards | Kept | Image CC0 (usable) | Other |
|---|---|---|---|---|
| NMAH (American History) | 256 | 4,120 | 2 | 4,118 have no image online in the bulk record |
| NPG (Portrait Gallery) | 256 | 14,703 | 14,664 | 34 "Usage conditions apply", 5 no image |
| NMAAHC (African American History) | 256 | 138 | 5 | 133 no image |
| SIA (Institution Archives) | 256 | 2,516 | 0 | no image in the record |

NMAH's radio receivers and microphones (the Clark Radioana collection, Work
and Industry) are almost all metadata-only in Open Access: 2 of 4,120 have an
image file. NPG is the useful unit: its CC0 portraits match **114 of our people
by portrait title** (301 usable links, below).

## 3. Period magazines as art

### Where the scans are

| Title | worldradiohistory.com PDFs | archive.org MHDL volumes |
|---|---|---|
| Radio Guide | 604 (1931-1943) | — |
| Radio Mirror (Radio & Television Mirror, Radio Romances, Radio-TV Mirror, TV Radio Mirror) | 303 (1933-1958) | 53 (1934-1963) |
| Radio Digest | 294 (1922-1933) | 14 (1922-1932) |
| Radio Stars | 75 (1932-1938) | 5 |
| Tune In | 42 (1943-1946) | 1 |
| Radio Varieties | 21 (1939-1941) | 1 |
| Screen and Radio Weekly | — | 14 (1934-1939) |
| Radio Showmanship | — | 8 (1940-1949) |
| Radio Daily | — | 6 (1937-1949) |
| Variety | — | 4 (1937-1940) |

**worldradiohistory.com's own terms** (home page, "Disclaimer and Rights",
read 2026-10-21): *"Other than where indicated, the operator of this web site
does not claim copyright or ownership of any photographic images contained
herein ... The content of this site appears under the 'fair use' doctrine of
United States copyright law ... Any persons wishing to duplicate or otherwise
make use of the images on this web site do so at their own risk."* It has a
take-down notice; robots.txt disallows only site-furniture folders (and
`ia_archiver` entirely). So the site is a scan source, never rights evidence:
the issue's own status decides.

**archive.org MHDL volumes carry no licence** (`licenseurl` on 1 of 108 radio
items) but 75 carry `possible-copyright-status: NOT_IN_COPYRIGHT` (or "Library
of Congress has determined that this item is not in copyright"). **That field is
wrong for Radio Mirror 1944-1963**: 35 volumes so marked fall in years whose
issues were renewed (OBP; and the CCE prints the renewals, e.g. R519469, 7 Dec
1971, the January 1944 issue, Macfadden-Bartell). The field is recorded in
`magazine_scans.holder_statement` and never used as evidence.

### Rights by title and year (`magazine_rights`)

Rules: published 1930 or earlier is public domain in 2026 (calendar rule);
1931-1963 needed a renewal in the 28th year; 1964 on renewed automatically.
Evidence, in order: our own reading of the CCE renewal entries; the Online Books
Page inventory of first periodical renewals (Ockerbloom, Penn), whose scope note
says it "should include all of the periodicals with renewed issue or
contribution copyrights (for 1931-1950 issues) between 1958 and 1977, that were
filed in the CCE". A title absent from that inventory, with no renewal found in
our reading of the 1958-1977 volumes, is `not_renewed` for 1931-1950. A
1951-1963 issue renews in 1979-1991, in the Copyright Office's online records;
where OBP checked the CCE only, those years are `unchecked`.

| Title | Years scanned | Status | Evidence |
|---|---|---|---|
| Radio Digest | 1922-1930 | pd_by_age | calendar rule |
| Radio Digest | 1931-1933 | not_renewed | OBP: "no issue renewals found in CCE; no contribution renewals found in CCE" |
| Radio Guide (Movie and Radio Guide) | 1931-1943 | not_renewed | OBP: "no issue renewals found in CCE; no contribution renewals found in CCE" |
| Radio Stars | 1932-1938 | not_renewed | OBP: same sentence |
| Radio Mirror | 1933-1943 | not_renewed | OBP: "issues actively renewed from January 1944 (v. 21 no. 3)"; caveat: "contributions actively renewed from June 1938" |
| Radio Mirror | 1944-1963 | **renewed** | OBP; CCE R519469 (1971, Jan 1944 issue), R521168, R524728, R525101 ... (1972), R547655 (1973, as Radio Romances) |
| Tune In | 1943-1946 | not_renewed | absent from OBP; none in our CCE reading |
| Radio Varieties | 1939-1941 | not_renewed | same |
| Screen and Radio Weekly | 1934-1939 | not_renewed | same |
| Radio Showmanship | 1940-1949 | not_renewed | same |
| Radio Daily | 1937-1949 | not_renewed | same |
| Variety | 1937-1940 | not_renewed | OBP: "no issue renewals found in CCE or CPRS; contributions renewed from January 8, 1947" |

Also on record from OBP, with no scan inventoried: Stand By (WLS, 1935-1938)
and What's On the Air (1929-1931) never renewed; Sponsor never renewed (CCE and
CPRS); **Radioland and Television renewed from November 1948** (and our CCE
reading found R684170, 1976, for the November 1948 issue); Broadcasting
(1957-1993) no renewals in CPRS; Song Hits issues never renewed, contributions
from 1941. Controls in the same reading: Photoplay and Motion Picture Magazine
(Macfadden, renewed from January 1944 per OBP) show renewal blocks in the 1971-73
volumes, as expected.

**Our CCE reading, measured**: 20 volumes (1958-1977, Third Series Part 2), 9
renewal blocks for the target titles: Radio Mirror 3, Photoplay 3, Motion
Picture 2, Radioland and Television 1 — all agreeing with OBP. It finds the
1971-73 renewals and misses Radio Mirror's 1974-77 renewals (filed as "TV Radio
Mirror", OCR'd "TY RADIO MIRROR", in a scrambled multi-column layout): a miss,
never a false renewal, which is why OBP is the primary source and an absence in
our reading alone never frees a title that OBP lists. The 1959 volume on
archive.org is July-December only.

**Caveats carried on every row** (`magazine_rights.caveats`): a contribution
(story, photo, drawing) can carry its own registration and renewal; an
advertisement may carry its own notice and is judged separately (Commons'
`PD-US-no notice advertisement` is the ad-level route); wire, studio and
syndicated photos reprinted in an issue may be the originator's. Where OBP
records renewed contributions (Radio Mirror from 1938, Variety from 1947), the
row says so first.

## 4. Matching (`archive_photo_links`)

- **Series**: the series' own name as a phrase in the record, a broadcasting
  word in the same record (radio, broadcast, microphone, announcer, NBC, CBS,
  Mutual, call letters ... — not "studio" or "program", which matched
  photographers' studios and theater programs), and the record's year within
  the run +/- 2. Only series with a known run and 10+ episodes; one-word names
  only with 100+ episodes and not generic ("Suspense", "Escape" never).
- **People**: a two-token name resolving to ONE person in `people` (3+ credited
  episodes, or a birth/death date); an LoC name heading's lifespan must agree
  with ours (+/- 1); a free-text name needs a broadcasting word; the record's
  year must fall in the person's life (after age 10).
- **Portraits** (NPG): the record's title is exactly the sitter's name and the
  sitter's printed lifespan agrees with ours; with no year on either side the
  name alone is refused.
- `strength`: `title` (portrait, or the name in the record's own title with at
  most 3 people matched), `heading` (LoC name heading), `mentioned` (named
  elsewhere: a theater program listing 40 names, a mural study). Only `title`
  and `heading` should be offered as art.

**Measured** (`archive_photo_links`, usable records only):

| Source | Person links (title / heading) | People with a usable title or heading photo | Series links |
|---|---|---|---|
| LoC | 131 title, 0 heading (+55 mentioned) | 73 | 0 usable |
| Smithsonian (NPG) | 301 title (+54 mentioned) | 114 | 0 usable |
| **both** | | **179 distinct people** | |

Examples: Graham McNamee (Bain, 1925, no known restrictions); Rudy Vallee at a
microphone (1930, no known restrictions; and NPG portraits 1928, 1930, CC0);
Fulton Lewis, Jr. creating the radio gallery (Harris & Ewing 1939); Elmer Davis
(OWI 1942); Jackie Gleason (Look 1952, no known restrictions); Orson Welles and
Ian Keith (Federal Theatre Project); Edgar Bergen 1948, Gene Autry 1942, Milton
Berle 1953 (NPG, CC0). The `people` table also holds the authors and guests
the logs credit, so Poe, Dickens and Einstein are among the
179 — correctly, since they are credited on our episodes.

**Series: none usable.** LoC's photographs that do name a series — *Fibber
McGee and Molly* (1944, 1950), *Information Please* (1941), *The Campbell
Playhouse* (Welles at the microphones, 1938), *Your Hit Parade* (1946, 1949),
*Grand Ole Opry* (1947), *Command Performance* — are NBC/CBS press prints in the
World-Telegram and Look files, and their records say "Publication may be
restricted" or nothing: 22 links, all restricted or unknown. Series art from
LoC therefore comes through the PEOPLE (the star at the microphone), as
05-design §3 anticipated. **One near miss**: *You Can't Do Business With
Hitler* (OWI, 1942; 3+ government photos of the cast rehearsing) is a series
in our DB (12 episodes) with no dates, and the series rule requires a known run;
dating that series (editorial) would bring it in.

Refusals (report `refused`): 2,011 record-year-after-death; 2,042 free-text
names with no broadcasting word; 57 before the person was 10; 43 ambiguous
names; 68 NPG portraits with no lifespan to compare; 51 lifespan
disagreements; 6 homonyms (the *Mae West* life vest — the first LoC pass tied
six OWI "pursuit pilot in combat gear" photos to the actress, which is why the
rule exists). Series named for a person ("Bing Crosby", "Winston Churchill")
are matched through the person only.

## 5. Not harvested, with the exact route

| Source | Measured | To harvest |
|---|---|---|
| NARA catalog (OWI 208-series, other federal radio photos; public domain) | `catalog.archives.gov/api/v2/records/search?q=radio%20broadcast&typeOfMaterials=Photographs%20and%20other%20Graphic%20Materials` without a key returns the catalog's HTML page, not JSON | the v2 API needs an `x-api-key` (free, by request to catalog_api@nara.gov). Many OWI negatives are also LoC's FSA/OWI collection (harvested above) |
| Smithsonian API | `DEMO_KEY` over its rate limit from this IP | not needed: the bulk files are the same records |
| NYPL Digital Collections | `api.repo.nypl.org/api/v2/items/search?q=radio&publicDomainOnly=true` answered 401 "HTTP Token: Access denied." | needs a free account token |
| DPLA | `api.dp.la/v2/items?q=radio+microphone` answered 403 invalid_api_key | a key is issued by `POST /v2/api_key/<email>`; an email is the owner's to give |
| Copyright Office online records (1978+ renewals, for 1951-1963 issues) | the public-records API answers, but a title query returns registrations from the card catalog, not RE renewals (104 "Radio mirror" hits, all B-registrations) | the `unchecked` 1951-1963 magazine years need a renewal-class query or the CPRS UI |

## Tests and controls

`tests/test_photo_archives.py` 42/42. Each control was run against a mutated
copy of the tools and failed (counts in the docstring): a government creator
beating a restriction 40/42, no broadcasting word for series 41/42, the series
year window ignored 41/42, generic one-word names 41/42, the LoC heading
lifespan not compared 41/42, an ambiguous name resolved 41/42, OBP's CCE-only
check trusted for 1951-63 41/42, the first-renewed month ignored 41/42, the NPG
portrait lifespan not compared or not required 41/42 each, the homonym rule
41/42, undated series matches 41/42, a CCE block running into the next title
40/42. The lifespan control first PASSED its mutation (its case also tripped
the age-10 rule) and was rewritten. `test_enrich_external.py` (37/37) and
`test_audio_rights.py` (22/22) still pass; no shared tool or table was edited.

## Open

- Owner: does a photo from a `not_renewed` magazine issue ship without a
  per-photo check, given the contribution caveat? (The owner rule says the
  record's evidence suffices; the magazine-level evidence is the issue's.)
- Owner: NPG's CC0 includes post-1930 photographs (Milton Berle 1953). The
  holder's own CC0 is the evidence under the rule; say if it should be held to
  the photo's age as well.
- Owner: the Federal Theatre Project records carry no rights sentence; they
  are classed `government` on the WPA creator alone (1,730 records, incl. FTP
  radio-division photos). Say if a creator credit is enough without a
  statement.
- Keys for NARA, NYPL and DPLA would widen the pool; each is a free signup.
- Remaining harvest: 43 item JSONs (TIFF masters); the next 160 series and 300
  people name queries; dates for *You Can't Do Business With Hitler*; the
  1951-1963 magazine years marked `unchecked` (none in the current scan
  inventory) need a CPRS renewal-class query.

## Addendum 2026-10-22: the widened name searches

The name queries were widened to 220 series and 400 people (`db_terms()`), and
run after loc.gov's hour-long 429 blocks lifted. Result: Library of Congress
12,091 -> 12,664 records, 5,116 -> 5,247 usable; people with a usable photo
naming them 179 -> 181; series still 0. **228 queries fail with HTTP 520**
(loc.gov's origin, not a rate limit; the same query answered 200 when tried by
hand, slowly) on two successive passes; failed queries are not cached, so
`python3 tools/harvest_loc_photos.py --phase all` retries only those.
