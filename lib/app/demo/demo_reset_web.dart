import 'package:web/web.dart' as web;

/// Hard-reloads the evaluator at its canonical product route.
///
/// Every demo repository is in memory, so a full navigation is the single
/// source of truth for restoring seeded workouts, nutrition, proposals,
/// settings, and recovery data together.
void resetDemoExperience() {
  web.window.location.replace('/');
}
