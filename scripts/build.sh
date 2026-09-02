#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PACKAGE_DIR"

flutter pub get
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
node "$PACKAGE_DIR/scripts/patch_flutter_bootstrap.mjs" \
  "$PACKAGE_DIR/build/web/flutter_bootstrap.js"

worker="$PACKAGE_DIR/build/web/flutter_service_worker.js"
if [[ -s "$worker" ]]; then
  echo "A non-empty service worker was generated." >&2
  exit 1
fi
rm -f "$worker"
rm -f "$PACKAGE_DIR/build/web/.last_build_id"

cp "$PACKAGE_DIR/evaluator_assets/runtime_guard.js" \
  "$PACKAGE_DIR/build/web/runtime_guard.js"
mkdir -p "$PACKAGE_DIR/build/web/assets/notosanssymbols/v43"
cp "$PACKAGE_DIR/evaluator_assets/font_fallback/notosanssymbols/v43/"*.woff2 \
  "$PACKAGE_DIR/build/web/assets/notosanssymbols/v43/"
cp "$PACKAGE_DIR/vercel.json" "$PACKAGE_DIR/build/web/vercel.json"
mkdir -p "$PACKAGE_DIR/build/web/legal"
cp "$PACKAGE_DIR/THIRD_PARTY_NOTICES.md" \
  "$PACKAGE_DIR/build/web/legal/THIRD_PARTY_NOTICES.md"
cp "$PACKAGE_DIR/assets/fonts/OFL-DMSans.txt" \
  "$PACKAGE_DIR/build/web/legal/OFL-DMSans.txt"
cp "$PACKAGE_DIR/assets/fonts/OFL-NotoSansSymbols.txt" \
  "$PACKAGE_DIR/build/web/legal/OFL-NotoSansSymbols.txt"

bash "$PACKAGE_DIR/scripts/verify.sh" "$PACKAGE_DIR/build/web"
echo "Standalone evaluator built at $PACKAGE_DIR/build/web"
