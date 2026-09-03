import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models/food_log_entry.dart';

class EditFoodEntrySheet extends StatefulWidget {
  const EditFoodEntrySheet({
    super.key,
    required this.entry,
    required this.onSave,
  });

  final FoodLogEntry entry;
  final ValueChanged<Map<String, dynamic>> onSave;

  @override
  State<EditFoodEntrySheet> createState() => _EditFoodEntrySheetState();
}

class _EditFoodEntrySheetState extends State<EditFoodEntrySheet> {
  late final TextEditingController _gramsController;
  late final TextEditingController _calController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;

  late DateTime _loggedAt;

  bool get _isManual => widget.entry.food == null;

  @override
  void initState() {
    super.initState();
    _gramsController = TextEditingController(
      text: widget.entry.servingGrams.toStringAsFixed(0),
    );
    _calController = TextEditingController(
      text: widget.entry.calories.toStringAsFixed(0),
    );
    _proteinController = TextEditingController(
      text: widget.entry.proteinGrams.toStringAsFixed(0),
    );
    _carbsController = TextEditingController(
      text: widget.entry.carbsGrams.toStringAsFixed(0),
    );
    _fatController = TextEditingController(
      text: widget.entry.fatGrams.toStringAsFixed(0),
    );

    _loggedAt = widget.entry.loggedAt.toLocal();

    // Live-rescale the macros as the user changes the serving size. For no-food
    // entries the editable cal/macro fields are scaled from the original entry
    // values by the grams ratio; for food-backed entries we just rebuild so the
    // computed preview recomputes from per-100g.
    _gramsController.addListener(_onGramsChanged);
  }

  @override
  void dispose() {
    _gramsController.removeListener(_onGramsChanged);
    _gramsController.dispose();
    _calController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  // Reacts to serving-size edits so the macros stay in sync with the portion.
  // No-food entries scale their editable fields from the ORIGINAL entry values
  // (stable ratio, not the current field text, so repeated edits don't drift);
  // food-backed entries just rebuild so the computed preview updates.
  void _onGramsChanged() {
    final grams = double.tryParse(
      _gramsController.text.trim().replaceAll(',', '.'),
    );

    if (_isManual) {
      final base = widget.entry.servingGrams;
      if (grams == null || grams <= 0 || base <= 0) return;
      final factor = grams / base;
      setState(() {
        _calController.text = (widget.entry.calories * factor).toStringAsFixed(
          0,
        );
        _proteinController.text = (widget.entry.proteinGrams * factor)
            .toStringAsFixed(0);
        _carbsController.text = (widget.entry.carbsGrams * factor)
            .toStringAsFixed(0);
        _fatController.text = (widget.entry.fatGrams * factor).toStringAsFixed(
          0,
        );
      });
    } else {
      // Food-backed: no editable macro fields, but the preview below the serving
      // field recomputes from per-100g on rebuild.
      setState(() {});
    }
  }

  // Builds the live "≈ N cal · Ng P · Ng C · Ng F" line for a food-backed entry
  // at the current serving (falls back to the entry's serving when the field is
  // empty/invalid). Mirrors _submit's per-100g math so the preview matches save.
  String _computedPreview() {
    final food = widget.entry.food;
    if (food == null) return '';
    final grams =
        double.tryParse(_gramsController.text.trim().replaceAll(',', '.')) ??
        widget.entry.servingGrams;
    final factor = (grams > 0 ? grams : widget.entry.servingGrams) / 100;
    final cal = ((food.caloriesPer100g ?? 0) * factor).round();
    final protein = ((food.proteinPer100g ?? 0) * factor).round();
    final carbs = ((food.carbsPer100g ?? 0) * factor).round();
    final fat = ((food.fatPer100g ?? 0) * factor).round();
    return '\u2248 $cal cal \u00b7 ${protein}g P \u00b7 ${carbs}g C \u00b7 ${fat}g F';
  }

  Future<void> _pickTime() async {
    final initial = TimeOfDay.fromDateTime(_loggedAt);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _loggedAt = DateTime(
        _loggedAt.year,
        _loggedAt.month,
        _loggedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  // Re-date the entry to any day (two years back through a year ahead, matching
  // the diary's own calendar). The time-of-day is preserved; only y/m/d change,
  // so the entry can move to a different day.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _loggedAt,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _loggedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _loggedAt.hour,
        _loggedAt.minute,
        _loggedAt.second,
      );
    });
  }

  // Snap the time to right now without opening the dial — keeps the entry on its
  // original day, only the clock changes (same contract as [_pickTime]).
  void _setTimeToNow() {
    final now = TimeOfDay.now();
    setState(() {
      _loggedAt = DateTime(
        _loggedAt.year,
        _loggedAt.month,
        _loggedAt.day,
        now.hour,
        now.minute,
      );
    });
  }

  void _submit() {
    final grams =
        double.tryParse(_gramsController.text.trim().replaceAll(',', '.')) ??
        widget.entry.servingGrams;
    if (grams <= 0) return;

    final patch = <String, dynamic>{
      'servingGrams': grams,
      'consumedAt': _loggedAt.toUtc().toIso8601String(),
      // The diary day is explicit so re-dating an entry recomputes BOTH days
      // server-side (it does not derive the day from loggedAt + timezone).
      'date': DateFormat('yyyy-MM-dd').format(_loggedAt),
    };

    if (_isManual) {
      patch['calories'] =
          double.tryParse(_calController.text.trim().replaceAll(',', '.')) ??
          widget.entry.calories;
      patch['proteinGrams'] =
          double.tryParse(
            _proteinController.text.trim().replaceAll(',', '.'),
          ) ??
          widget.entry.proteinGrams;
      patch['carbsGrams'] =
          double.tryParse(_carbsController.text.trim().replaceAll(',', '.')) ??
          widget.entry.carbsGrams;
      patch['fatGrams'] =
          double.tryParse(_fatController.text.trim().replaceAll(',', '.')) ??
          widget.entry.fatGrams;
    } else {
      final food = widget.entry.food!;
      final factor = grams / 100;
      patch['calories'] = (food.caloriesPer100g ?? 0) * factor;
      patch['proteinGrams'] = (food.proteinPer100g ?? 0) * factor;
      patch['carbsGrams'] = (food.carbsPer100g ?? 0) * factor;
      patch['fatGrams'] = (food.fatPer100g ?? 0) * factor;
      if (food.fiberPer100g != null) {
        patch['fiberGrams'] = food.fiberPer100g! * factor;
      }
      if (food.sugarPer100g != null) {
        patch['sugarGrams'] = food.sugarPer100g! * factor;
      }
      if (food.sodiumMgPer100g != null) {
        patch['sodiumMg'] = food.sodiumMgPer100g! * factor;
      }
    }

    widget.onSave(patch);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name =
        widget.entry.foodName ?? widget.entry.food?.name ?? 'Food entry';
    final timeLabel = DateFormat('h:mm a').format(_loggedAt);
    final dateLabel = DateFormat('EEE, MMM d, y').format(_loggedAt);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Edit entry',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(name, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _gramsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Serving (g)'),
                ),
              ),
            ],
          ),
          // Food-backed entries have no editable macro fields, so show a live
          // preview of the totals at the current serving (computed from the
          // food's per-100g values, the same math _submit uses on save).
          if (!_isManual) ...[
            const SizedBox(height: 8),
            Text(
              _computedPreview(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text('Logged on $dateLabel'),
            trailing: TextButton(
              onPressed: _pickDate,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
              ),
              child: const Text('Change date'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.schedule),
            title: Text('Logged at $timeLabel'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _setTimeToNow,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Now'),
                ),
                TextButton(
                  onPressed: _pickTime,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          if (_isManual) ...[
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _calController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Calories'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _proteinController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Protein (g)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _carbsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Carbs (g)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fatController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Fat (g)'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              child: const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}
