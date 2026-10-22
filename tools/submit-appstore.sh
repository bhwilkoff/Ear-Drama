#!/usr/bin/env bash
# Build + upload an App Store archive for ONE Apple platform from the command line (no Xcode GUI).
#   tools/submit-appstore.sh mac      → macOS  (.pkg)
#   tools/submit-appstore.sh ios      → iOS + iPadOS (.ipa)
#   tools/submit-appstore.sh tvos     → tvOS   (.ipa)
#   tools/submit-appstore.sh all      → mac, then ios, then tvos
#
# NOTE: needs `chmod +x tools/submit-appstore.sh` once (git preserves the bit thereafter).
#
# Setup: a RELEASED Xcode (App Review rejects beta builds), the App Store Connect API key in
# tools/asc-credentials.env (gitignored) + ~/.appstoreconnect/private_keys/. See docs/CLOUD-SUBMISSION.md.
#
# Signing is MANUAL, by design: cloud-managed/automatic signing can fail for a team's ASC API key
# ("Cloud signing permission error"), but the SAME key can create certs + profiles via the REST API.
# So this script ensures an Apple Distribution cert (+ a Mac Installer cert for macOS) exists, creates
# an App Store provisioning profile per embedded bundle id (tools/asc_profiles.py), writes a manual
# ExportOptions, and exports + uploads. Re-running is safe (profiles are recreated by name).
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:?usage: submit-appstore.sh <mac|ios|tvos|all>}"
if [ "$PLATFORM" = "all" ]; then
  for p in mac ios tvos; do "$0" "$p"; done
  exit 0
fi

# ============================ PER-APP CONFIG (edit these per template instance) ==================
# PROJECT     — the repo-root .xcodeproj, generated from project.yml (`xcodegen generate`).
# BID_FILTER  — a substring that matches ALL of THIS app's bundle ids (main app + any extensions).
#               NOTE: iOS, tvOS, and macOS can (and here do) SHARE ONE App Store Connect record via
#               a single bundle id like `com.example.appname`; extensions add a suffix, which the
#               substring still matches.
# SCHEME      — the Xcode scheme per platform. The universal iOS/tvOS target usually shares ONE
#               scheme (`AppName`); a macOS build is often a SEPARATE scheme — set it below.
# ORG / TEAM  — the org name EXACTLY as it appears in your signing certs, and your 10-char Team ID.
PROJECT="AppName.xcodeproj"
BID_FILTER="com.example.appname"
ORG="${ASC_ORG_NAME:-<ORG_NAME>}"          # e.g. "Acme, Inc." — must match the cert's O= exactly
TEAM="${ASC_TEAM_ID:?set ASC_TEAM_ID (your 10-char Apple Team ID)}"
case "$PLATFORM" in
  mac)  SCHEME="AppName"; DEST="generic/platform=macOS"; PKG=1 ;;   # ← if macOS is a separate scheme, set it here
  ios)  SCHEME="AppName"; DEST="generic/platform=iOS";   PKG=0 ;;
  tvos) SCHEME="AppName"; DEST="generic/platform=tvOS";  PKG=0 ;;
  *) echo "unknown platform '$PLATFORM' (use mac|ios|tvos|all)"; exit 1 ;;
esac
# ================================================================================================

# --- released Xcode (newest non-beta) -----------------------------------------------------------
resolve_dev() {
  if [ -n "${DEVELOPER_DIR:-}" ]; then printf '%s\n' "$DEVELOPER_DIR"; return; fi
  local sel; sel="$(xcode-select -p 2>/dev/null)"
  case "$sel" in *[Bb]eta*) : ;; */Contents/Developer) printf '%s\n' "$sel"; return ;; esac
  local app
  for app in $(ls -d /Applications/Xcode*.app 2>/dev/null | grep -iv beta | sort -rV); do
    printf '%s\n' "$app/Contents/Developer"; return
  done
  printf '%s\n' "/Applications/Xcode.app/Contents/Developer"
}
DEV="$(resolve_dev)"; export DEVELOPER_DIR="$DEV"
case "$DEV" in *[Bb]eta*) echo "REFUSING beta Xcode ($DEV) — App Review rejects beta builds."; exit 1;; esac
[ -x "$DEV/usr/bin/xcodebuild" ] || { echo "No released Xcode at $DEV — run: xcodes install <NN>"; exit 1; }

# --- credentials --------------------------------------------------------------------------------
[ -f "tools/asc-credentials.env" ] && { set -a; . "tools/asc-credentials.env"; set +a; }
: "${ASC_KEY_ID:?set ASC_KEY_ID}"; : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
KEY="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$KEY" ] || { echo "Missing API key at $KEY"; exit 1; }
AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$KEY")

# --- platform support present? (the device SDK is a separate Xcode component download) -----------
if ! "$DEV/usr/bin/xcodebuild" -showdestinations -project "$PROJECT" \
      -scheme "$SCHEME" 2>/dev/null | grep -qiE "platform:${PLATFORM/mac/macOS}.*name:Any"; then
  : # best-effort; xcodebuild reports the real "not installed" error if missing
fi
# Metal toolchain — only needed if the app ships a .metal shader; Xcode ships it as a separate component.
"$DEV/usr/bin/xcrun" --find metal >/dev/null 2>&1 || { echo "Installing Metal toolchain (~700MB)…"; xcodebuild -downloadComponent MetalToolchain; }

# The project is generated output (gitignored); make sure it exists and matches project.yml.
if [ -f project.yml ]; then
  command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
  xcodegen generate --quiet
fi

VERSION="$(grep -E '^MARKETING_VERSION' AppVersion.xcconfig | sed 's/.*= *//')"
BUILD="$(grep   -E '^CURRENT_PROJECT_VERSION' AppVersion.xcconfig | sed 's/.*= *//')"
echo "[$PLATFORM] $SCHEME $VERSION ($BUILD) | $(/usr/bin/xcodebuild -version | tr '\n' ' ') | $DEV"

ARCH="build/${PLATFORM}.xcarchive"
EXPORT="build/${PLATFORM}-export"
rm -rf "$ARCH" "$EXPORT"

echo "[$PLATFORM] archiving…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -destination "$DEST" -archivePath "$ARCH" archive \
  DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates "${AUTH[@]}"

# --- the embedded bundle ids (main app + extensions) --------------------------------------------
APP="$(ls -d "$ARCH"/Products/Applications/*.app 2>/dev/null | head -1)"
[ -n "$APP" ] || { echo "no .app in $ARCH"; exit 1; }
BIDS=$(find "$APP" -name Info.plist 2>/dev/null | while read -r p; do
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$p" 2>/dev/null; done | grep "$BID_FILTER" | sort -u)
echo "[$PLATFORM] bundle ids: $(echo "$BIDS" | tr '\n' ' ')"

# --- a Python that can import PyJWT (asc_certs/asc_profiles sign the ASC API JWT with it) --------
# Homebrew's python3 is externally-managed (PEP 668) and routinely lacks PyJWT, which used to make
# the cert step die "ModuleNotFoundError: No module named 'jwt'". Fall back to a dedicated venv,
# creating it on first need. Only asc_certs/asc_profiles need jwt; the inline `python3 -c` (json) don't.
PY=python3
if ! python3 -c 'import jwt' 2>/dev/null; then
  VENV="tools/.asc-venv"
  if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c 'import jwt' 2>/dev/null; then
    echo "[$PLATFORM] PyJWT not in python3 — provisioning $VENV (PyJWT + cryptography)…"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q PyJWT cryptography
  fi
  PY="$VENV/bin/python"
fi

# --- the Apple Distribution cert id (manual signing needs it; create if absent) -----------------
# CI override: when ASC_DIST_CERT_ID is set, the cert+key were imported from a .p12 into the runner's
# keychain (a beta-macOS dev box can't ship locally — ITMS-90301 — so the cloud appstore-build.yml
# workflow drives this path). Use that cert id directly and skip find/create; the installer cert is
# likewise imported from a .p12, and the ExportOptions reference both by name.
if [ -n "${ASC_DIST_CERT_ID:-}" ]; then
  DIST_CERT_ID="$ASC_DIST_CERT_ID"
  echo "[$PLATFORM] using CI signing cert $DIST_CERT_ID (imported .p12)"
else
  DIST_CERT_ID="$("$PY" tools/asc_certs.py distribution)"
  [ -n "$DIST_CERT_ID" ] || { echo "could not resolve/create Apple Distribution cert"; exit 1; }
  if [ "$PKG" = 1 ]; then "$PY" tools/asc_certs.py mac_installer >/dev/null; fi
fi

# --- App Store profiles for every bundle id, then a manual ExportOptions -------------------------
PJSON="$("$PY" tools/asc_profiles.py "$PLATFORM" "$DIST_CERT_ID" $BIDS)"
PLIST="$EXPORT-ExportOptions.plist"; mkdir -p "$(dirname "$PLIST")"
INSTALLER=""
[ "$PKG" = 1 ] && INSTALLER="  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer: $ORG ($TEAM)</string>"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0"><dict>'
  echo '  <key>method</key><string>app-store-connect</string>'
  echo '  <key>destination</key><string>upload</string>'
  echo "  <key>teamID</key><string>$TEAM</string>"
  echo '  <key>signingStyle</key><string>manual</string>'
  echo "  <key>signingCertificate</key><string>Apple Distribution: $ORG ($TEAM)</string>"
  echo "$INSTALLER"
  echo '  <key>manageAppVersionAndBuildNumber</key><false/>'
  echo '  <key>provisioningProfiles</key><dict>'
  echo "$PJSON" | python3 -c "import json,sys
for k,v in json.load(sys.stdin).items(): print(f'    <key>{k}</key><string>{v}</string>')"
  echo '  </dict>'
  echo '</dict></plist>'
} > "$PLIST"

echo "[$PLATFORM] exporting + uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$ARCH" -exportPath "$EXPORT" \
  -exportOptionsPlist "$PLIST" -allowProvisioningUpdates "${AUTH[@]}"

echo "✓ [$PLATFORM] uploaded $VERSION ($BUILD)."
# Uploading is not shipping, and finishing the job is not the owner's job either: nobody opens
# App Store Connect to press Submit. appstore-build.yml runs asc_release.py ship straight after
# this (it waits for the build to go VALID, then attaches + submits); by hand it is one command.
echo "  Next: tools/asc_release.py ship --platform $PLATFORM --submit --notes-file <whats-new.txt> --wait-build-minutes 40"
echo "  (appstore-build.yml already does this unless it was dispatched with submit=false or no notes)."
