import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/inactivity_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/workout_logging/domain/utils/superset_grouping.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/active_workout_screen.dart';

class _NoopNotificationService implements NotificationService {

  @override
  Future<void> showAutoLoggedProposal({required String id, required bool isFood, required String body}) async {}


  @override
  Future<void> handleAppLaunchNotification() async {}
  @override
  Future<void> init() async {}

  @override
  Future<void> navigateToActiveWorkout() async {}

  @override
  Future<void> navigateToProposal(String? id) async {}

  @override
  Future<void> showRestComplete({
    String? exerciseName,
    bool isNextSet = false,
    bool skipForegroundBell = false,
  }) async {}

  @override
  Future<void> scheduleRestComplete(
    int seconds, {
    String? exerciseName,
    bool isNextSet = false,
  }) async {}

  @override
  Future<void> cancelRestComplete() async {}

  @override
  Future<void> scheduleInactivityReminder(int seconds) async {}

  @override
  Future<void> cancelInactivityReminder() async {}

  @override
  Future<void> showSyncError(String message) async {}

  @override
  Future<bool> ensurePermissionsForWorkout() async => true;

  @override
  Future<void> showRestOngoing(int seconds, {String? exerciseName}) async {}

  @override
  Future<void> cancelRestOngoing() async {}

  @override
  Future<void> showWorkoutOngoing({
    required DateTime startTime,
    String? currentExerciseName,
  }) async {}

  @override
  Future<void> cancelWorkoutOngoing() async {}

  @override
  Future<bool> isRestCompleteNotificationPending() async => false;

  @override
  Future<void> updateRestLiveActivity(
    int seconds, {
    String? exerciseName,
    bool isPaused = false,
  }) async {}

  @override
  Future<void> endRestLiveActivity() async {}

  @override
  Future<void> scheduleWeeklyCheckIn({
    required int weekday,
    required int hour,
    required int minute,
  }) async {}

  @override
  Future<void> cancelWeeklyCheckIn() async {}

  @override
  Future<bool> isWeeklyCheckInScheduled() async => false;

  @override
  Future<void> scheduleWeeklyTrainingRecap({
    required int weekday,
    required int hour,
    required int minute,
  }) async {}

  @override
  Future<void> cancelWeeklyTrainingRecap() async {}

  @override
  Future<bool> isWeeklyTrainingRecapScheduled() async => false;

  @override
  Future<void> navigateToProgress() async {}

  @override
  Future<void> navigateToNutritionStrategy() async {}
}

WorkoutExercise _grouped({
  required String id,
  required String name,
  required String groupId,
  required int order,
  int setCount = 6,
}) {
  return WorkoutExercise(
    id: id,
    exercise: Exercise(name: name, muscles: const ['chest']),
    sets: List.generate(
      setCount,
      (i) => WorkoutSet(id: '$id-s$i', weight: 40, reps: 8),
    ),
    supersetGroupId: groupId,
    supersetOrder: order,
  );
}

/// A go_router-backed app hosting the active workout screen, so widgets that
/// dismiss sheets via `context.pop` (the project's go_router convention) work.
Widget _routedApp({required String sessionId}) {
  final router = GoRouter(
    initialLocation: '/active',
    routes: [
      GoRoute(
        path: '/active',
        builder: (context, state) => ActiveWorkoutScreen(sessionId: sessionId),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  final getIt = GetIt.instance;
  late MockWorkoutRepository repo;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    getIt.registerSingleton<PreferencesService>(prefs);
    repo = MockWorkoutRepository();
    getIt.registerSingleton<WorkoutRepository>(repo);
    getIt.registerSingleton<NotificationService>(_NoopNotificationService());
    getIt.registerSingleton<RestTimerService>(
      RestTimerService(notificationService: getIt<NotificationService>()),
    );
    getIt.registerFactory<InactivityService>(
      () => InactivityService(
        notificationService: getIt<NotificationService>(),
        preferencesService: getIt<PreferencesService>(),
      ),
    );
  });

  tearDown(() async {
    await getIt.reset(dispose: true);
  });

  Future<WorkoutSession> seedGroupedSession({int setCount = 6}) async {
    final session = WorkoutSession(
      id: 'sess-1',
      name: 'Workout',
      startTime: DateTime.now(),
      exercises: [
        _grouped(
          id: 'a',
          name: 'Bench Press',
          groupId: 'g1',
          order: 0,
          setCount: setCount,
        ),
        _grouped(
          id: 'b',
          name: 'Barbell Row',
          groupId: 'g1',
          order: 1,
          setCount: setCount,
        ),
      ],
    );
    return repo.createWorkoutSession(session);
  }

  testWidgets('grouped members render contiguous A/B round labels in order', (
    tester,
  ) async {
    // Few sets so both member cards fit the test viewport and build eagerly.
    await seedGroupedSession(setCount: 1);

    await tester.pumpWidget(
      const MaterialApp(home: ActiveWorkoutScreen(sessionId: 'sess-1')),
    );
    await tester.pumpAndSettle();

    // Member A round labels and member B round labels both render.
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('B1'), findsOneWidget);
    // The group header chip names the kind.
    expect(find.byKey(const Key('supersetHeaderChip')), findsOneWidget);
    expect(find.text('Superset'), findsWidgets);
  });

  testWidgets(
    'auto-advance scrolls the next member into view on set completion',
    (tester) async {
      await seedGroupedSession();

      await tester.pumpWidget(
        const MaterialApp(home: ActiveWorkoutScreen(sessionId: 'sess-1')),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final beforeOffset = tester
          .widget<Scrollable>(scrollable)
          .controller!
          .offset;

      // Complete A's first set; auto-advance should bring member B into view.
      await tester.tap(find.byTooltip('Mark set 1 as completed').first);
      await tester.pumpAndSettle();

      final afterOffset = tester
          .widget<Scrollable>(scrollable)
          .controller!
          .offset;
      expect(
        afterOffset,
        greaterThan(beforeOffset),
        reason: 'completing A1 should scroll toward member B',
      );
    },
  );

  testWidgets('auto-advance does not scroll when the preference is off', (
    tester,
  ) async {
    await getIt<PreferencesService>().setSupersetAutoAdvance(false);
    await seedGroupedSession();

    await tester.pumpWidget(
      const MaterialApp(home: ActiveWorkoutScreen(sessionId: 'sess-1')),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final beforeOffset = tester
        .widget<Scrollable>(scrollable)
        .controller!
        .offset;

    await tester.tap(find.byTooltip('Mark set 1 as completed').first);
    await tester.pumpAndSettle();

    final afterOffset = tester
        .widget<Scrollable>(scrollable)
        .controller!
        .offset;
    expect(afterOffset, beforeOffset);
  });

  testWidgets(
    'Superset chip groups two ungrouped exercises (shared id, contiguous, '
    'label Superset)',
    (tester) async {
      // Two ungrouped exercises in the session.
      final session = WorkoutSession(
        id: 'sess-1',
        name: 'Workout',
        startTime: DateTime.now(),
        exercises: const [
          WorkoutExercise(
            id: 'a',
            exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
            sets: [WorkoutSet(id: 'a-s0', weight: 40, reps: 8)],
          ),
          WorkoutExercise(
            id: 'b',
            exercise: Exercise(name: 'Barbell Row', muscles: ['back']),
            sets: [WorkoutSet(id: 'b-s0', weight: 40, reps: 8)],
          ),
        ],
      );
      await repo.createWorkoutSession(session);

      await tester.pumpWidget(_routedApp(sessionId: 'sess-1'));
      await tester.pumpAndSettle();

      // Tap the Superset chip on the first (ungrouped) exercise.
      await tester.tap(find.byKey(const ValueKey('chip-superset')).first);
      await tester.pumpAndSettle();

      // Pick the other exercise and confirm.
      await tester.tap(find.byKey(const ValueKey('superset-pick-b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('superset-picker-confirm')));
      await tester.pumpAndSettle();

      // The persisted session now groups both with a shared id, contiguous.
      final updated = await repo.getWorkoutSession('sess-1');
      final exercises = updated!.exercises;
      expect(exercises.map((e) => e.id), ['a', 'b']);
      final groupId = exercises.first.supersetGroupId;
      expect(groupId, isNotNull);
      expect(exercises.every((e) => e.supersetGroupId == groupId), isTrue);
      expect(exercises.map((e) => e.supersetOrder), [0, 1]);

      final groups = SupersetGrouping.groupsFor(exercises);
      expect(groups.single.label, 'Superset');

      // The UI now reflects the group (header chip + round labels).
      expect(find.byKey(const Key('supersetHeaderChip')), findsOneWidget);
      expect(find.text('A1'), findsOneWidget);
      expect(find.text('B1'), findsOneWidget);
    },
  );

  testWidgets(
    'delete + undo restores a 2-member superset (survivor stays grouped)',
    (tester) async {
      // Few sets so both member cards fit the viewport and build eagerly.
      await seedGroupedSession(setCount: 1);

      await tester.pumpWidget(_routedApp(sessionId: 'sess-1'));
      await tester.pumpAndSettle();

      // Sanity: the group is intact before delete.
      final before = await repo.getWorkoutSession('sess-1');
      final beforeGroup = before!.exercises.first.supersetGroupId;
      expect(beforeGroup, isNotNull);
      expect(
        before.exercises.every((e) => e.supersetGroupId == beforeGroup),
        isTrue,
      );

      // Delete member A: more chip -> Remove exercise -> confirm Delete.
      await tester.tap(find.byKey(const ValueKey('chip-more')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove exercise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // After delete the lone survivor dissolves out of the group.
      final afterDelete = await repo.getWorkoutSession('sess-1');
      expect(afterDelete!.exercises.map((e) => e.id), ['b']);
      expect(afterDelete.exercises.single.supersetGroupId, isNull);

      // Undo: the full prior list is restored, group intact.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      final restored = await repo.getWorkoutSession('sess-1');
      final exercises = restored!.exercises;
      expect(exercises.map((e) => e.id), ['a', 'b']);
      final groupId = exercises.first.supersetGroupId;
      expect(groupId, isNotNull);
      expect(
        exercises.every((e) => e.supersetGroupId == groupId),
        isTrue,
        reason: 'the survivor must rejoin the restored superset',
      );
      expect(exercises.map((e) => e.supersetOrder), [0, 1]);
    },
  );

  testWidgets(
    'helper buckets two shared-id exercises into one Superset group',
    (tester) async {
      final exercises = [
        _grouped(id: 'a', name: 'Bench', groupId: 'g1', order: 0),
        _grouped(id: 'b', name: 'Row', groupId: 'g1', order: 1),
      ];
      final groups = SupersetGrouping.groupsFor(exercises);
      expect(groups, hasLength(1));
      expect(groups.single.members.map((e) => e.id), ['a', 'b']);
      expect(groups.single.label, 'Superset');

      // A third shared-id member promotes the label to Giant set.
      final giant = [
        ...exercises,
        _grouped(id: 'c', name: 'Curl', groupId: 'g1', order: 2),
      ];
      expect(SupersetGrouping.groupsFor(giant).single.label, 'Giant set');
    },
  );
}
