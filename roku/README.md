# Ear Drama on Roku (1.0 stub)

DECISIONS 056: Roku is a stub at 1.0. The channel builds and opens to one
screen, Listen: the "Most episodes" row and one row per genre shelf, read
from the web projection's `index/listen.json` and `manifest.json`
(docs/CATALOG-CONTRACT.md §4), the same files eardrama.org serves. Until the
data is live there, the channel shows "This did not load." with Try again.
Selecting a series only logs `ED select: <key>` to the console; Series,
Detail, the player, and search come later from the core's design.

## Build

    bash roku/build.sh                     # data from https://eardrama.org/data/
    ED_DATA_BASE=http://<mac-ip>:8431/data/ bash roku/build.sh

The second form points a development build at a Mac on the LAN serving
`catalog/out/web` (`python3 tools/devserve.py 8431` from a checkout with the
`data` symlink). A launch parameter overrides the base without a rebuild:
`/launch/dev?data=<url-encoded base>` over ECP.

Output: `roku/dist/EarDrama-roku-<version>.zip`, version from
`AppVersion.xcconfig`. Checks: `python3 tools/roku_design_lint.py`, and
BrighterScript's compiler for syntax, undefined names, and component script
includes: `npx -p brighterscript bsc --rootDir build/roku/stage --createPackage false`.

## Owner steps

- Put the Roku in Developer mode (Home x3, Up x2, Right, Left, Right, Left,
  Right), set its password, then upload the zip at `http://<roku-ip>`
  (or `ROKU_DEV_PASS=… python3 tools/roku_run.py deploy --dir build/roku/stage`).
- A Roku developer account is needed only to publish, not to sideload.

## Placeholders

Every file below is a PLACEHOLDER from `tools/make_tv_stub_art.py` and says
so on its face. Replace each with final art at the same name and size
before any submission:

| File | Size | Slot |
|---|---|---|
| `images/poster_fhd.png` | 540x405 | channel poster, FHD |
| `images/poster_hd.png` | 290x218 | channel poster, HD |
| `images/splash_fhd.png` | 1920x1080 | splash, FHD |
| `images/splash_hd.png` | 1280x720 | splash, HD |

`images/ring.9.png`, `images/pill.9.png`, and `images/spinner.png` are the
channel's own design (focus ring, button, loading), not placeholders. The
fonts are Public Sans (SIL OFL 1.1, `fonts/LICENSE.txt`).
