#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

find . -type f \
  ! -path './.git/*' \
  ! -path './.dart_tool/*' \
  ! -path './.playwright-cli/*' \
  ! -path './build/*' \
  ! -path './lib/*.dart' \
  ! -path './lib/**/*.dart' \
  ! -path './config/source_manifest.txt' \
  ! -path './config/static_manifest.txt' \
  ! -path './config/public_manifest.sha256' \
  -print | sed 's#^./##' | LC_ALL=C sort > config/static_manifest.txt

{
  find . -type f \
    ! -path './.git/*' \
    ! -path './.dart_tool/*' \
    ! -path './.playwright-cli/*' \
    ! -path './build/*' \
    ! -path './config/public_manifest.sha256' \
    -print | sed 's#^./##' | LC_ALL=C sort
} | while IFS= read -r path; do
  shasum -a 256 "$path"
done > config/public_manifest.sha256

echo "updated config/static_manifest.txt and config/public_manifest.sha256"
