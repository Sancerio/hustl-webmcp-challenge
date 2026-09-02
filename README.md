# Hustl WebMCP evaluator

This is a standalone Flutter web evaluator for Hustl's collaboration-first
hackathon flow. It contains synthetic in-memory training, recovery, nutrition,
templates, and Coach proposals. It has no Hustl account, backend, auth,
telemetry, persistence, or production endpoint.

The athlete's goal remains in the AI conversation. WebMCP can read bounded
context, inspect bounded history and trends, and prepare nutrition, food-log,
food-correction, food-removal, and workout-template proposals. Every proposal
begins pending. Only the visible **Apply** and **Dismiss** controls in Coach can
make a synthetic change or close a proposal.

Proposal detail keeps an explicit **Return to Train** action, and a completed
review exposes **Continue to Train**, so the athlete can resume the story
without reloading and losing the in-memory collaboration state. A refreshed
proposal deep link explains the reset and also provides a direct Train exit.

## Run locally

```bash
flutter pub get
bash scripts/build.sh
python3 -m http.server 8767 -d build/web
```

Open `http://127.0.0.1:8767`. Use the built output so the pre-Flutter runtime
guard is present; direct `flutter run` is intentionally not the supported
evaluator path.

Reloading the page reconstructs the original synthetic baseline and empty
Coach inbox. `/demo` is only a compatibility redirect to `/`; there is no demo
banner, goal form, reset control, or evaluator-only product flow.

## Validate

```bash
flutter analyze --no-pub
flutter test --no-pub -r compact
node --test test/webmcp/*.mjs
bash scripts/build.sh
```

CI checksum-pins Flutter 3.38.7 and Gitleaks 8.30.1, pins Node 22.23.2 and every
external Action commit, scans source/history/build output, ships the font
licenses with the web build, uploads an exact SHA-256 file manifest, and issues
GitHub build-provenance attestations for `main`. GitHub's hosted runner image is
vendor-updated rather than byte-pinned, so its image identifiers are recorded
in artifact provenance. See `CONTRIBUTING.md`, `SECURITY.md`, and `RELEASING.md`
for the public collaboration, disclosure, and owner-controlled publication
process.

`public_manifest.txt` is the explicit publishable file list. Any public export
must include exactly those reviewed files and its own independent Git history.
Release tooling is intentionally kept outside this public source tree. Public
snapshots are built from frozen Git objects into a new one-root-commit history,
never by copying a developer working tree or private repository history.

## Safety boundary

- synthetic data only;
- no network calls except same-origin build assets;
- in-memory browser storage and product state;
- restrictive CSP plus a pre-Flutter runtime guard;
- cookie clearing on evaluator documents and deep links, never on the
  credentialless static assets needed to bootstrap Flutter;
- route-scoped WebMCP registrations with stale-route rejection;
- no WebMCP Apply, Dismiss, approval, reset, or bypass tool.

The public evaluator intentionally omits active-workout tools and the
`/workout_session` route. The hackathon story focuses on before/after coaching,
history, nutrition, meal correction, and programming collaboration rather than
gym-time logging.

This evaluator is not medical software and does not provide diagnosis.
