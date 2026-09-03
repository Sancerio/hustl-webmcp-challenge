#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo 'usage: reconstruct-candidate.sh DESTINATION' >&2
  exit 64
fi

publication_root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
destination="$1"
expected_candidate='3a412f5843c7098047673b393e04926e17872527'
expected_source='f52fd2196a5e77c6eb8083df0342ed68d46aeee4'

[[ ! -e "$destination" ]] || {
  echo "destination already exists: $destination" >&2
  exit 65
}
mkdir -p "$destination/config"

while read -r digest path; do
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || {
    echo "invalid digest in public manifest: $digest" >&2
    exit 65
  }
  [[ -n "$path" && "$path" != /* && "$path" != *'..'* ]] || {
    echo "unsafe public manifest path: $path" >&2
    exit 65
  }
  mkdir -p "$destination/$(dirname -- "$path")"
  cp "$publication_root/$path" "$destination/$path"
done < "$publication_root/config/public_manifest.sha256"
cp "$publication_root/config/public_manifest.sha256" "$destination/config/public_manifest.sha256"

actual_source="$(sed -n 's/.*"sourceCommit": "\([0-9a-f]\{40\}\)".*/\1/p' "$destination/config/source.json")"
[[ "$actual_source" == "$expected_source" ]] || {
  echo "unexpected pinned source commit: $actual_source" >&2
  exit 1
}

(
  cd "$destination"
  shasum -a 256 -c config/public_manifest.sha256
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q --initial-branch=main
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c core.hooksPath=/dev/null add .
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
  [[ "$(git rev-parse HEAD)" == "$expected_candidate" ]] || {
    echo 'reconstructed candidate commit does not match the frozen candidate' >&2
    exit 1
  }
  bash scripts/verify.sh
)

echo "PASS: reconstructed frozen candidate $expected_candidate from source $expected_source"
