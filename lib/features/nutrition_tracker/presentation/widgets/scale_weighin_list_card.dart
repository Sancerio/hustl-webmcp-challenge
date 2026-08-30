import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import '../../../../core/utils/date_only.dart';
import '../utils/weight_unit.dart';

class ScaleWeighInListCard extends StatelessWidget {
  const ScaleWeighInListCard({
    super.key,
    required this.scale,
    required this.sourcesByDate,
    required this.onOverrideDay,
    this.unit = const WeightUnit('kg'),
  });

  final List scale;
  final Map<String, dynamic> sourcesByDate;
  final ValueChanged<DateTime> onOverrideDay;
  final WeightUnit unit;

  String _labelForSource(String raw) {
    final s = raw.toLowerCase().trim();
    if (s == 'self') return 'Manual';
    if (s == 'apple_health') return 'Apple Health';
    // 'health_connect' is the current Android source label; 'google_fit'
    // is kept for already-persisted rows written before the rename.
    if (s == 'health_connect' || s == 'google_fit') return 'Health Connect';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');

    final items = scale.whereType<Map>().toList().reversed.take(20).toList();

    // Wave I: sentence-case section header over a grouped surface card — each
    // row is date left, weight value (tabular) right; source/sources as meta.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Scale weigh-ins'),
        SectionList(
          card: true,
          children: [
            for (final p in items)
              _WeighInRow(
                date: parseLocalDateOnly(p['date'] as String),
                kg: (p['weightKg'] as num?)?.toDouble() ?? 0,
                source: (p['source'] ?? 'self').toString(),
                sources: sourcesByDate[p['date']] as List?,
                labelForSource: _labelForSource,
                onOverrideDay: onOverrideDay,
                fmt: fmt,
                unit: unit,
              ),
          ],
        ),
      ],
    );
  }
}

class _WeighInRow extends StatelessWidget {
  const _WeighInRow({
    required this.date,
    required this.kg,
    required this.source,
    required this.sources,
    required this.labelForSource,
    required this.onOverrideDay,
    required this.fmt,
    required this.unit,
  });

  final DateTime date;
  final double kg;
  final String source;
  final List? sources;
  final String Function(String) labelForSource;
  final ValueChanged<DateTime> onOverrideDay;
  final DateFormat fmt;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = labelForSource(source);
    final isManual = source.toLowerCase() == 'self';
    final metaText = (sources != null && sources!.length > 1)
        ? 'Sources: ${sources!.join(', ')}'
        : label;

    void handleTap() {
      if (isManual) {
        onOverrideDay(date);
        return;
      }
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Synced weigh-in'),
          content: Text('This weigh-in was synced from $label.'),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                context.pop();
                onOverrideDay(date);
              },
              child: const Text('Override'),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: handleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmt.format(date), style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(metaText, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Text(unit.formatWeight(kg), style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
