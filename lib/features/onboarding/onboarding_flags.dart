/// Compile-time flag for the v3 onboarding (branded carousel + guest-first
/// welcome + the full first-run flow). **On by default** — v3 is now the
/// onboarding experience. `--dart-define=HUSTL_ONBOARDING_V3=false` is the
/// compile-time kill switch (emergency rollback) until the flag is removed in a
/// follow-up. First-run users are routed to `/onboarding/intro` (see the redirect
/// in `lib/app/navigation/app_router.dart`); already-onboarded users are seeded
/// past it by the startup migration in `service_locator.dart`.
const bool kOnboardingV3Enabled = bool.fromEnvironment(
  'HUSTL_ONBOARDING_V3',
  defaultValue: true,
);
