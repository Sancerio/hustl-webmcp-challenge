import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/health_platform_labels.dart';
import '../../domain/models/recovery_signal_availability.dart';

/// A slim, kind prompt shown when a user is connected and has *some* data, but
/// one or more core recovery signals (HRV / resting heart rate / sleep) are not
/// flowing. It names the specific missing signals so the user knows exactly
/// what to turn on — never a generic "reconnect".
///
/// Returns [SizedBox.shrink] when nothing is missing, so the surface renders
/// exactly as today for a fully-covered user.
class RecoverySignalPrompt extends StatelessWidget {
  const RecoverySignalPrompt({super.key, required this.availability});

  final RecoverySignalAvailability availability;

  @override
  Widget build(BuildContext context) {
    // Only nudge once at least one signal is flowing — a fully empty connection
    // is handled by the connect page, not here.
    if (!availability.hasAnySignal) return const SizedBox.shrink();
    final missing = availability.missingSignals;
    if (missing.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final providerLabel = healthPlatformLabel(platform: theme.platform);
    final labels = missing.map((s) => s.displayLabel).toList();
    final joined = _joinNaturally(labels);

    return Semantics(
      container: true,
      label:
          'Turn on $joined in $providerLabel for a fuller readiness picture.',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.favorite_border,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.x1),
            Expanded(
              child: Text(
                "We're not seeing $joined yet. Turn it on for Hustl in "
                '$providerLabel to sharpen your readiness.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _joinNaturally(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    final head = items.sublist(0, items.length - 1).join(', ');
    return '$head, and ${items.last}';
  }
}
