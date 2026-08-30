#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

node --check web/webmcp_bridge.js
node --test test/webmcp/webmcp_bridge_test.mjs
flutter test --no-pub -r compact \
  test/app/demo \
  test/core/webmcp \
  test/app/navigation \
  test/app/bootstrap/hustl_app_bootstrapper_test.dart \
  test/app/widgets/auth_sync_listeners_webmcp_test.dart
flutter analyze --no-pub
bash scripts/build_webmcp_evaluator.sh

if rg -q 'hustl-two\.vercel\.app|hustlbackend\.vercel\.app|hustl-mcp-server\.vercel\.app|api\.hustl\.app|qsrubtwhyzwdweedpzaf\.supabase\.co' build/web; then
  echo "Evaluator bundle contains a production Hustl origin." >&2
  exit 1
fi

for label in 'Demo data' 'Reset demo' 'Try the demo'; do
  if ! rg -q "$label" build/web/main.dart.js; then
    echo "Evaluator bundle is missing expected label: $label" >&2
    exit 1
  fi
done

echo "Evaluator static, focused, and offline-origin gates passed."
