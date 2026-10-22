# Windows build, test, and ship playbook ($0, from a Mac)

> **Enabling Windows in a new app**: the `windows/` scaffold at the repo root is
> the as-shipped architecture with every version gotcha pre-solved. Rename
> `AppName.*` per `windows/README.md`, copy `docs/windows/workflows/*.yml` into
> `.github/workflows/` (the template ships them only under `docs/`), and set `MSIX_PROJECT` if your MSIX project path
> differs. This doc and `WINDOWS-STORE-SUBMISSION.md` were written in Tidbits
> Trivia as the runbook for the NEXT app: this one.

**Companion to the binding design doc** (author yours from
`docs/templates/WINDOWS-DESIGN-template.md`). This is the **HOW**: the exact
$0 toolchain, the observability setup that lets a session SEE the Windows
UI from a Mac, the first-class-Windows implementation recipes, and the
CI/distribution pipeline. All commands run on the (any-OS) dev box unless
marked _(CI)_.

---

## 1. Toolchain (all free, all on the Mac)

```bash
brew install --cask dotnet-sdk        # .NET 10 SDK (free); `dotnet --version`
```
- **Avalonia 12** (pin an exact patch; Mica is a moving target) +
  **FluentAvaloniaUI 3** for WinUI-accurate controls + **.NET 10**. The
  scaffold pins working versions.
- Editor: VS Code + the C# Dev Kit (free), or Rider (optional).
- **No Windows machine, no Visual Studio needed to build.** The Skia renderer
  is why: `Avalonia.Headless` + `UseSkia()` renders the real UI in-process on
  any OS.

### Repo layout (sibling to `android/`, mirrors the universal-target idea)

Committed at `windows/`. The four-project shape is load-bearing:

```
windows/
├── AppName.slnx              # solution (new slnx format)
├── AppName.Core/             # C# port of the shared logic: models, networking,
│                             #   wire types, game/queue logic. OS-agnostic:
│                             #   NO Avalonia, NO Win32, NO WinRT.
├── AppName.App/              # Avalonia UI (net10.0): shell, views, VMs, the
│                             #   ONE Win32 seam, DPAPI secrets, AppxManifest
├── AppName.HeadlessTests/    # xUnit v3 + Avalonia.Headless: PNG capture,
│                             #   visual-baseline gate, golden vectors
└── AppName.Windows/          # the ONLY net10.0-windows TFM: content-free
                              #   WinRT edge (Store IAP), loaded reflectively
```

**A platform TFM goes in its own library, never on the app.** One
WinRT-needing feature put `net10.0-windows` on the app project once and every
MSIX publish died with `MSB4062 ExpandPriContent` (a task that ships with
Visual Studio, not the dotnet CLI; it runs over `@(Content)`, which the app
has). Full story: WINDOWS-STORE-SUBMISSION §7.

### Cross-build a runnable Windows binary (from the Mac)
```bash
cd windows
dotnet publish AppName.App -c Release -r win-x64 --self-contained \
  -p:PublishSingleFile=true -o publish/win-x64   # JIT, NOT AOT
# → publish/win-x64/AppName.App.exe  (won't run on the Mac;
#   validate via headless PNG + windows-latest CI, §3–§4)
```

---

## 2. The Core C# port (the ~60–70%)

Port, don't bridge. Source of truth = your `docs/DATA-CONTRACT.md` + the wire
schemas + the existing Swift/Kotlin/JS twins.

- **Networking:** a C# twin of the existing clients: REST over `HttpClient`
  (auth token refresh, ETag/CAS primitives, SSE streaming), no vendor SDK if
  the other platforms went SDK-free. All network calls go through this one
  shared client, never a raw `HttpClient` from a view/VM.
- **Wire types:** `record` types with `System.Text.Json`; **golden-vector
  tests** assert byte-compatibility with the other clients. The scaffold's
  `HashRank` + `HashRankTests` show the shape.
- **Game/domain logic:** direct port of the shared logic; unit-tested headless
  (no UI).
- **Persistence:** SQLite (`sqlite-net-pcl` or EF Core), the SwiftData/Room
  analog. **Secrets are DPAPI-protected** (`DpapiSecretStore` in the
  scaffold), never cleartext on disk. A cleartext refresh token was a real
  shipped bug.

---

## 3. Observability: SEE the Windows UI from the Mac

`Avalonia.Headless` renders the **real** UI to a PNG on the Mac,
pixel-faithful to Windows (Skia is OS-independent; only native window chrome
differs). The scaffold's `TestAppBuilder` carries the load-bearing config:

```csharp
[assembly: Avalonia.Headless.AvaloniaTestApplication(typeof(TestAppBuilder))]
public sealed class TestAppBuilder {
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<AppName.App.App>()
            .UseSkia()
            .WithInterFont()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions {
                UseHeadlessDrawing = false   // false => REAL Skia pixels (load-bearing)
            });
}
```

```bash
cd windows && APPNAME_ARTIFACTS=$PWD/artifacts dotnet test AppName.HeadlessTests
# → artifacts/*.png on the Mac; Read them to verify design
```

- **Render the WHOLE shell at a NARROW width, not single views at generous
  sizes.** Generous-size single-view renders hide the clipping/wrapping bugs
  an owner sees on a small laptop. The scaffold snapshots 1180×760 AND the
  900×680 floor, light AND dark.
- **Doubles as visual-regression:** the `VisualBaseline` gate diffs renders
  against committed baselines (§4.2).
- **What it does NOT show:** native Win11 title bar, Mica, OS font
  substitution, snap flyout. Those need real Windows (§4).
- **Gate network-touching auto-load behind a test flag.** A headless test
  that races a live fetch is flaky on CI and silently green on the Mac.

---

## 4. Real-Windows confirmation (free CI) _(CI)_: **the Windows box**

`windows-latest` is **unlimited-free on a public repo**, and per Decision 029
it IS the Windows machine. There is no free Windows VM to find, and
RDP-into-a-runner is ToS-gray, 6h-capped, and not sustainable. Don't
re-litigate; read the decision.

### 4.1 The CLI loop (no local toolchain needed)

```bash
# Run anything on real Windows and get the PNGs back
gh workflow run windows-repl.yml -f test_filter='FullyQualifiedName~ShellSnapshots'
gh run watch $(gh run list -w 'Windows REPL' -L1 --json databaseId -q '.[0].databaseId')
gh run download <run-id> -n windows-repl-artifacts   # then `Read` the PNGs

gh workflow run windows-repl.yml -f run_app=true             # launch the real .exe
gh workflow run windows-repl.yml -f update_baselines=true    # refresh baselines
gh workflow run windows-repl.yml -f command='dotnet --info'  # ad-hoc pwsh
```

Round trip ~2–4 min. **A green run here outranks a green run on the Mac.**

### 4.2 The three layers of the test rig

1. **Input simulation:** real clicks and typing through Avalonia's headless
   input stack (`win.MouseDown/MouseUp/KeyPressQwerty`), so the wiring BETWEEN
   a widget and the engine is covered, not just the render. Deterministic
   frame timing via `AvaloniaHeadlessPlatform.ForceRenderTimerTick()`.
2. **A visual-regression gate** (`VisualBaseline` in the scaffold): baselines
   captured ON Windows and enforced only there. Baseline-gated renders **must
   be deterministic**: fixed fixtures, never anything drawn from live or
   random data (a render fed by a random pick differs every run: fine for
   "prove it renders", useless as a baseline).
3. **Structure Windows-only work as pure behaviour + a thin platform edge.**
   The state decision is a pure function (unit-tested anywhere); only the
   final P/Invoke is Windows-gated (`Win32HostInterop` in the scaffold). This
   is what makes Windows-only features testable without a Windows box.

> **Pixel-format trap (cost real time once):** `Bitmap.CopyPixels` returns each
> bitmap's NATIVE format: a **captured frame is RGBA**, a **PNG-decoded file is
> BGRA**. Comparing them directly reads R against B and reports identical images
> as differing *only where they're coloured* (grey has R==G==B and agrees). Always
> normalize through one decode path (`VisualBaseline.Normalize`). Test the gate on
> COLOURED pixels; grey passes either way.

Two captures: headless PNG (deterministic) + a desktop screenshot (real
chrome/Mica). `windows-build.yml` runs tests + publish + a launch smoke on
every push to `windows/**`; download the artifact → `Read` the PNGs → verify
Mica/caption/snap that headless can't show. This is the "done" gate.

---

## 5. First-class-Windows recipes (the point of the platform)

All HWND interop lives in ONE Windows-guarded `Win32HostInterop` (in the
scaffold). Sketches:

### 5.1 Mica + Win11 caption
```xml
<Window xmlns="https://github.com/avaloniaui"
        TransparencyLevelHint="Mica" Background="Transparent"
        ExtendClientAreaToDecorationsHint="True">
  <!-- panels use theme-variant brushes WITH ALPHA so Mica shows through -->
</Window>
```
Fallback if the pinned build black-windows on Mica is DWM interop:
`DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, DWMSBT_MAINWINDOW)`.
**VERIFY on a CI screenshot before committing to the look.** (The scaffold
keeps standard decorations, which is what makes Snap Layouts work for free.)

### 5.2 A fullscreen surface on the second monitor
```csharp
var target = Screens.All.FirstOrDefault(s => !s.IsPrimary) ?? Screens.Primary;
var big = new PresentationWindow { SystemDecorations = SystemDecorations.None };
big.Position = target.Bounds.Position;      // THEN fullscreen (order matters)
big.WindowState = WindowState.FullScreen;
big.Show();
// hot-plug survival:
Screens.Changed += (_, _) => Reproject(big);  // re-pick screen; fall back to primary, never vanish
```

### 5.3 Taskbar progress
`Win32HostInterop.SetTaskbarProgress(...)` each tick, so folks see your
long-running state on a minimized window. Keep the mapping (what to show) a
pure function; the P/Invoke is just paint.

### 5.4 Global hotkeys
`Win32HostInterop.TryRegisterHotKey(...)` + pump `WM_HOTKEY` via an Avalonia
`Win32` message hook. Works when another app has focus. A false return means
"unavailable", never fatal.

### 5.5 Toasts
`DesktopNotifications.Avalonia`: register `INotificationManager` in the
AppBuilder; `Show(new Notification { Title=..., Body=... })`. Needs package
identity (the AppxManifest).

### 5.6 Keyboard-first + Alt-menus
Access keys via `_` in menu headers; `KeyBindings` for app accelerators
(Ctrl+, = Settings is in the scaffold, the Windows twin of macOS menu
commands). Keep the system-accent focus ring visible.

---

## 6. Publishing: the channel decision (which store, and how)

**THE RECOMMENDATION: Microsoft Store as the primary channel, GitHub
Releases + winget as the $0 direct channel alongside it.**

### 6.1 Channel matrix (all Mac-authored; CI does the Windows steps)

| Channel | Cost | Signing / SmartScreen | Auto-update | Best for | Verdict |
|---|---|---|---|---|---|
| **Microsoft Store (MSIX)** | **$0** (reg fee waived 2025) | **MS signs it → NO SmartScreen** | Store-managed | Broadest reach, trust, discoverability | **PRIMARY** |
| **GitHub Releases + Velopack** | $0 | Unsigned → SmartScreen until rep builds (or add Azure signing) | Velopack delta self-update | Direct download, fast iteration, beta channel | **SECONDARY (pair w/ Store)** |
| **winget** (`winget install`) | $0 | Points at your GitHub installer (inherits its signing) | via the referenced installer | Power users, IT, scriptable installs | **ADD (free, easy)** |
| **Website direct** | $0 | Same as GitHub installer | via Velopack | Link from the web app | Yes (same artifact) |
| **Steam** (Steamworks) | **$100 one-time**, recoupable after $1k rev; **30% cut** | Steam handles it | Steam client | Games audience | Later/optional |
| **itch.io** | $0 to publish | itch app handles it | itch app | Indie audience | Later/optional |

### 6.2 Why Microsoft Store is the right primary path

- **It kills the signing problem for free.** Registration fee is waived
  (start at `storedeveloper.microsoft.com`, ID-verify), and **Microsoft
  signs the package**, so folks see no SmartScreen "unknown publisher"
  warning and you never buy or renew a cert. The only $0 path that also
  removes the trust warning.
- **Discoverability + auto-update** are built in. Updates flow with no infra
  of yours.
- **Submission is CLI-shaped once bootstrapped.** See
  `WINDOWS-STORE-SUBMISSION.md`:

```bash
gh workflow run windows-store.yml                    # package MSIX only
gh workflow run windows-store.yml -f submit=true     # + submit as a DRAFT
gh workflow run windows-store.yml -f submit=true -f commit=true   # + publish
```

The load-bearing facts, learned the expensive way:

- **`PublishSingleFile` is INCOMPATIBLE with MSIX.** `windows-store.yml`
  publishes multi-file on purpose; `windows-build.yml` keeps single-file for
  the direct-download `.exe`. **Do not unify them.**
- **Condition native packages on the RID.** Referencing e.g.
  `VideoLAN.LibVLC.Mac` and `.Windows` unconditionally shipped a 42MB macOS
  dylib + a 99MB win-x86 tree inside the win-x64 package; with native pdbs
  that was over half of a 211MB package. The scaffold's csproj shows the
  conditions + the `TrimWindowsPublishBloat` target.
- **No signing certificate is needed.** The Store re-signs after
  certification. The self-signed step in the workflow exists ONLY to make the
  artifact installable for sideload testing.
- **The 4th version segment must be 0** (Store-reserved), so the build number
  has nowhere to live and **every Store upload needs a MARKETING_VERSION
  bump**. `tools/stamp_msix_version.py` keeps it in lockstep with
  `AppVersion.xcconfig`.
- **Beta = private audience (UI) + package flights (CLI).** The TestFlight
  analogue; flights support staged rollout with halt/finalize.
- **A manual bootstrap is unavoidable**: the API cannot create the app, and it
  refuses to drive submissions until one full manual submission (incl. age
  ratings) exists.

### 6.3 The $0 direct channel (GitHub Releases + winget)

Store review adds latency and MSIX sandboxing; the direct channel gives
control + speed and reaches users who don't use the Store:
1. GitHub Actions: `dotnet publish -r win-x64 --self-contained` _(CI)_.
2. **Velopack** `vpk pack` → installer + delta updates + self-updating
   app _(CI, free Windows runner)_.
3. Publish assets to **GitHub Releases** (the update feed, $0 hosting);
   app self-updates via Velopack `UpdateManager`.
4. **winget manifest** (a YAML PR to `microsoft/winget-pkgs`, or
   `wingetcreate`: free, no Windows PC needed) pointing at the GitHub
   Release installer.
- SmartScreen applies to this channel until reputation builds. The Store
  channel is the "no warning" path; this is the "full control" path.

### 6.4 The signing question (only relevant to the direct channel)

The Store channel needs no signing (MS does it). For the **direct** channel,
in cost order: **ship unsigned** ($0, SmartScreen tax) → **Azure Artifact
Signing ~$10/mo** (cloud, no token, `azure/trusted-signing-action`; removes
SmartScreen; pipeline unchanged) → **avoid** OV/EV certs ($200–685/yr +
mailed FIPS dongle, no better outcome; EV's instant-SmartScreen pass was
removed in 2024). **Never self-sign** for distribution (hard-blocked, worse
than unsigned).

---

## 7. Bootstrap sequence (to first running slice)

1. **Adopt the scaffold.** Rename per `windows/README.md`, copy the
   workflows in, commit; confirm `windows-build.yml` green and Read the shell
   PNGs. (The scaffold builds and its tests pass out of the box. Do NOT
   re-run `dotnet new`; the three version gotchas in §9 are already solved
   in-tree.)
2. **Core port, thin:** wire types + read client + a golden-vector test
   passing against the existing vectors (§2). This proves the contract twin
   before any UI.
3. **First real surface** rendering fixture data → headless PNG → `Read`.
   First visual proof.
4. **Shell wiring:** replace the placeholder sections with real views; arm
   the baseline gate (`-f update_baselines=true`, commit the artifact).
5. **Parity features:** port surface by surface; PARITY.md row per feature.
6. **Package** (MSIX + single-file `.exe`), first GitHub Release, Store
   bootstrap (`WINDOWS-STORE-SUBMISSION.md` §1).
7. Each step: headless PNG + `windows-latest` CI + PARITY.md row.

---

## 8. Cost ledger (honest)

| Item | Cost |
|---|---|
| .NET SDK, Avalonia, FluentAvalonia, Velopack | $0 (MIT/free) |
| Build from Mac + `windows-latest` CI (public repo) | $0 |
| Headless PNG observability | $0 |
| GitHub Releases (update feed) | $0 |
| Microsoft Store registration + signing | $0 (fee waived, Store signs) |
| **Ship-unsigned direct download** | **$0** (SmartScreen UX tax) |
| _Optional:_ Azure Artifact Signing (no SmartScreen, direct dl) | ~$10/mo |
| _Avoid:_ OV/EV certs (+ mailed FIPS dongle) | $200–685/yr |

**Steady-state $0 is achievable.** The only non-$0 option worth considering
later is ~$10/mo Azure signing, and only to remove the SmartScreen prompt on
direct downloads. It is deferrable and pipeline-compatible.

---

## 9. The version gotchas the scaffold pre-solves (will bite on different versions)

Kept for when a dependency bump re-surfaces them:

1. **FluentAvaloniaUI 3.x prefixes every control `FA`:** `FANavigationView`,
   `FANavigationViewItem`, `FANavigationViewSelectionChangedEventArgs` (v2
   used the unprefixed names). Symptom: XAML "Unable to resolve type
   NavigationView". Find real names with
   `strings <pkg>/lib/*/FluentAvalonia.dll | grep FA`.
2. **`Avalonia.Headless.XUnit` 12.x requires xunit v3** (`xunit.v3`), but
   `dotnet new xunit` pins **xunit v2** → `CS0433 InlineDataAttribute exists
   in both`. The scaffold's test csproj already references `xunit.v3`.
3. **`AvaloniaTestApplicationAttribute` is in the `Avalonia.Headless`
   namespace**, NOT `Avalonia.Headless.XUnit`.

**Headless render config that produces real pixels** (not a blank stub):
`AppBuilder.Configure<App>().UseSkia().WithInterFont().UseHeadless(new
AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false })`, then
`window.Show(); Dispatcher.UIThread.RunJobs(); window.CaptureRenderedFrame().Save(png)`.
