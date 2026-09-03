# Contributing

Keep the evaluator deterministic and fail-closed.

- Do not add credentials, production endpoints, user exports, auth/session
  storage, telemetry, or remote write paths.
- Preserve route-scoped WebMCP discovery and explicit pending-versus-applied
  semantics.
- Update the pinned source commit and manifests only through a deliberate
  provenance review.
- Add tests for schema, route, proposal, and runtime-guard changes.
- Run every command in the README validation section before submitting changes.
- Regenerate manifests with `bash scripts/update_manifests.sh` only after
  reviewing the complete diff.

Security issues should follow [SECURITY.md](SECURITY.md), not a public issue.
