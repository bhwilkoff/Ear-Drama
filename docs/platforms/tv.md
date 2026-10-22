# The television platforms beyond Apple TV

Read this before expanding to Android TV, Fire TV, webOS, Tizen, Cast,
or Roku. Apple TV's rules are in [apple.md](apple.md), and the store-by-
store overview is [`docs/TV-PLATFORMS.md`](../TV-PLATFORMS.md).

These rules lived in `AGENTS.md` until October 3, 2026, when it was cut
below 24,000 bytes so that Antigravity, which stops reading a rule file
at that size, would read all of it. They moved here word for word, and
`AGENTS.md` links to this page with one line saying when to read it. The
rules that hold on every platform stayed in `AGENTS.md`.

## Which skill

- **Android TV / Fire TV**: `androidtv-compose-focus`: tv-material
  only, the runtime `UiModeManager` branch (never a fork), the focus
  contract, the Google TV quality gates, and the Fire TV zero-GMS
  flavor rule.
- **Smart-TV web (webOS / Tizen / Cast)**: `smarttv-web-app`: the
  additive `tv.js`/`tv.css` layer over the vanilla web app, the
  spatial-navigation engine, per-platform shims, `.ipk`/`.wgt`
  packaging from the one shared root. Vendor overview + store
  process: `docs/TV-PLATFORMS.md`.
- **Roku**: `roku-brightscript-app`. Start from `smart-tv-platform-expansion`,
  which sequences every TV platform, and use `ten-foot-detail-design` for
  any Detail, Series, or Search screen.
