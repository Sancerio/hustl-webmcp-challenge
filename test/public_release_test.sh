#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")/.." && pwd)"

bash "$package_dir/scripts/scan_public_source.sh" "$package_dir"
node "$package_dir/scripts/verify_workflow_pins.mjs" \
  "$package_dir/.github"
LC_ALL=C sort -c "$package_dir/public_manifest.txt"

actual_files="$(mktemp "${TMPDIR:-/tmp}/hustl-public-files.XXXXXX")"
cleanup_files() {
  rm -f "$actual_files"
}
trap cleanup_files EXIT
git -C "$package_dir" ls-files --cached --others --exclude-standard -- . \
  | LC_ALL=C sort > "$actual_files"
if ! cmp -s "$package_dir/public_manifest.txt" "$actual_files"; then
  echo "Public source tree does not exactly match public_manifest.txt." >&2
  diff -u "$package_dir/public_manifest.txt" "$actual_files" || true
  exit 1
fi

for required in \
  .github/CODEOWNERS \
  .github/workflows/ci.yml \
  CONTRIBUTING.md \
  LICENSE \
  README.md \
  RELEASING.md \
  SECURITY.md \
  THIRD_PARTY_NOTICES.md \
  assets/fonts/OFL-DMSans.txt \
  assets/fonts/OFL-NotoSansSymbols.txt; do
  test -f "$package_dir/$required"
done

grep -Fq 'DM Sans' "$package_dir/THIRD_PARTY_NOTICES.md"
grep -Fq 'Noto Sans Symbols' "$package_dir/THIRD_PARTY_NOTICES.md"
grep -Fq "node-version: '22.23.2'" \
  "$package_dir/.github/workflows/ci.yml"
grep -Fq 'fetch-depth: 0' "$package_dir/.github/workflows/ci.yml"
grep -Fq 'include-hidden-files: true' \
  "$package_dir/.github/workflows/ci.yml"
grep -Fxq '.vercel' "$package_dir/.gitignore"
grep -Fq '! -path "$PACKAGE_DIR/.vercel/*"' \
  "$package_dir/scripts/verify.sh"
grep -Fq 'version=3.38.7' \
  "$package_dir/scripts/install_flutter_ci.sh"
grep -Fq '2d72de31119ccba1421391aa9ab53891a3e4905987a13f8272766ad78e3bbf93' \
  "$package_dir/scripts/install_flutter_ci.sh"
grep -Fq 'version=8.30.1' \
  "$package_dir/scripts/install_gitleaks.sh"
grep -Fq '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb' \
  "$package_dir/scripts/install_gitleaks.sh"
canary="$(mktemp -d "${TMPDIR:-/tmp}/hustl-public-scan-canary.XXXXXX")"
cleanup() {
  rm -rf "$canary"
  cleanup_files
}
trap cleanup EXIT
printf 'endpoint=https://private-example.%s\n' 'vercel.app' > "$canary/config.txt"
if bash "$package_dir/scripts/scan_public_source.sh" "$canary" >/dev/null 2>&1; then
  echo "Public source scanner failed its forbidden-origin canary." >&2
  exit 1
fi
printf 'AWS_ACCESS_KEY_ID=%s%s\n' 'AKIA' '1234567890ABCDEF' \
  > "$canary/config.txt"
if bash "$package_dir/scripts/scan_public_source.sh" "$canary" >/dev/null 2>&1; then
  echo "Public source scanner failed its AWS credential canary." >&2
  exit 1
fi
printf 'GITHUB_TOKEN=%s%s\n' 'ghp_' 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN' \
  > "$canary/config.txt"
if bash "$package_dir/scripts/scan_public_source.sh" "$canary" >/dev/null 2>&1; then
  echo "Public source scanner failed its GitHub credential canary." >&2
  exit 1
fi
printf 'OPENAI_API_KEY=%s%s\n' 'sk-proj-' 'abcdefghijklmnopqrstuvwxyz123456' \
  > "$canary/config.txt"
if bash "$package_dir/scripts/scan_public_source.sh" "$canary" >/dev/null 2>&1; then
  echo "Public source scanner failed its OpenAI credential canary." >&2
  exit 1
fi
printf 'harmless=true\n' > "$canary/config.txt"
printf 'harmless=true\n' > "$canary/credentials.env"
if bash "$package_dir/scripts/scan_public_source.sh" "$canary" >/dev/null 2>&1; then
  echo "Public source scanner failed its credential-filename canary." >&2
  exit 1
fi
rm "$canary/credentials.env"

mkdir "$canary/workflows"
printf 'jobs:\n  unsafe:\n    uses: actions/checkout@%s\n' 'v4' \
  > "$canary/workflows/unsafe.yml"
if node "$package_dir/scripts/verify_workflow_pins.mjs" \
  "$canary/workflows" >/dev/null 2>&1; then
  echo "Workflow pin verifier accepted a mutable action tag." >&2
  exit 1
fi
printf 'jobs:\n  unsafe:\n    uses: ./ci/local\n' \
  > "$canary/workflows/unsafe.yml"
if node "$package_dir/scripts/verify_workflow_pins.mjs" \
  "$canary/workflows" >/dev/null 2>&1; then
  echo "Workflow pin verifier accepted an unverified local action." >&2
  exit 1
fi

mkdir "$canary/build"
printf 'synthetic evaluator artifact\n' > "$canary/build/index.html"
bash "$package_dir/scripts/create_artifact_manifest.sh" \
  "$canary/build" "$canary/artifacts" >/dev/null
test -s "$canary/artifacts/build.sha256"
test -s "$canary/artifacts/provenance.json"
(
  cd "$canary/build"
  shasum -a 256 -c "$canary/artifacts/build.sha256" >/dev/null
)
node - "$canary/artifacts/provenance.json" <<'NODE'
const fs = require('node:fs');
const provenance = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (provenance.schemaVersion !== 1) process.exit(1);
if (!/^[0-9a-f]{40}$/i.test(provenance.sourceCommit)) process.exit(1);
if (!/^\d+\.\d+\.\d+/.test(provenance.flutterVersion)) process.exit(1);
if (!/^v\d+\.\d+\.\d+/.test(provenance.nodeVersion)) process.exit(1);
if (provenance.fileCount !== 1) process.exit(1);
if (!/^[0-9a-f]{64}$/.test(provenance.manifestSha256)) process.exit(1);
if (typeof provenance.runner !== 'object' || provenance.runner === null) {
  process.exit(1);
}
NODE

node - "$package_dir/assets/data/exercises.json" <<'NODE'
const fs = require('node:fs');
const fixtures = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!Array.isArray(fixtures) || fixtures.length !== 16) process.exit(1);
const ids = new Set();
for (const fixture of fixtures) {
  const keys = Object.keys(fixture).sort().join(',');
  if (keys !== 'id,loggingMode,muscles,name,slug') process.exit(1);
  if (ids.has(fixture.id)) process.exit(1);
  ids.add(fixture.id);
}
NODE

echo "Public governance and release tests passed."
