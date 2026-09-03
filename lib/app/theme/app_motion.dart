import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// A [Curve] driven by a [SpringDescription]. Lets physics-based springs be used
/// anywhere a curve is expected (e.g. flutter_animate's `.scaleXY`/`.slideY`),
/// so the celebration bounce matches the spec spring instead of an ad-hoc
/// `easeOutBack` approximation.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring)
    : _sim = SpringSimulation(spring, 0, 1, 0);

  final SpringSimulation _sim;

  @override
  double transformInternal(double t) => _sim.x(t) + t * (1 - _sim.x(1.0));
}

class AppMotion {
  AppMotion._();

  // Micro-interaction durations (taps, toggles, small state changes).
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 220);

  // Hero / state-moment duration for larger, deliberate transitions.
  static const Duration emphasized = Duration(milliseconds: 350);

  // Bottom-sheet enter/exit duration (replaces hardcoded 320/300ms).
  static const Duration sheet = Duration(milliseconds: 280);

  // Persistent-player expand/collapse. Matches the compact, continuous player
  // handoff used by premium music surfaces rather than modal-sheet pacing.
  static const Duration persistentSheet = Duration(milliseconds: 300);
  static const Curve persistentPlayerCurve = Cubic(0.2, 0, 0.6, 1);

  static const Curve enterCurve = Curves.easeOut;
  static const Curve exitCurve = Curves.easeIn;
  static const Curve emphasizedCurve = Curves.easeOutCubic;

  /// Spring for draggable / positional (spatial) motion — snappy and settled.
  static final SpringDescription spatial = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
    ratio: 0.85,
  );

  /// Looser, bouncier spring reserved for the workout-summary entrance and the
  /// PR banner. Do not use for routine spatial motion.
  static final SpringDescription celebrate = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
    ratio: 0.6,
  );

  /// The [celebrate] spring expressed as a [Curve], for curve-based animation
  /// APIs (e.g. flutter_animate). Use this for the summary entrance and PR
  /// banner so the bounce matches the spec spring.
  static final Curve celebrateCurve = SpringCurve(celebrate);

  // --- Stagger spec (see StaggeredEntrance) ---
  /// Interval between successive item entrances.
  static const Duration staggerInterval = Duration(milliseconds: 40);

  /// Per-item entrance duration.
  static const Duration staggerItem = Duration(milliseconds: 240);

  /// Vertical rise distance for the entrance animation.
  static const double staggerRise = 14;

  /// Cap on the number of items that animate; the rest appear instantly.
  static const int staggerMaxItems = 8;
}

Widget appFadeSlideTransition(Widget child, Animation<double> animation) {
  final slide = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: AppMotion.enterCurve));
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(position: slide, child: child),
  );
}
