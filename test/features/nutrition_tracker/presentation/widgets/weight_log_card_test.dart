import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_log_card.dart';

class _FakeNutritionTargetsRepository implements NutritionTargetsRepository {
  _FakeNutritionTargetsRepository(this.weightTrend);

  final Map<String, dynamic> weightTrend;

  @override
  Future<Map<String, dynamic>> getWeightTrend(
    DateTime start,
    DateTime end,
  ) async {
    return weightTrend;
  }

  @override
  Future<NutritionTargetPlan?> getCurrentPlan(
    DateTime date, {
    bool readOnly = false,
  }) async => null;

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

  @override
  Future<void> addWeightSample(DateTime date, double weightKg) async {}

  @override
  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart) async =>
      {};

  @override
  Future<Map<String, dynamic>> getInsights(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async => {};

  @override
  Future<String?> getCoachExplains(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async => null;

  @override
  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date) async => {};

  @override
  Future<NutritionTargetPlan?> applyWeeklyCheckIn(DateTime date) async => null;

  @override
  Future<void> skipWeeklyCheckIn(DateTime date) async {}
}

void main() {
  final getIt = GetIt.instance;

  setUp(() {
    PreferencesService().resetForTests();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('shows Override today when the latest weight is synced', (
    tester,
  ) async {
    getIt.registerLazySingleton<NutritionTargetsRepository>(
      () => _FakeNutritionTargetsRepository({
        'scale': [
          {'date': '2024-06-10', 'weightKg': 80.0, 'source': 'apple_health'},
        ],
        'trend': const [],
        'hasWeightToday': true,
        'latest': {
          'date': '2024-06-10',
          'weightKg': 80.0,
          'source': 'apple_health',
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeightLogCard(isSignedIn: true, now: DateTime(2024, 6, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Override today'), findsOneWidget);
  });

  testWidgets('shows Edit today when the latest weight is manual', (
    tester,
  ) async {
    getIt.registerLazySingleton<NutritionTargetsRepository>(
      () => _FakeNutritionTargetsRepository({
        'scale': [
          {'date': '2024-06-10', 'weightKg': 80.0, 'source': 'self'},
        ],
        'trend': const [],
        'hasWeightToday': true,
        'latest': {'date': '2024-06-10', 'weightKg': 80.0, 'source': 'self'},
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeightLogCard(isSignedIn: true, now: DateTime(2024, 6, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit today'), findsOneWidget);
  });

  testWidgets('formats the latest weight in the saved lb unit', (tester) async {
    SharedPreferences.setMockInitialValues({'weight_unit': 'lb'});

    getIt.registerLazySingleton<NutritionTargetsRepository>(
      () => _FakeNutritionTargetsRepository({
        'scale': [
          {'date': '2024-06-10', 'weightKg': 80.0, 'source': 'self'},
        ],
        'trend': const [],
        'hasWeightToday': true,
        'latest': {'date': '2024-06-10', 'weightKg': 80.0, 'source': 'self'},
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeightLogCard(isSignedIn: true, now: DateTime(2024, 6, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('176.4 lb'), findsOneWidget);
    expect(find.textContaining('kg'), findsNothing);
  });
}
