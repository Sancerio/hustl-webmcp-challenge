import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/core/widgets/coach_card.dart';
import 'package:hustl_app/core/widgets/coach_intro_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester, CoachInsight insight) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: CoachCard(insight: insight)),
      ),
    );
  }

  testWidgets('renders the eyebrow, headline, why and confidence cue', (
    tester,
  ) async {
    await pump(
      tester,
      const CoachInsight(
        headline: 'Add 3 chest sets this week',
        why: 'Chest is 45% of your goal over the last 4 weeks.',
        confidence: CoachConfidence.high,
        windowLabel: 'last 4 weeks',
        tone: CoachTone.attention,
      ),
    );

    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('Add 3 chest sets this week'), findsOneWidget);
    expect(find.textContaining('Chest is 45%'), findsOneWidget);
    expect(find.text('High confidence · last 4 weeks'), findsOneWidget);
  });

  testWidgets('hides the confidence row when confidence is none', (
    tester,
  ) async {
    await pump(tester, const CoachInsight(headline: 'Headline', why: 'Why'));
    expect(find.textContaining('confidence'), findsNothing);
  });

  testWidgets('the action button fires its callback', (tester) async {
    var tapped = false;
    await pump(
      tester,
      CoachInsight(
        headline: 'Headline',
        why: 'Why',
        action: CoachAction(
          label: 'Show me exercises',
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.text('Show me exercises'), findsOneWidget);
    await tester.tap(find.text('Show me exercises'));
    expect(tapped, isTrue);
  });

  group('first-time generic Coach auto-intro', () {
    const insight = CoachInsight(headline: 'Headline', why: 'Why');

    setUp(() {
      // First-time user: the persisted "seen" flag is unset, and the in-memory
      // once-per-session guard is reset so each case starts fresh.
      SharedPreferences.setMockInitialValues({});
      debugResetCoachIntroSessionGuard();
    });

    testWidgets(
      'a card WITHOUT onInfoTap auto-shows the generic intro for a first-time '
      'user',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CoachCard(insight: insight))),
        );
        // Flush the post-frame callback + the async prefs read it triggers.
        await tester.pumpAndSettle();

        // The shared "Meet your Coach" explainer surfaced proactively.
        expect(find.text('Meet your Coach'), findsOneWidget);
      },
    );

    testWidgets(
      'a card WITH onInfoTap does NOT auto-show the generic intro for a '
      'first-time user',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoachCard(insight: insight, onInfoTap: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The rec-specific (i) affordance owns the explainer on this surface, so
        // the generic auto-intro must stay suppressed.
        expect(find.text('Meet your Coach'), findsNothing);
      },
    );
  });
}
