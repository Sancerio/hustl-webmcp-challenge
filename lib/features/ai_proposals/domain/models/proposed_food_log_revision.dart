import 'package:equatable/equatable.dart';

/// A snapshot of one nutrition field as it currently stands and (for an edit) what
/// it would become. `to` is null when the field isn't changing.
class FoodFieldChange extends Equatable {
  const FoodFieldChange({required this.label, required this.from, this.to});

  final String label;

  /// The current value, already formatted for display (e.g. '300 kcal').
  final String from;

  /// The proposed value, formatted; null when this field is unchanged.
  final String? to;

  bool get changed => to != null && to != from;

  @override
  List<Object?> get props => [label, from, to];
}

/// The proposed revision carried by a `food_log_edit` / `food_log_delete` proposal.
///
/// The connected LLM pointed at an EXISTING diary entry (by id) to correct or
/// remove it, rather than logging a duplicate. The backend stamps the entry's
/// current values into `proposedPayload.target` so this preview can show
/// before→after without a second fetch. On approve the change is applied and is
/// undoable; on `food_log_delete` the whole entry is removed.
class ProposedFoodLogRevision extends Equatable {
  const ProposedFoodLogRevision({
    required this.isDelete,
    required this.targetEntryId,
    required this.foodName,
    required this.changes,
    this.date,
    this.currentCalories,
  });

  final bool isDelete;
  final String targetEntryId;

  /// The entry's food name (the new name when an edit renames it).
  final String foodName;

  /// For an edit: the per-field before/after rows (changed fields first). Empty
  /// for a delete.
  final List<FoodFieldChange> changes;

  /// The entry's logged day, when known.
  final DateTime? date;

  /// The entry's current calories (shown on a delete preview).
  final double? currentCalories;

  static double? _num(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static DateTime? _date(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  static String _g(double? v) => v == null ? '—' : '${v.round()} g';
  static String _kcal(double? v) => v == null ? '—' : '${v.round()} kcal';
  static String _mg(double? v) => v == null ? '—' : '${v.round()} mg';

  /// Parse from the backend `proposedPayload` map for a revision proposal.
  ///
  /// Payload shape: `{ targetEntryId, target: { foodName, servingGrams, calories,
  /// proteinGrams, carbsGrams, fatGrams, ... }, changes?: { ...subset... } }`.
  static ProposedFoodLogRevision? fromJson(
    Map<String, dynamic>? json, {
    required bool isDelete,
  }) {
    if (json == null || json.isEmpty) return null;
    final target = json['target'] is Map
        ? Map<String, dynamic>.from(json['target'] as Map)
        : <String, dynamic>{};
    final changes = json['changes'] is Map
        ? Map<String, dynamic>.from(json['changes'] as Map)
        : <String, dynamic>{};

    final currentName = target['foodName']?.toString();
    final newName = changes.containsKey('foodName')
        ? changes['foodName']?.toString()
        : null;

    final rows = <FoodFieldChange>[];
    if (!isDelete) {
      // Always show the core macros so the user sees the full picture.
      void add(String label, String Function(double?) fmt, String key) {
        final from = fmt(_num(target[key]));
        final to = changes.containsKey(key) ? fmt(_num(changes[key])) : null;
        rows.add(FoodFieldChange(label: label, from: from, to: to));
      }

      // Optional micros (fiber/sugar/sodium) are usually null, so only show them
      // when they're changing OR already have a value — otherwise they're noise.
      // Critically, ANY field the backend can apply that IS in `changes` must be
      // visible, so a sodium-only edit can never be approved unseen.
      void addOptional(String label, String Function(double?) fmt, String key) {
        final hasChange = changes.containsKey(key);
        final current = _num(target[key]);
        if (!hasChange && current == null) return;
        rows.add(
          FoodFieldChange(
            label: label,
            from: fmt(current),
            to: hasChange ? fmt(_num(changes[key])) : null,
          ),
        );
      }

      if (newName != null && newName != currentName) {
        rows.add(
          FoodFieldChange(label: 'Name', from: currentName ?? '—', to: newName),
        );
      }
      add('Calories', _kcal, 'calories');
      add('Portion', _g, 'servingGrams');
      add('Protein', _g, 'proteinGrams');
      add('Carbs', _g, 'carbsGrams');
      add('Fat', _g, 'fatGrams');
      addOptional('Fiber', _g, 'fiberGrams');
      addOptional('Sugar', _g, 'sugarGrams');
      addOptional('Sodium', _mg, 'sodiumMg');
      // Surface changed fields first so the correction is obvious at a glance.
      rows.sort((a, b) => (b.changed ? 1 : 0) - (a.changed ? 1 : 0));
    }

    return ProposedFoodLogRevision(
      isDelete: isDelete,
      targetEntryId: json['targetEntryId']?.toString() ?? '',
      foodName: (newName ?? currentName ?? 'Food entry'),
      changes: rows,
      date: _date(target['date']),
      currentCalories: _num(target['calories']),
    );
  }

  @override
  List<Object?> get props => [
    isDelete,
    targetEntryId,
    foodName,
    changes,
    date,
    currentCalories,
  ];
}
