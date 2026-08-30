import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';

/// Guards the codex [P2] (PR #385, body_score_screen.dart:314): the current-week
/// HEADLINE bars / do-next key off [CurrentWeekRegionSummary.displaySets] /
/// [displayGap] (the rounded display figure - the TRUE physical-set count when
/// present), but `_withRawCurrentWeek(...)` used to write the raw fractional
/// `rawSets` / raw gap into the LEGACY region snapshot the collapsed
/// "Trends & detail" / "Muscle groups" rows render. So secondary-heavy work
/// could show e.g. `9 / 10` in the headline but `5 / 10` + "Add about 5 sets" in
/// the detail row for the SAME region - a headline-vs-detail mismatch.
///
/// These tests pin the detail-row snapshot to the SAME display basis as the
/// headline, so the value, gap and "add N sets" copy reconcile.
void main() {
  group('current-week headline vs legacy detail-row snapshot', () {
    test(
      'secondary-heavy region: headline 9/10 AND detail 9/10 (not 5/10)',
      () {
        // Raw `baseSet x groupRatio` credit sums to 5.0, but 9 TRUE physical
        // working sets actually trained this region this week. The headline
        // shows the physical count (9 / 10); the detail row must too.
        final r = currentWeekHeadlineVsDetailForTest(
          region: DisplayRegion.back,
          rawSets: 5.0,
          weeklyTarget: 10,
          physicalSets: 9,
        );

        // Headline basis.
        expect(r.headlineSets, 9);
        expect(r.headlineGap, 1);
        expect(r.headlineMet, isFalse);

        // Detail-row basis must MATCH the headline (the bug: 5 / 10 + "add 5").
        expect(
          r.detailSets,
          r.headlineSets,
          reason: 'detail row value must equal the headline value',
        );
        expect(
          r.detailGap,
          r.headlineGap,
          reason: 'detail "add N sets" gap must equal the headline gap',
        );
        expect(r.detailSets, 9);
        expect(r.detailGap, 1);

        // The detail cue copy rides the same display basis.
        expect(r.detailCue, isNotNull);
        expect(r.detailCue!.mode, BodyScoreCoachingMode.addSets);
        expect(r.detailCue!.headline, 'Add about 1 back set.');
        expect(r.detailCue!.setCount, 1);
        expect(r.detailCue!.headline, isNot(contains('5')));
      },
    );

    test('met region: headline 10/10 done AND detail 10/10 done', () {
      // 9.6 raw rounds to 10 and 10 physical sets are counted: headline reads a
      // met 10 / 10, and the detail row + cue must agree (no nag).
      final r = currentWeekHeadlineVsDetailForTest(
        region: DisplayRegion.core,
        rawSets: 9.6,
        weeklyTarget: 10,
        physicalSets: 10,
      );

      expect(r.headlineSets, 10);
      expect(r.headlineMet, isTrue);
      expect(r.detailSets, r.headlineSets);
      expect(r.detailGap, 0);
      expect(r.detailCue, isNotNull);
      expect(r.detailCue!.mode, BodyScoreCoachingMode.maintain);
      expect(r.detailCue!.headline, 'Core 10 / 10 sets - done.');
      expect(r.detailCue!.headline.toLowerCase(), isNot(contains('add')));
    });

    test(
      'no physical count: display basis reduces to rounded raw (unchanged)',
      () {
        // The non-current-week / Home-focus path supplies no physical count, so
        // displaySets/displayGap reduce to rawSets.round() / the raw gap. The
        // detail row stays on the SAME (rounded raw) basis as before the fix.
        final r = currentWeekHeadlineVsDetailForTest(
          region: DisplayRegion.core,
          rawSets: 4.4,
          weeklyTarget: 10,
        );

        expect(r.headlineSets, 4);
        expect(r.headlineGap, 6);
        expect(r.detailSets, r.headlineSets);
        expect(r.detailGap, r.headlineGap);
        expect(r.detailCue, isNotNull);
        expect(r.detailCue!.mode, BodyScoreCoachingMode.addSets);
        expect(r.detailCue!.headline, 'Add about 6 core sets.');
        expect(r.detailCue!.setCount, 6);
      },
    );
  });
}
