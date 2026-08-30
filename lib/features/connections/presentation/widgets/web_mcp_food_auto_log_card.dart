import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';

class WebMcpFoodAutoLogCard extends StatelessWidget {
  const WebMcpFoodAutoLogCard({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = enabled ? colors.primary : colors.onSurfaceVariant;
    return Card(
      key: const ValueKey('web-mcp-food-auto-log-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hustl Web auto-log',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? 'Food logs apply immediately'
                            : 'Review before logging',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch.adaptive(
                    key: const ValueKey('web-mcp-food-auto-log-switch'),
                    value: enabled,
                    onChanged: onChanged,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              enabled
                  ? 'New food logs from Hustl\'s web tools are added right away. '
                        'They stay visible in AI Activity, where you can Undo them.'
                  : 'New food logs from Hustl\'s web tools wait in Coach for your '
                        'review. Turn this on only when you want immediate logging.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
