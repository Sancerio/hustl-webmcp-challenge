import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/workout_widget_service.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/load_recovery_trend.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/recovery_trend_card.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/segmented_pill_selector.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_utils.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/date_range_filter.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_balance_card.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_empty_state.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_hero_section.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/weekly_consistency_card.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import '../widgets/progress_charts.dart';
import '../../domain/services/body_score_service.dart';

class _ProgressConfig {
  static const int topPrsLimit = 20;
  static const int topDisplayLimit = 5;
  static const int summaryWeeksCount = 4;
  // Consistency hero reads as a forgiving 12-week rate ('hit goal N of last 12
  // weeks') — a process metric, not a fragile streak.
  static const int goalWindowWeeks = 12;
  static const double minChartHeight = 180;
  static const double maxChartHeight = 280;

  static double chartHeight(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.28;
    return height.clamp(minChartHeight, maxChartHeight);
  }
}

class WorkoutProgressScreen extends StatefulWidget {
  const WorkoutProgressScreen({super.key});

  @override
  State<WorkoutProgressScreen> createState() => _WorkoutProgressScreenState();
}

class _WorkoutProgressScreenState extends State<WorkoutProgressScreen> {
  final _workoutRepository = GetIt.instance<WorkoutRepository>();
  final _prefs = GetIt.instance<PreferencesService>();
  final DateTime _referenceNow = DateTime.now();
  final List<BodyScoreStrategy> _bodyScoreStrategies =
      BodyScoreStrategies.defaults;
  late final Map<String, BodyScoreService> _bodyScoreServices = {
    for (final strategy in _bodyScoreStrategies)
      strategy.id: BodyScoreService(
        config: BodyScoreConfig(loadStrategy: strategy.loadStrategy),
      ),
  };
  BodyScoreStrategy get _primaryBodyScoreStrategy => _bodyScoreStrategies.first;
  BodyScoreService get _primaryBodyScoreService =>
      _bodyScoreServices[_primaryBodyScoreStrategy.id]!;
  bool _loading = true;
  bool _transitioning = false;
  String? _error;
  List<WorkoutSession> _sessions = [];
  DateTimeRange? _dateRange;
  List<WorkoutSession> _filteredSessions = [];
  Map<String, double> _weeklyVolume = {};
  Map<String, double> _chartVolume = {};
  TimeGroup _timeGroup = TimeGroup.week;
  bool _userSetGroup = false;
  double _lastWeeksVolume = 0;
  double _prevWeeksVolume = 0;
  // Per-display-region weekly-equivalent sets (label → sets, most-trained first)
  // for the Training-balance card — surfaces the muscle balance BodyScoreService
  // already computes, which the Progress tab never linked to.
  Map<String, double> _balanceRegionSets = const {};
  int _weeklyGoal = 3;
  Map<String, int> _workoutsPerWeek = const {};
  int _goalHitWeeks = 0;
  // Compact recovery trend for the Progress "Recovery trend" card. Loaded
  // best-effort from the same pipeline Health uses; stays null (card absent)
  // when health DI is unregistered or there is no usable recovery data, so the
  // screen renders exactly as today for users without health permissions.
  List<DailyRecoverySnapshot>? _recoveryTrend;

  @override
  void initState() {
    super.initState();
    _initPrefsAndLoad();
    _loadRecoveryTrend();
  }

  Future<void> _loadRecoveryTrend() async {
    if (!GetIt.instance.isRegistered<LoadRecoveryTrendUseCase>()) return;
    try {
      final trend = await GetIt.instance<LoadRecoveryTrendUseCase>()();
      if (!mounted) return;
      setState(() => _recoveryTrend = trend);
    } catch (_) {
      // Best-effort; Progress renders exactly as today without the trend.
    }
  }

  Future<void> _initPrefsAndLoad() async {
    final quickIndex = await _prefs.getRecordQuickRangeIndex();
    final groupIndex = await _prefs.getRecordTimeGroupIndex();
    if (groupIndex != null &&
        groupIndex >= 0 &&
        groupIndex < TimeGroup.values.length) {
      _timeGroup = TimeGroup.values[groupIndex];
      _userSetGroup = true;
    }
    if (quickIndex != null &&
        quickIndex >= 0 &&
        quickIndex < QuickDateRange.values.length) {
      final q = QuickDateRange.values[quickIndex];
      _dateRange = quickDateRange(q);
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final weeklyGoal = await _loadWeeklyGoal();
      final sessions = await _workoutRepository.getWorkoutSessions(
        startDate: DateTime.fromMillisecondsSinceEpoch(0),
      );
      setState(() {
        _sessions = sessions.where((s) => s.isCompleted).toList();
        _weeklyGoal = weeklyGoal;
        _updateDerivedData();
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to load sessions: $e');
        debugPrintStack(stackTrace: st);
      }
      setState(() {
        _error = 'Failed to load data';
        _sessions = [];
        _updateDerivedData();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<int> _loadWeeklyGoal() async {
    try {
      return await _prefs.getWeeklyWorkoutGoal();
    } catch (_) {
      return 3;
    }
  }

  void _onDateRangeChanged(DateTimeRange? range) {
    setState(() {
      _transitioning = true;
      _dateRange = range;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _updateDerivedData();
        _transitioning = false;
      });
    });
  }

  void _updateDerivedData() {
    _filteredSessions = filterSessionsByDate(_sessions, _dateRange);
    _workoutsPerWeek = aggregateWorkoutsPerIsoWeek(
      _sessions.map((session) => session.startTime),
    );
    if (!_userSetGroup) {
      _timeGroup = _computeGroup();
    }
    _weeklyVolume = aggregateWeeklyVolume(_filteredSessions);
    _chartVolume = aggregateVolumeByPeriod(_filteredSessions, _timeGroup);
    _lastWeeksVolume = lastNWeeksVolume(
      _weeklyVolume,
      _ProgressConfig.summaryWeeksCount,
    );
    _prevWeeksVolume = prevNWeeksVolume(
      _weeklyVolume,
      _ProgressConfig.summaryWeeksCount,
    );
    _goalHitWeeks = goalHitWeeks(
      countsByWeek: _workoutsPerWeek,
      weeklyGoal: _weeklyGoal,
      windowWeeks: _ProgressConfig.goalWindowWeeks,
      now: _referenceNow,
    );
    _balanceRegionSets = _computeBalanceRegionSets();
  }

  /// Per-display-region weekly-equivalent sets (label → sets, sorted most-first)
  /// for the Training-balance card. Reuses the same BodyScoreService aggregate
  /// the removed "avg hard sets" stat used, rolled up to the 6 display regions.
  Map<String, double> _computeBalanceRegionSets() {
    if (_filteredSessions.isEmpty) return const {};
    DateTimeRange? range = _dateRange;
    range ??= _rangeFromSessions(_filteredSessions);
    if (range == null) return const {};
    final metrics = _primaryBodyScoreService.aggregateForRange(
      _filteredSessions,
      range,
    );
    final int rangeDays = range.end.difference(range.start).inDays + 1;
    final double weeks = rangeDays > 7 ? rangeDays / 7.0 : 1.0;
    final Map<DisplayRegion, double> byRegion = {};
    metrics.forEach((group, metric) {
      final region = group.displayRegion;
      byRegion.update(
        region,
        (v) => v + metric.sets,
        ifAbsent: () => metric.sets,
      );
    });
    final entries = byRegion.entries.where((e) => e.value > 0).map((e) {
      return MapEntry(e.key.label, e.value / weeks);
    }).toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  DateTimeRange? _rangeFromSessions(List<WorkoutSession> sessions) {
    if (sessions.isEmpty) {
      return null;
    }
    DateTime start = sessions.first.startTime;
    DateTime end = sessions.first.endTime ?? sessions.first.startTime;
    for (final session in sessions.skip(1)) {
      if (session.startTime.isBefore(start)) {
        start = session.startTime;
      }
      final candidateEnd = session.endTime ?? session.startTime;
      if (candidateEnd.isAfter(end)) {
        end = candidateEnd;
      }
    }
    if (end.isBefore(start)) {
      end = start;
    }
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _onWeeklyGoalChanged(int goal) async {
    await _prefs.setWeeklyWorkoutGoal(goal);
    if (GetIt.instance.isRegistered<WorkoutWidgetService>()) {
      await GetIt.instance<WorkoutWidgetService>()
          .updateWorkoutsPerWeekWidget();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _weeklyGoal = goal;
    });
  }

  TimeGroup _computeGroup() {
    if (_dateRange == null) return TimeGroup.month;
    final days = _dateRange!.end.difference(_dateRange!.start).inDays;
    if (days <= 7) return TimeGroup.day;
    if (days <= 90) return TimeGroup.week;
    return TimeGroup.month;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: const Text('Progress'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: const [
          HustlMenuButton(),
          SizedBox(width: AppSpacing.x1),
        ],
      ),
      child: _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loading) {
      return const ProgressSkeleton();
    }

    if (_error != null) {
      return _buildErrorState(theme);
    }

    if (_sessions.isEmpty) {
      return ProgressEmptyState(
        hasWorkoutsInOtherRanges: false,
        onLogWorkout: () => context.go('/'),
      );
    }

    if (_filteredSessions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: AppSpacing.screen,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            DateRangeFilter(
              range: _dateRange,
              onChanged: _onDateRangeChanged,
              onQuickRangeChanged: (qr) async {
                await _prefs.setRecordQuickRangeIndex(qr?.index);
              },
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: ProgressEmptyState(
                hasWorkoutsInOtherRanges: true,
                onLogWorkout: () => context.go('/'),
                onClearFilter: () => _onDateRangeChanged(null),
              ),
            ),
          ],
        ),
      );
    }

    final filter = DateRangeFilter(
      range: _dateRange,
      onChanged: _onDateRangeChanged,
      onQuickRangeChanged: (qr) async {
        await _prefs.setRecordQuickRangeIndex(qr?.index);
      },
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x4,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Date range filter — spans the full content width in both layouts.
          filter,
          const SizedBox(height: AppSpacing.x3),
          LayoutBuilder(
            builder: (context, constraints) {
              // Wave: on wide viewports (landscape tablet / desktop) reflow the
              // page's blocks into two columns to use the capped width. Below
              // 900 we emit the original single-column sequence unchanged.
              if (constraints.maxWidth >= 880) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _wideLeftColumnBlocks(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _wideRightColumnBlocks(),
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _narrowColumnBlocks(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Reusable content blocks ───────────────────────────────────────────────
  // Each getter returns a self-contained block so the narrow (original order)
  // and wide (two-column) layouts compose the same widgets without divergence.

  Widget get _heroBlock => ProgressHeroSection(
    goalHitWeeks: _goalHitWeeks,
    goalWindowWeeks: _ProgressConfig.goalWindowWeeks,
    weeklyGoal: _weeklyGoal,
    lastWeeksVolume: _lastWeeksVolume,
    prevWeeksVolume: _prevWeeksVolume,
    weeksCount: _ProgressConfig.summaryWeeksCount,
    weeklyVolumeSeries: _weeklyVolume.values.toList(growable: false),
  );

  Widget get _trainingBalance => ProgressBalanceCard(
    regionSets: _balanceRegionSets,
    onTap: () => context.push('/progress/body-score'),
  );

  Widget get _weeklyConsistency => WeeklyConsistencyCard(
    countsByWeek: _workoutsPerWeek,
    weeklyGoal: _weeklyGoal,
    now: _referenceNow,
    onGoalChanged: _onWeeklyGoalChanged,
  );

  // True only when a usable recovery trend is loaded — used to gate the card
  // AND its surrounding spacing so users without health data see a
  // pixel-identical Progress screen.
  bool get _hasRecoveryTrend =>
      _recoveryTrend != null && _recoveryTrend!.isNotEmpty;

  Widget get _recoveryTrendCard =>
      RecoveryTrendCard(snapshots: _recoveryTrend ?? const []);

  Widget get _volumeTrendsHeader => SectionHeader(
    'Volume trends',
    // Cap the toggle at 200px but let it shrink on narrow widths so the
    // title + toggle never force a horizontal overflow.
    trailing: Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: _buildTimeGroupToggle(),
      ),
    ),
  );

  Widget get _volumeChart => _VolumeChart(
    data: _chartVolume,
    group: _timeGroup,
    loading: _transitioning,
  );

  Widget get _sessionsHeader => const SectionHeader('Sessions by workout');

  Widget get _sessionsBreakdown => _BreakdownList(
    data: sessionsByWorkout(_filteredSessions),
    formatValue: (v) => NumberFormatUtil.formatDouble(v, decimalDigits: 0),
    limit: _ProgressConfig.topDisplayLimit,
    loading: _transitioning,
    emptyMessage: 'No sessions in this range yet',
  );

  Widget get _prsHeader => const SectionHeader('Top lifts (est. 1RM)');

  // Estimated 1RM (Epley, reps capped at 12) instead of raw max weight, so the
  // bars reflect real strength — bench 100×1 and squat 100×10 no longer read the
  // same, and a heavy-but-low-rep set can't masquerade as a strength PR.
  Widget get _prsBreakdown => _BreakdownList(
    data: topE1rmByExercise(
      _filteredSessions,
      limit: _ProgressConfig.topPrsLimit,
    ),
    formatValue: (v) =>
        '${NumberFormatUtil.formatDouble(v, decimalDigits: 0)} kg',
    limit: _ProgressConfig.topDisplayLimit,
    loading: _transitioning,
    emptyMessage: 'No lifts in this range yet',
  );

  /// Original single-column sequence — kept byte-for-byte for phones + tablet
  /// portrait (below 900).
  List<Widget> _narrowColumnBlocks() {
    return [
      _heroBlock,
      const SizedBox(height: AppSpacing.x3),
      _trainingBalance,
      const SizedBox(height: AppSpacing.x3),
      _weeklyConsistency,
      if (_hasRecoveryTrend) ...[
        const SizedBox(height: AppSpacing.x3),
        _recoveryTrendCard,
      ],
      const SizedBox(height: AppSpacing.x2),
      _volumeTrendsHeader,
      _volumeChart,
      _sessionsHeader,
      _sessionsBreakdown,
      _prsHeader,
      _prsBreakdown,
      const SizedBox(height: AppSpacing.x3),
    ];
  }

  /// Wide left column — the Tier-1 hero + the Training-balance card.
  List<Widget> _wideLeftColumnBlocks() {
    return [
      _heroBlock,
      const SizedBox(height: AppSpacing.x3),
      _trainingBalance,
      const SizedBox(height: AppSpacing.x3),
    ];
  }

  /// Wide right column — consistency + volume trends + breakdowns.
  List<Widget> _wideRightColumnBlocks() {
    return [
      _weeklyConsistency,
      if (_hasRecoveryTrend) ...[
        const SizedBox(height: AppSpacing.x3),
        _recoveryTrendCard,
      ],
      _volumeTrendsHeader,
      _volumeChart,
      _sessionsHeader,
      _sessionsBreakdown,
      _prsHeader,
      _prsBreakdown,
      const SizedBox(height: AppSpacing.x3),
    ];
  }

  Widget _buildErrorState(ThemeData theme) {
    return ScreenEmptyState(
      icon: Icons.cloud_off_outlined,
      title: "We couldn't load your progress",
      message: _error,
      actionLabel: 'Try again',
      onAction: _load,
    );
  }

  Widget _buildTimeGroupToggle() {
    return SegmentedPillSelector<TimeGroup>(
      key: const ValueKey('progress_time_group_toggle'),
      options: TimeGroup.values,
      selected: _timeGroup,
      labels: const {
        TimeGroup.day: 'Day',
        TimeGroup.week: 'Week',
        TimeGroup.month: 'Month',
      },
      onSelect: (g) async {
        if (g == _timeGroup) return;
        Haptics.selection();
        setState(() {
          _timeGroup = g;
          _userSetGroup = true;
          _chartVolume = aggregateVolumeByPeriod(_filteredSessions, _timeGroup);
        });
        await _prefs.setRecordTimeGroupIndex(_timeGroup.index);
      },
    );
  }
}

/// Edge-to-edge borderless volume chart (Wave G §12.4). No card frame: the
/// SectionHeader above carries the section voice; a quiet caption names the
/// period and unit.
class _VolumeChart extends StatelessWidget {
  const _VolumeChart({
    required this.data,
    required this.group,
    this.loading = false,
  });

  final Map<String, double> data;
  final TimeGroup group;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HustlIcon(
                asset: 'assets/icons/empty_chart.svg',
                size: 28,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.x1 + 4),
              Text(
                'No volume logged in this range — log a session to fill the chart.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_caption(), style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.x1),
        Semantics(
          label: 'Volume chart',
          child: RepaintBoundary(
            child: AnimatedOpacity(
              opacity: loading ? 0.4 : 1.0,
              duration: AppMotion.fast,
              child: SizedBox(
                height: _ProgressConfig.chartHeight(context),
                child: LineChartTimeSeries(
                  data: data,
                  group: group,
                  yUnit: 'kg',
                ),
              ),
            ),
          ),
        ),
        Container(height: 1, color: colorScheme.outlineVariant),
      ],
    );
  }

  String _caption() {
    switch (group) {
      case TimeGroup.day:
        return 'Weight × reps per day';
      case TimeGroup.week:
        return 'Weight × reps per week';
      case TimeGroup.month:
        return 'Weight × reps per month';
    }
  }
}

/// Flat categorical breakdown (sessions, PRs) as aligned bar rows — no card.
class _BreakdownList extends StatefulWidget {
  const _BreakdownList({
    required this.data,
    required this.formatValue,
    this.limit,
    this.loading = false,
    this.emptyMessage = 'Nothing logged in this range yet',
  });

  final Map<String, double> data;
  final String Function(double) formatValue;
  final int? limit;
  final bool loading;

  /// Inviting line shown when [data] is empty, in place of a bare "No data".
  final String emptyMessage;

  @override
  State<_BreakdownList> createState() => _BreakdownListState();
}

class _BreakdownListState extends State<_BreakdownList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.data.entries.toList();
    final displayEntries =
        widget.limit != null && !_expanded && entries.length > widget.limit!
        ? entries.sublist(0, widget.limit!)
        : entries;
    final displayData = Map.fromEntries(displayEntries);

    if (widget.data.isEmpty) {
      final colorScheme = theme.colorScheme;
      // Keep the section's shape with a couple of faint ghost rows instead of
      // collapsing to two words, and lead with an inviting, specific line.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _GhostBarRow(widthFactor: 0.7),
            const SizedBox(height: AppSpacing.x1 + 4),
            const _GhostBarRow(widthFactor: 0.45),
            const SizedBox(height: AppSpacing.x2),
            Text(
              widget.emptyMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Breakdown chart',
          child: RepaintBoundary(
            child: AnimatedOpacity(
              opacity: widget.loading ? 0.4 : 1.0,
              duration: AppMotion.fast,
              child: SimpleHorizontalBars(
                data: displayData,
                formatValue: widget.formatValue,
              ),
            ),
          ),
        ),
        if (widget.limit != null && entries.length > widget.limit!)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _expanded = !_expanded;
              }),
              child: Text(_expanded ? 'Show less' : 'Show more'),
            ),
          ),
      ],
    );
  }
}

/// A single faint, bar-shaped ghost row used to preserve a breakdown section's
/// shape when there is no data yet — a quiet placeholder, not a spinner.
class _GhostBarRow extends StatelessWidget {
  const _GhostBarRow({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}
