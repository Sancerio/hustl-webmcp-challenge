import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/coaching/coach_insight.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/utils/date_only.dart';
import '../../../../core/utils/health_platform_labels.dart';
import '../../../../core/widgets/coach_card.dart';
import '../../../../core/widgets/hustl_icon.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../health_sync/domain/repositories/health_metrics_repository.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import '../nutrition_view_cache.dart';
import '../utils/goal_rate_color.dart';
import '../utils/weight_unit.dart';
import '../widgets/charts/chart_changes_card.dart';
import '../widgets/charts/chart_granularity.dart';
import '../widgets/charts/chart_legend_card.dart';
import '../widgets/charts/chart_range_bar.dart';
import '../widgets/charts/chart_stat_header.dart';
import '../widgets/charts/trend_change_rows.dart';
import '../widgets/scale_weighin_list_card.dart';
import '../widgets/today_log_prompt.dart';
import '../widgets/weight_coach.dart';
import '../widgets/weight_trend_cards.dart';
import '../widgets/weight_source_card.dart';
import '../widgets/weight_entry_sheet.dart';

class WeightTrendScreen extends StatefulWidget {
  const WeightTrendScreen({super.key});

  @override
  State<WeightTrendScreen> createState() => _WeightTrendScreenState();
}

class _WeightTrendScreenState extends State<WeightTrendScreen> {
  final _repo = GetIt.instance<NutritionTargetsRepository>();
  final _healthRepo = GetIt.instance<HealthMetricsRepository>();
  late Future<Map<String, dynamic>> _future;
  late Future<HealthPermissionsStatus> _healthPermissionsFuture;
  Map<String, dynamic>? _cachedWeight;

  // Resolved once from prefs (async), then formatting is pure + per-frame safe.
  WeightUnit _unit = const WeightUnit('kg');

  final DateTime _end = DateTime.now();
  int _rangeDays = 30; // 0 == All.
  ChartGranularity _granularity = ChartGranularity.day;
  bool _showScale = true;
  bool _showTrend = true;
  bool _fitYAxis = false;

  static const _rangeLabels = {
    7: '1W',
    30: '1M',
    90: '3M',
    180: '6M',
    365: '1Y',
    0: 'All',
  };

  @override
  void initState() {
    super.initState();
    _granularity = defaultGranularity(_rangeDays);
    _future = _load();
    _healthPermissionsFuture = _healthRepo.getPermissionsStatus();
    _resolveUnit();
  }

  Future<void> _resolveUnit() async {
    final u = await PreferencesService().getWeightUnit();
    if (!mounted) return;
    setState(() => _unit = WeightUnit(u));
  }

  Future<Map<String, dynamic>> _load() {
    final isAll = _rangeDays == 0;
    final start = isAll
        ? _end.subtract(const Duration(days: 3650))
        : _end.subtract(Duration(days: _rangeDays - 1));
    final key = isAll ? 'weight:all' : 'weight:$_rangeDays';
    _cachedWeight = NutritionViewCache.instance.get<Map<String, dynamic>>(key);
    return _repo.getWeightTrend(start, _end).then((value) {
      NutritionViewCache.instance.set(key, value);
      return value;
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _healthPermissionsFuture = _healthRepo.getPermissionsStatus();
      _future = _load();
    });
    await _future;
  }

  void _setRange(int days) {
    if (_rangeDays == days) return;
    Haptics.selection();
    setState(() {
      _rangeDays = days;
      _granularity = defaultGranularity(days);
      _future = _load();
    });
  }

  void _setGranularity(ChartGranularity g) {
    if (_granularity == g) return;
    Haptics.selection();
    setState(() => _granularity = g);
  }

  void _toggleScale() {
    if (_showScale && !_showTrend) return; // keep at least one series on
    setState(() => _showScale = !_showScale);
  }

  void _toggleTrend() {
    if (_showTrend && !_showScale) return;
    setState(() => _showTrend = !_showTrend);
  }

  List<FlSpot> _downsample(List<FlSpot> spots, {int maxPoints = 200}) {
    if (spots.length <= maxPoints) return spots;
    final step = (spots.length / maxPoints).ceil();
    return [for (int i = 0; i < spots.length; i += step) spots[i]];
  }

  void _showWeightEntry(DateTime date) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) => WeightEntrySheet(
        date: date,
        onLogged: () => setState(() {
          _future = _load();
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Weight'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showWeightEntry(DateTime.now()),
        child: HustlIcon(
          asset: 'assets/icons/ic_add.svg',
          size: 24,
          color: theme.colorScheme.onPrimary,
        ),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data ?? _cachedWeight;
          if (data == null) {
            return AppSkeleton.lines(semanticsLabel: 'Loading weight trend');
          }
          final scale = (data['scale'] as List?) ?? const [];
          if (scale.isEmpty) return _emptyState(theme);
          return RefreshIndicator(onRefresh: _refresh, child: _content(data));
        },
      ),
    );
  }

  Widget _content(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final scale = (data['scale'] as List?) ?? const [];
    final trend = (data['trend'] as List?) ?? const [];
    final sourcesByDate =
        (data['sourcesByDate'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final healthSources = (data['healthSources'] as List?) ?? const [];
    final goalType = data['goalType'] as String?;

    final baseDate = parseLocalDateOnly(scale.first['date'] as String);
    double xOf(String dateStr) =>
        parseLocalDateOnly(dateStr).difference(baseDate).inDays.toDouble();

    // Spots in the DISPLAY unit, then bucketed by the granularity dropdown.
    var scaleSpots = _downsample(
      aggregateSpots(
        scale
            .map(
              (p) => FlSpot(
                xOf(p['date'] as String),
                _unit.toDisplay((p['weightKg'] as num).toDouble()),
              ),
            )
            .toList(),
        _granularity,
      ),
    );
    var trendSpots = _downsample(
      aggregateSpots(
        trend
            .map(
              (p) => FlSpot(
                xOf(p['date'] as String),
                _unit.toDisplay((p['trendKg'] as num).toDouble()),
              ),
            )
            .toList(),
        _granularity,
      ),
    );

    final allSpots = [...scaleSpots, ...trendSpots];
    final minY = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    // Metrics computed in stored kg from the RAW (un-bucketed) series.
    final trendKgs = trend
        .map((p) => (p['trendKg'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final periodAverageKg = trendKgs.isEmpty
        ? null
        : trendKgs.reduce((a, b) => a + b) / trendKgs.length;

    double? periodDeltaKg;
    double? weeklyRateKg;
    if (trend.length >= 2) {
      final first = trend.first as Map;
      final last = trend.last as Map;
      final firstKg = (first['trendKg'] as num?)?.toDouble();
      final lastKg = (last['trendKg'] as num?)?.toDouble();
      final days = parseLocalDateOnly(
        last['date'] as String,
      ).difference(parseLocalDateOnly(first['date'] as String)).inDays;
      if (firstKg != null && lastKg != null) {
        periodDeltaKg = lastKg - firstKg;
        if (days > 0) weeklyRateKg = (lastKg - firstKg) / days * 7.0;
      }
    }

    final startDate = parseLocalDateOnly(scale.first['date'] as String);
    final endDate = parseLocalDateOnly(scale.last['date'] as String);

    final trendSeries = <TrendSample>[
      for (final p in trend)
        if ((p['trendKg'] as num?) != null)
          (
            date: parseLocalDateOnly(p['date'] as String),
            value: (p['trendKg'] as num).toDouble(),
          ),
    ];
    final changeRows = weightChangeRows(series: trendSeries, unit: _unit);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final loggedToday = scale.any(
      (p) => parseLocalDateOnly(p['date'] as String) == today,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2 + 56 + AppSpacing.x2,
      ),
      children: [
        TodayLogPrompt(
          onLog: () => _showWeightEntry(DateTime.now()),
          loggedToday: loggedToday,
        ),
        const SizedBox(height: AppSpacing.x3),
        ChartStatHeader(
          leadingLabel: 'Average',
          leadingValue: _unit.value(periodAverageKg),
          leadingUnit: _unit.suffix,
          trailingLabel: 'Difference',
          trailingValue: _signed(periodDeltaKg),
          trailingUnit: _unit.suffix,
          trailingValueColor: goalRateColor(
            goalType: goalType,
            value: periodDeltaKg,
            neutral: theme.colorScheme.onSurface,
          ),
          dateRangeText: formatDateRange(startDate, endDate),
          fitActive: _fitYAxis,
          onToggleFit: () => setState(() => _fitYAxis = !_fitYAxis),
        ),
        const SizedBox(height: AppSpacing.x2),
        WeightTrendChart(
          baseDate: baseDate,
          scaleSpots: scaleSpots,
          trendSpots: trendSpots,
          showScale: _showScale,
          showTrend: _showTrend,
          minY: minY,
          maxY: maxY,
          unit: _unit,
          rangeDays: _rangeDays,
          fitYAxis: _fitYAxis,
        ),
        const SizedBox(height: AppSpacing.x2),
        ChartRangeBar(
          rangeOptions: const [7, 30, 90, 180, 365, 0],
          selectedRange: _rangeDays,
          rangeLabels: _rangeLabels,
          onSelectRange: _setRange,
          granularities: availableGranularities(_rangeDays),
          selectedGranularity: _granularity,
          onSelectGranularity: _setGranularity,
        ),
        const SizedBox(height: AppSpacing.x2),
        ChartLegendCard(
          entries: [
            ChartLegendEntry(
              swatch: ChartSwatch.line,
              color: theme.colorScheme.primary.withValues(alpha: 0.55),
              label: 'Scale weight',
              active: _showScale,
              onTap: _toggleScale,
            ),
            ChartLegendEntry(
              swatch: ChartSwatch.lineDot,
              color: theme.colorScheme.primary,
              label: 'Trend weight',
              active: _showTrend,
              onTap: _toggleTrend,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          'Insights & data',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        if (changeRows.isNotEmpty) ...[
          ChartChangesCard(
            title: 'Weight changes',
            accentColor: theme.colorScheme.primary,
            rows: changeRows,
          ),
          const SizedBox(height: AppSpacing.x2),
        ],
        CoachCard(
          insight: _maybeWeightInsight(weeklyRateKg, goalType, scale.length),
        ),
        const SizedBox(height: AppSpacing.x3),
        WeightSourceCard(
          healthSources: healthSources,
          permissionsFuture: _healthPermissionsFuture,
          onManageClosed: _refresh,
        ),
        const SizedBox(height: AppSpacing.x3),
        ScaleWeighInListCard(
          scale: scale,
          sourcesByDate: sourcesByDate,
          onOverrideDay: _showWeightEntry,
          unit: _unit,
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          'Trend is smoother than scale weight — it won’t match every weigh-in.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// A signed display value without a suffix, e.g. '−1.6' / '+0.5'.
  String _signed(double? kg) {
    if (kg == null) return '—';
    final d = _unit.toDisplay(kg);
    final sign = d >= 0 ? '+' : '−';
    return '$sign${d.abs().toStringAsFixed(1)}';
  }

  CoachInsight _maybeWeightInsight(
    double? weeklyRateKg,
    String? goalType,
    int weighInCount,
  ) {
    return buildWeightCoachInsight(
      weeklyRateKg: weeklyRateKg,
      goalType: goalType,
      unit: _unit,
      weighInCount: weighInCount,
    );
  }

  Widget _emptyState(ThemeData theme) {
    final providerLabel = healthPlatformLabel(platform: theme.platform);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                ),
                child: Center(
                  child: HustlIcon(
                    asset: 'assets/icons/ic_scale.svg',
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Track your weight trend',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Log your first weigh-in and we’ll smooth out the daily noise so '
                'you can see where you’re really heading.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _showWeightEntry(DateTime.now()),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Log your first weigh-in'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/health'),
                child: Text('Or connect $providerLabel to sync'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
