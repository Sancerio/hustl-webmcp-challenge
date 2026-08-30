import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/energy_balance_card.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/energy_compare_toggle.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/energy_verdict.dart';

void main() {
  group('energyVerdictInsight (TDEE honesty)', () {
    test('with no TDEE it compares to target and stays "building"', () {
      final insight = energyVerdictInsight(
        avgIntake: 2050,
        avgTarget: 2200,
        avgTdee: null,
        rangeDays: 14,
      );
      // Honest: never claims a TDEE comparison it doesn't have.
      expect(insight.why, contains('target'));
      expect(insight.why, isNot(contains('TDEE')));
      expect(insight.confidence, CoachConfidence.building);
      expect(insight.windowLabel, 'TDEE still calibrating');
      // Adherence-neutral: a gap to target is information, never an alarm.
      expect(insight.tone, CoachTone.neutral);
    });

    test('with a TDEE estimate it compares to TDEE at high confidence', () {
      final insight = energyVerdictInsight(
        avgIntake: 2050,
        avgTarget: 2200,
        avgTdee: 2300,
        rangeDays: 14,
      );
      expect(insight.why, contains('TDEE'));
      expect(insight.confidence, CoachConfidence.high);
      expect(insight.windowLabel, '14-day average');
      expect(insight.tone, CoachTone.neutral);
    });
  });

  group('EnergyCompareToggle', () {
    testWidgets('disables the TDEE segment when there is no TDEE', (
      tester,
    ) async {
      bool? toggled;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EnergyCompareToggle(
                // The stored flag asks for TDEE, but there is none yet.
                compareToExpenditure: true,
                hasTdee: false,
                onToggle: (v) => toggled = v,
              ),
            ),
          ),
        ),
      );

      // The "No TDEE yet" caption explains why TDEE is unavailable.
      expect(find.text('No TDEE yet'), findsOneWidget);

      // Tapping the disabled TDEE segment does nothing.
      await tester.tap(find.text('TDEE'));
      await tester.pump();
      expect(toggled, isNull);

      // Target still works.
      await tester.tap(find.text('Target'));
      await tester.pump();
      expect(toggled, isFalse);
    });

    testWidgets('enables the TDEE segment once a TDEE estimate exists', (
      tester,
    ) async {
      bool? toggled;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EnergyCompareToggle(
                compareToExpenditure: false,
                hasTdee: true,
                onToggle: (v) => toggled = v,
              ),
            ),
          ),
        ),
      );

      expect(find.text('No TDEE yet'), findsNothing);
      await tester.tap(find.text('TDEE'));
      await tester.pump();
      expect(toggled, isTrue);
    });
  });

  group('InsightsEnergyBalanceCard', () {
    testWidgets('stays on Target — no TDEE reference — when there is no TDEE', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InsightsEnergyBalanceCard(
                energyBalance: const {
                  'days': [
                    {
                      'date': '2026-06-10',
                      'intakeCalories': 2000,
                      'targetCalories': 2200,
                    },
                    {
                      'date': '2026-06-11',
                      'intakeCalories': 2100,
                      'targetCalories': 2200,
                    },
                  ],
                  'averages': {
                    'intakeCalories': 2050,
                    'targetCalories': 2200,
                    'diffVsTarget': -150,
                  },
                },
                // Flag asks for TDEE; with no TDEE the card must ignore it.
                compareToExpenditure: true,
                onToggleCompare: (_) {},
              ),
            ),
          ),
        ),
      );
      // Flush the chart's entrance animation without waiting on the
      // coach-intro post-frame (which is a no-op without a prefs mock).
      await tester.pump(const Duration(milliseconds: 400));

      // The comparison stays on Target: the reference line, the stat row and
      // the toggle all read Target, never a silently-mislabelled TDEE.
      expect(find.text('No TDEE yet'), findsOneWidget);
      expect(find.text('Avg Target'), findsOneWidget);
      expect(find.text('Avg TDEE'), findsNothing);
    });
  });
}
