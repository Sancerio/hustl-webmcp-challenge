import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/food_log_csv_export_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/weight_history_csv_export_service.dart';
import 'package:hustl_app/features/settings/presentation/screens/data_import_export_screen.dart';

class _FakeFoodLogRepository implements FoodLogRepository {
  int rangeCalls = 0;

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) async {
    rangeCalls += 1;
    // History in the most recent window only, then empty older windows so the
    // export's backwards walk terminates.
    if (rangeCalls > 1) return const [];
    return [
      FoodLogEntry(
        id: 'log-1',
        date: DateTime(2026, 7, 1),
        loggedAt: DateTime(2026, 7, 1, 8, 30),
        servingGrams: 80,
        calories: 300,
        proteinGrams: 10,
        carbsGrams: 50,
        fatGrams: 6,
        foodName: 'Oats',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeNutritionTargetsRepository implements NutritionTargetsRepository {
  @override
  Future<Map<String, dynamic>> getWeightTrend(DateTime start, DateTime end) async => {
    'scale': [
      {'date': '2026-07-01', 'weightKg': 80.0, 'source': 'self'},
    ],
    'trend': [
      {'date': '2026-07-01', 'trendKg': 80.1},
    ],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final getIt = GetIt.instance;
  late _FakeFoodLogRepository foodLogRepo;
  final captured = <({String fileName, String csvText})>[];

  setUp(() {
    foodLogRepo = _FakeFoodLogRepository();
    getIt.registerSingleton<FoodLogRepository>(foodLogRepo);
    getIt.registerSingleton<NutritionTargetsRepository>(
      _FakeNutritionTargetsRepository(),
    );
    captured.clear();
    DataImportExportScreen.debugCsvShareOverride =
        ({required String fileName, required String csvText}) async {
          captured.add((fileName: fileName, csvText: csvText));
        };
  });

  tearDown(() async {
    DataImportExportScreen.debugCsvShareOverride = null;
    await getIt.reset();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const DataImportExportScreen(),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  testWidgets('renders the nutrition and weight export rows', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Export nutrition (CSV)'), findsOneWidget);
    expect(find.text('Export weight history (CSV)'), findsOneWidget);
    // The pre-existing rows are untouched.
    expect(find.text('Export workouts (CSV)'), findsOneWidget);
    expect(find.text('Import from Strong'), findsOneWidget);
  });

  testWidgets('tapping Export nutrition produces a CSV with the documented header', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Export nutrition (CSV)'));
    await tester.pump(); // handler starts; progress dialog route pushes
    await tester.pump(const Duration(milliseconds: 400)); // dialog pops
    await tester.pump(const Duration(milliseconds: 400)); // snack settles

    expect(captured, hasLength(1));
    expect(captured.single.fileName, startsWith('hustl-nutrition-'));
    final lines = captured.single.csvText.split('\n');
    expect(lines.first, FoodLogCsvExportService.header.join(','));
    expect(lines[1], contains('Oats'));
    // The loader walked at least the most recent window and one empty one.
    expect(foodLogRepo.rangeCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('tapping Export weight history produces a CSV with the documented header', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Export weight history (CSV)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(captured, hasLength(1));
    expect(captured.single.fileName, startsWith('hustl-weight-'));
    final lines = captured.single.csvText.split('\n');
    expect(lines.first, WeightHistoryCsvExportService.header.join(','));
    expect(lines[1], '2026-07-01,80,80.1,self');
  });
}
