# 09 — Ear Drama: name check, icon sources, type, palette and store assets (2026-10-21)

Owner, 2026-10-21: *"The app is going to be called "Ear Drama"."* This file is the
brand research that the new repository needs before its first build: whether the
name is clear, what public-domain imagery an icon can be made from, which open
typefaces fit, a chrome palette that is a sibling of Archive Watch's without
borrowing a genre accent, every graphic asset each store and platform asks for,
and which Archive Watch asset tools carry over.

Rules this file keeps: no model-generated art (an icon is made from a
public-domain or CC0 period object, as Archive Watch's is made from a 1902 film
frame); no copy written for the product here (taglines, store text and banner
words are the owner's, CLAUDE.md "No AI-written lists or copy"); US English;
every factual claim carries its source and the date it was read (2026-10-21
unless stated). UNVERIFIED marks what could not be read from a primary source.

Method notes: domain status by RDAP (`rdap.org` bootstrap, IANA `dns.json`);
trademarks by the USPTO Trademark Search backend that `tmsearch.uspto.gov` itself
calls (a POST to `/prod-stage-v1-0-0/tmsearch`, controlled with `wordmark:netflix`
→ 59 hits, so a zero is a real zero); stores by the iTunes Search API and the
Google Play web search page; images by the Library of Congress JSON API
(`?fo=json`), the Smithsonian Open Access API and Wikimedia Commons (the Commons
action API rate-limited this session with HTTP 429, so searches went through
`api.wikimedia.org/core/v1/commons/search/page` and license reads through
`en.wikipedia.org/w/api.php?prop=imageinfo&iiprop=extmetadata`, which reads the
same Commons file pages); typefaces by the `google/fonts` repository's own
`METADATA.pb` and the font files' OpenType tables (fontTools 4.67); platform specs
from each vendor's page, quoted.

---

## 1. Name check: "Ear Drama"

### 1.1 What exists under the name (MEASURED)

| Where | Query | Result | Source |
|---|---|---|---|
| US App Store (apps) | `ear drama`, `eardrama` | No app with that or a near name. Results are ear-training, earwax, headphone and short-video "drama" apps (MoreShort, Pocket FM: Audio Dramas, GoodFM - Dramas & Audiobooks, Quinn - Audio Stories, GraphicAudio Access) | `https://itunes.apple.com/search?term=ear%20drama&entity=software&country=us` |
| US App Store (podcasts) | `ear drama`, `eardrama` | No show by that name. Nearest: "Murder In Your Ear", "Ear Hole Horror", "EarWyrm", and producers "Little Ear Productions", "Queer Ear Productions" | `https://itunes.apple.com/search?term=ear%20drama&entity=podcast&country=us` |
| Google Play (US) | `ear drama`, `"ear drama"` | No app by that name. The first 30 results are vertical short-video "drama" apps (FreeDrama, iDrama, DramaBox, ReelShort, DramaWave...); the quoted search returns nothing named Ear Drama | `https://play.google.com/store/search?q=ear%20drama&c=apps&hl=en_US&gl=US` |
| Web | `"Ear Drama" podcast OR app OR radio`, `"EarDrama" OR "Ear Drama" audio drama company` | No product, company or podcast called Ear Drama. Near names: **Earplay** (the 1970s public-radio drama series), **HEAR PLAY Audio Theatre** (a pandemic-era podcast named after Earplay), **EarPlays** (Theatre Artists Studio, Phoenix) | web search 2026-10-21; [Earplay (Wikipedia)](https://en.wikipedia.org/wiki/Earplay), [EarPlays](https://podstatus.com/podcasts/earplays-334017), [HEAR PLAY](https://trianglefireproject.buzzsprout.com/) |
| USPTO | `wordmark:(ear drama)`, `wordmark:eardrama`, `wordmark:(ear AND drama)` | **0 records**, live or dead | USPTO Trademark Search backend (above) |

### 1.2 Confusingly similar marks (USPTO, MEASURED)

| Mark | Status | Owner | Class and goods (quoted) | Serial |
|---|---|---|---|---|
| EARPLAY | REGISTERED 2024-07-23 | EARPLAY, INC. (Delaware) | IC 009: "Audio recordings featuring narration, voice acting, sound effects, and music; ... Digital media, namely, downloadable audio, image, and text files featuring interactive audio drama content; ... Downloadable software in the nature of a mobile application for distribution of voice-operated interactive audio entertainment publications" | [98084004](https://tsdr.uspto.gov/#caseNumber=98084004&caseType=SERIAL_NO&searchType=statusSearch) |
| EARPLAY | REGISTERED 2026-01-20 | EARPLAY, INC. | IC 041: "Entertainment services, namely, providing online interactive stories with voice user input; ..." | [99086396](https://tsdr.uspto.gov/#caseNumber=99086396&caseType=SERIAL_NO&searchType=statusSearch) |
| THEATER FOR THE MIND | SECTION 8-ACCEPTED (live) | Wayland Productions | IC 041 | 87451360 |
| SEEING EAR THEATRE | dead (cancelled / abandoned) | USA Networks | IC 009, 041 | 75428548, 75858203 |
| BAY AREA RADIO DRAMA | dead (abandoned) | individual | IC 041 | 90012141 |
| EARDRUM, EARDRUMS, EARDRUMA RECORDS ... | all dead | various | IC 009/041 | (see query `wordmark:eardrum*`) |

Earplay, Inc. is the Boston company behind voice-operated interactive audio
stories on iPhone and Alexa, founded 2013
([Amazon Alexa blog](https://developer.amazon.com/blogs/alexa/post/Tx2TM2QAL89ND1Q/earplay-an-interactive-audio-only-storyteller-made-even-better-by-alexa),
[Xconomy](https://legacy.xconomy.com/?p=341072),
[Built In](https://builtin.com/company/earplay)). An iTunes Search for `earplay`
returned no Earplay app in the US store today, so whether its app is still
distributed is UNVERIFIED; the registrations are live either way.

### 1.3 Domains (RDAP, MEASURED 2026-10-21)

| Domain | Status | Registered | Registrar | Name servers |
|---|---|---|---|---|
| eardrama.com | **registered** | 2026-10-13T19:23:57Z, expires 2027-10-13 | Cloudflare, Inc. | anita / merlin .ns.cloudflare.com |
| eardrama.app | **registered** | 2026-10-13T19:21:57Z, expires 2027-10-13 | CloudFlare, Inc. | anita / merlin .ns.cloudflare.com |
| eardrama.org | available (PIR: "Object not found") | — | — | — |
| eardrama.fm | available (CentralNic: "Object not found") | — | — | — |
| eardrama.net | available (Verisign 404) | — | — | — |
| eardrama.co, eardrama.radio, ear-drama.com, eardramas.com | available (404) | — | — | — |

Sources: `https://rdap.org/domain/<name>`; `https://rdap.verisign.com/net/v1/domain/eardrama.net`.
The two registered names were taken two minutes apart eight days ago, at the same
registrar, on the same Cloudflare name-server pair, and publish no A or MX record
(`https://dns.google/resolve?name=eardrama.com&type=A` returns only the SOA). The
registrant is redacted in RDAP. **Whether these are the owner's is the first thing
to settle (B1)**: the pattern fits a person reserving a name the week they chose
it; if they are someone else's, the .com and .app are gone and .org is the
open choice. The Wayback Machine could not be reached from this session
(`web.archive.org` connections reset), so any earlier use of eardrama.com is
UNVERIFIED. For comparison, archivewatch.org is registered through Automattic on
WordPress.com name servers (RDAP).

Social handles were not checked (optional in the brief).

### 1.4 Risks, stated plainly

1. **EARPLAY is the nearest mark, and it is live in exactly our class.** It is
   registered in IC 009 for audio drama content and a mobile app, and in IC 041
   for interactive audio stories. "Ear Drama" and "Earplay" share the first
   syllable and the field, differ in the second word, and Earplay's goods are
   *interactive voice-controlled* stories, not a catalog of archival broadcasts.
   No search here found an "Ear Drama" mark to collide with; whether "Ear Drama"
   is confusingly similar to "Earplay" is a legal judgment this file cannot make.
   A trademark attorney's clearance opinion before filing, or before the store
   listing, is the step that answers it.
2. **"Drama" in a 2026 store search means short-video serials.** Both stores'
   first page for "ear drama" is vertical micro-drama apps (and on Play, "Drama
   Cash: Earn Money" style apps). Searchers who type the name will find us, but
   the category word carries an association the owner should know about when
   writing the subtitle and choosing the store category.
3. **The 1970s Earplay series** (NPR / Corporation for Public Broadcasting,
   WHA Madison, Peabody-winning) is a real radio-drama precedent with a similar
   name ([Wikipedia](https://en.wikipedia.org/wiki/Earplay),
   [The Great Detectives of Old Time Radio](https://www.greatdetectives.net/detectives/the-american-audio-drama-tradition-part-six-1970s-part-one/)).
   Its episodes may well appear in the catalog's later layers; a listener could
   take "Ear Drama" for its successor.
4. **Not checked**: EUIPO, WIPO Global Brand Database, UK IPO, Canada — the
   stores are worldwide. UNVERIFIED.
5. Nothing found suggests the name cannot be used. No change of name is
   recommended; the owner chose it.

---

## 2. App icon concepts from public-domain and CC0 period imagery

### 2.1 What Archive Watch does, and whether radio has an analogue

Archive Watch's icon is a photograph: the 1902 *Le Voyage dans la Lune* frame,
toned and set in a 35 mm film-strip frame (`tools/render-app-icon.py`, source
`assets/app-icon/melies-moon-1902.jpg`, 944x914). The owner's rule is that the
icon is the photograph and nothing else — the illustrated vector was retired
2026-06-11 and the Android adaptive icon deliberately has no monochrome layer
"because the icon is the photograph and nothing else (owner rule)"
(`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`;
`tools/make_tv_banner.py` and `tools/roku_store_poster.py` repeat it; memory
`app_icon_photographic_only`). The tvOS icon is "flat": the still fills the Back
layer and the Front layer is transparent, because "the still is a single photo,
so no clean parallax cutout" (`render-app-icon.py` docstring).

**The radio analogue of a film still is a broadcast photograph**: a cast at the
microphone, a sound-effects man at work, a studio "on the air". Radio has no
frame of its own, but the networks and the government photographed broadcasts
constantly, and the Library of Congress holds thousands with no known
restrictions. The other analogue is the **object** — the microphone or the
receiver — which is to radio what the moon's face is to Méliès: the one thing
everyone recognizes.

Two facts from Apple's current guidance bear on choosing between them
([HIG, App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons),
change log "June 8, 2026 — Refined guidance for Liquid Glass"):

- *"Prefer illustrations to photos and avoid replicating UI components. Photos
  are full of details that don't work well when displayed in different
  appearances, viewed at small sizes, or split into layers."* Archive Watch's
  icon is already a deliberate exception to this; Ear Drama would be a second.
- iOS, iPadOS and macOS icons are now layered (Icon Composer) and appear in
  "Default, dark, clear light, clear dark, tinted light, tinted dark"; "the
  system automatically generates variants you don't provide." A full-bleed
  photograph has no foreground to separate, so its dark and tinted versions are
  whatever the system derives.

What follows is ranked by how well each reads at the three sizes that matter:
1024 px (the store), 29-40 pt (Settings, Spotlight, notifications — 58-120 px on
a 2x/3x screen) and the tvOS 400x240 pt parallax icon. The small-size judgement
for candidate A was MEASURED: a 1024 px crop of the microphone from its LOC file
was reduced to 29, 40, 60, 120 and 180 px with Lanczos resampling and viewed
(candidate 5 in §2.3); the same test was run on candidate 1. At 29 and 40 px the
photograph became an unreadable grey patch; at 120 px and above the microphone's
grille and capsule read clearly. **No photograph in this list reads at 29-40 px
as a photograph**; what survives at that size is a silhouette against a plain
ground, which is why every candidate's note says whether the object can be cut
out cleanly.

### 2.2 Rights test applied

Only images whose own record states public domain, "no known restrictions", or
CC0 are listed as usable. Modern photographs of period objects on Commons are
usually CC BY-SA (for example Joe Haupt's large Flickr set of "Vintage Philco /
RCA / Zenith ... Radio" photographs) and are excluded — a CC BY-SA icon would
need attribution wherever the icon appears and would bind derivatives to the same
license. Smithsonian Open Access returned the National Museum of American
History's records for an **RCA 44-BX Ribbon Velocity Microphone**, an **NBC / RCA
"Velocity" Ribbon Microphone**, a **Philco model 60 "cathedral"** and a **Philco
model 37-620 "tombstone"** with `metadata_usage: CC0` but **no online media**
(`media 0` in the API response,
`https://api.si.edu/openaccess/api/v1.0/search?q=ribbon+microphone`), so the
Smithsonian has no CC0 image of these objects to use today. Two further rights
cautions apply to every studio photograph:

- **Network microphone flags are live trademarks.** Most 1930s studio
  photographs show a mic flag reading NBC, CBS, MBS (Mutual) or a station's call
  letters. The NBC and CBS marks are in use today; a flag must be cropped out or
  the image passed over.
- **People's faces.** The photographs are public domain, but an app icon is a
  brand. Putting a recognizable actor's face on it reads as endorsement;
  right-of-publicity law varies by state and a deceased performer's estate may
  hold it. Prefer the object, or a group in which nobody is the subject. This is
  a caution, not a legal opinion.

### 2.3 Candidates

Each entry gives the file, its rights statement as the record words it, the
evidence page, the largest file, and how it reads. Previews were viewed at 600-1024
px this session; nothing larger was downloaded (TIFF dimensions were read from
the file header with a 64 KB range request).

**1. Western Electric double-button carbon microphone (ring mount) — RANKED FIRST**
- File: [`File:Microphone - Bayernhof Museum - DSC06319.JPG`](https://commons.wikimedia.org/wiki/File:Microphone_-_Bayernhof_Museum_-_DSC06319.JPG), photographed by Daderot, 2013-05-18.
- Rights: "CC0 — Creative Commons Zero, Public Domain Dedication"; description: "This is a Western Electric double-button carbon microphone, invented at Bell Laboratories ..." (the object is the 1920s-30s announcer's microphone; the photograph is the photographer's CC0 work; a utilitarian object carries no copyright of its own).
- Resolution: 3154x4453.
- 1024 px: the ring, its eight springs and the central button make one round, symmetrical figure; the museum background (wood paneling, other objects) must be cut away by hand.
- 29-40 px: reduced and viewed (same test as §2.1), the ring and the bright button still read as "a round microphone" at 29 px — the only candidate that does — and would read better cut out on a flat ground.
- tvOS parallax / Icon Composer: has a natural layer split — ground (Back), ring and stand (Middle), button (Front) — with the "clearly defined edges" the HIG asks for. A one-color silhouette gives Android's monochrome layer and iOS's tinted and clear variants without a second design.
- Cautions: no lettering was visible in the preview; check the full file for a maker's plate. Breaks Archive Watch's "photograph and nothing else" rule only if cut out — that is B4.

**2. A radio-drama cast at the microphone, 1942 (FSA/OWI) — the Archive Watch analogue**
- File: LOC [2017698439](https://www.loc.gov/item/2017698439/), "Gathered around the microphone during rehearsal are (left to right) Virginia Moore, Colonel Charles Ferris, Doris McWhirt, John Flynn, and Robert Poll..." — the OWI series *You Can't Do Business With Hitler*; photographer Howard Liberman; LC-DIG-fsa-8b08686.
- Rights: "The contents of the Library of Congress Farm Security Administration/Office of War Information Black-and-White Negatives are in the public domain and are free to use and reuse."
- Resolution: TIFF master 8673x6468 (`tile.loc.gov/storage-services/master/pnp/fsa/8b08000/8b08600/8b08686u.tif`, 56 MB).
- 1024 px: five actors with scripts around one ribbon microphone — the radio equivalent of the Méliès frame; a square crop centered on the microphone keeps three faces. The negative number "D-11023" is in the frame edge and must be cropped.
- 29-40 px: does not read (a grey patch, the same result measured for candidate 5).
- tvOS: flat, as Archive Watch's is (Back layer only), unless the figures are masked by hand.
- Cautions: named, identifiable people (§2.2); the series is wartime government propaganda, which Q8 already asks about for the catalog. Its companion frames — [2017697762](https://www.loc.gov/item/2017697762/) (rehearsal, 8674x6372) and [2017697737](https://www.loc.gov/item/2017697737/) (studio with the sound-effects table and turntables, 8688x6420) — carry the same statement and suit the WIDE master (Top Shelf, store header, Fire TV background) better than the icon.

**3. Recording sound effects, 1930s (Yle, Finland)**
- File: [`File:A man is recording sound effects, 1930s.jpg`](https://commons.wikimedia.org/wiki/File:A_man_is_recording_sound_effects,_1930s.jpg), Archives of the Finnish Broadcasting Company Yle, via Flickr The Commons.
- Rights: "Public domain"; category "PD Finland (simple photos)". A pre-1946 Finnish simple photograph was already public domain in Finland on 1 January 1996, so URAA did not restore it in the US.
- Resolution: 6928x4864.
- 1024 px: a sound man sawing a board while an engineer holds a Neumann "bottle" microphone to it — the sound-effects craft, legible and a little comic. A square crop holds either the saw or the microphone, not both.
- 29-40 px: the bottle microphone alone, cut out, is a plain vertical shape that would read only as "a cylinder".
- tvOS: flat unless masked.

**4. A radio-drama studio with wind machine and gong, 1949 (Yle)**
- File: [`File:Actress Toini Vartiainen and sound technician Marja Aaltonen.tif`](https://commons.wikimedia.org/wiki/File:Actress_Toini_Vartiainen_and_sound_technician_Marja_Aaltonen.tif): "Actress Toini Vartiainen behind the microphone and sound technician Marja Aaltonen using wind machine and playing gong."
- Rights: "No known copyright restrictions" (Yle's own statement on Flickr The Commons; Commons category "Files from external sources with reviewed licenses").
- Resolution: 4395x4592 — nearly square, the only candidate that is.
- 1024 px: the most complete radio-drama tableau found — actress, bottle microphone, wind machine, gong, script — in one square frame.
- 29-40 px: does not read.
- Cautions: "no known copyright restrictions" is the archive's statement, not a license; a 1949 Finnish photograph was still protected in Finland in 1996, so its US status turns on URAA and is not "public domain" by US rules. Usable on Yle's word; ranked below the US government and CC0 files for that reason.

**5. An actor at an RCA 44 ribbon microphone, 1942 (OWI)**
- File: LOC [2017697744](https://www.loc.gov/item/2017697744/), "Phil Dorn, film and radio actor, takes the mike to do his role on the War Production Board (WPB) radio program Three Thirds of a Nation"; photographer David Bransby.
- Rights: the FSA/OWI public-domain statement (as candidate 2).
- Resolution: **only 836x1024** (JPEG); the TIFF on file is 343x420. A 1024 px icon would be an upscale; a new scan of the negative would be a Library of Congress Duplication Services order (UNVERIFIED cost).
- 1024 px: the RCA 44's grille fills the lower frame, the definitive "old-time radio" microphone. MEASURED small-size test: at 29 and 40 px it is an unreadable grey patch; at 120 px the grille and capsule read.
- Cautions: one named actor's face dominates; crop to the microphone.

**6. The March of Time sound-effects team, CBS, c. 1931**
- File: [`File:MOT-Sound-Team.jpg`](https://commons.wikimedia.org/wiki/File:MOT-Sound-Team.jpg), "Promotional photograph of sound effects team for The March of Time radio series, CBS Radio, circa 1931."
- Rights: "Public domain", category "PD US no notice" ("released without copyright notice by Culver Pictures, Inc.").
- Resolution: 2800x1760.
- Use: a WIDE image (four people at sound-effects tables); not an icon. A faint network logo is on the back wall and must be cropped.

**7. A radio-drama studio, Helsinki, 1944 (Yle)**
- File: [`File:A radio drama studio during Finland's Continuation War, 1944.jpg`](https://commons.wikimedia.org/wiki/File:A_radio_drama_studio_during_Finland%27s_Continuation_War,_1944.jpg): "A radio drama studio during the war. In the center, a hexagonal microphone table."
- Rights: "Public domain", "PD Finland (simple photos)" (pre-1946, as candidate 3).
- Resolution: 3372x2211.
- Use: an empty studio with a light-filled window — a quiet backdrop for the wide master or the Now Playing screen's fallback; not an icon.

**8. Sound-effects equipment, 1940s (Yle)**
- File: [`File:Equipments for making sound effects, 1940s.jpg`](https://commons.wikimedia.org/wiki/File:Equipments_for_making_sound_effects,_1940s.jpg): "Equipments for making sound effects in the studio, including door and wind machine."
- Rights: "No known copyright restrictions" (Yle, Flickr The Commons). 1940s date unspecified — same URAA caveat as candidate 4 if after 1945.
- Resolution: 6573x4435.
- Use: the free-standing sound-effects DOOR is a strong radio-drama object (the creaking door of *Inner Sanctum*), but at icon size a door reads as a door, not as radio.

**9. AVRO radio-drama studio, Hilversum, 1936-37**
- File: [`File:AVRO hoorspelstudio PK-F-K.0062K.tif`](https://commons.wikimedia.org/wiki/File:AVRO_hoorspelstudio_PK-F-K.0062K.tif), Karel Kleijn, Leiden University Library.
- Rights: "CC0 — Creative Commons Zero, Public Domain Dedication".
- Resolution: 2953x2113.
- Use: a gravel tray, a "soldiers' rack", a shower cabin with a stair for running water — a sound-effects studio with no people; documentary interest, weak as brand art.

**10. The human ear, Gray's Anatomy (Henry Vandyke Carter)**
- File: [`File:Gray904.png`](https://commons.wikimedia.org/wiki/File:Gray904.png), "An anatomical diagram of the human ear, drawn by Henry Vandyke Carter for Gray's Anatomy" (1918 edition, plate 904).
- Rights: "Public domain" (PD-old-100-expired).
- Resolution: **285x450**, and the plate carries printed labels (Helix, Concha, Tragus...).
- Use: the only candidate that says the NAME; an ear's outline reads at any size. But it is an engraving, not a period object of radio, it would need a higher-resolution scan of the plate and the labels removed by hand, and an anatomical ear suggests a hearing-health app — the store neighbors for "ear" are ear-training and earwax apps (§1.1).

**11. A girl listening to the radio, c. 1940 (Rural Electrification Administration)**
- File: [`File:Girl listening to radio.gif`](https://commons.wikimedia.org/wiki/File:Girl_listening_to_radio.gif), "Rural Electrification Administration; 'Little girl by radio' circa 1940", from the FDR Library via NARA.
- Rights: "Public domain", "PD US Government".
- Resolution: 401x588 (GIF). Too small; a NARA master scan would be needed (UNVERIFIED availability).
- Use: the LISTENER's side — the only candidate showing radio as it was heard at home.

**12. Harris & Ewing studio microphones, 1930-38 (Library of Congress)**
- Files: e.g. LOC [2016880859](https://www.loc.gov/item/2016880859/) "[Men at NRS microphone]" (1935); [2016873365](https://www.loc.gov/item/2016873365/) "Sound effects men at Federal Labor Radio Show" (1938); [2016874234](https://www.loc.gov/item/2016874234/) the 1920 "'Tomato Can' radio microphone presented to Smithsonian Institution" (1938).
- Rights: "No known restrictions on publication" ([Harris & Ewing rights page](https://www.loc.gov/rr/print/res/140_harr.html)).
- Resolution: 1024 px JPEG service copies; ~20 MB TIFF masters (dimensions UNVERIFIED).
- Use: forty-seven Harris & Ewing "microphone" photographs exist, but nearly all show a network or station flag (NBC, CBS, Columbia, MBS, NRS) on the microphone and a politician at it — both reasons to pass (§2.2).

**Looked for and not found** (2026-10-21): a public-domain or CC0 photograph of
a **cathedral or tombstone receiver** — every Commons photograph of a Philco,
Zenith, RCA, Crosley, Atwater Kent or General Motors set found is GFDL, CC BY or
CC BY-SA (for example [`Philco cathedral radio.jpg`](https://commons.wikimedia.org/wiki/File:Philco_cathedral_radio.jpg),
GFDL 1.2; [`1935 Philco tombstone radio.jpg`](https://commons.wikimedia.org/wiki/File:1935_Philco_tombstone_radio.jpg),
CC BY-SA 3.0), and the Smithsonian's two cathedral and one tombstone records have
no online image. A period ADVERTISEMENT is the remaining route (e.g.
[`Atwater Kent Radio ad 1927.jpg`](https://commons.wikimedia.org/wiki/File:Atwater_Kent_Radio_ad_1927.jpg),
"PD US no notice"), but it carries a manufacturer's name. An **ON AIR sign** — none
in period photographs found. An isolated **RCA 44 / 77** — the Commons
photographs are CC BY-SA (`RCA 44-A Velocity Microphone.jpg`,
`RCA 44-BX Bi-Directional Velocity Microphone.jpg`, `RCA 44 of CBS 20071104.png`);
a CC0 one would need to be photographed (a museum piece, as Daderot photographed
candidate 1). Excluded for a logo: [`CBS microphone, 1930s, used by Franklin Roosevelt ...`](https://commons.wikimedia.org/wiki/File:CBS_microphone,_1930s,_used_by_Franklin_Roosevelt_for_his_Fireside_Chat_radio_programs_-_National_Museum_of_American_History_-_DSC06235.JPG)
(CC0, but the object is a large CBS flag) and `MOT-Ora-Nichols-1935.jpg` (PD US
not renewed, 800x508, CBS on the equipment).

**Ranking, with reasons.** (1) the Western Electric ring microphone: the only one
that reads at 29-40 px, layers naturally for tvOS and Icon Composer, carries no
face and no logo, CC0. (2) the 1942 OWI cast: the truest radio analogue of
Archive Watch's film still, a public-domain US government file at 8673 px —
first choice if the owner keeps the "photograph and nothing else" rule, at the
cost of the small sizes. (3) Yle 1930s sound effects: public domain, large,
characterful. (4) Yle 1949 tableau: the best square composition, weaker rights.
(5) RCA 44 with actor: the archetypal microphone, too small a file. (6)-(9) wide
images for the wide master. (10)-(12) concept or rights problems as stated.

---

## 3. Wordmark and typography

### 3.1 What Archive Watch uses

Archive Watch's Roku channel bundles **Fraunces** (Display Black, Display
SemiBold, Text Italic) and **Inter** (Medium, Regular, SemiBold) as Latin subsets,
"516 KB for six faces" (`docs/ROKU-DESIGN.md` §13, `roku/fonts/`, license in
`roku/fonts/LICENSE.md`); the web root sets `--font-display: "Fraunces", "New
York", ui-serif, Georgia, serif` (`css/styles.css`) while `docs/WEB-DESIGN.md`
says "System font stack; no webfonts (no build step, no FOUT)"; the Apple apps use
the system fonts. So the sibling already has a precedent: **system faces on Apple
and Android, bundled open faces only where the platform has none worth using
(Roku) or for the display voice.**

### 3.2 Platform norms (quoted)

- Apple: "SF Pro is the system font in iOS and iPadOS ... macOS ... tvOS"; "don't
  embed system fonts"; custom fonts must "implement the same behaviors" as
  Dynamic Type and Bold Text; tvOS default text size 29 pt, minimum 23 pt
  ([HIG, Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
  Fixed-width digits in SF come from SwiftUI's `monospacedDigit()` — "Returns a
  modified font that uses fixed-width digits, while leaving other characters
  proportionally spaced" (iOS 13, tvOS 13, macOS 10.15, watchOS 6;
  [Font.monospacedDigit()](https://developer.apple.com/documentation/swiftui/font/monospaceddigit())).
- Android: Roboto is the platform default (Archive Watch's Android design doc uses
  `Typeface.SERIF` / `MONOSPACE` for its own voices, `docs/ANDROID-DESIGN.md`);
  Compose takes OpenType features through `TextStyle(fontFeatureSettings = "tnum")`
  (UNVERIFIED against the reference page this session; it is the documented
  property name in Compose's `TextStyle`).
- Roku: no system face worth the six levels, which is why Archive Watch bundles
  its own; the bundle counts against the channel package (`ROKU-DESIGN.md` §5.2
  and §13).
- Web: `font-variant-numeric: tabular-nums` with a self-hosted `.woff2` needs no
  build step; whether to break Archive Watch's "no webfonts" rule on the web is an
  owner call (B9).

### 3.3 Candidates, measured

Every face below is under the SIL Open Font License 1.1 (each sits in
`google/fonts/ofl/<name>/`, and its `METADATA.pb` says `license: "OFL"`). Feature
columns were read from the font files themselves.

**Display (series titles, wordmark) — period character:**

| Face | Period source (designer's own words) | Variable axes | Weights | `tnum` | Latin Ext-A/B glyphs | Reads at small size? |
|---|---|---|---|---|---|---|
| **Big Shoulders** (Patric King) | "condensed American Gothic ... based in Chicago's multiple histories in railway transport, public political action, and dance" | opsz 10-72, wght 100-900 | 9 named | no | 204 | yes: opsz axis built for it |
| **League Gothic** (League of Moveable Type) | "a revival of ... Alternate Gothic ... designed by Morris Fuller Benton for the American Type Founders Company in 1903" — the headline face of the radio-guide and newspaper era | wdth 75-100 | 1 | no | 131 | yes, at headline sizes; one weight only |
| **Jost** (Owen Earl) | "inspired by 1920s German sans-serifs" (Futura's era and shape) | wght 100-900 | 18 | **yes** | 135 | yes |
| **Josefin Sans** (Santiago Orozco) | "inspired by geometric sans serif designs from the 1920s"; x-height "half way from baseline to cap height, an unusual proportion" | wght 100-700 | 14 | no | 192 | weak at small sizes (low x-height) |
| **Limelight** (Nicole Fally, Sorkin Type) | "the classic high contrast art deco style ... often used to suggest the 1920's ... the theatre generally" | none | 1 | no | 132 | no: "extreme contrast ... most reliably ... at medium and large font sizes" |
| **Poiret One** (Denis Masharov) | "a hint of Art Deco and constructivism ... light forms" | none | 1 | yes | 187 | no: hairline single weight |
| Fraunces (Undercase Type) | Archive Watch's display face; "Old Style soft" serif (SOFT, WONK axes) | SOFT, WONK, opsz 9-144, wght 100-900 | 18 | no | 190 | yes |

Descriptions are quoted from each family's `DESCRIPTION.en_us.html` in
`github.com/google/fonts`. Limelight and Poiret One are single-weight display
faces and cannot carry three weights of the hierarchy; they are wordmark-only
options.

**UI and body (dates, cast, lists) — legibility and tabular figures:**

| Face | Basis | Variable axes | `tnum` | Default figures already equal width? | Latin Ext glyphs | Notes |
|---|---|---|---|---|---|---|
| **Public Sans** (USWDS) | "Based on Libre Franklin" (itself Benton's 1912 Franklin Gothic) | wght 100-900 | **yes** (also `lnum`, `onum`) | no | 168 | US government's own interface face; Franklin is the American broadcast-era grotesque |
| **Inter** (Rasmus Andersson) | Archive Watch's UI face | opsz 14-32, wght 100-900 | **yes** | no | 334 | the widest coverage here; a direct sibling link |
| **IBM Plex Sans** | grotesque | wdth 75-100, wght 100-700 | no feature, but **default figures are tabular** | **yes** | 161 | dates align with no feature switched on |
| **Archivo** (Omnibus-Type) | grotesque | wdth 62-125, wght 100-900 | **yes** | no | 207 | width axis lets one family be both display and UI |
| **Atkinson Hyperlegible Next** (Braille Institute) | designed for low-vision readers | wght 200-800 | **yes** | no | 99 | the accessibility choice (05 §7.3); fewer Latin Extended glyphs |
| **Radio Canada Big** | CBC/Radio-Canada's corporate face | wght 400-700 | yes | no | 146 | a broadcaster's own face; the name is another broadcaster's, so a poor brand fit |
| Libre Franklin (Impallari) | Franklin Gothic 1912 | wght 100-900 | **no** | no | 194 | lacks `tnum` in the shipped build — Public Sans is the same design with it |

### 3.4 Recommended pairing and the six levels

Recommendation (owner decides, B6/B7): **Big Shoulders for display, Public Sans
for the UI face where a face must be bundled (Roku, the web, the TV web layer,
store art), and the system face with tabular digits on Apple (SF Pro +
`monospacedDigit()`) and Android (Roboto + `tnum`) for body text.** Reasons: both
are OFL and variable; Big Shoulders is a condensed American gothic with an
optical-size axis, so a long series title (*The Mercury Theatre on the Air*) fits
a card at one size without a second face; Public Sans is Franklin Gothic's
descendant with real tabular figures, so `1943-05-25` columns align; neither is
Archive Watch's face, yet both are grotesque/gothic where Archive Watch is a soft
serif — a family resemblance in structure (one display face, one sans), not a copy.
The alternative that keeps the two apps closest is **Fraunces + Inter** unchanged
(B6).

The six levels (three weights x two sizes, CLAUDE.md; the six roles named in 05
§3.2):

| Level | Role (05 §3.2) | Face | Weight | Size |
|---|---|---|---|---|
| 1 | Series title | display | Bold (700) | large |
| 2 | Section heading | display | SemiBold (600) | small |
| 3 | Episode title | UI | SemiBold (600) | large |
| 4 | People (body) | UI | Regular (400) | large |
| 5 | Date and network (caption), **tabular** | UI | Regular (400) | small |
| 6 | Eyebrow (ON NOW / AUDITION / PART 3 OF 5) | UI | SemiBold (600), caps, tracked | small |

That is three weights (700, 600, 400) and two sizes per platform, the sizes set
per platform as Archive Watch does (tvOS minimum 23 pt per HIG; Roku multiples of
3 per ROKU-DESIGN §13). The wordmark is level 1's face set by hand once, as an
outlined vector, and is not a seventh level of the interface.

---

## 4. Brand chrome palette

### 4.1 Constraints

- Decision 013 and CLAUDE.md: "never use a brand color for content meaning, never
  use a semantic color for chrome." 05 §3.3 proposes eight genre accents:
  `#FF5C35` drama, `#2D5BFF` mystery, `#7C5BBA` science fiction, `#C9A66B`
  western, `#FF4D8D` comedy, `#8A8F98` news, `#3FA796` documentary, `#E8A317`
  serials. **Archive Watch's own primary `#FF5C35` is in that list (drama)**, and
  its accent `#0047FF` is CIEDE2000 5.6 from the mystery accent `#2D5BFF`, so
  Ear Drama cannot reuse either Archive Watch chrome color without breaking the
  split.
- The free hues are red (~355°), cyan (~195°), green and yellow. Red is the
  period's broadcast color: the studio's ON AIR tally light. Cyan reads as dial
  glass and is far from every genre accent.
- WCAG 2.2: 4.5:1 for body text, 3:1 for large text and for UI components and
  graphical objects (SC 1.4.3, 1.4.11).

### 4.2 Proposal (numbers MEASURED with the WCAG relative-luminance formula and CIEDE2000)

| Token | Light | Dark | Use |
|---|---|---|---|
| `--color-primary` | `#C8102E` | `#C8102E` | CTA fills, ON AIR / now-playing mark, the wordmark |
| `--color-on-primary` | `#FFFFFF` | `#FFFFFF` | text on primary fills |
| `--color-accent` | `#0B6E99` | `#5AB4D6` | links, focus, interactive |
| `--color-bg` | `#FFFFFF` | `#0A0A0A` | page |
| `--color-text` | `#0A0A0A` | `#F5F1EA` | body |
| `--color-text-secondary` | `#6B6B6B` | `#9A9AA0` | captions |
| `--color-border` | `#E0E0E0` | `#2B2A2E` | hairlines |

The neutrals are Archive Watch's own (`#FFFFFF`, `#0A0A0A`, `#E0E0E0`, and
`#0A0A0A` as the dark ground that Archive Watch's Roku splash and web
`theme_color` already use) — that is the sibling tie; the primary and accent are
Ear Drama's own.

Contrast:

| Pair | Ratio | Passes |
|---|---|---|
| `#C8102E` text on `#FFFFFF` | 5.88 | AA body |
| `#FFFFFF` on `#C8102E` fill | 5.88 | AA body |
| `#F5F1EA` on `#C8102E` fill | 5.23 | AA body |
| `#C8102E` mark on `#0A0A0A` | 3.37 | 3:1 non-text only — **do not set red text on dark**; use it as a fill with white text |
| `#0B6E99` on `#FFFFFF` | 5.67 | AA body |
| `#FFFFFF` on `#0B6E99` | 5.67 | AA body |
| `#5AB4D6` on `#0A0A0A` | 8.42 | AAA body |
| `#0A0A0A` on `#FFFFFF` | 19.80 | AAA |
| `#F5F1EA` on `#0A0A0A` | 17.59 | AAA |
| `#6B6B6B` on `#FFFFFF` | 5.33 | AA body |
| `#9A9AA0` on `#0A0A0A` | 7.07 | AAA |
| `#E0E0E0` on `#FFFFFF`, `#2B2A2E` on `#0A0A0A` | 1.32, 1.39 | decorative hairlines only (not a boundary a control depends on) |

Distance from the genre accents (CIEDE2000; ≥ 10 is clearly distinct side by
side): `#C8102E` → drama 20.7, comedy 23.1; `#0B6E99` → mystery 15.5, news 22.6;
`#5AB4D6` → news 19.5, documentary 20.1. From Archive Watch: `#C8102E` is 20.7
from `#FF5C35`.

Rejected on the numbers: a brighter dark-mode red (`#FF4B4B` … `#F2545B`) sits
8.4-11.7 from the drama accent and 10.5-16 from comedy, so a red bright enough
to be TEXT on black reads as a genre; hence one red for both modes, used as a
fill. `#0047FF` (Archive Watch's accent) is 5.6 from mystery.

A warm "radio-guide paper" ground (`#FAF7F2`) was measured too (primary 5.51,
accent 5.30 on it) and is an owner option (B12); it is not the default because it
breaks the shared neutral.

### 4.3 Found along the way, for 05 §3.3

Three of the proposed genre accents fall below 3:1 as marks on white:
`#C9A66B` western 2.30, `#E8A317` serials 2.17, `#3FA796` documentary 2.93
(drama 3.07, comedy 3.14 and news 3.25 barely pass). On `#0A0A0A` every accent
passes (3.82-9.13). If genre rules are drawn on a light ground they need a darker
tone in light mode; this belongs to Q11 (RADIO-DRAMA §7), not to the chrome.

---

## 5. Every required graphic asset, per platform

Read 2026-10-21 from each vendor's page unless marked. "AW" names the file
Archive Watch ships for the same slot today (sizes measured from the files), as
a working reference.

### 5.1 Apple (iOS, iPadOS, macOS, tvOS, watchOS, CarPlay, App Store)

Sources: [HIG App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
(Specifications table), [HIG Top Shelf](https://developer.apple.com/design/human-interface-guidelines/top-shelf),
[HIG CarPlay](https://developer.apple.com/design/human-interface-guidelines/carplay),
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications),
[App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications),
[Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets).

| Asset | Spec (quoted or measured) | Notes | AW today |
|---|---|---|---|
| iOS / iPadOS / macOS app icon | Square layout, **1024x1024 px**, "Layered"; appearances "Default, dark, clear light, clear dark, tinted light, tinted dark"; built in **Icon Composer** ("define the background layer ... annotate for default, dark, and mono appearance variants ... export your icon for use in Xcode"); sRGB, Gray Gamma 2.2 or Display P3 | "the system automatically generates variants you don't provide"; "Prefer vector graphics"; "For mesh gradients and raster artwork, prefer PNG"; provide unmasked square layers | `AppIcon.appiconset`: one flat 1024 PNG for iOS plus macOS 16-1024 PNGs; no Icon Composer file, no dark/tinted |
| tvOS app icon | Rectangle **800x480 px** layout (400x240 pt @1x / 800x480 @2x), "Layered (Parallax)", **two to five layers**; keep a safe zone because "the system crops foreground layers more than background layers"; text, if any, on the top layer | built as an Xcode image stack (not Icon Composer); preview with Parallax Previewer | `App Icon.imagestack` Back + Front at 400x240 and 800x480; Middle layer empty |
| tvOS App Store icon | **1280x768**, same image stack | role `primary-app-icon`, size `1280x768` in the brand-assets `Contents.json` | `App Icon - App Store.imagestack` 1280x768 |
| tvOS Top Shelf (static) | HIG: "If you don't provide the recommended full-screen content, supply at least one static image as a fallback" — **2320x720 pt (2320x720 px @1x, 4640x1440 px @2x)** | dynamic Top Shelf content (carousel, sectioned rows: poster 404x608, square 608x608, 16:9 908x512 pt; inset banner 1940x692 pt) is preferred; for Ear Drama it would be the listener's own Continue items, with art only where a series has it | `Top Shelf Image Wide` 2320x720 and `Top Shelf Image` 1920x720 (the older second slot Xcode still offers) |
| watchOS app icon | Square **1088x1088 px**, circular mask, layered; "Avoid using black for your icon's background" | only if a watch app ships (B16) | none |
| CarPlay app icon | **120x120 (@2x), 180x180 (@3x)**; "Mirror your iPhone app icon"; "Don't use black for your icon's background. Lighten a black background or add a border" | generated from the main icon by Xcode; **the no-black rule bears on any near-black ground** (Archive Watch's tvOS ground is RGB 8,7,6) | — |
| CarPlay artwork | "Supply high-resolution images with scale factors of @2x and @3x for all CarPlay artwork" | an audio app's list rows and Now Playing show item artwork (`MPMediaItemArtwork`); most episodes have none (05 §3.1), so what Now Playing shows then is a decision (B17) | — |
| iPhone screenshots | Required: "iPhone with Dynamic Island (medium display)" — **1206x2622** or 1179x2556 portrait (or landscape); large display 1320x2868 / 1290x2796 / 1260x2736; up to 10 per size; .jpeg/.jpg/.png; "Images can't include alpha channels" | iPhone Duo: outer 1398x2034, inner 2007x2853; "Starting in April 2027, screenshots will be required for any app using the iOS 27.1 SDK or later" | `tools/appstore_shots.py` slots `iphone`, `duo` |
| iPad screenshots | Required if the app runs on iPad: 13" **2064x2752** or 2048x2732 | 11": 1488x2266, 1668x2420, 1668x2388 | slot `ipad` |
| Mac screenshots | 16:10: 1280x800, 1440x900, 2560x1600, **2880x1800** | | `tools/mac-screenshots.sh` |
| Apple TV screenshots | **1920x1080** or **3840x2160** | | slot `tv` |
| Apple Watch screenshots | one of 422x514 (Ultra 4/3), 410x502, 416x496 (Series 12/11/10), 396x484, 368x448, 312x390 | only with B16 | — |
| App previews (optional) | 15-30 s, ≤ 500 MB, H.264 (.mov/.m4v/.mp4) or ProRes 422 HQ; "macOS and tvOS app previews accepted in landscape only"; Mac and Apple TV 1920x1080; iPhone large display 886x1920 | an audio app's preview is a screen recording with sound | none |
| Product page header (Asset Library) | **3840x1646 (21:9), PNG** | optional "creative asset"; Apple: keep the focal point centered | `assets/app-store/header-21x9-3840x1646.png` by `tools/make_store_header.py` |
| Search results asset (Asset Library) | **2752x1835 (3:2)** | optional | `assets/app-store/search-3x2-2752x1835.png` |

The header and search sizes are from Archive Watch's own working uploads
(`tools/make_store_header.py`, which cites "the API's 21:9 header spec
(i3840x1646a0)", and `tools/asc_asset_library.py`); Apple's help page names the
placements but its size table was not found in the page text read here.

### 5.2 Android, Google Play, Android TV / Google TV, Android Auto

Sources: [Adaptive icons](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive),
[Google Play icon design specifications](https://developer.android.com/distribute/google-play/resources/icon-design-specifications),
[Play preview assets](https://support.google.com/googleplay/android-developer/answer/9866151),
[TV: get started — home screen banner](https://developer.android.com/training/tv/get-started/create).

| Asset | Spec | Notes | AW today |
|---|---|---|---|
| Adaptive launcher icon | foreground + background layers, "Size all layers to **108x108 dp**"; "The outer 18 dp on each of the four sides ... is reserved for masking"; **66x66 dp safe zone**; logo "at least 48x48 dp ... must not exceed 66x66 dp"; no masks or shadows on the layers; `res/mipmap-anydpi-v26/ic_launcher.xml` | legacy density PNGs for API < 26 (Fire TV's floor is 23, Decision 165) | `mipmap-anydpi-v26/ic_launcher.xml`, xxxhdpi foreground 432x432 px (=108 dp x 4) |
| Monochrome (themed) layer | optional; "starting with Android 13 (API level 33), users can theme their adaptive icons"; "Starting with Android 16 QPR 2, Android automatically themes app icons for apps that don't provide their own" | so even with no monochrome layer, Android 16 QPR 2+ launchers will derive one; a cut-out object (B4) is what makes a hand-made one possible | none, by the owner's rule |
| Play store icon | **512x512**, 32-bit PNG, sRGB, ≤ 1024 KB; "Full square – Google Play dynamically handles masking. Radius will be equivalent to 30% of icon size"; no shadow | | — |
| Feature graphic | **1024x500**, JPEG or 24-bit PNG (no alpha); required; "Do not use prominent branding that is similar to your app icon"; keep the focal point central (cut-off zones); "avoid using pure white, black, or dark gray"; no "Best", "#1", "Free" | words in it are the owner's (B15) | — |
| Phone screenshots | at least 2 across device types; JPEG or 24-bit PNG; min dimension 320 px, max 3840 px, long side ≤ 2x short; for promotional formats "at least four screenshots with minimum 1080px resolution", 16:9 (≥ 1920x1080) or 9:16 (≥ 1080x1920) | | — |
| Tablet / Chromebook screenshots | "a minimum of 4", 1,080-7,680 px, 16:9 or 9:16 | | — |
| Android TV screenshots + TV banner (listing) | "at least one Android TV screenshot"; "A banner asset is required to publish an Android TV-enabled app": **1280x720**, JPEG or 24-bit PNG (no alpha) | | `assets/tv/tv-banner-1280x720.png` (`tools/make_tv_banner.py`) |
| TV home-screen banner (in APK) | `android:banner`; "use an xhdpi resource with a size of **320 x 180 px**. Text must be included in the image. If your app is available in more than one language, you must provide separate versions of the banner with text for each supported language" | text is the owner's (B15) | `res/drawable-xhdpi/tv_banner.png` 320x180 |
| Wear OS screenshots | 1:1, ≥ 384x384, interface only | only if Wear ships | — |
| Android Automotive OS screenshots | if provided: "at least 2 portraits (800 px by 1,280 px) and 2 landscape (1,024 px by 768 px)"; screenshots "Optional for apps in one of the parked app categories" | Android **Auto** (projected) has no separate store art found; UNVERIFIED | — |
| Preview video | a YouTube URL; optional | | — |

### 5.3 Amazon Fire TV

Source: [Amazon Appstore — Appstore details](https://developer.amazon.com/docs/app-submission/appstore-details.html).

| Asset | Spec (quoted) |
|---|---|
| Fire TV App Icon (required) | **1280 x 720px**, "PNG (no transparency)"; "The 882 x 448px area represents where the main subject and title art are safe" (badges may cover the rest) |
| Fire TV Background Image (required) | **1920 x 1080px** (landscape), "JPG or 24-bit PNG (no transparency)"; appears top-right on a mini-detail page and can fill the background |
| Fire TV screenshots | "a minimum of 3 and a maximum of 10"; **1920 x 1080px** (landscape), JPG or 24-bit PNG (no transparency); not covered by badging |
| Icons (required for every listing) | **114 x 114px** (small) and **512 x 512px** (large), "PNG (transparent)"; "Do not just scale up the PNG image of your icon" |
| Feature Rotator | listed under Fire TV assets; size not read here (UNVERIFIED) |

Archive Watch submits these through `tools/submit-amazon.py` (Decision 111/115).

### 5.4 Roku

Sources: [Roku channel manifest](https://developer.roku.com/docs/developer-program/getting-started/architecture/channel-manifest.md);
Archive Watch `docs/ROKU-SUBMISSION.md` and `docs/roku-store-listing.md`.

| Asset | Spec | AW today |
|---|---|---|
| `mm_icon_focus_fhd` | **540x405** — "The app will not appear on devices or be accessible after publication without this attribute pointing to a valid image" | `roku/images/icon_focus_fhd.png` 540x405 |
| `mm_icon_focus_hd` | **290x218** | 290x218 |
| `mm_icon_focus_sd` | not given a size on the page read; AW ships 246x140 | 246x140 |
| `splash_screen_fhd` | **1920x1080** ("scaled down for HD display mode") | 1920x1080 (+ hd 1280x720, sd 720x480) |
| `splash_color` | a hex color (AW `#0A0A0A`) | `#0A0A0A` |
| Store poster | 540x405 (AW: "App poster 540 × 405") | `store_poster_fhd.png` 540x405 (`tools/roku_store_poster.py`) |
| Store screenshots | "up to 6, 1920 × 1080" (AW doc) | six QA captures |
| Search provider logo | 143x113 (AW `ROKU-SUBMISSION.md`, file `search_provider_logo_143x113.png`) | gitignored |

### 5.5 Web, PWA, LG webOS, Samsung Tizen, social

| Asset | Spec | Source | AW today |
|---|---|---|---|
| Manifest icons | **192x192** and **512x512**, `purpose: "any"` | [web.dev, Maskable icons](https://web.dev/articles/maskable-icon) (and Chrome's install criteria) | one 256x256 `any` (`manifest.json`) |
| Maskable icon | "The important parts of your icon ... must be within a circular area in the center of the icon with a radius equal to **40% of the icon width**. The outer 10% edge might be cropped" | web.dev (same) | none |
| Favicon, apple-touch-icon | AW uses the 256 PNG for both; Apple's preferred touch-icon size not read here (UNVERIFIED) | `index.html` | `assets/app-icon/favicon.png` |
| Open Graph image | "Use images that are at least **1200 x 630** pixels"; minimum 200x200; ≤ 8 MB; "as close to **1.91:1** ... as possible" | [Facebook, Images in link shares](https://developers.facebook.com/docs/sharing/webmasters/images) | `og:image` = the square app icon |
| X (Twitter) large card | 2:1 (UNVERIFIED — page did not render its text) | developer.x.com | — |
| webOS | `icon` **80x80**, `largeIcon` **130x130**, `splashBackground` (AW 1920x1080), `iconColor`, `bgColor` | [webOS appinfo.json](https://webostv.developer.lge.com/develop/references/appinfo-json) (example file names `AppName_80x80.png`, `AppName_130x130.png`) | `tv/webos/` 80, 130, 1920x1080; `iconColor` `#FF5C35` |
| Tizen | `config.xml` `<icon>` | Samsung's required size not read here (UNVERIFIED); AW ships 512x512 | `tv/tizen/icon.png` 512x512 |
| webOS / Tizen store screenshots | AW: webOS 1280x720 (`docs/webos-submission.md`); Samsung per its Seller Office (`docs/tizen-submission.md`) | AW docs | — |

### 5.6 The checklist

One master, one tool per derived size, as Archive Watch does (§6). "Text" marks
assets whose words the owner writes.

| # | Platform | Asset | Size (px) | Format | Text | Master it derives from |
|---|---|---|---|---|---|---|
| 1 | iOS/iPadOS/macOS | Icon Composer icon (light, dark, tinted) | 1024x1024 layers | `.icon` (PNG/SVG layers) | no | icon master |
| 2 | macOS (pre-Icon Composer builds) | appiconset 16-1024 | 16, 32, 64, 128, 256, 512, 1024 | PNG | no | icon master |
| 3 | tvOS | app icon image stack, 2-5 layers | 400x240, 800x480 | PNG layers | optional, top layer | icon master + cut-out |
| 4 | tvOS | App Store icon stack | 1280x768 | PNG layers | as above | same |
| 5 | tvOS | Top Shelf static fallback | 2320x720 @1x, 4640x1440 @2x | PNG | optional | wide master |
| 6 | watchOS (B16) | icon | 1088x1088 | layers | no | icon master |
| 7 | CarPlay | icon (auto) + list/Now Playing artwork | 120, 180; artwork @2x/@3x | PNG | no | icon master; B17 |
| 8 | App Store | screenshots iPhone, iPad, Mac, TV (+ Duo from April 2027) | 1206x2622, 2064x2752, 2880x1800, 3840x2160; Duo 2007x2853 / 1398x2034 | PNG, no alpha | captions only if the owner writes them | the app |
| 9 | App Store | header 21:9, search 3:2 (optional) | 3840x1646, 2752x1835 | PNG | no (AW rule) | wide master |
| 10 | Android | adaptive icon fg/bg (+ monochrome, B14) | 108 dp (432 px xxxhdpi) + legacy densities | PNG/vector | no | icon master + cut-out |
| 11 | Play | store icon | 512x512 | 32-bit PNG ≤ 1 MB | no | icon master |
| 12 | Play | feature graphic | 1024x500 | JPEG/24-bit PNG | owner | wide master |
| 13 | Play | phone, tablet, TV screenshots | ≥ 1080 short side, 16:9/9:16 | JPEG/24-bit PNG | — | the app |
| 14 | Play / Google TV | TV banner (listing) | 1280x720 | JPEG/24-bit PNG | owner | wide master |
| 15 | Android TV | `android:banner` | 320x180 xhdpi, one per language | PNG | owner, required | wide master |
| 16 | Fire TV | app icon | 1280x720 (safe 882x448) | PNG, no alpha | owner (title art) | wide master |
| 17 | Fire TV | background | 1920x1080 | JPG/24-bit PNG | no | wide master |
| 18 | Fire TV | screenshots | 1920x1080, 3-10 | JPG/24-bit PNG | — | the app |
| 19 | Amazon (all) | small and large icon | 114x114, 512x512 | PNG (transparent) | no | icon master |
| 20 | Roku | focus icons | 540x405, 290x218 (+ 246x140) | PNG | owner (AW poster carries the name) | wide master |
| 21 | Roku | splash | 1920x1080 (+ 1280x720, 720x480) | PNG/JPG | optional | wide master |
| 22 | Roku | store poster, screenshots, search logo | 540x405; 1920x1080 x6; 143x113 | PNG | owner | wide master |
| 23 | Web | manifest 192, 512 any + 512 maskable | 192, 512 | PNG | no | icon master |
| 24 | Web | favicon, apple-touch-icon | 32 / 180 (UNVERIFIED) | PNG | no | icon master |
| 25 | Web | Open Graph | 1200x630 | PNG/JPG | owner, if any | wide master |
| 26 | webOS | icon, largeIcon, splash | 80x80, 130x130, 1920x1080 | PNG | no | icon master |
| 27 | Tizen | icon | 512x512 (AW) | PNG | no | icon master |

Two masters cover everything: a **square icon master** (1024 or larger, with the
object cut out on its own layer) and a **wide master** (3840x2160 or larger, the
same image at its own aspect over an ambient wash, Decision 097 — how
`make_store_header.py` already composes the App Store header).

---

## 6. Reusing Archive Watch's asset tooling

| Archive Watch tool | What it does | Lift for Ear Drama | What must change |
|---|---|---|---|
| `tools/render-app-icon.py` | Grades the Méliès still (contrast, sepia blend), frames it as a film cell, writes the tvOS App Icon + Top Shelf imagestacks | **Adapt**: the imagestack writing and the grade | The film-strip frame is cinema-specific; source path; it writes a flat Back layer and an empty Front — an Ear Drama object icon should write a real Front layer (cut-out) so tvOS parallax works |
| `tools/make_tv_banner.py` | Renders both Android TV banners (1280x720 Play listing, 320x180 `android:banner`) natively from the icon master, with a `--check` mode | **Reuse** the two-size logic and `--check` | Colors (`ORANGE`, `INK`), fonts (it reads macOS system faces first), the master path; the banner TEXT is the owner's (Android requires text in the banner) |
| `tools/make_store_header.py` | App Store product-page header 3840x1646 (21:9) from a frame: subject centered, ambient wash of the same image, no text | **Reuse** as is in shape | Source image; the "moon center" constant becomes the object's center |
| `tools/roku_store_poster.py` | 540x405 Roku store poster: still + wordmark band, gradient scrim, never reshapes the still | **Adapt** | Fonts (`roku/fonts` Fraunces/Inter → B6), the 96x7 orange rule (Archive Watch's), the wordmark |
| `tools/asc_asset_library.py` | App Store Connect Asset Library (API 4.5, 2026-10-05): reserve / upload / commit / place / order screenshots, header and search assets | **Reuse as is** | Credentials and app id only; `placementGroup` values are Apple's, not ours |
| `tools/asc_stage_assets.py` | Places uploaded images on a new version by slot | **Reuse** | Slot naming prefix |
| `tools/appstore_shots.py` | Captures the screenshot set from simulators through DEBUG start doors (`AW_START_TAB`, `AW_SHOWCASE=1`), refuses wrong pixel sizes, flattens alpha | **Adapt** | The doors are Archive Watch's env vars; the slot table (sizes) carries over unchanged; Showcase's rules ("hero-tier rights, professional art, no horror") become radio rules |
| `tools/mac-screenshots.sh`, `tools/tv_screenshots.sh` | Mac (16:10 framed) and Apple TV sets | **Adapt** | App name, doors |
| `tools/test_app_banner.mjs` | Tests the web app-banner | **Adapt** | — |
| `tv/build-tv-packages.sh` + `tv/webos/appinfo.json` (80x80 icon, 130x130 largeIcon, 1920x1080 splash, `iconColor`) + `tv/tizen/config.xml` (512x512 icon) | Packages webOS / Tizen from the web root | **Reuse** | `iconColor` is `#FF5C35` today — Ear Drama's primary; ids; the Tizen 2022 floor (Decision 162) carries over |
| `manifest.json` (web) | One 256x256 `any` icon | **Fix while lifting** | Add 192 and 512 `any` plus a 512 `maskable` (see §5); Archive Watch itself has no maskable icon |
| `roku/fonts/` + `ROKU-DESIGN.md` §13 type table | Bundled Latin-subset faces | **Reuse the method** | New faces (B6) and their `LICENSE.md` |

What does not carry: anything tied to posters (`validate_posters.py`'s
TMDb-art logic beyond URL liveness), the Showcase rights tier, and the film-strip
motif.

---

## 7. Owner decisions

- **B1** Are eardrama.com and eardrama.app (registered 2026-10-13 at Cloudflare) yours; if not, is eardrama.org (available) the home?
- **B2** Commission a trademark clearance opinion on "Ear Drama" against EARPLAY (Reg. IC 009 / IC 041) before the store listing?
- **B3** File a US trademark application for "Ear Drama" (IC 009 software, IC 041 entertainment)?
- **B4** Icon kind: a period photograph (Archive Watch's rule) or a cut-out period object on a flat ground (what reads at 29-40 px and gives tvOS a real parallax layer)?
- **B5** Which candidate in §2.3 (or none — keep looking)?
- **B6** Type: Big Shoulders + Public Sans, or Fraunces + Inter shared with Archive Watch?
- **B7** Body text in the system face (SF / Roboto) on Apple and Android, with the bundled face only on Roku, web and store art?
- **B8** Wordmark: set in the display face by the owner or a human designer (not generated)?
- **B9** Web: allow self-hosted webfonts for Ear Drama, unlike Archive Watch's "no webfonts" rule?
- **B10** Palette: on-air red `#C8102E` + dial cyan `#0B6E99`/`#5AB4D6` on Archive Watch's neutrals?
- **B11** Red as a fill only in dark mode (no red text on black), as the contrast numbers require?
- **B12** Ground: Archive Watch's white/`#0A0A0A`, or a warm paper `#FAF7F2` in light mode?
- **B13** Provide dark and tinted iOS icon variants by hand, or let the system generate them?
- **B14** Android monochrome themed-icon layer: provide one (an object silhouette allows it), or none as Archive Watch does?
- **B15** Every text-bearing asset (Android TV banner, Roku poster, Fire TV icon, Play feature graphic, Top Shelf) carries words: the owner writes them.
- **B16** Ship a watchOS app in v1 (05 §6 proposes Continue + downloads only), which adds a 1088x1088 icon?
- **B17** What lock screen, CarPlay and Android Auto Now Playing show for an episode with no art: the app's own square brand artwork, the series photograph when one has passed rights, or nothing?
- **B18** Take (or commission) a new CC0 photograph of an RCA 44 or 77 in a museum (as Daderot did for candidate 1), if the owner wants that microphone rather than the Western Electric ring?
