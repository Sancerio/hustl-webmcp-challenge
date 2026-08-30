import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';
import 'package:hustl_app/features/workout_templates/presentation/screens/template_detail_screen.dart';

import '../../../../test_utils/exercise_repository_fake.dart';
import '../../../../test_utils/template_repository_fake.dart';

/// Minimal GoRouter wrapper so [context.pop()] in the sheet works correctly.
Widget _withRouter(Widget child) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => child,
        routes: [
          GoRoute(
            path: 'workout_session',
            builder: (context, state) => const Scaffold(body: Text('Session')),
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<TemplateRepository>(TemplateRepositoryFake());
    getIt.registerSingleton<ExerciseRepository>(ExerciseRepositoryFake());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('shows template details without starting workout', (
    tester,
  ) async {
    final repo = getIt<TemplateRepository>();
    await repo.createWorkoutTemplate(
      WorkoutTemplate(
        id: 'template-1',
        name: 'Lower Body + Dumbbell Bench Hypertrophy',
        description: 'Main gym day',
        exercises: const [
          {
            'exerciseId': 'Hack Squat',
            'sets': 4,
            'restTimerSeconds': 150,
            'previousSets': [
              {
                'id': 's1',
                'weight': 0,
                'reps': 8,
                'rpe': 7,
                'setType': 'regular',
              },
            ],
          },
        ],
        createdAt: DateTime(2026, 3, 28),
        updatedAt: DateTime(2026, 3, 28),
      ),
    );

    await tester.pumpWidget(
      _withRouter(const TemplateDetailScreen(templateId: 'template-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Lower Body + Dumbbell Bench Hypertrophy'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Main gym day'), findsOneWidget);
    expect(find.text('Hack Squat'), findsOneWidget);
    // Wave G: the flat header now surfaces a "N exercises · M sets" total line
    // in addition to the per-exercise summary, so "4 sets" appears twice.
    expect(find.textContaining('4 sets'), findsAtLeastNWidgets(1));
  });

  testWidgets('direct detail route provides a canonical back path', (
    tester,
  ) async {
    final repo = getIt<TemplateRepository>();
    await repo.createWorkoutTemplate(
      WorkoutTemplate(
        id: 'template-direct',
        name: 'Direct template',
        description: '',
        exercises: const [],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      ),
    );
    final router = GoRouter(
      initialLocation: '/templates/template-direct',
      routes: [
        GoRoute(
          path: '/templates',
          builder: (context, state) => const Scaffold(body: Text('Templates')),
        ),
        GoRoute(
          path: '/templates/:id',
          builder: (context, state) =>
              TemplateDetailScreen(templateId: state.pathParameters['id']!),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/templates');
    expect(find.text('Templates'), findsOneWidget);
  });

  testWidgets('edits and saves per-set exercise prescription', (tester) async {
    final repo = getIt<TemplateRepository>();
    await repo.createWorkoutTemplate(
      WorkoutTemplate(
        id: 'template-2',
        name: 'Upper Body + Posterior Chain Hypertrophy',
        description: 'Best between sport days',
        exercises: const [
          {
            'exerciseId': 'Overhead Press (Dumbbell)',
            'sets': 2,
            'restTimerSeconds': 90,
            'previousSets': [
              {
                'id': 's1',
                'weight': 0,
                'reps': 8,
                'rpe': 8,
                'setType': 'regular',
              },
              {
                'id': 's2',
                'weight': 0,
                'reps': 6,
                'rpe': 9,
                'setType': 'regular',
              },
            ],
          },
        ],
        createdAt: DateTime(2026, 3, 28),
        updatedAt: DateTime(2026, 3, 28),
      ),
    );

    await tester.pumpWidget(
      _withRouter(
        const TemplateDetailScreen(
          templateId: 'template-2',
          startInEditMode: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tapping the exercise row opens its targets editor (the standalone "tune"
    // icon was removed in favour of a tappable row).
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Rest seconds'),
      '120',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Reps').first, '10');
    // Field shows RIR; it persists as RPE = 10 − RIR (RIR 3 → RPE 7).
    await tester.enterText(find.widgetWithText(TextField, 'RIR').first, '3');
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Reps').last, '12');
    await tester.enterText(find.widgetWithText(TextField, 'RIR').last, '2');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save template'));
    await tester.pumpAndSettle();

    final saved = await repo.getWorkoutTemplate('template-2');
    final firstExercise = saved!.exercises.first as Map<String, dynamic>;
    final previousSets = firstExercise['previousSets'] as List<dynamic>;

    expect(firstExercise['sets'], 3);
    expect(firstExercise['restTimerSeconds'], 120);
    expect(previousSets, hasLength(3));
    expect((previousSets.first as Map<String, dynamic>)['reps'], 10);
    expect((previousSets[1] as Map<String, dynamic>)['reps'], 6);
    expect((previousSets.last as Map<String, dynamic>)['reps'], 12);
    // RIR entered in the field is persisted as RPE (10 − RIR).
    expect((previousSets.first as Map<String, dynamic>)['rpe'], 7); // RIR 3
    expect((previousSets.last as Map<String, dynamic>)['rpe'], 8); // RIR 2
  });
}
