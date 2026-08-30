import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

import '../../domain/models/food_log_entry.dart';
import '../utils/macro_format.dart';
import 'food_entry_avatar.dart';

/// A single editable plate row: tap the body (or the pencil) to reveal an inline
/// portion editor, tap the X to remove. When [isEditing] the row expands to show
/// a − / grams / + stepper plus quick chips; every grams change rescales the
/// entry live through [onGramsChanged] so the Cal·P·F·C line re-reads instantly.
///
/// A short-lived [highlighted] tint is used right after a scan to draw the eye
/// to the freshly-added row whose portion needs a glance.
class PlateReviewRow extends StatelessWidget {
  const PlateReviewRow({
    super.key,
    required this.entry,
    required this.onToggleEdit,
    required this.onGramsChanged,
    required this.onRemove,
    this.isEditing = false,
    this.highlighted = false,
  });

  final FoodLogEntry entry;

  /// Toggles the inline portion editor for this row open/closed.
  final VoidCallback onToggleEdit;

  /// Fires with the new absolute grams as the stepper / chips are used. The
  /// parent rescales the entry (calories + macros) and re-renders this row.
  final ValueChanged<double> onGramsChanged;

  final VoidCallback onRemove;

  /// Whether the inline portion editor is expanded for this row.
  final bool isEditing;

  /// Whether to paint a brief primary tint behind the row (post-scan emphasis).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = entry.foodName ?? entry.food?.name ?? 'Food';
    final macros = formatMacros(
      protein: entry.proteinGrams,
      fat: entry.fatGrams,
      carbs: entry.carbsGrams,
      calories: entry.calories,
    );

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.emphasizedCurve,
      decoration: BoxDecoration(
        color: highlighted
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: AppRadius.controlRadius,
        border: highlighted
            ? Border.all(color: colors.primary.withValues(alpha: 0.6))
            : Border.all(color: Colors.transparent),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggleEdit,
            borderRadius: AppRadius.controlRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.x1,
                horizontal: AppSpacing.x1 - 4,
              ),
              child: Row(
                children: [
                  // Same name->emoji glyph + source badge the diary rows use, so
                  // the plate reads as one system with the diary.
                  FoodEntryAvatar(name: name, source: entry.source),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$macros · ${entry.servingGrams.toStringAsFixed(0)} g',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Visible pencil affordance so editing the portion is
                  // discoverable (not just a hidden row tap). Tints to primary
                  // while the editor is open.
                  IconButton(
                    onPressed: onToggleEdit,
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    color: isEditing ? colors.primary : colors.onSurfaceVariant,
                    tooltip: isEditing ? 'Done' : 'Edit portion',
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    color: colors.onSurfaceVariant,
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
          // The inline portion editor expands/collapses beneath the macro line.
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.emphasizedCurve,
            alignment: Alignment.topCenter,
            child: isEditing
                ? _PlatePortionEditor(
                    grams: entry.servingGrams,
                    onGramsChanged: onGramsChanged,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Entry-native portion controls (no `Food` required) that mirror the visual
/// language of [AddFoodPortionStepper]: a − / grams / + stepper plus quick
/// chips. Reports the new absolute grams up via [onGramsChanged]; the parent
/// owns the rescale, so this widget stays a thin, stateless controller driven by
/// the live [grams].
class _PlatePortionEditor extends StatelessWidget {
  const _PlatePortionEditor({required this.grams, required this.onGramsChanged});

  /// The entry's current absolute grams (source of truth lives in the parent).
  final double grams;
  final ValueChanged<double> onGramsChanged;

  static const double _step = 5;

  /// Clamp to ≥1 g and round to whole grams so the stepper never produces a
  /// fractional or non-positive portion.
  double _normalize(double value) => value.clamp(1, 100000).roundToDouble();

  void _nudge(double delta) {
    Haptics.selection();
    onGramsChanged(_normalize(grams + delta));
  }

  void _scale(double factor) {
    Haptics.selection();
    onGramsChanged(_normalize(grams * factor));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.x1),
      padding: const EdgeInsets.all(AppSpacing.x1 + 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: AppRadius.controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // - / grams / + stepper.
          Row(
            children: [
              _StepperButton(
                icon: Icons.remove,
                onPressed: () => _nudge(-_step),
              ),
              Expanded(
                child: Text(
                  '${grams.toStringAsFixed(0)} g',
                  key: const Key('plateRowGrams'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StepperButton(icon: Icons.add, onPressed: () => _nudge(_step)),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          // Quick chips: relative nudges and multipliers off the current grams.
          Wrap(
            spacing: AppSpacing.x1,
            runSpacing: AppSpacing.x1,
            children: [
              _QuickChip(label: '−25 g', onPressed: () => _nudge(-25)),
              _QuickChip(label: '+25 g', onPressed: () => _nudge(25)),
              _QuickChip(label: '½×', onPressed: () => _scale(0.5)),
              _QuickChip(label: '2×', onPressed: () => _scale(2)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A pill that applies a relative portion change in one tap. Mirrors the
/// multiplier pills in [AddFoodPortionStepper].
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: AppRadius.pillRadius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.pillRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x1 + 4,
            vertical: 6,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
