#!/usr/bin/env bash
# B31 mock pictures: the files play_art.py would serve for four plays (Commons, archive.org), and two from the
# Gutenberg book's own HTML (sample_book_images.py saved them under $1). Resized to 480 px, kept small.
#     bash docs/research/design/b31-proto/fetch_mock_images.sh BOOKIMG_DIR
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p img
UA="ear-drama-research/1.0 (one-off design mock)"
get() { curl -sfL -A "$UA" -o "$1" "$2"; sleep 2; }
get img/howhelied-title.jpg "https://archive.org/download/howheliedtoherhu00shaw/page/n6_w800.jpg"
get img/candida-1924.jpg "https://commons.wikimedia.org/wiki/Special:FilePath/Cornell-de-Cordoba-Candida-1924.jpg?width=480"
get img/majorbarbara.png "https://commons.wikimedia.org/wiki/Special:FilePath/Major_Barbara_01.PNG?width=480"
get img/strindberg.jpg "https://commons.wikimedia.org/wiki/Special:FilePath/August_Strindberg_%28Bj%C3%B6rkman_1912%29.jpg?width=480"
get img/lysistrata-title.jpg "https://commons.wikimedia.org/wiki/Special:FilePath/Title_page_first_editions_of_Lysistrata_of_Aristophanes%2C_1516.jpg?width=480" || true
cp "$1/59421/0-frontispiece.jpg" img/chushingura-front.jpg
cp "$1/68576/0-coversmall.jpg" img/poorjack-cover.jpg
for f in img/*; do magick "$f" -resize '480x480>' -strip -quality 78 "${f%.*}.jpg"; done
rm -f img/majorbarbara.png
file img/*
