import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

/// Shows a non-blocking "New PR" banner that slides in from the top, holds for
/// ~3s, then dismisses itself. Paired with a celebrate haptic at the call site.
class PrBannerController {
  OverlayEntry? _entry;
  Timer? _timer;

  void show(BuildContext context, {required String message}) {
    dismiss();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final topInset = MediaQuery.of(context).viewPadding.top;

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: topInset + AppSpacing.x1,
        left: AppSpacing.x2,
        right: AppSpacing.x2,
        child: _PrBannerCard(message: message),
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(const Duration(seconds: 3), dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _PrBannerCard extends StatelessWidget {
  const _PrBannerCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = AppColors.accentWarningAmber;

    final card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1 + 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HustlIcon(
            asset: 'assets/icons/ic_trophy.svg',
            size: 22,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.x1),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    final material = Material(color: Colors.transparent, child: card);
    if (reduceMotion) return material;

    return material
        .animate()
        .fadeIn(duration: AppMotion.medium)
        .slideY(
          begin: -0.6,
          end: 0,
          duration: AppMotion.emphasized,
          curve: AppMotion.celebrateCurve,
        );
  }
}
