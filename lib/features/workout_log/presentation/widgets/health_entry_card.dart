import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

/// Entry to the Health dashboard from the Progress screen. The drawer is gone,
/// so this keeps Health reachable within two taps from its tab. Wave G §12.3:
/// a flat divider-bound row — label + subtitle, chevron, no icon block.
class HealthEntryCard extends StatelessWidget {
  const HealthEntryCard({super.key, this.onTap});

  /// Override the default `/health` navigation (used in tests).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: 'Open Health dashboard',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            Haptics.selection();
            if (onTap != null) {
              onTap!();
            } else {
              context.push('/health');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Health', style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Recovery, sleep and daily readiness',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
