# Windows app scaffold: Avalonia + FluentAvalonia + .NET 10

The optional 6th platform, developed **entirely from a Mac (or any OS) with $0 of
Windows hardware**. `windows-latest` on a public GitHub repo IS the Windows machine
(DECISIONS.md 029); `Avalonia.Headless` + Skia renders the real UI to PNGs
in-process, so you can SEE the Windows app from wherever you develop.

This scaffold is the as-shipped architecture of a real Microsoft Store app
(Tidbits Trivia, certified 2026), with every version gotcha pre-solved: FluentAvalonia
3's `FA` control prefix, `xunit.v3` (v2 collides with Avalonia.Headless.XUnit), the
`UseHeadlessDrawing = false` real-pixels config, the RGBA/BGRA `CopyPixels` trap,
and the platform-TFM isolation that keeps MSIX publishes alive.

## Layout

```
windows/
├── AppName.slnx              ← solution (new slnx format)
├── AppName.Core/             ← platform-agnostic C# port of the shared logic
│                               (the 4th–6th mirror alongside Swift/Kotlin/JS);
│                               NO Avalonia, NO Win32, NO WinRT
├── AppName.App/              ← Avalonia UI: FANavigationView shell, type ramp +
│                               card tokens in App.axaml, DPAPI secret store,
│                               the ONE Win32 seam (Win32HostInterop)
├── AppName.HeadlessTests/    ← xUnit v3 + Avalonia.Headless: PNG snapshots,
│                               the visual-baseline gate, golden vectors
└── AppName.Windows/          ← the ONLY project on a net10.0-windows TFM.
                                Content-free WinRT edge (Store IAP etc.), loaded
                                reflectively. NEVER put this TFM on AppName.App
```

## Adopting it (rename pass)

1. Rename every `AppName.*` directory/file/namespace to your app
   (`grep -rl AppName windows/ | xargs sed -i '' 's/AppName/YourApp/g'`, then
   `mv` the dirs/files; also `APPNAME_` env prefixes in HeadlessTests and the
   workflows). Keep the four-project shape.
2. Replace `appname:` / `your-domain.example` in Program.cs + AppxManifest.xml
   with your scheme/domain.
3. Copy `docs/windows/workflows/*.yml` into `.github/workflows/` and rename the
   same identifiers there.
4. Set your brand color in App.axaml (both the `FluentAvaloniaTheme
   CustomAccentColor` and the pinned `Button.accent` styles).

## The loop

```bash
# Iterate on the Mac head (fast, NOT the ship gate):
cd windows && dotnet build AppName.slnx && dotnet test AppName.HeadlessTests
# → artifacts/*.png (Read them to see the UI)

# Gate on real Windows (~2–4 min round trip):
gh workflow run windows-repl.yml
gh run download <id>            # → PNGs rendered ON Windows

# First Windows run / intended visual change: arm or refresh the baseline gate
# (the workflows run from .github/workflows/ once you copy them there, step 3 above):
gh workflow run windows-repl.yml -f update_baselines=true
# download the baselines artifact → commit to AppName.HeadlessTests/Baselines/windows/
# (that directory does not exist until you commit the first baselines)

# Cross-build the real Windows binary from the Mac:
dotnet publish AppName.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/win-x64
```

"Renders on the Mac" is never "correct on Windows". Mica, window chrome, DPAPI,
Win32 interop, and any native libs are Windows-only. A green `windows-repl.yml`
run outranks a green run on the Mac.

## Input-driven tests (the wiring, not just the render)

Avalonia's headless platform simulates real clicks and keys, so the connection
BETWEEN a widget and the engine is coverable:

```csharp
using Avalonia.Headless;   // extension methods on Window
win.MouseDown(new Point(x, y), MouseButton.Left);
win.MouseUp(new Point(x, y), MouseButton.Left);
win.KeyPressQwerty(PhysicalKey.Space, RawInputModifiers.None);
AvaloniaHeadlessPlatform.ForceRenderTimerTick();   // deterministic frame timing
```

## Rules that keep this pipeline alive

- **Baseline-gated renders must be deterministic:** fixed fixtures, never live or
  random data.
- **Normalize both images through ONE decode path before comparing** (see
  `VisualBaseline.Normalize` in `AppName.HeadlessTests/VisualBaseline.cs`).
  `CopyPixels` returns each bitmap's native channel
  order, and comparing a captured frame to a PNG-decoded file reads R against B.
- **`PublishSingleFile` is incompatible with MSIX.** `windows-store.yml` publishes
  multi-file; `windows-build.yml` keeps single-file for the direct-download `.exe`.
  Don't unify them.
- **Gate network-touching auto-load behind a test flag.** A headless test that
  races a live fetch is flaky on CI and quiet on the Mac.
- **Ship**: `docs/windows/WINDOWS-STORE-SUBMISSION.md` (Store MSIX via
  `windows-store.yml`); bump `<Version>` via `tools/stamp_msix_version.py` on every
  ship.
