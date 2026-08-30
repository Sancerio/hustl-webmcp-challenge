import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/nutrition_view_cache.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_entry_sheet.dart';

/// Fake that serves a configurable weight trend and records the logged sample.
/// Only [getWeightTrend] and [addWeightSample] are exercised by the sheet.
class _FakeTargetsRepository implements NutritionTargetsRepository {
  _FakeTargetsRepository({Map<String, dynamic>? trend, this.trendDelay})
    : trend = trend ?? const {'scale': []};

  Map<String, dynamic> trend;
  final Duration? trendDelay;
  DateTime? loggedDate;
  double? loggedKg;

  @override
  Future<Map<String, dynamic>> getWeightTrend(DateTime start, DateTime end) {
    if (trendDelay == null) return Future.value(trend);
    return Future.delayed(trendDelay!, () => trend);
  }

  @override
  Future<void> addWeightSample(DateTime date, double weightKg) async {
    loggedDate = date;
    loggedKg = weightKg;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

String _todayKey() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).toIso8601String().substring(0, 10);
}

Future<void> _openSheet(WidgetTester tester) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => WeightEntrySheet(date: DateTime.now()),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  final getIt = GetIt.instance;

  setUp(() {
    PreferencesService().resetForTests();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    NutritionViewCache.instance.clear();
    await getIt.reset();
  });

  testWidgets('seeds today’s weight instantly from cache, input enabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Cache hit for the default range the trend screen stores.
    NutritionViewCache.instance.set('weight:30', {
      'scale': [
        {'date': _todayKey(), 'weightKg': 80.0, 'source': 'self'},
      ],
    });
    // Network is slow; the seed must not wait for it.
    getIt.registerSingleton<NutritionTargetsRepository>(
      _FakeTargetsRepository(trendDelay: const Duration(seconds: 5)),
    );

    await _openSheet(tester);

    // Big display already shows the cached weight before the network resolves.
    expect(find.text('80.0 kg'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    await tester.pumpAndSettle(const Duration(seconds: 6)); // drain the future
  });

  testWidgets('prefills the latest weight from the network on a cache miss', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    getIt.registerSingleton<NutritionTargetsRepository>(
      _FakeTargetsRepository(
        trend: {
          'scale': [
            {'date': '2026-01-01', 'weightKg': 82.0, 'source': 'self'},
          ],
        },
      ),
    );

    await _openSheet(tester);

    expect(find.text('82.0 kg'), findsOneWidget);
  });

  testWidgets('logs the entered weight and dismisses', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _FakeTargetsRepository();
    getIt.registerSingleton<NutritionTargetsRepository>(repo);

    await _openSheet(tester);

    await tester.enterText(find.byType(TextField), '75.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.loggedKg, closeTo(75.5, 1e-9));
    expect(repo.loggedDate, isNotNull);
    expect(find.byType(WeightEntrySheet), findsNothing); // sheet popped
  });

  testWidgets('renders the saved lb preference and stores canonical kg', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({'weight_unit': 'lb'});

    NutritionViewCache.instance.set('weight:30', {
      'scale': [
        {'date': _todayKey(), 'weightKg': 80.0, 'source': 'self'},
      ],
    });
    final repo = _FakeTargetsRepository();
    getIt.registerSingleton<NutritionTargetsRepository>(repo);

    await _openSheet(tester);

    expect(find.text('176.4 lb'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.loggedKg, closeTo(45.359237, 1e-6));
  });
}
