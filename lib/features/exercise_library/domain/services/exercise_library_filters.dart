import '../models/exercise.dart';

const List<String> exerciseLibraryMuscleGroupOptions = <String>[
  'Arms',
  'Chest',
  'Legs',
  'Shoulders',
  'Back',
  'Core',
  'Abs',
  'Obliques',
];

const List<String> exerciseLibraryEquipmentOptions = <String>[
  'Dumbbell',
  'Barbell',
  'Bodyweight',
  'Machine',
  'Kettlebell',
  'Cable',
];

const List<String> exerciseLibraryDifficultyOptions = <String>[
  'Beginner',
  'Intermediate',
  'Advanced',
];

const List<String> exerciseLibraryTypeOptions = <String>[
  'Strength',
  'Mobility',
  'Cardio',
  'Plyometrics',
];

const Set<String> _absAliases = <String>{
  'abs',
  'abdominal',
  'abdominals',
  'upperabs',
  'lowerabs',
  'upperabdominal',
  'lowerabdominal',
  'upperabdominals',
  'lowerabdominals',
  'rectusabdominis',
  'sixpack',
};

const Set<String> _obliqueAliases = <String>{'oblique', 'obliques'};

const Map<String, Set<String>> _filterAliases = <String, Set<String>>{
  'abs': _absAliases,
  'abdominals': _absAliases,
  'oblique': _obliqueAliases,
  'obliques': _obliqueAliases,
  'core': <String>{'core', ..._absAliases, ..._obliqueAliases},
};

bool matchesExerciseLibraryFilter(Exercise exercise, String filter) {
  final normalizedFilter = _normalizeFilterToken(filter);
  if (normalizedFilter.isEmpty) return false;

  final searchTerms = _expandFilterTerms(normalizedFilter);
  for (final candidate in _filterCandidatesForExercise(exercise)) {
    final normalizedCandidate = _normalizeFilterToken(candidate);
    if (normalizedCandidate.isEmpty) continue;
    if (_matchesCandidate(normalizedCandidate, searchTerms)) {
      return true;
    }
  }

  return false;
}

Iterable<String> _filterCandidatesForExercise(Exercise exercise) sync* {
  yield exercise.name;
  yield* exercise.muscles;
  yield* exercise.equipment;
  final difficulty = exercise.difficulty;
  if (difficulty != null) {
    yield difficulty;
  }
  yield switch (exercise.kind) {
    ExerciseKind.strength => 'Strength',
    ExerciseKind.assisted => 'Assisted',
    ExerciseKind.cardio => 'Cardio',
  };
  yield* exercise.tags;
}

Set<String> _expandFilterTerms(String normalizedValue) {
  return <String>{normalizedValue, ...?_filterAliases[normalizedValue]};
}

bool _matchesCandidate(String candidate, Set<String> searchTerms) {
  final candidateTerms = _expandFilterTerms(candidate);
  for (final term in searchTerms) {
    if (candidateTerms.contains(term)) {
      return true;
    }
    if (candidate.contains(term) || term.contains(candidate)) {
      return true;
    }
    if (candidateTerms.any(
      (value) => value.contains(term) || term.contains(value),
    )) {
      return true;
    }
  }
  return false;
}

String _normalizeFilterToken(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
