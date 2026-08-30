# Hustl WebMCP evaluator

Hustl brings training, recovery, nutrition, and coaching into one collaborative
fitness experience. This repository is the credential-free evaluator build for
the WebMCP hackathon.

The evaluator runs the real Flutter application against deterministic in-memory
data. Its route-scoped WebMCP tools can read bounded context and prepare
reviewable changes. The athlete stays in control: they select the target, see
the proposal diff, and Apply or Dismiss it in Hustl.

## Try it locally

Install a compatible Flutter stable SDK, then run:

```bash
flutter pub get
bash scripts/smoke_webmcp_evaluator.sh
python3 -m http.server 8767 --directory build/web
```

Open `http://127.0.0.1:8767/demo` in a browser with WebMCP support.

## Safety boundary

- Demo data is synthetic and held in memory.
- Telemetry and production sync are disabled in the evaluator build.
- No Hustl credential, OAuth client, backend, MCP server, or private repository
  history is included.
- `Reset demo` reloads the app and restores the deterministic baseline.
- The normal Hustl product and its production services are developed in a
  separate private repository.

## Collaboration flow

1. Ask the agent to review training, recovery, and nutrition together.
2. Let it read bounded current/history/trend context.
3. Select a workout template yourself.
4. Let the agent prepare a small review-only edit.
5. Inspect the visible diff in Coach and choose Apply or Dismiss.
6. Let the agent acknowledge the decision, then reset for the next run.

## License

Evaluator source is available under the MIT License. Third-party assets retain
their own terms; see `THIRD_PARTY_NOTICES.md`.
