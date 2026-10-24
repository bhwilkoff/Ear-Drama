# Fonts/

`BigShoulders-Bold.ttf` is the display face for the page title and section
headers (L1, L2; Decision 060). Body text stays the system face. The file is
built by `tools/build_fonts.py` from the OFL master in `branding/fonts/`;
never edit it here. Its license is `OFL-BigShoulders.txt`, bundled beside it.

- Registered in `Resources/EarDrama-Info.plist`: `UIAppFonts` (iOS, tvOS) and
  `ATSApplicationFontsPath` (macOS).
- Read only through `TypeRamp.pageTitle` / `TypeRamp.sectionHeader` in
  `Core/Design.swift`, which `tools/design_tokens.mjs` writes from
  `design-tokens.json` (`font.display.apple`).
