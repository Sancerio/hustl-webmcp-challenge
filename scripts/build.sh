#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter build web --release \
  --dart-define-from-file=config/evaluator.json \
  --no-web-resources-cdn \
  --pwa-strategy=none
rm -f build/web/flutter_service_worker.js
cp vercel.json build/web/vercel.json
node scripts/inject_evaluator_runtime_guard.mjs build/web
