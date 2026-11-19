# R3a: Visual cohesion, and a drawn-art system for everything without a picture (research, 2026-11-19)

Research only. Nothing in the app changed. Direction D stays the visual language (owner,
2026-10-29), and so do the On Air roles (Decision 064): ink for actions, red only for recording,
blue for wayfinding, genre hues as content. This doc builds on D1a, D1b, D2, the D2c-3 grammar
(`directions/d/direction.md`), R2-home-and-create, R2-design-review, and the three image skills
(`artwork-presentation-design`, `uniform-imagery-design`, `catalog-experience-design` rule 11). It
does not re-propose what those settled: one skeleton per object, the window always present, the
grade and mount, two tiers, rule-named rows, On the air first. Finding more real images is a
separate track, so it is not covered here.

The owner, 2026-11-19: *"We need to continue making the app more visually appealing, both from the
home screen perspective (which still reads like a long list of items that feel unrelated) and the
individual item perspective ... We also can design default (or programmatically generated) designs
that could take the place of images that don't exist (or don't yet exist, anyway). The goal is to
have the home view feel more cohesive and inviting from the moment that you open the app."*

---

## 0. Verdict

1. **Products that make sound look cohesive buy that with one system, not with more pictures.**
   Penguin used one grid for every book. Blue Note used two colors and one type idea. Spotify, which
   had the same label photos as everyone else, used one duotone treatment and limited playlist
   editors to 15 palettes. NYPL drew a cover for every public-domain ebook from its title. Each one
   refuses per-item art direction, extra colors, and stock filler (§1).
2. **Today's Home has five visual vocabularies on one page**, and the loudest one is not the lead.
   On the air is a gray box with a 64 px thumbnail. Below it sit genre boards with photos, a full-width
   plum slab, a rainbow stacked chart, and round grayscale faces. Two rails open on the same four
   shows. On Detail, the episode has no picture of its own: it wears the show's board, and the page
   ends in six bitrate rows (§2).
3. **81% of shows have no picture (1,059 of 1,311), and the default art carries one fact, the
   initials.** It does not show era, network, or how long a show ran, even though the data has them,
   so a wall of bare shows reads as one repeated placeholder (§2.3).
4. **Recommendation: Option C, "the label".** Every broadcast with no picture is drawn as a flat
   transcription disc made from its own data: the board is the genre, the groove ring is the
   object, an arc on a fixed 1930–1962 dial is the years it ran, the center label is the monogram
   (on an episode, its date), and the rim text at large sizes is network and decade. Finished ear
   dramas get the same disc with their cast's part hues around the rim. It is two-tone like a graded
   photo on its board, so pictures and labels read as one set. It is legible at 56 px (label plus arc)
   and at a TV hero. It is deterministic from fields the catalog already publishes, plus one small
   new field. Option A (a typographic title card) and Option B (a hash-seeded genre motif) are the
   alternatives (§3).
5. **Home becomes one thing by giving it one lead object and one rhythm**: On the air as a real hero,
   quieter doors, one art system in every rail, a show at most once per Home, the rainbow chart and
   the plum slab brought down to the grammar's size, and large and small objects alternating (§4).

A rendered sketch of the three options at 56, 128 and 320 px, light and dark, is in the session
scratchpad (`sketch/sketch-light.png`, `sketch-dark.png`; not committed). I read both frames, and §3's
legibility claims come from them.

---

## 1. What the best audio and collection products do, and why it works

### 1.1 One system, applied to everything, beats per-item art

| Product | What it does | Why it works / what it refuses |
|---|---|---|
| **Penguin, the Marber grid** (1961–62) | One cover grid for Crime, then Pelican, fiction, and Modern Classics from 1963. Title and author placement flex with the title's length ([Penguin](https://www.penguin.co.uk/discover/articles/penguin-modern-classics-design); [Marber](https://romekmarber.com/portfolio/penguin-grid); [The Millions](https://themillions.com/2021/11/the-story-behind-penguin-modern-classics-iconic-cover-designs.html)) | A shelf reads as a set because the *frame* repeats and only the content varies. It refuses a new layout per book. |
| **Blue Note, Reid Miles** (1956–67) | Black plus one color, sans-serif capitals, a duotone photograph. When the photo is loud the type tucks into a corner, and when the type is loud the photo is muted ([Wikipedia](https://en.wikipedia.org/wiki/Album_covers_of_Blue_Note_Records); [Reid Miles](https://en.wikipedia.org/wiki/Reid_Miles); [typetune](https://typetune.netlify.app/2020/11/23/reid-miles)) | Hundreds of covers on about fifty dollars each read as one label because there are only ever two inks and one balance rule. It refuses full color. |
| **Vintage Contemporaries** (1984) | Lorraine Louie's single format; about 50 illustrators filled the same frame across close to 100 titles ([Talking Covers](https://talkingcovers.com/2012/09/12/vintage-contemporaries/); [People's Graphic Design Archive](https://peoplesgdarchive.org/item/4262/cathedral-vintage-contemporaries)) | Uneven art from many hands still reads as one series inside one fixed format. |
| **Spotify, Collins' 2015 identity** | It had "to work with the same label-provided images as its competitors," so a tool nicknamed "The Colorizer" applied duotones automatically; playlist editors got 15 palettes to pick from ([Transform](https://www.transformmagazine.net/articles/2015/spotify-gets-visceral/); [Collins](https://wearecollins.com/case-studies/spotify)) | One treatment makes images Spotify did not choose look like Spotify. It refuses free color choice. *Ear Drama takes the system, not the duotone: tinting a historical photograph is refused (`uniform-imagery-design`), and the neutral grade is our Colorizer.* |
| **Apple Music playlists** | The early covers were "uniform, but didn't stand out." In 2019 Apple began commissioning artists for "many thousands" of playlists so the art would be "a visual representation of the music" ([9to5Mac](https://9to5mac.com/2019/03/08/apple-music-custom-playlist-artwork/); [MacStories](https://www.macstories.net/linked/apple-music-commissions-custom-playlist-art/)) | A uniform template is cohesive but forgettable. Apple paid for variety *inside* a cover system. Ear Drama cannot commission 4,842 covers, so its variety has to come from data. |
| **NYPL Labs, generative ebook covers** (2014) | Every public-domain ebook gets a cover drawn from its title and author. Each letter maps to a 10 PRINT/PETSCII shape repeated on a grid. Hue comes from the title and author lengths (HSL 30–260) plus a complement. Title text sits in a plain enclosed band ([Giraldo](https://mauriciogiraldo.com/blog/2014/10/10/generative-ebook-covers/); [NYPL](https://live-legacy-admin.nypl.org/blog/2014/09/03/generative-ebook-covers); [FlowingData](https://flowingdata.com/2014/09/10/generative-book-covers)) | It is the closest precedent: a library's public-domain shelf with no art. Two lessons. Text in its own plain band stays legible whatever the pattern does. Long titles shrink the shapes until they turn to noise, so the size has to be capped. |
| **Spotify's default mosaic** | A playlist with no cover shows four album covers from its first tracks, changing as it changes ([Gadget Hacks](https://smartphones.next.gadgethacks.com/how-to/change-cover-images-your-spotify-playlists-get-rid-all-those-ugly-album-art-grids-0385363); [Spotify Community](https://community.spotify.com/t5/Desktop-Windows/Cover-art-bug/m-p/4709170/highlight/true)) | Users call these grids ugly and replace them. Spotify then shipped a cover maker with a random solid or gradient behind the name ([It's Nice That](https://www.itsnicethat.com/articles/spotify-playlist-covers-create-cover-art-digital-project-221024); [Techloy](https://www.techloy.com/spotify-now-lets-users-create-playlist-art-heres-how-to-do-it.md)). A collage of other things' art is not an identity, and a random gradient is not information. |
| **GitHub identicons** | A 5×5 symmetric sprite plus a color, both from a hash of the user's id ([GitHub blog](https://github.blog/news-insights/company-news/identicons/)) | Deterministic and distinct, but it says nothing about the person. It is the model for Option B, and its weakness too. |

### 1.2 Audio apps let the art carry the color, and keep the chrome still

- **Apple Podcasts** shows the square cover whole and takes the page's ground from the art,
  apparently sampled about halfway down the left edge ([Libsyn](https://libsyn.com/blog/?p=9738)).
  Apple asks shows for a required Show Cover, optional episode art, and a wide hero for featuring
  ([Apple Podcasters](https://podcasters.apple.com/support/896-artwork-requirements)). The page
  borrows color from the content, and the chrome stays neutral.
- **Overcast** goes the other way: a fixed white, orange, black, and gray chrome, with customizable
  playlist colors and SF Symbols icons ([Marco Arment](https://marco.org/2022/03/)). The art is
  the only color in the content area.
- **Audible's** designers set the hierarchy of information first, then the art direction, then
  "design for scalability, comparing the work at all intended sizes"
  ([Audible blog](https://www.audible.com/blog/go-ahead-judge-these-books-by-their-covers)).
  Podcast guides say cover text must survive at about 80 px wide
  ([Podnews](https://podnews.net/article/how-to-design-podcast-artwork)). Ear Drama's smallest
  slot is 56 px, so the default art has to be designed at 56 first.
- **Spotify's Canvas** (a looping visual on a track) is claimed by Spotify to raise streams by up
  to 120% ([Music Business Worldwide](https://www.musicbusinessworldwide.com/spotify-expands-canvas-beta-says-visuals-can-increase-streams-saves-artist-profile-visits-and-shares);
  [Spotify for Artists](https://artists.spotify.com/blog/canvas-metrics-guide)). That is Spotify's
  own, unverified metric. It is not a reason to animate archive art, and motion would also break the
  calm-listening rule (`catalog-experience-design` rule 7).
- **Spotify's 2023 Home** replaced rows of tiles with large preview cards that play on their own.
  Users disliked the autoplay and the clutter
  ([Engadget](https://www.engadget.com/spotify-debuts-its-tiktok-style-music-discovery-feed-183359654.html);
  [Tom's Guide](https://www.tomsguide.com/opinion/spotifys-redesign-is-so-bad-im-considering-switching-to-apple-music)).
  Big objects invite, but a page made only of big objects is a feed.
- **NTS** gives each show a full-page graphic inside a black, white, and red station identity,
  with host portraits ([Made Good](https://madegooddesigns.com/?p=104698);
  [It's Nice That](https://itsnicethat.com/articles/nts-radio)). Programs vary inside a fixed
  station frame.
- **BBC Sounds** (Mother Design, 2018) uses a "highly flexible system" of bold type and a restricted
  palette ([It's Nice That](https://itsnicethat.com/news/mother-design-bbc-sound-rebrand-graphic-design-281118)).
  A copy of a BBC Sounds image guide shows brand, episode, and podcast image classes
  ([Scribd copy, provenance unclear](https://www.scribd.com/document/728228236/BBC-Sounds-Image-Guide)).
  I could not read the official BBC program image template, so it is UNVERIFIED. What is visible:
  a program has a brand image and episodes inherit it.
- **Radiooooo** makes the *axis* the picture. It has no cover art: you pick a decade and a country
  on a hand-drawn map, and countries change color by decade to show where tracks exist
  ([Open Culture](https://www.openculture.com/2018/04/radiooooo-the-musical-time-machine.html);
  [Slowdown](https://www.slowdown.media/article/avoid-algorithms-with-the-incredibly-refreshing-radiooooo)).
  Time drawn on screen is enough identity for archival audio. Ear Drama's run strip and the label's
  dial come from the same idea.

### 1.3 Collections that unify uneven imagery

- **Cooper Hewitt** extracts each object's dominant colors once in the pipeline and snaps them to
  a fixed palette (121, later CSS4), so the colors are browsable data
  ([Labs](https://labs.cooperhewitt.org/?p=1747); [My Modern Met](https://mymodernmet.com/cooper-hewitt-design-museum-archive)).
  It squares thumbnails at a computed point and shows the whole object on its page (already in
  `artwork-presentation-design`).
- **Rijksmuseum** (Fabrique and Q42, 2020) uses very large images and makes full-screen details the
  navigation ([Q42](https://q42.nl/en/work/rijks-website1);
  [European Design Awards](https://awards.europeandesign.org/winner/248792)). That works because
  every object *has* a high-quality image. Ear Drama has the opposite problem, so the lesson is the
  restraint (one image scale per page), not the image-first layout.
- **Criterion** puts commissioned covers on uniform spines with a consistent width, the "C", and a
  spine number, so a shelf of discs becomes one designed object
  ([AIGA Eye on Design](https://eyeondesign.aiga.org/criterion-designs/)). Eye magazine warns that
  a fully systematic cover design "eventually becomes dull through predictability"
  ([Eye](https://eyemagazine.com/blog/post/critique-commentary)). The system needs a second level of
  variety, and Ear Drama's has to come from each show's own facts.

### 1.4 The era's own graphics (what is ours to use, and what is not)

- **Transcription discs** are how much of old-time radio survives: 16-inch discs at 33⅓ rpm, about
  15 minutes a side, leased to stations
  ([Wikipedia](https://en.wikipedia.org/wiki/Electrical_transcription);
  [Canadian Communications Foundation](https://broadcasting-history.ca/?p=9433)). A 1940 World
  Broadcasting System label prints the maker, a master number, a running time, and "licensed for
  radio broadcasting only" ([Ingenium](https://collection.ingeniumcanada.org/en/id/1990.0151.001/)).
  The disc and its label are the era's own carrier of a broadcast's facts, and a circle reads at
  any size. Option C draws a disc. It never reproduces a real label maker's name or layout.
- **Network logos are trademarks.** CBS's Eye (William Golden, 1951) is still CBS's mark
  ([Wikipedia](https://en.wikipedia.org/wiki/William_Golden_(graphic_designer));
  [Print](https://www.printmag.com/daily-heller/hex-marks-the-spot-the-cbs-eye/);
  [Newscast Studio](https://www.newscaststudio.com/2026/10/22/cbs-eye-75th-anniversary/)). A
  network in Ear Drama is its name set in Ear Drama's type, never a logo.
- **Radio Guide** ran two-color art covers from 1933, full-color painted star portraits by Charles
  Rubino from 1935 to early 1938, then photo covers. It became TV Guide's predecessor
  ([World Radio History](https://worldradiohistory.com/Radio_Guide_Master_Page.htm)). Radio Mirror
  ran monthly from 1933 to 1977 ([Media History Digital Library](https://mediahist.org/reader.php?id=r00macf)).
  The period lesson is that a star's face sold the issue. Ear Drama already leads with stars where
  it has them, and these covers belong to the image-finding track, not here.
- **The On Air lamp** is lit to say a live session is underway and nobody should interrupt
  ([NFSA, a 1940 lightbox](https://www.nfsa.gov.au/collection/curated/asset/103027-recording-studio-air-lightbox)).
  It has traditionally been red ([WBSM](https://wbsm.com/the-mystery-of-the-blue-on-air-light/)).
  On Air already gives that red to recording only (Decision 064), so no drawn art uses it.
- **Swiss grid and Saul Bass**: Müller-Brockmann's grid as "an ordering system" with posters built
  on fixed fields ([Neugraphic](https://neugraphic.com/muller-brockmann/muller-brockmann-text2.html));
  Bass's single dominant geometric image carried from titles to poster
  ([BFI](https://www.bfi.org.uk/lists/celebrating-saul-basss-centenary-10-essential-title-sequences)).
  Together they argue for one strong shape per object and one grid per page, which is what the label
  and §4 do.

### 1.5 The principles, distilled

1. **One frame, and the content varies inside it** (Penguin, Vintage, Criterion, NTS).
2. **Few inks** (Blue Note's two, Spotify's 15 palettes). Ear Drama has board plus onBoard, already
   measured (Decision 064, `uniform-imagery-design` §7).
3. **Default art must carry information, not chance** (NYPL draws from the title; Radiooooo's
   axis; the mosaic and the random gradient show what happens when it doesn't).
4. **Design at the smallest slot first, then check the largest** (Audible; Podnews' 80 px).
5. **One lead object per screen; big and small alternate** (Spotify's all-cards feed is the
   counter-example; Bass's single image).
6. **Refused everywhere**: stock or placeholder photos, model-generated imagery (NPPA, in
   `uniform-imagery-design`), tints over historical photos, logos you don't own, motion on a
   listening surface, and per-item random color.

---

## 2. Diagnosis: today's Home and Detail against those principles

Frames: `tools/web_fit_home.py --shots` against the live site (muted headless Chrome, `?mute=1`,
never presses Play; PASS, 0 problems, 30 frames), plus `?series=suspense`, `?series=xminusone`, and
`?item=suspense|1942-12-22` at 1440 px with `--mute-audio --autoplay-policy=user-gesture-required`.
I read home-evening light 1440, home-evening dark 375, record light 1440, and the Suspense series
and episode frames. Data: `data/manifest.json` and `data/index/series.json`, generated
2026-11-19 11:47 MST.

### 2.1 Home (evening, 375 and 1440 px)

| # | What is on screen | Principle broken |
|---|---|---|
| H1 | **On the air**, the lead, is a neutral `surfaceAlt` box: a 64 px picture (or title block), the series in body-strong, "The Telltale Bottle · 0 min in". It is the smallest picture on Home. | One lead object (5). The lead looks like a notification. |
| H2 | **Three doors** are three bordered gray boxes as tall as On the air's content | Big and small alternate (5). The navigation is visually as heavy as the content. |
| H3 | **Start a show** is genre boards with graded star photos: Gunsmoke brown, then Dragnet, Johnny Dollar, and Suspense blue | Fine on its own. It is the one place that already looks like a set. |
| H4 | **Today's scene** is a full-width **plum slab** (drama board) holding a gray print page of four speeches, with an ink button and two links. At 1440 it is about 470 px tall, the largest and most saturated object on Home. | Few inks and one lead (2, 5). The second job outweighs the first. |
| H5 | **By length · Under 15 min** opens on Gunsmoke, Dragnet, Johnny Dollar, and Suspense again, the same four tiles and the same pictures as Start a show | One frame, varied content (1). The repetition reads as a list, not a place (R2-review F8, still open at the source). |
| H6 | **This day in radio** is a board with a stacked bar chart in eight genre mark colors and an eight-entry legend | Few inks (2). The only rainbow on Home is a chart. |
| H7 | **Most heard voices** is round graded faces on the page ground, with no board | A sixth object style. |
| H8 | Suspense, the most downloaded show without a picture, draws a 200 px outline **"S"**. It sits between three photographs. | Default art must carry information (3). It reads as missing beside photos. |

The five vocabularies are a gray panel (H1, H2), a genre board with a picture (H3, H5), a saturated
slab with a paper page (H4), a rainbow data board (H6), and a bare face rail (H7). Each was right
in its own review. Together they are the owner's "long list of items that feel unrelated".

### 2.2 Detail

- **Episode** (`?item=suspense|1942-12-22`): the head board is the *show's* (Suspense, mystery
  blue, 1940–1962 · CBS · 1,077 episodes, the run histogram). The episode's star, Stu Erwin, is the
  picture, and the episode title is a page title *under* the board. Then Play, Add to queue, Share,
  Automatic transcript, On the air (one face), Cast and credits (9). **The page ends in six rows of
  "129 kbps · 30 min ... View on archive.org".** The object of the page, the broadcast of December
  22, 1942, has no visual identity of its own. The last third of the screen is file plumbing (D1b
  already proposed copies as a count).
- **Series** (`?series=suspense`): the board with the outline S and the histogram, the Wikipedia
  paragraph, then the log. **The date blocks in the log (JUL '40 / 21) are the strongest generated
  art the app already has**: a data object on the board, distinct per row, legible at 48 px. The
  label in §3 grows out of the date block and the run strip.
- **Record**: 803 tiles, all on the same plum board, each window a print page of two speeches. It
  is legible, but at 1440 px it is a wall of one color (R2-review F6). Plays carry no year or
  genre, so color cannot vary honestly (§5).

### 2.3 What the default art carries today, measured

Shows (5 or more episodes) on the live index, 2026-11-19:

| | Count | Share |
|---|---|---|
| Shows | 1,311 | |
| With a picture (`pictureKind` star / show / person) | 214 / 37 / 1 | 19% |
| **Typographic (no picture)** | **1,059** | **81%** |
| With a genre | 1,135 | 87% |
| With dates (`first`) | 617 | 47% |
| With a network | 528 | 40% |
| Genre only (no date, network, or picture) | 530 | 40% |
| Nothing at all (no genre, date, network, or picture) | 124 | 9% |

The title block uses only `name` (its monogram) and `genre` (its board). On an 81%-bare wall,
every Mystery show is the same blue square with an outline letter, and Suspense and Sherlock
Holmes differ by one glyph. The years, network and episode count that tell them apart are
printed *below* the window, in the facts. They never reach the picture.

---

## 3. A drawn-art system for every kind of content

### 3.1 The requirements (from §1 and the existing rules)

- **Deterministic**: the same inputs draw the same thing on web, Apple, Android, and TV, with no
  randomness at draw time. Per AGENTS.md ("publish a computed value rather than mirror its
  algorithm"), anything not trivially derived is published by the pipeline, and the geometry
  constants live in `design-tokens.json`, so platforms draw primitives from numbers rather than each
  re-deriving a design.
- **Honest**: flat vector, two tones, no texture, grain, fake wear, halftone, or photographic
  shading. No real label maker, network logo, or invented text. It is drawing, not a model
  output: the brand doc's "no model-generated art" (`docs/research/09-ear-drama-brand.md`) and the
  no-AI-copy rule both hold, because every mark is computed from catalog fields by a fixed
  algorithm.
- **On Air**: board plus onBoard only (the measured pairs in `uniform-imagery-design` §7). Part hues
  (the existing `PlaysCore.partHue` marks) are allowed only for finished ear dramas, where they
  already mean "a voice". No red, no blue (wayfinding), no ink fill.
- **The grammar**: art fills the window only. The name stays in its own slot and is never drawn
  twice (`catalog-experience-design` rule 11). The label replaces the title block in the same
  window, at the same radius, edge, and size floor.
- **Tiers**: S (56 px or less: row tiles, the mini player, a 32 px cast slot), M (96–200 px: show
  tiles, head boards), L (320 px and up: Now Playing, TV heroes up to 1920 px, share cards). Each
  tier drops detail rather than shrinking it.

### 3.2 Option A: the title card (typography only)

**Shape.** A Marber-style grid inside the window: a top band at onBoard 16% holding a kicker
(network · decade, caption caps), the name in Big Shoulders filling the width at three fit steps,
and a baseline rule. At tier S it is today's monogram under a thin band.

**Inputs.** name, genre, networks (first), first. **Algorithm.** Layout by name length (the
existing `nameStep`), no hash.

**For.** It is the most honest and cheapest option, closest to Penguin and NYPL's text band, and
TV and share cards come free. **Against.** It draws the name in the window, which rule 11 forbids
in tiles: the tile would show the name twice, or the window would fall back to a monogram and gain
nothing. In the sketch the 320 px hero is a word on an empty field. Eye's "dull through
predictability" applies. At 56 px it is today's tile.

### 3.3 Option B: the signal (a genre motif, seeded by hash)

**Shape.** Each genre owns one motif drawn from radio imagery: mystery, concentric rings; science
fiction, sine waves; western, horizon rays; comedy, dots; drama, curtain folds; news, ticker rules;
documentary, a survey grid; serials, numbered bars; stage plays, a proscenium. The motif's count,
phase, origin, and a rotation of up to ±18° come from FNV-1a 32 over the series key's UTF-8. The
monogram sits in a corner at tiers M and L.

**Inputs.** key, genre, name. **Algorithm.** FNV-1a 32 (the hash already proven cross-platform by
`todaysPlay`'s goldens), bit-sliced into parameters, clamped so a pattern never has more than 3
elements at tier S.

**For.** The most visual option: a Browse wall becomes a patterned quilt, and it looks good at
320 px. **Against.** Every parameter is chance: two shows differ, but the difference *means
nothing* (identicons, §1.1). Motifs assign a mood to a genre, which edges toward invented
editorializing. It is also a second visual language beside graded photographs, and nine motifs
need real design work and three ports. In the sketch, "Case Closed" (no genre) reads as a document
icon.

### 3.4 Option C: the label (a transcription disc drawn from data), recommended

**Shape** (100-unit viewBox, the window's square; sketch §0):

| Element | Geometry | Drawn from | Tier |
|---|---|---|---|
| Ground | the window, filled with `board[genre]` (`surfaceAlt` with no genre) | genre | S M L |
| Disc | circle r 46, onBoard at 10% | nothing (the object) | S M L |
| Grooves | concentric rings r 22 to 43, step 1.8, onBoard 0.35 px at 35% | nothing | M L |
| Dial ticks | 1930, 1940, 1950, 1960 at r 44–47 on a 240° dial (1930 at 210°, 1962 at −30°, clockwise) | the fixed `RUN_AXIS` | M L |
| **Run arc** | onBoard stroke (4.5, or 7 at S) at r 45 from angle(first) to angle(last); a year is 7.5°; years before 1930 or after 1962 clamp to the ends with a square cap | `first`, `last` (the run strip's own axis) | S M L |
| **Label** | circle r 19 (28 at S), solid onBoard | | S M L |
| Label text | the monogram (`API.monogram`, its goldens), in the board color, Big Shoulders 800 | name | S M L |
| Rim text | network · decade on a text path at r 39, caption caps, onBoard 85% | the primary network, decade of `first` | L only |

What a person can read from it with no words: what kind of show (board), whether it is dated and
which era (where the arc sits on the dial), whether it ran one season or twenty years (the arc's
length), and at large sizes which network. Suspense draws a long arc from the 1940 tick to the end
of the dial. X Minus One draws a short arc in the mid-1950s. Ranger Bill (undated) draws no arc: an
honest blank, never an invented era.

**Per content kind** (one object family, so the whole app reads as one set):

| Kind | Drawn as | Inputs | Today |
|---|---|---|---|
| **Series without a picture** | the label | key, name, genre, first, last, network | title block |
| **Single episode** (Now Playing, Continue, mini player, the episode head) | **its show's disc with its date in the label**: the date block's own text (DEC '42 / 22; '42 / Dec; 1942; "No." / 7 when undated and numbered); the show's monogram when there is neither | the series' inputs, plus the episode's date or num | the show's picture or title block |
| **Episode whose show has a picture** | the picture, unchanged (picture priority, contract §3.3a); the label never replaces a real image | | |
| **News and documentary** | the label on the news or documentary board. Bulletins with exact dates (CBS World News Today) get the date label at episode level, like a dated log | same | title block |
| **Genre stations and Tonight in 19xx** (On the air, Stations) | the label with the station's genre board; for an evening, the dial carries one tick at that year, so the evening's position in radio history is drawn | genre, the evening's year | the slot's show window |
| **Stage play** (803 Gutenberg plays) | not a disc (it was never broadcast): keep the existing **script page** (the opening's speeches on the print ground) and the cast fingerprint as the mark. Add one honest variable: the page's printed rule in the play's **voice-count band** (2 / 3–4 / 5–8 / 9+) drawn as 1–4 short rules at the page foot, onBoard. Color cannot vary (plays have no genre or year, §5) | title, cast, voices, opening | script page |
| **Radio play in the library** (4 Carlton scripts) | the label on the drama board, with no arc unless dated | | script page |
| **Finished ear drama** (made by users) | **the same disc with the cast around the rim**: one segment per speaking part, its length that part's share of lines, in the part's hue (`partHue`, the marks the bill and studio already use); label = the play's monogram; at L, rim text "Recorded" · the month and year it was finished. No run arc, so archive and new work are told apart at a glance without red | play title, cast shares, part hues, finished date | show-tile grammar with the voice strip |
| **Person without a portrait** | a round window (a person is round already), on `surfaceAlt`: the initials solid in Big Shoulders, inside one groove ring. At L, the ring carries an arc for the years of their credits | name; credit years (person file) | initial |
| **Network** (if a network ever gets a page or a chip) | never a logo: the name in Big Shoulders on the neutral board, as a typographic card | network | none |
| **Share card / lock screen** | the label at L with the name set beside it, where the window is the only label (`uniform-imagery-design` §5's exception) | | typographic card |

**Legibility, from the sketch.** At 56 px the disc, the label with its monogram, and the arc
read in light and dark, and the arc's position tells 1940s from 1950s. A short arc (3 years) is
small but visible. The grooves vanish below 96 px by design (tier S drops them). At 128 px the dial
ticks read. At 320 px the rim text reads. At a 1920 px ten-foot hero the same vector fills the art
area on a full-bleed dark board (`ten-foot-detail-design` §1 allows the full-screen scene there),
with the title in its own slot on the left.

**How it sits with real pictures.** A graded photograph is monochrome on the print mount inside the
board. A label is onBoard on the board. Both are "one light tone on the genre's deep tone", so a
rail mixing Gunsmoke's photo with Suspense's label reads as one family. Today the outline S looks
like an empty frame instead.

**Cross-platform shape.** Nearly everything is already published: `first`, `last`, `genre`, `name`,
and episode `date`/`num`. The monogram and the run axis already have golden tests on three stacks.
New pieces:

1. **`network`** (one normalized primary network per series, published by the pipeline: the most
   frequent across its dated episodes, NBC Red and NBC Blue folded to NBC, Mutual-Don Lee to Mutual).
   Clients never parse the `networks` string.
2. **`art.label` tokens** in `design-tokens.json` (radii, groove step, dial start, end and degrees per
   year, tier thresholds, stroke widths), emitted by `tools/design_tokens.mjs` for CSS/SVG,
   SwiftUI `Canvas`, and Compose `Canvas`.
3. **`API.labelSpec(series, episode?)`** on each platform: a pure function returning
   `{ground, arc: [deg0, deg1] | null, text, small, rim}`, with golden cases (Suspense; X Minus One;
   an undated show; a show clamped at 1962, such as CBS Radio Mystery Theater; an episode with a full
   date, month only, year only, and number only; a finished ear drama's segments) in
   `js/*.test.js`, the Swift tests, and the Kotlin tests, as `cropRect` has. Drawing stays native
   (SVG / `Canvas` / Compose `Canvas` / Roku `Poster` from a pre-rendered PNG if Roku ever ships).
   No hash is needed. Two shows with the same monogram, genre, and no dates draw the same label,
   and that is true of their data. Their names, in their own slot, tell them apart.

**For.** Every mark means something, so the art is a small picture of the catalog's knowledge (a
"data portrait"). It is era-true: the disc is the object these broadcasts actually survived on. It
extends what exists (date block, run strip, monogram, fingerprint, part hues) instead of adding a
vocabulary. It is the only option that gives an episode its own image, and the only one that marks
user-made work as different without words or red. **Against.** It is skeuomorphic, a drawn
object, though flat, two-tone, and diagrammatic rather than a photo of a disc. Half of shows are
undated and draw no arc, so a Browse wall of genre-only shows is still discs with letters. That is
more intentional than today but not richer, until dates arrive. Shows after 1962 clamp (NPR-era
drama, Mystery Theater), so the dial says "1962 or later", not the year.

### 3.5 Comparison

| | A, Title card | B, Signal | **C, The label** |
|---|---|---|---|
| Carries information | name, network, decade (as words) | genre only; the rest is chance | genre, era, length of run, network, and per episode the date |
| Episode-level art | no | no | **yes** (date label) |
| Marks user-made work as distinct | no | no | **yes** (part-hue rim) |
| 56 px | monogram, as today | 3-element motif | label plus arc |
| 1920 px hero | a word on a field | strong pattern | disc with dial and rim |
| Rule 11 (name once) | conflicts in tiles | holds | holds |
| Sits with graded photos | yes | weakly (second language) | yes (same two-tone family) |
| New data | none | none | `network` (one field) |
| Cost (web / iOS / macOS / tvOS / Android) | S / S / S / S / S | L / L / M / M / L | M / M / S / M / M |

---

## 4. A Home that reads as one thing

### 4.1 Rules (proposed for WEB-DESIGN §4.2 and each platform doc; fix the doc first)

1. **One lead object.** On the air becomes the hero: the board of the show on air, full column
   width, its window at tier L (the show's picture, or its label with the evening's year ticked),
   the kicker "● On the air · Tonight in 1939", the show's name in page-title type, the event line
   (episode · N min in), Listen live (ink), All stations. Nothing else on the first screen is as
   large. When nothing is on, the doors lead (as today).
2. **The dial under the hero.** The eight genre stations as a single row of S-tier labels (each
   one's board, its genre's name, what is on now as a caption). Tapping one tunes in. This replaces
   the Listen door's job and shows the whole radio at a glance (R2 Concept A's dial, which needs
   no new data: `stations.json`).
3. **Doors get quieter.** Two doors remain (Find a show, Record a play) as one row of ghost buttons
   with icons, not bordered boxes. The navigation stops competing with content.
4. **One art system in every rail.** Every window is a graded picture or a label, the same size in
   every rail on Home (the show tile's 200-unit window), so Start a show, By length, Stories in
   parts, and Made here share one rhythm.
5. **A show at most once per Home.** Home draws its rows in order and skips a series already
   shown higher up. The rule is deterministic from the published shelves and order, the same on
   every platform, and named in the contract next to `byLength` (fixing F8 at the source, which R2
   listed). No rail may open on the same show as the rail above it.
6. **Two inks per screen.** The day board's stacked chart on Home draws its bars in onBoard, with
   the genre marks only in the legend keys, or moves whole to Browse where the overview belongs
   (`catalog-experience-design` rule 4). The plum slab becomes a **wide card at the grammar's
   size**: the drama board as the window (the script page), and the title, author, voices and
   minutes beside it on the page ground, so the board is the picture, not the background of the
   whole row.
7. **Rhythm: L, S, M, L, M, S.** Hero (L), dial (S), Start a show rail (M), Today's scene wide card
   (L), By length rail (M), voices faces (S), This day in radio (L, lower down), Made here (M). Never
   two L objects adjacent; at most one L per screen height at 375 px.
8. **Editorial framing from data only.** Headings stay verbs or rule names. A rail's facts come
   from data (years, network, length). The one new on-screen fact is the hero's era (the dial tick),
   which is drawn, not written. No blurbs, no "Because you listened".

### 4.2 The rule for real images and drawn art together

- **A picture wins when it passes the size floor; otherwise the label.** The label is never placed
  beside a picture of the same object, and never overlays one.
- **Ranking never looks at pictures.** A rail's order is its published rule. Promoting pictured
  shows would quietly turn "most downloaded" into "most photogenic" and hide 81% of the catalog
  (`values-based-feed-ranking`). The hero is whatever is on the air.
- **Same window, same mount, same radius, same edge** for both. A label never gets a drop shadow,
  a frame, or a caption the picture does not.
- **On a page about one show**, a real picture is shown whole (unchanged rule). The label appears
  there only when there is no picture, at tier L, with the rim text.

### 4.3 Detail, with the same system

- **Episode**: the head board becomes the episode's. Its window is the show's picture, else the
  episode's label (the show's disc with the date). The kicker is the show (a link), and the name is
  the episode title. Recordings collapse to "6 copies" (D1b §7.7), so the page ends on credits, not
  bitrates.
- **Series**: the label at tier L beside the name, its arc echoing the histogram under it. The date
  blocks in the log stay as they are (they are the episode labels at tier S, without the disc).
- **Now Playing and the lock screen**: the episode label when the show has no picture, so each
  broadcast has its own lock-screen art instead of one letter per show.
- **Record**: tiles keep the script page; the voice-band rules (§3.4) add the one variable the data
  supports. A real fix for the plum wall needs play metadata (§5).

---

## 5. What the data supports today vs needs

| Need | Field | Today (live, 2026-11-19) | Gap / proposed source |
|---|---|---|---|
| Label ground | `series.genre` | 87% of shows (1,135 / 1,311) | 176 shows neutral; genre work is the catalog's |
| Run arc | `series.first`, `last`, `years` | 47% of shows (617) | 694 undated shows draw no arc (honest). More dates come from the existing date work, not from this track |
| Rim text | `series.network` (one value) | the string `networks` on 40% (528), mixed ("NBC, CBS, NBC Red") | **new**: one normalized primary network, published by the pipeline |
| Decade | derived from `first` | as `first` | none |
| Monogram | `name` via `API.monogram` | all; goldens on three stacks | none |
| Episode label | episode `date`, `num` | dated episodes are about half (D1b) | none; undated and unnumbered episodes fall back to the show's monogram |
| Finished ear drama rim | cast shares, part hues, finished date | cast and hues exist in plays and productions | the finished date in the Worker's list, if not already there |
| Person ring at L | credit years | in each person file's `credits` | none (L tier only, read on the person page) |
| Play variety | play year, author dates, form (one-act) | plays carry `kind` (799 stage, 4 radio), `authors`, `voices`, `cast`, `minutes`, `opening`; no year | **needed for real variety**: author birth and death (Wikidata) or the first-edition year from Gutenberg; without them, plays stay one color |
| Home de-dup | shelf order | published shelves | **rule**, client-side and deterministic, or a pipeline cut (contract §5.1) |
| Geometry | `art.label` tokens | none | **new** in `design-tokens.json`, plus `test_design_tokens.mjs` checks (arc contrast is onBoard on board, already measured) |

---

## 6. Values check (`learning-orientation-design`)

**The three questions of the idea.**
- *Should it exist?* Yes. The title block already exists, and the label replaces it with one that
  tells the truth about each show. No other OTR app draws its catalog's facts. Not building leaves
  81% of shows as one letter.
- *Who does it touch?* Listeners, and the people outside the screen: archive.org uploaders and the
  collectors whose dates and networks feed the arc (the art makes their work visible), and the
  rights holders of network marks (refused, so untouched). The strongest case against: a drawn disc
  could suggest a recording came from a transcription disc when it came from a tape or an AFRS copy.
  Answer: the label is a format of display, not a provenance claim. It says nothing about the source
  medium, and the Recordings section keeps the real source. If the owner thinks the metaphor
  misleads, Option A has no such reading.
- *What will people learn, or stop learning?* They learn, at a glance, that radio has eras, that
  some shows ran for decades and some for one season, and that networks mattered. They will not stop
  learning anything: the label adds facts, and it never hides the name or the source.

**The four questions.**
1. **Deepens understanding?** Yes for C: every mark is a fact (era, run, network, date, cast
   shares). Partly for A (words). No for B (chance).
2. **Invites participation?** Indirectly: a disc with no arc shows a gap the catalog can fill
   (dates), and a finished ear drama's rim shows a cast of real people's parts. Home's dial invites
   tuning in, not scrolling.
3. **Supports agency?** Yes: rails ranked by published rules, never by picture presence; the hero is
   the clock's, not a model's. Nothing is inferred about the person.
4. **Clarity over cleverness?** C is one pure function and a set of tokens over fields already
   published, plus one field. B is the clever one (nine motifs, a hash, mood assignments), and is
   not recommended. A is simplest, but it fails rule 11 and carries less.

All four pass for C and for the Home rules. B fails question 1.

---

## 7. Questions only the owner can answer

1. **Which drawn-art option: A (title card), B (signal), or C (the label)?** Recommended: C.
2. **Is the transcription disc the right object for every broadcast**, including news, documentary
   and post-1962 drama, or should news get its own form (a wire slip)? Recommended: one disc for
   every broadcast. One object family is the cohesion, and the board already says news.
3. **Make On the air a real hero, and add the dial of eight stations under it**, with the doors
   reduced to two quiet buttons (§4.1 rules 1–3)? Recommended: yes.
4. **The day board's rainbow on Home**: draw it in onBoard with genre colors only in the legend, or
   move it to Browse? Recommended: onBoard on Home. The almanac stays, quieter.
5. **Today's scene as a wide card at the grammar's size** instead of a full-width plum slab?
   Recommended: yes. It keeps every word and button; only the board's area shrinks.

Answerable from existing rules, so not asked: no network logos (trademarks); ranking never uses
pictures (`values-based-feed-ranking`); a show at most once per Home (R2-review F8); red never in
drawn art (Decision 064).

## 8. If C is chosen: build order

1. Pipeline: `series.network` (normalized primary), tests over real data (shape only, never pinned
   contents).
2. Tokens: `art.label` in `design-tokens.json`, the generator, and `test_design_tokens.mjs` checks.
3. Core: `labelSpec` with goldens on web, Apple, and Android; drawn in the window by `fillWindow`'s
   block branch and its native equivalents.
4. Home rules 1–8, then Detail (§4.3); `tools/web_fit_home.py` gains checks that no rail opens on the
   show above it and that the hero is the largest window on the first screen.
5. Verify on every platform, light and dark, including a TV hero across the room and the 56 px row
   tile on the iPhone 12 and the Duo; update PARITY.md.
