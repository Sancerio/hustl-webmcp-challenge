import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/meal_clipboard.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/screens/diary_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records which days the diary asked to load so the test can assert a tap on
/// the date title (then a calendar pick) fires LoadDiary(thatDay).
class _RecordingFoodLogRepository implements FoodLogRepository {
  final List<DateTime> queried = [];

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
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async {
    queried.add(date);
    return const [];
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

class _FakeTargetsRepository implements NutritionTargetsRepository {
  @override
  Future<NutritionTargetPlan?> getCurrentPlan(DateTime date, {bool readOnly = false}) async => null;

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

void main() {
  final getIt = GetIt.instance;
  late _RecordingFoodLogRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MealClipboard.instance.clear();
    repo = _RecordingFoodLogRepository();
    getIt
      ..registerSingleton<FoodLogRepository>(repo)
      ..registerSingleton<NutritionTargetsRepository>(_FakeTargetsRepository())
      ..registerSingleton<PreferencesService>(PreferencesService());
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
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tapping the date title opens a calendar and a pick fires LoadDiary',
    (tester) async {
      await pumpDiary(tester);

      // The diary loads today first.
      final now = DateTime.now();
      expect(repo.queried, isNotEmpty);
      repo.queried.clear();

      // Tap the date title (reads "Today") to open the month calendar.
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);

      // Pick the 15th of the visible month; confirm. (The 15th is unambiguous
      // in the grid and is never the same as the day labels.)
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('15'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // LoadDiary fired for the chosen day (the 15th of the current month).
      final picked = DateTime(now.year, now.month, 15);
      expect(
        repo.queried.any(
          (d) =>
              d.year == picked.year &&
              d.month == picked.month &&
              d.day == picked.day,
        ),
        isTrue,
      );
    },
  );
}
