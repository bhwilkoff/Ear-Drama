#!/usr/bin/env bash
# Restore the caches the play library's pictures are read from (catalog/tools/play_art.py) out of the newest dated
# catalog Release, before a play library build. B31 C1: the library was built on a Mac with no art_v2 cache and
# attach returned every row bare, so the published index carried no picture at all.
#
#     bash tools/restore_play_art_caches.sh [CACHE_DIR]     # default catalog/.cache
#
# The Release's harvest-cache.tar.xz is downloaded once per tag (checked against its SHA256SUMS) and only the five
# folders play_art reads are taken from it: art_v2, people_wd, loc, commons, series_art. They are merged into
# CACHE_DIR file by file, and a file already there is never overwritten (that cache is shared with every other
# harvest on this machine, and may be newer than the Release): what was added and what was kept is printed.
# A marker (.restored-<tag>) skips the download next time. Exits 1 when, after it, there is still no
# art_v2/plays.json.gz: play_art.attach would refuse the build anyway, and this says why sooner.
set -uo pipefail

REPO=${REPO:-bhwilkoff/Ear-Drama}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CACHE=${1:-$ROOT/catalog/.cache}
FOLDERS=(art_v2 people_wd loc commons series_art)
die() { echo "refused: $*" >&2; exit 1; }

mkdir -p "$CACHE" || die "cannot make $CACHE"
# PLAY_ART_TAG names the Release instead of asking GitHub for the newest (the tests' planted cache).
tag=${PLAY_ART_TAG:-}
[ -n "$tag" ] || tag=$(gh release list -R "$REPO" --limit 100 --exclude-drafts --json tagName \
  --jq '[.[].tagName | select(test("^catalog-[0-9]{4}-[0-9]{2}-[0-9]{2}$"))] | sort | last // empty') \
  || die "could not list the catalog Releases"
[ -n "$tag" ] || die "no dated catalog Release (catalog-YYYY-MM-DD) to restore the picture caches from"

if [ -e "$CACHE/.restored-$tag" ]; then
  echo "picture caches: already restored from $tag ($CACHE/.restored-$tag)"
else
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  echo "picture caches: restoring from $tag"
  bash "$HERE/gh_retry.sh" gh release download "$tag" -R "$REPO" -D "$work" -p harvest-cache.tar.xz -p SHA256SUMS \
    || die "downloading harvest-cache.tar.xz from $tag failed"
  (cd "$work" && shasum -a 256 -c --ignore-missing SHA256SUMS) || die "harvest-cache.tar.xz does not match $tag's SHA256SUMS"
  mkdir -p "$work/x"
  python3 -I - "$work/harvest-cache.tar.xz" "$work/x" "${FOLDERS[@]}" <<'PY' || die "harvest-cache.tar.xz did not unpack"
import sys, tarfile
src, dest, *names = sys.argv[1:]
with tarfile.open(src, "r:xz") as t:
    members = [m for m in t.getmembers() if m.name.split("/")[0] in names and (m.isreg() or m.isdir())]
    t.extractall(dest, members=members, filter="data")
print(f"  {sum(m.isreg() for m in members)} files in {', '.join(names)}")
PY
  for d in "${FOLDERS[@]}"; do
    [ -d "$work/x/$d" ] || { echo "  $d: not in the Release"; continue; }
    total=$(find "$work/x/$d" -type f | wc -l | tr -d ' ')
    added=$(rsync -a --ignore-existing --out-format='%n' "$work/x/$d/" "$CACHE/$d/" | grep -vc '/$')
    kept=$((total - added))
    differ=0
    if [ "$kept" -gt 0 ]; then
      differ=$( (cd "$work/x/$d" && find . -type f) | while read -r f; do
        cmp -s "$work/x/$d/$f" "$CACHE/$d/$f" || echo "$f"; done | wc -l | tr -d ' ')
    fi
    echo "  $d: added $added of $total; kept $kept already here, never overwritten ($differ of them differ from the Release's copy)"
  done
  touch "$CACHE/.restored-$tag"
fi
[ -s "$CACHE/art_v2/plays.json.gz" ] || die "no art_v2/plays.json.gz in $CACHE after the restore: the library would carry no picture"
echo "picture caches ready in $CACHE"
