#!/usr/bin/env bash
# Assemble the LG webOS (.ipk) and Samsung Tizen (.wgt) packages from the ONE
# shared web app at the repo root (docs/TV-DESIGN.md §7.1, Decision 047).
#
# There is no separate TV codebase: this copies the same index.html / watch.js /
# watch.css / tv.js / tv.css the browser serves, drops in the per-platform
# manifest + icons, and hands off to the vendor CLI. If you ever find yourself
# editing a file inside tv/webos/app or tv/tizen/app, stop — the change belongs
# upstream in the shared app.
#
# Prerequisites (owner, one-time — see docs/TV-PLATFORM-BACKLOG.md §OWNER):
#   webOS : the webOS TV CLI (ares-package) — webostv.developer.lge.com
#   Tizen : Tizen Studio CLI (tizen build-web / tizen package) + a signing
#           certificate. KEEP THAT CERTIFICATE — Samsung requires every update
#           to be signed with the same one.
#
# Usage:  ./tv/build-tv-packages.sh [webos|tizen|all]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/tv/dist"
TARGET="${1:-all}"

# The shared app payload. Keep this list in sync with sw.js SHELL_URLS — both
# describe "what the app is made of".
APP_FILES=(index.html tv.css tv.js manifest.json)
APP_DIRS=(assets)
# From js/ the viewer needs ONLY api.js. app.js and whats-new.js belong to the
# curator dashboard at /curate/ — dead weight in a TV package, and webOS's
# packager aborts trying to minify them.
APP_JS=(js/compat.js js/api.js js/app.js js/cast-sender.js)
APP_CSS=(css/styles.css)

# One source of truth for the version, the same file the Apple targets read
# (Decision 003). Both vendor manifests are STAMPED at package time rather than
# hand-edited, because they drifted immediately: the .ipk shipped 1.3.284 while
# the app was 1.3.309, and a store will happily accept a wrongly-versioned
# package and then refuse the next upload as "not newer".
VERSION="$(sed -n 's/^MARKETING_VERSION = //p' "$ROOT/AppVersion.xcconfig" | tr -d ' \r')"
if [ -z "$VERSION" ]; then
  echo "!! could not read MARKETING_VERSION from AppVersion.xcconfig" >&2
  exit 1
fi
echo "Version: $VERSION"

# Samsung 2022 sets run Chromium 85 (Tizen 6.5). Refuse to package code they
# cannot run: a raised required_version would drop a model year silently.
python3 "$ROOT/tools/test_tv_compat.py" >&2 || { echo "!! TV code uses a feature 2022 TVs lack" >&2; exit 1; }

stage() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  for f in "${APP_FILES[@]}"; do
    [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$dest/" || echo "  (skip missing $f)"
  done
  for d in "${APP_DIRS[@]}"; do
    [ -d "$ROOT/$d" ] && cp -R "$ROOT/$d" "$dest/" || true
  done
  for f in "${APP_JS[@]}"; do
    mkdir -p "$dest/$(dirname "$f")"
    [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$dest/$f" || echo "  (skip missing $f)"
  done
  mkdir -p "$dest/css"
  for f in "${APP_CSS[@]}"; do cp "$ROOT/$f" "$dest/css/"; done
  # macOS turds ship inside the package otherwise. Removed here rather than via
  # ares-package -e, whose pattern did not match a nested assets/.DS_Store.
  find "$dest" -name '.DS_Store' -delete
  # The service worker is deliberately NOT packaged: a packaged TV app already
  # stores its resources locally, and a stale SW inside the package would shadow
  # the packaged files. Network data still comes from archivewatch.org, which
  # watch.js reaches because PAGES_ROOT falls back to the canonical origin under
  # file:// — do not "simplify" that back to a relative URL.
  rm -f "$dest/sw.js"
  # If the app registers a service worker, it must guard registration by
  # protocol (a packaged TV app runs under file:// and a rejected register()
  # fires on every launch). Assert it when the main script is present.
  MAIN_JS="$dest/js/app.js"
  if [ -f "$MAIN_JS" ] && grep -q 'serviceWorker' "$MAIN_JS" \
     && ! grep -qE "serviceWorker.+https?" "$MAIN_JS"; then
    echo "  !! app.js registers a service worker without a protocol guard" >&2
    exit 1
  fi
}

build_webos() {
  echo "==> webOS"
  local app="$ROOT/tv/webos/app"
  stage "$app"
  sed "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$VERSION\"/" \
    "$ROOT/tv/webos/appinfo.json" > "$app/appinfo.json"
  cp "$ROOT/tv/webos/icon.png" "$ROOT/tv/webos/largeIcon.png" \
     "$ROOT/tv/webos/splash.png" "$app/"
  mkdir -p "$OUT"
  if command -v ares-package >/dev/null 2>&1; then
    # -n / --no-minify (undocumented in --help, present since 3.x). The CLI
    # bundles uglify-js, which cannot parse modern syntax (optional chaining,
    # nullish coalescing) and aborts the whole package. This app is deliberately
    # no-build-step vanilla (Decision 001), so minification is neither expected
    # nor wanted — and letting an old minifier rewrite working code is a risk,
    # not an optimisation.
    ares-package -n -e ".DS_Store" "$app" -o "$OUT"
    echo "    .ipk -> $OUT"
  else
    echo "    ares-package not installed — staged only at $app"
    echo "    Install the webOS TV CLI, then: ares-package $app -o $OUT"
  fi
}

# DEBUG HOOK for a retail Samsung set, which offers no shell, no screenshot and
# no log. With APP_TV_INSPECT=<this Mac's ip>:8080 (and `chii start -p 8080`
# running), the package loads Chii's target script so tools/tv_inspect.mjs,
# tv_press.mjs and tv_walk.mjs can drive and read the app ON the TV. A widget
# with no CSP of its own runs only its own scripts, so the debug package names
# the inspector host; the store package declares none. Never upload a -debug.wgt.
debug_hooks() {
  local dest="$1"
  [ -n "${APP_TV_INSPECT:-}" ] || return 0
  sed -i '' "s#<head>#<head><script src=\"http://${APP_TV_INSPECT}/target.js\"></script>#" "$dest/index.html"
  sed -i '' "s#</widget>#  <tizen:content-security-policy>default-src * data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' file: 'unsafe-inline' 'unsafe-eval' http://${APP_TV_INSPECT}; connect-src * ws: wss:</tizen:content-security-policy>\n</widget>#" "$dest/config.xml"
  echo "    inspector hook -> http://${APP_TV_INSPECT}/target.js"
}

build_tizen() {
  echo "==> Tizen"
  local app="$ROOT/tv/tizen/app"
  stage "$app"
  sed "s/version=\"[0-9][^\"]*\"/version=\"$VERSION\"/" \
    "$ROOT/tv/tizen/config.xml" > "$app/config.xml"
  cp "$ROOT/tv/tizen/icon.png" "$app/"
  debug_hooks "$app"
  mkdir -p "$OUT"
  if command -v tizen >/dev/null 2>&1; then
    tizen build-web -- "$app"
    # tizen build-web emits into <app>/.buildResult
    tizen package -t wgt -o "$OUT" -- "$app/.buildResult"
    if [ -n "${APP_TV_INSPECT:-}" ]; then
      for w in "$OUT"/*.wgt; do
        case "$w" in *-debug.wgt) ;; *) mv "$w" "${w%.wgt}-debug.wgt" ;; esac
      done
      echo "    DEBUG package (never upload this)"
    fi
    echo "    .wgt -> $OUT"
  else
    echo "    tizen CLI not installed — staged only at $app"
    echo "    Install Tizen Studio CLI, create a signing certificate, then:"
    echo "      tizen build-web -- $app"
    echo "      tizen package -t wgt -o $OUT -- $app/.buildResult"
  fi
}

case "$TARGET" in
  webos) build_webos ;;
  tizen) build_tizen ;;
  all)   build_webos; build_tizen ;;
  *)     echo "usage: $0 [webos|tizen|all]" >&2; exit 2 ;;
esac

echo "Done."
