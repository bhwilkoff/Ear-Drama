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

A field the device does not know is `null`, never invented. An empty library
exports empty lists, not an error.

## The CSV file

`ear-drama-history-YYYY-MM-DD.csv`, one row a listened episode, newest first:
`episode,title,seriesName,airDate,listenedAt,positionSeconds,durationSeconds`.
Cells with a comma, quote or line break are quoted, quotes doubled; lines end
`\r\n`.

## Checks

`js/export.test.js`, `apple/Tests/DataExportTests.swift`,
`android/.../data/DataExportTest.kt`.
