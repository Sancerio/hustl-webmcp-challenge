#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFINE_FILE="$APP_DIR/config/webmcp_evaluator.defines.json"
VERCEL_CONFIG="$APP_DIR/vercel.evaluator.json"
FLUTTER_DIR="$APP_DIR/.flutter"
if [[ ! -f "$VERCEL_CONFIG" ]]; then
  VERCEL_CONFIG="$APP_DIR/vercel.json"
fi

if [[ ! -f "$DEFINE_FILE" ]]; then
  echo "Evaluator defines are missing: $DEFINE_FILE" >&2
  exit 1
fi

if grep -Eq 'hustl-two\.vercel\.app|hustlbackend\.vercel\.app|hustl-mcp-server\.vercel\.app|api\.hustl\.app|supabase\.co' "$DEFINE_FILE" "$VERCEL_CONFIG"; then
  echo "Evaluator configuration references a production Hustl origin." >&2
  exit 1
fi
if grep -Eq '"source"[[:space:]]*:[[:space:]]*"/api|immutable' "$VERCEL_CONFIG"; then
  echo "Evaluator Vercel config contains an API proxy or stale immutable cache." >&2
  exit 1
fi
if ! grep -Eq 'must-revalidate' "$VERCEL_CONFIG"; then
  echo "Evaluator Vercel config must revalidate deploy artifacts." >&2
  exit 1
fi

if ! command -v flutter >/dev/null; then
  FLUTTER_VERSION="${FLUTTER_VERSION:-$(awk '$1 == "flutter" { print $2; exit }' "$APP_DIR/.tool-versions")}"
  if [[ -z "$FLUTTER_VERSION" ]]; then
    echo "Evaluator Flutter version is missing from .tool-versions." >&2
    exit 1
  fi
  if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
    echo "Installing Flutter $FLUTTER_VERSION for the evaluator build..."
    git config --global --add safe.directory "$FLUTTER_DIR" || true
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

cd "$APP_DIR"
flutter pub get
flutter build web --release --dart-define-from-file="$DEFINE_FILE"

# The private offline catalog contains optional production-hosted thumbnails.
# The evaluator must never request them, so strip only that field from the
# generated asset while preserving ids, names, instructions, and muscles.
CATALOG="$APP_DIR/build/web/assets/assets/data/exercises_seed.json"
if [[ ! -f "$CATALOG" ]]; then
  echo "Built evaluator catalog is missing: $CATALOG" >&2
  exit 1
fi
if ! command -v node >/dev/null; then
  echo "Node.js is required to scrub evaluator thumbnail origins." >&2
  exit 1
fi
SCRUBBED_CATALOG="$CATALOG.scrubbed"
node "$APP_DIR/scripts/scrub_evaluator_catalog.mjs" \
  "$CATALOG" "$SCRUBBED_CATALOG"
mv "$SCRUBBED_CATALOG" "$CATALOG"
cp "$VERCEL_CONFIG" "$APP_DIR/build/web/vercel.json"

echo "Evaluator build complete at $APP_DIR/build/web"
