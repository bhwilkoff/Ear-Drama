#!/usr/bin/env bash
# Cut a new dated catalog Release (catalog-YYYY-MM-DD) from a staged folder.
#
#     bash tools/cut_catalog_release.sh [--dry-run] <folder> <tag>
#
# The publish workflow restores the NEWEST dated Release's database and harvest
# cache (catalog-publish.yml, "Restore"), so a new harvest reaches the apps only
# through a new dated Release. The runbook is in catalog/README.md.
#
# The folder holds radio-catalog.sqlite.xz, harvest-cache.tar.xz, SHA256SUMS
# (every other file in it listed there too) and NOTES.md, the release notes,
# which are not uploaded. Every check runs before anything is written; --dry-run
# runs the checks and prints what it would do.
#
# It never overwrites. It refuses a tag that exists as a Release, a draft or a
# git tag, a tag that is not newer than every dated Release, and --clobber
# (docs/CI-FLEET.md: `gh release upload --clobber` deletes before it uploads,
# and a failed upload loses the asset). The Release is built as a draft, each
# asset checked against GitHub's own sha256 digest, and only then published.
set -uo pipefail

REPO=${REPO:-bhwilkoff/Ear-Drama}
HERE=$(cd "$(dirname "$0")" && pwd)
REQUIRED=(radio-catalog.sqlite.xz harvest-cache.tar.xz SHA256SUMS)
MAX_BYTES=2147483647                       # GitHub's per-asset ceiling is 2 GiB

die() { echo "refused: $*" >&2; exit 1; }

dry=0
args=()
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --clobber) die "--clobber deletes the published asset before uploading; this script never overwrites" ;;
    -*) die "unknown option $a" ;;
    *) args+=("$a") ;;
  esac
done
[ "${#args[@]}" -eq 2 ] || { echo "usage: cut_catalog_release.sh [--dry-run] <folder> <tag>" >&2; exit 2; }
dir=${args[0]%/}
tag=${args[1]}

# The tag: the form the workflow selects, and newer than every dated Release.
[[ "$tag" =~ ^catalog-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "tag $tag is not catalog-YYYY-MM-DD, the form the publish workflow restores from"
[ -d "$dir" ] || die "no folder $dir"

# The folder: required assets, every asset checksummed, nothing unlisted.
for f in "${REQUIRED[@]}" NOTES.md; do
  [ -s "$dir/$f" ] || die "$dir/$f is missing or empty"
done
listed=()
while read -r sum name; do
  [ -n "${sum:-}" ] || continue
  name=${name#\*}
  case "$name" in */*|""|SHA256SUMS|NOTES.md) die "SHA256SUMS lists '$name', which is not an asset" ;; esac
  [ -f "$dir/$name" ] || die "SHA256SUMS lists $name, which is not in $dir"
  listed+=("$name")
done < "$dir/SHA256SUMS"
assets=()
for p in "$dir"/* "$dir"/.[!.]*; do
  [ -e "$p" ] || continue
  b=$(basename "$p")
  [ -f "$p" ] || die "$b is not a regular file; the folder holds assets only"
  [ "$b" = NOTES.md ] && continue
  assets+=("$b")
  [ "$b" = SHA256SUMS ] && continue
  printf '%s\n' "${listed[@]}" | grep -qxF "$b" || die "$b is not listed in SHA256SUMS, so nothing would prove what was uploaded"
  [ "$(wc -c < "$p" | tr -d ' ')" -le "$MAX_BYTES" ] || die "$b is over GitHub's 2 GiB asset limit"
done
for f in radio-catalog.sqlite.xz harvest-cache.tar.xz; do
  printf '%s\n' "${listed[@]}" | grep -qxF "$f" || die "SHA256SUMS does not list $f"
done
if command -v sha256sum > /dev/null 2>&1; then sumtool=(sha256sum -c); else sumtool=(shasum -a 256 -c); fi
(cd "$dir" && "${sumtool[@]}" SHA256SUMS) || die "checksums do not match SHA256SUMS"
for f in "$dir"/*.xz; do
  xz -t "$f" || die "$(basename "$f") is not a whole xz stream"
done

# GitHub: the tag exists nowhere, and sorts after every dated Release.
if ! rel=$(gh api "repos/$REPO/releases" --paginate --jq '.[].tag_name' 2>&1); then
  die "cannot list the Releases of $REPO, so cannot prove $tag is new: $rel"
fi
printf '%s\n' "$rel" | grep -qxF "$tag" && die "a Release or draft named $tag already exists on $REPO"
if ref=$(gh api "repos/$REPO/git/ref/tags/$tag" 2>&1); then
  die "the git tag $tag already exists on $REPO"
elif ! printf '%s' "$ref" | grep -q "Not Found"; then
  die "cannot tell whether the git tag $tag exists: $ref"
fi
newest=$(printf '%s\n' "$rel" | grep -E '^catalog-[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | tail -1)
if [ -n "$newest" ] && [ "$(printf '%s\n%s\n' "$newest" "$tag" | sort | tail -1)" != "$tag" ]; then
  die "$tag is not newer than $newest, so the publish workflow would keep restoring $newest"
fi

echo "checked: ${assets[*]} in $dir; $tag is new on $REPO (newest dated: ${newest:-none})"
if [ "$dry" -eq 1 ]; then
  echo "dry run: would create draft $tag, upload ${#assets[@]} assets, check each digest, then publish it"
  exit 0
fi

draft_note="the draft $tag stays on $REPO; nothing restores from a draft. Delete it on the Releases page, then run this again"
bash "$HERE/gh_retry.sh" gh release create "$tag" -R "$REPO" --draft --title "Catalog ${tag#catalog-}" \
  --notes-file "$dir/NOTES.md" || die "creating the draft failed; if it was made, $draft_note"
n=$(gh api "repos/$REPO/releases" --paginate --jq '.[].tag_name' 2>&1 | grep -cxF "$tag")
[ "$n" = 1 ] || die "found $n Releases named $tag after creating one; $draft_note"
for f in "${assets[@]}"; do
  bash "$HERE/gh_retry.sh" gh release upload "$tag" -R "$REPO" "$dir/$f" || die "uploading $f failed; $draft_note"
done

# Each asset as GitHub stores it: name, size and sha256 digest against the folder.
got=$(gh release view "$tag" -R "$REPO" --json assets --jq '.assets[] | "\(.name) \(.size) \(.digest)"') \
  || die "cannot read back the assets; $draft_note"
for f in "${assets[@]}"; do
  size=$(wc -c < "$dir/$f" | tr -d ' ')
  sum=$( (sha256sum "$dir/$f" 2>/dev/null || shasum -a 256 "$dir/$f") | awk '{print $1}')
  printf '%s\n' "$got" | grep -qxF "$f $size sha256:$sum" || die "$f on GitHub is not $size bytes with sha256 $sum; $draft_note"
done
[ "$(printf '%s\n' "$got" | wc -l | tr -d ' ')" = "${#assets[@]}" ] || die "the draft holds assets the folder does not; $draft_note"

bash "$HERE/gh_retry.sh" gh release edit "$tag" -R "$REPO" --draft=false --latest \
  || die "publishing the draft failed; $draft_note"
echo "published $tag with ${#assets[@]} assets, each matched to GitHub's digest"
echo "next: gh workflow run catalog-publish.yml -R $REPO   # restores $tag"
