import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import '../../domain/models/food_log_entry.dart';
import '../utils/macro_format.dart';
import 'diary_entry_tile.dart';

/// Builds the muted hourly/meal macro summary: "380 kcal · P30 F10 C42".
String _macroSummary(List<FoodLogEntry> entries) {
  var cal = 0.0, p = 0.0, f = 0.0, c = 0.0;
  for (final e in entries) {
    cal += e.calories;
    p += e.proteinGrams;
    f += e.fatGrams;
    c += e.carbsGrams;
  }
  return formatMacros(protein: p, fat: f, carbs: c, calories: cal);
}

/// A 28px ghost '+' button (§12.2): no fill, no border — just the muted glyph.
class _GhostAddButton extends StatelessWidget {
  const _GhostAddButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: () {
            Haptics.selection();
            onTap();
          },
          radius: 20,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// The diary's multi-select state, threaded down to the rows so selection mode
/// is a purely additive overlay on the existing meal/timeline layout. When
/// [active] is false every field below it is inert and rows render exactly as
/// before.
class DiarySelection {
  const DiarySelection({
    this.active = false,
    this.selectedIds = const {},
    this.onToggle,
    this.onToggleGroup,
    this.onEnter,
  });

  final bool active;
  final Set<String> selectedIds;

  /// Toggles a single entry's selection.
  final ValueChanged<String>? onToggle;

  /// Selects every id in the group if any is unselected; clears them all when
  /// the whole group is already selected. Wired to meal/hour headers.
  final ValueChanged<List<String>>? onToggleGroup;

  /// Long-press entry point: enters selection mode with this id pre-selected.
  final ValueChanged<String>? onEnter;

  bool isSelected(String id) => selectedIds.contains(id);
}

/// Interleaves hairline dividers between flat food tiles, threading the shared
/// [selection] state so each row can render its checkbox / selected state.
List<Widget> _tilesWithDividers(
  List<FoodLogEntry> entries, {
  required ValueChanged<String> onDelete,
  required ValueChanged<FoodLogEntry> onEdit,
  required DiarySelection selection,
}) {
  return [
    for (var i = 0; i < entries.length; i++) ...[
      if (i > 0) const Divider(),
      DiaryEntryTile(
        entry: entries[i],
        onDelete: onDelete,
        onTap: () => onEdit(entries[i]),
        selectionMode: selection.active,
        selected: selection.isSelected(entries[i].id),
        onSelectToggle: () => selection.onToggle?.call(entries[i].id),
        onLongPress: () => selection.onEnter?.call(entries[i].id),
      ),
    ],
  ];
}

/// Meal-grouped list shown for sparse days (fewer than the timeline
/// threshold): flat 13px UPPERCASE meal headers with the day's foods as flat
/// divider-bound tiles — no card chrome.
class DiaryMealSections extends StatelessWidget {
  const DiaryMealSections({
    super.key,
    required this.entries,
    required this.onDelete,
    required this.onEdit,
    required this.onAddToMeal,
    this.selection = const DiarySelection(),
  });

  final List<FoodLogEntry> entries;
  final ValueChanged<String> onDelete;
  final ValueChanged<FoodLogEntry> onEdit;

  /// Called with a representative hour for the chosen meal section.
  final ValueChanged<int> onAddToMeal;

  final DiarySelection selection;

  static const _slots = <_MealSlot>[
    _MealSlot('Breakfast', 0, 11, 8),
    _MealSlot('Lunch', 11, 15, 12),
    _MealSlot('Dinner', 15, 21, 19),
    _MealSlot('Snack', 21, 24, 22),
  ];

  _MealSlot _slotForHour(int hour) {
    for (final slot in _slots) {
      if (hour >= slot.startHour && hour < slot.endHour) return slot;
    }
    return _slots.last;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <_MealSlot, List<FoodLogEntry>>{
      for (final slot in _slots) slot: <FoodLogEntry>[],
    };
    for (final entry in entries) {
      grouped[_slotForHour(entry.loggedAt.toLocal().hour)]!.add(entry);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slot in _slots)
          _MealSection(
            slot: slot,
            entries: grouped[slot]!,
            onDelete: onDelete,
            onEdit: onEdit,
            onAdd: () => onAddToMeal(slot.addHour),
            selection: selection,
          ),
      ],
    );
  }
}

class _MealSlot {
  const _MealSlot(this.title, this.startHour, this.endHour, this.addHour);

  final String title;
  final int startHour;
  final int endHour;
  final int addHour;
}

class _MealSection extends StatelessWidget {
  const _MealSection({
    required this.slot,
    required this.entries,
    required this.onDelete,
    required this.onEdit,
    required this.onAdd,
    required this.selection,
  });

  final _MealSlot slot;
  final List<FoodLogEntry> entries;
  final ValueChanged<String> onDelete;
  final ValueChanged<FoodLogEntry> onEdit;
  final VoidCallback onAdd;
  final DiarySelection selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selecting = selection.active;

    final header = SectionHeader(
      slot.title,
      padding: const EdgeInsets.only(top: AppSpacing.x2),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entries.isNotEmpty)
            Text(_macroSummary(entries), style: theme.textTheme.bodySmall),
          // The ghost add button is meaningless while multi-selecting — hide it
          // and let a header tap select the whole section instead.
          if (!selecting) ...[
            const SizedBox(width: AppSpacing.x1),
            _GhostAddButton(
              onTap: onAdd,
              label: 'Add to ${slot.title.toLowerCase()}',
            ),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selecting && entries.isNotEmpty)
          InkWell(
            onTap: () =>
                selection.onToggleGroup?.call([for (final e in entries) e.id]),
            child: header,
          )
        else
          header,
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x1),
            child: Text('Nothing logged yet', style: theme.textTheme.bodySmall),
          )
        else
          ..._tilesWithDividers(
            entries,
            onDelete: onDelete,
            onEdit: onEdit,
            selection: selection,
          ),
      ],
    );
  }
}

/// MacroFactor-style timeline view for densely-logged days. Only renders hour
/// slots that contain entries plus the current hour: a muted 12px hour label,
/// a 28px ghost '+', a muted hourly summary line, then the hour's foods as
/// flat divider-bound tiles.
class DiaryTimeline extends StatelessWidget {
  const DiaryTimeline({
    super.key,
    required this.entriesByHour,
    required this.onDelete,
    required this.onEdit,
    required this.onAddAtHour,
    this.currentHourKey,
    this.highlightCurrentHour = true,
    this.selection = const DiarySelection(),
  });

  final Map<int, List<FoodLogEntry>> entriesByHour;
  final ValueChanged<String> onDelete;
  final ValueChanged<FoodLogEntry> onEdit;
  final ValueChanged<int> onAddAtHour;
  final GlobalKey? currentHourKey;
  final bool highlightCurrentHour;
  final DiarySelection selection;

  @override
  Widget build(BuildContext context) {
    final currentHour = highlightCurrentHour ? DateTime.now().hour : -1;

    // Only show hours that hold entries (+ the current hour). Empty slots add
    // scroll distance without value.
    final hours = <int>{...entriesByHour.keys};
    if (highlightCurrentHour) hours.add(currentHour);
    final sorted = hours.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final hour in sorted)
          _TimelineHourSlot(
            key: hour == currentHour ? currentHourKey : null,
            hour: hour,
            entries: entriesByHour[hour] ?? const [],
            isCurrentHour: hour == currentHour,
            onDelete: onDelete,
            onEdit: onEdit,
            onAdd: () => onAddAtHour(hour),
            selection: selection,
          ),
      ],
    );
  }
}

class _TimelineHourSlot extends StatelessWidget {
  const _TimelineHourSlot({
    super.key,
    required this.hour,
    required this.entries,
    required this.isCurrentHour,
    required this.onDelete,
    required this.onEdit,
    required this.onAdd,
    required this.selection,
  });

  final int hour;
  final List<FoodLogEntry> entries;
  final bool isCurrentHour;
  final ValueChanged<String> onDelete;
  final ValueChanged<FoodLogEntry> onEdit;
  final VoidCallback onAdd;
  final DiarySelection selection;

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEntries = entries.isNotEmpty;
    final selecting = selection.active;

    // Hour label 12/w500 muted; the current hour gets quiet monochrome
    // emphasis (onSurface w600), never an accent.
    final hourStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: isCurrentHour ? FontWeight.w600 : FontWeight.w500,
      color: isCurrentHour
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
    );

    final headerRow = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(_formatHour(hour), style: hourStyle)),
          // The ghost add button is meaningless while multi-selecting — hide it
          // and let an hour-row tap select the whole hour instead.
          if (!selecting)
            _GhostAddButton(
              onTap: onAdd,
              label: 'Add food at ${_formatHour(hour)}',
            ),
          const SizedBox(width: AppSpacing.x1),
          if (hasEntries)
            Expanded(
              child: Text(
                _macroSummary(entries),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selecting && hasEntries)
          InkWell(
            onTap: () =>
                selection.onToggleGroup?.call([for (final e in entries) e.id]),
            child: headerRow,
          )
        else
          headerRow,
        if (hasEntries) ...[
          ..._tilesWithDividers(
            entries,
            onDelete: onDelete,
            onEdit: onEdit,
            selection: selection,
          ),
          const SizedBox(height: AppSpacing.x1),
        ],
      ],
    );
  }
}
