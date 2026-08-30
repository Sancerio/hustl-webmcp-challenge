import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import 'hustl_icon.dart';

/// The single empty-state pattern: a softly held icon, a confident headline, a
/// supportive line, and at most one call to action. Kind by default — copy
/// should reassure and invite, never shame. Wave I (Apple Fitness+ x Whoop):
/// blue primary, a soft blue-tinted circular icon holder, big sentence-case
/// type, and a blue [FilledButton] for the primary action.
class ScreenEmptyState extends StatelessWidget {
  const ScreenEmptyState({
    super.key,
    required this.icon,
    this.assetIcon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  /// Fallback Material glyph, used when no [assetIcon] is supplied.
  final IconData icon;

  /// Optional bespoke SVG glyph (e.g. `'assets/icons/empty_chart.svg'`). When
  /// provided, it renders in the holder via [HustlIcon] tinted to the primary
  /// color, in place of [icon].
  final String? assetIcon;
  final String title;
  final String? message;

  /// CTA label. When provided alongside [onAction], a single filled button is
  /// shown.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasAction = actionLabel != null && onAction != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A soft, blue-tinted circular holder — layered with a wider,
              // fainter halo — makes the glyph feel like a warm welcome rather
              // than a placeholder. Two concentric tints read as gentle depth
              // (Apple Fitness+ / Whoop), not a flat gray well.
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.06),
                ),
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.12),
                  ),
                  child: assetIcon != null
                      ? HustlIcon(
                          asset: assetIcon!,
                          size: 40,
                          color: colors.primary,
                        )
                      : Icon(icon, size: 34, color: colors.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  height: 1.2,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.x1),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              if (hasAction) ...[
                const SizedBox(height: AppSpacing.x3),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x3,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.controlRadius,
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
