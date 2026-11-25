# Export

Human-Shaped principle 11: a person can take their own data with them. Ear
Drama builds the files on the device and hands them to the platform's own
share or save sheet. Nothing is uploaded, and no account is needed.

| Platform | Where | How |
|---|---|---|
| Web | Library, the "Export my data" and "Export history (CSV)" buttons | `js/export.js`; the browser's download |
| iOS, iPadOS, macOS | Library, Account, "Export my data" and "Export history (CSV)" | `apple/Core/Account/DataExport.swift`, `apple/Shared/ExportViews.swift`; `ShareLink` of a temporary file |
| Android | Library, "Export my data" | `android/.../data/DataExport.kt`, `ui/ExportRow.kt`; the system's save sheet (`CreateDocument`) |
| Apple TV | n/a | the TV has no share or save sheet; the same data is one tap away on a phone |

## The JSON file

`ear-drama-YYYY-MM-DD.json`, the same keys on every platform (`format` 1):

- `app`, `format`, `exportedAt` (ISO 8601)
- `history[]`: `episode`, `title`, `seriesName`, `airDate`, `listenedAt`, `positionSeconds`, `durationSeconds`
- `following[]`: `series`, `name`
- `queue[]`: `position`, `episode`, `title`, `seriesName`, `airDate`
- `takes[]`: `production`, `title`, `created`, and `takes[]` with `id`, `lineID`, `created`, `chosen` (plus `part` and `seconds` on the apps). The recordings' audio is not in the file; it stays in the app.
- `marks[]` (PLAYS-DESIGN §2.10, Decision 076 S5): every script mark on the device, one row a mark: `script`, `title`, `revision`, `line`, `start`, `end` (offsets into the line's printed words), `kind` (`highlight`, `underline`, `breath`, `pause`, `beat`, `note`), `text` (the marked words; empty for a point mark), `hue` (a highlight's), `label` (a beat's), `note` (a note's), `created`, `updated`. Web, iOS, iPadOS, macOS (`MarkStore.exportRows`, `DataExport.marks`) and Android since 2026-11-15. A mark a revision could not place is exported as stored.

- `ink[]` (PLAYS-DESIGN §2.10 rule 1, iPad Pencil ink): one row a line that has ink: `script`, `title`, `revision`, `line`, `strokes` (the count), `width` (the text column's width in points the strokes' units are measured in) and `drawing` (the line's `PKDrawing` data, base64: the whole ink, so nothing is lost and it can be read back). Chosen over a bare count so an export is a complete copy of the person's own work; the data is in the line block's coordinates, so it does not depend on a page. iOS, iPadOS and macOS (`InkStore.exportRows`, `DataExport.ink`); the web and Android hold no ink and omit the key. Ink a revision could not place is exported as stored.

- `scripts[]` (PLAYS-DESIGN §13, Decision 088.3): the scripts the person added, the last one changed first: `id`, `title`, `source` (`Added by you`), `created`, `done`, and `lines[]` in the castable shape (`id`, `kind`, `role` and `parts` for a speech, `source` for the rest); a script not yet Done has no line ids, and a line with no part has `kind` `open`. The web since 2026-11-24 (`OwnScripts.exportRows`); Apple and Android with R4-6 and R4-7.

A field the device does not know is `null`, never invented. An empty library
exports empty lists, not an error.

## The CSV file

`ear-drama-history-YYYY-MM-DD.csv`, one row a listened episode, newest first:
`episode,title,seriesName,airDate,listenedAt,positionSeconds,durationSeconds`.
Cells with a comma, quote or line break are quoted, quotes doubled; lines end
`\r\n`.

## Checks

`js/export.test.js`, `apple/Tests/DataExportTests.swift`, `apple/Tests/InkTests.swift`,
`android/.../data/DataExportTest.kt`, `android/.../plays/MarksCoreTest.kt`.
