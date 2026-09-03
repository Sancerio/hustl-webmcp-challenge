import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

/// Reusable skeleton for primary content loading states.
/// Use this instead of spinner-only placeholders for full-screen sections.
class HustlInlineSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final int rows;
  final String semanticsLabel;
  final bool liveRegion;

  const HustlInlineSkeleton({
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.x2),
    this.rows = 4,
    this.semanticsLabel = 'Loading content',
    this.liveRegion = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.65);
    final accent = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.95,
    );

    Widget line(double widthFactor) {
      return FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: AppSpacing.x2,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(AppSpacing.x1),
            border: Border.all(
              color: accent.withValues(alpha: 0.55),
              width: 0.6,
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: liveRegion,
      label: semanticsLabel,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                line(0.74),
                const SizedBox(height: AppSpacing.x2),
                for (var i = 0; i < rows; i++) ...[
                  line(i.isEven ? 1 : 0.92),
                  if (i < rows - 1) const SizedBox(height: AppSpacing.x1),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
