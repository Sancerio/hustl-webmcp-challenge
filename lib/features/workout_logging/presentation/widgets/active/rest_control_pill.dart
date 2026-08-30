import 'package:flutter/material.dart';

import '../../../../../core/widgets/hustl_icon.dart';

/// The IDLE rest control (Wave I): an outlined "Rest" pill that opens the global
/// rest-timer dialog. When a rest timer is running this is swapped out for the
/// filled-blue [RestTimerChip]; this widget only represents the resting-not-yet
/// state.
class RestControlPill extends StatelessWidget {
  const RestControlPill({super.key, required this.onTap});

  /// Invoked when the pill is tapped (opens the global rest-timer dialog).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Tooltip(
      message: 'Start rest timer',
      child: Semantics(
        button: true,
        label: 'Start rest timer',
        child: Material(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HustlIcon(
                    asset: 'assets/icons/ic_timer.svg',
                    size: 18,
                    color: colors.onSurface,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Rest',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
