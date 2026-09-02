# Contributing

This repository contains a synthetic Hustl WebMCP evaluator. It is separate
from the production Hustl app and must remain safe to run without an account or
backend.

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

Keep one concern per pull request. Describe the user-visible change, the data
or authority it can access, and the validation evidence. Update tests and docs
when behavior changes. UI changes require browser evidence at desktop and
narrow-mobile widths, with no console warnings or errors.

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

Changes to the runtime guard, WebMCP bridge or catalog, proposal state machine,
release scripts, response headers, or CI require an independent security
review.

Public CI downloads checksum-pinned Flutter and Gitleaks archives. It tests the
current-source and removed-history scanner canaries, scans the full Git history
and generated web build, and verifies the bundled license notices. Workflow
dependencies must be direct external Actions pinned to commits. Local composite
Actions are not allowed because their transitive dependencies cannot be checked
by the pin verifier.
