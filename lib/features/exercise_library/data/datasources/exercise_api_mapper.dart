import '../../domain/models/exercise.dart';

Exercise mapExerciseFromBackend(Map<String, dynamic> m) {
  final String name = (m['name'] ?? '').toString();
  final List<String> primary = List<String>.from(
    m['primary_muscles'] ?? const [],
  );
  final List<String> secondary = List<String>.from(
    m['secondary_muscles'] ?? const [],
  );
  final List<String> muscles = [
    ...primary.map(_toTitleCase),
    ...secondary.map(_toTitleCase),
  ];

  String? imageUrl;
  // Prefer explicit thumbnail_url, then first image variant
  if (m['thumbnail_url'] is String &&
      (m['thumbnail_url'] as String).isNotEmpty) {
    imageUrl = m['thumbnail_url'] as String;
  } else if (m['image_url'] is String &&
      (m['image_url'] as String).isNotEmpty) {
    imageUrl = m['image_url'] as String;
  } else if (m['images'] is List) {
    final List imgs = m['images'] as List;
    if (imgs.isNotEmpty) {
      final first = Map<String, dynamic>.from(imgs.first as Map);
      imageUrl = (first['url'] as String?) ?? imageUrl;
    }
  }

  // equipment can be string or array depending on backend evolution
  final eqRaw = m['equipment'];
  final List<String> equipment = eqRaw is List
      ? List<String>.from(eqRaw.map((e) => _toTitleCase(e.toString())))
      : (eqRaw is String && eqRaw.isNotEmpty)
      ? [_toTitleCase(eqRaw)]
      : const [];

  final String? description =
      (m['description'] as String?)?.trim().isNotEmpty == true
      ? (m['description'] as String)
      : null;

  final List<String> steps = (m['steps'] is List)
      ? List<String>.from((m['steps'] as List).map((e) => e.toString()))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
      : const <String>[];

  final List<String> cues = (m['cues'] is List)
      ? List<String>.from((m['cues'] as List).map((e) => e.toString()))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
      : const <String>[];

  final String? instructions =
      (m['instructions'] as String?)?.trim().isNotEmpty == true
      ? (m['instructions'] as String)
      : null;
  final String? level = (m['level'] as String?)?.trim().isNotEmpty == true
      ? _toTitleCase(m['level'] as String)
      : null;
  final String? mechanic = (m['mechanic'] as String?)?.trim().isNotEmpty == true
      ? _toTitleCase(m['mechanic'] as String)
      : null;
  final String? force = (m['force'] as String?)?.trim().isNotEmpty == true
      ? _toTitleCase(m['force'] as String)
      : null;
  final String? category = (m['category'] as String?)?.trim().isNotEmpty == true
      ? _toTitleCase(m['category'] as String)
      : null;
  final String? pattern =
      (m['movement_pattern'] as String?)?.trim().isNotEmpty == true
      ? _toTitleCase(m['movement_pattern'] as String)
      : null;

  final tags = <String>[
    if (category != null) category,
    if (mechanic != null) mechanic,
    if (force != null) force,
    if (pattern != null) pattern,
    ...equipment,
  ];

  // Map kind if provided by backend; default to strength
  ExerciseKind kind = ExerciseKind.strength;
  final rawKind = m['kind'];
  if (rawKind is String) {
    switch (rawKind.trim().toLowerCase()) {
      case 'cardio':
        kind = ExerciseKind.cardio;
        break;
      case 'assisted':
        kind = ExerciseKind.assisted;
        break;
      default:
        kind = ExerciseKind.strength;
    }
  } else if (rawKind is int) {
    if (rawKind >= 0 && rawKind < ExerciseKind.values.length) {
      kind = ExerciseKind.values[rawKind];
    }
  }

  ExerciseLoggingMode loggingMode = kind == ExerciseKind.cardio
      ? ExerciseLoggingMode.distanceDuration
      : ExerciseLoggingMode.weightReps;
  final rawLogging = m['logging_mode'] ?? m['loggingMode'];
  if (rawLogging is String) {
    final compact = rawLogging.trim().toLowerCase().replaceAll(
      RegExp(r'[_\s-]+'),
      '',
    );
    if (compact.isNotEmpty) {
      switch (compact) {
        case 'weightreps':
          loggingMode = ExerciseLoggingMode.weightReps;
          break;
        case 'distanceduration':
          loggingMode = ExerciseLoggingMode.distanceDuration;
          break;
        case 'durationonly':
          loggingMode = ExerciseLoggingMode.durationOnly;
          break;
      }
    }
  } else if (rawLogging is int) {
    if (rawLogging >= 0 && rawLogging < ExerciseLoggingMode.values.length) {
      loggingMode = ExerciseLoggingMode.values[rawLogging];
    }
  }

  ExerciseVisibility visibility = ExerciseVisibility.catalog;
  final rawVisibility = m['visibility'];
  if (rawVisibility is String) {
    final normalized = rawVisibility.trim().toLowerCase();
    if (normalized == 'private') {
      visibility = ExerciseVisibility.private;
    } else if (normalized == 'public') {
      visibility = ExerciseVisibility.public;
    } else {
      visibility = ExerciseVisibility.catalog;
    }
  }

  // Choose a fallback muscle group when none provided
  String fallbackMuscle;
  if (category != null && category.toLowerCase() != 'unknown') {
    fallbackMuscle = category;
  } else if (pattern != null && pattern.toLowerCase() != 'unknown') {
    fallbackMuscle = pattern;
  } else if (mechanic != null && mechanic.toLowerCase() != 'unknown') {
    fallbackMuscle = mechanic;
  } else {
    fallbackMuscle = 'General';
  }

  return Exercise(
    id: (m['id']?.toString()),
    slug: (m['slug']?.toString()),
    name: _toTitleCase(name),
    muscles: muscles.isEmpty ? <String>[fallbackMuscle] : muscles,
    imageUrl: imageUrl,
    description: description,
    steps: steps,
    cues: cues,
    instructions: instructions,
    equipment: equipment,
    difficulty: level,
    videoUrl: null,
    tags: tags,
    kind: kind,
    loggingMode: loggingMode,
    visibility: visibility,
  );
}

String _toTitleCase(String input) {
  if (input.isEmpty) return input;
  return input
      .split(RegExp(r'[\s_]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
