import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';

/// The MacroFactor-style header shared by the weight, expenditure, and other
/// nutrition trend screens: two big stats side by side (e.g. Average +
/// Difference), the visible date range beneath them, and a circular button that
/// toggles the chart's vertical "fit to data" zoom.
class ChartStatHeader extends StatelessWidget {
  const ChartStatHeader({
    super.key,
    required this.leadingLabel,
    required this.leadingValue,
    required this.leadingUnit,
    required this.trailingLabel,
    required this.trailingValue,
    required this.trailingUnit,
    required this.dateRangeText,
    this.trailingValueColor,
    this.fitActive = false,
    this.onToggleFit,
  });

  final String leadingLabel;
  final String leadingValue;
  final String leadingUnit;

  final String trailingLabel;
  final String trailingValue;
  final String trailingUnit;

  /// Optional accent for the difference numeral (e.g. goal-aware color); falls
  /// back to neutral onSurface for the clean reference look.
  final Color? trailingValueColor;

  final String dateRangeText;

  final bool fitActive;
  final VoidCallback? onToggleFit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Stat(
                label: leadingLabel,
                value: leadingValue,
                unit: leadingUnit,
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: _Stat(
                label: trailingLabel,
                value: trailingValue,
                unit: trailingUnit,
                valueColor: trailingValueColor,
              ),
            ),
            if (onToggleFit != null) ...[
              const SizedBox(width: AppSpacing.x2),
              _FitButton(active: fitActive, onTap: onToggleFit!),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          dateRangeText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.unit,
    this.valueColor,
  });

  final String label;
  final String value;
  final String unit;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A touch smaller than the 40px hero so two stats sit comfortably two-up.
    final valueStyle = AppTextStyles.nutritionHero(context).copyWith(
      fontSize: 32,
      height: 36 / 32,
      color: valueColor ?? theme.colorScheme.onSurface,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Sub-8 values here are intentional intra-cluster kerning (label↔value,
        // value↔unit, unit baseline), not list/section rhythm — the 8pt grid
        // governs the structural gaps above, handled via AppSpacing.
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: valueStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                unit,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The circular vertical-resize button: toggles the chart between a padded view
/// and a tight "fit to data" zoom.
class _FitButton extends StatelessWidget {
  const _FitButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = active
        ? colors.primary.withValues(alpha: 0.14)
        : colors.surfaceContainerHighest;
    final fg = active ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      toggled: active,
      label: 'Fit chart to data',
      child: Material(
        color: bg,
        shape: CircleBorder(
          side: BorderSide(color: colors.outlineVariant, width: 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.unfold_more, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}
