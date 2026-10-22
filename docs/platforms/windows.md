# The Windows app (optional)

Read this before any Windows work. The long-form how-to is
[`docs/windows/WINDOWS-PLAYBOOK.md`](../windows/WINDOWS-PLAYBOOK.md).

These rules lived in `AGENTS.md` until October 3, 2026, when it was cut
below 24,000 bytes so that Antigravity, which stops reading a rule file
at that size, would read all of it. They moved here word for word, and
`AGENTS.md` links to this page with one line saying when to read it. The
rules that hold on every platform stayed in `AGENTS.md`.

## Which skill

- **Windows (optional)**: `windows-production-gotchas`
  FIRST: the CI-is-the-Windows-machine doctrine, headless-PNG
  observability, the visual-baseline gate, the platform-TFM and MSIX
  traps. The `windows/` scaffold is the as-shipped architecture
  (builds green out of the box); pipeline depth in `docs/windows/`.

## Windows app (optional)

**Stack**: **Avalonia 12** + **FluentAvaloniaUI 3** + **.NET 10** (C#),
`CommunityToolkit.Mvvm` for MVVM, DPAPI for secrets. No WinUI, no WPF:
Avalonia-only, because `Avalonia.Headless` renders real Skia pixels
in-process on any OS, which is what makes the $0, no-Windows-hardware
pipeline real (Decision 029). Ships to the Microsoft Store as an MSIX
(Microsoft re-signs; no cert to manage) + a single-file `.exe` direct
channel.

The **`windows/` scaffold is the as-shipped architecture** of a
Store-certified app. Adopt it per `windows/README.md`; don't re-derive
it. Four projects, and the shape is load-bearing: `AppName.Core`
(OS-agnostic C# port of the shared logic), `AppName.App` (Avalonia UI),
`AppName.HeadlessTests` (PNG snapshots + the visual-baseline gate +
golden vectors), `AppName.Windows` (the ONLY `net10.0-windows` TFM:
content-free WinRT edge, loaded reflectively; the TFM on the app project
kills every MSIX publish with MSB4062).

**The Windows workflows ship parked.** `windows-build.yml`,
`windows-repl.yml`, `windows-store.yml` and `windows-store-addons.yml`
live in `docs/windows/workflows/`. Copy the ones you need into
`.github/workflows/` before any `gh workflow run` below will find them.

**The loop is CI, not a local desktop**: iterate on the Mac head
(`dotnet test` → open the PNGs), gate on `windows-latest`
(`gh workflow run windows-repl.yml`, ~2–4 min). "Renders on the Mac" is
never "correct on Windows". Critical conventions (depth in
`windows-production-gotchas` + `docs/windows/WINDOWS-PLAYBOOK.md`):

- **FluentAvalonia components first** (`FANavigationView` shell,
  `FAContentDialog`, `SettingsExpander`) before any custom control.
  Note the `FA` prefix in v3.
- **Compiled bindings on** + `x:DataType` on every view. A binding
  typo is a build error, not a silent blank. Views are parameterless.
- **The six-level type ramp + `Border.card` live once in `App.axaml`**;
  pin the brand accent (Fluent's dark-theme derivation washes it out).
- **All network calls through the shared Core client**, never a raw
  `HttpClient` from a view/VM.
- **Secrets are DPAPI-protected**, never cleartext on disk.
- **Pure function + thin Windows-guarded edge** for all Win32/WinRT work
  (`Win32HostInterop`, the reflective store gateway). This is what
  keeps it testable off Windows.
- **Version bump on every ship**: `<Version>` in the csproj +
  AppxManifest, stamped by `tools/stamp_msix_version.py` from
  `AppVersion.xcconfig` (the Store reserves the 4th segment).
- **Ship**: `gh workflow run windows-store.yml -f submit=true
  -f commit=true` (after copying it into `.github/workflows/`).
  Anything less succeeds while shipping nothing. See
  `docs/windows/WINDOWS-STORE-SUBMISSION.md` for the bootstrap and the
  silent stalls.
