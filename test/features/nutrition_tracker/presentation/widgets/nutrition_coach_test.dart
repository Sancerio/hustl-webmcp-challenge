import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/nutrition_coach.dart';

NutritionTargetPlan _plan({String mode = 'auto', String? rationale}) =>
    NutritionTargetPlan(
      weekStart: DateTime(2026, 1, 5),
      mode: mode,
      goal: 'lose',
      caloriesTarget: 2000,
      proteinTarget: 150,
      carbsTarget: 200,
      fatTarget: 60,
      rationale: rationale,
    );

void main() {
  group('nutritionCoachInsight', () {
    test('manual mode says coaching is off (neutral, no confidence)', () {
      final insight = nutritionCoachInsight(
        plan: _plan(mode: 'manual'),
        checkIn: null,
      );
      expect(insight, isNotNull);
      expect(insight!.headline, 'Coaching is off');
      expect(insight.tone, CoachTone.neutral);
      expect(insight.confidence, CoachConfidence.none);
    });

    test('auto mode with the check-in still loading returns null', () {
      expect(nutritionCoachInsight(plan: _plan(), checkIn: null), isNull);
    });

    test('calibrating when the estimator has no TDEE/window yet', () {
      final insight = nutritionCoachInsight(
        plan: _plan(),
        checkIn: const {
          'available': false,
          'why': {'confidence': 0},
          'coverage': {'daysWithCaloriesLogged': 3, 'weighInDays': 2},
        },
      );
      expect(insight!.headline, 'Getting to know you');
      expect(insight.confidence, CoachConfidence.building);
      expect(insight.tone, CoachTone.neutral);
      expect(insight.windowLabel, '3/7 days logged this week');
    });

    test(
      'targets changed surfaces a plain-language delta + Carbon-style why',
      () {
        var reviewed = false;
        final insight = nutritionCoachInsight(
          plan: _plan(),
          checkIn: const {
            'available': true,
            'why': {'tdeeKcal': 2150, 'windowDays': 21, 'confidence': 0.8},
            'coverage': {'daysWithCaloriesLogged': 7},
            'deltas': {'calories': 150},
          },
          onReviewCheckIn: () => reviewed = true,
        );
        expect(insight!.headline, 'Calories +150 this week');
        expect(insight.why, contains('2150 kcal'));
        expect(insight.why, contains('21-day trend'));
        expect(insight.tone, CoachTone.attention);
        expect(insight.confidence, CoachConfidence.high);
        expect(insight.windowLabel, '21-day trend');
        expect(insight.action, isNotNull);
        insight.action!.onTap();
        expect(reviewed, isTrue);
      },
    );

    test('no change reads as a positive, not a non-event', () {
      final insight = nutritionCoachInsight(
        plan: _plan(),
        checkIn: const {
          'available': true,
          'why': {'tdeeKcal': 2100, 'windowDays': 21, 'confidence': 0.7},
          'coverage': {'daysWithCaloriesLogged': 7},
          'deltas': {'calories': 0},
        },
      );
      expect(insight!.headline, 'You’re on track');
      expect(insight.tone, CoachTone.positive);
      expect(insight.why, contains('no change needed'));
    });
  });
}
