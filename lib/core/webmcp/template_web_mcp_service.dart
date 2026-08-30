import '../../features/ai_proposals/domain/models/template_proposal_result.dart';
import '../../features/workout_templates/domain/models/workout_template.dart';
import '../../features/workout_templates/domain/repositories/template_repository.dart';

const templateNormalizationWarning =
    'This template cannot be edited losslessly. A proposal replaces the full '
    'template and normalizes exercises to uniform regular sets with explicit '
    'rest. Per-set differences, special set types, placeholder/default values, '
    'assisted weights, extra exercises, and out-of-range values may be removed '
    'or clamped.';

class TemplateWebMcpContext {
  const TemplateWebMcpContext({
    required this.templateId,
    required this.updatedAt,
    required this.plan,
    required this.lossyOnEdit,
    required this.syncedForEdit,
  });

  final String templateId;
  final DateTime updatedAt;
  final TemplateProposalPlan plan;
  final bool lossyOnEdit;
  final bool syncedForEdit;

  bool get editable => syncedForEdit && plan.exercises.isNotEmpty;

  Map<String, Object?> toJson() => {
    'status': 'ready',
    'templateId': templateId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'exerciseCount': plan.exercises.length,
    'plan': plan.toJson(),
    'lossyOnEdit': lossyOnEdit,
    'editable': editable,
    if (!syncedForEdit) 'editUnavailableReason': 'template_not_synced',
    if (lossyOnEdit) 'warning': templateNormalizationWarning,
  };
}

class TemplateWebMcpService {
  TemplateWebMcpService({
    required TemplateRepository repository,
    Future<bool> Function(String templateId)? isSyncedForEdit,
  }) : _repository = repository,
       _isSyncedForEdit = isSyncedForEdit ?? _alwaysEditable;

  final TemplateRepository _repository;
  final Future<bool> Function(String templateId) _isSyncedForEdit;

  static Future<bool> _alwaysEditable(String _) async => true;

  Future<TemplateWebMcpContext?> load(String templateId) async {
    final template = await _repository.getWorkoutTemplate(templateId);
    if (template == null) return null;
    final syncedForEdit = await _isSyncedForEdit(templateId);
    return normalize(template, syncedForEdit: syncedForEdit);
  }

  static TemplateWebMcpContext normalize(
    WorkoutTemplate template, {
    bool syncedForEdit = true,
  }) {
    var lossy = false;

    String boundedString(String value, int max) {
      final trimmed = value.trim();
      if (trimmed != value || trimmed.length > max) lossy = true;
      return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
    }

    var name = boundedString(template.name, 120);
    if (name.isEmpty) {
      name = 'Untitled template';
      lossy = true;
    }
    final description = boundedString(template.description, 2000);
    final rawExercises = template.exercises;
    if (rawExercises.length > 30) lossy = true;
    final exercises = <TemplateProposalExercise>[];

    for (final raw in rawExercises.take(30)) {
      if (raw is! Map) {
        lossy = true;
        continue;
      }
      if (raw.keys.any((key) => key is! String)) {
        lossy = true;
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final rawName = map['exerciseId'];
      if (rawName is! String || rawName.trim().isEmpty) {
        lossy = true;
        continue;
      }
      final exerciseName = boundedString(rawName, 120);

      final rawPreviousSets = map['previousSets'];
      final sourceSets = rawPreviousSets is List
          ? rawPreviousSets
          : const <dynamic>[];
      if (rawPreviousSets != null && rawPreviousSets is! List) lossy = true;
      final previousSets = sourceSets
          .whereType<Map>()
          .where((set) => set.keys.every((key) => key is String))
          .map((set) => Map<String, dynamic>.from(set))
          .toList(growable: false);
      if (sourceSets.length != previousSets.length) {
        lossy = true;
      }
      if (previousSets.isEmpty) lossy = true;
      final first = previousSets.isEmpty
          ? const <String, dynamic>{}
          : previousSets.first;
      if (!_setsAreUniform(previousSets) ||
          previousSets.any(
            (set) => set['setType'] != null && set['setType'] != 'regular',
          )) {
        lossy = true;
      }
      final placeholder = map['targetsArePlaceholder'] == true;
      if (placeholder) lossy = true;

      final setsFallback = previousSets.isEmpty ? 1 : previousSets.length;
      final sets = _boundedInt(map['sets'], setsFallback, 1, 20);
      if (sets.changed) lossy = true;
      if (previousSets.isNotEmpty && previousSets.length != sets.value) {
        lossy = true;
      }
      final rest = _boundedInt(map['restTimerSeconds'], 0, 0, 600);
      if (rest.changed || map['restTimerSeconds'] is! num) lossy = true;

      int? reps;
      double? weight;
      int? rpe;
      String? notes;
      if (!placeholder) {
        final rawReps = first['reps'];
        if (rawReps is num && rawReps > 0) {
          final bounded = _boundedInt(rawReps, 1, 1, 100);
          reps = bounded.value;
          if (bounded.changed) lossy = true;
        }
        final rawWeight = first['weight'];
        if (rawWeight is num && rawWeight < 0) {
          lossy = true;
        } else if (rawWeight is num && rawWeight > 0) {
          weight = rawWeight.toDouble().clamp(0, 2000).toDouble();
          if (weight != rawWeight.toDouble()) lossy = true;
        }
        final rawRpe = first['rpe'];
        if (rawRpe is num) {
          final bounded = _boundedInt(rawRpe, 1, 1, 10);
          rpe = bounded.value;
          if (bounded.changed) lossy = true;
        }
        final rawNotes = first['notes'] ?? map['notes'];
        if (rawNotes is String && rawNotes.trim().isNotEmpty) {
          notes = boundedString(rawNotes, 500);
        }
      }

      String? slug;
      final rawSlug = map['slug'];
      if (rawSlug is String && rawSlug.isNotEmpty) {
        final trimmed = rawSlug.trim();
        if (RegExp(r'^[a-z0-9-]+$').hasMatch(trimmed)) {
          slug = trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);
          if (slug != rawSlug) lossy = true;
        } else {
          lossy = true;
        }
      }

      exercises.add(
        TemplateProposalExercise(
          exerciseId: exerciseName,
          slug: slug,
          sets: sets.value,
          repsTarget: reps,
          restTimerSeconds: rest.value,
          weightTarget: weight,
          rpeTarget: rpe,
          notes: notes,
        ),
      );
    }

    return TemplateWebMcpContext(
      templateId: template.id,
      updatedAt: template.updatedAt,
      plan: TemplateProposalPlan(
        name: name,
        description: description.isEmpty ? null : description,
        exercises: exercises,
      ),
      lossyOnEdit: lossy,
      syncedForEdit: syncedForEdit,
    );
  }

  static bool _setsAreUniform(List<Map<String, dynamic>> sets) {
    if (sets.length < 2) return true;
    final first = sets.first;
    return sets
        .skip(1)
        .every(
          (set) =>
              set['reps'] == first['reps'] &&
              set['weight'] == first['weight'] &&
              set['rpe'] == first['rpe'] &&
              set['notes'] == first['notes'],
        );
  }

  static ({int value, bool changed}) _boundedInt(
    Object? raw,
    int fallback,
    int min,
    int max,
  ) {
    if (raw is! num || !raw.isFinite) {
      return (value: fallback.clamp(min, max), changed: true);
    }
    final rounded = raw.round();
    final bounded = rounded.clamp(min, max);
    return (value: bounded, changed: raw.toDouble() != bounded.toDouble());
  }
}
