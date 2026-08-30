import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_edit_screen.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

/// Minimal repo fake that just serves a single session for read.
class _EditRepoFake implements WorkoutRepository {
  _EditRepoFake(this.session);

  WorkoutSession session;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => session;

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession updated, {
    bool markDirty = true,
  }) async {
    session = updated;
    return session;
  }

  @override
  Future<void> recomputeAllPrFlags() async {}

  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;

  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) => Future.error(UnimplementedError());

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) => Future.error(UnimplementedError());

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) =>
      Future.error(UnimplementedError());

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) =>
      Future.error(UnimplementedError());

  @override
  Future<void> deleteWorkoutSession(String id) =>
      Future.error(UnimplementedError());

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) => Future.error(UnimplementedError());

  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) => Future.error(UnimplementedError());

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) => Future.error(UnimplementedError());

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) => Future.error(UnimplementedError());

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

/// Helper: a card-like surface container that holds [matching]. The Wave I flat
/// group cards are `Container`s with a `BoxDecoration` colour fill and no
/// border — this matches a [Container] whose decoration is a [BoxDecoration].
Finder _flatCardAround(Finder matching) {
  return find.ancestor(
    of: matching,
    matching: find.byWidgetPredicate(
      (w) => w is Container && w.decoration is BoxDecoration,
    ),
  );
}

WorkoutSession _session({List<WorkoutExercise> exercises = const []}) {
  return WorkoutSession(
    id: 's1',
    name: 'Original',
    startTime: DateTime(2024, 8, 1, 9, 0),
    endTime: DateTime(2024, 8, 1, 10, 0),
    notes: 'n1',
    exercises: exercises,
  );
}

Future<void> _pumpEdit(WidgetTester tester, {VoidCallback? onSelectRoute}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const WorkoutEditScreen(sessionId: 's1'),
      ),
      GoRoute(
        path: '/exercise_select',
        builder: (_, __) {
          onSelectRoute?.call();
          return const Scaffold(body: Text('Exercise select'));
        },
      ),
    ],
  );
  return tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      // Render the staggered entrance statically so the test isn't racing
      // flutter_animate's delayed timers.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
    ),
  );
}

void main() {
  setUp(() async {
    StaggeredEntrance.resetForTest();
    await GetIt.instance.reset(dispose: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.instance.registerSingleton<PreferencesService>(prefs);
  });

  testWidgets(
    'Details / Notes / Exercises render as SectionHeaders in flat cards',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      GetIt.instance.registerSingleton<WorkoutRepository>(
        _EditRepoFake(_session()),
      );

      await _pumpEdit(tester);
      await tester.pump(const Duration(milliseconds: 300));

      // Sentence-case SectionHeaders, not one-off titleMedium labels.
      expect(find.widgetWithText(SectionHeader, 'Details'), findsOneWidget);
      expect(find.widgetWithText(SectionHeader, 'Notes'), findsOneWidget);
      expect(find.widgetWithText(SectionHeader, 'Exercises'), findsOneWidget);

      // The name field renders with a premium decoration label inside a flat
      // surface card (no bordered one-off Container).
      final nameField = find.widgetWithText(TextFormField, 'Workout name');
      expect(nameField, findsOneWidget);
      expect(_flatCardAround(nameField), findsWidgets);

      // Start + End rows show the formatted date·time value inside the card.
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));

      // Notes uses a clean sentence-case hint, not a bordered void.
      final notesField = find.widgetWithText(
        TextFormField,
        'Add notes about this workout',
      );
      expect(notesField, findsOneWidget);
      expect(_flatCardAround(notesField), findsWidgets);
    },
  );

  testWidgets('Add affordance opens the exercise picker', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    GetIt.instance.registerSingleton<WorkoutRepository>(
      _EditRepoFake(_session()),
    );

    var openedPicker = false;
    await _pumpEdit(tester, onSelectRoute: () => openedPicker = true);
    await tester.pump(const Duration(milliseconds: 300));

    // The premium "Add" CTA in the Exercises section header. Match on the exact
    // label — "Add exercise" in the empty state and "Add another" don't collide
    // with an exact "Add". The button leads with the HustlIcon ic_add glyph.
    final addLabel = find.text('Add');
    expect(addLabel, findsOneWidget);
    // FilledButton.icon builds a private ButtonStyleButton subclass, so match by
    // subtype rather than exact runtime type.
    final addButton = find.ancestor(
      of: addLabel,
      matching: find.bySubtype<ButtonStyleButton>(),
    );
    expect(addButton, findsWidgets);
    // It leads with the tokenized add glyph (HustlIcon ic_add).
    expect(
      find.descendant(of: addButton.first, matching: find.byType(HustlIcon)),
      findsOneWidget,
    );

    await tester.tap(addButton.first);
    await tester.pumpAndSettle();

    expect(openedPicker, isTrue);
    expect(find.text('Exercise select'), findsOneWidget);
  });

  testWidgets('editing the name keeps the field focused (no reparent)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    GetIt.instance.registerSingleton<WorkoutRepository>(
      _EditRepoFake(_session()),
    );

    // Pump WITHOUT disabling animations so we exercise the real entrance path.
    // Before the fix, the form body lived inside a StaggeredEntrance that swaps
    // each child from an animated wrapper to a raw widget after its first play;
    // the per-keystroke setState then reparented the TextFormField and dropped
    // focus. The stable Column must keep focus through the first edit.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const WorkoutEditScreen(sessionId: 's1'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final nameField = find.widgetWithText(TextFormField, 'Workout name');
    expect(nameField, findsOneWidget);

    await tester.tap(nameField);
    await tester.pump();
    await tester.enterText(nameField, 'Leg day');
    await tester.pump();

    final editable = tester.state<EditableTextState>(
      find.descendant(of: nameField, matching: find.byType(EditableText)),
    );
    expect(
      editable.widget.focusNode.hasFocus,
      isTrue,
      reason: 'Name field must retain focus through the first keystroke',
    );
    expect(find.text('Leg day'), findsOneWidget);
  });

  testWidgets('no-exercises empty state still shows', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    GetIt.instance.registerSingleton<WorkoutRepository>(
      _EditRepoFake(_session()),
    );

    await _pumpEdit(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ScreenEmptyState), findsOneWidget);
    expect(find.text('No exercises yet'), findsOneWidget);
    expect(find.text('Add exercise'), findsOneWidget);
  });
}
