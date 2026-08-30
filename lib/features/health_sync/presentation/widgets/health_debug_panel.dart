import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../domain/models/health_metric_sample.dart';
import '../bloc/health_overview_bloc.dart';

class HealthDebugPanel extends StatelessWidget {
  const HealthDebugPanel({super.key, required this.state});

  final HealthOverviewState state;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final shouldShow =
        state.fallbackUsed ||
        state.loadedFromCache ||
        state.assumedPermissions ||
        state.rawPermissionResult == null;
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final metricEntries = state.metricCounts.entries.toList()
      ..sort((a, b) => a.key.name.compareTo(b.key.name));
    final l10n = MaterialLocalizations.of(context);
    final syncedLabel = state.lastSyncedAt == null
        ? '—'
        : '${l10n.formatMediumDate(state.lastSyncedAt!.toLocal())} '
              '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(state.lastSyncedAt!.toLocal()))}';

    final metricsLabel = metricEntries.isEmpty
        ? '0'
        : metricEntries
              .map((entry) => '${entry.key.label}: ${entry.value}')
              .join(' · ');

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Health sync diagnostics',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            _DebugLine(label: 'Last sync', value: syncedLabel),
            _DebugLine(label: 'Metrics fetched', value: metricsLabel),
            _DebugLine(
              label: 'Nutrition entries',
              value: state.nutritionEntryCount.toString(),
            ),
            _DebugLine(
              label: 'Fallback used',
              value: state.fallbackUsed ? 'Yes' : 'No',
            ),
            _DebugLine(
              label: 'Loaded from cache',
              value: state.loadedFromCache ? 'Yes' : 'No',
            ),
            _DebugLine(
              label: 'Raw permission check',
              value: state.rawPermissionResult == null
                  ? 'Undetermined'
                  : state.rawPermissionResult!
                  ? 'Granted'
                  : 'Denied',
            ),
            _DebugLine(
              label: 'Assumed permissions',
              value: state.assumedPermissions ? 'Yes (iOS privacy)' : 'No',
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugLine extends StatelessWidget {
  const _DebugLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x1 - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 156,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
