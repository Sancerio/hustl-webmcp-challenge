import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';

import '../../../domain/models/workout_session.dart';

/// Per-region "top contributors" recap, shown as collapsible rows. Complements
/// the heatmap by naming the exercises that earned each muscle group's hard sets.
class SummaryEsRecap extends StatelessWidget {
  const SummaryEsRecap({
    super.key,
    required this.session,
    required this.bodyScoreService,
    required this.credits,
  });

  final WorkoutSession session;
  final BodyScoreService bodyScoreService;
  final Map<DisplayRegion, double> credits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (credits.isEmpty) return const SizedBox.shrink();

    final breakdown = _breakdown();
    if (breakdown.isEmpty) return const SizedBox.shrink();

    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'Session recap',
          padding: EdgeInsets.only(bottom: AppSpacing.x1),
        ),
        for (final entry in breakdown.entries)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.x1),
              expandedAlignment: Alignment.centerLeft,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key.label,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  Text(
                    '+${_fmt(credits[entry.key] ?? 0)} hard sets',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
              children: [
                for (final c in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${c.name}  +${_fmt(c.sets)} hard sets',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Map<DisplayRegion, List<_Contribution>> _breakdown() {
    final raw = bodyScoreService.aggregateExercisesForSession(
      session,
      topExercisesPerRegion: 4,
      minVolume: 0.1,
    );
    final merged = <DisplayRegion, Map<String, double>>{};
    raw.forEach((group, exercises) {
      final region = group.displayRegion;
      if (!credits.containsKey(region)) return;
      final dest = merged[region] ?? <String, double>{};
      for (final e in exercises.entries) {
        if (e.value <= 0.05) continue;
        dest.update(e.key, (v) => v + e.value, ifAbsent: () => e.value);
      }
      merged[region] = dest;
    });

    final result = <DisplayRegion, List<_Contribution>>{};
    merged.forEach((region, exercises) {
      final list =
          exercises.entries
              .map((e) => _Contribution(name: e.key, sets: e.value))
              .toList()
            ..sort((a, b) => b.sets.compareTo(a.sets));
      if (list.isNotEmpty) result[region] = list;
    });
    final sorted = result.entries.toList()
      ..sort((a, b) => (credits[b.key] ?? 0).compareTo(credits[a.key] ?? 0));
    return Map<DisplayRegion, List<_Contribution>>.fromEntries(sorted);
  }

  String _fmt(double v) => NumberFormatUtil.formatDouble(
    v,
    decimalDigits: (v - v.round()).abs() < 0.05 ? 0 : 1,
  );
}

class _Contribution {
  const _Contribution({required this.name, required this.sets});
  final String name;
  final double sets;
}
