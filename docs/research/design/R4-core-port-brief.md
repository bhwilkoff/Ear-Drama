# R4 core port brief: own scripts in Swift and Kotlin (batch R4-1)

The web's core is `js/own-core.js` (2026-11-24, R4-1 of `R4-record-anything.md`, Decision 088.3). This
is the spec for `apple/Core/Plays/OwnScript.swift` and `android/.../plays/OwnScript.kt`. Core only: no
screen, no storage, no network, no audio. Where this page and R4 differ, §6 says why.

**A port is done when** its test runs every case of the three golden files, finds each file's
`control` wrong, and reads 400 KB in under 100 ms on a Mac or a development JVM:

| File in `catalog/tests/golden/` | Sections |
|---|---|
| `own_script_parse.json` | `normalize`, `names`, `pieces`, `cases` (59 pasted texts, 8 layouts), `control` |
| `own_script_ops.json` | `sequences` (20), `cut`, `wordsChanged`, `nearest`, `letters`, `canonical`, `scripts`, `refusals`, `control` |
| `ear_cast_lines.json` | `vtt`, `lines`, `cues`, `sentences`, `times`, `lineAt`, `casts` (13), `script`, `control` |

`js/own-core.test.js` shows how each section is run. Everything outside ASCII in the files is
`\u`-escaped, so no editor can normalize a case away. Never edit a `want` by hand: change the rule in
`js/own-core.js`, all three ports, and the golden in one change set.

## 1. Functions

Same names. `doc` is immutable: `apply` returns a new one.

| Function | Does |
|---|---|
| `normalize(raw)` | the text every rule reads: §2 |
| `textRefusal(raw)` | `empty`, `too_long`, or none; asked before `parse` |
| `partName(raw)`, `partNameRefusal(name)` | a part's stored name; `empty`, `too_long` (over 40 UTF-16 units), `bad_name` |
| `labels(row)` | every way a row opens with a name: `{ form, name, key, label, text, bare }` |
| `cueKind(row)`, `isHeading(row)`, `isEntrance(row)` | rules 1, 2, and a printed entrance |
| `parse(raw)` | `{ text, lines, parts }` |
| `pieces(text)`, `textOf(parts)` | a speech's text to `say` and `direction` parts, and back |
| `cutAt(text, at)` | where a split goes, or -1 |
| `newDoc(lines)`, `apply(doc, op, env)`, `done(doc, keepOpen)`, `kept(doc)` | the parts page: assign, split, join, words, leaveOut, add, rename, notPart, undo |
| `nearestParts(lines, i)` | the two one-tap answers |
| `wordsChanged(before, after)` | the take list's **Words changed** |
| `toScript(doc, meta)`, `rolesOf`, `fromScript(script)` | the castable shape; a doc over a script (Edit a copy) |
| `canonicalLines(lines)`, `revisionOf(lines)`, `seal(script)` | the hashed bytes, the revision |
| `refusalOf(script)` | may it be kept and shared |
| `parseCues(raw)`, `sentenceCuts(text)`, `fromCues(cues)` | a transcript to lines with times |
| `lineAt(doc, ms)`, `hear`, `tap`, `leaveOutHeard`, `castOf`, `castCount`, `settle` | cast by ear |

`op` and `refusal` are strings in JSON; use an enum with raw values. `castOf` answers a name, OUT, or
nothing: an enum (`JS` uses a Symbol). **A script on its own device is kept as its doc** (`kept(doc)`,
plain JSON) beside `script.json`, because marks, labels, heard lines and letters are not in the
castable shape; `fromScript` is only for copying a script that arrived without one.

## 2. Characters and units

- **Offsets are UTF-16 code units** of a line's `text` (a mark's unit). Kotlin: `String` indexes.
  Swift: work in `[UInt16]` (`Array(s.utf16)`), never `Character` or `String.Index` arithmetic.
- **A name's length cap while reading is 30 code points; a part's stored name 40 UTF-16 units; caps in
  bytes are UTF-8** (400,000 for a text and for the canonical lines; 6,000 lines).
- `normalize`, in this order: CRLF, CR, VT, FF, U+0085, U+2028, U+2029 to `\n`; U+00A0, U+1680,
  U+2000-200A, U+202F, U+205F, U+3000 to a space (tab stays); dropped: U+0000-0008, U+000E-001F,
  U+007F-009F (but U+0085), U+00AD, U+200B, U+200E-200F, U+202A-202E, U+2060, U+2066-2069, U+FEFF;
  a lone surrogate to U+FFFD; **NFC**; then `_` alone between anything but two ASCII letters or digits
  is dropped, and `**`. ZWJ and ZWNJ stay. Quotes and dashes are never changed.
- `trim` and `wordsOf` know **space, tab and `\n` only**. Never `trimmingCharacters(in: .whitespaces)`,
  `trim()`, or `\s`.

## 3. The exact patterns

No regular expression decides a rule (R4's risk 5). These single-code-point classes are all there is:

| Class | JS | Swift (`Unicode.Scalar.Properties.generalCategory`) | Kotlin (`Character.getType(codePoint)`) |
|---|---|---|---|
| UPPER | `[\p{Lu}\p{Lt}]` | `.uppercaseLetter, .titlecaseLetter` | `UPPERCASE_LETTER, TITLECASE_LETTER` |
| LOWER | `\p{Ll}` | `.lowercaseLetter` | `LOWERCASE_LETTER` |
| LETTER | `\p{L}` | the five letter categories | `Character.isLetter(cp)` |
| MARK | `\p{M}` | `.nonspacingMark, .spacingMark, .enclosingMark` | the three mark types |
| DIGIT | `\p{Nd}` | `.decimalNumber` | `DECIMAL_DIGIT_NUMBER` |

Ids: `^own-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`, `^L[0-9]{4}[a-z]*$` (match the
whole string: in Kotlin and ICU `$` also matches before a final line break, so use `matches()`).
A name's characters: LETTER, MARK, DIGIT, `. ' ’ ‘ & # - /`, space, U+FFFD. Word sets (NOT_NAME,
COMMON, COMMON_MIXED, TITLES, SMALL, WORD_NUMBERS, HEADS, CUE_*, ABBREVIATIONS): copy them from the
file. ASCII case folding (`asciiUpper`) for cues and headings, never a locale's.

## 4. `parse`, in order

1. Normalize, split on `\n`, trim each row.
2. For each row that is not blank, a cue, or a heading, `labels(row)`; count its **first** label's key:
   `mixed` in `starting`, others in `seen` (an `alone` only when one of the next two rows is not blank).
   Count `colon`, `dot` and `alone` keys apart too: a form with two names printed twice is *established*.
3. A label is a part when: printed twice (not `mixed`); `mixed`, at five row starts (or twice in other
   forms, opening a paragraph); or **once** in an established form: `dot` opening a paragraph with a
   small letter after it; `alone` opening a paragraph over a row with a small letter; `colon` in
   capitals opening a paragraph or under a cue or colon row; `colon` with a titled name of one or two
   words opening a paragraph.
4. Row by row: cue; heading; label (but not a lower-case one right under a name standing alone); a name
   still waiting takes the row; a bracket opening a paragraph (to the row it closes on; unclosed `[` is
   a direction, unclosed `(` is No part); an entrance opening a paragraph; a lone Exit inside a speech
   (the rows after it, with no blank, are that part's next line); a row with no blank above goes on;
   anything else is No part.
5. A speech with no words goes back as printed, No part.

In `labels`, the shortest name that fits a form stands; a name that so far is a title (`MRS.`) or one
letter (`J.`) is only *held*, the **longest** held used when no form was found outright. Order: found
colon, dot, gap, alone, mixed, then held in the same order.

## 5. Traps

- **Swift `==` on strings is canonical equivalence**: an un-normalized `é` equals a normalized one and
  the NFC goldens pass with no NFC. Compare `Array(a.utf16)`.
- Swift treats `"\r\n"` as one `Character`, and a flag or family as one; iterate UTF-16 or scalars.
- Swift: `precomposedStringWithCanonicalMapping`. Kotlin: `Normalizer.normalize(s, NFC)`.
- Uppercase with no locale: `uppercased()`, `uppercase(Locale.ROOT)` (Turkish `i`). `ß` becomes `SS` in
  all three, so a name can grow: the 40 cap is checked after.
- The JVM's `\s`, `\w`, `\b` are ASCII and Android's are ICU's: the same Kotlin test passes on one and
  fails on the other. Hence no such class anywhere.
- **Canonical JSON by hand.** Swift's `JSONEncoder` escapes `/` unless told not to, and neither it nor
  kotlinx sorts as needed for every field. Escape only `"`, `\`, `\n \r \t \b \f`, and other controls
  under U+0020 as lower-case `\u00xx`. U+007F, U+2028 and emoji go raw, as UTF-8. Hash with `SHA256`
  (CryptoKit) and `MessageDigest`; hex is lower case; Kotlin bytes are signed (`and 0xFF`).
- **Letters are per numbered line** (`L0009`): splitting `L0009a` gives `L0009b`, never `L0009aa`; after
  `z` comes `aa`. Undo gives no letter, key, or heard line back.
- `done` empties undo: an id is given once.
- Times are whole milliseconds: `start + floor((end - start) * at / length)`. Use `Int64`/`Long` and
  integer division; `length` is the cue's UTF-16 length, not the piece's.
- `pieces`: match brackets in **one pass with two stacks**. Looking for a partner from every `(` is
  quadratic on a hostile paste. The same in `bracketRows`, which reads a paragraph once.
- Build a speech's rows in a list and join at the end: appending to a `String` per row is quadratic in
  Swift and Kotlin (JavaScript's ropes hide it).
- `labels` tries an end only where `couldEnd`: without it, 400 KB takes three times as long.
- Cap before parsing: `ACTION_SEND` and a document open reach the inbox with any size (R4-7).
- Keep `doc.undo` as references to the earlier `lines` arrays (copy on write), not deep copies.
- Swift: these types are `nonisolated` and `Sendable`; parse off the main actor.

## 6. Where the core differs from R4, and why

Measured on R4's own sample (140 radio scripts; 64 Gutenberg plays the pipeline now reads clean) and on
a second, unseen one (144; 81). R4's prototype on the same texts, then the core, median and worst tenth:

| | Prototype | Core |
|---|---|---|
| Radio | 96.1 / 87.8 | **98.5 / 90.5** |
| Stage | 94.8 / 67.9 | **97.2 / 83.1** |
| Radio, unseen | 96.8 / 87.7 | **98.6 / 90.4** |
| Stage, unseen | 93.8 / 65.9 | **97.9 / 77.0** |

1. **A name printed once** is a part when two others are established in the same form (R4: twice or
   more). One-line parts are in nearly every script, and a missed one read its label aloud.
2. **`Name.`** counts at row starts, not only paragraph starts (the Folio prints no blank rows).
3. Titles and initials belong to a name; `YES.`, `NO.` and kin are never parts but before a colon.
4. A direction may stand between a name and its words with no period (`HODGE [hesitating] Is it`).
5. Entrances and exits that open a paragraph are directions; a bracket may run over rows.
6. A row under a cue or a direction, with no blank, is more of it (R4 said so of a speech only).
7. `**bold**` marks are dropped as `_italic_` marks are (a .md file, a page copied from the web).
8. Added: `notPart` (a name read by mistake gives its printed label back to the words; without it a
   word is lost, and R4 says none is), `add`, and `part_has_take` (renaming a part whose line has a
   take would orphan the production's part, so it is refused).
9. Letters follow the numbered line (§5). `kind` is `"own"`: R4 named no value, and `radio` or `stage`
   would be a claim; the kicker seams (`js/plays-ui.js` `kindOf`, `PlaysScreens.kt`,
   `SurpriseScreen.kt`) read anything else as one of the two and need a case in R4-2, 6 and 7.
10. A part's name is capped at 40, the Worker's `MAX_NAME`. R4-4 must **not** put the title through
    that cap: titles here run to 300, as the manifest's do.
11. 400 KB is 400,000 bytes.

Still No part, on purpose: the second paragraph of a speech (rule 10; most of what is left), a label
that is only digits, `NAME, doing this, "words"`, and abbreviations of one name (`TI.`, `TIT.`), which
one **Join to** fixes.
