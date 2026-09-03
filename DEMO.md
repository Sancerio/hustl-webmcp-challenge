# Demo walkthrough

1. Open `/`. Inspect the real Train surface and use WebMCP discovery to confirm
   the shared tools plus Train context/history tools.
2. Ask `hustl_open_surface` to open `recovery`, `nutrition`, `coach`, or
   `templates`. Confirm the route changes and discovery is replaced rather than
   accumulated.
3. On `/nutrition`, call `hustl_propose_food_log` with a synthetic meal. The
   result must report a pending proposal, not an applied diary mutation.
4. Open `/proposals`, then call `hustl_open_proposal` for the returned ID. Review
   the proposal detail in the Flutter UI.
5. On `/templates`, inspect template context and stage a template edit. The
   original template remains unchanged until an explicit product review flow.
6. Return to Train and press **Start** on the suggested repeat workout (or open
   `/workout_session`, which has the same public seed fallback). Inspect the
   active workout, then stage an adjustment. The adjustment is pending and the
   active workout is not silently rewritten.

The fixtures reset on page reload. No sign-in or external service is required.
