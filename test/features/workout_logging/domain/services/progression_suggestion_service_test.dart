import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/services/progression_suggestion_service.dart';

void main() {
  const service = ProgressionSuggestionService();

  WorkoutSet set({
    required double weight,
    required int reps,
    bool isCompleted = true,
    int? rpe,
    SetType setType = SetType.regular,
    String? parentSetId,
  }) {
    return WorkoutSet(
      id: 's',
      weight: weight,
      reps: reps,
      isCompleted: isCompleted,
      rpe: rpe,
      setType: setType,
      parentSetId: parentSetId,
    );
  }

  ProgressionSuggestion? suggest(
    WorkoutSet prev, {
    ExerciseLoggingMode mode = ExerciseLoggingMode.weightReps,
    ProgressionUnit unit = ProgressionUnit.kg,
  }) {
    return service.suggestFromPreviousSet(
      previous: prev,
      loggingMode: mode,
      unit: unit,
    );
  }

  group('rule 1 — no previous working set at index', () {
    test('empty list yields no suggestion', () {
      expect(
        service.suggestForWorkingSetIndex(
          previousSessionSets: const [],
          workingSetIndex: 0,
          loggingMode: ExerciseLoggingMode.weightReps,
        ),
        isNull,
      );
    });

    test('index beyond available working sets yields no suggestion', () {
      expect(
        service.suggestForWorkingSetIndex(
          previousSessionSets: [set(weight: 100, reps: 5)],
          workingSetIndex: 1,
          loggingMode: ExerciseLoggingMode.weightReps,
        ),
        isNull,
      );
    });
  });

  group('rule 2 — non weight×reps logging modes defer', () {
    test('durationOnly yields no suggestion', () {
      expect(
        suggest(
          set(weight: 100, reps: 10),
          mode: ExerciseLoggingMode.durationOnly,
        ),
        isNull,
      );
    });

    test('distanceDuration yields no suggestion', () {
      expect(
        suggest(
          set(weight: 100, reps: 10),
          mode: ExerciseLoggingMode.distanceDuration,
        ),
        isNull,
      );
    });
  });

  group('rule 3 — incomplete previous set', () {
    test('incomplete set yields no suggestion', () {
      expect(suggest(set(weight: 100, reps: 10, isCompleted: false)), isNull);
    });
  });

  group('rule 4 — reps >= 8 double progression', () {
    test('heavy compound adds one increment at same reps', () {
      final result = suggest(set(weight: 100, reps: 8));
      expect(result, const ProgressionSuggestion(weightKg: 102.5, reps: 8));
    });

    test('+5% cap on a light isolation lift adds a rep instead', () {
      // 2.5 kg on a 20 kg curl is 12.5% (> 5%): keep weight, add a rep.
      final result = suggest(set(weight: 20, reps: 10));
      expect(result, const ProgressionSuggestion(weightKg: 20, reps: 11));
    });

    test('cap boundary — exactly at 50 kg allows the weight bump', () {
      // increment 2.5 == 5% of 50, so 2.5 > 2.5 is false: weight bumps.
      final result = suggest(set(weight: 50, reps: 8));
      expect(result, const ProgressionSuggestion(weightKg: 52.5, reps: 8));
    });
  });

  group('rule 5 — reps < 8 adds a rep', () {
    test('same weight, one more rep', () {
      final result = suggest(set(weight: 100, reps: 5));
      expect(result, const ProgressionSuggestion(weightKg: 100, reps: 6));
    });
  });

  group('rule 6 — failure / 0 RIR consolidates', () {
    test('RPE 10 (0 RIR) keeps weight and reps even with reps >= 8', () {
      final result = suggest(set(weight: 100, reps: 8, rpe: 10));
      expect(result, const ProgressionSuggestion(weightKg: 100, reps: 8));
    });

    test('RPE 8 (2 RIR) still applies normal progression', () {
      final result = suggest(set(weight: 100, reps: 8, rpe: 8));
      expect(result, const ProgressionSuggestion(weightKg: 102.5, reps: 8));
    });
  });

  group('rule 7 — rounding to the plate grid', () {
    test('off-grid weight rounds to nearest 0.5 kg after the bump', () {
      // 60.1 + 2.5 = 62.6 -> nearest 0.5 kg = 62.5.
      final result = suggest(set(weight: 60.1, reps: 8));
      expect(result, const ProgressionSuggestion(weightKg: 62.5, reps: 8));
    });
  });

  group('rule 8 — bodyweight / assisted defer', () {
    test('zero weight yields no suggestion', () {
      expect(suggest(set(weight: 0, reps: 12)), isNull);
    });

    test('negative (assisted) weight yields no suggestion', () {
      expect(suggest(set(weight: -20, reps: 10)), isNull);
    });

    test('zero reps yields no suggestion', () {
      expect(suggest(set(weight: 100, reps: 0)), isNull);
    });
  });

  group('working-set filtering', () {
    test('warm-up sets are excluded from the working index', () {
      final sets = [
        set(weight: 40, reps: 12, setType: SetType.warmup),
        set(weight: 100, reps: 8),
      ];
      // Working index 0 maps to the 100 kg working set, not the warm-up.
      expect(
        service.suggestForWorkingSetIndex(
          previousSessionSets: sets,
          workingSetIndex: 0,
          loggingMode: ExerciseLoggingMode.weightReps,
        ),
        const ProgressionSuggestion(weightKg: 102.5, reps: 8),
      );
      // Only one working set exists, so index 1 is out of range.
      expect(
        service.suggestForWorkingSetIndex(
          previousSessionSets: sets,
          workingSetIndex: 1,
          loggingMode: ExerciseLoggingMode.weightReps,
        ),
        isNull,
      );
    });

    test('dropset children are excluded from the working index', () {
      final sets = [
        set(weight: 100, reps: 8),
        set(
          weight: 80,
          reps: 6,
          setType: SetType.dropset,
          parentSetId: 'parent',
        ),
      ];
      // The drop is filtered out, so index 1 is out of range.
      expect(
        service.suggestForWorkingSetIndex(
          previousSessionSets: sets,
          workingSetIndex: 1,
          loggingMode: ExerciseLoggingMode.weightReps,
        ),
        isNull,
      );
    });
  });

  group('display unit — lb rounds on the imperial grid', () {
    test('reps < 8 keeps the (kg) weight and adds a rep', () {
      // 100 lb == 45.359237 kg; reps < 8 keeps weight, +1 rep.
      final result = suggest(
        set(weight: 45.359237, reps: 5),
        unit: ProgressionUnit.lb,
      );
      expect(result!.reps, 6);
      expect(result.weightKg, closeTo(45.359237, 1e-6));
    });

    test('+5 lb bump rounds to 1.25 lb grid then back to kg', () {
      // 100 lb, reps 10: 5 lb is exactly 5% (not > 5%), so weight bumps to
      // 105 lb, already on the 1.25 lb grid -> 105 * 0.45359237 kg.
      final result = suggest(
        set(weight: 45.359237, reps: 10),
        unit: ProgressionUnit.lb,
      );
      expect(result!.reps, 10);
      expect(result.weightKg, closeTo(105 * 0.45359237, 1e-6));
    });

    test('+5% cap in lb adds a rep on a light lift', () {
      // 40 lb, reps 10: 5 lb is 12.5% (> 5%), so keep weight, add a rep.
      final result = suggest(
        set(weight: 40 * 0.45359237, reps: 10),
        unit: ProgressionUnit.lb,
      );
      expect(result!.reps, 11);
      expect(result.weightKg, closeTo(40 * 0.45359237, 1e-6));
    });
  });
}
