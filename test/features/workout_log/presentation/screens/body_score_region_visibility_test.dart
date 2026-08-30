import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';

/// Guards codex [P2] (PR #384, body_score_screen.dart:_visibleSummaries): the
/// current-week headline cue can recommend a TARGETED region that has ZERO sets
/// logged this week (e.g. "add chest sets" at 0/10 when only core was trained).
/// Under the default "Recently trained only" filter that zero-volume row was
/// hidden, so the cue named a region absent from the visible list.
///
/// Fix (option a): for the in-progress current week, keep every targeted,
/// under-target region visible by default so the cue's recommended region is
/// always on screen. CLOSED periods keep their volume/recency gate unchanged.
void main() {
  final now = DateTime(2026, 6, 17, 12); // a Wednesday, current week partial.

  group('isRegionVisibleForTest', () {
    test('current week: a zero-volume, targeted, under-target region is shown '
        'by default (so the cue never names a hidden row)', () {
      final visible = isRegionVisibleForTest(
        hasSnapshot: true,
        weeklyTarget: 10,
        isUnderTarget: true,
        windowVolume: 0, // zero sets this week — the cue may still name it.
        lastStimulus: null, // never recently trained.
        showActiveOnly: true, // the default filter.
        isCurrentWeek: true,
        now: now,
      );
      expect(visible, isTrue);
    });

    test('current week: a met (not under-target) zero-volume region stays '
        'hidden under the default filter', () {
      final visible = isRegionVisibleForTest(
        hasSnapshot: true,
        weeklyTarget: 10,
        isUnderTarget: false, // already met — not a gap the cue points at.
        windowVolume: 0,
        lastStimulus: null,
        showActiveOnly: true,
        isCurrentWeek: true,
        now: now,
      );
      expect(visible, isFalse);
    });

    test('current week: an untargeted (weeklyTarget 0) region is not force-'
        'shown by the under-target carve-out', () {
      final visible = isRegionVisibleForTest(
        hasSnapshot: true,
        weeklyTarget: 0, // not a targeted region.
        isUnderTarget: true,
        windowVolume: 0,
        lastStimulus: null,
        showActiveOnly: true,
        isCurrentWeek: true,
        now: now,
      );
      expect(visible, isFalse);
    });

    test('CLOSED period: a zero-volume under-target region stays hidden under '
        'the default filter (closed-period behaviour unchanged)', () {
      final visible = isRegionVisibleForTest(
        hasSnapshot: true,
        weeklyTarget: 10,
        isUnderTarget: true,
        windowVolume: 0,
        lastStimulus: null,
        showActiveOnly: true,
        isCurrentWeek: false, // closed period — the carve-out must NOT apply.
        now: now,
      );
      expect(visible, isFalse);
    });

    test('filter off (show all) => every region is shown regardless of period',
        () {
      final visible = isRegionVisibleForTest(
        hasSnapshot: true,
        weeklyTarget: 10,
        isUnderTarget: false,
        windowVolume: 0,
        lastStimulus: null,
        showActiveOnly: false,
        isCurrentWeek: false,
        now: now,
      );
      expect(visible, isTrue);
    });

    test('default filter: a recently-trained or sufficiently-trained region is '
        'shown via the volume/recency gate', () {
      // Meets the volume gate (>= 2 window sets).
      expect(
        isRegionVisibleForTest(
          hasSnapshot: true,
          weeklyTarget: 10,
          isUnderTarget: false,
          windowVolume: 3,
          lastStimulus: null,
          showActiveOnly: true,
          isCurrentWeek: false,
          now: now,
        ),
        isTrue,
      );
      // Meets the recency gate (trained within 21 days).
      expect(
        isRegionVisibleForTest(
          hasSnapshot: true,
          weeklyTarget: 10,
          isUnderTarget: false,
          windowVolume: 0,
          lastStimulus: now.subtract(const Duration(days: 5)),
          showActiveOnly: true,
          isCurrentWeek: false,
          now: now,
        ),
        isTrue,
      );
    });

    test('default filter: a region with no snapshot is hidden', () {
      final visible = isRegionVisibleForTest(
        hasSnapshot: false,
        weeklyTarget: 0,
        isUnderTarget: false,
        windowVolume: 0,
        lastStimulus: null,
        showActiveOnly: true,
        isCurrentWeek: true,
        now: now,
      );
      expect(visible, isFalse);
    });
  });
}
