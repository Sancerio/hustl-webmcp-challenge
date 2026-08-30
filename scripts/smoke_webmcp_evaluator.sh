#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

# This is the deterministic, credential-free release gate. The focused tests
# exercise landing -> shell, route ownership, proposal collaboration, and reset;
# the bridge tests exercise browser registration/staleness; the built-bundle
# scan enforces the offline production-origin boundary.
bash scripts/verify_webmcp_evaluator.sh

DEFAULT_OUTPUT="${AGENT_TMPDIR:-${TMPDIR:-/tmp}}/hustl-default-web-$$"
flutter build web --release --output="$DEFAULT_OUTPUT"

# The shared router deliberately keeps the evaluator widget code available so
# tests can inject challengeMode=true; a string scan therefore cannot prove
# runtime exposure. The focused route/frame tests above are the authoritative
# production-off assertion, while this build catches accidental compile drift.
echo "Evaluator release gate passed; default route behavior remains off."
echo "Default comparison bundle: $DEFAULT_OUTPUT"
