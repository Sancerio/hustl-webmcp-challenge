import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/data/datasources/body_score_api.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score/this_week_by_region.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score_radar.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _BodyScoreApiStub implements BodyScoreApi {
  const _BodyScoreApiStub();
  @override
  Future<BodyScoreSummary?> fetchLatest({int windowDays = 28}) async => null;
}

class _Repo implements WorkoutRepository {
  final List<WorkoutSession> sessions;
  _Repo(this.sessions);
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => sessions;
  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One completed set on [muscle], logged [setCount] times, at [day] this week.
WorkoutSession _session(String muscle, int setCount, DateTime day) {
  return WorkoutSession(
    id: 'session-$muscle-${day.millisecondsSinceEpoch}',
    name: '$muscle day',
    startTime: day,
    endTime: day.add(const Duration(hours: 1)),
    isCompleted: true,
    exercises: [
      WorkoutExercise(
        id: 'ex-$muscle',
        exercise: Exercise(name: '$muscle move', muscles: [muscle]),
        sets: [
          for (var i = 0; i < setCount; i++)
            WorkoutSet(
              id: 'set-$muscle-$i',
              weight: 100,
              reps: 8,
              isCompleted: true,
            ),
        ],
      ),
    ],
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
  // A tall surface so the whole screen lays out without scrolling - the radar's
  // looping entrance animation means pumpAndSettle would never return, so the
  // test drives discrete pumps and finders match offstage-built widgets too.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: BodyScoreScreen()));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final getIt = GetIt.instance;

  void resetGetIt() {
    if (getIt.isRegistered<WorkoutRepository>()) {
      getIt.unregister<WorkoutRepository>();
    }
    if (getIt.isRegistered<PreferencesService>()) {
      getIt.unregister<PreferencesService>();
    }
    if (getIt.isRegistered<BodyScoreApi>()) {
      getIt.unregister<BodyScoreApi>();
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetGetIt();
    getIt.registerSingleton<PreferencesService>(PreferencesService());
    getIt.registerSingleton<BodyScoreApi>(const _BodyScoreApiStub());
  });

  tearDown(resetGetIt);

  testWidgets(
    'current week leads with the This-week-by-region IA, demoting the radar',
    (tester) async {
      final now = DateTime.now();
      final weekStart = startOfWeek(now);
      // Seed mid-week so the early-week guard does not fire: core met (10),
      // legs behind (3), back behind (0, implicitly), several sessions.
      final sessions = [
        _session('Abs', 5, weekStart.add(const Duration(days: 1))),
        _session('Obliques', 5, weekStart.add(const Duration(days: 1))),
        _session('Quads', 3, weekStart.add(const Duration(days: 2))),
        _session('Chest', 8, weekStart.add(const Duration(days: 3))),
        _session('Lats', 6, weekStart.add(const Duration(days: 3))),
      ];
      getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

      await _pumpScreen(tester);

      // The IA is the headline.
      expect(find.byType(ThisWeekByRegion), findsOneWidget);
      expect(find.text('This week, by region'), findsOneWidget);
      expect(find.textContaining('day '), findsWidgets); // header strip
      expect(find.text('Do next'), findsOneWidget);

      // The radar is DEMOTED - not shown until "Trends & detail" is expanded.
      expect(find.byType(BodyScoreRadar), findsNothing);
      expect(find.text('Trends & detail'), findsOneWidget);

      // Expand the collapsible -> the radar (and the demoted evenness card)
      // appear. Discrete pumps, not pumpAndSettle, because the radar animates.
      await tester.tap(find.text('Trends & detail'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(BodyScoreRadar), findsOneWidget);
      expect(find.text('Evenness'), findsOneWidget);
      expect(find.text('Last 4 weeks'), findsOneWidget);
    },
  );
}
