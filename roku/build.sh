#!/usr/bin/env bash
# Build Ear Drama's Roku channel into a sideload zip (DECISIONS 056: a stub).
#
# Stages the channel's files into build/roku/stage with the manifest's version
# stamped from AppVersion.xcconfig (one version everywhere), then zips it with
# tools/roku_run.py's walk, which puts the manifest at the archive root (Roku
# refuses a zip whose manifest sits in a folder).
#
#   bash roku/build.sh                         # data from https://eardrama.org/data/
#   ED_DATA_BASE=http://192.168.1.20:8431/data/ bash roku/build.sh
#                                              # a Mac on the LAN serving catalog/out/web
#
# Output: roku/dist/EarDrama-roku-<version>.zip. Sideload it at http://<roku-ip>
# (Developer mode), or: python3 tools/roku_run.py deploy --dir build/roku/stage
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/build/roku/stage"
OUT="$ROOT/roku/dist"

VERSION="$(sed -n 's/^MARKETING_VERSION = //p' "$ROOT/AppVersion.xcconfig" | tr -d ' \r')"
IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
if [ -z "${MAJOR:-}" ] || [ -z "${MINOR:-}" ] || [ -z "${PATCH:-}" ]; then
  echo "!! could not read MARKETING_VERSION from AppVersion.xcconfig" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT"
for d in source components images fonts; do
  cp -R "$ROOT/roku/$d" "$STAGE/"
done
find "$STAGE" -name '.DS_Store' -delete

sed -e "s/^major_version=.*/major_version=$MAJOR/" \
    -e "s/^minor_version=.*/minor_version=$MINOR/" \
    -e "s/^build_version=.*/build_version=$PATCH/" \
    "$ROOT/roku/manifest" > "$STAGE/manifest"
if [ -n "${ED_DATA_BASE:-}" ]; then
  sed -i '' "s#^ed_data_base=.*#ed_data_base=$ED_DATA_BASE#" "$STAGE/manifest"
  echo "data base: $ED_DATA_BASE (development build)"
fi

# The font license travels with the fonts (SIL OFL 1.1); the walk below skips
# .md files, so it ships as .txt.
[ -f "$STAGE/fonts/LICENSE.txt" ] || { echo "!! roku/fonts/LICENSE.txt missing" >&2; exit 1; }

ZIP="$OUT/EarDrama-roku-$VERSION.zip"
python3 "$ROOT/tools/roku_run.py" zip --dir "$STAGE" --out "$ZIP"
unzip -l "$ZIP" | tail -n +4 | awk 'NF==4 && $4 != "Name" {print "    " $4}' || true
echo "Done: $ZIP"
