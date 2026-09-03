#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

expected_commit='f52fd2196a5e77c6eb8083df0342ed68d46aeee4'
actual_commit="$(sed -n 's/.*"sourceCommit": "\([0-9a-f]\{40\}\)".*/\1/p' config/source.json)"
[[ "$actual_commit" == "$expected_commit" ]] || {
  echo "FAIL: unexpected source commit $actual_commit" >&2; exit 1;
}

if find . -type l ! -path './.git/*' -print -quit | grep -q .; then
  echo 'FAIL: symlinks are not allowed' >&2; exit 1
fi

awk -F '\t' '
  NF != 2 || ($1 != "source" && $1 != "overlay") || $2 !~ /^lib\/.*\.dart$/ || $2 ~ /\.\./ { exit 1 }
' config/source_manifest.txt || { echo 'FAIL: invalid source manifest' >&2; exit 1; }

for forbidden in \
  'lib/core/auth/' 'lib/core/api/' 'lib/core/analytics/' \
  'lib/core/telemetry/' 'lib/core/storage/token' 'lib/core/supabase/' \
  '.env' 'google-services.json' 'GoogleService-Info.plist'; do
  if rg -n -F "$forbidden" config/source_manifest.txt config/static_manifest.txt >/dev/null; then
    echo "FAIL: forbidden path in manifest: $forbidden" >&2; exit 1
  fi
done

if rg -n --hidden \
  --glob '!.git/**' --glob '!.dart_tool/**' --glob '!.playwright-cli/**' --glob '!build/**' \
  --glob '!scripts/verify.sh' \
  "(https?://[^[:space:]\"'<>]*(hustlbackend|hustl-two|hustl-mcp-server|supabase\\.co)|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk_live_[A-Za-z0-9]+)" .; then
  echo 'FAIL: private origin or secret-shaped value found' >&2; exit 1
fi

shasum -a 256 -c config/public_manifest.sha256 >/dev/null || {
  echo 'FAIL: public manifest mismatch' >&2; exit 1;
}

actual_files="$(mktemp)"
expected_files="$(mktemp)"
trap 'rm -f "$actual_files" "$expected_files"' EXIT
find . -type f \
  ! -path './.git/*' \
  ! -path './.dart_tool/*' \
  ! -path './.playwright-cli/*' \
  ! -path './build/*' \
  ! -path './.flutter-plugins-dependencies' \
  ! -path './config/public_manifest.sha256' \
  -print | sed 's#^./##' | LC_ALL=C sort > "$actual_files"
cut -c 67- config/public_manifest.sha256 | LC_ALL=C sort > "$expected_files"
diff -u "$expected_files" "$actual_files" >/dev/null || {
  echo 'FAIL: unlisted or missing public file' >&2; exit 1;
}

if [[ -n "${HUSTL_SOURCE_REPO:-}" ]]; then
  git -C "$HUSTL_SOURCE_REPO" cat-file -e "$expected_commit^{commit}"
  while IFS=$'\t' read -r origin path; do
    if [[ "$origin" == source ]]; then
      git -C "$HUSTL_SOURCE_REPO" show "$expected_commit:hustl_app/$path" | cmp -s - "$path" || {
        echo "FAIL: source mismatch: $path" >&2; exit 1;
      }
    fi
  done < config/source_manifest.txt
fi

[[ -d .git ]] || { echo 'FAIL: disconnected Git repository is required' >&2; exit 1; }
[[ "$(git rev-list --count --all)" == 1 ]] || {
  echo 'FAIL: public repository must have one root commit' >&2; exit 1;
}
[[ "$(git symbolic-ref --short HEAD)" == main ]] || {
  echo 'FAIL: public repository branch must be main' >&2; exit 1;
}
expected_commit_metadata='Hustl Public Export|public-export@localhost.invalid|2026-09-02T00:00:00Z|Hustl Public Export|public-export@localhost.invalid|2026-09-02T00:00:00Z|Initial public Hustl WebMCP evaluator|N'
actual_commit_metadata="$(git show -s --format='%an|%ae|%aI|%cn|%ce|%cI|%s|%G?' HEAD)"
[[ "$actual_commit_metadata" == "$expected_commit_metadata" ]] || {
  echo 'FAIL: public root commit metadata or signing is not deterministic' >&2; exit 1;
}
[[ -z "$(git remote)" ]] || { echo 'FAIL: Git remotes are not allowed' >&2; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
  echo 'FAIL: public repository is not clean' >&2; exit 1;
}
[[ -z "$(git fsck --unreachable --no-reflogs 2>/dev/null)" ]] || {
  echo 'FAIL: unreachable Git objects found' >&2; exit 1;
}

if [[ -f build/web/index.html ]]; then
  rg -q 'evaluator_runtime_guard\.js' build/web/index.html || {
    echo 'FAIL: built index lacks runtime guard' >&2; exit 1;
  }
  [[ ! -f build/web/flutter_service_worker.js ]] || {
    echo 'FAIL: service worker must be absent' >&2; exit 1;
  }
fi

echo "PASS: isolated public evaluator at $expected_commit"
