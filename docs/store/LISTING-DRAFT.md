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

Rewritten 2026-11-16 for the second submission, on the owner's positioning
(memory "dual purpose"): the app is for exploring old-time radio AND making new
ear dramas from scripts, with equal weight. Facts checked 2026-11-16: 73,642
episodes and 4,842 series served (eardrama.org/data/manifest.json, 2026-11-15
publish), 803 plays in the play library. No radio script is castable yet
(SCRATCHPAD item 16), so the making half names stage plays only.

**Name** (30 max): `Ear Drama`

**Subtitle** (30 max): `Hear old radio. Make new drama`

Subtitle options for the owner: "Hear old radio. Make new drama" (30); "Classic radio. New audio drama" (30); "Listen to and make audio drama" (30); "Radio drama to hear and make" (28).

**Promotional text** (170 max):
> Ear Dramas, past and present: 73,000 old-time radio episodes to hear, and 800 plays to read and record with friends, one part at a time. Free, with no ads.

**Description:**
> Ear Drama is a home for drama made to be heard. Listen to the golden age of radio, then make new ear dramas yourself from real scripts.
>
> LISTEN
> • 73,000 old-time radio episodes from the Internet Archive's collections, in 4,800 series with air dates, networks, and casts where the records carry them.
> • On the Air plays a real broadcast evening at the hour it aired, rebuilt from the day's listings. Where a program does not survive, Ear Drama says so instead of filling the gap.
> • Browse by genre, decade, and network. Search titles, people, and air dates.
> • A sleep timer that ends with the episode or fades out, your place saved as you listen, and downloads for the car or a flight.
>
> MAKE
> • 800 stage plays in a script reader built for performers: turn pages, follow your part, highlight, underline, and write notes.
> • Record your part line by line in the script. Retake any line, and hear it in the scene.
> • Until someone records a part, a device voice reads it, so you can rehearse alone. That voice is never saved.
> • Invite friends to a shared production: each person records their own part on their own device, and the play comes together as one ear drama.
> • Read along: the script follows the voices as an ear drama plays.
>
> Free, with no ads. No account is needed; signing in is optional and syncs your listening and your shared productions.
>
> Recordings with no known rights claim are removed on request: eardrama.org/takedown

**Description, tvOS** (Apple TV has no script reader or studio; it plays and reads along):
> Ear Drama is a home for drama made to be heard. Listen to the golden age of radio, then make new ear dramas yourself from real scripts.
>
> LISTEN
> • 73,000 old-time radio episodes from the Internet Archive's collections, in 4,800 series with air dates, networks, and casts where the records carry them.
> • On the Air plays a real broadcast evening at the hour it aired, rebuilt from the day's listings. Where a program does not survive, Ear Drama says so instead of filling the gap.
> • Browse by genre, decade, and network. Search titles, people, and air dates.
> • A sleep timer that ends with the episode or fades out, your place saved as you listen, and downloads for the car or a flight.
>
>
> EAR DRAMAS YOU MAKE
> • Plays recorded with Ear Drama on iPhone, iPad, and Mac play here too, with the script alongside as the voices speak.
>
> Free, with no ads. No account is needed; signing in is optional and syncs your listening.
>
> Recordings with no known rights claim are removed on request: eardrama.org/takedown

**Keywords** (100 max, comma-separated, no spaces after commas):
`old time radio,OTR,radio drama,audio drama,radio plays,stage plays,script,record,acting,theater`

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
