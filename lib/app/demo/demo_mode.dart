/// Compile-time demo-mode flag.
///
/// Enabled via `--dart-define=HUSTL_DEMO=true`. When `true`, the service
/// locator registers deterministic in-memory `Demo*` repositories ahead of the
/// real ones so every screen renders a rich, reproducible "Alex" persona state
/// fully offline (see `docs/exec-plans/ui-revamp-2026.md` §10).
///
/// Never on in normal builds — the default is `false`, so the real
/// repositories are used and behavior is unchanged.
const bool kDemoMode = bool.fromEnvironment('HUSTL_DEMO');

/// Public evaluator chrome and reset controls.
///
/// Challenge mode is deliberately subordinate to [kDemoMode]. A build cannot
/// expose the evaluator experience unless all product repositories are already
/// using deterministic in-memory demo data.
const bool kChallengeMode =
    kDemoMode && bool.fromEnvironment('HUSTL_CHALLENGE');
