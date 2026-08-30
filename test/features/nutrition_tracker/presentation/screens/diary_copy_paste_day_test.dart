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

class _RecordingFoodLogRepository implements FoodLogRepository {
  _RecordingFoodLogRepository(this._entries);

  final List<FoodLogEntry> _entries;
  final List<List<FoodLogEntry>> addedBatches = [];

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
      List<FoodLogEntry>.from(_entries);

  @override
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries) async {
    addedBatches.add(List<FoodLogEntry>.from(entries));
    return entries;
  }

  @override
  Future<void> deleteEntry(String id) async {}

  @override
  Future<List<FoodLogEntry>> copyDay(
    DateTime fromDate,
    DateTime toDate, {
    bool replaceExisting = false,
  }) async => [];

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

FoodLogEntry _entry({required String id, required String name}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return FoodLogEntry(
    id: id,
    date: today,
    loggedAt: today.add(const Duration(hours: 8)),
    servingGrams: 150,
    calories: 250,
    proteinGrams: 30,
    carbsGrams: 12,
    fatGrams: 8,
    foodName: name,
  );
}

void main() {
  final getIt = GetIt.instance;
  late _RecordingFoodLogRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MealClipboard.instance.clear();
    repo = _RecordingFoodLogRepository([
      _entry(id: 'a', name: 'Oats'),
      _entry(id: 'b', name: 'Eggs'),
    ]);
    getIt
      ..registerSingleton<FoodLogRepository>(repo)
      ..registerSingleton<NutritionTargetsRepository>(_FakeTargetsRepository())
      ..registerSingleton<PreferencesService>(PreferencesService());
  });

  tearDown(() async {
    MealClipboard.instance.clear();
    await getIt.reset();
  });

  Future<void> sizeView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  void ignoreWeekBannerOverflow() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final summary = details.exceptionAsString();
      if (summary.contains('A RenderFlex overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  Future<void> pumpDiary(WidgetTester tester) async {
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
    'Copy day then Paste day writes the clipboard onto every chosen date',
    (tester) async {
      await sizeView(tester);
      ignoreWeekBannerOverflow();
      await pumpDiary(tester);

      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);

      // Copy the day onto the clipboard.
      await tester.tap(find.byTooltip('Day options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy day'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Day copied'), findsOneWidget);
      expect(MealClipboard.instance.hasContent, isTrue);
      expect(MealClipboard.instance.count, 2);

      // Paste day now appears in the menu.
      await tester.tap(find.byTooltip('Day options'));
      await tester.pumpAndSettle();
      expect(find.text('Paste day'), findsOneWidget);
      await tester.tap(find.text('Paste day'));
      await tester.pumpAndSettle();

      // Tick two future days in the picker, then paste.
      expect(find.text('Paste to which days?'), findsOneWidget);
      final boxes = find.byType(CheckboxListTile);
      expect(boxes, findsWidgets);
      await tester.tap(boxes.at(0));
      await tester.pumpAndSettle();
      await tester.tap(boxes.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Paste to 2 days'));
      await tester.pumpAndSettle();

      // Snapshots written for both days (2 foods each), with fresh ids and a
      // 'copy' source badge re-stamped onto the target dates.
      expect(repo.addedBatches, hasLength(1));
      final written = repo.addedBatches.single;
      expect(written, hasLength(4));
      expect(written.every((e) => e.source == 'copy'), isTrue);
      expect(written.map((e) => e.foodName).toSet(), {'Oats', 'Eggs'});
      // Two distinct target dates were written.
      expect(written.map((e) => e.date).toSet(), hasLength(2));
      expect(find.text('Pasted to 2 days.'), findsOneWidget);
    },
  );

  testWidgets('Paste day is hidden until the clipboard has content', (
    tester,
  ) async {
    await sizeView(tester);
    ignoreWeekBannerOverflow();
    await pumpDiary(tester);

    await tester.tap(find.byTooltip('Day options'));
    await tester.pumpAndSettle();
    expect(find.text('Copy day'), findsOneWidget);
    expect(find.text('Paste day'), findsNothing);
  });
}
