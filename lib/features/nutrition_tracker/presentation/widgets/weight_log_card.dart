import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';

import '../../../health_sync/presentation/widgets/health_connect_primer.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import '../utils/weight_unit.dart';
import 'weight_entry_sheet.dart';

class WeightLogCard extends StatefulWidget {
  const WeightLogCard({
    super.key,
    required this.isSignedIn,
    required this.now,
    this.onSignInTap,
  });

  final bool isSignedIn;
  final DateTime now;
  final VoidCallback? onSignInTap;

  @override
  State<WeightLogCard> createState() => _WeightLogCardState();
}

class _WeightLogCardState extends State<WeightLogCard> {
  static const int _rangeDays = 30;
  late Future<_WeightSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _parseLocalDate(String raw) {
    final s = raw.trim();
    if (s.length == 10 && s[4] == '-' && s[7] == '-') {
      final parts = s.split('-');
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    return DateTime.parse(s);
  }

  Future<_WeightSummary> _load() async {
    if (!widget.isSignedIn) return const _WeightSummary();

    final repo = GetIt.instance<NutritionTargetsRepository>();
    final end = _startOfDay(widget.now);
    final start = end.subtract(const Duration(days: _rangeDays - 1));
    final data = await repo.getWeightTrend(start, end);
    final unit = WeightUnit(await PreferencesService().getWeightUnit());
    final scale = (data['scale'] as List?) ?? const [];

    double? latestKg;
    DateTime? latestDate;
    bool hasToday = data['hasWeightToday'] == true;
    String? latestSource;

    final latest = data['latest'];
    if (latest is Map) {
      final dateRaw = latest['date']?.toString();
      final kg = (latest['weightKg'] as num?)?.toDouble();
      if (dateRaw != null && kg != null && kg > 0) {
        latestKg = kg;
        latestDate = _parseLocalDate(dateRaw);
        latestSource = latest['source']?.toString();
      }
    }

    if (latestKg == null || latestDate == null) {
      for (final point in scale) {
        if (point is! Map) continue;
        final dateRaw = point['date']?.toString();
        final kg = (point['weightKg'] as num?)?.toDouble();
        if (dateRaw == null || kg == null || kg <= 0) continue;
        latestKg = kg;
        latestDate = _parseLocalDate(dateRaw);
        latestSource = point['source']?.toString();
      }
    }

    return _WeightSummary(
      latestWeightKg: latestKg,
      latestDate: latestDate,
      hasToday: hasToday,
      latestSource: latestSource,
      unit: unit,
    );
  }

  Future<void> _openWeightEntry(
    BuildContext context,
    DateTime now,
    WeightUnit unit,
  ) async {
    // Value-timed: before the first weight-log, offer to connect Apple Health
    // (the only place the OS permission can be requested). Shows once; declining
    // proceeds straight to the manual entry below — never a dead-end.
    await maybeRunHealthConnectPrimer(context);
    if (!context.mounted) return;
    final didLog = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) => WeightEntrySheet(date: now, initialUnit: unit),
    );
    if (!mounted) return;
    if (didLog == true) {
      setState(() => _future = _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = widget.now;

    if (!widget.isSignedIn) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Weight', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text(
                'Log weigh-ins to improve your weight trend and TDEE accuracy.',
                style: theme.textTheme.bodySmall,
              ),
              if (widget.onSignInTap != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onSignInTap,
                    icon: const Icon(Icons.login_outlined, size: 20),
                    label: const Text('Sign in to log weigh-ins'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return FutureBuilder<_WeightSummary>(
      future: _future,
      builder: (context, snapshot) {
        final summary = snapshot.data ?? const _WeightSummary();
        final hasData =
            summary.latestWeightKg != null && summary.latestDate != null;
        final didLogToday = summary.hasToday;
        final isSyncedToday =
            didLogToday && (summary.latestSource ?? '').toLowerCase() != 'self';

        final localizations = MaterialLocalizations.of(context);
        final dateLabel = summary.latestDate == null
            ? null
            : localizations.formatMediumDate(summary.latestDate!.toLocal());

        return Card(
          elevation: 0,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Weight', style: theme.textTheme.bodyLarge),
                    ),
                    TextButton(
                      onPressed: () => context.push('/nutrition/weight'),
                      child: const Text('View trend'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (snapshot.connectionState == ConnectionState.waiting) ...[
                  // Loading is its own state — a small skeleton, never the
                  // "no weigh-ins" line, so the empty state can't flash by.
                  const AppSkeleton(width: 120, height: 24),
                ] else if (snapshot.hasError) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Couldn’t load your weigh-ins.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _future = _load()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ] else if (!hasData) ...[
                  Text(
                    'No weigh-ins yet — log one to start your trend.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _openWeightEntry(context, now, summary.unit),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('Log weight'),
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        summary.unit.formatWeight(summary.latestWeightKg),
                        style: AppTextStyles.metricEmphasis(context),
                      ),
                      const Spacer(),
                      if (dateLabel != null)
                        Text(dateLabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.x1 + 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        snapshot.connectionState == ConnectionState.waiting
                        ? null
                        : () => _openWeightEntry(context, now, summary.unit),
                    child: Text(
                      didLogToday
                          ? (isSyncedToday ? 'Override today' : 'Edit today')
                          : 'Log today',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WeightSummary {
  const _WeightSummary({
    this.latestWeightKg,
    this.latestDate,
    this.hasToday = false,
    this.latestSource,
    this.unit = const WeightUnit('kg'),
  });

  final double? latestWeightKg;
  final DateTime? latestDate;
  final bool hasToday;
  final String? latestSource;
  final WeightUnit unit;
}
