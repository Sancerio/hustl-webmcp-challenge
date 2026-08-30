class AppRoutes {
  /// Routes we honor as the post-login landing.
  ///
  /// Post-login navigation uses `context.go(route)`, which REPLACES the whole
  /// stack. The landing must therefore be self-navigable on its own — a shell
  /// tab (with the bottom nav) or a flow that routes itself back to one — rather
  /// than a standalone overlay that would strand the user with no back and no
  /// nav (notably on web, where there is no system back).
  ///
  /// Deliberately excluded: `/account` and `/settings`. Both are standalone
  /// overlay routes reached only via `context.push(...)` from inside the shell
  /// (where they get a real back button). Landing on either via `go` after
  /// login left the user on a screen with no bottom nav and no back — the
  /// post-login dead-end. Dropping them means any stale `/account`/`/settings`
  /// redirect falls back to home.
  static const validAfterLoginRoutes = [
    '/', // home shell tab
    '/history', // shell tab
    '/workout', // legacy alias; redirects to canonical active-workout flow
    '/workout_session', // active-workout flow; routes itself back to the shell
    '/widget/workouts', // widget launcher; resolves to a session or home
  ];

  /// Home (the first shell tab) — always navigable, with the bottom nav.
  static const defaultAfterLoginRoute = '/';
}
