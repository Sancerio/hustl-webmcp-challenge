import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/data/datasources/body_score_api.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score/this_week_by_region.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

/// End-to-end guard for the codex [P2 + P3s] (PR #385): the in-progress (current)
/// week's 4-week-trend bar must read the SAME DEDUPED set count as the headline
/// "This week, by region" bar - never the raw, compound-inflated figure.
///
/// Scenario: a single compound leg day of 8 Hack-Squat sets (Quads + Glutes,
/// both -> Legs). Deduped Legs physical sets = 8 (under the ~10 target). The OLD
/// raw summed basis would have read 8*1.5 = 12 / 10 (met, emerald) in the trend
/// strip while the headline read 8 / 10 (under, amber) - the bug. Both must now
/// read 8 / 10.
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

WorkoutSession _legDay(int sets, DateTime day) {
  return WorkoutSession(
    id: 'legday-${day.millisecondsSinceEpoch}',
    name: 'Leg day',
    startTime: day,
    endTime: day.add(const Duration(hours: 1)),
    isCompleted: true,
    exercises: [
      WorkoutExercise(
        id: 'hack-squat-${day.millisecondsSinceEpoch}',
        exercise: const Exercise(
          id: 'hack-squat',
          slug: 'hack-squat',
          name: 'Hack Squat',
          muscles: ['Quads', 'Glutes'],
          kind: ExerciseKind.strength,
        ),
        sets: [
          for (var i = 0; i < sets; i++)
            WorkoutSet(
              id: 'set-$i-${day.millisecondsSinceEpoch}',
              weight: 100,
              reps: 10,
              isCompleted: true,
            ),
        ],
      ),
    ],
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
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

  bool hasTooltip(WidgetTester tester, bool Function(String) match) {
    return tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .any((t) => t.message != null && match(t.message!));
  }

  testWidgets(
    'in-progress trend bar reads the deduped 8/10, matching the headline (not raw 12/10)',
    (tester) async {
      final now = DateTime.now();
      final weekStart = startOfWeek(now);
      // Mid-week-ish so the early-week guard does not swallow the verdict; a
      // single compound leg day of 8 sets.
      final sessions = [_legDay(8, weekStart.add(const Duration(days: 3)))];
      getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

      await _pumpScreen(tester);

      // Headline: the current-week IA leads, and the Legs goal bar reads the
      // DEDUPED 8 / 10 sets (under target).
      expect(find.byType(ThisWeekByRegion), findsOneWidget);
      expect(find.text('8 / 10 sets'), findsWidgets);
      // The raw-inflated figure must NOT appear anywhere on the headline.
      expect(find.text('12 / 10 sets'), findsNothing);

      // Expand "Trends & detail" to reveal the 4-week trend strip.
      await tester.tap(find.text('Trends & detail'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Last 4 weeks'), findsOneWidget);

      // The in-progress Legs trend bar tooltip shows the DEDUPED "8 / 10 sets
      // (in progress)" - the SAME basis as the headline - NOT the raw "12 / 10".
      expect(
        hasTooltip(
          tester,
          (m) => m.contains('8 / 10 sets') && m.contains('in progress'),
        ),
        isTrue,
        reason: 'in-progress Legs trend bar must read the deduped 8 / 10',
      );
      expect(
        hasTooltip(tester, (m) => m.contains('12 / 10')),
        isFalse,
        reason: 'the raw, compound-inflated 12 / 10 must never appear',
      );
    },
  );
}
