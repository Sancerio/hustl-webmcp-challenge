import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart'
    show RegionVolumeBand;
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score/this_week_by_region.dart';

CurrentWeekRegionSummary _region(
  DisplayRegion region, {
  required double sets,
  double target = 10,
  int? physicalSets,
  RegionVolumeBand? band,
}) {
  return CurrentWeekRegionSummary(
    region: region,
    rawSets: sets,
    weeklyTarget: target,
    physicalSets: physicalSets,
    band: band,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('WeekStatusLine', () {
    testWidgets('mid-week with some regions behind reads "on track / N of M"', (
      tester,
    ) async {
      await _pump(
        tester,
        WeekStatusLine(
          dayOfWeek: 4,
          sessionCount: 3,
          regions: [
            _region(DisplayRegion.core, sets: 10), // met
            _region(DisplayRegion.legs, sets: 3), // under
            _region(DisplayRegion.back, sets: 0), // under
          ],
        ),
      );

      expect(
        find.textContaining('1 of 3 regions hit their weekly goal'),
        findsOneWidget,
      );
      // The gap region is the furthest-behind (Back, 0/10).
      expect(find.textContaining('Back is your gap this week'), findsOneWidget);
    });

    testWidgets('all regions met reads the balanced verdict', (tester) async {
      await _pump(
        tester,
        WeekStatusLine(
          dayOfWeek: 6,
          sessionCount: 5,
          regions: [
            _region(DisplayRegion.core, sets: 10),
            _region(DisplayRegion.legs, sets: 11),
          ],
        ),
      );

      expect(
        find.textContaining('every region hit its weekly goal'),
        findsOneWidget,
      );
    });

    testWidgets('early in the week uses the non-judgemental variant', (
      tester,
    ) async {
      await _pump(
        tester,
        WeekStatusLine(
          dayOfWeek: 1,
          sessionCount: 1,
          regions: [
            _region(DisplayRegion.core, sets: 2),
            _region(DisplayRegion.legs, sets: 0),
          ],
        ),
      );

      expect(find.text('Still early this week'), findsOneWidget);
      expect(find.textContaining('1 session logged'), findsOneWidget);
      // It must NOT scold with an on-track/behind verdict.
      expect(find.textContaining('hit their weekly goal'), findsNothing);
    });
  });

  group('RegionGoalBar 3 colour zones', () {
    Color fillColor(WidgetTester tester) {
      // The fill is the AnimatedFractionallySizedBox's Container colour.
      final box = tester.widget<AnimatedFractionallySizedBox>(
        find.byType(AnimatedFractionallySizedBox),
      );
      return ((box.child as Container).color)!;
    }

    testWidgets('under goal renders the amber zone', (tester) async {
      await _pump(
        tester,
        RegionGoalBar(
          summary: _region(DisplayRegion.legs, sets: 3),
          dayOfWeek: 4,
        ),
      );
      expect(fillColor(tester), AppColors.accentWarningAmber);
      expect(find.text('3 / 10 sets'), findsOneWidget);
    });

    testWidgets('on target renders the emerald zone + check', (tester) async {
      await _pump(
        tester,
        RegionGoalBar(
          summary: _region(DisplayRegion.core, sets: 10),
          dayOfWeek: 4,
        ),
      );
      final colors = ThemeData.dark().colorScheme;
      expect(fillColor(tester), colors.tertiary);
      expect(find.text('10 / 10 sets'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('plenty (over goal) renders the blue zone', (tester) async {
      await _pump(
        tester,
        RegionGoalBar(
          summary: _region(DisplayRegion.chest, sets: 16),
          dayOfWeek: 6,
        ),
      );
      expect(fillColor(tester), AppColors.accentElectricBlue);
    });

    testWidgets('tap invokes the drill-down callback', (tester) async {
      DisplayRegion? tapped;
      await _pump(
        tester,
        RegionGoalBar(
          summary: _region(DisplayRegion.back, sets: 2),
          dayOfWeek: 4,
          onTap: () => tapped = DisplayRegion.back,
        ),
      );
      await tester.tap(find.text('Back'));
      expect(tapped, DisplayRegion.back);
    });
  });

  group('Codex P2 #385 - in-band-but-under-target reads consistent', () {
    Color fillColor(WidgetTester tester) {
      final box = tester.widget<AnimatedFractionallySizedBox>(
        find.byType(AnimatedFractionallySizedBox),
      );
      return ((box.child as Container).color)!;
    }

    // A 6..14 band with a 10 target. 7 physical sets sits INSIDE the band yet
    // UNDER the target. The bar must read amber/building (not emerald), there is
    // no done-check, and the figure is the displayed 7 / 10 - i.e. the bar colour
    // can never say "on target / green" while the pip is empty and the do-next
    // still says "add sets".
    final inBandUnderTarget = _region(
      DisplayRegion.legs,
      sets: 7,
      target: 10,
      physicalSets: 7,
      band: const RegionVolumeBand(min: 6, target: 10, max: 14),
    );

    testWidgets('7 / 10 in-band region renders amber, not emerald', (
      tester,
    ) async {
      await _pump(
        tester,
        RegionGoalBar(summary: inBandUnderTarget, dayOfWeek: 4),
      );
      expect(fillColor(tester), AppColors.accentWarningAmber);
      expect(find.text('7 / 10 sets'), findsOneWidget);
      // Under target -> NOT met -> no done-check on the bar.
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('its pip is empty (not the met/emerald dot)', (tester) async {
      // Not met, so isMet is false - the shared predicate the pip keys off.
      expect(inBandUnderTarget.isMet, isFalse);
      // Render through the public WeekStatusLine, which lays out the pip row.
      // Mid-week + enough sessions so the early-week variant does not suppress
      // the verdict/pips.
      await _pump(
        tester,
        WeekStatusLine(
          dayOfWeek: 4,
          sessionCount: 3,
          regions: [inBandUnderTarget],
        ),
      );
      // The single pip is the only 14x14 circle Container. An empty pip has a
      // transparent fill + an outline border (the met dot is a solid tertiary
      // fill with no border).
      final pip = tester.widgetList<Container>(find.byType(Container)).firstWhere((
        c,
      ) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      });
      final decoration = pip.decoration as BoxDecoration;
      expect(decoration.color, Colors.transparent);
      expect(decoration.border, isNotNull);
    });

    testWidgets('the do-next still lists it (no green-but-add-sets)', (
      tester,
    ) async {
      await _pump(tester, DoNextList(regions: [inBandUnderTarget]));
      // The displayed gap is 10 - 7 = 3, so the do-next nags exactly that.
      expect(find.text('Add about 3 legs sets'), findsOneWidget);
      expect(find.textContaining('all caught up'), findsNothing);
    });
  });

  group('DoNextList', () {
    testWidgets('shows at most three "Add about N" rows, furthest behind first', (
      tester,
    ) async {
      await _pump(
        tester,
        DoNextList(
          regions: [
            _region(DisplayRegion.core, sets: 10), // met -> excluded
            _region(DisplayRegion.legs, sets: 3), // gap 7
            _region(DisplayRegion.back, sets: 0), // gap 10 (most behind)
            _region(DisplayRegion.arms, sets: 6), // gap 4
            _region(DisplayRegion.chest, sets: 8), // gap 2
          ],
        ),
      );

      // Exactly three rows (the cap), met region excluded.
      expect(find.textContaining('Add about'), findsNWidgets(3));
      // Furthest-behind region surfaces.
      expect(find.text('Add about 10 back sets'), findsOneWidget);
      expect(find.text('Add about 7 legs sets'), findsOneWidget);
      expect(find.text('Add about 4 arms sets'), findsOneWidget);
      // The least-behind two are dropped by the cap.
      expect(find.text('Add about 2 chest sets'), findsNothing);
    });

    testWidgets(
      'orders by the DISPLAYED gap - a 5 / 10 primary outranks a 9 / 10 '
      'secondary-heavy region',
      (tester) async {
        // The bug: the sort keyed off the RAW percent (rawSets / target) while
        // the UI displays + gaps on the PHYSICAL count. Pick raw fractions that
        // DISAGREE with the physical counts so the two sorts diverge:
        //   secondary-heavy: raw 4.0 / 10 (40% raw) but a displayed 9 / 10
        //   primary:         raw 6.0 / 10 (60% raw) but a displayed 5 / 10
        // RAW percent would rank the secondary (40%) FIRST - the reported bug,
        // recommending its 1-set gap before the primary's 5-set gap. Sorting on
        // the DISPLAYED gap must instead put the 5 / 10 primary (gap 5) first.
        await _pump(
          tester,
          DoNextList(
            regions: [
              // Secondary-heavy: lower RAW percent, but displayed 9 / 10 (gap 1).
              _region(DisplayRegion.core, sets: 4.0, physicalSets: 9),
              // Primary: higher RAW percent, but displayed 5 / 10 (gap 5).
              _region(DisplayRegion.legs, sets: 6.0, physicalSets: 5),
            ],
          ),
        );

        final addFinder = find.textContaining('Add about');
        expect(addFinder, findsNWidgets(2));
        // The 5 / 10 primary (gap 5) must be the FIRST row, ahead of the
        // 9 / 10 secondary-heavy region (gap 1).
        final firstRow = tester.widgetList<Text>(addFinder).first.data;
        expect(firstRow, 'Add about 5 legs sets');
        expect(find.text('Add about 1 core set'), findsOneWidget);
      },
    );

    testWidgets('all met collapses to the all-clear row', (tester) async {
      await _pump(
        tester,
        DoNextList(
          regions: [
            _region(DisplayRegion.core, sets: 10),
            _region(DisplayRegion.legs, sets: 12),
          ],
        ),
      );
      expect(find.textContaining('all caught up'), findsOneWidget);
      expect(find.textContaining('Add about'), findsNothing);
    });
  });

  group('CountingExplainer', () {
    testWidgets('collapsed by default, expands to the raw-vs-hard-sets copy', (
      tester,
    ) async {
      await _pump(tester, const CountingExplainer());
      expect(find.textContaining('weighted'), findsNothing);
      await tester.tap(find.text('How are these counted?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('raw sets you logged this week'), findsOneWidget);
    });
  });
}
