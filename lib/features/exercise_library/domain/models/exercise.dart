import 'package:flutter/foundation.dart';

enum ExerciseKind { strength, assisted, cardio }

enum ExerciseVisibility { catalog, private, public }

/// Controls how an exercise is logged in the workout logger UI.
///
/// This is intentionally separate from [ExerciseKind] because some "strength"
/// exercises are time-based (e.g., Plank) and some "cardio" entries might be
/// duration-only (e.g., Jump Rope for time).
enum ExerciseLoggingMode { weightReps, distanceDuration, durationOnly }

class Exercise {
  final String? id;
  final String? slug;
  final String name;
  final List<String> muscles;
  final String? imageUrl;
  final String? description;
  final List<String> steps;
  final List<String> cues;
  final String? instructions;
  final List<String> equipment;
  final String? difficulty;
  final String? videoUrl;
  final List<String> tags;
  final bool isFavorite;
  final ExerciseKind kind;
  final ExerciseLoggingMode loggingMode;
  final ExerciseVisibility visibility;

  const Exercise({
    this.id,
    this.slug,
    required this.name,
    required this.muscles,
    this.imageUrl,
    this.description,
    this.steps = const [],
    this.cues = const [],
    this.instructions,
    this.equipment = const [],
    this.difficulty,
    this.videoUrl,
    this.tags = const [],
    this.isFavorite = false,
    this.kind = ExerciseKind.strength,
    this.loggingMode = ExerciseLoggingMode.weightReps,
    this.visibility = ExerciseVisibility.catalog,
  });

  /// Canonical key used for matching historical workout data to this exercise.
  /// Prefers the backend slug when available, otherwise falls back to a
  /// slugified version of the exercise name. The result is always lowercase.
  String? get canonicalKey => canonicalKeyFrom(name: name, slug: slug);

  /// Determine whether this exercise matches the provided identifiers.
  ///
  /// Matching is case-insensitive and tolerant to slug/name differences by
  /// comparing canonical keys and normalized names.
  bool matchesIdentity({String? name, String? slug}) {
    final targetKey = canonicalKeyFrom(name: name, slug: slug);
    final selfKey = canonicalKey;
    if (targetKey != null && selfKey != null && targetKey == selfKey) {
      return true;
    }

    final normalizedTarget = _normalizeName(name);
    final normalizedSelf = _normalizeName(this.name);
    if (normalizedTarget != null && normalizedSelf != null) {
      return normalizedTarget == normalizedSelf;
    }
    return false;
  }

  static String? canonicalKeyFrom({String? name, String? slug}) {
    final slugKey = _normalizeSlug(slug);
    if (slugKey != null) {
      return slugKey;
    }
    final normalizedName = _normalizeName(name);
    if (normalizedName == null) {
      return null;
    }
    final slugified = _slugify(normalizedName);
    return slugified ?? normalizedName;
  }

  static String? _normalizeSlug(String? value) {
    if (value == null) return null;
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final slugified = _slugify(trimmed);
    return slugified ?? trimmed;
  }

  static String? _normalizeName(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.toLowerCase();
  }

  static String? _slugify(String? value) {
    if (value == null) return null;
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? null : slug;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'slug': slug,
      'name': name,
      'muscles': muscles,
      'imageUrl': imageUrl,
      'description': description,
      'steps': steps,
      'cues': cues,
      'instructions': instructions,
      'equipment': equipment,
      'difficulty': difficulty,
      'videoUrl': videoUrl,
      'tags': tags,
      'isFavorite': isFavorite,
      'kind': kind.name,
      'loggingMode': loggingMode.name,
      'visibility': visibility.name,
    };
  }

  factory Exercise.fromMap(Map<String, dynamic> map) {
    ExerciseKind parseKind(dynamic raw) {
      if (raw is String) {
        final normalized = raw.trim().toLowerCase();
        if (normalized.isEmpty) return ExerciseKind.strength;
        return ExerciseKind.values.firstWhere(
          (e) => e.name.toLowerCase() == normalized,
          orElse: () => ExerciseKind.strength,
        );
      }
      if (raw is int) {
        return (raw >= 0 && raw < ExerciseKind.values.length)
            ? ExerciseKind.values[raw]
            : ExerciseKind.strength;
      }
      return ExerciseKind.strength;
    }

    ExerciseLoggingMode parseLoggingMode(dynamic raw, ExerciseKind kind) {
      ExerciseLoggingMode fallback() => kind == ExerciseKind.cardio
          ? ExerciseLoggingMode.distanceDuration
          : ExerciseLoggingMode.weightReps;

      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return fallback();
        final compact = trimmed.toLowerCase().replaceAll(
          RegExp(r'[_\\s-]+'),
          '',
        );
        switch (compact) {
          case 'weightreps':
            return ExerciseLoggingMode.weightReps;
          case 'distanceduration':
            return ExerciseLoggingMode.distanceDuration;
          case 'durationonly':
            return ExerciseLoggingMode.durationOnly;
        }
        try {
          return ExerciseLoggingMode.values.firstWhere(
            (e) => e.name.toLowerCase() == compact,
          );
        } catch (_) {
          return fallback();
        }
      }

      if (raw is int) {
        return (raw >= 0 && raw < ExerciseLoggingMode.values.length)
            ? ExerciseLoggingMode.values[raw]
            : fallback();
      }

      return fallback();
    }

    ExerciseVisibility parseVisibility(dynamic raw) {
      if (raw is String) {
        final normalized = raw.trim().toLowerCase();
        if (normalized.isEmpty) return ExerciseVisibility.catalog;
        return ExerciseVisibility.values.firstWhere(
          (e) => e.name.toLowerCase() == normalized,
          orElse: () => ExerciseVisibility.catalog,
        );
      }
      final id = map['id'] as String?;
      if (id != null && id.startsWith('custom-')) {
        // Legacy local custom exercises were prefixed with "custom-".
        return ExerciseVisibility.private;
      }
      return ExerciseVisibility.catalog;
    }

    final kind = parseKind(map['kind']);
    final rawLoggingMode = map['loggingMode'] ?? map['logging_mode'];
    final loggingMode = parseLoggingMode(rawLoggingMode, kind);
    final visibility = parseVisibility(map['visibility']);

    return Exercise(
      id: map['id'] as String?,
      slug: map['slug'] as String?,
      name: map['name'] ?? '',
      muscles: List<String>.from(map['muscles'] ?? []),
      imageUrl: map['imageUrl'],
      description: map['description'],
      steps: List<String>.from(map['steps'] ?? const []),
      cues: List<String>.from(map['cues'] ?? const []),
      instructions: map['instructions'] as String?,
      equipment: List<String>.from(map['equipment'] ?? []),
      difficulty: map['difficulty'],
      videoUrl: map['videoUrl'],
      tags: List<String>.from(map['tags'] ?? []),
      isFavorite: map['isFavorite'] ?? false,
      kind: kind,
      loggingMode: loggingMode,
      visibility: visibility,
    );
  }

  Exercise copyWith({
    String? id,
    String? slug,
    String? name,
    List<String>? muscles,
    String? imageUrl,
    String? description,
    List<String>? steps,
    List<String>? cues,
    String? instructions,
    List<String>? equipment,
    String? difficulty,
    String? videoUrl,
    List<String>? tags,
    bool? isFavorite,
    ExerciseKind? kind,
    ExerciseLoggingMode? loggingMode,
    ExerciseVisibility? visibility,
  }) {
    return Exercise(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      muscles: muscles ?? this.muscles,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      steps: steps ?? this.steps,
      cues: cues ?? this.cues,
      instructions: instructions ?? this.instructions,
      equipment: equipment ?? this.equipment,
      difficulty: difficulty ?? this.difficulty,
      videoUrl: videoUrl ?? this.videoUrl,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      kind: kind ?? this.kind,
      loggingMode: loggingMode ?? this.loggingMode,
      visibility: visibility ?? this.visibility,
    );
  }

  @override
  String toString() =>
      'Exercise(id: $id, slug: $slug, name: $name, muscles: $muscles, imageUrl: $imageUrl, description: $description, steps: ${steps.length}, cues: ${cues.length}, equipment: $equipment, difficulty: $difficulty, videoUrl: $videoUrl, tags: $tags, isFavorite: $isFavorite, kind: ${kind.name}, loggingMode: ${loggingMode.name})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Exercise &&
        other.id == id &&
        other.slug == slug &&
        other.name == name &&
        listEquals(other.muscles, muscles) &&
        other.imageUrl == imageUrl &&
        other.description == description &&
        listEquals(other.steps, steps) &&
        listEquals(other.cues, cues) &&
        other.instructions == instructions &&
        listEquals(other.equipment, equipment) &&
        other.difficulty == difficulty &&
        other.videoUrl == videoUrl &&
        listEquals(other.tags, tags) &&
        other.isFavorite == isFavorite &&
        other.kind == kind &&
        other.loggingMode == loggingMode;
  }

  @override
  int get hashCode =>
      (id?.hashCode ?? 0) ^
      (slug?.hashCode ?? 0) ^
      name.hashCode ^
      muscles.hashCode ^
      imageUrl.hashCode ^
      description.hashCode ^
      steps.hashCode ^
      cues.hashCode ^
      instructions.hashCode ^
      equipment.hashCode ^
      difficulty.hashCode ^
      videoUrl.hashCode ^
      tags.hashCode ^
      isFavorite.hashCode ^
      kind.hashCode ^
      loggingMode.hashCode;
}
