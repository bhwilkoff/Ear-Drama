---
name: artwork-presentation-design
description: Use when designing how images of MIXED, unknown, or uncontrolled aspect ratios appear in one slot (a page header, a hero band, Now Playing art, a detail figure, a tile, an avatar), on any platform. Carries the rule that the slot takes the image's shape rather than the image the slot's, the decision tree by aspect ratio and slot, when a crop is allowed and where its focal point is computed (once in the pipeline, never per device), matting and framing as an archival print, dominant-color fields, the typographic card as default art, and the anti-patterns (blur-and-bars, center crops of faces, filled boxes on light pages). Triggers on aspect ratio, portrait vs landscape, hero image, header image, artwork slot, letterbox, pillarbox, blurred background, "black bars", object-fit, ContentScale, crop, focal point, face crop, smart crop, Now Playing art, artist page, poster, photo caption, image credit, "make it more visual".
---

# Artwork Presentation Design

How to show images you did not compose (archival photographs, user
uploads, a public catalog's art) when one slot must take a portrait, a
square and a landscape image. The serving side (sizes, CDN, one URL
helper) is `image-cdn-discipline`; this skill is what the picture looks
like once it arrives.

## The one rule

**Shape the slot to the image, never the image to the slot.** A slot
is a bound (a maximum width and height) and a layout, not a fixed box.
The image is drawn at its own aspect inside that bound, and the box
around it is exactly the image's size, so there is no leftover area to
fill. Every bad treatment (bars, blur fills, a slice of someone's
forehead) starts by fixing the box first and then asking what to do
with the space the image did not cover.

Why: the leftover area is not neutral. Black or blurred bars read as
"this did not fit"; on a light page a dark, blurred field is the
heaviest thing on the screen and is not even the picture. A box that
fits the picture has nothing to apologize for.

## What strong products do (the references)

| Product | What it does | The lesson |
|---|---|---|
| Apple Music artist pages, Spotify artist headers | Full-bleed crops of a square or wide artist image, with a safe area the supplier designs for ([Apple artist image guidelines](https://artists.apple.com/support/88-artist-image-guidelines)) | A crop is safe only when the image was **composed for that crop**. They control the supply; you usually do not. |
| Apple Podcasts show pages | The square cover sits whole; the page ground takes a color from the art (observed by [Libsyn](https://libsyn.com/blog/?p=9738); Apple does not document the method) | A **dominant-color field** works when the art has a flat ground. It is a field, not a fill around the image. |
| Rijksmuseum (Fabrique + Q42) | Huge images, with a correct crop per image and screen size ([Q42](https://q42.nl/en/work/rijks-website1)) | Large crops there are **art-directed per image**, not computed blindly. |
| Cooper Hewitt collection | Square thumbnails cropped to the most "interesting" region by a computed measure; the object shown whole on its page ([summary](https://briansuda.opalstacked.com/newsletter/02013Q4/), [Labs](https://labs.cooperhewitt.org/2013/b-is-for-beta/)) | Crops belong to **small, repeated slots**; the object's own page shows it whole. The crop point is computed **once**, server-side. |
| Netflix artwork (AVA) | Face and focal-point detection over frames, in the pipeline, with designers choosing the final art ([Gigazine summary](https://gigazine.net/gsc_news/en/20180905-netflix-art-science-image-discovery/)) | Face boxes are **data computed once** and stored, not a per-device guess. |
| Wikipedia infoboxes, Letterboxd and IMDb person pages, newspaper obituaries and archive photos (observed) | A portrait whole at its own aspect, **beside** the text, with a caption and credit line directly under it | The museum label: the picture, then who it is and whose photograph it is. A tall image goes beside text; it never has to fill a wide band. |
| Vertical phone video on TV news ("echo pillarboxing", [Shotstack](https://shotstack.io/learn/blur-sides-vertical-video/)) | The tall frame centered over a blurred copy of itself | Common, and called distracting by broadcast designers ([Newscast Studio](https://www.newscaststudio.com/2018/09/18/kathie-lee-and-hoda-vertical-video/)). A workaround for a fixed 16:9 screen, which an app page is not. |

## The rules

### 1. Know the shape before the image arrives

Publish each image's width and height in the data (once, in the
pipeline: `shared-data-plane-contract`) so a client chooses the layout
before the first byte and nothing moves when the image lands. A
client that lacks them sizes the box from a typical aspect for the
class (about 4:5 for a head-and-shoulders portrait) and lets the
platform's intrinsic sizing correct it on decode (CSS `aspect-ratio:
auto 4 / 5`, a height-bounded `.fit` image in SwiftUI, `ContentScale.Fit`
with a bounded height in Compose).

Why: a layout chosen after load jumps, and one guessed from a typical
aspect is wrong for the wide minority, which is exactly the set that
needs a different layout.

### 2. Classify by aspect, with one set of thresholds everywhere

`a = width / height`:

- **upright**: `a < 0.9` (a portrait; under 0.6 is a very tall one)
- **square**: `0.9 <= a <= 1.15`
- **wide**: `a > 1.15`

Put the thresholds in one place per platform and quote them in the
binding design doc, so web, Apple and Android make the same choice for
the same image (`cross-platform-parity-discipline`).

### 3. The decision tree, by slot

| Slot | Upright | Square | Wide | No image |
|---|---|---|---|---|
| **Page header** (a person, a show, an item) | Beside the heading, height-bounded, width from its aspect; caption under it (the label) | Beside, as upright, a little smaller | A plate: full column width at its own aspect, height capped; if the cap binds, the width shrinks and the plate sits at the start, never centered in a filled band | The typographic card: the heading set large on the content's own hue |
| **Hero band on a dark, full-screen, lean-back surface** (TV) | Whole, beside the copy; the scene ground may be the art's dominant color | As upright | Sharp and full-bleed only when the image was composed wide | Category accent field |
| **Now Playing / large single art** | Bounded square; the image fitted inside at its own aspect, the box shrunk to it, centered on the page ground | Fills the square | Full width, shorter than the square | Square typographic card |
| **Row tile, grid cell** (small, repeated) | Crop to a square, anchored at the focal point (else top third for a portrait) | Fills | Crop at the focal point; without one, prefer the letter tile over a blind center crop of a wide group photo | Initial on the hue |
| **Avatar** (round, 24 to 64) | Crop at the face box, else top-anchored | Fills | Face box required; else no avatar, keep the empty slot | Empty slot, aligned |
| **Lock screen, system media art** | The system crops to square: hand it the best square (focal-point crop, or the fitted image on a quiet ground rendered once) | As is | As upright | The card rendered to an image |

### 4. Crop only small repeated slots, and only at a known focal point

A crop is allowed where the picture is a cue rather than the content
(a 56 px tile, a 32 px avatar), where it is repeated (cropping is how a
list stays even), and where the face survives. The page that is ABOUT
the picture shows it whole. A crop that removes more than about 40% of
an axis needs a focal point; a top-third anchor is a fair default only
for head-and-shoulders portraits.

### 5. Compute focal points once, in the pipeline

A face box (or a saliency point) is a fact about the image, the same on
every device: compute it where the catalog is built, store it as
normalized `{x, y, w, h}` next to width and height, and publish it.
Every client then does a cheap anchor (`object-position`, an alignment,
`Alignment` with a bias), and no client ships a model.

On-device detection (Apple Vision `VNDetectFaceRectanglesRequest`, ML
Kit Face Detection) is for images the user supplies, never for a shared
catalog: it repeats the same work on every device, can disagree across
platforms and OS versions, costs battery, and needs the full image
first. A face box from a detector is a hint, not evidence: it never
decides whose face it is.

### 6. Frame like an archival print, not like a phone screen

Archival photographs have their own edges, borders and tone. Show them
as objects: a hairline rule (the border token) or a thin mat in the
surface color, a small corner radius (the control radius, never a pill),
no drop shadow, no tint overlay, no filter. The loading placeholder is
the box itself in the surface color, at exactly the image's size.

### 7. A dominant-color field is a ground, not a fill

Taking a color from the art (Android `Palette`, a server-computed
average) is good for a page or scene ground behind a whole image, when
the color passes contrast for the text on it. For black-and-white
archival photographs it is gray: use the theme's surface instead.
Compute it once in the pipeline if more than one platform shows it.

### 8. Credits and captions travel with the picture

A credit a license requires sits directly under or beside the image, in
caption type, linked to the source page where links open. Whose face it
is goes in the caption when the heading does not already say so. Never
put text over a photograph you did not compose: its contrast is unknown.

### 9. No image is a designed state

With no image, draw a card from data (the name, one fact line, on the
content's hue) at the slot's shape. Never a stock photo, a silhouette,
a gray box or a generic icon: those say "missing", and a missing
picture of a real person is better than a wrong one
(`evidence-gated-catalog-curation`).

### 10. Verify with the extremes

Render every slot with the tallest, the squarest and the widest real
images in the catalog, at the narrowest and widest layouts, light and
dark, and look at the PNGs. Most catalogs are dominated by one shape;
the minority is where a design breaks.

## Per-platform native idiom

- **Web**: set `width`/`height` attributes from the data so the browser
  reserves the box; `height: <bound>; width: auto; max-width: <share>`
  for a beside figure; `aspect-ratio: auto 4 / 5` when the size is
  unknown; `object-position: x% y%` from the focal point for crops;
  `<figure>` + `<figcaption>` for the label. One class per shape, set
  from the data.
- **SwiftUI** (iOS, iPadOS, macOS, tvOS): `image.resizable().aspectRatio(
  contentMode: .fit)` with a bounded height and `.frame(width: h * a)`
  from the data; `ViewThatFits` or a size class for beside vs stacked; a
  crop is `.aspectRatio(contentMode: .fill)` in a fixed frame with an
  alignment from the focal point. tvOS: the focused card carries the
  lift; the figure itself is not focusable.
- **Compose**: `Modifier.height(h).width(h * a)` with
  `ContentScale.Fit`, or `Modifier.aspectRatio(a)`; Coil's
  `AsyncImage`; a crop is `ContentScale.Crop` with a `BiasAlignment`
  from the focal point; `Palette` for a dominant color.
- **Lock screen / media session**: square art; render the card or the
  fitted image to a bitmap once.

## Anti-patterns

- **Blur-and-bars**: a fixed box, the image fitted in it, and the
  leftover filled with a blurred, darkened copy (or black). It reads as
  heavy dark bars on a light page, doubles the downloads, and makes the
  image smaller than the box it occupies. The only defensible use is a
  full-screen, dark-first scene where the image IS the scene (a TV
  backdrop: `ten-foot-detail-design` §1), never a box inside a page.
- **Center-cropping a portrait into a wide band**: shows a forehead.
- **Assuming one aspect** (`aspectRatio(2/3)` everywhere): the minority
  breaks.
- **Per-device face detection over a shared catalog**.
- **Text over an uncontrolled photograph**, or a gradient scrim to
  rescue it.
- **A filter or tint for mood** (sepia, duotone) over a historical
  photograph: it changes the evidence. A duotone is a brand device for
  images you own.
- **A placeholder that looks like content** (silhouette, stock).

## Worked example: Ear Drama (2026-10-28)

The catalog's only served art is people's portraits from Wikidata (P18)
on Commons. Measured 2026-10-28 over the 271 series stars (all 3,765
harvested files sized): 222 upright (6 of them under 0.6, Jack Benny's
0.52), 25 square, 24 wide (up to 1.83, Life With Luigi). Until that date the
projection published width and height only for series photographs, so
236 of the 271 series stars had none; `harvest_people_wikidata.py
--phase dims` now reads them once, and `build_projection.py` publishes
them. V2 (1.0.86) drew every page face as a 240 or 320 high band, the
portrait fitted over a blurred, dimmed copy of itself; the owner: *"I
think you can find better solutions for different aspect ratios of
images, then just blurring and black bars."* V3 applied this skill: an
upright or square face sits beside the heading as a captioned print, a
wide one is a plate at its own aspect, Now Playing's box shrinks to the
image, and the 56 px tiles and 32 px cast faces keep their top-anchored
crops (no focal point is published yet; that is the next step, computed
in the pipeline). The rules live in WEB-DESIGN §6.4a and R11a of each
platform design doc.

## See also

- `image-cdn-discipline`: sizes, one URL helper, never re-host.
- `ten-foot-detail-design` §1: the TV backdrop scene.
- `mobile-first-density-design`: density by removing chrome.
- `evidence-gated-catalog-curation`: whose face may be shown at all.
- `shared-data-plane-contract`: publishing a computed value once.
