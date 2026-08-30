import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import '../../../workout_logging/domain/repositories/workout_repository.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/widgets/account_sheet.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/widgets/sync_prompt_card.dart';
import '../../../workout_logging/data/services/workout_sync_service.dart';
import '../../../workout_logging/data/datasources/hustl_backend_workout_history_api.dart';
import '../../../workout_logging/data/mappers/workout_server_mapper.dart';
import '../../../../core/services/token_storage.dart';
import '../../domain/services/body_score_service.dart';
import '../../domain/utils/muscle_group_mapper.dart';
import '../widgets/history/history_filter_sheet.dart';
import '../widgets/history/history_session_card.dart';
import '../widgets/history/history_session_metrics.dart';
import '../widgets/history/staggered_card_entrance.dart';

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({
    super.key,
    this.initialRegion,
    this.initialRangeDays,
    this.historyApiOverride,
  });

  final DisplayRegion? initialRegion;
  final int? initialRangeDays;
  final HustlBackendWorkoutHistoryApi? historyApiOverride;

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  static const String _muscleGroupFilterPrefKey =
      'workout_history_muscle_group_filter_v1';
  static const String _rangeDaysFilterPrefKey =
      'workout_history_range_days_filter_v1';

  final MuscleGroupMapper _muscleGroupMapper = MuscleGroupMapper();
  late final HustlBackendWorkoutHistoryApi _historyApi;
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  List<WorkoutSession> _sessions = [];
  List<WorkoutSession> _allSessions = [];
  bool _isLoading = true;
  String? _error;
  bool _serverEnabled = false;
  bool _serverHasMore = false;
  String? _serverCursor;
  bool _isLoadingMore = false;
  String? _loadMoreError;
  bool _syncBannerDismissed = false;
  DateTime _focusedDay = DateUtils.dateOnly(DateTime.now());
  DateTime? _selectedDay = DateUtils.dateOnly(DateTime.now());
  final Map<DateTime, int> _dateToFirstIndex = {};
  final Map<DateTime, List<WorkoutSession>> _sessionsByDate = {};
  // Precomputed per-session card metrics, keyed by session id, so cards never
  // recompute best-sets/volume on every scroll frame.
  final Map<String, HistorySessionMetrics> _metricsBySessionId = {};
  static const _historyListHeaderCount = 2;
  final ItemScrollController _itemScrollController = ItemScrollController();
  Set<MuscleGroup> _filterMuscleGroups = {};
  int? _filterRangeDays;
  // Tracks which cards have already played their entrance, so the stagger runs
  // once per session (not on every scroll into view).
  final Set<String> _staggeredSessionIds = {};

  // Sync/auth reactivity: a cold start often loads History before auth has
  // hydrated (so the server fetch is skipped) and never reacts to a background
  // sync — which stranded the user on the empty state until a manual
  // pull-to-refresh. We re-fetch when auth lands and when a sync finishes, and
  // show a "syncing" state instead of the empty story until the first
  // server-enabled load completes.
  StreamSubscription<AuthState>? _authSub;
  bool _didServerLoad = false;
  bool _prevSyncing = false;

  @override
  void initState() {
    super.initState();
    final tokens = GetIt.instance.isRegistered<TokenStorage>()
        ? GetIt.instance<TokenStorage>()
        : TokenStorage();
    _historyApi =
        widget.historyApiOverride ??
        HustlBackendWorkoutHistoryApi(tokens: tokens);
    if (widget.initialRangeDays != null && widget.initialRangeDays! > 0) {
      _filterRangeDays = widget.initialRangeDays;
    }
    if (widget.initialRegion != null) {
      _filterMuscleGroups = _mappableGroupsFor(widget.initialRegion!).toSet();
    } else {
      if (!_isTestEnv()) {
        _loadStoredFilters();
      }
    }
    _loadSessions();
    _loadBannerState();
    _itemPositionsListener.itemPositions.addListener(_handleScrollPositions);
    _subscribeToSyncSignals();
  }

  /// Re-fetch when the token finishes hydrating (so the server history loads
  /// without a manual pull) and when a background sync completes (so newly
  /// synced sessions appear). Both call back into [_loadSessions].
  void _subscribeToSyncSignals() {
    if (_isTestEnv()) return;
    try {
      _authSub = context.read<AuthBloc>().stream.listen((state) {
        if (state is AuthAuthenticated && mounted && !_isLoading) {
          _loadSessions();
        }
      });
    } catch (_) {
      // No AuthBloc in this context (e.g. a standalone harness) — skip.
    }
    if (GetIt.instance.isRegistered<WorkoutSyncService>()) {
      GetIt.instance<WorkoutSyncService>().status.addListener(
        _onSyncStatusChanged,
      );
    }
  }

  void _onSyncStatusChanged() {
    if (!mounted || !GetIt.instance.isRegistered<WorkoutSyncService>()) return;
    final syncing =
        GetIt.instance<WorkoutSyncService>().status.value == SyncStatus.syncing;
    // A sync just finished — pull in anything it may have changed.
    if (_prevSyncing && !syncing && !_isLoading) {
      _loadSessions();
    }
    _prevSyncing = syncing;
    // Refresh the "Syncing…" empty state's spinner/text regardless.
    setState(() {});
  }

  /// True while we still expect server data to arrive: the user is signed in
  /// (or auth is still hydrating) AND either a sync is running or the first
  /// server-enabled load hasn't completed yet. Signed-out users fall through to
  /// the genuine empty state (with the sign-in prompt above it).
  bool _isAwaitingFirstSync(BuildContext context) {
    AuthState authState;
    try {
      authState = context.read<AuthBloc>().state;
    } catch (_) {
      return false;
    }
    final authedOrPending =
        authState is AuthAuthenticated ||
        authState is AuthLoading ||
        authState is AuthHydrating;
    if (!authedOrPending) return false;
    final syncing =
        GetIt.instance.isRegistered<WorkoutSyncService>() &&
        GetIt.instance<WorkoutSyncService>().status.value == SyncStatus.syncing;
    return syncing || !_didServerLoad;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    if (GetIt.instance.isRegistered<WorkoutSyncService>()) {
      GetIt.instance<WorkoutSyncService>().status.removeListener(
        _onSyncStatusChanged,
      );
    }
    _itemPositionsListener.itemPositions.removeListener(_handleScrollPositions);
    super.dispose();
  }

  bool _isTestEnv() {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTestWidgetsFlutterBinding');
  }

  Future<void> _loadStoredFilters() async {
    final prefs = GetIt.instance<PreferencesService>();
    final rawGroups = await prefs.getRawString(_muscleGroupFilterPrefKey);
    final rawRange = await prefs.getRawString(_rangeDaysFilterPrefKey);

    Set<MuscleGroup> groups = {};
    if (rawGroups != null && rawGroups.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawGroups);
        if (decoded is List) {
          groups = decoded
              .whereType<String>()
              .map(muscleGroupFromKey)
              .whereType<MuscleGroup>()
              .toSet();
        }
      } catch (_) {}
    }

    int? rangeDays;
    if (rawRange != null && rawRange.isNotEmpty) {
      rangeDays = int.tryParse(rawRange);
    }

    if (!mounted) return;
    setState(() {
      _filterMuscleGroups = groups;
      _filterRangeDays = rangeDays;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyFiltersAndRebuild();
    });
  }

  Future<void> _persistFilters() async {
    if (_isTestEnv()) return;
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setRawString(
      _muscleGroupFilterPrefKey,
      _filterMuscleGroups.isEmpty
          ? null
          : jsonEncode(_filterMuscleGroups.map((g) => g.key).toList()),
    );
    await prefs.setRawString(
      _rangeDaysFilterPrefKey,
      _filterRangeDays?.toString(),
    );
  }

  static Iterable<MuscleGroup> _mappableGroupsFor(DisplayRegion region) {
    return MuscleGroup.values.where((group) {
      if (group == MuscleGroup.other || group == MuscleGroup.fullBody) {
        return false;
      }
      return group.displayRegion == region;
    });
  }

  String _encodeHistoryCursor(WorkoutSession session) {
    final payload = jsonEncode({
      'start_time': session.startTime.toUtc().toIso8601String(),
      'id': session.id,
    });
    return base64Url.encode(utf8.encode(payload));
  }

  Future<bool> _canUseServerHistory() async {
    if (_isTestEnv()) {
      return widget.historyApiOverride != null;
    }
    final String? token;
    try {
      token = await _historyApi.tokens.getAccessToken();
    } catch (_) {
      // Keychain/secure-storage access can fail transiently (simulator or
      // entitlement edge cases). Server history is an enhancement over the
      // local store, so fail closed to local-only history instead of
      // surfacing an error state — mirrors local_workout_repository's guard.
      return false;
    }
    return token != null && token.isNotEmpty;
  }

  Future<Set<String>> _getDeletedWorkoutIds() async {
    final ids = await GetIt.instance<PreferencesService>()
        .getWorkoutsDeletedIds();
    return ids.where((id) => id.isNotEmpty).toSet();
  }

  Future<({List<WorkoutSession> sessions, String? nextCursor})>
  _fetchServerHistorySessionsFiltered({
    required Set<String> deletedIds,
    required Set<String> existingIds,
    String? cursor,
    int limit = 50,
    int maxPages = 5,
  }) async {
    final kept = <WorkoutSession>[];
    String? next = cursor;
    for (int i = 0; i < maxPages; i++) {
      final page = await _historyApi.listHistory(limit: limit, cursor: next);
      next = page.nextCursor;

      for (final m in page.items) {
        final session = WorkoutServerMapper.sessionFromServerMap(m);
        if (session.id.isEmpty) continue;
        if (deletedIds.contains(session.id)) continue;
        if (existingIds.contains(session.id)) continue;
        kept.add(session);
      }

      if (kept.isNotEmpty || next == null) break;
    }

    return (sessions: kept, nextCursor: next);
  }

  void _handleScrollPositions() {
    if (_isLoading || _isLoadingMore) return;
    if (_loadMoreError != null) return;
    if (!_serverEnabled || !_serverHasMore) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    int maxIndex = 0;
    for (final pos in positions) {
      if (pos.index > maxIndex) maxIndex = pos.index;
    }
    final itemCount = _computeListItemCount();
    if (maxIndex >= itemCount - 5) {
      _loadMoreServerSessions();
    }
  }

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _loadMoreError = null;
    });
    try {
      final sessions = await GetIt.instance<WorkoutRepository>()
          .getWorkoutSessions();
      if (!mounted) return;
      final completed =
          sessions.where((s) => s.endTime != null).toList(growable: true)
            ..sort((a, b) {
              final byStart = b.startTime.compareTo(a.startTime);
              if (byStart != 0) return byStart;
              return b.id.compareTo(a.id);
            });

      final serverEnabled = await _canUseServerHistory();
      var combined = completed;
      String? cursor;
      bool serverHasMore = false;
      if (serverEnabled) {
        cursor = combined.isNotEmpty
            ? _encodeHistoryCursor(combined.last)
            : null;
        serverHasMore = true;
      }

      // If we have no local history but are authenticated, prime the first server page.
      if (serverEnabled && combined.isEmpty) {
        try {
          final deletedIds = await _getDeletedWorkoutIds();
          final page = await _fetchServerHistorySessionsFiltered(
            deletedIds: deletedIds,
            existingIds: const <String>{},
            limit: 50,
          );
          combined = page.sessions;
          cursor = page.nextCursor;
          serverHasMore = cursor != null;
        } catch (e) {
          // If server fetch fails, fall back to empty history + error footer.
          _loadMoreError = e.toString();
          serverHasMore = true;
        }
      }

      if (!mounted) return;
      setState(() {
        _serverEnabled = serverEnabled;
        _serverHasMore = serverHasMore;
        _serverCursor = cursor;
        _allSessions = combined;
        _isLoading = false;
        // Once we've completed a load WITH server access, an empty result is a
        // genuine empty history — not "still waiting for the token / a sync".
        if (serverEnabled) _didServerLoad = true;
      });
      _applyFiltersAndRebuild();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _allSessions = [];
        _sessions = [];
        _serverEnabled = false;
        _serverHasMore = false;
        _serverCursor = null;
        _isLoadingMore = false;
        _loadMoreError = null;
        _rebuildSessionMetadata();
      });
    }
  }

  Future<void> _loadMoreServerSessions() async {
    if (!_serverEnabled || !_serverHasMore) return;
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      final deletedIds = await _getDeletedWorkoutIds();
      final existingIds = _allSessions.map((s) => s.id).toSet();

      final page = await _fetchServerHistorySessionsFiltered(
        deletedIds: deletedIds,
        existingIds: existingIds,
        cursor: _serverCursor,
        limit: 50,
      );
      final appended = page.sessions;

      if (!mounted) return;
      setState(() {
        _serverCursor = page.nextCursor;
        _serverHasMore = page.nextCursor != null;
        _allSessions = [..._allSessions, ...appended];
        _isLoadingMore = false;
      });
      _applyFiltersAndRebuild();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = e.toString();
      });
    }
  }

  Future<void> _loadBannerState() async {
    final dismissed = await GetIt.instance<PreferencesService>()
        .isSyncBannerDismissed();
    if (!mounted) return;
    setState(() => _syncBannerDismissed = dismissed);
  }

  DateTime _normalizeDate(DateTime date) => DateUtils.dateOnly(date.toLocal());

  void _rebuildSessionMetadata() {
    final byDate = <DateTime, List<WorkoutSession>>{};
    final firstIndex = <DateTime, int>{};

    for (var i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];
      final date = _normalizeDate(session.startTime);
      byDate.putIfAbsent(date, () => []).add(session);
      firstIndex.putIfAbsent(date, () => i);
    }

    _sessionsByDate
      ..clear()
      ..addAll(byDate);
    _dateToFirstIndex
      ..clear()
      ..addAll(firstIndex);

    if (_selectedDay != null) {
      final normalizedSelection = _normalizeDate(_selectedDay!);
      if (_sessionsByDate.containsKey(normalizedSelection)) {
        _selectedDay = normalizedSelection;
      } else {
        _selectedDay = null;
      }
    }

    if (_selectedDay == null && _sessionsByDate.isNotEmpty) {
      _selectedDay = _sessionsByDate.keys.first;
    }

    if (_selectedDay != null) {
      _focusedDay = _selectedDay!;
    } else {
      _focusedDay = DateUtils.dateOnly(DateTime.now());
    }
  }

  bool get _hasActiveFilters =>
      _filterMuscleGroups.isNotEmpty || _filterRangeDays != null;

  List<WorkoutSession> _applyFilters(List<WorkoutSession> source) {
    if (_filterMuscleGroups.isEmpty && _filterRangeDays == null) {
      return List<WorkoutSession>.from(source);
    }

    final now = DateTime.now();
    final int? rangeDays = _filterRangeDays == null
        ? null
        : (_filterRangeDays!.clamp(1, 365)).toInt();
    final DateTime? start = rangeDays == null
        ? null
        : now.subtract(Duration(days: rangeDays));

    return source.where((session) {
      if (start != null) {
        final end = session.endTime ?? session.startTime;
        if (end.isBefore(start)) {
          return false;
        }
      }
      if (_filterMuscleGroups.isNotEmpty) {
        final sessionGroups = _muscleGroupsForSession(session);
        final matches = sessionGroups.any(_filterMuscleGroups.contains);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  Set<MuscleGroup> _muscleGroupsForSession(WorkoutSession session) {
    final groups = <MuscleGroup>{};
    for (final workoutExercise in session.exercises) {
      for (final muscle in workoutExercise.exercise.muscles) {
        groups.add(_muscleGroupMapper.groupFor(muscle));
      }
    }
    return groups;
  }

  void _applyFiltersAndRebuild() {
    if (!mounted) return;
    // Compute filtered list and memoize metrics outside setState so the
    // per-session exercise/set scan doesn't block the raster thread.
    final filtered = _applyFilters(_allSessions);
    _rebuildCardMetrics(filtered);
    setState(() {
      _sessions = filtered;
      _rebuildSessionMetadata();
    });
  }

  void _rebuildCardMetrics(List<WorkoutSession> sessions) {
    final ids = sessions.map((s) => s.id).toSet();
    // Evict metrics for sessions no longer in the filtered list.
    _metricsBySessionId.removeWhere((id, _) => !ids.contains(id));
    // Only compute metrics for sessions not already cached — this avoids
    // re-scanning exercises/sets for every session on every filter change.
    for (final session in sessions) {
      if (!_metricsBySessionId.containsKey(session.id)) {
        _metricsBySessionId[session.id] = HistorySessionMetrics.from(session);
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _filterMuscleGroups = {};
      _filterRangeDays = null;
    });
    _persistFilters();
    _applyFiltersAndRebuild();
  }

  String _filterDescription() {
    final parts = <String>[];
    if (_filterMuscleGroups.isNotEmpty) {
      final matchRegion = DisplayRegion.values.firstWhere((region) {
        final regionGroups = _mappableGroupsFor(region).toSet();
        return region != DisplayRegion.other &&
            regionGroups.isNotEmpty &&
            regionGroups.length == _filterMuscleGroups.length &&
            regionGroups.containsAll(_filterMuscleGroups);
      }, orElse: () => DisplayRegion.other);
      if (matchRegion != DisplayRegion.other) {
        parts.add(matchRegion.label);
      } else if (_filterMuscleGroups.length == 1) {
        parts.add(_filterMuscleGroups.first.label);
      } else {
        parts.add('${_filterMuscleGroups.length} muscle groups');
      }
    }
    if (_filterRangeDays != null) {
      parts.add('Last $_filterRangeDays days');
    }
    if (parts.isEmpty) {
      return 'Filters applied';
    }
    return parts.join(' · ');
  }

  void _scrollToDate(DateTime day) {
    final normalized = _normalizeDate(day);
    final index = _dateToFirstIndex[normalized];
    if (index == null || index >= _sessions.length) return;
    if (!_itemScrollController.isAttached) return;

    final listIndex = _historyListHeaderCount + (index * 2);
    _itemScrollController.scrollTo(
      index: listIndex,
      duration: AppMotion.slow,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _showCalendarSheet() async {
    if (_isLoading) return;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) {
        var sheetFocused = _focusedDay;
        DateTime? sheetSelected = _selectedDay;

        return StatefulBuilder(
          builder: (context, bottomSetState) {
            final theme = Theme.of(context);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text(
                      'Jump to a workout',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _HistoryCalendar(
                        focusedDay: sheetFocused,
                        selectedDay: sheetSelected,
                        sessionsByDate: _sessionsByDate,
                        onDaySelected: (selectedDay, focusedDay) {
                          // Selecting a day jumps the list — pair the jump with
                          // a selection tick (preference-aware, no-op on web).
                          Haptics.selection();
                          final normalizedSelected = _normalizeDate(
                            selectedDay,
                          );
                          final normalizedFocused = _normalizeDate(focusedDay);
                          bottomSetState(() {
                            sheetSelected = normalizedSelected;
                            sheetFocused = normalizedFocused;
                          });
                          if (!mounted) return;
                          setState(() {
                            _selectedDay = normalizedSelected;
                            _focusedDay = normalizedFocused;
                          });
                          context.pop();
                          _scrollToDate(normalizedSelected);
                        },
                        onPageChanged: (focusedDay) {
                          final normalizedFocused = _normalizeDate(focusedDay);
                          bottomSetState(() {
                            sheetFocused = normalizedFocused;
                          });
                          if (!mounted) return;
                          setState(() {
                            _focusedDay = normalizedFocused;
                          });
                        },
                      ),
                    ),
                  ),
                  if (_sessionsByDate.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'Finish a workout and the day lights up here, ready to jump to.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showFilterSheet() async {
    if (_isLoading) return;
    final result = await showHistoryFilterSheet(
      context,
      selectedGroups: _filterMuscleGroups,
      selectedRangeDays: _filterRangeDays,
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterMuscleGroups = {...result.muscleGroups};
      _filterRangeDays = result.rangeDays;
    });
    _persistFilters();
    _applyFiltersAndRebuild();
  }

  void _startWorkoutFromSession(WorkoutSession session) {
    context.go(
      '/workout_session',
      extra: workoutRouteExtra(context, {
        'initialName': session.name,
        'initialExercises': session.exercises
            .map(
              (e) => {
                'name': e.exercise.name,
                'sets': e.sets.length,
                'rest': e.restTimerSeconds,
                // Provide the exact sets from this history session
                'previousSets': e.sets.map((s) => s.toMap()).toList(),
              },
            )
            .toList(),
      }),
    );
  }

  Future<WorkoutSession?> _fetchRemoteSessionDetail(String sessionId) async {
    try {
      final map = await _historyApi.fetchWorkoutDetail(sessionId);
      return WorkoutServerMapper.sessionFromServerMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _startWorkoutFromSessionId(String sessionId) async {
    if (!mounted) return;
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    // Use the root navigator context so the dialog isn't tied to this route's
    // lifecycle. Always dismiss it, even if this widget unmounts.
    showDialog<void>(
      context: rootNavigator.context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) =>
          const PopScope(canPop: false, child: HustlInlineSkeleton()),
    );

    WorkoutSession? detail;
    try {
      detail = await _fetchRemoteSessionDetail(sessionId);
    } finally {
      if (rootNavigator.mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
    }

    if (!mounted) return;

    if (detail == null) {
      final fallback = _allSessions.cast<WorkoutSession?>().firstWhere(
        (s) => s?.id == sessionId,
        orElse: () => null,
      );
      if (fallback != null) {
        _startWorkoutFromSession(fallback);
        return;
      }
      HustlSnack.show(
        context,
        'We couldn\'t load this workout\'s details.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    _startWorkoutFromSession(detail);
  }

  void _openSummary(WorkoutSession session) {
    context.push('/summary/${session.id}');
  }

  /// Long-press action menu. Tap goes straight to the summary, so this menu is
  /// where the secondary actions live.
  Future<void> _showSessionActions(WorkoutSession session) async {
    final hasDetails = session.exercises.isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final errorColor = theme.colorScheme.error;
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('View summary'),
                onTap: () {
                  sheetContext.pop();
                  _openSummary(session);
                },
              ),
              if (hasDetails)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit workout'),
                  onTap: () async {
                    sheetContext.pop();
                    await context.push('/workout_edit/${session.id}');
                    if (mounted) {
                      await _loadSessions();
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Repeat this workout'),
                onTap: () {
                  sheetContext.pop();
                  if (hasDetails) {
                    _startWorkoutFromSession(session);
                  } else {
                    _startWorkoutFromSessionId(session.id);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: errorColor),
                title: Text(
                  'Delete workout',
                  style: TextStyle(color: errorColor),
                ),
                onTap: () async {
                  sheetContext.pop();
                  final confirmed = await _confirmDelete();
                  if (confirmed) {
                    await _deleteSession(session);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete workout'),
        content: const Text(
          'Are you sure you want to delete this workout session? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => dialogContext.pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteSession(WorkoutSession session) async {
    await Haptics.maybeMediumImpact();
    if (!mounted) return;
    await GetIt.instance<WorkoutRepository>().deleteWorkoutSession(session.id);
    if (!mounted) return;
    await _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: const Text('History'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Open calendar',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _showCalendarSheet(),
          ),
          IconButton(
            tooltip: _hasActiveFilters ? 'Filters active' : 'Filters',
            isSelected: _hasActiveFilters,
            icon: const Icon(Icons.filter_alt_outlined),
            selectedIcon: Icon(
              Icons.filter_alt,
              color: theme.colorScheme.primary,
            ),
            onPressed: _showFilterSheet,
          ),
          const HustlMenuButton(),
          const SizedBox(width: AppSpacing.x1),
        ],
      ),
      child: _isLoading
          ? const HustlInlineSkeleton()
          : _error != null
          ? ScreenEmptyState(
              icon: Icons.cloud_off_outlined,
              title: "We couldn't load your history",
              message: _error,
              actionLabel: 'Try again',
              onAction: _loadSessions,
            )
          : RefreshIndicator(
              onRefresh: () async {
                // Try syncing with backend then reload local sessions
                try {
                  if (GetIt.instance.isRegistered<WorkoutSyncService>()) {
                    await GetIt.instance<WorkoutSyncService>().syncNow();
                  }
                } catch (_) {}
                await _loadSessions();
              },
              child: ScrollablePositionedList.builder(
                itemScrollController: _itemScrollController,
                itemPositionsListener: _itemPositionsListener,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x2,
                  AppSpacing.x1 + 4,
                  AppSpacing.x2,
                  AppSpacing.x4,
                ),
                itemCount: _computeListItemCount(),
                itemBuilder: (context, index) =>
                    _wideCenter(context, _buildHistoryListItem(context, index)),
              ),
            ),
    );
  }

  /// On wide viewports (>= 900) the history list lives inside a ~1200 shell, so
  /// a single column of full-width cards reads as sprawling and sparse. Rather
  /// than re-flow the ScrollablePositionedList into a true two-column masonry —
  /// which would corrupt the strict per-session index math that drives
  /// jump-to-date (`_scrollToDate`), infinite-scroll paging
  /// (`_handleScrollPositions`), and the staggered entrance — each row is
  /// centred inside a comfortable reading column. The list, its index mapping,
  /// scroll, tap-to-open, and paging stay byte-for-byte identical; only the
  /// horizontal bounds of each item change, and only at and above 900. Below
  /// 900 the child is returned untouched.
  Widget _wideCenter(BuildContext context, Widget child) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < ResponsiveCenter.wideBreakpoint) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _wideHistoryColumnWidth),
        child: child,
      ),
    );
  }

  /// Comfortable reading width for the history column on wide viewports.
  static const double _wideHistoryColumnWidth = 760;

  int _computeListItemCount() {
    if (_sessions.isEmpty) {
      return _historyListHeaderCount + 1;
    }
    final base = _historyListHeaderCount + (_sessions.length * 2) - 1;
    final showFooter =
        _serverEnabled || _isLoadingMore || _loadMoreError != null;
    return base + (showFooter ? 1 : 0);
  }

  Widget _buildHistoryListItem(BuildContext context, int index) {
    if (index == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SyncBanner(
            hidden: _syncBannerDismissed,
            onDismiss: () async {
              await GetIt.instance<PreferencesService>().dismissSyncBanner();
              if (!mounted) return;
              setState(() => _syncBannerDismissed = true);
            },
          ),
          const SizedBox(height: 8),
          _SyncStatusBanner(),
        ],
      );
    }

    if (index == 1) {
      if (_hasActiveFilters) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterNotice(
              description: 'Filtering: ${_filterDescription()}',
              onClear: _clearFilters,
            ),
            const SizedBox(height: 16),
          ],
        );
      }
      return const SizedBox(height: 16);
    }

    if (_sessions.isEmpty) {
      if (_serverEnabled && (_isLoadingMore || _loadMoreError != null)) {
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: _HistoryPagingFooter(
            isLoading: _isLoadingMore,
            error: _loadMoreError,
            hasMore: true,
            onRetry: _loadMoreServerSessions,
          ),
        );
      }
      if (!_hasActiveFilters && _isAwaitingFirstSync(context)) {
        return const _SyncingHistoryMessage();
      }
      return _EmptyHistoryMessage(
        filtered: _hasActiveFilters,
        onClearFilters: _clearFilters,
      );
    }

    final baseCount = _historyListHeaderCount + (_sessions.length * 2) - 1;
    final showFooter =
        _serverEnabled || _isLoadingMore || _loadMoreError != null;
    if (showFooter && index == baseCount) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _HistoryPagingFooter(
          isLoading: _isLoadingMore,
          error: _loadMoreError,
          hasMore: _serverHasMore,
          onRetry: _loadMoreServerSessions,
        ),
      );
    }

    final sessionListIndex = index - _historyListHeaderCount;
    if (sessionListIndex.isEven) {
      final sessionIndex = sessionListIndex ~/ 2;
      final session = _sessions[sessionIndex];
      final metrics =
          _metricsBySessionId[session.id] ??
          HistorySessionMetrics.from(session);
      final card = RepaintBoundary(
        child: HistorySessionCard(
          session: session,
          metrics: metrics,
          onOpenSummary: () => _openSummary(session),
          onLongPress: () => _showSessionActions(session),
          onSwipeDelete: () async {
            final confirmed = await _confirmDelete();
            if (confirmed) {
              await _deleteSession(session);
            }
            // Always return false: the list reloads itself after a confirmed
            // delete, so we never let Dismissible remove the tile directly.
            return false;
          },
        ),
      );
      return KeyedSubtree(
        key: ValueKey(session.id),
        child: _maybeStagger(sessionIndex, session.id, card),
      );
    }

    // Wave I: each session is its own elevated card, so the separator between
    // cards is breathing room rather than a hairline ledger divider.
    return const SizedBox(height: AppSpacing.x2);
  }

  /// Applies the staggered entrance to the first few cards, once per session.
  Widget _maybeStagger(int sessionIndex, String sessionId, Widget child) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion ||
        _isTestEnv() ||
        sessionIndex >= AppMotion.staggerMaxItems ||
        _staggeredSessionIds.contains(sessionId)) {
      return child;
    }
    _staggeredSessionIds.add(sessionId);
    return StaggeredCardEntrance(index: sessionIndex, child: child);
  }
}

class _EmptyHistoryMessage extends StatelessWidget {
  const _EmptyHistoryMessage({this.filtered = false, this.onClearFilters});

  final bool filtered;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    if (filtered) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
        child: ScreenEmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'No workouts match these filters',
          message: 'Try a wider date range or a different body region.',
          actionLabel: 'Clear filters',
          onAction: onClearFilters,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
      child: ScreenEmptyState(
        icon: Icons.fitness_center,
        assetIcon: 'assets/icons/empty_history.svg',
        title: 'Your training story starts here',
        message:
            'Finish your first workout and it lands here — every set, streak, and '
            'volume trend you build over time.',
        actionLabel: 'Start your first workout',
        onAction: () => GoRouter.of(context).go('/'),
      ),
    );
  }
}

/// Shown in place of the empty "training story" state while we're still pulling
/// the signed-in user's history from the server — so a synced account never
/// looks like a blank slate that needs a manual pull-to-refresh.
class _SyncingHistoryMessage extends StatelessWidget {
  const _SyncingHistoryMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.x4),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text('Syncing your workouts…', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.x1),
          Text(
            'Pulling your training history from the cloud.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPagingFooter extends StatelessWidget {
  const _HistoryPagingFooter({
    required this.isLoading,
    required this.error,
    required this.hasMore,
    required this.onRetry,
  });

  final bool isLoading;
  final String? error;
  final bool hasMore;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading older workouts…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      );
    }

    if (error != null && error!.isNotEmpty) {
      return Center(
        child: TextButton.icon(
          onPressed: () => onRetry(),
          icon: Icon(Icons.refresh, color: theme.colorScheme.primary),
          label: Text(
            'Retry loading older workouts',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (!hasMore) {
      return Center(
        child: Text(
          'You’ve reached the start of your history.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return Center(
      child: Text(
        'Scroll to load older workouts.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _FilterNotice extends StatelessWidget {
  const _FilterNotice({required this.description, required this.onClear});

  final String description;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Wave G §12.1: flat inline row — no card chrome.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(description, style: theme.textTheme.bodyLarge)),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  final bool hidden;
  final Future<void> Function() onDismiss;
  const _SyncBanner({required this.hidden, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isAuthed = state is AuthAuthenticated;
        if (isAuthed || hidden) return const SizedBox.shrink();
        return SyncPromptCard(
          title: 'Sign in to sync',
          subtitle: 'Back up your workout history and sync across devices.',
          ctaLabel: 'Sign in',
          onCtaPressed: () => showLoginSheet(context),
          onDismiss: onDismiss,
          showBenefits: false,
        );
      },
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!GetIt.instance.isRegistered<WorkoutSyncService>()) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final svc = GetIt.instance<WorkoutSyncService>();
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: svc.status,
      builder: (context, status, _) {
        if (status != SyncStatus.degraded) {
          return const SizedBox.shrink();
        }
        // Wave G §12.1: flat inline status row — no card chrome.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Some workouts may not be backed up yet. We’ll sync them when possible.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Map<DateTime, List<WorkoutSession>> sessionsByDate;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final ValueChanged<DateTime>? onPageChanged;

  const _HistoryCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.sessionsByDate,
    required this.onDaySelected,
    this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    List<WorkoutSession> eventsForDay(DateTime day) {
      return sessionsByDate[DateUtils.dateOnly(day)] ?? const [];
    }

    DateTime minDate;
    DateTime maxDate;
    if (sessionsByDate.isEmpty) {
      final today = DateUtils.dateOnly(DateTime.now());
      minDate = today;
      maxDate = today;
    } else {
      final dates = sessionsByDate.keys.toList()
        ..sort((a, b) => a.compareTo(b));
      minDate = dates.first;
      maxDate = dates.last;
    }

    final firstDay = minDate.subtract(const Duration(days: 365));
    final lastDay = maxDate.add(const Duration(days: 365));
    final clampedFocusedDay = focusedDay.isBefore(firstDay)
        ? firstDay
        : focusedDay.isAfter(lastDay)
        ? lastDay
        : focusedDay;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: TableCalendar<WorkoutSession>(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: clampedFocusedDay,
          calendarFormat: CalendarFormat.month,
          sixWeekMonthsEnforced: true,
          startingDayOfWeek: StartingDayOfWeek.monday,
          availableGestures: AvailableGestures.horizontalSwipe,
          onDaySelected: onDaySelected,
          onPageChanged: onPageChanged,
          selectedDayPredicate: (day) =>
              selectedDay != null && isSameDay(selectedDay, day),
          eventLoader: eventsForDay,
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle:
                theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ) ??
                const TextStyle(fontWeight: FontWeight.w700),
            leftChevronIcon: Icon(
              Icons.chevron_left,
              color: theme.colorScheme.onSurface,
            ),
            rightChevronIcon: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface,
            ),
          ),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(color: theme.colorScheme.onSurface),
            selectedDecoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
            markerDecoration: BoxDecoration(
              color: theme.colorScheme.tertiary,
              shape: BoxShape.circle,
            ),
            markersAlignment: Alignment.bottomCenter,
            markersMaxCount: 1,
          ),
          calendarBuilders: CalendarBuilders<WorkoutSession>(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return const SizedBox.shrink();
              final markerColor = Theme.of(context).colorScheme.tertiary;
              return Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: markerColor,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// Removed Strong import flow from History; now available in Settings.
