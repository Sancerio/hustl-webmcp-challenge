import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/coaching/training_explain_facts.dart';

// trainingExplainResetKey (PR #381 Finding 3). The OLD reset key only included
// period / rounded balance / session count, so a change to a region percent, the
// lagging/dominant region, the cue text, the set count, or the window left the key
// stable — and a stale note hung above fresh data. The key is now derived from the
// FULL training facts map, so a change to ANY narrative input changes the key.

// A representative training facts map, matching the shape body_score_screen builds
// for the `training` explain domain.
Map<String, dynamic> facts({
  int balanceScore = 72,
  List<Map<String, dynamic>>? regions,
  String? laggingRegion = 'Chest',
  String? dominantRegion = 'Back',
  String cueHeadline = 'Add 2 more sets of chest',
  String cueDetail = 'Chest is at 40% of goal over the last 4 weeks.',
  int setCount = 2,
  int sessionCount = 4,
  int windowDays = 28,
  String windowLabel = 'Last 4 full weeks',
}) {
  return {
    'balanceScore': balanceScore,
    'regions': regions ??
        [
          {'name': 'Chest', 'percentOfGoal': 40},
          {'name': 'Back', 'percentOfGoal': 110},
          {'name': 'Shoulders', 'percentOfGoal': 85},
          {'name': 'Arms', 'percentOfGoal': 95},
          {'name': 'Core', 'percentOfGoal': 60},
          {'name': 'Legs', 'percentOfGoal': 100},
        ],
    'laggingRegion': laggingRegion,
    'dominantRegion': dominantRegion,
    'cueHeadline': cueHeadline,
    'cueDetail': cueDetail,
    'setCount': setCount,
    'sessionCount': sessionCount,
    'windowDays': windowDays,
    'windowLabel': windowLabel,
  };
}

void main() {
  group('trainingExplainResetKey', () {
    test('is stable for an unchanged facts map', () {
      expect(trainingExplainResetKey(facts()), trainingExplainResetKey(facts()));
    });

    test('is insensitive to key insertion order (sorted)', () {
      final a = facts();
      // Same entries, different insertion order.
      final reordered = <String, dynamic>{};
      for (final k in a.keys.toList().reversed) {
        reordered[k] = a[k];
      }
      expect(trainingExplainResetKey(a), trainingExplainResetKey(reordered));
    });

    test('changes when a region percent changes (was STABLE under the old key)', () {
      final a = facts();
      final b = facts(regions: [
        {'name': 'Chest', 'percentOfGoal': 55}, // 40 -> 55
        {'name': 'Back', 'percentOfGoal': 110},
        {'name': 'Shoulders', 'percentOfGoal': 85},
        {'name': 'Arms', 'percentOfGoal': 95},
        {'name': 'Core', 'percentOfGoal': 60},
        {'name': 'Legs', 'percentOfGoal': 100},
      ]);
      // balance, session count, and window are all identical — the OLD key would NOT
      // have changed; the full-facts key MUST.
      expect(a['balanceScore'], b['balanceScore']);
      expect(a['sessionCount'], b['sessionCount']);
      expect(trainingExplainResetKey(a), isNot(trainingExplainResetKey(b)));
    });

    test('changes when the lagging region changes', () {
      expect(
        trainingExplainResetKey(facts()),
        isNot(trainingExplainResetKey(facts(laggingRegion: 'Legs'))),
      );
    });

    test('changes when the dominant region changes', () {
      expect(
        trainingExplainResetKey(facts()),
        isNot(trainingExplainResetKey(facts(dominantRegion: 'Legs'))),
      );
    });

    test('changes when the cue text changes', () {
      final a = facts();
      final b = facts(cueHeadline: 'Add 3 more sets of chest');
      expect(a['balanceScore'], b['balanceScore']);
      expect(a['sessionCount'], b['sessionCount']);
      expect(trainingExplainResetKey(a), isNot(trainingExplainResetKey(b)));
    });

    test('changes when the set count changes', () {
      expect(
        trainingExplainResetKey(facts()),
        isNot(trainingExplainResetKey(facts(setCount: 3))),
      );
    });

    test('changes when the window changes', () {
      expect(
        trainingExplainResetKey(facts()),
        isNot(trainingExplainResetKey(facts(
          windowDays: 7,
          windowLabel: 'Last full week',
        ))),
      );
    });

    test('still changes when balance / session count change (old inputs preserved)', () {
      expect(
        trainingExplainResetKey(facts()),
        isNot(trainingExplainResetKey(facts(balanceScore: 73))),
      );
      expect(
        trainingExplainResetKey(facts()),
        isNot(trainingExplainResetKey(facts(sessionCount: 5))),
      );
    });
  });
}
