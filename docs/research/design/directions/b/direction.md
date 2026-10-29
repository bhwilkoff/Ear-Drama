# Direction B: The Company

*D2, 2026-10-29. Prototype: `index.html?s=<screen>`. Data: `../shared/sample.js`,
taken from the live projection (generated 2026-10-29T16:30Z). The production's
performers (Pat, Sam, Ada) are D1c's fixture names, not real people.*

## Metaphor

A radio stock company's playbill and face book. Network radio was a repertory:
the same few hundred voices played the detective, the widow and the announcer
night after night, across shows. In this direction a person finds by **who**,
the way a theater regular reads a playbill: the faces first, then the play they
are in. Shows and episodes are still the units you play. People are the way in.

## What it surfaces

- **Most heard** (Home, Browse's Voices scope): the people heard on the most
  episodes who have a served portrait, as a wall of round face crops with each
  name and episode count. The heading names the rule. D1a §1.3: 613 of the 1,795
  people heard on 20 or more episodes have a portrait. So the app goes from
  mostly letter tiles to mostly faces without loosening Decision 069.
- **Shows by their star** (Browse's Shows scope): each show's star print at its
  own aspect, or its typographic card when it has none, with the star's name,
  the core years and the episode count. The count is the true one: "1,374
  shows", with "7,189 single recordings" one tap away (D1a §4.1).
- **Heard most, per season** (series page): the faces heard most in the season
  in view (Suspense 1943–44: Hans Conried 36, John McIntire 17). A face heard on
  a quarter or more of the season counts as a regular. Each episode row shows
  its first other face as the guest (Cary Grant on "The Black Curtain", Lillian
  Gish, Charles Laughton). An anthology reads as a list of guest stars, its
  strongest scent (D1a §3.2, series page, "Add, candidate").
- **On the air** (Detail and Now Playing): up to three faces as captioned prints
  above the title, then the broadcast line ("CBS · Thursday, December 2, 1943 ·
  Roma Wines") and Play with the length on the button (D1b Patterns 1 and 2).
  Now Playing puts the episode's face whole at its own aspect, and the faces
  row below the transport.
- **The cast sheet as a playbill** (Create): each part is a card with its
  reading time and line count. A claimed part shows its performer's initial.
  An open part shows Take part. There is one name field, not one per part
  (D1c Pattern 3). The recorder says who else is in the production.
- **The finished production as a playbill** (Share): the title, the author,
  "Recorded October 23–29, 2026", each part followed by its performer, one
  Listen through, Listen together and Share. Project Gutenberg's own rights
  claim is quoted and linked (D1c Pattern 5).

## What it hides

- Network lists, sponsors and years on list rows. The sponsor appears only in
  Detail's broadcast line.
- The full credits: behind a closed "Cast and credits" disclosure, grouped
  On the air / Writing / Production, one line per person (D1b Pattern 2).
- Copies: behind a closed "Copies" disclosure with its count. Here all six are
  full 30-minute copies, so nothing more is said (D1b Pattern 7).
- People without a portrait on the walls. They stay in credits and Search.
  A wall is a rule over data, never a judgment.

## The sparse record

Stay Tuned For Terror (two undated episodes, no faces) and the 1945 Radio News
episode (dated, no credits) draw the typographic card large, then a row per
episode named by its number ("No. 31"), Play, and the rights line. Nothing
promised is missing, because no faces section is drawn when there are none.

## Cost per platform

| Platform | Cost | Native idiom |
|---|---|---|
| Pipeline | M | Merge duplicate people (Clayton "Bud" Collyer and Bud Collyer, D1a §1.3), split Goldin cast fragments (D1b §1), publish a role-to-group map, publish per-season "heard most" and the guest rule (computed once, never on a device). Optional: a billing rule for whose face leads. |
| Web | M | CSS grid walls, `<details>` for credits and copies, the existing `API.cropRect` crop |
| iOS / iPadOS | M | `LazyVGrid` of face crops, `DisclosureGroup` credits, a scope `Picker` for Voices and Shows, size-class columns on iPad |
| macOS | S after iOS | The shared Core views; more grid columns; a person page per window |
| tvOS | M | A face shelf is the native ten-foot idiom (focus scale on the focused face only); Detail's faces as one focus section, the credits as another |
| Android | M | `LazyVerticalGrid` with Coil crops at the face box, `SegmentedButton` for scopes, an expandable credits section |

A person page (WEB-DESIGN §4.14) is the destination of every face. It exists
on every platform and gains a Discogs-style filmography (D1a §4.3).

## Which D1 findings it answers

- D1a Verdict 2 (faces belong to people, not shows), §4.3 (voices wall), §4.1
  (two-tier count), §3.2 (guest name on anthology rows).
- D1b Verdict 4 (credits are liner notes), Pattern 1 (broadcast line), Pattern 2
  (three faces, then the booklet), Pattern 6 (Now Playing's "who is on" below the fold).
- D1c Patterns 3 (one name, time not lines), 4 (who holds a part), 5 (the
  premiere page as a playbill).

## Risks

- **Shows stay mostly cards.** Only 271 series (2.5%) have a star portrait, 17%
  of shows with ten or more episodes. In the popular top 24, 7 are cards. The
  Shows grid must look right as a mix, and the long tail will be all cards.
- **Whose face leads is an owner question.** Data order puts Hans Conried over
  Cary Grant on "The Black Curtain". The series rule gives Boston Blackie a
  supporting actress (D1a "Seen on the way"). A billing rule is a ranking, so it
  goes through `values-based-feed-ranking` and is published, never computed per
  device.
- **Celebrity bias.** A wall ranked by episode count favors comedy regulars
  (the Jack Benny and Fibber McGee casts hold seven of the top eight). The heading states the rule.
  A second scope (per genre, per decade) would widen it without a new ranking.
- **Duplicate and wrong people show at the top.** The wall is only as good as
  the people merge.
- **Faces of a production's cast** are initials only. A signed-in performer's
  photo is a consent and moderation question this direction does not open.

## Screenshots

| Screen | 375 px | 1440 px |
|---|---|---|
| Home | ../../img/d2/b/home-375.png | ../../img/d2/b/home-1440.png |
| Browse | ../../img/d2/b/browse-375.png | ../../img/d2/b/browse-1440.png |
| Series, rich (Suspense) | ../../img/d2/b/series-rich-375.png | ../../img/d2/b/series-rich-1440.png |
| Series, sparse (Stay Tuned For Terror) | ../../img/d2/b/series-sparse-375.png | ../../img/d2/b/series-sparse-1440.png |
| Episode, rich (The Black Curtain) | ../../img/d2/b/episode-rich-375.png | ../../img/d2/b/episode-rich-1440.png |
| Episode, bare (1945 Radio News) | ../../img/d2/b/episode-bare-375.png | ../../img/d2/b/episode-bare-1440.png |
| Now Playing | ../../img/d2/b/now-playing-375.png | ../../img/d2/b/now-playing-1440.png |
| Create: pick a play | ../../img/d2/b/create-pick-375.png | ../../img/d2/b/create-pick-1440.png |
| Create: claim a part | ../../img/d2/b/create-part-375.png | ../../img/d2/b/create-part-1440.png |
| Create: record a line | ../../img/d2/b/create-record-375.png | ../../img/d2/b/create-record-1440.png |
| Production page | ../../img/d2/b/production-375.png | ../../img/d2/b/production-1440.png |
