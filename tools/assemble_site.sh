#!/usr/bin/env bash
# Assemble the Pages site: everything the repo root served when Pages read
# main, minus the app sources and the pipeline (not the website), plus the web
# projection under /data/ and the castable plays beside it, and the share
# pages (catalog/tools/build_share_pages.py). Shared by
# catalog-publish.yml (fresh projection) and site-deploy.yml (the last one).
#
#     bash tools/assemble_site.sh <web projection dir> <output dir>
set -euo pipefail
web="$1"; out="$2"
rm -rf "$out"; mkdir -p "$out"
rsync -a --exclude='/.git' --exclude='/.github' --exclude='/.claude' --exclude='/.agents' \
  --exclude='/.devcontainer' --exclude='/apple' --exclude='/android' --exclude='/windows' \
  --exclude='/catalog' --exclude='/tools' --exclude='/ci_scripts' --exclude='/docs' \
  --exclude='/worker' --exclude='/build' --exclude='/EarDrama.xcodeproj' --exclude='node_modules' --exclude='/built' --exclude='/live' --exclude='/vendor' --exclude="/$(basename "$out")" ./ "$out/"
cp -R "$web" "$out/data"
mkdir -p "$out/data/plays"
cp catalog/plays/castable-scripts.json "$out/data/plays/"
# The full play library (Decision 075): index.json + scripts/<id>.json. A run that built one uses it;
# every other run downloads the newest dated asset of the `plays-library` Release
# (tools/refresh_play_library.sh uploads it). Either way it must pass the shape check, or the build stops:
# the deploy never ships an empty or partial shelf.
if [ ! -s catalog/out/plays-library/index.json ]; then
  python3 tools/fetch_play_library.py catalog/out/plays-library
fi
python3 catalog/tools/check_play_library.py catalog/out/plays-library
mkdir -p "$out/data/plays/library"
cp -R catalog/out/plays-library/. "$out/data/plays/library/"
# The castable manifest the Worker reads (docs/WORKER.md "Castable only"): one row a play, made here from the
# very scripts being deployed, then checked against them, so a library refresh needs no Worker deploy.
node worker/tools/castable-manifest.mjs --library "$out/data/plays/library"
# The web's Kokoro voice model (Decision 078): the fp32 model in parts under 50 MB, the voice table and the
# vocabulary, from the newest kokoro-vN-web-manifest.json on the `kokoro-model` Release
# (tools/publish_kokoro_model.py). Every file is checked against the manifest and the Release, or the build stops.
python3 tools/fetch_kokoro_model.py "$out/data/kokoro"
# The ONNX Runtime those voices run on, from our own origin (Decision 084, R3d T1: no third-party script
# at runtime): the pinned npm tarball, checked against its SHA-512 integrity, or the build stops.
python3 tools/fetch_onnx_runtime.py "$out/vendor/onnxruntime-web"
# A real page at every served /series/{key} and /episode/{id}, so a preview bot reads a 200 with a
# card; a path it does not write stays with 404.html.
# The finished ear dramas come from the Worker's open listing; if it cannot be read, the drama
# pages wait for the next deploy and 404.html still routes /drama/{id} into the app.
finished="$(mktemp)"
curl -fsS --max-time 20 "${FINISHED_URL:-https://eardrama-api.benwilkoff.workers.dev/v1/plays/finished?limit=50}" -o "$finished" || echo '{}' > "$finished"
python3 catalog/tools/build_share_pages.py "$web" "$out" --finished "$finished"
# SHELL_VERSION comes from the shell itself (WEB-DESIGN §10.1), never a hand bump.
node tools/stamp_shell_version.mjs "$out"
# .nojekyll is empty by design: it must exist, not have size.
test -e "$out/.nojekyll" || { echo "::error::$out/.nojekyll is missing; not deploying"; exit 1; }
for f in index.html 404.html CNAME manifest.json css/styles.css js/app.js \
         .well-known/apple-app-site-association .well-known/assetlinks.json \
         data/manifest.json data/index/series.json data/plays/castable-scripts.json data/plays/library/index.json \
         data/plays/library/phonemes-report.json data/kokoro/manifest.json \
         vendor/onnxruntime-web/ort.webgpu.min.js vendor/onnxruntime-web/ort-wasm-simd-threaded.asyncify.wasm \
         .well-known/security.txt privacy/index.html schools/index.html security/index.html; do
  test -s "$out/$f" || { echo "::error::$out/$f is missing or empty; not deploying"; exit 1; }
done
echo "site files: $(find "$out" -type f | wc -l); data files: $(find "$out/data" -type f | wc -l); $(du -sh "$out" | cut -f1)"
