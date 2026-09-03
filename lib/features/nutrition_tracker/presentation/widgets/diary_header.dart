import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';

import '../bloc/diary_state.dart';

/// The diary hero module (Wave I — Apple Fitness+ x Whoop, "data as hero"):
/// a large emerald calorie ring with the remaining-kcal number BIG in its
/// centre, paired with three compact macro bars (protein emerald, carbs blue,
/// fat amber) — all inside one elevated card. Over budget renders in amber,
/// never red.
class DiaryHeader extends StatelessWidget {
  const DiaryHeader({super.key, required this.state});

  final DiaryState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final targets = state.targets;

    final calTarget = targets?.caloriesTarget ?? 0;
    final consumed = state.totalCalories;
    final hasCalTarget = calTarget > 0;
    final calOver = hasCalTarget && consumed > calTarget;
    final progress = hasCalTarget
        ? (consumed / calTarget).clamp(0.0, 1.0)
        : 0.0;

    // The hero number lives in the ring centre (counts up as data loads).
    final double heroNumber;
    final String heroCaption;
    if (!hasCalTarget) {
      heroNumber = consumed;
      heroCaption = 'kcal';
    } else if (calOver) {
      heroNumber = consumed - calTarget;
      heroCaption = 'kcal over';
    } else {
      heroNumber = calTarget - consumed;
      heroCaption = 'kcal left';
    }

    final heroNumberStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 40,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
      color: colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppProgressRing(
            progress: progress,
            size: 136,
            strokeWidth: 13,
            color: calOver ? AppColors.accentWarningAmber : colors.primary,
            trackColor: colors.outlineVariant.withValues(alpha: 0.5),
            semanticsLabel: 'Calories',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedMetricText(
                  value: heroNumber,
                  grouped: true,
                  style: heroNumberStyle,
                  semanticsLabel: 'Calories $heroCaption',
                ),
                const SizedBox(height: 2),
                Text(
                  heroCaption,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: calOver
                        ? AppColors.accentWarningAmber
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MacroBar(
                  label: 'Protein',
                  current: state.totalProtein,
                  target: targets?.proteinTarget,
                  color: AppColors.macroProtein,
                ),
                const SizedBox(height: 14),
                _MacroBar(
                  label: 'Carbs',
                  current: state.totalCarbs,
                  target: targets?.carbsTarget,
                  color: AppColors.macroCarbs,
                ),
                const SizedBox(height: 14),
                _MacroBar(
                  label: 'Fat',
                  current: state.totalFat,
                  target: targets?.fatTarget,
                  color: AppColors.macroFat,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact macro bar: label + `consumed / target g` on one line, a 5px
/// rounded fill bar beneath. The fill is the macro colour; the track is faint.
class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.current,
    required this.target,
    required this.color,
  });

  final String label;
  final double current;
  final double? target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasTarget = target != null && target! > 0;
    final progress = hasTarget ? (current / target!).clamp(0.0, 1.0) : 0.0;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final valueText = hasTarget
        ? '${current.toStringAsFixed(0)} / ${target!.toStringAsFixed(0)} g'
        : '${current.toStringAsFixed(0)} g';

    return Semantics(
      label: label,
      value: valueText,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  valueText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return Stack(
                      children: [
                        Container(color: colors.outlineVariant),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: progress),
                          duration: reduceMotion
                              ? Duration.zero
                              : AppMotion.emphasized,
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              Container(width: width * value, color: color),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
