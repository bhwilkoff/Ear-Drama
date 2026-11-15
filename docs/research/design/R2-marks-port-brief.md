# R2 marks port brief: marks in the reader on Apple and Android (Decision 076, S5)

The web shipped marks first (2026-11-15). This brief is the spec for the Apple (iOS, iPadOS, the
iPhone Duo, macOS) and Android ports. It binds nothing new: the rules are PLAYS-DESIGN §2.10 (the
verbs) and each platform's design doc (iOS-DESIGN §4.15 "Marks", macOS-DESIGN §4.7, ANDROID-DESIGN
§4.17 "Marks"; tvOS-DESIGN §4.13 says the TV has none). Where this brief and a design doc differ,
the doc wins; fix the doc first.

The owner, 2026-11-14: *"You should be able to read a script and turn pages and mark them up and do
all of the things that a good book/script reading experience should contain."* Rulings (Decision
076): typed marks everywhere, plus Apple Pencil ink on iPad; anchored to lines; on the device first,
synced later; private.

**Before you start.** The reader (S1) is on both stacks (`ScriptReaderView`, `ReaderScreen`), with
the Ear Drama page's `layoutOf` ported (`PlayPage.swift`, `PlayPage.kt`), each drawn piece mapped
back to its offset in `lineText`. Marks need exactly that mapping, both ways. Real devices only
(iPhone 12, iPad with an Apple Pencil, the Duo closed and open, a Mac window; Pixel 8a); never a
simulator or emulator. Press the keys yourself; draw the ink yourself on the iPad.

**The web reference** (port behavior, not idiom):
- `js/marks-core.js`: the whole model, no DOM. Port it to Core (`MarksCore.swift`) and to
  `plays/MarksCore.kt` as plain types and functions with the same names.
- `catalog/tests/golden/marks_anchor.json`: the golden cases every stack runs (`snap`, `point`,
  `anchor`). A port is not done until its test runs every case.
- `js/marks.test.js`: every case in §4, the mutants it was seen to fail against.
- `js/marks.js` (the bar, drawing, the notebook) and `tools/web_fit_marks.py` (the frames and the
  gate): what to see on screen.
- The tokens: `color.mark` in `design-tokens.json`, already generated: `Color.markYellow` …
  `Color.mark(_:)` (Apple `Design.swift`), `MarkYellowLight/Dark` … `markColor(key, dark)` (Compose
  `Color.kt`), `mark_*` (Android resources). Never a hard-coded hue.

---

## 1. Core (both stacks)

1. **The mark** (`Mark`, `Codable` / `@Serializable`, the web's JSON keys exactly, so an export
   reads the same and a later sync needs no mapping):
   `id, kind, line, start, end, text, prefix, suffix, revision, created, updated` and, by kind,
   `hue` (highlight: `yellow|green|blue|pink`), `label` (beat, at most 24 characters), `note`
   (note), `group` (highlights or underlines from one selection across lines). `kind` is one of
   `highlight, underline, breath, pause, beat, note`. Offsets are UTF-16 code units into
   `lineText` on every stack (the web's string indexes): Swift must convert with
   `String.Index(utf16Offset:in:)`, never `Character` counts, or a curly quote or a dash shifts
   every mark after it. Kotlin `String` is UTF-16 already. Times are epoch milliseconds.
2. **`snapWords(text, start, end)`**: trim space; grow to whole words; null when only space. A word
   character is a letter, digit, `'`, `’`, `-` or `_` (the printed italic marks).
3. **`pointAfter(text, end)`**: back over trailing space, on to the end of the word, then over
   punctuation that follows; that is where a breath, pause or beat stands.
4. **`make(script, lineID, start, end, kind, extra, now)`** and **`fromSelection(script, pieces,
   kind, extra, now)`**: pieces are the selection per line in reading order; span kinds snap each
   piece (a note only its first); a selection over more than one line gives highlights or
   underlines a shared `group`; point kinds take the last piece's `pointAfter`. `prefix` and
   `suffix` are up to 32 characters either side, read from the line as it is.
5. **`add(script, marks, mark)`**: highlights (and underlines) that overlap **or touch** in the same
   line merge into one over all their words, taking the new mark's id, hue and group, the quote
   re-read; notes never merge; a point mark replaces any point mark at its line and offset.
   **`remove(marks, id)`** removes the mark and its group and returns what went (for Undo).
   **`update(marks, id, patch)`**: a hue applies to the whole group; a label or note to the mark.
6. **`place(script, marks) -> (placed, lost, changed)`**, the re-anchoring (PLAYS-DESIGN §2.10
   rule 4), step for step as `js/marks-core.js`:
   1. same revision (non-null) and the slice still reads `text`: as stored;
   2. else in the same line id, `bestIn` (every occurrence of `text`; for a point mark the places
      where the last 16 characters of `prefix` end or the first 16 of `suffix` begin), scored by
      `commonTail(prefix, before) + commonHead(suffix, after)`, ties to the nearest old offset;
      a point mark needs a score of `min(8, prefix + suffix length)`;
   3. else every other line, best score, ties to the nearest line by script order (where the old
      id sorts, by plain string order, so `L0009a` follows `L0009`), then the nearest offset;
      accepted only when `text.length + score >= min(16, text.length + prefix + suffix length)`
      and, for a point mark, the score is above zero;
   4. else lost: returned exactly as stored.
   `changed` is true when any placed mark moved or took the new revision; then save.
7. **`order(script, marks)`** (line index, start, end, kind order) and **`at(marks, line, offset)`**
   (span marks under an offset, narrowest first, a note before an equal underline): the notebook
   and a tap.
8. **Storage**, keyed by script id, the web's shape `{format: 1, script, title, marks: [...]}`:
   - Apple: `Application Support/Marks/<script id>.json` through `PlayFiles`-style atomic writes;
     never `UserDefaults` (it would grow without bound), never iCloud until the sync phase (tvOS
     never reads it). The prefs (`show`, last `hue`) in `UserDefaults` `ed.marks.prefs`.
   - Android: Room, a `MarkEntity` table (`scriptId`, `id` primary key, the fields above, plus the
     play `title`), a DAO with `marksFor(scriptId)`, `replaceAll(scriptId, marks)`, `all()` for
     the export; the prefs in `SharedPreferences` `ed.marks.prefs` (as `ReaderStore` keeps the
     reader's). Excluded from Auto Backup's cloud rules until the sync phase.
   - A failed write is surfaced (§2.6), never swallowed.
9. **Export**: `DataExport` adds `marks[]`, one row a mark: `script, title, revision, line, start,
   end, kind, text, hue, label, note, created, updated` (ISO 8601 times, `null` for an absent
   field), sorted by script id. Update `DataExportTests` / `DataExportTest` and docs/EXPORT.md's
   "Web since" line.

## 2. The reader (both stacks)

1. **Selecting** maps the system's own selection to pieces `(line id, start, end)` through each
   drawn run's offset (the S1 work kept them): a selection starting on a speaker's name, an added
   parenthesis, "(cont'd)" or a mark's own glyph starts at the next drawn word.
2. **The mark bar is the system's edit menu**, not a custom toolbar: iOS `UIEditMenuInteraction`
   (Books' own place), Android's floating `TextToolbar`, the Mac's context menu plus a **Marks**
   menu. Six actions in this order: Highlight (last hue), Underline, Breath, Pause, Beat, Note.
   Beat and Note open a sheet with the marked words (a point mark's words around it) above a field;
   Save is disabled for an empty note.
3. **A tap or click on a mark** opens it: the four hues and Delete (highlight), Delete (underline,
   breath, pause), Edit and Delete (beat, note). Delete is undoable (Apple `UndoManager`, Android
   `Snackbar` with Undo). A tap elsewhere keeps the reader's behavior (turn on the outer fifth,
   peek a hidden line, make my line current in the studio).
4. **Drawing never changes the text**: highlights a fill behind the run boxes; underline a 2 pt/dp
   ink rule; a note's words under a dotted rule with a note glyph after; breath `/`, pause `//`
   and beat `//` plus its label (caption capitals in an outline) drawn in the gap after the word.
   On Apple draw them in the Core Text page's own drawing pass (or as `CALayer`s placed from the
   line fragment rects); on Android in `drawBehind` / `drawWithContent` from the
   `TextLayoutResult`. A point mark re-paginates (it takes room); a span mark does not. The
   position is kept as the first line that starts on the page.
5. **Show marks** (in the notebook) hides every mark; making a mark shows them again.
6. **The notebook**: Marks in the reader's toolbar (`bookmark` / Material `bookmark`), a sheet (a
   Mac sidebar section) with the Show marks switch, every mark in script order, a tap closing it
   and going to the line with the reader's outline flash; Not placed after, each deletable.
   Empty: "Select words on the page to mark them."
7. **Hide my lines** hides a hidden line's marks; a peek shows them.
8. **In the studio** (S3) marks draw on every line; a tap on a mark opens it and never changes the
   current line; the studio's keys are unchanged.
9. **Keys** with a selection: iPad and Android H, U, /, P, B, N, Esc; Mac ⌘⇧H, ⌘U, ⌘/, ⌘⇧/,
   ⌘⇧B, ⌘⇧N, ⌘⇧M (menu items; a Mac document window takes no bare letters).
10. **Accessibility**: each mark is a custom accessibility action on its speech (VoiceOver,
    TalkBack: "Highlight: first thing"); point marks are announced in reading order; the notebook
    is the complete list.

## 3. Pencil ink (iPad only)

1. **Ink** in the reader's toolbar (`pencil.tip`, a `Toggle`): one `PKCanvasView` per line block
   on the page, sized to the block, `drawingPolicy = .pencilOnly` (a finger turns pages and
   selects), `PKToolPicker` shown while Ink is on.
2. Each line's `PKDrawing` is stored beside the marks, `Marks/<script id>-ink/<line id>.drawing`,
   with the line's `lineText` hash and the text size it was drawn at; drawn scaled by the size
   ratio, so ink moves with its line on reflow, a new size and a page turn.
3. A revision: the drawing stays when the line's text hash is unchanged (it may move to a split
   id when exactly its text moved there); otherwise it is listed under Not placed (a thumbnail)
   and never drawn over other words.
4. iPhone and Mac draw the ink read-only at the same anchor; Android draws none until its Ink API
   phase (PARITY ⏳); the web draws none (no ink on the web, PLAYS-DESIGN §2.10 rule 1).
5. Scribble writes into the note field (the system's; nothing to build).

## 4. Tests (mirror `js/marks.test.js`; see each fail before it passes)

1. The golden file: `snap`, `point`, `anchor` (same revision; words added before; a split id
   L0009 to L0009a; the same word twice kept by context; words gone, lost; a breath by context; one
   short word elsewhere, lost; a vanished id, the nearest line; the nearer of two lines).
2. Offsets: every drawn run of every bundled script maps back into `lineText` (the stack's own
   `layoutOf`), with verse (an indented half-line), emphasis (`em`, a short italic direction) and
   a run-in speaker. Mutant: drop the verse row's lead-space adjustment; the case fails.
3. A selection: words grown; a breath after "morning,"; one mark per line with one group; a note on
   its first line only; a beat label cut to 24; space alone, nothing.
4. Overlap: merge on overlap and on touch (mutant `<` for `<=` fails); a highlight and an underline
   share words; two notes stay two; another line never merges; a point mark replaces a point mark.
5. Remove and update: a group goes together (mutant: ignore the group fails); a hue for the group.
6. Order and lost: script order; a revision that drops lines keeps their marks as lost; placing
   again changes nothing.
7. A real script: marks across many lines survive a new revision with the same text; a split line
   carries its mark to the `a` id.
8. Storage: per script, unreadable reads as none, an unknown kind dropped, a failed write reported;
   the export rows.

## 5. Frames and the gate

Shoot what `tools/web_fit_marks.py` shoots, on devices, light and dark: a stage play (The
Philanderer at L0009), a verse play (Macbeth at L0015) and a radio play (Caesar Rodney's Ride at
L0020): the edit menu on a selection, a page with all six marks, a highlight opened (four hues),
the notebook, larger text (the marks on their words), and the studio attached with a highlight and
a breath on the current line. iPad: ink on two lines, then a text size change (the ink follows),
then a page turn and back. READ every frame before reporting.

## 6. PARITY.md

Rows "Marks in the reader" and "Pencil ink anchored to lines": Apple and Android cells move from ⏳
to 🚧 with what was seen on which device; tvOS stays n/a (tvOS-DESIGN §4.13). The export row's
note names `marks[]` once the stack exports it.
