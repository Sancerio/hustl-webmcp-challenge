import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';

import '../../../health_sync/domain/usecases/load_latest_readiness.dart';
import '../../domain/models/workout_session.dart';
import '../../../workout_log/domain/utils/time_periods.dart';
import '../../domain/services/next_workout_focus_service.dart';
import '../../../workout_templates/domain/models/workout_template.dart';
import '../../../workout_templates/domain/repositories/template_repository.dart';
import '../widgets/home/home_hydrated_content.dart';
import '../widgets/home/home_week_stats.dart';
import '../widgets/home/home_template_picker.dart';
import '../widgets/home/quick_start_sheet.dart';
import '../widgets/home/readiness_today_slot.dart';
import '../widgets/home/repeat_session_picker.dart';
import '../widgets/workout_home_loading_skeleton.dart';
import '../../domain/repositories/workout_repository.dart';

class WorkoutHomeScreen extends StatefulWidget {
  const WorkoutHomeScreen({super.key, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Clock seam for the calendar-window math this screen does (see
  /// [_WorkoutHomeScreenState._loadActive] and
  /// [_WorkoutHomeScreenState._refreshFocusPeriod]). Both call sites read
  /// "now" from this SAME function, so a fixed-clock test can pin ONE value
  /// for every "now" this screen captures instead of two independent
  /// real-clock reads that can (rarely, near a month rollover) disagree.
  /// Defaults to [DateTime.now] so production behavior is unchanged.
  final DateTime Function() _now;

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  // Floor for the focus-card history fetch. The actual fetch start is derived
  // from the SELECTED period's resolved range (see [_focusFetchStart]); this
  // window is only the MINIMUM lookback so the rolling default ("last 4 weeks")
  // and short periods still pull a sensible buffer of context.
  static const Duration _nextWorkoutFocusFetchWindow = Duration(days: 35);
  final _workoutRepository = GetIt.instance<WorkoutRepository>();
  final _templateRepository = GetIt.instance<TemplateRepository>();
  final _prefs = GetIt.instance.isRegistered<PreferencesService>()
      ? GetIt.instance<PreferencesService>()
      : PreferencesService();
  // Built with the SAME Training-balance period the detail uses (the user's
  // persisted selection, read in [_loadActive]) so the home card's verdict and
  // window can never contradict the detail it links to. Until the pref resolves
  // it defaults to the detail's own default period.
  NextWorkoutFocusService _nextWorkoutFocusService = NextWorkoutFocusService();
  // The Training-balance period the focus card currently reflects. Tracked so
  // a return from the body-score detail (where the user can change the
  // persisted period while this tab stays mounted) can cheaply detect a change
  // and rebuild ONLY the focus card for the new window — see [_refreshFocusPeriod].
  BodyScorePeriod _focusPeriod = _focusServicePeriod;

  // Hide-on-scroll FAB: shared by the hydrated Train list and the extended
  // "Start workout" FAB so it never sits over the Volume-trend chart.
  final _scrollController = ScrollController();

  List<WorkoutSession> _recent = [];
  // The recent-window aggregation that feeds the Train hero, week strip and
  // volume trend. Computed OFF the build path (here in [_loadActive], and again
  // only when the underlying sessions change) and CACHED, so [build] never
  // re-runs the O(recent) nested set-iteration on every rebuild - critical on
  // Flutter web, where there are no isolates so that work would run inline on
  // the UI thread on every FAB-scroll/readiness/goal setState. Starts empty
  // (no history) and is replaced wholesale when sessions hydrate or change.
  HomeWeekStats _weekStats = HomeWeekStats.from(const []);
  List<WorkoutTemplate> _templates = [];
  // The completed sessions the current focus plan was built from, cached so the
  // plan can be cheaply rebuilt (same body-balance verdict, plus the readiness
  // context line) once the lazily-loaded readiness snapshot arrives.

  // Keep independently arriving annotations independently observable. A late
  // readiness read must not rebuild the hero/week bars, and a goal read must
  // not rebuild readiness or coaching while the user is already scrolling.
  final _homeFocus = ValueNotifier<NextWorkoutFocusPlan?>(null);
  final _homeReadinessState = ValueNotifier<ReadinessTodayState>(
    const ReadinessTodayState.loading(),
  );
  final _weeklyWorkoutGoal = ValueNotifier<int>(3);
  bool _sessionsHydrated = false;
  bool _scrollGestureActive = false;

  /// Whether the extended "Start workout" FAB is currently shown. This is a
  /// notifier rather than screen state so a scroll-direction change rebuilds
  /// only the FAB transition, not the entire hydrated Train dashboard.
  final _fabVisible = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadActive();
    // Weekly workout goal drives the hero ring's goal progress + green-on-met
    // state. Best-effort async read; the hero shows the default 3/wk until it
    // resolves, then refreshes in place.
    // ignore: discarded_futures
    _loadWeeklyWorkoutGoal();
    // This tab stays alive in the indexed shell, so a goal change made on the
    // Progress tab won't re-run initState. Listen to the shared preference
    // notifier so the hero ring updates live when the user returns.
    _prefs.weeklyWorkoutGoalListenable.addListener(_handleWeeklyGoalChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _fabVisible.dispose();
    _homeFocus.dispose();
    _homeReadinessState.dispose();
    _weeklyWorkoutGoal.dispose();
    _prefs.weeklyWorkoutGoalListenable.removeListener(_handleWeeklyGoalChanged);
    super.dispose();
  }

  /// Live-updates the hero ring when the weekly goal changes elsewhere (e.g. the
  /// Progress screen), since this tab is kept alive by the indexed shell.
  void _handleWeeklyGoalChanged() {
    if (!mounted) return;
    final goal = _prefs.weeklyWorkoutGoalListenable.value;
    if (goal == _weeklyWorkoutGoal.value) return;
    _weeklyWorkoutGoal.value = goal;
  }

  /// Hides the FAB during an active drag and brings it back once scrolling
  /// settles. Treating both directions the same avoids repeatedly reversing a
  /// scale/fade animation when the user scrubs back and forth on cold launch.
  /// The FAB starts visible at the top, but never reappears while a gesture is
  /// still active — even when that gesture scrubs all the way back to the top.
  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // At/near the top the FAB is visible only after the gesture settles. If the
    // finger is still down, reappearing here would animate over the same frames
    // that are handling a fast back-and-forth scrub.
    if (position.pixels <= position.minScrollExtent + 1) {
      if (!_scrollGestureActive) _setFabVisible(true);
      return;
    }
    switch (position.userScrollDirection) {
      case ScrollDirection.reverse:
      case ScrollDirection.forward:
        // Keep the transition quiet for the entire gesture. Reversing direction
        // mid-drag must not start another raster animation over the list.
        _setFabVisible(false);
      case ScrollDirection.idle:
        // An overscroll boundary can report idle while the pointer is still
        // down. Keep the FAB quiet until ScrollEnd releases the gesture; only
        // true settled momentum may bring it back here.
        if (!_scrollGestureActive) _setFabVisible(true);
    }
  }

  void _setFabVisible(bool visible) {
    if (_fabVisible.value == visible || !mounted) return;
    _fabVisible.value = visible;
  }

  Future<void> _loadActive() async {
    try {
      final now = widget._now();
      // Align the next-workout-focus card to the SAME period the Training-balance
      // detail reads, via the SHARED helper so the one-time current-week
      // migration runs HERE too when Home loads before the detail - otherwise a
      // stale stored closed-period pref would override the new current-week
      // default and the card would headline a window that hides this week's
      // work. Best-effort: any read failure keeps the default.
      BodyScorePeriod focusPeriod = _focusServicePeriod;
      try {
        final period = await readPersistedBodyScorePeriod(_prefs);
        focusPeriod = period;
        _focusPeriod = period;
        _nextWorkoutFocusService = NextWorkoutFocusService(period: period);
      } catch (_) {
        // Keep the default-period service on any pref read failure.
      }
      final results = await Future.wait([
        // Fetch enough history to avoid mis-classifying existing users as "new"
        // when their most recent sessions are incomplete.
        _workoutRepository.getWorkoutSessions(limit: 25),
        // Fetch the WHOLE window the card claims to summarize. For periods that
        // resolve earlier than the rolling floor (e.g. "last full month" begins
        // at the month start, which on mid-to-late dates predates 35 days back),
        // this pulls from the period start so early-window sessions are NOT
        // silently dropped from the card's verdict.
        _workoutRepository.getWorkoutSessions(
          startDate: _focusFetchStart(focusPeriod, now),
        ),
        _templateRepository.getWorkoutTemplates(),
      ]);
      if (!mounted) return;
      final completedRecent = (results[0] as List<WorkoutSession>)
          .where((s) => s.isCompleted)
          .toList();
      // The wide history covers the WHOLE selected period (so the focus card's
      // verdict is never clipped). It feeds ONLY the focus service.
      final completedFocus = (results[1] as List<WorkoutSession>)
          .where((s) => s.isCompleted)
          .toList();
      // Home-stats sessions stay bounded to the window the dashboard actually
      // DISPLAYS (the current week + the 6-week volume trend) even when the
      // selected period (e.g. "last full month") reaches further back, so
      // widening the focus fetch never silently widens the Train hero, week
      // strip or volume trend. Derive that window as a SLICE of the wide fetch —
      // same predicate the repo uses for [startDate]. Bounding here keeps the
      // off-build [HomeWeekStats] aggregation O(recent), never O(all-history).
      final homeStatsFloor = now.subtract(HomeWeekStats.displayWindow);
      final windowSessions = completedFocus
          .where((s) => s.startTime.isAfter(homeStatsFloor))
          .toList();
      // Aggregate OFF the build path and cache it: build() just reads the cached
      // stats, so it never re-runs the nested set-iteration on every rebuild.
      // Empty window (no recent sessions) falls back to [_recent] so a returning
      // user whose only history is older than the window still gets a sensible
      // hero — matching the prior in-build fallback exactly.
      final weekStats = HomeWeekStats.from(
        windowSessions.isNotEmpty ? windowSessions : completedRecent,
        now: now,
      );

      _homeFocus.value = _nextWorkoutFocusService.build(
        completedFocus,
        anchor: now,
      );
      setState(() {
        _recent = completedRecent;
        _weekStats = weekStats;
        _templates = results[2] as List<WorkoutTemplate>;
        _sessionsHydrated = true;
      });

      // Readiness is loaded lazily AFTER the workout data hydrates so it never
      // blocks or slows first paint. Best-effort: any failure → null → the
      // Train home renders exactly as today.
      // ignore: discarded_futures
      _loadReadiness();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sessionsHydrated = true);
      // Resolve the readiness slot independently even when workout hydration
      // fails; otherwise the static placeholder would remain indefinitely.
      // ignore: discarded_futures
      _loadReadiness();
    }
  }

  /// Opens the Body Score detail (the focus card links here) and refreshes the
  /// focus period on return. The detail is pushed on the ROOT navigator
  /// (`parentNavigatorKey: navigatorKey`), so popping it does NOT notify Home's
  /// branch route — a `RouteAware.didPopNext()` would never fire. Awaiting the
  /// push future instead resolves exactly when the detail pops, regardless of
  /// which navigator hosted it, so the period change made in the detail is
  /// picked up reliably here. See [_refreshFocusPeriod].
  Future<void> _openBodyScore() async {
    await context.push('/progress/body-score');
    if (!mounted) return;
    await _refreshFocusPeriod();
  }

  /// Re-reads the persisted Body Score period and, only when it differs from
  /// the one the focus card currently reflects, rebuilds the focus service and
  /// re-fetches the (period-anchored) focus history so the card's verdict and
  /// window match the detail again. Kept cheap: a no-op when the period is
  /// unchanged, and it refreshes ONLY the focus card — the fixed home-stats
  /// window, hero ring and templates are left untouched.
  Future<void> _refreshFocusPeriod() async {
    BodyScorePeriod period;
    try {
      // Same SHARED helper as the initial load so the migration stays the single
      // source of truth; on return from the detail the marker is already set, so
      // this just reflects the user's (possibly newly changed) selection.
      period = await readPersistedBodyScorePeriod(_prefs);
    } catch (_) {
      // Keep the current period on any pref read failure.
      return;
    }
    if (!mounted || period == _focusPeriod) return;

    final now = widget._now();
    final service = NextWorkoutFocusService(period: period);
    List<WorkoutSession> completedFocus;
    try {
      // Re-fetch ONLY the focus history for the new period's window (same
      // query the initial load uses). The fixed home-stats window does not
      // depend on the period, so it is deliberately not re-derived here.
      final sessions = await _workoutRepository.getWorkoutSessions(
        startDate: _focusFetchStart(period, now),
      );
      completedFocus = sessions.where((s) => s.isCompleted).toList();
    } catch (_) {
      // Leave the card on its current window if the refresh fetch fails.
      return;
    }
    if (!mounted) return;
    _focusPeriod = period;
    _nextWorkoutFocusService = service;
    _homeFocus.value = service.build(completedFocus, anchor: now);
  }

  /// The period the focus card defaults to until the persisted selection
  /// resolves — the SAME default the detail and [NextWorkoutFocusService] use.
  static const BodyScorePeriod _focusServicePeriod =
      BodyScorePeriod.defaultPeriod;

  /// History-fetch start for the focus card. Anchored to the SELECTED period's
  /// resolved range so the fetch covers the entire window the card claims to
  /// summarize — never less than [_nextWorkoutFocusFetchWindow] of lookback so
  /// the rolling default and short periods still carry a sensible buffer of
  /// context for recency cues.
  static DateTime _focusFetchStart(BodyScorePeriod period, DateTime now) {
    // Fetch far enough back to cover BOTH the focus card's minimum lookback AND
    // the home-stats display window (the 6-week volume trend, which reaches
    // further back than the 35-day focus floor) — otherwise the trend's oldest
    // weeks would be silently empty. Take the wider (earlier) of the two floors.
    final focusFloor = now.subtract(_nextWorkoutFocusFetchWindow);
    final homeStatsFloor = now.subtract(HomeWeekStats.displayWindow);
    final floor = homeStatsFloor.isBefore(focusFloor)
        ? homeStatsFloor
        : focusFloor;
    final periodStart = period.resolve(now).range.start;
    // Take the EARLIER of the floor and the period start so periods that begin
    // before the floor (e.g. "last full month" mid-month) are fetched in full,
    // while shorter periods still get the floor's buffer.
    return periodStart.isBefore(floor) ? periodStart : floor;
  }

  /// Lazily reads the latest readiness snapshot for the quiet "Readiness today"
  /// annotations (R2). Reuses the shared recovery pipeline via a tiny use-case;
  /// never blocks the home. Every terminal path resolves the fixed loading slot
  /// to either the real row or a quiet unavailable state.
  Future<void> _loadReadiness() async {
    if (!GetIt.instance.isRegistered<LoadLatestReadinessUseCase>()) {
      if (mounted) {
        _homeReadinessState.value = const ReadinessTodayState.unavailable();
      }
      return;
    }
    try {
      final readiness = await GetIt.instance<LoadLatestReadinessUseCase>()();
      if (!mounted) return;
      if (readiness == null || !readiness.hasRecoveryData) {
        _homeReadinessState.value = const ReadinessTodayState.unavailable();
        return;
      }
      _homeReadinessState.value = ReadinessTodayState.available(readiness);
      // Do not rebuild the coaching card here. Its optional readiness note
      // changes the card's height for Charged/Recharge snapshots, which would
      // move the rest of the list during an active cold-start scroll. The
      // fixed readiness slot and next-session metadata own this late signal.
    } catch (_) {
      if (mounted) {
        _homeReadinessState.value = const ReadinessTodayState.unavailable();
      }
    }
  }

  /// Reads the weekly workout goal (default 3/wk) so the hero ring can track
  /// "workouts done / weekly goal" and turn emerald once the goal is met. Any
  /// failure leaves the default in place, so the hero still renders sensibly.
  Future<void> _loadWeeklyWorkoutGoal() async {
    try {
      final goal = await _prefs.getWeeklyWorkoutGoal();
      if (!mounted) return;
      if (goal == _weeklyWorkoutGoal.value) return;
      _weeklyWorkoutGoal.value = goal;
    } catch (_) {
      // Keep the default 3/wk goal on any read failure.
    }
  }

  Map<String, dynamic> _extraFromSession(WorkoutSession s) => {
    'initialName': s.name,
    'initialExercises': s.exercises
        .map(
          (e) => {
            'name': e.exercise.name,
            'sets': e.sets.length,
            'rest': e.restTimerSeconds,
            'previousSets': e.sets.map((set) => set.toMap()).toList(),
          },
        )
        .toList(),
  };

  void _repeatSession(WorkoutSession s) {
    context.go(
      '/workout_session',
      extra: workoutRouteExtra(context, _extraFromSession(s)),
    );
  }

  void _startEmptyWorkout() {
    context.go('/workout_session', extra: workoutRouteExtra(context));
  }

  /// Opens the recent-sessions picker so the user can repeat ANY past session,
  /// not just the last. Selecting one reuses [_repeatSession] (a fresh draft;
  /// history is never mutated).
  void _openRepeatPreviousPicker() {
    // ignore: discarded_futures
    RepeatSessionPicker.show(
      context,
      sessions: _recent,
      onSelect: _repeatSession,
    );
  }

  /// Opens the quick-start sheet from the extended "Start workout" FAB. Offers
  /// the three ways to begin in priority order — repeat the last completed
  /// session, start from a template, or start an empty workout — each reusing
  /// the existing handlers. The inline next-session "Start" row is unchanged.
  void _openQuickStart() {
    Haptics.confirm();
    final lastSession = _recent.isNotEmpty ? _recent.first : null;
    // ignore: discarded_futures
    QuickStartSheet.show(
      context,
      hasLastSession: lastSession != null,
      lastSessionName: lastSession?.name,
      hasPreviousSessions: _recent.length > 1,
      onRepeatLast: () {
        if (lastSession != null) _repeatSession(lastSession);
      },
      onRepeatPrevious: _openRepeatPreviousPicker,
      onFromTemplate: () =>
          showHomeTemplatePicker(context, templates: _templates),
      onEmpty: _startEmptyWorkout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text('Train', style: theme.textTheme.titleLarge),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: const [
          HustlMenuButton(),
          SizedBox(width: AppSpacing.x1),
        ],
      ),
      // Keep scroll-driven FAB animation local. Rebuilding this tiny
      // ValueListenableBuilder avoids rebuilding the ListView, readiness row,
      // charts, and metric tweens on the first drag after a cold start.
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _fabVisible,
        builder: (context, visible, fab) => AnimatedSwitcher(
          duration: AppMotion.fast,
          switchInCurve: AppMotion.enterCurve,
          switchOutCurve: AppMotion.exitCurve,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: visible
              ? KeyedSubtree(key: const ValueKey('train-fab'), child: fab!)
              : const SizedBox.shrink(key: ValueKey('train-fab-hidden')),
        ),
        child: FloatingActionButton.extended(
          onPressed: _openQuickStart,
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          // The app FAB theme forces a CircleBorder (right for round FABs),
          // which would clip this extended FAB into a circle with the label
          // spilling off-screen. Pin the stadium shape so it reads as a pill.
          shape: const StadiumBorder(),
          tooltip: 'Start a workout',
          icon: HustlIcon(
            asset: 'assets/icons/ic_add.svg',
            size: 22,
            color: theme.colorScheme.onPrimary,
          ),
          label: const Text('Start workout'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: _sessionsHydrated
            ? NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    if (notification.dragDetails != null) {
                      _scrollGestureActive = true;
                      // At a scroll boundary there may be no direction change,
                      // so hide immediately on pointer-driven scroll start.
                      _setFabVisible(false);
                    }
                  } else if (notification is ScrollEndNotification) {
                    _scrollGestureActive = false;
                    _setFabVisible(true);
                  }
                  return false;
                },
                child: ListView(
                  key: const ValueKey('home-hydrated'),
                  controller: _scrollController,
                  // Extra bottom padding so the edge-to-edge Volume-trend chart
                  // (its "This week" label + latest-point dot) scrolls clear of
                  // the extended "Start workout" FAB instead of sitting under it.
                  padding: AppSpacing.screen.copyWith(
                    bottom: AppSpacing.x2 + 56 + AppSpacing.x2,
                  ),
                  children: [
                    HomeHydratedContent(
                      recent: _recent,
                      stats: _weekStats,
                      templates: _templates,
                      focusListenable: _homeFocus,
                      readinessStateListenable: _homeReadinessState,
                      weeklyWorkoutGoalListenable: _weeklyWorkoutGoal,
                      onStartEmptyWorkout: _startEmptyWorkout,
                      onRepeatSession: _repeatSession,
                      onOpenTemplates: () => showHomeTemplatePicker(
                        context,
                        templates: _templates,
                      ),
                      onOpenBodyScore: _openBodyScore,
                    ),
                  ],
                ),
              )
            : const Padding(
                key: ValueKey('home-loading'),
                padding: AppSpacing.screen,
                child: WorkoutHomeLoadingSkeleton(),
              ),
      ),
    );
  }
}
