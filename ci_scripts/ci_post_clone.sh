#!/bin/sh
# Xcode Cloud: runs after cloning the repo, before building.
#
# The .xcodeproj is generated from project.yml and gitignored, so a fresh
# clone has none. Generate it here, before Xcode Cloud looks for it.
#
# Available environment variables:
#   CI_PRIMARY_REPOSITORY_PATH  path to the cloned repo
#   CI_PRODUCT                  product name
#   CI_BRANCH                   branch being built
#   CI_BUILD_NUMBER             auto-incrementing build number
set -e

echo "ci_post_clone: build #${CI_BUILD_NUMBER:-local} on ${CI_BRANCH:-unknown}"

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
