#!/usr/bin/env bash
# Pre-merge check for any change under catalog/: restore the newest dated catalog
# Release, rebuild, build the projections, and run catalog-publish.yml's
# "Contract tests over the real artifacts", publishing nothing. The steps are
# read from the workflow, not copied. Usage: bash tools/catalog_dryrun.sh [--with-suites] [--keep]
set -euo pipefail
exec python3 "$(dirname "$0")/catalog_dryrun.py" "$@"
