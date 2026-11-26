#!/usr/bin/env bash
# Rebuild the castable play library and publish it as a dated Release asset.
#
#     bash tools/refresh_play_library.sh [--no-upload] [--no-harvest]
#
# rsync harvest (every rights-cleared Gutenberg play's text, one rsync session) -> the picture caches from the newest
# dated catalog Release (tools/restore_play_art_caches.sh: adds what is missing, never overwrites) -> build
# (catalog/tools/build_play_library.py, which runs the phoneme step, build_play_phonemes.py, in
# catalog/.venv-phonemes: bash catalog/tools/setup_phoneme_env.sh once) -> tests
# (catalog/tests/test_play_library.py, test_play_phonemes.py with the phoneme env's python) -> pack ->
# upload `plays-library-YYYY-MM-DD.tar.xz` to the rolling `plays-library` Release -> check the Release's own
# size and sha256 against the file. tools/assemble_site.sh downloads the newest asset at the next site build
# (tools/fetch_play_library.py), so a refresh reaches the site on the next deploy, with no workflow edit, and the
# castable manifest (what can be shared, read together, or cast) is made from it there: no Worker deploy.
#
# It never overwrites: a same-day rebuild uploads as -2, -3 (docs/CI-FLEET.md: `gh release upload --clobber`
# deletes before it uploads, and a failed upload loses the asset). Nothing is uploaded unless every step before
# it passed. --no-upload stops after the pack; --no-harvest reuses the text cache already on disk.
set -uo pipefail

REPO=${REPO:-bhwilkoff/Ear-Drama}
TAG=plays-library
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
die() { echo "refused: $*" >&2; exit 1; }

upload=1; harvest=1
for a in "$@"; do
  case "$a" in
    --no-upload) upload=0 ;;
    --no-harvest) harvest=0 ;;
    *) die "unknown option $a" ;;
  esac
done

cd "$ROOT/catalog" || die "no catalog/ beside tools/"
if [ "$harvest" = 1 ]; then
  python3 tools/harvest_gutenberg_plays.py --rsync-castable || die "harvest failed"
fi
[ -x .venv-phonemes/bin/python ] || die "no phoneme environment: run bash catalog/tools/setup_phoneme_env.sh"
# The pictures (play_art) are read from the catalog Release's harvest cache: without it every row was published bare.
bash "$HERE/restore_play_art_caches.sh" "$ROOT/catalog/.cache" || die "the picture caches are not restored"
python3 tools/build_play_library.py || die "build failed"
python3 tests/test_play_library.py || die "play library tests failed"
.venv-phonemes/bin/python tests/test_play_phonemes.py || die "phoneme tests failed"
python3 tools/check_play_library.py || die "shape check failed"
python3 -c "import json; s = json.load(open('out/plays-library/phonemes-report.json'))['summary']; print('phonemes:', {k: s[k] for k in ('plays', 'with_phonemes', 'words', 'guessed', 'guessed_share', 'rule', 'dictionary')})"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
day=$(date -u +%Y-%m-%d)
existing=$(gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name' 2>/dev/null || true)
name="plays-library-$day.tar.xz"; n=1
while printf '%s\n' "$existing" | grep -qx "$name"; do n=$((n + 1)); name="plays-library-$day-$n.tar.xz"; done
python3 tools/play_library_archive.py pack out/plays-library "$work/$name" || die "pack failed"
python3 tools/play_library_archive.py unpack "$work/$name" "$work/check" || die "the packed archive does not unpack clean"
# The site build makes the castable manifest from this archive; a play the Worker would refuse stops here, not there.
node "$ROOT/worker/tools/castable-manifest.mjs" --library "$work/check" || die "the castable manifest does not build from it"
echo "packed $name: $(wc -c < "$work/$name" | tr -d ' ') bytes"
[ "$upload" = 1 ] || { cp "$work/$name" "$ROOT/$name"; echo "--no-upload: left $ROOT/$name"; exit 0; }

if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  bash "$HERE/gh_retry.sh" gh release create "$TAG" -R "$REPO" --latest=false --title "Play library (rolling)" \
    --notes "Dated plays-library-YYYY-MM-DD.tar.xz assets built by tools/refresh_play_library.sh. The site build (tools/assemble_site.sh) unpacks the newest. Contract: docs/CATALOG-CONTRACT.md 4.1." \
    || die "creating the $TAG release failed"
fi
bash "$HERE/gh_retry.sh" gh release upload "$TAG" -R "$REPO" "$work/$name" || die "uploading $name failed"
got=$(gh release view "$TAG" -R "$REPO" --json assets --jq ".assets[] | select(.name == \"$name\") | \"\(.size) \(.digest)\"") \
  || die "could not read $name back from the release"
want="$(wc -c < "$work/$name" | tr -d ' ') sha256:$(shasum -a 256 "$work/$name" | cut -d' ' -f1)"
[ "$got" = "$want" ] || die "release says '$got', file is '$want'"
echo "published $name to https://github.com/$REPO/releases/tag/$TAG ($got)"
