# Windows Store logo assets

The MSIX layout (`windows-store.yml`) copies `*.png` from this directory. Before
the first Store package, generate the seven tiles the AppxManifest references:

| File | Size |
|---|---|
| `StoreLogo.png` | 50×50 |
| `Square44x44Logo.png` | 44×44 |
| `Square71x71Logo.png` | 71×71 |
| `Square150x150Logo.png` | 150×150 |
| `Square310x310Logo.png` | 310×310 |
| `Wide310x150Logo.png` | 310×150 |
| `SplashScreen.png` | 620×300 |

Render them from `branding/` (the shared icon source) — e.g. `sips -z H W in.png
--out out.png` on the Mac, or a small Python/PIL script. Transparent background;
the tile background color comes from the manifest.
