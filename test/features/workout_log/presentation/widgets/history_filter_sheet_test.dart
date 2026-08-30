import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/history/history_filter_sheet.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    if (GetIt.instance.isRegistered<PreferencesService>()) {
      GetIt.instance.unregister<PreferencesService>();
    }
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.instance.registerSingleton<PreferencesService>(prefs);
  });

  testWidgets('history filter sheet returns selected region and range', (
    tester,
  ) async {
    HistoryFilterResult? result;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showHistoryFilterSheet(
                    context,
                    selectedGroups: const {},
                    selectedRangeDays: null,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The sheet shows region + range chips (no nested ExpansionTile/checkboxes).
    expect(find.byType(AppChip), findsWidgets);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Chest'), findsOneWidget);

    await tester.tap(find.text('Chest'));
    await tester.pump();
    await tester.tap(find.text('28 days'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.rangeDays, 28);
    final chestGroups = MuscleGroup.values
        .where((g) => g.displayRegion == DisplayRegion.chest)
        .toSet();
    expect(result!.muscleGroups, containsAll(chestGroups));
  });
}
