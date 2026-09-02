#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: verify_gitleaks.sh <gitleaks-bin> <source-root> [build-root]" >&2
  exit 64
fi

gitleaks_bin="$1"
source_root="$(cd "$2" && pwd -P)"
trusted_config="$source_root/config/gitleaks.toml"
build_root=""
if [[ $# -eq 3 ]]; then
  build_root="$(cd "$3" && pwd -P)"
fi

test -x "$gitleaks_bin"
test "$("$gitleaks_bin" version)" = 8.30.1
test -f "$trusted_config"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/hustl-gitleaks.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT
empty_ignore="$scratch/empty.gitleaksignore"
: > "$empty_ignore"
scanner_args=(
  --config "$trusted_config"
  --gitleaks-ignore-path "$empty_ignore"
  --ignore-gitleaks-allow
  --no-banner
  --redact
)

current_canary="$scratch/current"
history_canary="$scratch/history"
mkdir "$current_canary" "$history_canary"
cat > "$current_canary/.gitleaks.toml" <<'TOML'
[[allowlists]]
description = "Target-controlled configuration must not suppress scans"
paths = ['''.*''']
TOML
printf 'api_key = "%s%s"\n' 'a9F4kLm2Qp7R' 'x8Vn3Tz6Wc1Y' \
  > "$current_canary/credential.txt"
printf 'gitlab_token = "%s%s" # %s\n' 'glpat-' 'AbCdEfGhIjKlMnOpQrSt' \
  'gitleaks:allow' >> "$current_canary/credential.txt"
mkdir -p "$current_canary/lib/core/services"
{
  printf 'class PreferencesService {\n'
  printf '%s%s%s\n' \
    '  static const String _keyPrFlagsRecomputedV1 = ' \
    "'pr_flags_" "recomputed_v1';"
  printf '}\n'
} > "$current_canary/lib/core/services/preferences_service.dart"
set +e
"$gitleaks_bin" dir "${scanner_args[@]}" --report-format json \
  --report-path "$scratch/current.json" "$current_canary" >/dev/null 2>&1
current_status=$?
set -e
if [[ "$current_status" -ne 1 ]]; then
  echo "Gitleaks current-source canary was not detected." >&2
  exit 1
fi
node -e '
const fs = require("node:fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(report) || report.length < 3) process.exit(1);
if (!report.some(item =>
  item.File.endsWith("lib/core/services/preferences_service.dart") &&
  item.StartLine === 2
)) process.exit(1);
' "$scratch/current.json"

git -C "$history_canary" init -q
git -C "$history_canary" config user.name 'Hustl Scanner Canary'
git -C "$history_canary" config user.email 'scanner-canary@hustl.invalid'
git -C "$history_canary" config commit.gpgsign false
cp "$current_canary/.gitleaks.toml" "$history_canary/.gitleaks.toml"
printf 'api_key = "%s%s"\n' 'b8G5mNk3Rs9U' 'y7Wp4Xa2Zd6C' \
  > "$history_canary/credential.txt"
printf 'gitlab_token = "%s%s" # %s\n' 'glpat-' 'TuVwXyZaBcDeFgHiJkLm' \
  'gitleaks:allow' >> "$history_canary/credential.txt"
git -C "$history_canary" add .gitleaks.toml credential.txt
git -C "$history_canary" commit -qm 'add scanner canary'
printf 'credential removed\n' > "$history_canary/credential.txt"
git -C "$history_canary" add credential.txt
git -C "$history_canary" commit -qm 'remove scanner canary'
set +e
"$gitleaks_bin" git "${scanner_args[@]}" --report-format json \
  --report-path "$scratch/history.json" "$history_canary" >/dev/null 2>&1
history_status=$?
set -e
if [[ "$history_status" -ne 1 ]]; then
  echo "Gitleaks removed-history canary was not detected." >&2
  exit 1
fi
node -e '
const fs = require("node:fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(report) || report.length < 2) process.exit(1);
' "$scratch/history.json"

"$gitleaks_bin" dir "${scanner_args[@]}" "$source_root"
"$gitleaks_bin" git "${scanner_args[@]}" "$source_root"
if [[ -n "$build_root" ]]; then
  "$gitleaks_bin" dir "${scanner_args[@]}" "$build_root"
fi

echo "Gitleaks source, history, and build gates passed."
