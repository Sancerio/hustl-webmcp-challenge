#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/regenerate.sh HUSTL_REPOSITORY NEW_DESTINATION" >&2
  exit 64
fi

public_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
upstream_repo="$(CDPATH= cd -- "$1" && pwd)"
destination="$2"
expected_public_commit="$(git -C "$public_root" rev-parse HEAD)"
source_commit="$(sed -n 's/.*"sourceCommit": "\([0-9a-f]\{40\}\)".*/\1/p' "$public_root/config/source.json")"

[[ -n "$source_commit" ]] || { echo "invalid config/source.json" >&2; exit 65; }
[[ ! -e "$destination" ]] || { echo "destination already exists" >&2; exit 65; }
git -C "$upstream_repo" cat-file -e "$source_commit^{commit}"
mkdir -p "$destination/config"

while IFS=$'\t' read -r origin path; do
  [[ "$path" == lib/*.dart && "$path" != *'..'* ]] || {
    echo "unsafe source manifest path: $path" >&2; exit 65;
  }
  mkdir -p "$destination/$(dirname -- "$path")"
  case "$origin" in
    source) git -C "$upstream_repo" show "$source_commit:hustl_app/$path" > "$destination/$path" ;;
    overlay) cp "$public_root/$path" "$destination/$path" ;;
    *) echo "unknown source origin: $origin" >&2; exit 65 ;;
  esac
done < "$public_root/config/source_manifest.txt"

while IFS= read -r path; do
  [[ -n "$path" && "$path" != /* && "$path" != *'..'* ]] || {
    echo "unsafe static manifest path: $path" >&2; exit 65;
  }
  mkdir -p "$destination/$(dirname -- "$path")"
  cp "$public_root/$path" "$destination/$path"
done < "$public_root/config/static_manifest.txt"

cp "$public_root/config/source_manifest.txt" "$destination/config/source_manifest.txt"
cp "$public_root/config/static_manifest.txt" "$destination/config/static_manifest.txt"
cp "$public_root/config/public_manifest.sha256" "$destination/config/public_manifest.sha256"

(cd "$destination" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q --initial-branch=main)
(cd "$destination" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c core.hooksPath=/dev/null add .)
(
  cd "$destination"
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME='Hustl Public Export' \
  GIT_AUTHOR_EMAIL='public-export@localhost.invalid' \
  GIT_AUTHOR_DATE='2026-09-02T00:00:00Z' \
  GIT_COMMITTER_NAME='Hustl Public Export' \
  GIT_COMMITTER_EMAIL='public-export@localhost.invalid' \
  GIT_COMMITTER_DATE='2026-09-02T00:00:00Z' \
    git -c core.hooksPath=/dev/null -c commit.gpgSign=false \
      commit -q -m 'Initial public Hustl WebMCP evaluator'
)
(cd "$destination" && [[ "$(git rev-parse HEAD)" == "$expected_public_commit" ]]) || {
  echo 'regenerated Git commit does not match the source public repository' >&2
  exit 1
}
(cd "$destination" && bash scripts/verify.sh)
echo "regenerated $destination from $source_commit"
