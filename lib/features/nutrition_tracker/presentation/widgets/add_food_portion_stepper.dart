import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/services/haptics.dart';

import '../../domain/models/food.dart';

/// Inline grams picker that expands under a search result. Replaces the
/// grams `AlertDialog`, dropping add-food from 3 taps to 2: tap a food to
/// reveal the stepper, tap Add to commit. The live macro preview updates as
/// grams change.
///
/// Quick multipliers (0.5x / 1x / 2x) preset the portion instantly off the
/// food's default serving, and a unit toggle flips the display between grams
/// and servings when the food carries a serving size — both apply haptics.
class AddFoodPortionStepper extends StatefulWidget {
  const AddFoodPortionStepper({
    super.key,
    required this.food,
    required this.onAdd,
    required this.onCancel,
  });

  final Food food;
  final ValueChanged<double> onAdd;
  final VoidCallback onCancel;

  @override
  State<AddFoodPortionStepper> createState() => _AddFoodPortionStepperState();
}

class _AddFoodPortionStepperState extends State<AddFoodPortionStepper> {
  late final TextEditingController _controller;
  late double _grams;
  bool _servingUnit = false;

  static const _step = 10.0;
  static const _multipliers = [0.5, 1.0, 2.0];

  /// Base portion the quick multipliers scale from: the food's default serving
  /// when present, else a 100g reference. Stable so multipliers don't compound.
  ///
  // For a `recent` search result the backend sets `servingSizeGrams` to the
  // user's LAST-USED portion for this food, so re-logging a staple pre-fills the
  // grams they always use rather than the catalog 100g default — no special
  // casing needed here, it flows through `servingSizeGrams`.
  double get _baseGrams =>
      (widget.food.servingSizeGrams ?? 100).clamp(1, 100000).toDouble();

  bool get _hasServing => (widget.food.servingSizeGrams ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _grams = _baseGrams;
    _controller = TextEditingController(text: _fieldText());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The field's text in the active unit: servings (1 decimal) or grams (int).
  String _fieldText() {
    if (_servingUnit) {
      final servings = _grams / _baseGrams;
      return _trimDecimal(servings.toStringAsFixed(1));
    }
    return _grams.toStringAsFixed(0);
  }

  String _trimDecimal(String value) =>
      value.endsWith('.0') ? value.substring(0, value.length - 2) : value;

  void _syncField() {
    final text = _fieldText();
    if (_controller.text != text) {
      _controller
        ..text = text
        ..selection = TextSelection.collapsed(offset: text.length);
    }
  }

  void _setGrams(double value) {
    final clamped = value.clamp(1, 100000).toDouble();
    setState(() => _grams = clamped);
    _syncField();
  }

  void _nudge(int direction) {
    Haptics.selection();
    // In serving mode each tap nudges by a quarter of the base serving so the
    // step feels proportional; in grams mode it stays a fixed gram step.
    final step = _servingUnit ? _baseGrams * 0.25 : _step;
    _setGrams(_grams + direction * step);
  }

  void _applyMultiplier(double multiplier) {
    Haptics.selection();
    _setGrams(_baseGrams * multiplier);
  }

  void _toggleUnit() {
    if (!_hasServing) return;
    Haptics.selection();
    setState(() => _servingUnit = !_servingUnit);
    _syncField();
  }

  void _onFieldChanged(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) return;
    setState(() => _grams = _servingUnit ? value * _baseGrams : value);
  }

  String _macroPreview() {
    final factor = _grams / 100;
    final cals = ((widget.food.caloriesPer100g ?? 0) * factor).toStringAsFixed(
      0,
    );
    final p = ((widget.food.proteinPer100g ?? 0) * factor).toStringAsFixed(0);
    final c = ((widget.food.carbsPer100g ?? 0) * factor).toStringAsFixed(0);
    final f = ((widget.food.fatPer100g ?? 0) * factor).toStringAsFixed(0);
    return '$cals kcal · ${p}P ${c}C ${f}F';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.x1, bottom: AppSpacing.x1),
      padding: const EdgeInsets.all(AppSpacing.x1 + 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _macroPreview(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          // Quick multipliers preset the portion off the default serving in one
          // tap so common amounts need no manual typing.
          Row(
            children: [
              for (final m in _multipliers) ...[
                _MultiplierButton(
                  label: '${_trimDecimal(m.toStringAsFixed(1))}x',
                  selected: (_grams - _baseGrams * m).abs() < 0.5,
                  onPressed: () => _applyMultiplier(m),
                ),
                const SizedBox(width: AppSpacing.x1),
              ],
              _UnitToggle(
                key: const Key('portionUnitToggle'),
                label: _servingUnit ? 'serving' : 'g',
                enabled: _hasServing,
                onPressed: _toggleUnit,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          // Stepper controls on their own row: the grams field flexes so the
          // minus/plus buttons stay fixed and nothing overflows on narrow
          // phones. The Cancel/Add actions live on a second row below.
          Row(
            children: [
              _StepperButton(icon: Icons.remove, onPressed: () => _nudge(-1)),
              const SizedBox(width: AppSpacing.x1),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: TextField(
                    controller: _controller,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AppTextStyles.metric(
                      theme.textTheme.titleMedium ?? const TextStyle(),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: _servingUnit ? 'srv' : 'g',
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppRadius.control - 4,
                        ),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: _onFieldChanged,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              _StepperButton(icon: Icons.add, onPressed: () => _nudge(1)),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          // Actions sit on a second row, end-aligned, so Cancel + Add never
          // contend with the stepper controls for horizontal room at 320px.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.x1),
              FilledButton(
                onPressed: () {
                  Haptics.selection();
                  if (_grams > 0) widget.onAdd(_grams);
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A pill that presets the portion to a multiple of the default serving. Tints
/// to the primary container when its multiple matches the current amount.
class _MultiplierButton extends StatelessWidget {
  const _MultiplierButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
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
              color: selected
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tap-to-switch unit chip. Shows the active unit ('g' or 'serving') and flips
/// between them; disabled (and muted) when the food has no serving size.
class _UnitToggle extends StatelessWidget {
  const _UnitToggle({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: AppRadius.pillRadius,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: AppRadius.pillRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x1 + 4,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (enabled) ...[
                Icon(
                  Icons.swap_horiz,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: enabled
                      ? colors.onSurfaceVariant
                      : colors.onSurfaceVariant.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
