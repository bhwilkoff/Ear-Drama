---
name: uniform-imagery-design
description: Use when images you did not make (archival photographs, halftone scans, cartoons, title cards, lobby cards, plaques, group photos, user uploads) must read as ONE set in a repeated slot (a face wall, a show tile, a list thumbnail, a card) even though they differ in size, shape, tone, crop and quality. Carries the rule that uniformity comes from the presentation (one crop rule, one tonal grade, one mount, one edge, one size floor) and never from changing what a picture shows; the decision tree by slot and by source condition; the grade (neutral monochrome plus measured levels, inside normal news-photo limits) and why genre duotone, sepia, colorization and AI upscaling are refused; the mount in the genre hue; minimum-size rules and the typographic fallback; what is measured once in the pipeline versus applied per platform (SVG filter, Core Image, Compose ColorMatrix); and the CDN implications. Triggers on uniform images, consistent thumbnails, mixed image quality, "make the images match", grayscale, monochrome, duotone, sepia, tint, image filter, normalize images, contrast, levels, matte, mount, frame, face wall, artist grid, low-resolution image, tiny thumbnail, halftone, cartoon, colorize, upscale, image restoration.
---

# Uniform Imagery Design

How a set of pictures that were never meant to sit together (a 95 px
newspaper halftone beside a 4,032 px color snapshot, a cartoon beside a
studio portrait) reads as one designed set in a grid, without lying
about any of them. `artwork-presentation-design` decides the slot's
shape and where a crop centers; `image-cdn-discipline` decides how the
bytes arrive. This skill is what makes forty of them look like one
family once they arrive.

## The one rule

**Make the presentation uniform, never the picture.** A set reads as
one when every member gets the same crop rule, the same tone, the same
mount, the same edge and the same size floor. Nothing that changes what
a picture depicts is allowed: no added color, no invented detail, no
retouched face, no generated fill. The page that is about one picture
(Detail, a person page) shows the original, ungraded, with its credit.

Why: the owner, 2026-10-29: *"Images of people and of the shows
themselves are the most appealing for any user to use as a way of
browsing and selecting items. However, with no real way to standardize
the images (dimentions, quality, etc.), we will need to create skills to
allow for everything to look uniform even though it is not."* And:
*"Graphics count just as much as photos."* The archive's own rule
allows it: US federal digitization guidance forbids retouching a master
but approves "image processing techniques ... for the creation of
access files", which "may be cropped" ([FADGI 2016](https://www.archives.gov/files/digitization/fadgi-2016-rev-1.pdf)).
A grid tile is an access file. The original stays one tap away.

## What the references do

| Source | What it does | Lesson |
|---|---|---|
| Spotify's 2015 identity by Collins | Duotone over artist photos, because every service gets the same label images: "a great way to reinterpret those images so that they're recognisably on-brand" ([Transform](https://www.transformmagazine.net/articles/2015/spotify-gets-visceral/)) | Duotone is a **brand device on photos of living artists who supplied them**, for marketing. It is not a way to show an archive. |
| Spotify for Artists | Minimum sizes (avatar 750 by 750), "Don't include text, advertising, or busy backgrounds" ([Spotify](https://support.spotify.com/artists/article/artist-image-guidelines)) | Uniformity starts with a **quality floor**; below it, the slot does not take the image. |
| Apple Music artist images | "Do not upscale images"; no borders; the crop keeps "eyebrows and lips" inside the frame ([Apple](https://artists.apple.com/support/88-artist-image-guidelines)) | **A fixed crop around the face plus a floor**, no tint. Upscaling is refused even by a supplier-controlled catalog. |
| FADGI (US federal digitization) | "No image retouching is permitted to master files"; processing is approved for access files; derivatives are "each optimized for a particular use" ([FADGI](https://www.archives.gov/files/digitization/fadgi-2016-rev-1.pdf)) | Masters untouched; **display copies may be cropped and leveled**. |
| IIIF Image API 3.0 | `gray` and `bitonal` are standard `quality` values beside `color`: a rendering requested from the same image ([IIIF](https://iiif.io/api/image/3.0/)) | **Gray is a standard presentation** of a color original, not an edit to it. |
| Rijksmuseum (Q42, Fabrique) | Image first; "the visitor always sees the correct crop and the correct size image"; no tonal treatment described ([Q42](https://q42.nl/en/work/rijks-website1)) | The collection site's uniformity is **crop and size**, set per image. |
| AP photo rules | "Minor photo editing, including cropping and toning and color adjustments ... for clear and accurate reproduction" allowed; changes in "density, contrast, color and saturation levels that substantially alter the original scene" not ([AP, quoted by PBS](https://www.pbs.org/newshour/world/why-news-organizations-retracted-the-princess-of-wales-photo)) | **Leveling exposure and contrast is accepted practice**; a change that alters how the scene reads is not. |
| NPPA contest rules | "Normal limits of toning and color correction"; a gray sky turned blue is out; generative AI "expressly prohibited" ([NPPA BOP 2025](https://site.picter.com/nppa-bop-2025)) | The **limits are numbers you can hold**: a bounded stretch, no hue the scene did not have, nothing generated. |
| Vice and the S-21 portraits (2021) | Colorized portraits of Khmer Rouge victims, with smiles added, pulled within hours; "He is falsifying history" ([Hyperallergic](https://hyperallergic.com/vice-removed-altered-photos-of-cambodian-genocide-victims)) | **Colorization and retouching are the line.** The harm was content changed and the original not shown. |
| American Historical Association | Colorizing raises consent, misidentification, altered expressions and lost context; it can be inquiry when done "prudently" ([AHA Perspectives](https://www.historians.org/perspectives-article/colorizing-photos-from-the-past-the-ethics-of-making-history/)) | False color presented as real is refused here outright; it is research, not presentation. |
| Google Design, dark theme | Google Photos shows photos "without adjusting them", on dark gray, not black ([Google Design](https://design.google/library/material-design-dark-theme)) | In dark mode, **change the ground, not the photograph**. |
| GOV.UK Design System | Consistency is asked of illustrations ("consistent colours, line widths and border radiuses"); photos where realism matters, no generic stock ([GOV.UK](https://design-system.service.gov.uk/styles/images/)) | **Consistency lives in the frame**: radius, edge, ground. |
| CSS-Tricks duotone | SVG `feColorMatrix` to gray, then `feComponentTransfer` to map two colors ([CSS-Tricks](https://css-tricks.com/?p=263756)); CSS `grayscale()` is Baseline widely available ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/filter-function/grayscale)) | The web can apply an exact per-image linear grade cheaply, without touching the bytes. |

Not sourced, observed only: Spotify and Apple Music draw artists as
circles; Letterboxd shows every poster in a fixed 2:3 frame with a
placeholder; Criterion's covers share a house layout; Cooper Hewitt,
the Met, NYPL and Wellcome show collection images in grids as they are.
Library digitization projects (Chronicling America's microfilm scans)
show uneven scans as they are and spend the effort on the metadata
around them, per search summaries of the Library of Congress
([FDLP slides](https://fdlp.gov/sites/default/files/training/20221213-wn-chronicling-america-using-historical-newspapers-slides.pdf)).

### Respect, flatten, falsify

| Treatment | Verdict | Why |
|---|---|---|
| One crop rule at the published face box | **Respects** | Apple's own crop rule; the face survives; computed once |
| A mount, an inset, a hairline edge, one radius | **Respects** | Adds nothing to the picture; GOV.UK's frame consistency |
| A quality floor with a typographic fallback | **Respects** | Spotify's and Apple's floors; no invented pixels |
| Neutral monochrome in repeated slots, original on Detail | **Respects** | IIIF `gray`; FADGI access copies; removes no content, only the color cast of a print or a lab |
| Bounded levels (black and white points) | **Respects** | AP and NPPA "normal limits" |
| Genre-hue duotone or sepia over the photo | **Flattens** | Adds a hue the scene never had; reads as a colored photograph; Spotify's device for supplied images |
| Blur fill, gradient scrim, text over the photo | **Flattens** | `artwork-presentation-design` anti-patterns |
| Colorization | **Falsifies** | Color presented as real (S-21, AHA) |
| AI upscaling, "restoration", face enhancement, outpainting | **Falsifies** | Invented detail; NPPA bans generative tools; Apple bans upscaling |

## The decision tree

`a = width / height`; `cropPx` = the crop's side in source pixels
(`cropRect.h * height`, contract §3.3a); `slot` = the slot's side in CSS
points. A face is the pipeline's published box, never a device's guess.

### By source condition (applies in every repeated slot)

| Condition | Measured by | Treatment |
|---|---|---|
| **Has a face** (any shape) | `face` not null | The crop square around it (`cropRect`) |
| **Upright, no face** (`a < 0.9`) | `face` null | The top-anchored square (50% across, 20% down the slack). Mostly halftones and profiles the detector missed; head and shoulders sit near the top |
| **Square or wide, no face** (`a >= 0.9`) | `face` null | A **graphic** (a cartoon, a page, a scene, a title card): shown **whole**, contained on the print ground, never cropped blind. Below 48 points, the initial |
| **Group** | the pipeline's group box | The square around the whole group; never zoom to one face (someone else's) |
| **Tiny** | `cropPx < slot` | More than 2x upscale on a 2x screen: the slot does not take it. Show tile: the typographic card. Face wall: the initial. Header: drawn at no more than its own pixels |
| **Low contrast, too dark, too light** | the grade's levels | Stretched by the grade, within its limits; never past them |
| **Color, sepia, toned** | the grade's tone class | Neutral monochrome in repeated slots; the original on the page about it |
| **Text in the picture** (title cards, lobby cards, ads) | not measured | Kept: it is part of the evidence. Never add text over it |

### By slot

| Slot | Shape and crop | Grade | Mount and edge | Floor | Fallback |
|---|---|---|---|---|---|
| **Face wall** (people, 64 to 96 pt) | Circle at the face crop; a graphic whole in the inscribed square | Monochrome + levels | The print ground in the circle, 1 px hairline ring | `cropPx >= slot` | The initial on the surface |
| **Show tile** (grid cell, 96 to 160 pt) | Square at the face crop; a graphic whole | Monochrome + levels | **A board in the genre hue** (people and genre-less: the neutral surface-alt), the print inset 6 pt, inner radius 4 inside the card's 12, hairline edge; the name set on the board below, never on the picture | `cropPx >= slot` | The typographic card on the same board |
| **List thumbnail** (40 to 64 pt) | Square at the face crop; no graphic whole (too small to read): the initial | Monochrome + levels | Control radius, hairline | `cropPx >= slot` | The initial on the genre hue |
| **Card** (a feature, Home's large blocks) | The picture at its own aspect (`artwork-presentation-design` §3), height-bounded | Monochrome + levels when it sits among others; original when alone | The genre board around it | Width at most its own pixels | The large typographic card |
| **Hero / page header** (the page about it) | Whole, own aspect, beside or above the heading | **None: the original** | A hairline or thin mat, caption and credit under it | Never drawn larger than its own pixels | The typographic card |
| **Lock screen / system art** | The face crop, rendered once | **None** (the system shows it alone) | None | `cropPx` at least the art size the system asks for | The card rendered to an image |

Why monochrome in repeated slots but the original in headers: the set is
what needs to agree, and a set of 40 where 24% are color (hand-tinted
prints beside color snapshots) and 6% sepia reads as noise; one
picture alone has nothing to disagree with, and the page about it owes
the person the evidence as it is. Why the color goes on the board and
not into the photograph: the genre hue is content (Decision 064), the
board carries it at full strength, and the picture stays true.

## The treatments

### 1. Framing: one crop rule, computed once

Use the pipeline's face box and the one `cropRect` formula
(`artwork-presentation-design` §5, contract §3.3a). This skill adds the
graphic branch: a square or wide picture without a face is shown whole
inside the square on the print ground, because without a face a blind
crop of a cartoon or a lobby card shows the middle of a page.

### 2. The grade: neutral monochrome plus measured levels

One linear map on sRGB-encoded luminance, `out = k * in + o`, applied
after converting to gray (Rec. 709 weights: 0.2126, 0.7152, 0.0722).

- Measure **inside the crop the slot shows**, not the whole frame: the
  face is what the eye compares across tiles.
- `lo`, `hi` = the 1st and 99th percentile of luminance. Target: `lo`
  to 0.04, `hi` to 0.96. `k = 0.92 / (hi - lo)`, `o = 0.04 - lo * k`.
- **Limits** (the "normal limits"): `k` between 1.0 and 1.6. At 1.0 or
  below (already full range) the grade is the identity: never flatten
  a picture to match the others. At the 1.6 cap, center the stretch
  (`o = 0.5 - k * (lo + hi) / 2`) instead of pinning one end.
- No gamma, no curves, no sharpening, no noise reduction, no local
  contrast: each is either invisible at tile size or a step toward
  "restoration". One linear map is exact on every platform.
- Publish the result per image, as two numbers. Measured 2026-10-29 on
  the 40-image sheet: 14 were the identity, 3 hit the cap (Tony Barrett
  0.02 to 0.42, Ben Wright, Jan Miner), the rest stretched 2% to 42%.

### 3. The mount and the edge

- The **print ground** (`#EDEDED` light, `#2A2A2E` dark in the
  prototype; make it a token) shows wherever a contained graphic
  leaves room. It is the mount's paper, present in every cell, so it is
  never "the space the image did not cover".
- **Hairline edge**: 1 px at about 18% ink light, 16% paper dark. It
  separates a white-ground halftone from a white page.
- **One radius pair**: the card radius outside, 4 inside. A circle only
  for a person's face.
- **Text on the board** must pass contrast for its size: the genre hues
  are checked at 3:1 (large text only); a name below 18.66 px bold
  needs 4.5:1, so either set it large or add on-genre text tokens.
  Never text on the photograph.

### 4. Minimum size

`cropPx >= slot` (CSS points). That is at most a 2x upscale on a 2x
screen, the softness of a printed halftone, not mush. Below it, use the
fallback; never request a bigger step than the original (Commons
returns the original anyway) and never run an upscaler. A header draws
the whole picture at no more than its own pixel size at 1x.

### 5. The fallback is designed, not missing

The typographic card (the name on the board, in display type) and the
initial (on the surface or the genre hue) are members of the set, drawn
with the same radius, edge and board as a picture. A wall where 10% are
initials still reads as one set; a wall with gray boxes does not.

### 6. Dark mode

Change the ground, not the photograph: no dimming, no inversion. The
print ground lifts to a dark gray so a black-background portrait keeps
its edge; the hairline flips to paper.

## Where each step runs

**In the pipeline (measure once, publish numbers):**

- The face box and group box (already: Apple Vision on a Mac, contract
  §3.3a).
- **The grade**: `[k, o]` and the tone class (`mono`, `sepia`,
  `color`) per image, from Commons' 500 px thumbnail (the faces phase
  already reads it) with Pillow, inside the image's `cropRect`. It runs
  on Linux, so it can be a build step, not only a harvest phase; a
  golden test fixes the formula on fixtures (`tests never pin catalog
  contents`). Prototype: `docs/research/design/d2b-1/grade.py`.
- Proposed contract field: `art.grade = [k, o]`, NULL meaning identity.
  Publish the computed value; never ship the measurement algorithm to
  clients (`shared-data-plane-contract`).

**Per platform (apply the published numbers, natively):**

- **Web**: one inline SVG filter per graded image, with
  `color-interpolation-filters="sRGB"` (the SVG default is linearRGB,
  which would make the same numbers darker than measured):
  `feColorMatrix type="saturate" values="0"`, then
  `feComponentTransfer` with `feFuncR/G/B type="linear" slope=k
  intercept=o`. Avoid composing CSS `brightness()` and `contrast()`:
  they clip between steps and dull the whites when `o > 0`.
- **Apple** (iOS, iPadOS, macOS, tvOS): apply in the shared image
  pipeline at decode, once, cached: `CIColorControls` (saturation 0)
  then `CIColorMatrix` (R, G, B vectors `k`, bias `o`), working in sRGB
  (`CIContext` with `workingColorSpace` sRGB, or the values will shift).
  SwiftUI's `.grayscale`, `.contrast`, `.brightness` approximate it but
  their color space is not documented; measure before using them.
- **Android**: `ColorMatrix().apply { setToSaturation(0f) }` concatenated
  with a scale `k` and translate `o * 255` on R, G, B, as
  `ColorFilter.colorMatrix` on Coil's `AsyncImage`; exact, since Android
  color matrices act on 0 to 255 sRGB values.
- **The mount, edge, fallback and floor** are layout on every platform,
  from tokens.

**Pre-rendered derivatives (graded, cropped WebPs at each size step) are
the alternative**, and the one `image-cdn-discipline` would prefer at
scale. Ear Drama does not do this yet: the contract hot-links Commons
and forbids a re-hosted copy, a derivative is a modified copy that must
carry its credit and a link to the original, and it needs an image CDN
on a custom domain. That is an owner decision (it reverses a contract
rule); until then, publish parameters.

## CDN implications

- **One download per picture.** The grade is applied to the bytes the
  client already has, so a tile and the Detail header share the same
  cached file (graded in one, original in the other). Derivatives would
  double the downloads per picture viewed both ways.
- **Request the step the crop needs**: `slot * DPR / cropRect.w`, then
  the smallest standard step at or above it (Commons' 120, 330, 500,
  960; `artURL`). The floor rule means a tiny original is never asked
  for at a bigger step than it has.
- **Cache keys do not change** with the grade; a regraded catalog needs
  no cache purge.
- **The measurement fetch rides the faces phase's** 500 px thumbnail: no
  second pass over Commons.

## Verify on the real set

Render a contact sheet of about 40 real served images chosen to span the
worst cases (the smallest, widest, tallest, no-face, group, cartoon,
plaque, lobby card, halftone, color, sepia, darkest, lightest, lowest
contrast), before and after, as tiles and as a face wall, at 375 px,
light and dark, through the app's own size steps and crop formula. Look
at the PNGs. Add a rejected variant (duotone) to the same sheet so the
choice is visible. The recipe: `docs/research/design/d2b-1/`
(`sheet.html`, `shoot.mjs`, `grade.py`).

## Anti-patterns

- **A filter for mood** (sepia, genre duotone, a color wash) over a
  historical photograph. Rendered in the sheet: a genre duotone makes
  every face look tinted and reads as a colored photograph.
- **Colorizing, upscaling, "restoring" or enhancing faces.** Invented
  content, whatever the tool calls it.
- **Grading the page about the picture.** Detail shows the original.
- **Grading without limits**: matching every tile to one mean
  brightness flattens high-key and low-key portraits into one gray.
- **Flattening a full-range picture** to match a dull one (`k < 1`).
- **A blind crop of a graphic** with no face: the middle of a page.
- **Text on the photograph**, or a scrim to rescue it.
- **Per-device measurement** of a shared catalog (the same rule as face
  boxes).
- **A gray box or silhouette** for a missing or too-small picture.

## Worked example: Ear Drama (2026-10-29)

Measured over the served series stars (263 of 271 thumbnails read from
`eardrama.org/data/index/series.json`, 120 px step): 183 monochrome, 17
sepia, 63 color (70%, 6%, 24%); 33 under 330 px wide, 71 under 500; 23
wide; 1 with no face box. The served people (2,174 portraits) add the
graphics the series set lacks: Billboard and Radio Album halftones,
lobby cards, sheet-music covers, a dust jacket, cartoons (Feg Murray's
and Milt Gross's own strips as their P18), a plaque presentation, jazz
group shots.

The 40-image sheet (26 series stars, 14 people) is at
`docs/research/design/img/d2b-1/`: `tiles-before-375-light.png`,
`tiles-after-375-light.png`, the same in dark, `wall-before-375-*.png`,
`wall-after-375-*.png`, and the rejected `tiles-duotone-375-light.png`.
Before: a full-color, unmounted mix where saturated color and sepia sit
beside halftones. After: one family. What the sheet showed:

- **Hello Sucker** (Arthur Peterson, a 95 by 129 original) is too small
  for a 103 pt tile and draws as its typographic card; at 76 pt on the
  wall it passes.
- **Eight of 40 have no face box**, mostly halftones (Curt Massey,
  Joseph Dunninger, Garry Moore) and graphics. The upright ones crop
  well at the top anchor; the square ones (Feg Murray's strip, Milt
  Gross's "Nize Baby" art, Lucille Fletcher's dust jacket) now show
  whole on the print ground where V4 cropped the middle of the page.
- **Sylvia Froos** (a wide newspaper scan with no face) was a letter
  tile and an empty circle; shown whole, it is a picture again.
- The grade lifts the low-key Tony Barrett and Ben Wright portraits and
  steadies the washed-out sepia of Barbara Luddy without making any of
  them look processed; the 14 full-range pictures are untouched.

Open questions for the owner (D2b-3 builds against the defaults): the
`art.grade` contract field; whether derivatives on an image CDN replace
hot-linked Commons files; on-genre text tokens for names on the boards.

## See also

- `artwork-presentation-design`: the slot's shape, the face crop, the
  header and caption rules.
- `image-cdn-discipline`: size steps, one URL helper, tiers.
- `evidence-gated-catalog-curation`: whose picture may be shown at all.
- `catalog-experience-design`: where faces lead (walls, tiles, logs).
- `shared-data-plane-contract`: publish a computed value once.
