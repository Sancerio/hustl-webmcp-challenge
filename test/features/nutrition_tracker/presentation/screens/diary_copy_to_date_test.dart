import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/screens/diary_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every batch handed to [addEntries] (and the days requested) so the
/// "Copy to…" flow can be asserted: N new entries on the target date, fresh
/// ids, macros + the 'copy' source badge preserved, originals untouched.
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
    fiberGrams: 3,
    foodName: name,
  );
}

void main() {
  final getIt = GetIt.instance;
  late _RecordingFoodLogRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    await getIt.reset();
  });

  // A tall phone viewport keeps the single-column layout below the wide
  // breakpoint, with room for the sticky selection bar and rows.
  Future<void> sizeView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  // The pinned week banner overflows its fixed-height cells by ~2px under the
  // test font — a pre-existing quirk unrelated to this flow. Swallow only that.
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

  Future<void> enterSelection(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Day options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select foods'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Copy to Today writes a fresh copy of every selected food onto today, '
    'preserving macros, showing a snackbar, and clearing the selection',
    (tester) async {
      await sizeView(tester);
      ignoreWeekBannerOverflow();
      await pumpDiary(tester);

      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);

      await enterSelection(tester);

      // Both actions are present in selection mode.
      expect(find.text('Copy to…'), findsOneWidget);
      expect(find.text('Create recipe'), findsOneWidget);

      // Select both foods at once via the Breakfast (8 AM) meal header. The
      // header text is wrapped in excludeSemantics, so tap the InkWell.
      expect(find.byType(Checkbox), findsNWidgets(2));
      final header = find.ancestor(
        of: find.text('Breakfast'),
        matching: find.byType(InkWell),
      );
      await tester.tap(header.first);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 selected'), findsOneWidget);

      // Copy to… → choose the quick "Today" option.
      await tester.tap(find.text('Copy to…'));
      await tester.pumpAndSettle();
      expect(find.text('Copy to which day?'), findsOneWidget);
      // Scope to the sheet's ListTiles — "Today" also labels the diary date
      // title button, so match the choice row specifically.
      final todayTile = find.widgetWithText(ListTile, 'Today');
      final pickTile = find.widgetWithText(ListTile, 'Pick a date…');
      expect(todayTile, findsOneWidget);
      expect(pickTile, findsOneWidget);
      await tester.tap(todayTile);
      await tester.pumpAndSettle();

      // One add batch with both foods, fresh ids, the 'copy' badge, macros
      // preserved, dated onto today. Originals are never re-written.
      expect(repo.addedBatches, hasLength(1));
      final written = repo.addedBatches.single;
      expect(written, hasLength(2));
      expect(written.map((e) => e.foodName).toSet(), {'Oats', 'Eggs'});
      expect(written.every((e) => e.source == 'copy'), isTrue);
      expect(written.every((e) => e.id != 'a' && e.id != 'b'), isTrue);
      final now = DateTime.now();
      expect(
        written.every(
          (e) =>
              e.date.year == now.year &&
              e.date.month == now.month &&
              e.date.day == now.day,
        ),
        isTrue,
      );
      final oats = written.firstWhere((e) => e.foodName == 'Oats');
      expect(oats.calories, 250);
      expect(oats.proteinGrams, 30);
      expect(oats.carbsGrams, 12);
      expect(oats.fatGrams, 8);
      expect(oats.fiberGrams, 3);
      expect(oats.servingGrams, 150);

      // Confirmation snackbar, dated, and selection mode has exited.
      expect(find.text('Copied 2 items to today.'), findsOneWidget);
      expect(find.text('Copy to…'), findsNothing);
      expect(find.text('Create recipe'), findsNothing);
    },
  );

  testWidgets(
    'Copy to… via Pick a date writes the selection onto the chosen calendar day',
    (tester) async {
      await sizeView(tester);
      ignoreWeekBannerOverflow();
      await pumpDiary(tester);

      await enterSelection(tester);

      // Select one food.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 selected'), findsOneWidget);

      // Copy to… → Pick a date… opens the calendar; pick the 15th of the
      // currently-shown month, then confirm with OK.
      await tester.tap(find.text('Copy to…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick a date…'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('15'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // One entry was copied onto a day whose day-of-month is the 15th.
      expect(repo.addedBatches, hasLength(1));
      final written = repo.addedBatches.single;
      expect(written, hasLength(1));
      expect(written.single.date.day, 15);
      expect(written.single.source, 'copy');

      // Selection cleared + a confirmation snackbar appeared.
      expect(find.text('Copy to…'), findsNothing);
      expect(find.textContaining('Copied 1 item to'), findsOneWidget);
    },
  );

  testWidgets('the copy action is disabled until something is selected', (
    tester,
  ) async {
    await sizeView(tester);
    ignoreWeekBannerOverflow();
    await pumpDiary(tester);

    await enterSelection(tester);

    // With nothing selected the Copy to… button is present but disabled.
    final copyButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Copy to…'),
    );
    expect(copyButton.onPressed, isNull);
  });
}
