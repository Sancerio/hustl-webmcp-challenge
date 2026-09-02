# Hustl WebMCP evaluator

This repository contains the standalone Flutter evaluator used for the Hustl
WebMCP challenge. The repository's About section links to the deployed build.

The evaluator uses synthetic, in-memory training, recovery, nutrition,
template, and Coach data. It does not connect to a Hustl account, backend,
authentication service, analytics service, persistent store, or production
endpoint.

The athlete states the goal in the AI conversation. WebMCP can read bounded
current context, history, and trends, then prepare nutrition, food-log,
food-correction, food-removal, and workout-template proposals. New proposals
are pending until the athlete uses the visible Apply or Dismiss control in
Coach.

Pending proposal details include Return to Train. After review, the action
changes to Continue to Train. Both routes preserve the in-memory session. If a
proposal link is refreshed after that state has been lost, the page explains
what happened and links back to Train.

## Run locally

```bash
flutter pub get
bash scripts/build.sh
python3 -m http.server 8767 -d build/web
```

Open `http://127.0.0.1:8767`. The evaluator must run from the built output so
the pre-Flutter runtime guard can execute. Do not use `flutter run` for this
test path.

Reloading restores the original synthetic data and empties the Coach inbox.
`/demo` redirects to `/` for compatibility. The evaluator does not add a demo
banner, goal form, reset control, or separate product flow.

## Validate

```bash
flutter analyze --no-pub
flutter test --no-pub -r compact
node --test test/webmcp/*.mjs
bash scripts/build.sh
```

CI pins Flutter 3.38.7 and Gitleaks 8.30.1 by checksum. It also pins Node
22.23.2 and each external GitHub Action by commit. The workflow scans the
current source, full Git history, and generated build; checks bundled font
licenses; uploads a SHA-256 file manifest; and issues GitHub build-provenance
attestations for `main`. GitHub updates its hosted runner image, so the
workflow records the runner image identifiers instead of claiming that the
base image is byte-reproducible.

See `CONTRIBUTING.md` for change requirements, `SECURITY.md` for vulnerability
reporting, and `RELEASING.md` for publication and deployment checks.

`public_manifest.txt` lists every file allowed in a public export. An export
must contain exactly those files and must start with an independent Git
history. Private release tooling stays outside this repository. It builds the
public snapshot from frozen Git objects, not from a developer working tree or
private repository history.

## Runtime limits

- synthetic data only;
- no network calls except same-origin build assets;
- in-memory browser storage and product state;
- restrictive CSP plus a pre-Flutter runtime guard;
- cookie clearing on evaluator documents and deep links, never on the
  credentialless static assets needed to bootstrap Flutter;
- route-scoped WebMCP registrations with stale-route rejection;
- no WebMCP Apply, Dismiss, approval, reset, or bypass tool.

The evaluator omits active-workout tools and the `/workout_session` route. The
challenge flow covers planning before training and review afterward: recent
history, recovery, nutrition, meal changes, and workout programming. It does
not cover logging sets during a workout.

This evaluator is not medical software and does not provide diagnosis.
