import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

import '../../domain/models/food_log_entry.dart';
import '../utils/macro_format.dart';
import 'food_entry_avatar.dart';

/// Stage 2 of [CopyFromDaySheet]: the chosen day's entries as checkable rows,
/// with a running total and a "Copy N items" action. Every item starts checked,
/// so the common "copy the whole day" case is still one tap — but the user can
/// uncheck the few they don't want (MacroFactor-style). Returns the SELECTED
/// source entries via [onCopy]; [onBack] returns to the day list.
class CopyDayItemPicker extends StatefulWidget {
  const CopyDayItemPicker({
    super.key,
    required this.dayLabel,
    required this.entries,
    required this.onBack,
    required this.onCopy,
  });

  final String dayLabel;
  final List<FoodLogEntry> entries;
  final VoidCallback onBack;
  final ValueChanged<List<FoodLogEntry>> onCopy;

  @override
  State<CopyDayItemPicker> createState() => _CopyDayItemPickerState();
}

class _CopyDayItemPickerState extends State<CopyDayItemPicker> {
  late final Set<String> _checked = widget.entries.map((e) => e.id).toSet();

  List<FoodLogEntry> get _selected =>
      widget.entries.where((e) => _checked.contains(e.id)).toList();

  double get _selectedCalories =>
      _selected.fold(0.0, (sum, e) => sum + e.calories);

  bool get _allChecked => _checked.length == widget.entries.length;

  void _toggle(String id) {
    setState(() {
      _checked.contains(id) ? _checked.remove(id) : _checked.add(id);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_allChecked) {
        _checked.clear();
      } else {
        _checked.addAll(widget.entries.map((e) => e.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = _selected.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x1,
            0,
            AppSpacing.x2,
            AppSpacing.x1,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
              Expanded(
                child: Text(
                  'Copy from ${widget.dayLabel}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: _toggleAll,
                child: Text(_allChecked ? 'Clear' : 'Select all'),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
            itemCount: widget.entries.length,
            itemBuilder: (context, i) => _ItemRow(
              entry: widget.entries[i],
              checked: _checked.contains(widget.entries[i].id),
              onToggle: () => _toggle(widget.entries[i].id),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            AppSpacing.x1,
            AppSpacing.x3,
            AppSpacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$n ${n == 1 ? 'item' : 'items'} · '
                  '${_selectedCalories.toStringAsFixed(0)} Cal',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton(
                onPressed: n == 0
                    ? null
                    : () {
                        Haptics.confirm();
                        widget.onCopy(_selected);
                      },
                child: Text('Copy $n ${n == 1 ? 'item' : 'items'}'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.entry,
    required this.checked,
    required this.onToggle,
  });

  final FoodLogEntry entry;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = entry.foodName ?? entry.food?.name ?? 'Food';
    final serving = entry.servingGrams > 0
        ? '${entry.servingGrams.toStringAsFixed(0)} g'
        : null;
    final macros = formatMacros(
      protein: entry.proteinGrams,
      fat: entry.fatGrams,
      carbs: entry.carbsGrams,
      calories: entry.calories,
    );
    final subtitle = serving == null ? macros : '$serving · $macros';

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
        child: Row(
          children: [
            Checkbox(value: checked, onChanged: (_) => onToggle()),
            const SizedBox(width: AppSpacing.x1),
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
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
