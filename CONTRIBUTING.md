# Contributing

Thank you for improving the Hustl WebMCP evaluator. This repository is a
standalone, synthetic collaboration surface—not the production Hustl app.

## Boundaries

- Use synthetic fixtures only. Never add account exports, real health data,
  tokens, credentials, private endpoints, or developer-machine paths.
- WebMCP may read bounded context and create pending proposals. It must not
  expose Apply, Approve, Dismiss, Reject, Reset, or another decision bypass.
- Keep route-owned tools scoped to the visible page and fail stale handles
  closed before returning data or changing state.
- Keep the app offline apart from same-origin build assets. Do not add auth,
  analytics, telemetry, backend clients, or persistent browser storage.
- Every source file must appear exactly once in `public_manifest.txt`.

## Pull requests

Keep one concern per pull request. Explain the user-visible behavior, safety
boundary, and validation evidence. Update tests and documentation with behavior
changes. UI changes need desktop and narrow-mobile browser proof with a clean
console.

Before opening a pull request, run:

```bash
bash scripts/scan_public_source.sh .
bash test/public_release_test.sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub -r compact
node --test test/webmcp/*.mjs
bash scripts/build.sh
```

Changes to the runtime guard, WebMCP bridge/catalog, proposal state machine,
release scripts, headers, or CI require an independent security-minded review.
Public CI additionally downloads checksum-pinned Flutter and Gitleaks archives,
proves current-source and removed-history scanner canaries, scans the complete
Git history and generated web build, and verifies shipped license notices.
Workflow dependencies must be direct, commit-pinned external Actions; local
composite Actions are intentionally rejected so transitive dependencies cannot
escape the pin verifier.
