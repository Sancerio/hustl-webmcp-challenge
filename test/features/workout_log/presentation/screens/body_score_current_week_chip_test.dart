import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';

/// Guards the codex [P2] (PR #384, body_score_coach.dart:372): the current-week
/// region met-check rounds the raw sets to the displayed integer, but the chip
/// used to render the SAME snapshot as `9.5 / 10` AND color it amber (raw 95%
/// score) - so Home/overview said "done" while the detail chip read under goal.
///
/// These tests pin ONE rounded display basis across the chip value, the chip
/// color/zone (met state) AND the per-region cue, so they can never disagree:
///   - 9.5 / 10 -> chip "10 / 10", met (green, NOT amber), cue "done".
///   - 4.4 / 10 -> chip "4 / 10", under (amber), cue "add about 6".
void main() {
  group('current-week region chip + cue share one rounded basis', () {
    test('9.5 / 10 -> chip "10 / 10" met (green, NOT amber) + cue "done"', () {
      // Chip value + color basis.
      final chip = currentWeekGoalDisplayForTest(done: 9.5, target: 10);
      expect(chip.value, '10 / 10', reason: 'displays the rounded integer');
      expect(
        chip.isMet,
        isTrue,
        reason: 'met after rounding -> green/tertiary, NOT amber',
      );
      expect(chip.semantics, 'Weekly goal: 10 of 10 weekly sets');

      // Cue basis - must agree with the chip (done, no "add" nag).
      final cue = currentWeekRegionCueForTest(
        ewma7: 9.5,
        weeklyTarget: 10,
        region: DisplayRegion.core,
      );
      expect(cue, isNotNull);
      expect(cue!.mode, BodyScoreCoachingMode.maintain);
      expect(cue.headline, 'Core 10 / 10 sets - done.');
      expect(cue.headline.toLowerCase(), isNot(contains('add')));

      // Domain headline basis (overview "done") - same rounded met state.
      final domainCue = BodyScoreCoach.currentWeekCue(
        {MuscleGroup.upperAbs: 9.5},
        weeklyTargets: {MuscleGroup.upperAbs: 10},
      );
      expect(domainCue.mode, BodyScoreCoachingMode.maintain);
      expect(domainCue.headline.toLowerCase(), isNot(contains('add')));
    });

    test('4.4 / 10 -> chip "4 / 10" under (amber) + cue "add about 6"', () {
      final chip = currentWeekGoalDisplayForTest(done: 4.4, target: 10);
      expect(chip.value, '4 / 10', reason: 'displays the rounded integer');
      expect(
        chip.isMet,
        isFalse,
        reason: 'genuinely under after rounding -> amber',
      );
      expect(chip.semantics, 'Weekly goal: 4 of 10 weekly sets');

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

    test('exactly met (10 / 10) -> chip "10 / 10" met (green)', () {
      final chip = currentWeekGoalDisplayForTest(done: 10, target: 10);
      expect(chip.value, '10 / 10');
      expect(chip.isMet, isTrue);
    });

    test('just-over a fractional target stays met after rounding', () {
      // 9.6 raw vs a 9.5 target: both round to 10, so the chip reads "10 / 10"
      // met - the rounded basis never marks a displayed-equal pair under goal.
      final chip = currentWeekGoalDisplayForTest(done: 9.6, target: 9.5);
      expect(chip.value, '10 / 10');
      expect(chip.isMet, isTrue);
    });
  });
}
