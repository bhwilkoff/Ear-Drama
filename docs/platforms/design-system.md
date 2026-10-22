# The shared design system, in full

Read this before changing the look on any platform, adding a color, or
touching type, haptics, or icons. `AGENTS.md` keeps the rules, and this
page adds each platform's token files and the full type ramp.

These rules lived in `AGENTS.md` until October 3, 2026, when it was cut
below 24,000 bytes so that Antigravity, which stops reading a rule file
at that size, would read all of it. They moved here word for word, and
`AGENTS.md` links to this page with one line saying when to read it. The
rules that hold on every platform stayed in `AGENTS.md`.

## Shared design system

**Design tokens have one source: `design-tokens.json`** at the root. It
holds the palette (light and dark), the six-level type ramp, spacing, and
radius. `node tools/design_tokens.mjs` writes every platform's token file
from it, and `node tools/test_design_tokens.mjs` (in `tools/test_web.sh`
and the Design Tokens workflow) fails if any file drifts from the JSON or a
text pair drops below WCAG AA. To change the look: **edit
`design-tokens.json`, run the generator, then build and look at every
platform**, light and dark. Never hand-edit a generated file or a
`BEGIN design-tokens` block; the test will fail, and it should.

| Platform | Generated from the JSON | Reads it as |
|---|---|---|
| Web | the `:root` block in `css/styles.css`; theme-color metas in `index.html`; `manifest.json` colors | `var(--color-primary)`, `--type-page-title-size`, `--space-4`, `--radius-card` |
| Apple (iOS/iPadOS/macOS/tvOS) | `apple/Core/Design.swift`; `AccentColor.colorset` | `Color.brandPrimary` (never `Color.primary`, which SwiftUI already defines), `Color.semanticError`, `TypeRamp.pageTitle`, `Spacing.s4`, `Radius.card` |
| Android | `ui/theme/Color.kt`, `Type.kt`; `res/values{,-night}/colors.xml` | `MaterialTheme.colorScheme` (mapped in the hand-written `Theme.kt`), `AppSemantics.colors.error`, `Spacing.S4` |
| Windows | the two `design-tokens` blocks in `App.axaml`; the splash color in `AppxManifest.xml` | `{DynamicResource BrandPrimaryBrush}`, `RadiusCard`, the `TextBlock` ramp classes |
| Smart-TV web, Cast, webOS | the `html.tv` block in `tv.css`; the block in `cast/index.html`; `tv/webos/appinfo.json` | the dark palette (`--tv-bg`, `--tv-accent`), since TV is dark-first |

Two systems, kept distinct (Decision 012): **brand** colors (primary,
background, surface, text, border) are UI chrome only, and **semantic**
colors (success, warning, error) carry content meaning only. Never use a
brand color for content meaning or a semantic color for chrome. Add a
domain-specific semantic color to `color.semantic` in the JSON, and the
generator carries it to every platform.

**Typography hierarchy**: three weights × two sizes = six levels.
Refuse a seventh; refactor instead. See `mobile-first-density-design`
for the discipline.

| Level | Web class | iOS / macOS `Font.TextStyle` | tvOS | Android M3 token | Windows (`App.axaml`) |
|---|---|---|---|---|---|
| L1 Page title | `.view-heading` | `.largeTitle` | `.title1` (57pt) | `displaySmall` | `TextBlock.view-heading` |
| L2 Section header | `.section-header` | `.title2` | `.title3` (38pt) | `headlineSmall` | `.section-header` |
| L3 Emphasized body | `.body-strong` | `.headline` | `.headline` | `titleMedium` | `.body-strong` |
| L4 Body | `.body` | `.body` | `.body` (29pt, the 10-ft floor) | `bodyMedium` | `.body` |
| L5 Caption | `.caption` | `.caption` | `.caption1` (25pt) | `labelMedium` | `.caption` |
| L6 Tabular | `.tabular` | `.body.monospacedDigit()` | same | `bodySmall` w/ tabular | `.tabular` |

The sizes and weights live in `design-tokens.json` (`type`), and the
generator applies them on the web, Android, and Windows. Apple keeps the
system text styles so Dynamic Type works, with the JSON's weights.
macOS shares the iOS `Font.TextStyle` ramp (same Core `Design.swift`).
tvOS uses the same six levels but its own larger ramp: system tokens
only, never hardcoded sizes. 29pt is the body floor at ten feet.
tvOS 27 added Dynamic Type (`.scaledFont`); honor it behind `#available`
on 27 and keep the 29pt floor on 26.

**Density rule**: density comes from removing chrome, not adding
decoration. Test at 375px before 1440px. On tvOS the analogue is
**focus does the work**: the focused card is the chrome; surrounding
cards should be quiet, and brightness is reserved for the focused
element.

**Haptics (touch platforms)**: one semantic taxonomy, never ad-hoc
generators. `selection` (paging, toggles, segment changes) ·
`light`/`medium`/`heavy` (discrete actions by weight) ·
`success`/`warning`/`error` (operation outcomes). Two binding
pairings: `error` always accompanies a surfaced error banner;
`selection` always accompanies a page/segment change. Call sites name
the meaning; the platform mapping (`.sensoryFeedback` /
`UIFeedbackGenerator` on iOS, `HapticFeedback` on Android) lives in
one place. Don't sprinkle feedback where it adds noise.

**Icons vs. emoji (R-ICON-1)**: UI icons come from the platform icon
system: SF Symbols on Apple, Material Symbols on Android, inline SVG on
web. Emoji are **content** (a share grid, celebration copy, a data
string), never chrome. An emoji used as a button/nav icon renders
inconsistently across platforms and OS versions and reads as unpolished;
reach for the icon system every time.
