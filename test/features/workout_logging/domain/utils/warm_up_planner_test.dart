import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/utils/warm_up_planner.dart';

WorkoutSet _set({
  required String id,
  required double weight,
  int reps = 5,
  SetType type = SetType.regular,
}) {
  return WorkoutSet(id: id, weight: weight, reps: reps, setType: type);
}

void main() {
  group('buildWarmUpSuggestions', () {
    test('ramps the %-ladder from a bare target — no logged set required', () {
      final ladder = buildWarmUpSuggestions(
        targetWeight: 100,
        reps: 8,
        isAssisted: false,
      );

      // 40 / 60 / 75 percent for an 8-rep working set (no 90% rung above 6).
      expect(ladder.map((s) => s.weight), [40, 60, 75]);
      // Sorted easiest (lightest) first.
      expect(ladder.first.weight, 40);
      expect(ladder.last.weight, 75);
    });

    test('adds a 90% rung for low working reps', () {
      final ladder = buildWarmUpSuggestions(
        targetWeight: 100,
        reps: 3,
        isAssisted: false,
      );
      expect(ladder.map((s) => s.weight), [40, 60, 75, 90]);
    });

    test('returns nothing for a zero / blank target', () {
      expect(
        buildWarmUpSuggestions(targetWeight: 0, reps: 8, isAssisted: false),
        isEmpty,
      );
    });

    test('inverts for assisted machines — warm-ups carry MORE assistance', () {
      // Assisted target of -40 (40kg of assistance). A warm-up should be
      // *more* assisted (more negative) and sorted most-assistance first.
      final ladder = buildWarmUpSuggestions(
        targetWeight: -40,
        reps: 8,
        isAssisted: true,
      );
      expect(ladder, isNotEmpty);
      // Every suggestion is negative (assistance) and heavier than the target.
      for (final s in ladder) {
        expect(s.weight, lessThan(0));
        expect(s.weight.abs(), greaterThan(40));
      }
      // Easiest (most assistance) first.
      expect(ladder.first.weight.abs(), greaterThanOrEqualTo(ladder.last.weight.abs()));
    });
  });

  group('resolveWarmUpSeed', () {
    test('prefers a current-session working set over PR and previous', () {
      final seed = resolveWarmUpSeed(
        currentSets: [_set(id: 'c', weight: 80, reps: 6)],
        previousSessionSets: [_set(id: 'p', weight: 70, reps: 8)],
        prWeight: 90,
        prReps: 5,
        isAssisted: false,
      );
      expect(seed, isNotNull);
      expect(seed!.source, WarmUpSeedSource.currentSet);
      expect(seed.targetWeight, 80);
      expect(seed.reps, 6);
    });

    test('seeds from PR when there is no current or previous set', () {
      final seed = resolveWarmUpSeed(
        currentSets: const [],
        previousSessionSets: null,
        prWeight: 52.5,
        prReps: 8,
        isAssisted: false,
      );
      expect(seed, isNotNull);
      expect(seed!.source, WarmUpSeedSource.pr);
      expect(seed.targetWeight, 52.5);
      expect(seed.reps, 8);
    });

    test('current-session warm-ups do not count as a seed', () {
      final seed = resolveWarmUpSeed(
        currentSets: [_set(id: 'w', weight: 20, type: SetType.warmup)],
        previousSessionSets: null,
        prWeight: 60,
        prReps: 5,
        isAssisted: false,
      );
      // Falls through the warm-up to the PR.
      expect(seed!.source, WarmUpSeedSource.pr);
      expect(seed.targetWeight, 60);
    });

    test('falls back to previous-session top set when PR is unresolved', () {
      final seed = resolveWarmUpSeed(
        currentSets: const [],
        previousSessionSets: [
          _set(id: 'p1', weight: 60, reps: 8),
          _set(id: 'p2', weight: 70, reps: 6),
        ],
        prWeight: null,
        prReps: null,
        isAssisted: false,
      );
      expect(seed, isNotNull);
      expect(seed!.source, WarmUpSeedSource.previousSession);
      // Heaviest previous working set wins.
      expect(seed.targetWeight, 70);
      expect(seed.reps, 6);
    });

    test('returns null when there is truly no data', () {
      final seed = resolveWarmUpSeed(
        currentSets: const [],
        previousSessionSets: const [],
        prWeight: null,
        prReps: null,
        isAssisted: false,
      );
      expect(seed, isNull);
    });

    test('assisted PR is the lightest load (least assistance)', () {
      // The caller resolves the assisted PR as the lightest (-30 vs -40).
      final seed = resolveWarmUpSeed(
        currentSets: const [],
        previousSessionSets: null,
        prWeight: -30,
        prReps: 6,
        isAssisted: true,
      );
      expect(seed!.source, WarmUpSeedSource.pr);
      expect(seed.targetWeight, -30);
    });

    test('assisted current set picks the lightest assistance', () {
      final seed = resolveWarmUpSeed(
        currentSets: [
          _set(id: 'a', weight: -40, reps: 8),
          _set(id: 'b', weight: -30, reps: 6),
        ],
        previousSessionSets: null,
        isAssisted: true,
      );
      expect(seed!.source, WarmUpSeedSource.currentSet);
      // Lightest assistance (-30) is the "top" set for assisted.
      expect(seed.targetWeight, -30);
    });
  });

  group('warmUpSupportsLogging', () {
    test('only the weight-based logging mode supports warm-ups', () {
      // Weight/reps (strength bars, assisted machines) is the only mode that
      // surfaces a kg field, so it is the only one a kg %-ladder applies to.
      expect(warmUpSupportsLogging(ExerciseLoggingMode.weightReps), isTrue);
    });

    test(
      'duration-only strength (Wall Sit / Plank) gets no warm-up support',
      () {
        // These are kind == strength but hide weight and read reps as seconds:
        // gating on kind alone (the old bug) would let kg warm-ups seed hidden
        // -weight, "8-12 second" rows. Gating on logging mode rejects them.
        expect(
          warmUpSupportsLogging(ExerciseLoggingMode.durationOnly),
          isFalse,
        );
      },
    );

    test('distance/duration cardio gets no warm-up support', () {
      expect(
        warmUpSupportsLogging(ExerciseLoggingMode.distanceDuration),
        isFalse,
      );
    });
  });
}
