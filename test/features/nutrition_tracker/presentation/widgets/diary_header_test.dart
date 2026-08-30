import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/bloc/diary_state.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/diary_components.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/diary_header.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/diary_week_banner.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/food_entry_avatar.dart';

NutritionTargetPlan _plan() => NutritionTargetPlan(
  weekStart: DateTime(2026, 6, 8),
  mode: 'auto',
  goal: 'maintain',
  caloriesTarget: 2000,
  proteinTarget: 150,
  carbsTarget: 200,
  fatTarget: 70,
);

FoodLogEntry _entry(String id, {required int hour, double cal = 100}) =>
    FoodLogEntry(
      id: id,
      date: DateTime(2026, 6, 12),
      loggedAt: DateTime(2026, 6, 12, hour, 0),
      servingGrams: 100,
      calories: cal,
      proteinGrams: 10,
      carbsGrams: 10,
      fatGrams: 5,
      foodName: 'Food $id',
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('DiaryHeader renders a calorie ring hero with three macro bars', (
    tester,
  ) async {
    final state = DiaryState(
      date: DateTime(2026, 6, 12),
      totalCalories: 1200,
      targets: _plan(),
      totalProtein: 90,
      totalCarbs: 120,
      totalFat: 40,
    );
    await _pump(tester, DiaryHeader(state: state));

    // Wave I: the calorie focal metric is an AppProgressRing hero.
    expect(find.byType(AppProgressRing), findsOneWidget);
    // The remaining kcal is the BIG centred numeral (2000 - 1200 = 800).
    final hero = tester.widget<Text>(find.text('800'));
    expect(hero.style?.fontSize, 40);
    expect(find.text('kcal left'), findsOneWidget);

    // Three compact macro bars: Protein, Carbs, Fat (no Calories row).
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('Carbs'), findsOneWidget);
    expect(find.text('Fat'), findsOneWidget);
    expect(find.text('Calories'), findsNothing);

    // Macro bar values now read "consumed / target g" on one line.
    expect(find.text('90 / 150 g'), findsOneWidget);
    expect(find.text('120 / 200 g'), findsOneWidget);
    expect(find.text('40 / 70 g'), findsOneWidget);

    // The old flat-row module and its keys are gone.
    expect(find.text('1200 / 2000'), findsNothing);
    expect(
      find.byKey(const ValueKey('diary-macro-row-Calories')),
      findsNothing,
    );
  });

  testWidgets('DiaryHeader shows remaining calories as the BIG ring numeral', (
    tester,
  ) async {
    final state = DiaryState(
      date: DateTime(2026, 6, 12),
      totalCalories: 1230, // 2000 target -> 770 remaining
      targets: _plan(),
      totalProtein: 90,
      totalCarbs: 120,
      totalFat: 40,
    );
    await _pump(tester, DiaryHeader(state: state));

    // The remaining number is the 40px hero in the ring centre; the
    // caption sits quietly beneath. The old 13px "770 kcal left" line and
    // its combined value are gone.
    final remaining = tester.widget<Text>(find.text('770'));
    expect(remaining.style?.fontSize, 40);
    expect(find.text('kcal left'), findsOneWidget);
    expect(find.text('770 kcal left'), findsNothing);
  });

  testWidgets('DiaryHeader over-budget reads amber in the ring, never red', (
    tester,
  ) async {
    final state = DiaryState(
      date: DateTime(2026, 6, 12),
      totalCalories: 2500, // over the 2000 target
      targets: _plan(),
      totalProtein: 200,
      totalCarbs: 100,
      totalFat: 40,
    );
    await _pump(tester, DiaryHeader(state: state));

    // Over budget: the hero shows the excess (2500 - 2000 = 500) and the
    // caption flips to "kcal over" in the warning amber, never red.
    expect(find.text('500'), findsOneWidget);
    final overCaption = tester.widget<Text>(find.text('kcal over'));
    expect(overCaption.style?.color, AppColors.accentWarningAmber);
    expect(find.text('kcal left'), findsNothing);

    // The calorie ring itself fills amber when over budget.
    final ring = tester.widget<AppProgressRing>(find.byType(AppProgressRing));
    expect(ring.color, AppColors.accentWarningAmber);

    // The old per-macro tick markers are gone in Wave I.
    expect(
      find.byKey(const ValueKey('diary-macro-tick-Protein')),
      findsNothing,
    );
  });

  testWidgets('DiaryMealSections groups into four sentence-case sections', (
    tester,
  ) async {
    await _pump(
      tester,
      DiaryMealSections(
        entries: [_entry('a', hour: 8), _entry('b', hour: 19)],
        onDelete: (_) {},
        onEdit: (_) {},
        onAddToMeal: (_) {},
      ),
    );

    // Wave I: shared SectionHeader renders sentence-case labels.
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Snack'), findsOneWidget);
    // The two logged foods render.
    expect(find.text('Food a'), findsOneWidget);
    expect(find.text('Food b'), findsOneWidget);
  });

  testWidgets('DiaryTimeline renders MF hour rows with muted summaries', (
    tester,
  ) async {
    await _pump(
      tester,
      DiaryTimeline(
        entriesByHour: {
          8: [_entry('a', hour: 8)],
          13: [_entry('b', hour: 13)],
        },
        onDelete: (_) {},
        onEdit: (_) {},
        onAddAtHour: (_) {},
        highlightCurrentHour: false,
      ),
    );

    expect(find.text('8 AM'), findsOneWidget);
    expect(find.text('1 PM'), findsOneWidget);
    // An empty hour like 10 AM is not rendered at all.
    expect(find.text('10 AM'), findsNothing);
    // Hourly summary is one muted text line — no colored letter chips.
    expect(find.text('100 Cal · 10P · 5F · 10C'), findsNWidgets(2));
  });

  testWidgets('DiaryTimeline food tiles show a food glyph, no pencil', (
    tester,
  ) async {
    var editedId = '';
    await _pump(
      tester,
      DiaryTimeline(
        entriesByHour: {
          8: [_entry('a', hour: 8)],
        },
        onDelete: (_) {},
        onEdit: (entry) => editedId = entry.id,
        onAddAtHour: (_) {},
        highlightCurrentHour: false,
      ),
    );

    // Leading food glyph (MacroFactor-style) + name + serving/macros, with the
    // calories and the muted log time right-aligned. Still no inline pencil.
    expect(find.byType(FoodEntryAvatar), findsOneWidget);
    expect(find.text('8:00'), findsOneWidget);
    expect(find.text('100 Cal'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    // Tap the row (not a pencil) to edit.
    await tester.tap(find.text('Food a'));
    expect(editedId, 'a');
  });

  testWidgets('DiaryWeekBanner shows the Mon–Sun week and jumps on tap', (
    tester,
  ) async {
    DateTime? selected;
    await _pump(
      tester,
      DiaryWeekBanner(
        // 2026-06-12 is a Friday; its week runs Mon 8 – Sun 14 June.
        date: DateTime(2026, 6, 12),
        onSelectDay: (d) => selected = d,
      ),
    );

    for (var day = 8; day <= 14; day++) {
      expect(find.text('$day'), findsOneWidget);
    }

    await tester.tap(find.text('10'));
    expect(selected, DateTime(2026, 6, 10));
  });

  testWidgets('DiaryWeekBanner chevrons shift the visible week by ±7 days', (
    tester,
  ) async {
    DateTime? selected;
    await _pump(
      tester,
      DiaryWeekBanner(
        date: DateTime(2026, 6, 12),
        onSelectDay: (d) => selected = d,
      ),
    );

    // The next-week chevron jumps the selected day forward a week.
    await tester.tap(find.byTooltip('Next week'));
    expect(selected, DateTime(2026, 6, 19));

    // The previous-week chevron jumps it back a week.
    await tester.tap(find.byTooltip('Previous week'));
    expect(selected, DateTime(2026, 6, 5));
  });

  testWidgets('DiaryWeekBanner marks the selected day with a solid oval', (
    tester,
  ) async {
    await _pump(
      tester,
      DiaryWeekBanner(date: DateTime(2026, 6, 12), onSelectDay: (_) {}),
    );

    final scheme = Theme.of(
      tester.element(find.byType(DiaryWeekBanner)),
    ).colorScheme;
    final oval = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('diary-week-day-2026-06-12')),
    );
    final decoration = oval.decoration as BoxDecoration?;
    expect(decoration?.color, scheme.primary);
  });

  testWidgets('DiaryWeekHeaderDelegate pins the title and collapses the '
      'banner on scroll', (tester) async {
    // 2020-01-06 is a Monday well in the past, so the title is a plain date.
    final date = DateTime(2020, 1, 6);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: DiaryWeekHeaderDelegate(
                  topPadding: 0,
                  title: DiaryDateTitle(date: date, onToday: () {}),
                  banner: DiaryWeekBanner(date: date, onSelectDay: (_) {}),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Mon, Jan 6'), findsOneWidget);
    Opacity bannerOpacity() => tester.widget<Opacity>(
      find.ancestor(
        of: find.byType(DiaryWeekBanner),
        matching: find.byType(Opacity),
      ),
    );
    expect(bannerOpacity().opacity, 1);

    // Scroll the log: the banner collapses away while the title stays pinned.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Mon, Jan 6'), findsOneWidget);
    expect(bannerOpacity().opacity, 0);
  });

  testWidgets('DiaryDateTitle shows a Today shortcut only when off today', (
    tester,
  ) async {
    var wentToday = false;
    await _pump(
      tester,
      DiaryDateTitle(
        date: DateTime(2020, 1, 1),
        onToday: () => wentToday = true,
      ),
    );

    await tester.tap(find.text('Today'));
    expect(wentToday, isTrue);

    await _pump(tester, DiaryDateTitle(date: DateTime.now(), onToday: () {}));
    // On today the title itself reads "Today" and the shortcut button is gone.
    expect(find.text('Today'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('DiaryDateTitle label fires onPickDate when tapped', (
    tester,
  ) async {
    var picked = false;
    await _pump(
      tester,
      DiaryDateTitle(
        date: DateTime(2020, 1, 1),
        onToday: () {},
        onPickDate: () => picked = true,
      ),
    );

    // The label reads its formatted date and is tappable (a chevron hints the
    // calendar). Tapping it opens the picker via the callback.
    await tester.tap(find.text('Wed, Jan 1'));
    expect(picked, isTrue);
  });

  testWidgets('DiaryDateTitle label is a plain label without onPickDate', (
    tester,
  ) async {
    await _pump(
      tester,
      DiaryDateTitle(date: DateTime(2020, 1, 1), onToday: () {}),
    );
    // No calendar affordance when onPickDate is absent.
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
  });
}
