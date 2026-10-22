---
name: windows-production-gotchas
description: Use when building or debugging the Windows (Avalonia + FluentAvalonia + .NET) app — the cross-cutting production lessons from shipping an Avalonia MSIX to the Microsoft Store from a Mac with zero Windows hardware. Covers the CI-is-the-Windows-machine doctrine, headless-Skia PNG observability, the visual-baseline gate and the CopyPixels RGBA/BGRA trap, the platform-TFM-in-its-own-library rule (MSB4062), FluentAvalonia FA-prefix and xunit-v3 version traps, DPAPI secret storage, pure-function + thin-Win32-edge structure, RID-conditioned natives, PublishSingleFile-vs-MSIX, and the Store submission silent stalls. Triggers on Avalonia, FluentAvalonia, FANavigationView, MSIX, msstore, windows-latest, Avalonia.Headless, headless PNG, visual baseline, CopyPixels, MSB4062, ExpandPriContent, NETSDK1083, net10.0-windows, DPAPI, ProtectedData, Win32 interop, taskbar progress, global hotkey, Mica, AppxManifest, runFullTrust, "renders on the Mac", windows-repl, windows-store.yml.
---

# Windows Production Gotchas

Cross-cutting lessons from shipping an Avalonia 12 + FluentAvaloniaUI 3 +
.NET 10 app to the Microsoft Store — built and verified **entirely from an
Apple Silicon Mac** with `windows-latest` CI as the only Windows compute.
The repo carries the working artifacts: the `windows/` scaffold (every
version gotcha pre-solved, builds green out of the box),
`docs/windows/WINDOWS-PLAYBOOK.md` (the pipeline), and
`docs/windows/WINDOWS-STORE-SUBMISSION.md` (the ship runbook). This skill
carries the **rules and bug classes that cost real sessions**.

## The doctrine

- **`windows-latest` IS the Windows machine.** There is no free Windows VM;
  the search was exhaustive and the answer is settled (DECISIONS.md 029).
  Don't re-research VMs, don't RDP into runners. The loop is: iterate on the
  Mac head (`dotnet test` renders real Skia pixels headlessly), gate on
  Windows (`gh workflow run windows-repl.yml` → download → Read the PNGs,
  ~2–4 min round trip).
- **"Renders on the Mac" is never "correct on Windows."** Mica, window
  chrome, DPAPI, Win32/WinRT interop, font substitution, and native libs are
  Windows-only. A green `windows-repl.yml` run outranks a green Mac run.
- **Avalonia, not WinUI/WPF/MAUI** — because `Avalonia.Headless` with
  `UseSkia()` + `UseHeadlessDrawing = false` renders the REAL UI to PNGs
  in-process on any OS. That property is the entire $0 pipeline; WinUI
  cannot do it.

## Observability (the spine)

- **Every UI change is observed as a PNG before it ships.** Capture with
  `window.Show(); Dispatcher.UIThread.RunJobs();
  window.CaptureRenderedFrame().Save(...)`. `UseHeadlessDrawing = false` is
  load-bearing — `true` produces a blank stub that "passes".
- **Render the WHOLE shell at a NARROW width**, not single views at generous
  sizes — generous single-view renders hide the clipping/wrapping an owner
  sees on a small laptop. Capture light AND dark; accent-derivation bugs
  (brand color washed to pastel) only show in dark.
- **Baseline-gated renders must be deterministic** — fixed fixtures, never a
  random or live pick. A render that differs every run is fine for "proves it
  renders", useless as a baseline.
- **The CopyPixels trap:** `Bitmap.CopyPixels` returns each bitmap's NATIVE
  channel order — a captured frame is RGBA, a PNG-decoded file is BGRA.
  Comparing them directly reads R against B and reports *identical* images as
  differing wherever they're coloured (grey has R==G==B and agrees), and the
  tempting fix — refreshing baselines — hides it forever while blinding the
  gate. Normalize both sides through ONE decode path (PNG round-trip), and
  self-test the comparator on COLOURED pixels.
- **Prove the gate can see.** Keep a self-test that renders two different
  frames and asserts the comparator reports a diff — a check that cannot
  detect a change must die, not report clean.
- **Input simulation covers the wiring**, not just the render:
  `win.MouseDown/MouseUp/KeyPressQwerty` +
  `AvaloniaHeadlessPlatform.ForceRenderTimerTick()` for deterministic frames.
- **Gate network-touching auto-load behind a test flag** — a headless test
  racing a live fetch is flaky on CI and silently green on the Mac.

## Build-system traps (each one broke the ship)

- **A platform TFM goes in its OWN library, never on the app project.**
  `net10.0-windows10.0.x` (needed for any WinRT API) turns on MSBuild's
  Appx/PRI indexing over `@(Content)`; the app links shared assets as
  Content, and every publish then dies with `MSB4062 ExpandPriContent` — a
  task that ships with Visual Studio, not the dotnet CLI.
  `WindowsPackageType=None` / `EnableMsixTooling=false` do NOT stop it. The
  fix: an isolated **content-free** class library carries the TFM; the
  net10.0 app cannot reference it, so it's loaded with `Assembly.LoadFrom`
  and absence degrades to an inert implementation. Companion traps:
  `NETSDK1083` (the TFM defaults to deleted UWP-era RIDs — name `win-x64`),
  `CS0104` (WinRT redefines names — alias the namespace),
  `EnableWindowsTargeting=true` (lets the library compile on the Mac head).
- **`PublishSingleFile` is incompatible with MSIX.** The Store workflow
  publishes multi-file; the direct-download workflow keeps single-file. Two
  publishes, on purpose — don't unify.
- **Condition native packages on the RID.** Unconditional `.Mac` + `.Windows`
  native references shipped a 42MB macOS dylib and a 99MB win-x86 tree
  inside the win-x64 Store package — over half of it. Also trim native pdbs
  after publish.
- **Version bumps every ship.** The Store reserves the 4th version segment,
  so two builds of one marketing version are indistinguishable — bump
  `MARKETING_VERSION` and stamp csproj + AppxManifest together
  (`tools/stamp_msix_version.py`).

## Framework version traps (pre-solved in the scaffold)

- FluentAvaloniaUI 3.x prefixes every control `FA` (`FANavigationView`);
  "Unable to resolve type NavigationView" means a v2 name.
- `Avalonia.Headless.XUnit` 12.x needs **xunit.v3**; `dotnet new xunit` pins
  v2 → `CS0433`.
- `AvaloniaTestApplicationAttribute` lives in `Avalonia.Headless`, not
  `.XUnit`.
- Compiled bindings ON (`AvaloniaUseCompiledBindingsByDefault` +
  `x:DataType` everywhere) — a binding typo becomes a build error, not a
  silent runtime blank.
- Views are parameterless and bind `DataContext` — a constructor parameter
  on a View trips `AVLN3001`.
- `FANavigationView` can settle on its first item WITHOUT raising
  SelectionChanged — navigate the landing surface directly in `Loaded` or
  the detail pane stays blank until a click.

## Windows-native structure

- **ONE Win32 seam** (`Win32HostInterop`): every HWND-touching call
  (taskbar progress, global hotkeys, owner handles) in one Windows-guarded
  class that no-ops off Windows. Keep the DECISION a pure function
  (unit-testable anywhere); the P/Invoke is just paint.
- **Secrets are DPAPI-protected** (`ProtectedData`, CurrentUser + entropy),
  never cleartext — a cleartext refresh token on disk was a real shipped
  bug. Fall back to a file store off Windows; on `CryptographicException`
  (roamed profile / restored backup) drop the blob and re-authenticate
  rather than wedging sign-in.
- **Package identity unblocks** protocol activation, toasts, and jump lists
  (all throw NO_PACKAGE without it). Deep links land in an inbox
  (`Program.LaunchUrl`), consumed by the shell once shown; EVERY URL shape
  emitted must be declared in the AppxManifest or external opens fail
  silently.
- **`Package.Current` is the packaged-or-not probe**, not
  `StoreContext.GetDefault()` — the latter hands back a context in an
  unpackaged process and fails one call deeper.

## Store shipping (the silent stalls)

Full runbook: `docs/windows/WINDOWS-STORE-SUBMISSION.md`. The two that burn
weeks: a run without `-f commit=true` **succeeds while shipping nothing**
(and deletes the prior draft); and a certified submission can sit at "ready
to publish" forever behind a `targetPublishMode` hold that `msstore` cannot
change — set "publish as soon as it passes certification" once in Partner
Center. Ground truth is Partner Center → Manage packages, never a green
Actions run. For IAP: `GetAssociatedStoreProductsAsync` (not
`GetStoreProductsAsync`), a subscription is a `Durable` add-on (one query
covers all kinds — the opposite of Play Billing's one-query-per-type), the
entitlement gate fails OPEN, and no API can list add-ons once one is a
subscription — verify ids by eye in Partner Center plus a read-back
workflow.
