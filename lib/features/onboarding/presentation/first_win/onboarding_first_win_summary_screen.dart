import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/onboarding/domain/coach_readiness_service.dart';
import 'package:hustl_app/features/onboarding/domain/onboarding_telemetry.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

import 'connected_system_graph.dart';
import 'first_win_widgets.dart';
import 'save_progress_upgrade_card.dart';

/// The v3 onboarding "first win" moment: a full-screen "Building your plan"
/// summary shown once, after a new lifter's first completed workout. It renders
/// the REAL session stats and a coach-readiness gauge computed from REAL data,
/// then commits the plan and drops the user home.
class OnboardingFirstWinSummaryScreen extends StatefulWidget {
  const OnboardingFirstWinSummaryScreen({
    super.key,
    required this.sessionId,
    this.workoutRepository,
    this.readinessService,
    this.preferencesService,
    this.animate = true,
  });

  final String sessionId;

  /// Injectable for tests; defaults to the GetIt-registered instances.
  final WorkoutRepository? workoutRepository;
  final CoachReadinessService? readinessService;
  final PreferencesService? preferencesService;

  /// Off for deterministic screenshots/tests.
  final bool animate;

  @override
  State<OnboardingFirstWinSummaryScreen> createState() =>
      _OnboardingFirstWinSummaryScreenState();
}

class _OnboardingFirstWinSummaryScreenState
    extends State<OnboardingFirstWinSummaryScreen> {
  late final WorkoutRepository _workoutRepository =
      widget.workoutRepository ?? GetIt.instance<WorkoutRepository>();
  late final CoachReadinessService _readinessService =
      widget.readinessService ?? GetIt.instance<CoachReadinessService>();
  late final PreferencesService _preferences =
      widget.preferencesService ?? GetIt.instance<PreferencesService>();

  late final Future<WorkoutSession?> _sessionFuture = _workoutRepository
      .getWorkoutSession(widget.sessionId);
  late final Future<CoachReadinessSnapshot> _snapshotFuture = _readinessService
      .snapshot();

  bool _committing = false;

  Future<void> _lockInPlan() async {
    if (_committing) return;
    setState(() => _committing = true);
    final router = GoRouter.of(context);
    // ignore: discarded_futures
    Haptics.confirm();
    try {
      await _preferences.setOnboardingIntroSeen(true);
      await _preferences.setOnboardingFirstWinSeen(true);
    } finally {
      router.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    OnboardingTelemetry.instance.firstWinShown();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animate = widget.animate && !reduceMotion;

    final content = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x3,
          AppSpacing.x3,
          AppSpacing.x3,
          AppSpacing.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1 — Personal delta beat: this session is about YOU.
            const _TrophyHero(),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Your first session is logged',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              "Here's your baseline — and the start of your plan.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            _SessionStats(sessionFuture: _sessionFuture),
            const SizedBox(height: AppSpacing.x4),

            // 2 — Data-flow reveal + coaching readiness gauge (REAL data).
            Text(
              'Building your plan',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Everything you log feeds one coach that gets smarter over time.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            _ReadinessGauge(snapshotFuture: _snapshotFuture, animate: animate),
            const SizedBox(height: AppSpacing.x4),

            // 3 — The starter plan the coach will draft next (static preview).
            const StarterPlanPreviewCard(),
            const SizedBox(height: AppSpacing.x4),

            // 3b — Value-timed upgrade: back up this first win (guests only).
            // Collapses to nothing (incl. its own trailing space) when signed in.
            const SaveProgressUpgradeCard(),

            // 4 — Tactile commitment.
            FilledButton.icon(
              onPressed: _committing ? null : _lockInPlan,
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: const Text('Lock in my plan'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                textStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.controlRadius,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Keep logging and your coach sharpens every session.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: colors.surface,
      body: animate ? _Entrance(child: content) : content,
    );
  }
}

/// A softly held, emerald-tinted trophy — the celebratory delta beat. Decorative.
class _TrophyHero extends StatelessWidget {
  const _TrophyHero();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentEmeraldGreen.withValues(alpha: 0.12),
          ),
          child: Icon(
            Icons.emoji_events_rounded,
            size: 34,
            color: AppColors.accentEmeraldGreen,
          ),
        ),
      ),
    );
  }
}

/// Real session stats (sets, volume, duration, exercises) in a 2×2 tile grid,
/// with a skeleton while the session loads.
class _SessionStats extends StatelessWidget {
  const _SessionStats({required this.sessionFuture});

  final Future<WorkoutSession?> sessionFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkoutSession?>(
      future: sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StatsSkeleton();
        }
        final session = snapshot.data;
        if (session == null) return const SizedBox.shrink();
        final sets = session.exercises
            .expand((e) => e.sets)
            .where((s) => s.isCompleted)
            .length;
        final volume = session.totalVolume;
        final exercises = session.exercises.length;
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(value: '$sets', label: 'sets'),
                ),
                const SizedBox(width: AppSpacing.x1),
                Expanded(
                  child: StatTile(value: _grouped(volume), label: 'volume'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    value: _durationLabel(session.duration),
                    label: 'duration',
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                Expanded(
                  child: StatTile(value: '$exercises', label: 'exercises'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _grouped(num value) {
    final n = value.round();
    final digits = n.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${n < 0 ? '-' : ''}$buffer';
  }

  static String _durationLabel(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row() => const Row(
      children: [
        Expanded(child: FirstWinSkeletonBox(height: 64)),
        SizedBox(width: AppSpacing.x1),
        Expanded(child: FirstWinSkeletonBox(height: 64)),
      ],
    );
    return Column(
      children: [
        row(),
        const SizedBox(height: AppSpacing.x1),
        row(),
      ],
    );
  }
}

/// The readiness gauge fed by [CoachReadinessService.snapshot], with a skeleton
/// while it computes.
class _ReadinessGauge extends StatelessWidget {
  const _ReadinessGauge({required this.snapshotFuture, required this.animate});

  final Future<CoachReadinessSnapshot> snapshotFuture;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoachReadinessSnapshot>(
      future: snapshotFuture,
      builder: (context, snapshot) {
        // A failed read (the service itself degrades to 0/false internally, so
        // this only fires if the future rejects outright) renders the gauge in
        // a quiet, neutral zero state instead of shimmering forever — no error
        // copy on a celebration screen.
        if (snapshot.hasError) {
          return ConnectedSystemGraph(
            readiness: 0,
            filledCount: 0,
            animateReveal: animate,
          );
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const _GaugeSkeleton();
        }
        final data = snapshot.data!;
        return ConnectedSystemGraph(
          readiness: data.readiness,
          filledCount: data.filledCount,
          readinessNote: data.note,
          animateReveal: animate,
        );
      },
    );
  }
}

class _GaugeSkeleton extends StatelessWidget {
  const _GaugeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        FirstWinSkeletonBox(height: 128, width: 128, shape: BoxShape.circle),
        SizedBox(height: AppSpacing.x3),
        FirstWinSkeletonBox(height: 44),
      ],
    );
  }
}

/// Calm fade + rise for the whole screen on entrance.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.child});
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.enterCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
