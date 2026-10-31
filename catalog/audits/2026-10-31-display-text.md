# Audit of displayed text, 2026-10-31 (P-6)

Owner, verbatim: "there are hundreds of shows/ear dramas that have uploader titles or garbage text that show instead of clean metadata and titles that should be there. I need you to do an audit of the text that displays in the app to see if we can get a much cleaner database."

Ruling the same day: raw uploader text never reaches a display field; a title may be composed from data, never invented; what has no context is withheld and kept in the research database (catalog DECISIONS 025).

Measured on the live projection `catalog-latest` (10,641 series, 107,190 episodes, 216 M series-downloads) and on a local rebuild from the same caches with these changes (8,740 series, 103,027 episodes). Counts are plain; "dl" is the series' downloads (series) or the default copy's item downloads (episodes). A row can fall in several title classes. The classifier is `catalog/tools/text_defects.py`; the guard is `catalog/tests/test_display_text.py`.

## Root cause

Confirmed in part, corrected in part. `build_db.resolve_file` tries the file-name series, the folder, the item, the item title and the ID3 album/artist against the registry (OTRR, RadioEchoes, editorial aliases) and, when nothing matches, takes the first usable name as a series of its own: that is how uploads became shows (8,318 served series, 31,943 episodes were placed that way, no registry source). Two corrections: (1) the 297 dated "series" were a **parser bug**, not a collection: a date written `1959 10 01 World Series ...` fell through to `F5_number`, which read "1959 10" as the series and the day as the episode number (1,094 of 1,106 episodes in them); (2) most unplaced series are genuine one-off programs the registry does not know; only a few hundred are grab bags. The file *name* itself was never tried against the registry, and a file's own ID3 title never beat a title that only restated the file name.

## Class table (before = live, after = rebuild)

| class | before n | before dl | after n | after dl | fix and evidence |
|---|---:|---:|---:|---:|---|
| S_DATED name is a date or number | 297 | 25,726,804 | 0 | 0 | Parse fix: a date written "YYYY MM DD" was read as a series (otr_parse F7d/F7e); the series is then the item's own title (class 2). Left: a name that is still a date is withheld. Evidence: file names (dated), archive.org item `title`. |
| S_LOWER name has no capital | 151 | 879,019 | 0 | 0 | Item `title` that spells the same letters (class 2); a multi-word lowercase name is set in the catalog's case (titles.py); a one-word lowercase identifier is withheld. Evidence: archive.org item `title`, the catalog's own vocabulary. |
| S_RUNTOGETHER name is a run-together identifier | 99 | 4,825,818 | 0 | 0 | Album tag the uploader wrote on 80%+ of the files (class 2); else withheld. Evidence: ID3 `album` in the item's files. |
| S_COLLECTION name is an uploader's grab bag | 51 | 796,709 | 5 | 60,480 | Re-attribute the files whose names begin with a known program (class 1); a grab bag with nothing re-attributable is withheld. A collection named for a person stays. Evidence: OTRR / RadioGOLDINdex / RadioEchoes program names and titles; file dates vs the program's run. |
| T_LEADNUM leading number, code or date | 689 | 9,512,123 | 1,293 | 41,625,535 | Already mechanical (DECISIONS 022); the rest keep their numbers because a series with no dates sorts by them. Evidence: none needed. |
| T_RUNTOGETHER words run together | 2,046 | 112,993,585 | 0 | 0 | ID3 `title` over a title that restates the file name (class 3); the series name run together as one token is dropped; else composed or withheld. Evidence: ID3 `title` per file. |
| T_RIPTAG OTR / mp3 / kbps / VBR left in | 3,322 | 22,737,918 | 71 | 764,061 | titles.py `_tidy` (class 4). Evidence: mechanical. |
| T_CODE square or curly brackets, codes | 962 | 50,895,383 | 874 | 48,141,114 | titles.py `_tidy`: shelf codes, "RRT182:" tags and BBC pids removed; words in brackets are the source's and stay. Evidence: mechanical. |
| T_DOUBLED doubled punctuation | 181 | 12,502,789 | 83 | 6,372,565 | titles.py `_tidy`: " -- " and "- -" to " - ", ",," to ",". Evidence: mechanical. |
| T_CASE no lowercase / no capital | 2,450 | 39,010,315 | 353 | 7,999,855 | A title with no capital is set in the catalog's case; "episode 3"-style titles are composed. Evidence: the catalog's vocabulary. |
| T_EMPTY no title or a placeholder | 3,840 | 37,449,295 | 0 | 0 | Composed from series name + air date or number; else withheld. Evidence: episodes.air_date, episodes.num. |
| CLEAN series | 10,050 | 184,478,873 | 8,735 | 181,052,583 | |
| CLEAN episode titles | 93,948 | 16,848,326,362 | 100,359 | 17,028,822,415 | |

The "after" S_COLLECTION rows are collections named for a person ("Boris Karloff Collection"). The "after" T_LEADNUM, T_CODE, T_DOUBLED and T_CASE rows are residue: numbering kept because an undated series sorts by it (DECISIONS 022), words in brackets, " : " spacing, and shouted titles.

## Five real examples per class (live text, then what is shown now)

### S_DATED: name is a date or number (297)

- `1959 10` -> `Classic Baseball on the Radio`
- `1961 10` -> `Classic Baseball Radio Broadcasts MLB`
- `2020-11` -> withheld (series_name_is_a_date)
- `2013-05` -> withheld (series_name_is_a_date)
- `1943 07` -> `1940s Classic MLB Radio Broadcast`

### S_LOWER: name has no capital (151)

- `jbintro` -> withheld (series_name_is_an_identifier)
- `rrthriller2` -> `Relic Radio Thrillers`
- `strindberg the father` -> `Strindberg the Father`
- `the mystery of his will` -> `The Mystery of his Will`
- `the blues 14. feel like goin to canada` -> `The Blues 14. Feel Like Goin to Canada`

### S_RUNTOGETHER: name is a run-together identifier (99)

- `CaseClosed3` -> `Case Closed`
- `RRSciFi2` -> `Relic Radio Science Fiction`
- `RRShow1` -> `Relic Radio Show`
- `Afrs058-JackBenny` -> withheld (series_name_is_a_file_name)
- `Afrs020-JackBenny` -> withheld (series_name_is_a_file_name)

### S_COLLECTION: name is an uploader's grab bag (51)

- `Singles & Doubles Collection` -> withheld (series_is_an_uploaders_grab_bag)
- `Misc` -> withheld (series_is_an_uploaders_grab_bag)
- `Various Tomorrow is Today A Tribute to the Australian Psychedelic Scene disc one the tributes leda036` -> `Tomorrow is Today: Tributes`
- `Old Time Radio CFRG` -> withheld (series_is_an_uploaders_grab_bag)
- `Old Time Radio` -> withheld (series_is_an_uploaders_grab_bag)

### T_LEADNUM: leading number, code or date (689)

- `048 V-Disc A Bing Crosby Chorus and Orchestra - Silent Night` (500 Christmas Shows) -> `048 V-Disc A Bing Crosby Chorus and Orchestra - Silent Night`
- `048 V-Disc A Chorus and Organ - Joy To The World` (500 Christmas Shows) -> `048 V-Disc A Chorus and Organ - Joy To The World`
- `060 V Disc A David Rose his Orchestra - Our Waltz` (News From The 30's Through The 70's) -> `060 V Disc A David Rose his Orchestra - Our Waltz`
- `042 V Disc B Goldman Band - Korcoran Cadets` (American Armed Forces Radio No 14) -> `042 V Disc B Goldman Band - Korcoran Cadets`
- `058a Tommy Tucker Time-Do You Know` (AFRS V Disc 7) -> `58a Tommy Tucker Time - Do You Know`

### T_RUNTOGETHER: words run together (2,046)

- `A Tale of Two Sisters (RomaWinesPresents; has BSA PSA)` (Suspense) -> `Suspense, February 8, 1945`
- `BasementBroadcast` (Bob And Ray Show) -> `Bob And Ray Show, June 29, 1959`
- `RelicRadio145` (Relic) -> `Suspense and Cabin B-13`
- `CaseClosed150` (CaseClosed1) -> `Murder Clinic and Crime Classics`
- `CommissarisVanIn-Inferno-deel 09` (PieterAspe) -> withheld (series_name_is_a_file_name)

### T_RIPTAG: OTR / mp3 / kbps / VBR left in (3,322)

- `Hillybilly Feud (OTR)` (Jack Benny Program) -> `Hillybilly Feud`
- `19360728Chicago White Sox Vs Athletics Vintage Baseball Otr` (Classic Baseball Radio Broadcasts MLB) -> `Chicago White Sox vs Athletics Vintage Baseball`
- `Rdria OTR USO` (Rdria USO) -> `Rdria USO`
- `Buckshot's Victory 52-02-22 (OTR)` (W B Hickok) -> `Buckshot's Victory 52-02-22`
- `Suspicion (OTR)` (Theater Of Romance) -> `Suspicion`

### T_CODE: square or curly brackets, codes (962)

- `[Pre-empted {was to be The Jackie Cleaver Matter, broadcast 51-03-31}]` (Yours Truly Johnny Dollar) -> `Yours Truly Johnny Dollar, December 9, 1950`
- `The Dameron Matter [Network]` (Yours Truly Johnny Dollar) -> `The Dameron Matter [Network]`
- `Spellbound (Benedict Cumberbatch) [by Ben Hecht]` (2008-02) -> withheld (series_name_is_a_date)
- `Dover Beats the Band (60 min) [2012-01-12 R4Xtra] (GBCC) 128 Kbps` (Chief Inspector Dover Mysteries) -> `Dover Beats the Band (60 min) [2012-01-12 R4Xtra] (GBCC)`
- `Originals By Bennett xxxxxx - [Audition] Joan Gets A Job` (Audition Recordings of Unrecognized Programs) -> `Originals By Bennett xxxxxx - [Audition] Joan Gets A Job`

### T_DOUBLED: doubled punctuation (181)

- `The Gravedigger???s Spades (Mr & Mrs Arbuthnel Trump)` (Yours Truly Johnny Dollar) -> `The Gravedigger???s Spades (Mr & Mrs Arbuthnel Trump)`
- `To Rent -- Danger` (The Whistler) -> `To Rent - Danger`
- `Winston Churchill%27s Address to Congress on the Allied Struggle , 05:19:1943` (Winston Churchill's Address To Congress On The Allied Struggle 05/19/) -> withheld (series_name_is_a_file_name)
- `Book 1, Chapter 7 : Going Down the Volga` (Michael Strogoff (Dramatic Reading)) -> `Book 1, Chapter 7 : Going Down the Volga`
- `How sweet the moonlight.. - The Merchant of Venice` (Shakespeare Monologues Collection vol. 10 (Multilingual)) -> `How sweet the moonlight. - The Merchant of Venice`

### T_CASE: no lowercase / no capital (2,450)

- `news-battleofbritain` (News reports 01) -> `News reports 01, August 16, 1940`
- `jbintro` (jbintro) -> withheld (series_name_is_an_identifier)
- `deel 08` (Arjen) -> withheld (no_readable_title_and_no_date_or_number)
- `raid of the international xmas` (The Goon Show) -> `Raid of the International Xmas`
- `series 3 episode 03 - innocent party` (Destination Fire) -> `Series 3 Episode 03 - Innocent Party`

### T_EMPTY: no title or a placeholder (3,840)

- `20-20` (Gunsmoke) -> `Gunsmoke, July 16, 1955`
- `xxx` (Bob And Ray Show) -> `Bob And Ray Show, July 31, 1949`
- `None` (Afrs095 Jack Benny Claudette Colbert Paulette Goddard) -> withheld (series_name_is_a_file_name)
- `None` (Afrs001 Fred Allen guest Orson Welles) -> withheld (series_name_is_a_file_name)
- `None` (The Guiding Light) -> `The Guiding Light, episode 810`

## What moved, and why

Recorded per episode in `identity.reattributed` (`from` series, the name as uploaded, `rule`, and for a file name the `gate` that held). Episodes served or not, by rule:

- album tag: 776
- file name begins with a known program / gate title: 257
- file name begins with a known program / gate date: 234
- file name begins with a known program / gate date (hidden by the rights audit): 93
- file name begins with a known program / gate title (hidden by the rights audit): 70
- album tag (hidden by the rights audit): 42

Largest moves (from series -> to series, episodes):

- `0920wwjtytysonnyyankeesvsdetroittigers` -> `1930's Radio News`: 81
- `News From The 30's Through The 70's` -> `CBS World News Today`: 59
- `rrscifi2` -> `Relic Radio Science Fiction`: 55
- `caseclosed3` -> `Case Closed`: 49
- `caseclosed1` -> `Case Closed`: 47
- `relicradioscifi` -> `Relic Radio Science Fiction`: 46
- `rrthrillers1` -> `Relic Radio Thrillers`: 44
- `rrscific` -> `Relic Radio Science Fiction`: 40
- `rrshow2` -> `Relic Radio Show`: 40
- `American Armed Forces Radio No 65` -> `Dragnet`: 38
- `Miscelaneous Radio News AFN AFRS 1 3 GB` -> `CBS World News Today`: 37
- `casecloseda` -> `Case Closed`: 35
- `rrshow3` -> `Relic Radio Show`: 32
- `rrthriller2` -> `Relic Radio Thrillers`: 32
- `rrscifi1` -> `Relic Radio Science Fiction`: 31
- `caseclosed2` -> `Case Closed`: 30
- `caseclosedb` -> `Case Closed`: 30
- `American Armed Forces Radio No 129` -> `Swing And Sway With Sammy Kaye`: 29
- `oldtimegospelhits` -> `OLD TIMEY GOSPEL`: 27
- `American Armed Forces Radio No 7` -> `Gunsmoke`: 27
- `Benny Goodman's Radio Performances of the 1930s` -> `Camel Caravan`: 26
- `rrthrillersb` -> `Relic Radio Thrillers`: 25
- `rrthrillersc` -> `Relic Radio Thrillers`: 23
- `thereslaughterintheair` -> `There's Laughter in the Air! Radio's Top Comedians and Their Best Shows`: 22
- `American Armed Forces Radio No 66` -> `My Friend Irma`: 15

Episodes that stay in a grab bag are either withheld (below) or, where the series is a person's collection, shown under it.

## Withheld from the apps (kept in the research database)

Series withheld, by reason: series_name_is_a_file_name 1,337, series_name_is_a_date 73, series_name_is_an_identifier 50, series_is_an_uploaders_grab_bag 36, series_named_by_an_upload_code 6.

Episodes withheld, by reason (includes every episode of a withheld series): series_name_is_a_file_name 2,037, no_readable_title_and_no_date_or_number 1,170, series_is_an_uploaders_grab_bag 1,076, series_named_by_an_upload_code 599, series_name_is_a_date 195, series_name_is_an_identifier 114. Total 5,191 of 107,190.

## Five composed titles and their source fields

- `Fiddlin Mike Hollerich, episode 2` from series.name, episodes.num (episode `fiddlinmikehollerich|n2`)
- `Perry Mason, episode 2751` from series.name, episodes.num (episode `perrymason|n2751`)
- `Kees den does en zijn politiehond - deel, episode 3` from series.name, episodes.num (episode `keesdendoesenzijnpolitiehonddeel|n3`)
- `Tip Toe Thru the 20's, episode 129` from series.name, episodes.num (episode `tiptoethruthe20s|n129`)
- `Gregory Keen - Dossier On Dumetrius, episode 8` from series.name, episodes.num (episode `gregorykeendossierondumetrius|n8`)

Composed in all: 4,395 episodes.
