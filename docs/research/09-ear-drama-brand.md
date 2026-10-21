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
`api.wikimedia.org/core/v1/commons/search/page` and licence reads through
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
was reduced to 29, 40, 60, 120 and 180 px (image at
`/tmp/claude-0/img/dorn_small.png` this session). At 29 and 40 px the
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
licence. Smithsonian Open Access returned the National Museum of American
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

ICON_CANDIDATES_PLACEHOLDER

---

## 3. Wordmark and typography

### 3.1 What Archive Watch uses

Archive Watch's Roku channel bundles **Fraunces** (Display Black, Display
SemiBold, Text Italic) and **Inter** (Medium, Regular, SemiBold) as Latin subsets,
"516 KB for six faces" (`docs/ROKU-DESIGN.md` §13, `roku/fonts/`, licence in
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

PLATFORM_TABLE_PLACEHOLDER

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
