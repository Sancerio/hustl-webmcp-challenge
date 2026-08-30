import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/onboarding/domain/import_summary.dart';
import 'package:hustl_app/features/onboarding/domain/workout_import_runner.dart';
import 'package:hustl_app/features/onboarding/presentation/import/onboarding_import_preview_screen.dart';
import 'package:hustl_app/features/onboarding/presentation/import/onboarding_import_restored_screen.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

/// A repository whose every call throws — used to drive the preview's import
/// failure path (the [WorkoutImportRunner] resolves it from GetIt).
class _ThrowingWorkoutRepo implements WorkoutRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _summary = ImportSummary(
  workouts: 142,
  exercises: 37,
  totalSets: 1840,
  totalVolumeKg: 284000,
  firstDate: DateTime(2023, 1, 15),
  lastDate: DateTime(2025, 12, 2),
);

WorkoutSession _session(String name, DateTime start, int exercises) {
  return WorkoutSession(
    id: name,
    name: name,
    startTime: start,
    exercises: [
      for (var i = 0; i < exercises; i++)
        WorkoutExercise(
          id: '$name-$i',
          exercise: Exercise(name: 'Exercise $i', muscles: const []),
          sets: const [],
        ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preview renders the real summary numbers', (tester) async {
    // Ascending order, as produced by StrongCsvImportService.parse.
    final sessions = [
      _session('Push Day', DateTime(2025, 11, 28), 7),
      _session('Lower Body A', DateTime(2025, 11, 30), 5),
      _session('Upper Body B', DateTime(2025, 12, 2), 6),
    ];

    await _pump(
      tester,
      OnboardingImportPreviewScreen(sessions: sessions, summary: _summary),
    );

    expect(find.text('142 workouts ready to restore'), findsOneWidget);
    expect(find.textContaining('37 exercises · 1840 sets'), findsOneWidget);
    expect(find.textContaining('since Jan 2023'), findsOneWidget);
    // Most-recent-first preview rows come from the real sessions.
    expect(find.text('Upper Body B'), findsOneWidget);
    expect(find.text('+ 139 more workouts'), findsOneWidget);
    expect(find.text('Import 142 workouts'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('restored renders the real outcome + summary stats', (
    tester,
  ) async {
    await _pump(
      tester,
      OnboardingImportRestoredScreen(
        outcome: const ImportOutcome(imported: 142, replaced: 0),
        summary: _summary,
      ),
    );

    expect(
      find.textContaining('142 workouts imported from Strong'),
      findsOneWidget,
    );
    // Real stat tiles — no mock placeholders.
    expect(find.text('142'), findsOneWidget); // workouts tile
    expect(find.text('37'), findsOneWidget); // exercises tile
    expect(find.text('284 t'), findsOneWidget); // tonnes tile
    expect(
      find.textContaining('Your full history since Jan 2023'),
      findsOneWidget,
    );
    expect(find.text('Take me to Hustl'), findsOneWidget);
  });

  testWidgets('preview recovers when the import write fails', (tester) async {
    // The runner resolves its WorkoutRepository from GetIt; a throwing repo makes
    // run() fail so we can assert the screen recovers instead of stranding the CTA.
    if (GetIt.instance.isRegistered<WorkoutRepository>()) {
      await GetIt.instance.reset();
    }
    GetIt.instance.registerSingleton<WorkoutRepository>(_ThrowingWorkoutRepo());
    addTearDown(GetIt.instance.reset);

    final sessions = [_session('Push Day', DateTime(2025, 11, 28), 7)];
    await _pump(
      tester,
      OnboardingImportPreviewScreen(sessions: sessions, summary: _summary),
    );

    await tester.tap(find.text('Import 142 workouts'));
    await tester.pumpAndSettle();

    // The failed write must: clear progress, re-enable the CTA, and surface a
    // recoverable message — never an uncaught error + permanently-disabled CTA.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import 142 workouts'),
    );
    expect(button.onPressed, isNotNull);
    expect(find.textContaining("Couldn't import your history"), findsOneWidget);
  });

  testWidgets('restored reflects replaced count in its headline', (
    tester,
  ) async {
    await _pump(
      tester,
      OnboardingImportRestoredScreen(
        outcome: const ImportOutcome(imported: 142, replaced: 12),
        summary: _summary,
      ),
    );

    expect(find.textContaining('12 updated in place'), findsOneWidget);
  });
}
