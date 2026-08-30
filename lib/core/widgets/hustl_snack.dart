import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

/// Semantic tone of a [HustlSnack]. The tone never floods the surface — it lives
/// in the leading glyph, a thin leading accent bar, and the optional action.
enum HustlSnackVariant { info, success, warning, error }

/// The single app-wide toast. Every transient confirmation, warning, or error in
/// Hustl should route through [HustlSnack.show] so toasts share one calm,
/// premium-dark look that belongs with the onboarding sheets — a layered dark
/// surface, tokenized rounding, onSurface text, a tinted variant glyph, an
/// optional accent action, and an X to dismiss.
///
/// The surface stays dark (`surfaceContainerHigh`) for ALL variants: errors are
/// legible, not alarmist. Color is reserved for the glyph + accent bar + action.
class HustlSnack {
  HustlSnack._();

  static const Duration _defaultDuration = Duration(seconds: 4);

  /// Shows a premium toast for [message] in the nearest [ScaffoldMessenger].
  ///
  /// - [variant] selects the accent tone (see [HustlSnackVariant]).
  /// - [actionLabel] + [onAction] render an accent action button.
  /// - [duration] defaults to ~4s.
  /// - [dismissible] renders the trailing X close button.
  static void show(
    BuildContext context,
    String message, {
    HustlSnackVariant variant = HustlSnackVariant.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    bool dismissible = true,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    // Never stack toasts — the latest message replaces the current one.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        // The content widget IS the surface, so strip the SnackBar's own chrome.
        backgroundColor: Colors.transparent,
        elevation: 0,
        // The theme enables a built-in close icon; suppress it so HustlSnack
        // renders a single close affordance (its own X, only when dismissible).
        showCloseIcon: false,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.x2),
        duration: duration ?? _defaultDuration,
        dismissDirection: DismissDirection.horizontal,
        content: _HustlSnackContent(
          message: message,
          variant: variant,
          actionLabel: actionLabel,
          onAction: onAction,
          dismissible: dismissible,
          onDismiss: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }
}

/// The dark layered card rendered inside the (transparent) SnackBar.
class _HustlSnackContent extends StatelessWidget {
  const _HustlSnackContent({
    required this.message,
    required this.variant,
    required this.actionLabel,
    required this.onAction,
    required this.dismissible,
    required this.onDismiss,
  });

  final String message;
  final HustlSnackVariant variant;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dismissible;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _accentColor(colors);
    final hasAction = actionLabel != null && onAction != null;

    return Container(
      decoration: BoxDecoration(
        // Same surface ladder + radius family as the onboarding sheets/cards.
        color: colors.surfaceContainerHigh,
        borderRadius: AppRadius.cardRadius,
        boxShadow: [AppShadows.medium(context)],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.cardRadius,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Thin leading accent bar — the only colored fill, kept quiet.
            Container(width: 3, height: 44, color: accent),
            const SizedBox(width: AppSpacing.x2 - 3),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 4),
              child: Icon(_iconData, size: 24, color: accent),
            ),
            const SizedBox(width: AppSpacing.x1 + 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: AppSpacing.x1 + 4,
                  // Pad the trailing edge when nothing follows the message.
                  horizontal: hasAction || dismissible ? 0 : AppSpacing.x2,
                ),
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
            if (hasAction) ...[
              const SizedBox(width: AppSpacing.x1),
              TextButton(
                onPressed: () {
                  onDismiss();
                  onAction!();
                },
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x1 + 4,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel!),
              ),
            ],
            if (dismissible)
              IconButton(
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: colors.onSurfaceVariant,
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close_rounded),
              )
            else
              const SizedBox(width: AppSpacing.x1),
          ],
        ),
      ),
    );
  }

  /// Variant accent, resolved entirely from tokens.
  ///   info    -> primary (electric blue)
  ///   success -> tertiary (emerald success tone)
  ///   warning -> amber warning token
  ///   error   -> error (alert red)
  Color _accentColor(ColorScheme colors) {
    switch (variant) {
      case HustlSnackVariant.info:
        return colors.primary;
      case HustlSnackVariant.success:
        return colors.tertiary;
      case HustlSnackVariant.warning:
        return AppColors.accentWarningAmber;
      case HustlSnackVariant.error:
        return colors.error;
    }
  }

  IconData get _iconData {
    switch (variant) {
      case HustlSnackVariant.info:
        return Icons.info_outline_rounded;
      case HustlSnackVariant.success:
        return Icons.check_circle_outline_rounded;
      case HustlSnackVariant.warning:
        return Icons.warning_amber_rounded;
      case HustlSnackVariant.error:
        return Icons.error_outline_rounded;
    }
  }
}
