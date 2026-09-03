# Hustl WebMCP evaluator

This repository is a deterministic, offline-safe evaluator for Hustl's WebMCP
Challenge submission. It preserves the real Flutter presentation and WebMCP
coordinator from Hustl commit `f52fd2196a5e77c6eb8083df0342ed68d46aeee4`,
while replacing private infrastructure with in-memory demo repositories and
explicit no-op seams.

The evaluator contains no production credentials, authenticated user data,
backend client, token storage, analytics, or deployment history. Mutating
WebMCP tools create reviewable, pending proposals; they do not silently apply
changes.

## Run locally

Prerequisites: the Flutter version pinned in `.tool-versions` and Node.js 20+.
Always use the guarded release bundle; a raw Flutter development server does
not inject the evaluator runtime boundary.

```sh
bash scripts/build.sh
python3 -m http.server 8767 --directory build/web
```

Then open `http://127.0.0.1:8767`.

## Validate

```sh
bash scripts/verify.sh
flutter analyze --no-pub
flutter test --no-pub test/core/webmcp test/app/demo test/app/navigation
node --test test/webmcp/*.mjs
bash scripts/build.sh
```

`scripts/verify.sh` checks provenance, manifest integrity, forbidden private
paths and network origins, symlinks, Git isolation, and the built runtime guard.

## Surfaces

| Surface | Route | Purpose |
| --- | --- | --- |
| Train | `/` | Training context, history, exercise history, and workout launch |
| Nutrition | `/nutrition` | Food diary and review-first food/target proposals |
| Recover | `/health` | Recovery context and health overview |
| Coach | `/proposals` | Pending proposal inbox and activity |
| Proposal detail | `/proposals/:id` | Explicit review of a staged change |
| Templates | `/templates` | Workout-template library |
| Template detail | `/templates/:id` | Template context and staged edits |
| Active workout | `/workout_session` | Active-workout state and staged adjustment |

`/workout` aliases the active-workout route and `/account` redirects to Coach.
WebMCP discovery is route-scoped: only tools relevant to the current surface
are registered, with shared navigation and today-context tools always present.
See [ARCHITECTURE.md](ARCHITECTURE.md) for the complete tool inventory.

## Provenance and regeneration

`config/source.json` pins the upstream commit. `config/source_manifest.txt`
labels every Dart file as either exact upstream `source` or public-safety
`overlay`. `config/static_manifest.txt` lists the remaining public files.

To regenerate into a new directory from a local Hustl checkout containing the
pinned object:

```sh
bash scripts/regenerate.sh /path/to/hustl /tmp/hustl-public-rebuilt
```

The script refuses a different commit, an existing destination, unsafe paths,
or missing objects. It creates a disconnected Git repository with one
deterministic root commit, then runs `bash scripts/verify.sh` itself.

## Scope

This is an evaluator, not a production client. The included fixtures are
synthetic and deterministic. Camera/barcode packages remain because the real
Nutrition UI imports those widgets, but public demo repositories never call a
remote meal-analysis service. The runtime guard blocks unexpected network
requests and browser credential APIs.

The code is MIT licensed. See [LICENSE](LICENSE),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and
[SECURITY.md](SECURITY.md).
