# Every string the apps render, field by field (2026-10-31, P-8)

Owner, 2026-10-31: "I don't want raw text uploads to show at all ... Titles without context don't belong in the app. If it means writing with AI, based upon data, that is okay." Never invent. Scope: drama and spoken story only.

Why the earlier passes (P-6, P-7) missed things: they started from the columns the pipeline chose (series name, episode title), not from the strings the clients put on screen. This inventory starts from the clients' rendering code: web `js/app.js` and `js/plays-ui.js`, `apple/Shared` and `apple/iOS` (through `apple/Core/Catalog/CatalogDatabase.swift`), and `android/.../ui` (through `data/CatalogDatabase.kt`). A field is on the list when any of them draws it, alone or inside a sentence ("as {character}", "{role} as {character}", a share line, an accessibility label).

## The inventory (31 fields)

| # | field | where it reaches the screen |
|--:|---|---|
| 1 | `series.name` | tiles, rows, heads, search, Radio slots, stations, shares |
| 2 | `series.genre` | genre chips, the Stations list, tile captions (lower-case word, the client sets its case) |
| 3 | `series.networks[]` | Browse network filter, series head |
| 4 | `series.first_date`, `last_date`, `year_counts` | head board, decade jumps (dates: another agent's pass) |
| 5 | `series.star` (a person id) | the face and name on a tile |
| 6 | `episodes.title` | rows, Detail head, Now Playing, queue, search, Radio slots, shares, notification text |
| 7 | `episodes.aka` | "Also titled ..." |
| 8 | `episodes.season` | the 1948-49 season line |
| 9 | `episodes.network`, `network_source` | event line, Radio slot |
| 10 | `episodes.sponsor` | "Sponsored by ..." |
| 11 | `episodes.air_date`, `num` | event line (dates: another agent's pass) |
| 12 | `recordings.archive_id` | the Recordings list on Detail: the **name** of each copy on web, Apple (`ListScreens.swift`) and Android (`EpisodeScreen.kt`) |
| 13 | `recordings.label` (new) | the same list, as the name; NULL falls back to "Recording N" |
| 14 | `recordings.format`, `kbps`, `variant`, `length_s` | the facts line under a copy (mapped to words by the client) |
| 15 | `credits.role` | the "Cast and credits" heads, the roles line ("Writer, Cast as ...") |
| 16 | `credits.character` | "as {character}" |
| 17 | `people.name` | credits, person page, search, voices |
| 18 | `people.birth`, `death` | person head (dates: another agent's pass) |
| 19 | `voices.name` | Voices shelf |
| 20 | `arcs.title` | the arc offer ("Continue the story ...") |
| 21 | `art.credit`, `art.author` | the picture credit line under a portrait or show image |
| 22 | `stations.json` slots | station names, each slot's program and title: series name and episode title, so they inherit 1 and 6 |
| 23 | `tonight.json` evenings | evening name, program, network, sponsor: inherit 1, 6, 9, 10 |
| 24 | plays: `title`, `collection` | the Plays library and a script's head (`catalog/plays/castable-scripts.json`) |
| 25 | plays: `authors[].name` / `display` | "by ..." |
| 26 | plays: `roles[].name` | the speaker labels of a script (the play's own prefixes: CLAP, EBEN) |
| 27 | finished dramas | the title and cast line a finished play shows: they inherit 24 to 26 and the recorder's own display name (not catalog text) |
| 28 | search results and snippets | rows are fields 1 and 6; the transcript snippet is archive.org's automatic transcript, gated (`transcript_gate.py`) |
| 29 | withheld reason codes | never shown (`display_text.json`, manifest counts) |
| 30 | `meta.rightsLines` | the rights lines (editorial text, written here, not from uploads) |
| 31 | share-page strings (`build_share_pages.py`) | series name, episode title, the caption: inherit 1 and 6 |

Fields 4, 11 and 18 are dates; the unambiguous-date design is the app agent's. Fields 22, 23 and 31 add no text of their own, so a defect fixed in 1, 6, 9 and 10 is fixed in them; `stations.json` is rebuilt from the projection and its kept-slot rule was run (below).

## Audit against the owner's rule

The classifier is `catalog/tools/field_defects.py` (one definition, imported by the build, the guard and this table); the guard is `catalog/tests/test_display_fields.py`. Counts are **distinct texts**. SHOUT (a lower-case or upper-case genre word, `AFRS`, `WABC`) is not a defect for those fields and is left out of both columns.

Defect classes: IDENT (an identifier), GLUED (words run together), RIPTAG (OTR, mp3, kbps), COUNT (an upload's episode count), UPLOADER (ALT SOURCE, copy, v2, remastered), MOJIBAKE (broken encoding), CODE (brackets and upload codes), FILE (extension or path), DOUBLED (`--`, a dangling hyphen), SMALLWORDS ("The Case Of The Doll"), LOWERROLE (a sentence in a role).

| field | distinct (live -> now) | defects on the live projection | defects now |
|---|---|---|---|
| `series.name` | 6970 -> 6758 | CODE 6, COUNT 3, FILE 19, GLUED 22, IDENT 4, RIPTAG 2, SMALLWORDS 1425, UPLOADER 1 | clean |
| `series.genre` | 8 -> 8 | clean | clean |
| `series.networks` | 45 -> 45 | clean | clean |
| `episodes.title` | 83405 -> 82053 | CODE 840, COUNT 4, DOUBLED 71, FILE 49, GLUED 714, IDENT 53, MOJIBAKE 2, RIPTAG 18, SMALLWORDS 10523, UPLOADER 33 | clean |
| `episodes.aka` | 78 -> 78 | SMALLWORDS 23 | clean |
| `episodes.network` | 28 -> 28 | clean | clean |
| `episodes.sponsor` | 240 -> 240 | SMALLWORDS 2 | clean |
| `credits.role` | 2843 -> 1507 | CODE 4, DOUBLED 1, IDENT 1, LOWERROLE 971, MOJIBAKE 202 | clean |
| `credits.character` | 45 -> 273 | clean | clean |
| `people.name` | 15289 -> 15285 | GLUED 5, UPLOADER 1 | UPLOADER 1 |
| `voices.name` | 300 -> 300 | clean | clean |
| `arcs.title` | 335 -> 333 | GLUED 1, IDENT 1, SMALLWORDS 26 | clean |
| `art.credit` | 83 -> 83 | CODE 1, DOUBLED 1, FILE 3, GLUED 3, IDENT 3 | GLUED 3 |
| `recordings.label` | n/a -> 2273 | n/a | clean |

Fields with defects: `series.name`, `episodes.title`, `episodes.aka`, `episodes.sponsor`, `credits.role`, `credits.character`, `people.name`, `arcs.title`, `art.credit`, `recordings.archive_id` (an identifier used as a name), plays `title` and `authors` ("..., with Notes and Introduction"; "Baker, George M. (George Melville)"). Clean on the live projection: `series.genre`, `series.networks`, `episodes.network`, `voices.name`, `meta.rightsLines`. Left as the source writes them, with the reason: play speaker labels (CLAP, EBEN) are the play's own prefixes; `people.name` "Harley Copy" is a real name; `art.credit` user names such as "JQRalph" are Commons accounts, credited as the licence requires.

| field | distinct (live -> now) | defects on the live projection | defects now |
|---|---|---|---|
| `series.name` | 6970 -> 6758 | CODE 6, COUNT 3, FILE 19, GLUED 22, IDENT 4, RIPTAG 2, SMALLWORDS 1425, UPLOADER 1 | clean |
| `series.genre` | 8 -> 8 | clean | clean |
| `series.networks` | 45 -> 45 | clean | clean |
| `episodes.title` | 83405 -> 82053 | CODE 840, COUNT 4, DOUBLED 71, FILE 49, GLUED 714, IDENT 53, MOJIBAKE 2, RIPTAG 18, SMALLWORDS 10523, UPLOADER 33 | clean |
| `episodes.aka` | 78 -> 78 | SMALLWORDS 23 | clean |
| `episodes.network` | 28 -> 28 | clean | clean |
| `episodes.sponsor` | 240 -> 240 | SMALLWORDS 2 | clean |
| `credits.role` | 2843 -> 1507 | CODE 4, DOUBLED 1, IDENT 1, LOWERROLE 971, MOJIBAKE 202 | clean |
| `credits.character` | 45 -> 273 | clean | clean |
| `people.name` | 15289 -> 15285 | GLUED 5, UPLOADER 1 | UPLOADER 1 |
| `voices.name` | 300 -> 300 | clean | clean |
| `arcs.title` | 335 -> 333 | GLUED 1, IDENT 1, SMALLWORDS 26 | clean |
| `art.credit` | 83 -> 83 | CODE 1, DOUBLED 1, FILE 3, GLUED 3, IDENT 3 | GLUED 3 |
| `recordings.label` | n/a -> 2273 | n/a | clean |

(`credits.character` grows from 45 to 273 because 228 stage names that rode inside the role text ("host, as 'Geoffrey Barnes'") now sit in the character field; `credits.role` falls from 2,843 to 1,507 distinct because the same notes are folded into a word or two.)

## What changed, by rule

All in `catalog/tools/polish.py` (the last pass, imported by `build_projection.py`), `display_text.py`, `enrich_scope.py` and `art_policy.py`. Each rule undoes one habit and adds no word the source did not spell, except the dictionary contractions below.

- Broken encodings repaired (`â€™` and `???s` to an apostrophe); a title whose characters were lost is composed from data or withheld.
- Upload notes and codes out of titles: `[474]`, `[AFRTS]`, `{AFRS}`, `[b00rl56h]`, `Aud01 `, `(HQ)`, a trailing ` copy`, `-Ver 2`, `REMASTERED`. Other bracketed words become parentheses.
- Part markers: `- Ep 3` to `, episode 3`; `Ep01of03` to `, episode 1 of 3`.
- Glued article `APink` to `A Pink`; `--` to ` - `; an inverted article ("Flooded House, The") set back.
- Small words lower-cased in a title-case title (`Of The` to `of the`), never at a part's start or end.
- Apostrophes: the dictionary contractions (`Dont`, `Cant`, `Isnt` ... and `Lets` only as a title's first word) and, where an independent source (`episode_witnesses`) spells the same letters with an apostrophe, that spelling (exactly one, not shouted).
- Series names: an episode-count suffix (`48 Eps`) and uploader suffixes (`ALT SOURCE`, `copy`, `v2`); a name that is still a file name, a date fragment ("Aired 15") or carries a code is withheld.
- Roles: a word or two, or none (shown as cast); the stage name moves to `character`.
- `recordings.label` (new): see the contract, section 3.2.
- Pictures: wiki markup and bare links out of the credit line.
- Plays: `title` without cataloguer boilerplate; `authors[].display` ("George Melville Baker").
- Scope (catalog DECISIONS 027): band remotes and run-together music-group names. Speeches stay.

## Not repaired, on purpose

- "Star, Bright" (X Minus One): Wikipedia spells it with the comma, Haendiges without; neither is a registry, so it stays as sourced.
- "Truck Hi-jackers - Tom Laval", "Brick-Bat Slayer": the source's own spelling and hyphenation.
- "Whatever Became Of" (series): a fragment the source gave; nothing to compose it from.
- "Dramatis Personae" (a play's cast-list section) and the 71-character "1601: Conversation, as it was by the Social Fireside ..." are the works' own titles.

## Speeches stay

The first pass withheld 28 speech series. Owner ruling, 2026-10-31: "Keep them." Historical speeches and wartime addresses are in scope (catalog DECISIONS 027); the rule is removed. Band remotes ("Band Remotes", "Remote Harryjames" and the rest of the "Remote ..." series, 28 series, 75 episodes) remain out of scope as music.
