import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/utils/date_only.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import '../nutrition_view_cache.dart';
import '../widgets/charts/chart_changes_card.dart';
import '../widgets/charts/chart_granularity.dart';
import '../widgets/charts/chart_legend_card.dart';
import '../widgets/charts/chart_range_bar.dart';
import '../widgets/charts/chart_stat_header.dart';
import '../widgets/charts/expenditure_trend_chart.dart';
import '../widgets/charts/trend_change_rows.dart';

/// A dedicated expenditure (TDEE) trend screen, mirroring the weight trend's
/// MacroFactor layout: Average + Difference header, a smoothed expenditure line
/// (over intake context) with the granularity dropdown, a legend card, and an
/// "Insights & data" change card. Expenditure is sourced from the per-day
/// `tdeeKcal` the insights endpoint already returns.
class ExpenditureTrendScreen extends StatefulWidget {
  const ExpenditureTrendScreen({super.key});

  @override
  State<ExpenditureTrendScreen> createState() => _ExpenditureTrendScreenState();
}

class _ExpenditureTrendScreenState extends State<ExpenditureTrendScreen> {
  final _repo = GetIt.instance<NutritionTargetsRepository>();
  late Future<Map<String, dynamic>> _future;
  Map<String, dynamic>? _cached;

  final DateTime _end = DateTime.now();
  int _rangeDays = 30; // 0 == All.
  ChartGranularity _granularity = ChartGranularity.day;
  bool _showExpenditure = true;
  bool _showIntake = true;
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
  }

  Future<Map<String, dynamic>> _load() {
    final isAll = _rangeDays == 0;
    // Insights is heavier than the weight series, so 'All' looks back ~2y rather
    // than a decade.
    final start = isAll
        ? _end.subtract(const Duration(days: 730))
        : _end.subtract(Duration(days: _rangeDays - 1));
    final key = isAll ? 'expenditure:all' : 'expenditure:$_rangeDays';
    _cached = NutritionViewCache.instance.get<Map<String, dynamic>>(key);
    return _repo.getInsights(start, _end).then((value) {
      NutritionViewCache.instance.set(key, value);
      return value;
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _future = _load());
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

  void _toggleExpenditure() {
    if (_showExpenditure && !_showIntake) return;
    setState(() => _showExpenditure = !_showExpenditure);
  }

  void _toggleIntake() {
    if (_showIntake && !_showExpenditure) return;
    setState(() => _showIntake = !_showIntake);
  }

  List<FlSpot> _downsample(List<FlSpot> spots, {int maxPoints = 200}) {
    if (spots.length <= maxPoints) return spots;
    final step = (spots.length / maxPoints).ceil();
    return [for (int i = 0; i < spots.length; i += step) spots[i]];
  }

  List<Map<String, dynamic>> _days(Map<String, dynamic> data) {
    final eb = data['energyBalance'] as Map?;
    return ((eb?['days'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Expenditure'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data ?? _cached;
          if (data == null) {
            return AppSkeleton.lines(semanticsLabel: 'Loading expenditure');
          }
          final days = _days(data);
          final hasTdee = days.any((d) => (d['tdeeKcal'] as num?) != null);
          if (!hasTdee) return _emptyState();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _content(data, days),
          );
        },
      ),
    );
  }

  Widget _content(Map<String, dynamic> data, List<Map<String, dynamic>> days) {
    final theme = Theme.of(context);
    final averages = (data['energyBalance'] as Map?)?['averages'] as Map? ?? {};

    final baseDate = parseLocalDateOnly(days.first['date'] as String);
    double xOf(String dateStr) =>
        parseLocalDateOnly(dateStr).difference(baseDate).inDays.toDouble();

    var expenditureSpots = _downsample(
      aggregateSpots([
        for (final d in days)
          if ((d['tdeeKcal'] as num?) != null)
            FlSpot(xOf(d['date'] as String), (d['tdeeKcal'] as num).toDouble()),
      ], _granularity),
    );
    var intakeSpots = _downsample(
      aggregateSpots([
        for (final d in days)
          if (((d['intakeCalories'] as num?)?.toDouble() ?? 0) > 0)
            FlSpot(
              xOf(d['date'] as String),
              (d['intakeCalories'] as num).toDouble(),
            ),
      ], _granularity),
    );

    // Frame the axis from BOTH series (regardless of toggle) so it never
    // reduces an empty list — e.g. expenditure hidden while intake has no
    // positive points — and so the scale doesn't jump as series toggle.
    final allSpots = [...expenditureSpots, ...intakeSpots];
    final ys = allSpots.map((s) => s.y);
    final minY = ys.isEmpty ? 0.0 : ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.isEmpty ? 1.0 : ys.reduce((a, b) => a > b ? a : b);

    // Metrics from the RAW (un-bucketed) expenditure series.
    final expSeries = <TrendSample>[
      for (final d in days)
        if ((d['tdeeKcal'] as num?) != null)
          (
            date: parseLocalDateOnly(d['date'] as String),
            value: (d['tdeeKcal'] as num).toDouble(),
          ),
    ];
    final avgTdee = (averages['tdeeKcal'] as num?)?.toDouble() ??
        (expSeries.isEmpty
            ? null
            : expSeries.map((e) => e.value).reduce((a, b) => a + b) /
                  expSeries.length);
    final periodDelta = expSeries.length >= 2
        ? expSeries.last.value - expSeries.first.value
        : null;
    final changeRows = kcalChangeRows(series: expSeries);

    final startDate = expSeries.first.date;
    final endDate = expSeries.last.date;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x3,
      ),
      children: [
        ChartStatHeader(
          leadingLabel: 'Average',
          leadingValue: avgTdee == null ? '—' : avgTdee.round().toString(),
          leadingUnit: 'kcal',
          trailingLabel: 'Difference',
          trailingValue: _signed(periodDelta),
          trailingUnit: 'kcal',
          dateRangeText: formatDateRange(startDate, endDate),
          fitActive: _fitYAxis,
          onToggleFit: () => setState(() => _fitYAxis = !_fitYAxis),
        ),
        const SizedBox(height: AppSpacing.x2),
        ExpenditureTrendChart(
          baseDate: baseDate,
          expenditureSpots: expenditureSpots,
          intakeSpots: intakeSpots,
          showExpenditure: _showExpenditure,
          showIntake: _showIntake,
          minY: minY,
          maxY: maxY,
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
              swatch: ChartSwatch.lineDot,
              color: expenditureColor,
              label: 'Expenditure',
              active: _showExpenditure,
              onTap: _toggleExpenditure,
            ),
            ChartLegendEntry(
              swatch: ChartSwatch.line,
              color: intakeColor,
              label: 'Intake',
              active: _showIntake,
              onTap: _toggleIntake,
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
        if (changeRows.isNotEmpty)
          ChartChangesCard(
            title: 'Expenditure changes',
            accentColor: expenditureColor,
            rows: changeRows,
          ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          'Expenditure is an estimate of the calories you burn, smoothed from '
          'your logged intake and weight trend — it won’t match a tracker’s '
          'daily number.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// A signed whole-kcal value without the unit, e.g. '+268' / '−112'.
  String _signed(double? kcal) {
    if (kcal == null) return '—';
    final sign = kcal >= 0 ? '+' : '−';
    return '$sign${kcal.abs().round()}';
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x4,
      ),
      children: [
        const SizedBox(height: AppSpacing.x6),
        ScreenEmptyState(
          icon: Icons.local_fire_department_outlined,
          assetIcon: 'assets/icons/empty_chart.svg',
          title: 'Expenditure needs a few weeks of logging',
          message:
              'Once you’ve logged food consistently and have a weight trend, '
              'we’ll estimate the calories you burn each day and chart it here.',
          actionLabel: 'Log your food',
          onAction: () => context.go('/nutrition'),
        ),
      ],
    );
  }
}
