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
  --exclude='/worker' --exclude='/build' --exclude='/EarDrama.xcodeproj' --exclude='node_modules' --exclude='/built' --exclude='/live' --exclude="/$(basename "$out")" ./ "$out/"
cp -R "$web" "$out/data"
mkdir -p "$out/data/plays"
cp catalog/plays/castable-scripts.json "$out/data/plays/"
# A real page at every served /series/{key} and /episode/{id}, so a preview bot reads a 200 with a
# card; a path it does not write stays with 404.html.
python3 catalog/tools/build_share_pages.py "$web" "$out"
# .nojekyll is empty by design: it must exist, not have size.
test -e "$out/.nojekyll" || { echo "::error::$out/.nojekyll is missing; not deploying"; exit 1; }
for f in index.html 404.html CNAME manifest.json css/styles.css js/app.js \
         .well-known/apple-app-site-association .well-known/assetlinks.json \
         data/manifest.json data/index/series.json data/plays/castable-scripts.json; do
  test -s "$out/$f" || { echo "::error::$out/$f is missing or empty; not deploying"; exit 1; }
done
echo "site files: $(find "$out" -type f | wc -l); data files: $(find "$out/data" -type f | wc -l); $(du -sh "$out" | cut -f1)"
