import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_goal_profile.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/goal_setup_dialog.dart';

/// The payload the sheet returned (the calc trigger), captured by the host so a
/// test can assert what a "Set targets" tap hands back.
Map<String, dynamic>? _capturedResult;

/// Hosts the goal sheet behind a button. MaterialApp.router so the sheet's
/// go_router `context.pop` resolves the way it does in the app.
Future<void> _openSheet(
  WidgetTester tester, {
  required String initialGoal,
  double? initialRatePerWeek,
  NutritionGoalProfile? initialProfile,
  bool requireProfile = false,
}) async {
  _capturedResult = null;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                _capturedResult = await showGoalSetupDialog(
                  context,
                  initialGoal: initialGoal,
                  initialRatePerWeek: initialRatePerWeek,
                  initialProfile: initialProfile,
                  requireProfile: requireProfile,
                );
              },
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

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  testWidgets(
    'prefills every field from the last-saved goal + profile on reopen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openSheet(
        tester,
        initialGoal: 'lose',
        initialRatePerWeek: 0.4,
        initialProfile: NutritionGoalProfile(
          birthDate: DateTime(1990, 1, 15),
          heightCm: 178,
          weightKg: 81.5,
          gender: 'female',
          activityLevel: 'active',
        ),
      );

      // Weekly rate seeded from the saved plan (0.40), not a default.
      expect(_fieldText(tester, 'goalRateField'), '0.40');
      // The DOB field shows the formatted saved date and a derived-age helper.
      expect(find.byKey(const Key('goalBirthDateField')), findsOneWidget);
      expect(find.text('15 Jan 1990'), findsOneWidget);
      final expectedAge =
          ageFromBirthDate(DateTime(1990, 1, 15), DateTime.now());
      expect(find.text('Age $expectedAge'), findsOneWidget);
      // About-you numeric fields seeded from the saved profile.
      expect(_fieldText(tester, 'goalHeightField'), '178');
      expect(_fieldText(tester, 'goalWeightField'), '81.5');
      // Sex dropdown reflects the saved value.
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('goalSexField')),
            )
            .initialValue,
        'female',
      );
      // Selected goal + activity chips carry the saved selection.
      expect(
        _selectedChipLabels(tester),
        containsAll(<String>['Lose', 'Active']),
      );
    },
  );

  testWidgets(
    'returns the seeded birthDate (ISO) in the result so a no-edit save '
    'preserves it (regression: profile silently reset to defaults on reopen)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openSheet(
        tester,
        initialGoal: 'gain',
        initialRatePerWeek: 0.25,
        initialProfile: NutritionGoalProfile(
          birthDate: DateTime(1998, 3, 7),
          heightCm: 182,
          weightKg: 75.0,
          gender: 'male',
          activityLevel: 'moderate',
        ),
      );

      await tester.tap(find.byKey(const Key('goalSetTargets')));
      await tester.pumpAndSettle();

      expect(_capturedResult, isNotNull);
      expect(_capturedResult!['goal'], 'gain');
      expect(_capturedResult!['rate'], 0.25);
      final profile = _capturedResult!['profile'] as Map<String, dynamic>;
      // The previously-entered values flow straight back out as a verbatim ISO
      // date (no timezone shift) — they are NOT dropped to defaults.
      expect(profile['birthDate'], '1998-03-07');
      expect(profile.containsKey('ageYears'), isFalse);
      expect(profile['heightCm'], 182);
      expect(profile['weightKg'], 75.0);
      expect(profile['gender'], 'male');
      expect(profile['activityLevel'], 'moderate');
    },
  );

  testWidgets('tapping the DOB field opens a date picker', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _openSheet(
      tester,
      initialGoal: 'maintain',
      initialProfile: NutritionGoalProfile(birthDate: DateTime(1990, 5, 20)),
    );

    await tester.tap(find.byKey(const Key('goalBirthDateField')));
    await tester.pumpAndSettle();

    // The Material date picker dialog is on screen.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    // Dismiss so the test tears down cleanly (tap Cancel inside the dialog).
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'DOB picker opens (no assert) for a 120-year-old saved DOB at the oldest '
    'edge of the backend-aligned range',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      // Exactly the oldest selectable DOB (today - 120y). Before the fix the
      // picker floor was ~100y, so this seed sat before firstDate and tripped the
      // framework's initialDate assertion instead of opening.
      final oldest = DateTime(now.year - 120, now.month, now.day);

      await _openSheet(
        tester,
        initialGoal: 'maintain',
        initialProfile: NutritionGoalProfile(birthDate: oldest),
      );

      await tester.tap(find.byKey(const Key('goalBirthDateField')));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      await _dismissPicker(tester);
    },
  );

  testWidgets(
    'DOB picker opens (no assert) for the youngest allowed saved DOB',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      // Exactly the youngest selectable DOB (today - 13y), the under-13 floor.
      final youngest = DateTime(now.year - 13, now.month, now.day);

      await _openSheet(
        tester,
        initialGoal: 'maintain',
        initialProfile: NutritionGoalProfile(birthDate: youngest),
      );

      await tester.tap(find.byKey(const Key('goalBirthDateField')));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      await _dismissPicker(tester);
    },
  );

  testWidgets(
    'DOB picker opens (no assert) for an out-of-range saved DOB (clamped seed)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      // Older than the 120-year floor: the initialDate must be clamped into
      // [firstDate, lastDate] or showDatePicker asserts.
      final tooOld = DateTime(now.year - 150, now.month, now.day);

      await _openSheet(
        tester,
        initialGoal: 'maintain',
        initialProfile: NutritionGoalProfile(birthDate: tooOld),
      );

      await tester.tap(find.byKey(const Key('goalBirthDateField')));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      await _dismissPicker(tester);
    },
  );

  testWidgets('with no saved profile, the DOB field starts empty', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _openSheet(tester, initialGoal: 'maintain');

    expect(find.byKey(const Key('goalBirthDateField')), findsOneWidget);
    // No date chosen yet -> no derived-age helper rendered.
    expect(find.textContaining('Age '), findsNothing);
    expect(_fieldText(tester, 'goalHeightField'), isEmpty);
    // Maintain hides the weekly-rate field entirely.
    expect(find.byKey(const Key('goalRateField')), findsNothing);
  });

  // The DOB picker floor must be the EARLIEST date that still derives age 120,
  // matching the backend's inclusive ceiling (derived age <= 120) — not exactly
  // `today - 120y`. Asserting on the resolver (`ageFromBirthDate`) pins the
  // boundary regardless of the widget's private firstDate.
  test(
    'picker floor admits the oldest age-120 DOB and excludes the age-121 one',
    () {
      final now = DateTime.now();
      // This mirrors `_pickDob`'s firstDate: the day after `today - 121y`.
      final floor = subtractYears(now, 121).add(const Duration(days: 1));

      // The earliest selectable DOB still derives age 120 (inclusive ceiling).
      expect(ageFromBirthDate(floor, now), 120);

      // One day earlier derives age 121 and must sit BELOW the floor (excluded).
      final dayBeforeFloor = floor.subtract(const Duration(days: 1));
      expect(ageFromBirthDate(dayBeforeFloor, now), 121);
      expect(dayBeforeFloor.isBefore(floor), isTrue);
    },
  );
}

/// Tap the picker's Cancel so the test tears down cleanly.
Future<void> _dismissPicker(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.widgetWithText(TextButton, 'Cancel'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Labels of the chips currently rendered in the selected state.
Set<String> _selectedChipLabels(WidgetTester tester) {
  final selected = <String>{};
  for (final s in tester.widgetList<Semantics>(find.byType(Semantics))) {
    final props = s.properties;
    if (props.inMutuallyExclusiveGroup == true && props.selected == true) {
      final label = props.label;
      if (label != null) selected.add(label);
    }
  }
  return selected;
}
