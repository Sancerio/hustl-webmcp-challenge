import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';
import 'package:hustl_app/features/workout_templates/presentation/screens/templates_screen.dart';
import 'package:hustl_app/features/workout_templates/presentation/widgets/template_card.dart';

import '../../../../test_utils/template_repository_fake.dart';

/// Router wrapping the templates list with the detail/session destinations the
/// screen pushes to, so a row tap can be asserted by the landing screen.
({Widget app, GoRouter router}) _withRouter({
  bool reflectDetailRouteInBrowser = false,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TemplatesScreen(
          reflectDetailRouteInBrowser: reflectDetailRouteInBrowser,
        ),
        routes: [
          GoRoute(
            path: 'templates/:id',
            builder: (context, state) =>
                Scaffold(body: Text('Detail ${state.pathParameters['id']}')),
          ),
          GoRoute(
            path: 'workout_session',
            builder: (context, state) => const Scaffold(body: Text('Session')),
          ),
        ],
      ),
    ],
  );
  return (app: MaterialApp.router(routerConfig: router), router: router);
}

WorkoutTemplate _template({
  String id = 'template-1',
  String name = 'Push day',
  String description = 'Chest, shoulders, triceps',
}) {
  return WorkoutTemplate(
    id: id,
    name: name,
    description: description,
    exercises: const [
      {'exerciseId': 'Bench Press', 'sets': 4},
      {'exerciseId': 'Overhead Press', 'sets': 3},
    ],
    createdAt: DateTime(2026, 3, 28),
    updatedAt: DateTime(2026, 3, 28),
  );
}

/// Fails every load so the screen's catch block fires — used to assert the
/// plain-language error copy replaces the raw exception (plan 016).
class _ThrowingTemplateRepository implements TemplateRepository {
  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async {
    throw Exception('Simulated network failure');
  }

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async => null;

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(
    WorkoutTemplate template,
  ) async => template;

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(
    WorkoutTemplate template,
  ) async => template;

  @override
  Future<void> deleteWorkoutTemplate(String id) async {}
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<TemplateRepository>(TemplateRepositoryFake());
    StaggeredEntrance.resetForTest();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('renders a premium template row: name, meta, glyph, overflow', (
    tester,
  ) async {
    await getIt<TemplateRepository>().createWorkoutTemplate(_template());

    await tester.pumpWidget(_withRouter().app);
    await tester.pumpAndSettle();

    // The grouped card row exists as a TemplateCard.
    expect(find.byType(TemplateCard), findsOneWidget);

    // Name (sentence-case) and the muted description subtitle.
    expect(find.text('Push day'), findsOneWidget);
    expect(find.text('Chest, shoulders, triceps'), findsOneWidget);

    // A clean meta line: 2 exercises (Bench + Overhead) and 7 sets (4 + 3).
    // The numerals render as tabular spans inside one rich-text run.
    expect(find.textContaining('2 exercises'), findsOneWidget);
    expect(find.textContaining('7 sets'), findsOneWidget);

    // The tasteful leading dumbbell glyph holder.
    expect(
      find.descendant(
        of: find.byType(TemplateCard),
        matching: find.byType(HustlIcon),
      ),
      findsOneWidget,
    );
    expect(find.byType(SvgPicture), findsWidgets);

    // The kept per-row overflow (⋮) menu.
    expect(find.byTooltip('Template actions'), findsOneWidget);
  });

  testWidgets('tapping a row navigates to the template detail', (tester) async {
    await getIt<TemplateRepository>().createWorkoutTemplate(_template());

    final harness = _withRouter(reflectDetailRouteInBrowser: true);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push day'));
    await tester.pumpAndSettle();

    expect(find.text('Detail template-1'), findsOneWidget);
    expect(
      harness.router.routeInformationProvider.value.uri.path,
      '/templates/template-1',
    );
  });

  testWidgets('overflow menu exposes the kept template actions', (
    tester,
  ) async {
    await getIt<TemplateRepository>().createWorkoutTemplate(_template());

    await tester.pumpWidget(_withRouter().app);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Template actions'));
    await tester.pumpAndSettle();

    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('empty state shows the build-your-first-routine prompt', (
    tester,
  ) async {
    await tester.pumpWidget(_withRouter().app);
    await tester.pumpAndSettle();

    expect(find.byType(ScreenEmptyState), findsOneWidget);
    expect(find.text('Build your first routine'), findsOneWidget);
    expect(find.byType(TemplateCard), findsNothing);
  });

  testWidgets(
    'a failed load shows plain-language error copy, never the raw exception',
    (tester) async {
      await getIt.reset();
      getIt.registerSingleton<TemplateRepository>(
        _ThrowingTemplateRepository(),
      );
      StaggeredEntrance.resetForTest();

      await tester.pumpWidget(_withRouter().app);
      await tester.pumpAndSettle();

      expect(
        find.text(
          "We couldn't load your templates. Pull to refresh or try again.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
    },
  );
}
