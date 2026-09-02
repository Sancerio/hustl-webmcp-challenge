#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-$PACKAGE_DIR/build/web}"

test -f "$BUILD_DIR/index.html"
test -f "$BUILD_DIR/runtime_guard.js"
test -f "$BUILD_DIR/webmcp_bridge.js"
test -f "$BUILD_DIR/vercel.json"
test ! -e "$BUILD_DIR/flutter_service_worker.js"
test ! -e "$BUILD_DIR/.last_build_id"
test -f "$BUILD_DIR/assets/notosanssymbols/v43/rP2up3q65FkAtHfwd-eIS2brbDN6gxP34F9jRRCe4W3gfQ8gb_VFRkzrbQ.woff2"
for legal_file in \
  THIRD_PARTY_NOTICES.md \
  OFL-DMSans.txt \
  OFL-NotoSansSymbols.txt; do
  test -f "$BUILD_DIR/legal/$legal_file"
done
cmp -s "$PACKAGE_DIR/THIRD_PARTY_NOTICES.md" \
  "$BUILD_DIR/legal/THIRD_PARTY_NOTICES.md"
cmp -s "$PACKAGE_DIR/assets/fonts/OFL-DMSans.txt" \
  "$BUILD_DIR/legal/OFL-DMSans.txt"
cmp -s "$PACKAGE_DIR/assets/fonts/OFL-NotoSansSymbols.txt" \
  "$BUILD_DIR/legal/OFL-NotoSansSymbols.txt"
cmp -s "$PACKAGE_DIR/vercel.json" "$BUILD_DIR/vercel.json"
grep -Fq '_flutter.loader.load({config:{fontFallbackBaseUrl:"assets/"}});' \
  "$BUILD_DIR/flutter_bootstrap.js"
! grep -Fq '_flutter.loader.load();' "$BUILD_DIR/flutter_bootstrap.js"

guard_line="$(grep -n 'runtime_guard.js' "$BUILD_DIR/index.html" | cut -d: -f1)"
gate_line="$(grep -n 'bootstrap_gate.js' "$BUILD_DIR/index.html" | cut -d: -f1)"
test "$guard_line" -lt "$gate_line"
! grep -q 'src="flutter_bootstrap.js"' "$BUILD_DIR/index.html"

if rg -n --hidden \
  'hustl-two\.vercel\.app|hustlbackend\.vercel\.app|hustl-mcp-server\.vercel\.app|api\.hustl\.app|supabase\.co|accounts\.google\.com' \
  "$PACKAGE_DIR" \
  -g '!build/**' -g '!.dart_tool/**' -g '!pubspec.lock'; then
  echo "Forbidden external origin found in evaluator source." >&2
  exit 1
fi

if rg -n 'package:hustl_app|\.\./hustl_app|path:[[:space:]]*.*hustl_app' \
  "$PACKAGE_DIR" -g '!build/**' -g '!.dart_tool/**' \
  -g '!scripts/verify.sh'; then
  echo "Standalone evaluator depends on the private app." >&2
  exit 1
fi

LC_ALL=C sort -c "$PACKAGE_DIR/public_manifest.txt"
while IFS= read -r file; do
  test -f "$PACKAGE_DIR/$file" || {
    echo "Manifest file missing: $file" >&2
    exit 1
  }
done < "$PACKAGE_DIR/public_manifest.txt"

actual_files="$(mktemp "${TMPDIR:-/tmp}/hustl-evaluator-files.XXXXXX")"
reviewed_files="$(mktemp "${TMPDIR:-/tmp}/hustl-evaluator-manifest.XXXXXX")"
cleanup_manifest_check() {
  rm -f "$actual_files" "$reviewed_files"
}
trap cleanup_manifest_check EXIT

find "$PACKAGE_DIR" -type f \
  ! -path "$PACKAGE_DIR/.dart_tool/*" \
  ! -path "$PACKAGE_DIR/.git" \
  ! -path "$PACKAGE_DIR/.git/*" \
  ! -path "$PACKAGE_DIR/.playwright-cli/*" \
  ! -path "$PACKAGE_DIR/.vercel/*" \
  ! -path "$PACKAGE_DIR/build/*" \
  ! -path "$PACKAGE_DIR/coverage/*" \
  ! -name '.flutter-plugins' \
  ! -name '.flutter-plugins-dependencies' \
  ! -name '.packages' \
  -print | sed "s#^$PACKAGE_DIR/##" | LC_ALL=C sort > "$actual_files"
LC_ALL=C sort "$PACKAGE_DIR/public_manifest.txt" > "$reviewed_files"
if ! cmp -s "$actual_files" "$reviewed_files"; then
  echo "Public manifest does not exactly match evaluator source files:" >&2
  diff -u "$reviewed_files" "$actual_files" >&2 || true
  exit 1
fi

echo "Standalone evaluator isolation checks passed."
