import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';

void main() {
  group('_currentWeekRegionCue (presentation)', () {
    test(
      'a region at 9.5 raw vs a 10 target reads met (10 / 10) with NO "add" nag',
      () {
        // 9.5 raw sets (e.g. split compound/secondary muscle credit) round to 10
        // for display, so the tile renders "Core 10 / 10". The presentation cue
        // must agree: met, never "Add about 1 set" - consistent with the domain
        // `CurrentWeekRegionSummary.isMet` / `BodyScoreCoach.currentWeekCue`.
        final cue = currentWeekRegionCueForTest(
          ewma7: 9.5,
          weeklyTarget: 10,
          region: DisplayRegion.core,
        );

        expect(cue, isNotNull);
        expect(cue!.mode, BodyScoreCoachingMode.maintain);
        expect(cue.headline, 'Core 10 / 10 sets - done.');
        expect(cue.headline.toLowerCase(), isNot(contains('add')));
        expect(cue.setCount, 0);
      },
    );

    test('an exactly-met region reads met with no nag', () {
      final cue = currentWeekRegionCueForTest(
        ewma7: 10,
        weeklyTarget: 10,
        region: DisplayRegion.core,
      );

      expect(cue, isNotNull);
      expect(cue!.mode, BodyScoreCoachingMode.maintain);
      expect(cue.headline, 'Core 10 / 10 sets - done.');
      expect(cue.headline.toLowerCase(), isNot(contains('add')));
    });

    test('a genuinely under-target region gets a rounded "add about N" cue', () {
      // 4.4 raw rounds to 4; 4 < 10, so the cue nags with the rounded gap (6).
      final cue = currentWeekRegionCueForTest(
        ewma7: 4.4,
        weeklyTarget: 10,
        region: DisplayRegion.core,
      );

      expect(cue, isNotNull);
      expect(cue!.mode, BodyScoreCoachingMode.addSets);
      expect(cue.headline, 'Add about 6 core sets.');
      expect(cue.setCount, 6);
    });

    test('returns null when there is no weekly target', () {
      final cue = currentWeekRegionCueForTest(
        ewma7: 0,
        weeklyTarget: 0,
        region: DisplayRegion.core,
      );

      expect(cue, isNull);
    });
  });
}
