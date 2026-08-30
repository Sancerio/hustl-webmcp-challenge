import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import '../../../health_sync/domain/repositories/health_metrics_repository.dart';

class WeightSourceCard extends StatelessWidget {
  const WeightSourceCard({
    super.key,
    required this.healthSources,
    this.permissionsFuture,
    this.onManageClosed,
  });

  final List healthSources;
  final Future<HealthPermissionsStatus>? permissionsFuture;
  final Future<void> Function()? onManageClosed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectedFromBackend = healthSources.isNotEmpty;

    Future<void> onPressed() async {
      await context.push('/health');
      await onManageClosed?.call();
    }

    Widget buildCard({
      HealthPermissionsStatus? permissions,
      bool? connectedOverride,
      String? statusLabelOverride,
      String? actionLabelOverride,
      bool disableAction = false,
    }) {
      final connectedFromDevice =
          permissions?.isServiceAvailable == true &&
          permissions?.hasPermissions == true;
      final connected =
          connectedOverride ?? (connectedFromBackend || connectedFromDevice);

      String? lastSyncedAt;
      if (healthSources.isNotEmpty && healthSources.first is Map) {
        lastSyncedAt = (healthSources.first as Map)['last_synced_at']
            ?.toString();
      }
      final parsedLastSynced = lastSyncedAt == null
          ? null
          : DateTime.tryParse(lastSyncedAt);
      final syncLabel = parsedLastSynced == null
          ? null
          : MaterialLocalizations.of(
              context,
            ).formatMediumDate(parsedLastSynced.toLocal());
      final showUnknownLastSynced =
          lastSyncedAt != null &&
          lastSyncedAt.trim().isNotEmpty &&
          parsedLastSynced == null;

      final statusLabel =
          statusLabelOverride ??
          (connected
              ? (syncLabel != null
                    ? 'Last synced: $syncLabel'
                    : showUnknownLastSynced
                    ? 'Last synced: —'
                    : connectedFromBackend
                    ? 'Connected.'
                    : 'Connected on this device.')
              : (permissions?.isServiceAvailable == false
                    ? 'Unavailable on this device.'
                    : 'Not connected.'));

      // Wave I: sentence-case section header with a trailing action over a
      // grouped surface card — status + helper sit inside the card as meta.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Health sync',
            trailing: TextButton(
              onPressed: disableAction ? null : onPressed,
              child: Text(
                actionLabelOverride ?? (connected ? 'Manage' : 'Connect'),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusLabel, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  'Synced weights count as logged — no need to enter again.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      );
    }

    final future = permissionsFuture;
    if (future == null) {
      return buildCard();
    }

    return FutureBuilder<HealthPermissionsStatus>(
      future: future,
      builder: (context, snapshot) {
        if (!connectedFromBackend &&
            snapshot.connectionState == ConnectionState.waiting) {
          return buildCard(
            connectedOverride: false,
            statusLabelOverride: 'Checking connection…',
            actionLabelOverride: 'Open',
            disableAction: false,
          );
        }
        if (!connectedFromBackend && snapshot.hasError) {
          return buildCard(
            connectedOverride: false,
            statusLabelOverride: 'Unable to check connection.',
            actionLabelOverride: 'Open',
            disableAction: false,
          );
        }
        return buildCard(permissions: snapshot.data);
      },
    );
  }
}
