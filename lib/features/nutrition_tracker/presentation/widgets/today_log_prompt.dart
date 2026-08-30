import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

/// A slim, tappable "log today's weigh-in" fast-path card for the top of the
/// Weight screen. When already logged today it reads as a calm confirmation
/// instead of a call to action.
class TodayLogPrompt extends StatelessWidget {
  const TodayLogPrompt({
    super.key,
    required this.onLog,
    this.loggedToday = false,
  });

  final VoidCallback onLog;
  final bool loggedToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: AppRadius.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loggedToday ? null : onLog,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x2 - 2,
          ),
          child: Row(
            children: [
              HustlIcon(
                asset: 'assets/icons/ic_scale.svg',
                size: 20,
                color: loggedToday ? colors.onSurfaceVariant : colors.primary,
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  loggedToday ? 'Weighed in today' : 'Log today’s weigh-in',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: loggedToday
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                  ),
                ),
              ),
              Icon(
                loggedToday ? Icons.check_circle_outline : Icons.add,
                size: 20,
                color: loggedToday ? colors.onSurfaceVariant : colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
