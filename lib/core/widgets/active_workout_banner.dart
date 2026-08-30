import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/navigation/route_observer.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/workout_events_service.dart';

/// A compact global banner that appears when a workout is active.
/// Tapping it navigates to the in-progress workout screen.
class ActiveWorkoutBanner extends StatefulWidget {
  final bool isVisibleOverride;
  final bool includeBottomSafeArea;

  const ActiveWorkoutBanner({
    super.key,
    this.isVisibleOverride = true,
    this.includeBottomSafeArea = true,
  });

  static final Set<void Function()> _destinationPreparers = {};
  static final Set<void Function()> _destinationRestorers = {};
  static final Set<void Function(WorkoutSession)> _sessionSynchronizers = {};

  /// Refreshes and unmutes every mounted MiniPlayer before minimize motion
  /// exposes it. The snapshot avoids concurrent modification if navigation
  /// disposes a fallback banner while callbacks are running.
  static void prepareForMinimizeDestination() {
    for (final prepare in _destinationPreparers.toList()) {
      prepare();
    }
  }

  /// Re-mutes banners that were exposed for a direct drag which did not
  /// ultimately minimize the workout.
  static void restoreAfterCancelledMinimize() {
    for (final restore in _destinationRestorers.toList()) {
      restore();
    }
  }

  /// Publishes a newly-created session synchronously so the already-mounted
  /// shell player cannot be blank on the first drag frame.
  static void synchronizeSession(WorkoutSession session) {
    for (final synchronize in _sessionSynchronizers.toList()) {
      synchronize(session);
    }
  }

  /// Height reserved for the compact mobile player during route handoff.
  ///
  /// The card can grow with accessibility text scaling, so the transition
  /// cannot safely treat it as a fixed-height destination.
  static double mobileLandingHeight(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    double lineHeight(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      return painter.height;
    }

    final detailsHeight =
        lineHeight('Workout', theme.textTheme.bodyMedium) +
        2 +
        lineHeight('00:00', theme.textTheme.labelMedium);
    final buttonStyle = theme.textButtonTheme.style;
    final buttonTextStyle = buttonStyle?.textStyle?.resolve({});
    final resumeHeight = lineHeight('Resume', buttonTextStyle) + 16;
    final contentHeight = <double>[
      32,
      48,
      detailsHeight,
      resumeHeight,
    ].reduce((a, b) => a > b ? a : b);

    // 24px inner vertical padding plus the 8px gap below the card. Keep a
    // scale-aware rounding allowance because the Row lays out scaled glyph
    // metrics on physical pixels.
    final scaleRoundingAllowance = (textScaler.scale(2) - 2).clamp(
      0.0,
      double.infinity,
    );
    return contentHeight + 32 + scaleRoundingAllowance;
  }

  @override
  State<ActiveWorkoutBanner> createState() => _ActiveWorkoutBannerState();
}

class _ActiveWorkoutBannerState extends State<ActiveWorkoutBanner>
    with RouteAware, WidgetsBindingObserver {
  final WorkoutRepository _workoutRepository =
      GetIt.instance<WorkoutRepository>();
  final WorkoutEventsService? _workoutEvents =
      GetIt.instance.isRegistered<WorkoutEventsService>()
      ? GetIt.instance<WorkoutEventsService>()
      : null;
  WorkoutSession? _activeSession;
  bool _loading = true;
  late final Ticker _ticker;
  // Elapsed time is driven via a ValueNotifier so only the timer label rebuilds
  // each frame, not the whole banner.
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  bool _tickerRunning = false;
  bool _routeCovered = false;
  bool _tickerModeEnabled = true;
  StreamSubscription<WorkoutChange>? _eventsSub;
  Timer? _refreshDebounce;
  bool _restoreCoveredAfterPreparation = false;
  int _sessionRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Ticker((_) {
      final session = _activeSession;
      if (session != null) {
        _elapsed.value = DateTime.now().difference(session.startTime);
      }
    });
    _load();
    ActiveWorkoutBanner._destinationPreparers.add(
      _prepareForMinimizeDestination,
    );
    ActiveWorkoutBanner._destinationRestorers.add(
      _restoreAfterCancelledMinimize,
    );
    ActiveWorkoutBanner._sessionSynchronizers.add(_synchronizeSession);
    _eventsSub = _workoutEvents?.stream.listen(_onWorkoutChange);
  }

  @override
  void dispose() {
    ActiveWorkoutBanner._destinationPreparers.remove(
      _prepareForMinimizeDestination,
    );
    ActiveWorkoutBanner._destinationRestorers.remove(
      _restoreAfterCancelledMinimize,
    );
    ActiveWorkoutBanner._sessionSynchronizers.remove(_synchronizeSession);
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _eventsSub?.cancel();
    _eventsSub = null;
    WidgetsBinding.instance.removeObserver(this);
    try {
      final modal = ModalRoute.of(context);
      if (modal is PageRoute) {
        routeObserver.unsubscribe(this);
      }
    } catch (_) {
      // Ignore errors when looking up deactivated widget's ancestor
    }
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  void _onWorkoutChange(WorkoutChange change) {
    if (change.kind == WorkoutChangeKind.created) {
      _refreshDebounce?.cancel();
      _refreshDebounce = null;
      unawaited(_load());
      return;
    }
    _scheduleRefresh();
  }

  void _prepareForMinimizeDestination() {
    if (!mounted) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _restoreCoveredAfterPreparation |= _routeCovered;
    _routeCovered = false;
    final session = _activeSession;
    if (session != null) {
      _elapsed.value = DateTime.now().difference(session.startTime);
    }
    _syncTickerMute();
  }

  void _restoreAfterCancelledMinimize() {
    if (!mounted || !_restoreCoveredAfterPreparation) return;
    _restoreCoveredAfterPreparation = false;
    _routeCovered = true;
    _syncTickerMute();
  }

  void _synchronizeSession(WorkoutSession session) {
    if (!mounted) return;
    _sessionRevision++;
    _elapsed.value = DateTime.now().difference(session.startTime);
    setState(() {
      _activeSession = session;
      _loading = false;
    });
    _syncTicker();
  }

  void _scheduleRefresh() {
    if (!mounted) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes to refresh when returning to this route
    final modal = ModalRoute.of(context);
    if (modal is PageRoute) {
      routeObserver.subscribe(this, modal);
    }
    _tickerModeEnabled = TickerMode.of(context);
    _syncTickerMute();
    // Force refresh when dependencies change (e.g., when navigating to this screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleRefresh();
      }
    });
  }

  // Called when a new route has been popped and the current route shows up
  @override
  void didPopNext() {
    // Refresh active session when returning from minimized ActiveWorkoutScreen
    _routeCovered = false;
    _restoreCoveredAfterPreparation = false;
    _syncTickerMute();
    // Use post-frame callback to ensure proper timing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleRefresh();
      }
    });
  }

  // Called when a new route has been pushed atop this one
  @override
  void didPushNext() {
    // Mute ticker updates while not visible
    _routeCovered = true;
    _syncTickerMute();
  }

  // Called when app lifecycle state changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh when app comes back to foreground
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scheduleRefresh();
        }
      });
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final revision = ++_sessionRevision;
    try {
      final session = await _workoutRepository.getLatestActiveSession();
      if (!mounted || revision != _sessionRevision) return;
      if (session != null) {
        _elapsed.value = DateTime.now().difference(session.startTime);
      }
      setState(() {
        _activeSession = session;
        _loading = false;
      });
      _syncTicker();
    } catch (_) {
      if (!mounted || revision != _sessionRevision) return;
      setState(() {
        _activeSession = null;
        _loading = false;
      });
      _syncTicker();
    }
  }

  void _syncTicker() {
    final shouldRun = _activeSession != null;
    if (shouldRun == _tickerRunning) return;
    if (shouldRun) {
      _ticker.start();
    } else {
      _ticker.stop();
    }
    _tickerRunning = shouldRun;
    _syncTickerMute();
  }

  void _syncTickerMute() {
    _ticker.muted = _routeCovered || !_tickerModeEnabled;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisibleOverride || _loading || _activeSession == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final session = _activeSession!;

    void onResume() {
      WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.push);
      context.go(
        '/workout_session',
        extra: workoutRouteExtra(context, {
          'sessionId': session.id,
          'initialName': session.name,
          workoutExpandFromMiniPlayerExtraKey: true,
        }),
      );
    }

    return SafeArea(
      top: false,
      bottom: widget.includeBottomSafeArea,
      child: Padding(
        key: const Key('activeWorkoutBannerSurface'),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onResume,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                key: const Key('activeWorkoutBannerContent'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      key: const Key('activeWorkoutBannerDetails'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name.isNotEmpty ? session.name : 'Workout',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        RepaintBoundary(
                          child: ValueListenableBuilder<Duration>(
                            valueListenable: _elapsed,
                            builder: (context, elapsed, _) {
                              final value = elapsed == Duration.zero
                                  ? DateTime.now().difference(session.startTime)
                                  : elapsed;
                              return Text(
                                _format(value),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: onResume, child: const Text('Resume')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
