import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/exercise_card.dart';

/// A repo that returns a fixed PR so the planner can seed from it deterministically.
class _PrRepo extends MockWorkoutRepository {
  _PrRepo(this._pr);
  final ExercisePr? _pr;

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    return _pr;
  }
}

/// A repo whose PR lookup completes only when the test releases it, so we can
/// open the planner while the PR future is still pending and assert the seed
/// still honours the PR (PR-before-previous contract) rather than falling
/// through to previous-session data.
class _PendingPrRepo extends MockWorkoutRepository {
  _PendingPrRepo(this._pr);
  final ExercisePr? _pr;
  final Completer<ExercisePr?> _completer = Completer<ExercisePr?>();

  void release() => _completer.complete(_pr);

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) {
    return _completer.future;
  }
}

/// A repo whose PR lookup fails, exercising the planner's error path: the
/// fire-and-forget seed fetch must swallow the error and leave the seed null.
class _ThrowingPrRepo extends MockWorkoutRepository {
  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    throw Exception('PR lookup failed');
  }
}

Widget _host(Widget child) {
  // MaterialApp.router so the sheet's context.pop (go_router) resolves — the app
  // uses go_router, and the planner dismisses via context.pop per repo guidelines.
  return MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SizedBox(width: 390, child: ListView(children: [child])),
          ),
        ),
      ],
    ),
  );
}

Future<void> _openPlanner(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chip-warmup')));
  await tester.pumpAndSettle();
}

void main() {
  WorkoutExercise? lastUpdate;

  setUp(() async {
    lastUpdate = null;
    await GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    GetIt.I.registerSingleton<PreferencesService>(prefs);
  });

  tearDown(() async {
    await GetIt.I.reset(dispose: true);
  });

  void registerRepo(WorkoutRepository repo) {
    GetIt.I.registerSingleton<WorkoutRepository>(repo);
  }

  Future<void> pumpCard(WidgetTester tester, WorkoutExercise exercise) async {
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: exercise,
          onExerciseUpdated: (e) => lastUpdate = e,
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'planner OPENS with no data and shows no "log a working set" snackbar',
    (tester) async {
      registerRepo(_PrRepo(null));
      await pumpCard(
        tester,
        const WorkoutExercise(
          id: 'ex1',
          exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
          sets: [],
        ),
      );

      await _openPlanner(tester);

      // The sheet is up (editable target field present)...
      expect(find.byKey(const Key('warmupTargetField')), findsOneWidget);
      // ...and the old scary gate snackbar is gone.
      expect(find.textContaining('Log at least one working set'), findsNothing);
      // Apply is disabled until a target is typed; Skip is offered instead of
      // a Cancel-only dead end.
      expect(find.text('Skip'), findsOneWidget);
      final apply = tester.widget<FilledButton>(
        find.byKey(const Key('warmupApply')),
      );
      expect(apply.onPressed, isNull);
    },
  );

  testWidgets('seeds from PR when there are no current/previous sets', (
    tester,
  ) async {
    registerRepo(_PrRepo(const ExercisePr(weight: 52.5, reps: 8)));
    await pumpCard(
      tester,
      const WorkoutExercise(
        id: 'ex1',
        exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
        sets: [],
      ),
    );

    await _openPlanner(tester);

    // The seed line names the PR it is ramping from.
    expect(find.textContaining('Ramping from PR 52.5 kg'), findsOneWidget);
    // The target field is pre-seeded with the PR weight.
    final field = tester.widget<TextField>(
      find.byKey(const Key('warmupTargetField')),
    );
    expect(field.controller!.text, '52.5');
    // The ladder generated suggestions (40/60/75% of 52.5). The revamped
    // rung renders the weight magnitude and the percentage as separate
    // labels, so assert on each rather than a single combined string.
    expect(find.text('21'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets(
    'a locale-seeded target (comma decimals) still produces suggestions',
    (tester) async {
      // Under a comma-decimal locale, a display formatter would render the PR
      // as "52,5", which double.tryParse rejects — yielding no suggestions and
      // a disabled Apply. The field must instead seed a parse-stable canonical
      // number so the ladder builds without the user retyping anything.
      final previousLocale = Intl.defaultLocale;
      Intl.defaultLocale = 'de';
      addTearDown(() => Intl.defaultLocale = previousLocale);

      registerRepo(_PrRepo(const ExercisePr(weight: 52.5, reps: 8)));
      await pumpCard(
        tester,
        const WorkoutExercise(
          id: 'ex1',
          exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
          sets: [],
        ),
      );

      await _openPlanner(tester);

      // The field carries a parse-stable value, NOT the "52,5" a display
      // formatter would emit under this locale.
      final field = tester.widget<TextField>(
        find.byKey(const Key('warmupTargetField')),
      );
      expect(field.controller!.text, '52.5');

      // Suggestions exist immediately (Apply is enabled) — the seed parsed.
      final apply = tester.widget<FilledButton>(
        find.byKey(const Key('warmupApply')),
      );
      expect(apply.onPressed, isNotNull);
      expect(find.text('40%'), findsOneWidget);
    },
  );

  testWidgets(
    'opening the planner before the PR future completes still seeds from the PR',
    (tester) async {
      // The PR fetch is still in flight when Warm-up is tapped. Without the
      // bounded await, resolveWarmUpSeed would fall through to the previous
      // session (40 kg) and stay anchored there. With it, the planner waits for
      // the PR (52.5 kg) and seeds from it instead.
      final repo = _PendingPrRepo(const ExercisePr(weight: 52.5, reps: 8));
      registerRepo(repo);
      await pumpCard(
        tester,
        const WorkoutExercise(
          id: 'ex1',
          exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
          sets: [],
          // Previous session would seed 40 kg — the PR must win over this.
          previousSessionSets: [
            WorkoutSet(id: 'p0', weight: 40, reps: 5, isCompleted: true),
          ],
        ),
      );

      // Tap Warm-up while the PR future is still pending (not yet released).
      await tester.tap(find.byKey(const ValueKey('chip-warmup')));
      await tester.pump();
      // Now let the PR fetch resolve, inside the bounded wait window.
      repo.release();
      await tester.pumpAndSettle();

      // The seed is the PR (52.5 kg), NOT the previous session (40 kg).
      expect(find.textContaining('Ramping from PR 52.5 kg'), findsOneWidget);
      expect(find.textContaining('last workout'), findsNothing);
      final field = tester.widget<TextField>(
        find.byKey(const Key('warmupTargetField')),
      );
      expect(field.controller!.text, '52.5');
      // Revamped rung: weight + percent are separate labels.
      expect(find.text('21'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
    },
  );

  testWidgets(
    'a comma-decimal target normalises to a dot (52,5 -> 52.5, not 525)',
    (tester) async {
      // Comma-decimal keyboards / paste emit "52,5". A plain allow([0-9.])
      // filter would drop the comma and concatenate to "525", letting Apply ramp
      // off a 525 kg target. The field must rewrite ',' to '.' so the ladder
      // builds from 52.5 (40% rung = 21 kg), never 525 (40% rung = 210 kg).
      registerRepo(_PrRepo(null));
      await pumpCard(
        tester,
        const WorkoutExercise(
          id: 'ex1',
          exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
          sets: [],
        ),
      );

      await _openPlanner(tester);

      await tester.enterText(
        find.byKey(const Key('warmupTargetField')),
        '52,5',
      );
      await tester.pumpAndSettle();

      // The comma was normalised to a dot, not dropped.
      final field = tester.widget<TextField>(
        find.byKey(const Key('warmupTargetField')),
      );
      expect(field.controller!.text, '52.5');

      // The ladder is built from 52.5 (40% rung = 21 kg), not 525
      // (whose 40% rung would render a 210 weight label).
      expect(find.text('21'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('210'), findsNothing);
    },
  );

  testWidgets(
    'a PR fetch error leaves the planner usable (no crash, no seed)',
    (tester) async {
      // getExercisePr throwing must not raise an uncaught async exception; the
      // planner simply opens with no seed and the lifter types a target.
      registerRepo(_ThrowingPrRepo());
      await pumpCard(
        tester,
        const WorkoutExercise(
          id: 'ex1',
          exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
          sets: [],
        ),
      );

      await _openPlanner(tester);

      expect(find.byKey(const Key('warmupTargetField')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('warmupTargetField')),
      );
      // No seed survived the failed fetch.
      expect(field.controller!.text, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('seeds from a typed target with zero history, then applies', (
    tester,
  ) async {
    registerRepo(_PrRepo(null));
    await pumpCard(
      tester,
      const WorkoutExercise(
        id: 'ex1',
        exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
        sets: [],
      ),
    );

    await _openPlanner(tester);

    // Type a target; the ladder recomputes live.
    await tester.enterText(find.byKey(const Key('warmupTargetField')), '100');
    await tester.pumpAndSettle();
    // Revamped rung: weight magnitude (40) and percent (40%) are separate.
    expect(find.text('40'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);

    // Apply is now enabled.
    final apply = tester.widget<FilledButton>(
      find.byKey(const Key('warmupApply')),
    );
    expect(apply.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('warmupApply')));
    await tester.pumpAndSettle();

    // Warm-up sets were materialised.
    expect(lastUpdate, isNotNull);
    final warmups = lastUpdate!.sets
        .where((s) => s.setType == SetType.warmup)
        .toList();
    expect(warmups, isNotEmpty);
    // Built from the typed 100kg target (40% rung = 40kg).
    expect(warmups.first.weight, 40);
  });

  testWidgets('applied warm-ups prepend ahead of the working sets', (
    tester,
  ) async {
    registerRepo(_PrRepo(null));
    await pumpCard(
      tester,
      const WorkoutExercise(
        id: 'ex1',
        exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
        sets: [WorkoutSet(id: 's0', weight: 100, reps: 5)],
      ),
    );

    await _openPlanner(tester);
    // Seeds from the current 100kg working set; just apply the default ladder.
    await tester.tap(find.byKey(const Key('warmupApply')));
    await tester.pumpAndSettle();

    expect(lastUpdate, isNotNull);
    final sets = lastUpdate!.sets;
    // Every warm-up comes before the first working set.
    final firstWorkingIndex = sets.indexWhere(
      (s) => s.setType != SetType.warmup,
    );
    final lastWarmupIndex = sets.lastIndexWhere(
      (s) => s.setType == SetType.warmup,
    );
    expect(lastWarmupIndex, lessThan(firstWorkingIndex));
    // The original working set survives.
    expect(sets.any((s) => s.id == 's0'), isTrue);
  });
}
