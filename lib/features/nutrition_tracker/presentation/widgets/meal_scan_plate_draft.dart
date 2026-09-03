import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import '../../domain/models/meal_scan_result.dart';
import '../utils/macro_format.dart';

/// Editable preview of the AI-estimated plate. Each row shows an item's name,
/// provenance, a muted macro line, an editable grams field, and a remove
/// control. Editing grams proportionally rescales that item's macros.
class MealScanPlateDraft extends StatefulWidget {
  const MealScanPlateDraft({
    super.key,
    required this.items,
    required this.onChanged,
  });

  final List<MealScanItem> items;
  final ValueChanged<List<MealScanItem>> onChanged;

  @override
  State<MealScanPlateDraft> createState() => _MealScanPlateDraftState();
}

class _MealScanPlateDraftState extends State<MealScanPlateDraft> {
  late final List<MealScanItem> _items = List<MealScanItem>.from(widget.items);

  // Stable per-row keys assigned once at init, kept index-aligned with [_items].
  // Keying rows by identity (not index) means removing one row no longer tears
  // down and rebuilds its siblings' State.
  int _nextRowId = 0;
  late final List<Key> _rowKeys = List<Key>.generate(
    _items.length,
    (_) => ValueKey('plate-row-${_nextRowId++}'),
  );

  void _updateItem(int index, MealScanItem next) {
    setState(() => _items[index] = next);
    widget.onChanged(List<MealScanItem>.unmodifiable(_items));
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _rowKeys.removeAt(index);
    });
    widget.onChanged(List<MealScanItem>.unmodifiable(_items));
  }

  /// Linear rescale of per-100g-derived macros from [oldGrams] to [newGrams].
  ///
  /// A grams edit makes weight authoritative, so quantity/unit are realigned to
  /// the new grams (quantity = grams, unit = 'g'). Otherwise the mapper would
  /// keep preferring the old quantity for the serving size + portion label,
  /// committing a stale serving that disagrees with the rescaled macros.
  void _rescaleGrams(int index, double newGrams) {
    final item = _items[index];
    final oldGrams = item.grams;
    if (oldGrams == null || oldGrams <= 0) {
      // No baseline weight to scale from — keep macros, just record grams.
      _updateItem(
        index,
        item.copyWith(grams: newGrams, quantity: newGrams, unit: 'g'),
      );
      return;
    }
    final factor = newGrams / oldGrams;
    double? scale(double? value) => value == null ? null : value * factor;
    _updateItem(
      index,
      item.copyWith(
        grams: newGrams,
        quantity: newGrams,
        unit: 'g',
        caloriesKcal: scale(item.caloriesKcal),
        proteinGrams: scale(item.proteinGrams),
        carbsGrams: scale(item.carbsGrams),
        fatGrams: scale(item.fatGrams),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
        child: Text(
          'No items left. Add a photo or log the total instead.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          _PlateDraftRow(
            key: _rowKeys[i],
            item: _items[i],
            onGramsChanged: (grams) => _rescaleGrams(i, grams),
            onRemove: () => _removeItem(i),
          ),
          if (i != _items.length - 1)
            Divider(
              height: AppSpacing.x2,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
        ],
        const SizedBox(height: AppSpacing.x1),
        _PlateDraftTotals(items: _items),
      ],
    );
  }
}

/// Running total across the remaining draft items.
class _PlateDraftTotals extends StatelessWidget {
  const _PlateDraftTotals({required this.items});

  final List<MealScanItem> items;

  double _sum(double? Function(MealScanItem) pick) =>
      items.fold(0, (acc, item) => acc + (pick(item) ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kcal = _sum((i) => i.caloriesKcal);
    final protein = _sum((i) => i.proteinGrams);
    final carbs = _sum((i) => i.carbsGrams);
    final fat = _sum((i) => i.fatGrams);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Total',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            formatMacros(
              protein: protein,
              fat: fat,
              carbs: carbs,
              calories: kcal,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single editable plate row: name + provenance, macro pills, grams, remove.
class _PlateDraftRow extends StatefulWidget {
  const _PlateDraftRow({
    super.key,
    required this.item,
    required this.onGramsChanged,
    required this.onRemove,
  });

  final MealScanItem item;
  final ValueChanged<double> onGramsChanged;
  final VoidCallback onRemove;

  @override
  State<_PlateDraftRow> createState() => _PlateDraftRowState();
}

class _PlateDraftRowState extends State<_PlateDraftRow> {
  late final TextEditingController _gramsController = TextEditingController(
    text: widget.item.grams == null
        ? ''
        : widget.item.grams!.toStringAsFixed(0),
  );

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  void _commitGrams() {
    final raw = _gramsController.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || value < 0) return;
    widget.onGramsChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final name = item.name.trim().isEmpty ? 'Item' : item.name.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _provenancePill(theme, item),
                    Text(
                      formatMacros(
                        protein: item.proteinGrams,
                        fat: item.fatGrams,
                        carbs: item.carbsGrams,
                        calories: item.caloriesKcal,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          SizedBox(
            width: 76,
            child: TextField(
              controller: _gramsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textAlign: TextAlign.end,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'g',
                labelText: 'Grams',
              ),
              onEditingComplete: _commitGrams,
              onSubmitted: (_) => _commitGrams(),
              onTapOutside: (_) => _commitGrams(),
            ),
          ),
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Remove item',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _provenancePill(ThemeData theme, MealScanItem item) {
    if (item.isDbMatched) {
      final label = (item.matchedName ?? item.name).trim();
      final text = label.isEmpty ? 'Matched' : 'Matched · $label';
      return MacroPills.checkPill(theme, text);
    }
    return MacroPills.mutedPill(theme, 'AI estimate');
  }
}

/// Shared pill builders mirroring the meal photo scan dialog's visual language.
class MacroPills {
  const MacroPills._();

  static Widget _base({
    required ThemeData theme,
    required String text,
    required Color foregroundColor,
    required Color backgroundColor,
    BorderSide? border,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.fromBorderSide(border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget checkPill(ThemeData theme, String text) {
    final color = AppColors.accentEmeraldGreen;
    return _base(
      theme: theme,
      text: text,
      foregroundColor: color,
      backgroundColor: color.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14,
      ),
      icon: Icons.check_circle_outline,
    );
  }

  static Widget mutedPill(ThemeData theme, String text) {
    return _base(
      theme: theme,
      text: text,
      foregroundColor: theme.colorScheme.onSurfaceVariant,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      border: BorderSide(color: theme.colorScheme.outlineVariant),
    );
  }
}
