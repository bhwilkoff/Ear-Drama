# [APP NAME] Windows design (BINDING)

<!-- Seed for docs/WINDOWS-DESIGN.md (you create it from this file once
     the Windows app passes ~5 views). Invoke
     `binding-design-doc-discipline` for the workflow and
     `windows-production-gotchas` for the mechanics this doc does NOT
     restate. The build/test/ship pipeline lives in
     docs/windows/WINDOWS-PLAYBOOK.md and the Store submission in
     docs/windows/WINDOWS-STORE-SUBMISSION.md. Reference them, do not
     duplicate them.

     Learned in Tidbits Trivia, a trivia app whose Windows build was
     certified in the Microsoft Store in 2026. Its marquee was a host-run
     live night on a laptop and a projector, which is where the
     "second-screen presenter" module (section 6) came from.

     Sections marked "(optional module)" apply only if the app has that
     surface. Replace every [BRACKET] and delete the FILL notes. -->

**Status: binding.** Quote the relevant rule before proposing any new
window, page, dialog, or feature ("per WINDOWS-DESIGN 5.4"). When the
doc and a feature conflict, **fix the doc first**. Amendments are
append-only, with a dated note and a reason.

Division of labor: **this doc** is the binding Windows contract.
**`windows-production-gotchas`** carries the mechanics and failure
modes. **`docs/windows/WINDOWS-PLAYBOOK.md`** is the pipeline.
**`PARITY.md`** says what ships where. **`DECISIONS.md`** (029) says
why Windows is here at all.

**Stack (settled, see `windows/README.md`):** Avalonia 12 +
FluentAvaloniaUI 3 + .NET 10 (C#, XAML). Avalonia renders with Skia
(its own controls, not WinUI peers), which is exactly why it
cross-builds and renders headless from a Mac. Persistence:
[FILL IN: SQLite via `sqlite-net` or EF Core, the SwiftData/Room
analog]. Shared backend: [FILL IN: the data plane every client already
consumes], read by a C# client twin of the web and native clients.

> [FILL IN: why Windows earns its place for this app, in two
> sentences. Name the person and the hardware. Tidbits Trivia's answer
> was "hosts run live nights from Windows laptops plugged into
> projectors", so Windows was a host-first platform and the consumer
> game rode along for parity.]

---

## 0. Architecture blockers (the compile and structure traps)

0.1 **Core is a C# port, not shared Swift.** Roughly 60 to 70 percent
of an app is platform-agnostic logic (models, the REST client, wire
types, scoring and queue logic, the corpus consumer). It is
**re-implemented in C#** in `AppName.Core`, the same relationship
Android (Kotlin) and the web (JS) have to the contract. No Swift is
shared or bridged. The contract (`docs/DATA-CONTRACT.md`, which you
create from `docs/templates/DATA-CONTRACT-template.md`) is the source
of truth every side conforms to. Golden-vector tests
(`windows/AppName.HeadlessTests/HashRankTests.cs` is the pattern) keep
the C# wire types byte-compatible with the Apple, Kotlin and JS twins.

0.2 **The Win32 interop seam is the `#if os()` analog.** Mica via DWM,
taskbar `ITaskbarList3`, global `RegisterHotKey`, and the
`WM_NCHITTEST` to `HTMAXBUTTON` snap fix all need the HWND
(`TopLevel.TryGetPlatformHandle()`). Put ALL of it behind ONE
`Win32HostInterop` helper (`windows/AppName.App/Services/Win32HostInterop.cs`)
with `OperatingSystem.IsWindows()` guards. `AppName.Core` NEVER
references it, so Core stays OS-agnostic and compiles for the headless
test host and the macOS dev head.

0.3 **Only `AppName.Windows` carries the `net10.0-windows` TFM.** It is
a content-free WinRT edge (Store purchases and similar), loaded
reflectively. Putting the Windows TFM on the app project kills every
MSIX publish with MSB4062.

0.4 **JIT self-contained publish, NOT Native AOT.** `dotnet publish -r
win-x64 --self-contained` cross-builds from Apple Silicon. Native AOT
does not cross OSes and would force a Windows build box. Keep AOT out
of the default pipeline (a CI-only experiment at most).

0.5 **Package identity is required for the good parts.** Toasts, jump
lists, the startup task, and `[appscheme]://` protocol activation all
need MSIX package identity or they throw `NO_PACKAGE`. The Store MSIX
carries that identity. An unpackaged raw `.exe` loses those features,
so treat the direct-download channel as a reduced surface and say so in
PARITY.md.

0.6 **Develop against the Avalonia macOS head. Verify with a headless
PNG and Windows CI.** Avalonia runs natively on the Mac, so iterate the
UI there. Gate "done" on an `Avalonia.Headless` PNG (`Read` it) AND a
`windows-latest` CI run (`windows-repl.yml`, copied from
`docs/windows/workflows/`). "Compiles" and "renders on the Mac head"
are not "correct on Windows": Mica, window chrome and snap are
Windows-only (sections 2 and 8).

---

## 1. What the Windows app is

1.1 [FILL IN: the one-line shape. Example: "a host cockpit plus the
consumer app, in ONE Avalonia app, Fluent-themed for Windows 11 and
graceful on Windows 10."] Name which mode is the reason the platform
exists and which modes ride along for parity.

1.2 **Design principles are identical to the sibling platforms; the
idioms diverge.** Density from removing chrome, the six-level type
ramp, the brand primary for CTAs, and the learning-orientation test.
The inversions against the Mac: pointer plus **keyboard-first**
(Windows folks run things from the keyboard), an Alt-mnemonic menu bar,
taskbar and tray presence, system light/dark and accent, Mica
materials.

1.3 **First-class, not a port (the bar).** If a Windows user would say
"this is clearly a cross-platform port," it fails 8.2. The tells of a
first-class app: a Mica window base, a real Windows 11 caption, snap
layout participation, remembered per-monitor geometry, taskbar
progress where a long-running state exists, toast notifications, and
global hotkeys where the app is driven while another window has focus.

---

## 2. The shell (window model)

2.1 **The shell is FluentAvalonia `FANavigationView`** (the WinUI
idiom): a left nav pane ([FILL IN: the top-level destinations]) that
collapses to a hamburger at narrow widths. NOT the macOS
`NavigationSplitView` reused, NOT a tab bar. One content frame. **The
landing surface renders on load**, never as a side effect of
`SelectionChanged`: a detail pane that stays blank until someone
clicks the nav is a broken first impression.

2.2 **Settings is a `FANavigationView` footer item** (gear), opening a
Settings page. That is the Windows idiom (there is no `Cmd+,` Settings
scene). If the app has accounts, sign-in lives in Settings AND as a
banner on the surface that benefits from signing in. Sign-in must be
reachable in two clicks or fewer from launch.

2.3 **A full-screen mode REPLACES the window content.** Starting a
session, a game, or a presenter mode swaps the shell for that surface.
Never an overlay over the nav, because its chrome bleeds through. (The
same rule as the macOS player-as-window-root.) A second screen is a
SEPARATE top-level window (section 6).

2.4 **Window chrome:** extend into the title bar
(`ExtendClientAreaToDecorationsHint`), a Mica backdrop
(`TransparencyLevelHint="Mica"` plus a transparent background and
translucent panels), and follow `ActualThemeVariant`. **Verify on the
pinned Avalonia build** (0.6, 8.6): some Avalonia 12 previews rendered
a black window on Mica.

---

## 3. The main experience (parity, keyboard-first)

3.1 **One engine.** The main experience runs on the C# Core port, never
a second engine or a re-derived pipeline (7.3). Esc or a visible Quit
affordance always returns to the shell.

3.2 **Keyboard-first.** [FILL IN: the key map. Example: number keys
pick options, Enter continues, Esc quits, arrows drive sliders and
steppers.] Mirror the tvOS and macOS key maps where they exist. Every
interactive control is Tab-reachable with a visible system-accent
focus ring.

3.3 **Remote images route through ONE image helper** (a decoded cache
plus a capped `HttpClient`), never bare per-frame network image
controls. This is the Windows analog of the macOS `ImagePipeline`
rule. Decode to a consistent color space so a grayscale or CMYK image
never renders as a white box.

3.4 **Buttons size to content** (the Fluent default). A full-width
button is ONLY a genuine single primary CTA below content, never a
control sitting next to another control in a row. The macOS app
shipped exactly that malformed-button class once. Do not reintroduce
it here.

---

## 4. Lists and dashboards

4.1 **A history surface is a dashboard, not a ledger.** Summary first,
then **recent items bounded to three plus "See all"**, then the deeper
sections. "See all" is a light Fluent list or `DataGrid`, **never** a
wall of cards. Do not port an inline dump from another platform.

4.2 **Every list and grid defines its loading, empty, error and
offline states** (`universal-feature-states`). A signed-out state that
hides data carries a banner routing to sign-in.

---

## 5. Design system (Fluent, brand-forward)

5.1 **Shared tokens, Windows expression.** Reuse the palette values
from AGENTS.md (`--color-primary`, `--color-accent`, surface, text,
border) as Avalonia `ThemeVariant` resource dictionaries (light and
dark) in `windows/AppName.App/App.axaml`. The brand drives CTAs and
active states. The **system accent** drives OS chrome only (focus
rings, selection), so the app belongs on the machine without diluting
the brand.

5.2 **One card style.** `Border.card` in `App.axaml` is the reusable
card (rounded rect, border, its own shadow). Never hand-add shadow
padding at a call site.

5.3 **Typography is the same six levels** (L1 page title to L6
tabular), defined once in `App.axaml`. Refuse a seventh. Any
big-screen or presenter text scales by **viewport fraction with a
minimum scale**, never a fixed point size: a projector at 100 percent
and a laptop at 150 percent make fixed sizes wrong on one of them.

5.4 **The brand CTA is PINNED, and an accent button never sits on an
accent surface.** FluentAvalonia derives a lighter accent for the dark
theme, so a `Classes="accent"` button washes out to a pale tint with
black text while any hard-coded brand color beside it stays saturated.
Two adjacent CTAs then disagree. `Button.accent` pins the brand token
(with white text) in both themes. Fluent's derived accent still drives
focus rings and selection, which is correct there. On a brand-colored
surface the accent button is invisible, so use the inverse treatment
(a white chip with a brand-colored label). This applies to EVERY accent
surface, not only buttons: a switched-on `ToggleSwitch` washed out the
same way until it was pinned too.

5.5 **Settings is `FASettingsExpander` rows**, not bold `TextBlock`
headers over `StackPanel`s. Header, Description and a Footer control
per row is the Windows 11 Settings shape. Status messages use
`FAInfoBar`. Any row carrying an ACCOUNT affordance ships
`IsExpanded="True"`: sign-in hidden behind a chevron reads as "this
app has no account." (FluentAvalonia 3 prefixes these `FA`. The
unprefixed WinUI names do not resolve.)

---

## 6. Second-screen presenter window (optional module)

<!-- FILL: delete this section if the app never drives a second
     display. Keep it for any host, presenter, kiosk, or big-screen
     mode. -->

6.1 **The control surface.** [FILL IN: the keyboard map for the host.
Example: Space reveals, Left/Right move, digits jump, Esc holds the big
screen.] An Alt-mnemonic menu bar mirrors every action. **Taskbar
progress** shows the running state so a host with the window minimized
still sees it. **Global hotkeys** (`RegisterHotKey`) fire the main
actions even when the presenter window or a slideshow has focus.

6.2 **The presenter window is a SEPARATE chromeless top-level window**
on the second monitor: pick the non-primary `Screen`, set `Position =
screen.Bounds.Position` THEN `WindowState.FullScreen`,
`SystemDecorations="None"`, and hide the cursor. **It must survive
hot-plug.** Projectors connect and disconnect mid-session, so on a
display change re-query `Screens` and fall back to the primary (or a
"no second display" slide). Never vanish off-screen. Remember the
chosen monitor. All presenter text scales by viewport fraction (5.3).

6.3 **The presenter window never hijacks the only display.**
Auto-fullscreen is correct ONLY when a non-primary `Screen` exists.
With a single monitor, open a normal **decorated, resizable** window
the host can drag onto the projector. A chromeless fullscreen window on
the primary display covers the control surface with no title bar, no
taskbar entry, and no way out. Always `ShowInTaskbar`, and always bind
**Esc to leave fullscreen** so the big screen is never a trap.

6.4 **Control rows WRAP.** A dozen host buttons in a non-wrapping
`StackPanel` clip or collide the moment the window is anything but
maximized. Use a `WrapPanel` per group so they reflow onto another
line. A control the host cannot reach mid-session is a broken session.

---

## 7. Links and notifications

7.1 **Deep links land in an inbox.** Register `[appscheme]://` and the
https twin of every shared link (see `DEEP_LINKS.md`) so a shared link
opens the Windows app into a **deep-link inbox**. External entry
points never mutate the router directly (the cross-platform inbox
rule).

7.2 **Toasts** for the events a person would otherwise miss while the
window is in the background ([FILL IN: the events]), through
`DesktopNotifications.Avalonia` or the Store identity's native path.
Toasts need package identity (0.5).

---

## 8. Anti-patterns (never)

- A resized macOS or iOS layout, or reusing `NavigationSplitView`
  instead of `FANavigationView` (2.1).
- A landing pane that stays blank until the nav is clicked (2.1).
- A full-screen mode as an overlay over the nav instead of replacing
  the window content (2.3).
- A second engine or a re-derived data pipeline instead of the C# Core
  port and the shared contract (0.1, 3.1).
- Native AOT, or any step that forces a Windows build machine into the
  default pipeline (0.4).
- The `net10.0-windows` TFM on any project other than `AppName.Windows`
  (0.3).
- Win32 interop leaking into `AppName.Core` (0.2).
- A bare per-frame network image control for remote art (3.3).
- An inline history dump instead of the bounded dashboard (4.1).
- A full-width button next to another control in a row (3.4).
- Hand-added shadow padding at a card call site (5.2).
- Fixed-point big-screen text (5.3).
- An unpinned accent CTA, or an accent button on an accent surface
  (5.4).
- A presenter window that vanishes when the display is unplugged, or
  goes fullscreen-chromeless on a single-monitor machine (6.2, 6.3).
- A non-wrapping control row (6.4).
- Declaring "done" on the macOS Avalonia head without a headless PNG
  and a `windows-latest` CI check (0.6, 9).

---

## 9. The tests (before any surface ships)

1. **Competent-designer test.** Could someone rebuild the surface from
   one paragraph of this doc?
2. **Windows-idiom test.** Mica and caption, keyboard and Alt menus,
   taskbar and tray. Or is it a ported Mac window?
3. **Cross-build test.** Does `dotnet publish -r win-x64
   --self-contained` succeed from the Mac, with no AOT and no
   Windows-only dependency pulled into Core?
4. **Parity test.** Same verb as the other platforms, native idiom,
   PARITY.md row updated in the same change set.
5. **Headless-PNG test.** An `[AvaloniaFact]` renders the surface to
   PNG (`Read` it) at every window size that matters and in both theme
   variants. The visual-baseline gate
   (`windows/AppName.HeadlessTests/VisualBaseline.cs`) passes.
6. **Real-Windows test.** `windows-latest` CI builds, runs the headless
   capture, and (for Mica, chrome and snap) takes a desktop screenshot.
   Download the artifacts and look at them.
7. **Contract test.** The C# wire types pass the golden vectors against
   the Apple, Kotlin and JS twins.

---

## Open owner decisions

<!-- FILL: resolve these with the owner before the first Store
     submission. The defaults below are what Tidbits Trivia shipped. -->

1. **Distribution.** Default is **both**: the free Microsoft Store
   (MSIX, Microsoft re-signs it, no SmartScreen prompt, $0) plus a
   direct single-file `.exe` or Velopack installer on GitHub Releases
   (unsigned at first). Confirm the owner wants the Store listing and
   its review.
2. **Signing spend.** Default is **$0** (unsigned direct download plus
   the Store). Azure Artifact Signing at about $10 a month is a later,
   optional upgrade that removes SmartScreen from the direct download.
   Decide when there is an audience.
3. **First slice.** [FILL IN: which surface ships first. Recommend the
   one that is the reason Windows exists, so the platform proves its
   value early.]

The Windows app is done when a Windows person forgets it was built on
a Mac.
