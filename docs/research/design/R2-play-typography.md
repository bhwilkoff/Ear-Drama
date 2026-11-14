# R2-T: Setting a play on the page (research and design, 2026-11-14)

The owner, 2026-11-14 (verbatim): *"You definietly need to work on the formatting of plays.
Probably need to figure out the best way to show plays from research and then figure out an
innovative way to do it within our app."*

This follows `R2-script-reader-and-studio.md` §4.1, the reader the web shipped earlier that day
(Decision 076 S1). It covers the research, what was wrong, the design (the **Ear Drama page**),
the data problems the parser has to fix, and the frames before and after. The rules it produced
are binding in PLAYS-DESIGN §2.7 rule 10 and WEB-DESIGN §4.16 item 3. Each platform doc's reader
section gives the same rules in its own idiom.

Frames: `img/play-typography/before/` and `img/play-typography/after/`, named
`{case}-{theme}-{width}.png`. The cases are **stage** (Shaw, *The Philanderer*, gut-5071, at L0009),
**verse** (*Macbeth*, gut-1533, at L0015) and **radio** (*Caesar Rodney's Ride*, gut-28051, at
L0020). Each is shot at 320, 375, 430 and 1440 px, in light and dark, in headless Chrome over
DevTools at device scale 2 (stored at 1x), with scrollWidth checked against the width (no frame scrolls
sideways).

---

## 1. What was wrong (read from the frames)

| # | Problem | Seen in |
|---|---|---|
| W1 | **The speaker was run in.** A 13 px name in the part's hue sat at the start of the paragraph, so names and words were one gray block, and a scan for who speaks next had nothing to land on. On a phone, a long speech pushed the name off the screen. | `before/stage-light-375.png`, `before/radio-light-375.png` |
| W2 | **A page opened mid-speech with no speaker.** "brought out all the good in him…" at the top of page 2, with nobody named. | `before/stage-light-375.png` |
| W3 | **Speeches run together were drawn as one person's.** "Of course. Why not? GRACE *reflecting*. Never mind why. … CHARTERIS *amazed…*" was all drawn as CHARTERIS. This is a parser miss: 7,630 speeches in 151 of 552 library scripts sampled (§4 D1). | `before/stage-light-375.png` |
| W4 | **Verse was reflowed as prose.** "What bloody man is that? He can report, As seemeth by his plight…": the line breaks the data keeps were thrown away. | `before/verse-light-375.png` |
| W5 | **A direction inside a speech looked like speech.** An italic gray fragment with no parentheses: "Yes--the first thing tomorrow morning. *murmurs of assent*", or "HANCOCK *sound of gavel* You have heard…". | `before/radio-light-375.png` |
| W6 | **Radio sound cues had no lane.** A knock, a gavel or a door was drawn as an italic aside, the same as "(to himself)", although in radio drama the sound *is* the scene. | `before/radio-light-375.png` |
| W7 | **Brackets were inconsistent.** "[Enter Lane.]" kept its brackets, but "Lane goes out." (an aside) did not. And "[_Exeunt._]" printed as roman "[Exeunt.]" once its italic marks were turned. | `before/earnest-light-1440.png`, `before/verse-light-375.png` |
| W8 | **No cast list.** The reader opened on the first speech. The person had never seen which hue meant which part. | every before frame |
| W9 | **Headings came in two arbitrary sizes** (1.25 em and 1.05 em), which is a seventh type level, and acts did not open a page. | `before/verse-light-375.png` |
| W10 | **The "I'm playing" tint was clipped** at a page's left edge, by its negative margin inside the page clip. This was noted in DESIGN-LOOP tick 11. | stage-mine, before |
| W11 | **A name could be left alone at a page's foot**, and a single verse line could be carried alone onto the next page. | `after` pass 1, fixed |

## 2. What the conventions say (research, cited)

Pages the research opened are marked (verified). Pages seen only in search results or another
write-up are marked (secondhand).

- **Acting editions (Samuel French guide, hosted by the Dramatists Guild, verified;**
  https://www.dramatistsguild.com/sites/default/files/2020-01/General-SFI-Formatting-Guidelines-Complete.pdf**):**
  - The name is in ALL CAPS on its own line above the speech.
  - A one-word direction may sit on the name line in parentheses, e.g. "JOHN (laughing)". Longer directions go on their own indented line in parentheses.
  - Names inside directions are in CAPS.
  - A speech continued onto the next page is marked **"(Cont.)"**.
  - Each act starts a new page.
  - A cast page follows the title.
  - The DG modern sample (verified, https://www.dramatistsguild.com/sites/default/files/2019-12/modernformat-New.pdf) indents stage action toward the page's center, with a blank line around it.
- **Folger digital texts (verified,** https://www.folger.edu/explore/shakespeares-works/hamlet/read/1/2/**):**
  - The speaker is in CAPS above the speech.
  - Entrances are centered. Directions inside a speech get their own right-aligned line.
  - A split verse line is indented to start where the previous part-line ended.
  - Stable through-line numbers are used for reference.
  - Verse lines are joined with `&nbsp;`, so they never reflow. That overflows on a phone; avoid it.
- **Internet Shakespeare Editions lineation (verified,** https://internetshakespeare.uvic.ca/Foyer/guidelines/lineation/index.html**):** part-lines are indented. When the linking is doubtful, the line is not indented.
- **BBC radio drama, scene style (Writersroom, 2004, verified;** https://www.bbc.co.uk/writers/documents/bbcradioscene.pdf**):**
  - Names are in CAPS in a left column, with the speech hanging beside them.
  - **Sound and music in CAPITALS UNDERLINED**, set apart from dialogue. Dialogue continues after a cue without repeating the name.
  - A speech is split across pages only after a sentence, with at least two lines before the break, and the next page starts "NAME (CONT'D):".
  - Mic terms: (OFF), (V.O.), (D) for distort, (LOW), (CLOSE).
  - The cue style (https://www.bbc.co.uk/writers/documents/bbcradiocue.pdf, verified) labels cues F/X: and GRAMS: in bold caps.
- **Screenplay / Fountain (verified,** https://fountain.io/syntax**):** the character is an uppercase line, and a parenthetical sits on its own line. Final Draft's MORE / CONT'D on page breaks is secondhand: its help page returned 403.
- **Standard Ebooks manual 7.6 (verified,** https://standardebooks.org/manual/latest/7-high-level-structural-patterns**):**
  - The persona sits in a **right-aligned column, about 20% wide**, beside the speech.
  - **Below 400 px the persona stacks above the speech with `break-after: avoid`.**
  - Stage directions are italic, with **upright parentheses added by CSS**. Names in directions are marked as personae.
  - Dramatis personae is a list.
  - Verse is one span per line.
  - From the complex-drama how-to (verified, https://standardebooks.org/contribute/how-tos/how-to-conquer-complex-drama-formatting): stichomythia gets no extra indents.
- **Project Gutenberg HTML (verified, #844):** the name in caps above the speech, and directions in square brackets inline. It has no semantic markup.
- **LibriVox dramatic readings (verified,** https://wiki.librivox.org/index.php/Information_on_coordinating_dramatic_readings**):** each reader gets a part, the cast is listed first, and stage directions may be left out or read by a narrator.
- **Actor apps:**
  - Scriptation Actor Highlight (verified, https://scriptation.com/features/actor-highlight) gives one color per character and keeps highlights apart from the actor's own notes.
  - Scriptation Reader Mode (verified, https://scriptation.com/features/reader-mode) reflows the script and lets the reader show or hide element types.
  - Run Lines (verified, https://apps.apple.com/hn/app/run-lines-script-rehearsal/id6755323192) offers Show All, Hide My Lines and First Letter modes.
- **Accessibility:**
  - DPUB-ARIA has no drama roles (verified, https://www.w3.org/TR/dpub-aria-1.1/). Drama semantics live in DAISY Z39.98 (persona, stage-direction, verse), which is known here only through Standard Ebooks, since its vocabulary page returned 404.
  - Nothing found says how VoiceOver reads a table-based play. Our inference is that a heading-free block per speech, with the name as the first text, reads in the right order and is calmer than a table.
- **Readability:**
  - Butterick: 45 to 90 characters a line (verified, https://practicaltypography.com/line-length.html). Use real small caps sparingly, and never scaled capitals (https://practicaltypography.com/small-caps.html).
  - Baymard: 50 to 75 characters, about 34 em (verified, https://baymard.com/blog/line-length-readability).
  - NN/g (Moran 2016, verified, https://www.nngroup.com/articles/mobile-content/): comprehension is the same on a phone, but reading difficult text is slower there. That argues for removing the work of finding the speaker, not for shrinking anything.

**What the sources agree on.**
- Names look unlike speech: caps, set apart, one form per character.
- Names go above the speech on narrow pages, and in a hanging column beside it on wide pages.
- Directions are italic and in parentheses, offset from dialogue, with the names inside them marked.
- Radio cues get a heavier style of their own.
- A speech is never orphaned from its name, and a speech continued onto the next page is labeled.
- Verse keeps its lines, with a turnover indent.
- The cast comes first.
- An act opens a page.

## 3. The design: the Ear Drama page

The medium is the ear, and the people using it are casting and performing. So the page answers,
in this order: *who speaks, what they say, what is heard, what is done.* Everything below stays
within direction D and the six type levels (L1 page title, L2 section header, L3 body strong, L4
body, L5 caption, L6 tabular). All of it is in `ReaderCore.layoutOf` (no DOM, tested) and
`js/reader.js` / `css/styles.css`.

1. **Speaker over speech on a phone, in a gutter when the page is wide.**
   - The name is L3 (body strong) in the part's hue, uppercase as printed, on its own line over the words (L4).
   - When a page holds **30 em or more** (`ReaderCore.GUTTER_MIN_EM`: tablets, desktop, each of two facing pages at 1440), the name moves into a **right-aligned 8.5 em gutter** beside the words, as in the BBC and Standard Ebooks. Long names wrap inside the gutter.
   - The name never ends a page (`break-after: avoid`). Prose keeps at least two lines at either side of a break, and verse at least two rows.
2. **Verse keeps its lines** (`ReaderCore.isVerse`).
   - A speech is verse when every row after a printed break begins with a capital and its rows are not mostly as long as a transcriber's wrapped line (60 characters and more).
   - Verse draws one row per printed line, with a 1.5 em turnover indent on the phone. A printed line that was indented (a shared half-line, when the source kept the indent) is drawn indented.
   - Prose reflows: its breaks are drawn as the spaces they stand for.
3. **A direction inside a speech is italic, muted, in upright parentheses** (added by CSS, so the printed words and their offsets are untouched). A direction printed wholly in italics stays italic.
4. **A stage direction is a quieter paragraph.**
   - It is italic and muted, indented 1.5 em; in gutter mode it sits in the text column.
   - Its enclosing brackets are not drawn: the page already sets it apart.
   - **A part it names in capitals is drawn in that part's hue**, upright and strong. An entrance shows who comes on in the color you will see their speeches in.
5. **The sound lane** (radio, and any cue).
   - A sound piece, or an aside whose words begin "sound of", "noise of" or "music", is its own row: a speaker glyph, then the cue as an L5 caption in capitals on a quiet block (surface-alt).
   - Within a speech, the words continue after it without repeating the name (BBC scene style). The cue is heard in the speech's time, so it sits inside the speech.
6. **"(cont'd)" running head.** When a page opens inside a speech, the space above the page names its speaker in the hue, followed by "(cont'd)" (L5). This covers French's "(Cont.)", the BBC's CONT'D and Final Draft's continueds. There is one head per facing page, none in Scroll.
7. **The front of the play.** Page one is the title (L1), the authors (L4, muted), and **Parts** (L5) followed by every speaking part in its hue, largest first: the dramatis personae, and the key to the colors.
8. **Acts open a page** (L1, `break-before: column` in Pages); scenes are L2. Nothing else changes size.
9. **I'm playing.**
   - My speeches are tinted in my hue, with a 3 px rule outside the text. The tint is painted inside a 14 px inner margin of the page, so it is never clipped.
   - **The cue I come in on is underlined in my hue**: the last sentence of the speech before each of mine (`ReaderCore.cueTail`), as actors mark it.
   - Hide my lines bars only my *said* words. Names, directions and cues stay showing.
   - A speech another speaker's words ran into is still theirs on the page (D1).
10. **Built for marks and the read-along.**
    - Every drawn run keeps its offset into `lineText`, including the run-in speaker's printed name. A character the page leaves out (a label's period, a bracket) is simply not drawn.
    - The line element (`id`, `data-line`) is unchanged, so `go`, `follow` and the studio dock work as before.
    - The read-along tint (`rd-now`) is drawn behind each speech block.

What was considered and left out:
- **A live "who's on stage" strip**: the data has no reliable entrances or exits (directions are free text), so it would guess.
- **Speech numbers** (the BBC's "cue 5, page 19"): a recording feature for the studio (S3), not typography.
- **Small caps for names**: Public Sans has no true small caps, and Butterick rules out scaled capitals.
- **A centered layout** (French): it costs measure on a phone, and our display type is left-set.

## 4. Data problems (for the parser; exact examples)

The page works around D1, D2 and D6 for display only. Casting, recording, the voices and
`lineIndexesOf` still read the parser's lines, so every item below needs a fix in
`catalog/tools/script_parse.py`.

- **D1. Speeches run together** (Shaw style, `NAME (direction). Words`):
  - gut-5071 L0009 says `"Of course. Why not?\nGRACE"`, then `{direction: "reflecting"}`, then `{say: ". Never mind why. …\nCHARTERIS"}`. These are three speeches, stored as one CHARTERIS line.
  - Measured across 552 of the 730 library scripts: **7,630 run-in speeches in 151 scripts** (gut-3612 has 407, gut-2175 has 388, gut-5071 has 298).
  - Fix: split at `\nROLE` followed by end of piece or `. `/`: `, where ROLE is a known role.
- **D2. Emphasis typed as a direction:**
  - gut-5071 L0010 is `"It is the first in which"` + `{direction: "I"}` + `"have been serious."`.
  - gut-844 L0013 is `"I believe it"` + `{direction: "is"}` + `"a very pleasant state"`.
  - gut-5071 L0020 is `"Oh, yes:"` + `{direction: "I"}` + `"broke it off,"`.
  - The voices skip these words. The page draws a short italic piece between lowercase said words as said.
- **D3. Spoken words typed as `mic`** (stage plays): `{mic: "in breefe"}` and `{mic: "in which, beyond all expectation, You are invited to your good"}` in the bundle's stage texts. They are spoken words lost to the voices. `mic` should apply to radio scripts only.
- **D4. A verse parenthesis typed as a direction:** gut-1533 L0019, `{direction: "Worthy to be a rebel, for to that\nThe multiplying villainies of nature\nDo swarm upon him"}`, which the Captain speaks.
- **D5. Folio texts lost their verse lines and keep abbreviated speakers:**
  - gut-2265 *Hamlet* has no line breaks, with roles BARN/BAR and HOR/HORA as separate parts. L0018 carries a second speaker inline: `"… Fra. Barnardo ha's my place"`.
  - gut-1113 *A Midsummer Night's Dream* has `"… giue soueraignty The. Take time to pause"`, which is "Thes." read as words.
  - The dedupe kept these over modern editions (gut-1524 *Hamlet*, gut-1514 *MND*: "kept the bundled play", "kept the fuller cast"). Recommendation: prefer the edition whose verse keeps its lines and whose speakers are full names.
- **D6. Sound cues typed as directions in radio scripts:** gut-28051 L0006, `{direction: "sound of gavel"}`, next to L0020, `{sound: "sound of gavel"}`. The page draws both in the sound lane.
- **D7. A role artifact:** gut-5071 lists **GRAVEN** beside CRAVEN (a typo in the source, now a part of its own).
- **D9. A half-stripped parenthesis:** gut-49295 (*After Taps*) has an aside whose opening "(" the
  parser dropped while keeping the closing ")" ("Exeunt, R., _POLLY_ and _BIJAH_.)"). The page
  adds no parenthesis where one is printed, so it reads "(Exeunt, R., POLLY and BIJAH.)".
- **D8. Directions holding verse:** gut-10523 L0288, `"[ADMETUS _looks and stands amazed_.]\n    Go, and forget in bliss\nThy sorrow!"`.

## 5. Frames read

These frames are all read, before and after. stage, verse and radio are shot at 320, 375, 430 and 1440, light and dark, 48 in all:
`img/play-typography/before/{stage,verse,radio}-{light,dark}-{320,375,430,1440}.png` and
`img/play-typography/after/…` with the same names. Further after frames:
- `after/stage-mine-light-1440.png`: I'm playing GRACE, with the cue underlines and the gutter.
- `after/hide-dark-375.png`: Hide my lines as MACBETH, with the cue underlined.
- `after/earnest-light-1440.png`: brackets, directions, and parts named in directions.
- `after/folio-light-375.png`: the Folio *Hamlet*. It is still prose, which is D5.

## 6. Open questions

None the rules leave open. The gutter threshold, the "(cont'd)" head and the sound lane follow from
§2's consensus. D5 (which Hamlet is the default) is a dedupe rule for the catalog, not an owner
call: prefer the edition with full speaker names and verse lines.
