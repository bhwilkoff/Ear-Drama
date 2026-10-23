# Store listing words: draft for the owner

**Status: DRAFT, not approved.** Decision 060: the agent drafts store and asset
words; the owner approves; nothing reaches a listing unapproved. Every claim
below is a fact about the app as built on 2026-10-23, with its source. A line
marked *check* is true on main but must be re-measured before submission.
Lengths measured 2026-10-23: subtitle 27/30, promotional text 151/170,
keywords 97/100, Play title 25/30, Play short description 80/80, description
979/4000.

Rules the words keep: never "public domain" for an unclaimed recording
(Decision 055); no superlatives the app cannot show; no feature a platform
lacks (PARITY.md); US English.

---

## Shared facts (the source for every line)

| Fact | Value | Source |
|---|---|---|
| Episodes served | 108,005 (*check*: rises with each publish) | SCRATCHPAD "Catalog now" |
| Price, ads, account | Free, no ads, signing in optional | Decisions 057, AGENTS.md |
| Radio | a past evening rebuilt on its own clock; gaps shown as gaps | Decision 058, PARITY "Radio" |
| Plays | record a stage play part by part on one device, with headphones | Decision 059, PARITY §3 |
| Sleep timer | ends the episode or fades over 10 seconds | Decision 062 |
| Transcripts | archive.org's automatic transcripts, labeled as such, where they pass the gate | Decision 058 |

---

## App Store (iOS, iPadOS, macOS, tvOS)

**Name** (30 max): `Ear Drama`

**Subtitle** (30 max): `Old-time radio, as it aired`

**Promotional text** (170 max):
> Hear a real evening of old-time radio, rebuilt from the newspaper's listings and played at the hour it aired. Over 100,000 episodes, free, with no ads.

**Description:**
> Ear Drama is a place to listen to old-time radio and radio drama from the Internet Archive's collections.
>
> RADIO
> Tonight in 19xx rebuilds a real broadcast evening from the newspaper's listings and plays it on its own clock. Where a program does not survive, Ear Drama says so instead of filling the gap.
>
> SERIES AND EPISODES
> Browse series by genre and decade, with air dates, networks, casts, and sponsors where the records carry them. Each episode plays the best surviving copy, and you can choose another.
>
> FOR BEDTIME AND THE CAR
> A sleep timer that ends the episode or fades out over ten seconds. Your place is saved as you listen.
>
> PLAYS
> Record a stage play with friends, one part at a time, on one device. Until someone records a part, a device voice reads its cues aloud; that voice is never saved.
>
> Free, with no ads. Signing in is optional and only syncs your listening between devices.
>
> Recordings with no known rights claim are removed on request: eardrama.org/takedown

*Check before submission: genre and decade filters, sponsors on Detail, and
the versions picker on every platform (ANDROID-DESIGN §12 lists Detail's
missing sponsor).*

**Keywords** (100 max, comma-separated, no spaces after commas):
`old time radio,OTR,radio drama,radio shows,audio drama,classic radio,mystery,western,comedy,sleep`

**Category**: Entertainment (secondary: Education). *Owner's call.*

---

## Google Play

**Title** (30 max): `Ear Drama: Old-Time Radio`

**Short description** (80 max):
> Old-time radio and radio drama, free with no ads. Tonight's 1940s evening, live.

**Full description**: the App Store description above, unchanged (Play allows
4,000 characters; the same words keep the verbs identical).

---

## Privacy answers (both stores) *check before submission*

- Without signing in: no data collected by Ear Drama (listening history stays
  on the device). *Check:* no analytics or crash SDK in any client.
- Signed in: an account identifier from Apple or Google (no email, no name
  stored, Decision 063) and listening history, queue, and follows, linked to the
  account, used only for sync; deletable in the app and at the web deletion page.
- Recording a play: audio stays on the device in phase 1 (M7); nothing is
  uploaded.

---

## Open for the owner

1. The subtitle and promotional line: "as it aired". The evening's year
   changes nightly (the 15 published on 2026-10-23: ten from the 1940s, three
   from the 1950s, two from the 1930s), so neither names a year or decade.
2. Category: Entertainment or Education first.
3. Whether the take-down address belongs in the description.
