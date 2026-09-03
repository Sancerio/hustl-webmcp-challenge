# Architecture

## Trust boundary

The public entry point creates a Flutter `GetIt` graph using only deterministic
demo repositories. Presentation screens, domain models, and the WebMCP
coordinator come from the pinned Hustl commit. Private adapters are replaced by
small overlays that either serve in-memory fixtures or return an explicit
unavailable result.

The browser bridge exposes tool registration only. Its runtime guard denies
non-local network access, `sendBeacon`, WebSocket/EventSource connections,
service workers, and browser credential APIs. The evaluator configuration uses
the reserved `.invalid` domain for all endpoint-shaped values.

## WebMCP tool inventory

Always available:

- `hustl_get_today_context`
- `hustl_open_surface`

Train:

- `hustl_get_training_context`
- `hustl_get_workout_history`
- `hustl_get_exercise_history`

Recover:

- `hustl_get_recovery_context`

Nutrition:

- `hustl_get_nutrition_context`
- `hustl_get_food_log_entries`
- `hustl_propose_nutrition_targets`
- `hustl_propose_food_log`
- `hustl_propose_food_log_edit`
- `hustl_propose_food_log_delete`

Coach and proposals:

- `hustl_get_coach_activity`
- `hustl_get_coaching_trends`
- `hustl_open_proposal`

Templates:

- `hustl_propose_template`
- `hustl_get_template_context`
- `hustl_propose_template_edit`

Active workout:

- `hustl_get_active_workout`
- `hustl_stage_workout_adjustment`

All proposal and adjustment tools stage pending records for UI review. The
challenge-mode proposal repository does not implement a direct apply path.

## Included

- Real Flutter screens and widgets for Train, Nutrition, Recover, Coach,
  Templates, and Active workout.
- Real route-scoped WebMCP coordinator, host adapter, schemas, and tests.
- Synthetic workout, nutrition, health, history, trend, and proposal fixtures.
- The subset of Hustl icons and DM Sans fonts referenced by the source closure.
- Release build script, WebMCP bootstrap/bridge, runtime safety guard, and
  Vercel static-hosting headers.

## Deliberately excluded

- Backend/Supabase clients, production endpoint configuration, auth/session and
  token persistence, analytics/telemetry, push notifications, and crash upload.
- Production user records, account identifiers, private datasets, secrets, and
  environment files.
- Native Health Connect, watch, widget, or background-service implementations;
  public compatibility seams return empty/unavailable states.
- CI/CD, deployment targets, remote Git history, and repository automation.

## Source overlays

Overlays exist only for composition, navigation, dependency injection,
deterministic repositories, no-op platform/API seams, and tests for those seams.
They are called out individually as `overlay` in
`config/source_manifest.txt`; every `source` entry can be compared byte-for-byte
with `git show <commit>:hustl_app/<path>`.
