import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/meal_clipboard.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/screens/diary_screen.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/nutrition_inline_states.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A food-log repo whose initial fetch is held open by a [Completer] so the test
/// can pump a frame while the diary's first load is still in flight, assert what
/// renders, then resolve the fetch and assert what it settles into.
class _PendingFoodLogRepository implements FoodLogRepository {
  _PendingFoodLogRepository();

  final Completer<List<FoodLogEntry>> logs = Completer<List<FoodLogEntry>>();
  bool _queried = false;

  @override
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async => const FoodSuggestions();

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) =>
      throw UnimplementedError();

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) {
    // Only the first (initial) load is held pending; any later reloads resolve
    // immediately so the test never deadlocks on a settle.
    if (_queried) return Future.value(const []);
    _queried = true;
    return logs.future;
  }

  @override
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries) async =>
      entries;

  @override
  Future<void> deleteEntry(String id) async {}

  @override
  Future<List<FoodLogEntry>> copyDay(
    DateTime fromDate,
    DateTime toDate, {
    bool replaceExisting = false,
  }) async => const [];

  @override
  Future<FoodLogEntry> updateEntry(
    String id,
    Map<String, dynamic> patch,
  ) async => throw UnimplementedError();
}

/// A food-log repo whose initial fetch fails, to drive the error branch.
class _FailingFoodLogRepository implements FoodLogRepository {
  @override
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async => const FoodSuggestions();

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) =>
      throw UnimplementedError();

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async =>
      throw Exception('network down');

  @override
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries) async =>
      entries;

  @override
  Future<void> deleteEntry(String id) async {}

  @override
  Future<List<FoodLogEntry>> copyDay(
    DateTime fromDate,
    DateTime toDate, {
    bool replaceExisting = false,
  }) async => const [];

  @override
  Future<FoodLogEntry> updateEntry(
    String id,
    Map<String, dynamic> patch,
  ) async => throw UnimplementedError();
}

class _FakeTargetsRepository implements NutritionTargetsRepository {
  _FakeTargetsRepository({this.plan});

  /// Returned by [getCurrentPlan]. Null models a user who never set targets.
  final NutritionTargetPlan? plan;

  @override
  Future<NutritionTargetPlan?> getCurrentPlan(DateTime date, {bool readOnly = false}) async => plan;

  @override
  Future<Map<String, dynamic>> getInsights(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async => const {};

  @override
  Future<String?> getCoachExplains(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async => null;

  @override
  Future<Map<String, dynamic>> getWeightTrend(
    DateTime start,
    DateTime end,
  ) async => const {};

  @override
  Future<void> addWeightSample(DateTime date, double weightKg) async {}

  @override
  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date) async =>
      const {};

  @override
  Future<NutritionTargetPlan?> applyWeeklyCheckIn(DateTime date) async => null;

  @override
  Future<void> skipWeeklyCheckIn(DateTime date) async {}

  @override
  Future<NutritionTargetPlan?> recalculatePlan(
    DateTime date, {
    String? mode,
    String? goal,
    double? ratePerWeek,
    Map<String, dynamic>? profile,
  }) async => null;

  @override
  Future<NutritionTargetPlan?> updatePlan(
    DateTime weekStart,
    Map<String, dynamic> patch,
  ) async => null;
}

NutritionTargetPlan _plan() => NutritionTargetPlan(
  weekStart: DateTime.now(),
  mode: 'auto',
  goal: 'maintain',
  caloriesTarget: 2200,
  proteinTarget: 165,
  carbsTarget: 220,
  fatTarget: 70,
);

FoodLogEntry _entry() => FoodLogEntry(
  id: 'e1',
  date: DateTime.now(),
  loggedAt: DateTime.now(),
  servingGrams: 120,
  calories: 250,
  proteinGrams: 20,
  carbsGrams: 30,
  fatGrams: 6,
  foodName: 'Oatmeal',
);

/// Matches the first-run setup card's headline (curly apostrophe agnostic).
final _setupCopy = find.textContaining('set up your nutrition');

void main() {
  final getIt = GetIt.instance;

  void registerRepos({
    required FoodLogRepository logs,
    required NutritionTargetsRepository targets,
  }) {
    getIt
      ..registerSingleton<FoodLogRepository>(logs)
      ..registerSingleton<NutritionTargetsRepository>(targets)
      ..registerSingleton<PreferencesService>(PreferencesService());
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MealClipboard.instance.clear();
  });

  tearDown(() async {
    MealClipboard.instance.clear();
    await getIt.reset();
  });

  Future<void> pumpDiary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: DiaryScreen()),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets(
    'while the first fetch is in flight: shows the loading skeleton, NOT the '
    'setup prompt',
    (tester) async {
      final logs = _PendingFoodLogRepository();
      registerRepos(logs: logs, targets: _FakeTargetsRepository(plan: null));

      await pumpDiary(tester);
      // One frame: LoadDiary has been dispatched and isLoading is true, but the
      // fetch future is still pending (not completed).
      await tester.pump();

      expect(
        find.byType(AppSkeleton),
        findsWidgets,
        reason: 'the initial load should render a skeleton',
      );
      expect(
        _setupCopy,
        findsNothing,
        reason: 'the setup prompt must not flash before the fetch resolves',
      );

      // Resolve so the bloc/futures settle and the test tears down cleanly.
      logs.logs.complete(const []);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a returning user with data: skeleton then their diary, never the setup '
    'prompt',
    (tester) async {
      final logs = _PendingFoodLogRepository();
      registerRepos(
        logs: logs,
        targets: _FakeTargetsRepository(plan: _plan()),
      );

      await pumpDiary(tester);
      await tester.pump();

      // Mid-flight: skeleton, no setup copy.
      expect(find.byType(AppSkeleton), findsWidgets);
      expect(_setupCopy, findsNothing);

      // Data arrives.
      logs.logs.complete([_entry()]);
      await tester.pumpAndSettle();

      // The diary log resolved to the user's data -- never the setup prompt.
      expect(_setupCopy, findsNothing);
      expect(find.text('Oatmeal'), findsOneWidget);
    },
  );

  testWidgets(
    'a genuinely new user: skeleton then the setup prompt once the fetch '
    'resolves empty',
    (tester) async {
      final logs = _PendingFoodLogRepository();
      registerRepos(logs: logs, targets: _FakeTargetsRepository(plan: null));

      await pumpDiary(tester);
      await tester.pump();

      // Mid-flight: skeleton, no setup copy yet.
      expect(find.byType(AppSkeleton), findsWidgets);
      expect(_setupCopy, findsNothing);

      // Empty data resolves: this is a real first-run user.
      logs.logs.complete(const []);
      await tester.pumpAndSettle();

      expect(
        _setupCopy,
        findsOneWidget,
        reason: 'an empty diary after the fetch resolves IS the first-run case',
      );
    },
  );

  testWidgets(
    'a fetch error shows a retry, NOT the setup prompt',
    (tester) async {
      registerRepos(
        logs: _FailingFoodLogRepository(),
        targets: _FakeTargetsRepository(plan: null),
      );

      await pumpDiary(tester);
      await tester.pumpAndSettle();

      expect(
        _setupCopy,
        findsNothing,
        reason: 'a load error must not be mistaken for a brand-new diary',
      );

      // The inline error + retry live below the empty-diary fold; scroll it
      // into view, then assert the retry affordance is present.
      await tester.scrollUntilVisible(
        find.byType(NutritionInlineError),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.byType(NutritionInlineError), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    },
  );
}
