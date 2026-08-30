import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/rec_detail_sheet.dart';

/// Pumps [RecDetailSheet] inside a GoRouter so its action exercises real
/// navigation (the deep-link is the point) and `context.pop()` has a route to
/// dismiss.
Future<void> _pumpSheet(WidgetTester tester, Map rec) async {
  final router = GoRouter(
    initialLocation: '/insights',
    routes: [
      GoRoute(
        path: '/insights',
        builder: (context, state) => Scaffold(body: RecDetailSheet(rec: rec)),
      ),
      GoRoute(
        path: '/nutrition/strategy',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('strategy'))),
      ),
      GoRoute(
        path: '/nutrition/weight',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('weight'))),
      ),
      GoRoute(
        path: '/add-food',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('add-food'))),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RecDetailSheet', () {
    const energyTrend = {
      'key': 'energy_trend',
      'headline': 'In a slight deficit',
      'why': 'Avg intake 1950 vs ~2400 kcal TDEE over the last 10 days.',
      'tone': 'neutral',
      'confidence': 'high',
      'windowLabel': '10-day average',
      'action': {'label': 'Adjust targets', 'route': '/nutrition/strategy'},
    };

    const proteinLow = {
      'key': 'protein_low',
      'headline': 'Protein trending low',
      'why':
          'Averaging 110 g vs your ~150 g target over 8 logged days — '
          'about 40 g/day short.',
      'tone': 'attention',
      'confidence': 'building',
      'windowLabel': '8 days logged',
      'action': {'label': 'Adjust targets', 'route': '/nutrition/strategy'},
    };

    const weightPace = {
      'key': 'weight_pace',
      'headline': 'On pace for −0.4 kg/week',
      'why': 'Based on your intake vs TDEE and weight trend.',
      'tone': 'positive',
      'confidence': 'high',
      'windowLabel': '10-day trend',
      'action': {'label': 'View weight', 'route': '/nutrition/weight'},
    };

    testWidgets('energy_trend renders headline, data and confidence', (
      tester,
    ) async {
      await _pumpSheet(tester, energyTrend);

      expect(find.text('In a slight deficit'), findsOneWidget);
      // The real numbers (the rec why) are shown as the evidence.
      expect(find.textContaining('Avg intake 1950'), findsOneWidget);
      // Confidence explainer ties the tier + window to a plain-language line.
      expect(
        find.textContaining('we have seen enough to trust this'),
        findsOneWidget,
      );
      expect(find.textContaining('10-day average'), findsOneWidget);
    });

    testWidgets('the logic expander reveals the threshold copy', (
      tester,
    ) async {
      await _pumpSheet(tester, energyTrend);

      // Collapsed by default — the threshold detail is hidden.
      expect(find.textContaining('within about 75 kcal'), findsNothing);
      await tester.tap(find.text('How we calculate this'));
      await tester.pumpAndSettle();
      expect(find.textContaining('about 75 kcal'), findsOneWidget);
    });

    testWidgets('protein_low shows its keyed logic and building confidence', (
      tester,
    ) async {
      await _pumpSheet(tester, proteinLow);

      expect(find.text('Protein trending low'), findsOneWidget);
      expect(find.textContaining('check back in a few days'), findsOneWidget);
      await tester.tap(find.text('How we calculate this'));
      await tester.pumpAndSettle();
      expect(find.textContaining('more than 10% under'), findsOneWidget);
    });

    testWidgets('weight_pace renders without error', (tester) async {
      await _pumpSheet(tester, weightPace);

      expect(find.text('On pace for −0.4 kg/week'), findsOneWidget);
      await tester.tap(find.text('How we calculate this'));
      await tester.pumpAndSettle();
      expect(find.textContaining('7,700 kcal per kg'), findsOneWidget);
    });

    const missedLogging = {
      'key': 'missed_logging',
      'headline': 'You trained but skipped logging',
      'why':
          'You completed 4 workouts in the last 7 days but logged food on '
          'only 2. Logging on training days lets the coach see your real '
          'energy needs.',
      'tone': 'neutral',
      'confidence': 'medium',
      'windowLabel': 'last 7 days',
      'action': {'label': 'Log today', 'route': '/add-food'},
    };

    testWidgets('missed_logging shows its cross-domain keyed logic', (
      tester,
    ) async {
      await _pumpSheet(tester, missedLogging);

      expect(find.text('You trained but skipped logging'), findsOneWidget);
      // Generic fallback must NOT be used — the keyed logic renders instead.
      expect(
        find.textContaining('drawn from the numbers you log'),
        findsNothing,
      );
      await tester.tap(find.text('How we calculate this'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'how many days you completed a workout in the last 7 days',
        ),
        findsOneWidget,
      );
    });

    testWidgets('missed_logging deep-links to /add-food', (tester) async {
      await _pumpSheet(tester, missedLogging);

      expect(find.text('Log today'), findsOneWidget);
      await tester.tap(find.text('Log today'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('add-food'), findsOneWidget);
    });

    testWidgets('an unknown key falls back to a generic explanation', (
      tester,
    ) async {
      await _pumpSheet(tester, const {
        'key': 'mystery_future_rec',
        'headline': 'Something new',
        'why': 'A future signal with the user numbers inline.',
        'tone': 'neutral',
        'confidence': 'medium',
      });

      expect(find.text('Something new'), findsOneWidget);
      await tester.tap(find.text('How we calculate this'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('drawn from the numbers you log'),
        findsOneWidget,
      );
    });

    testWidgets('the action deep-links through to its route', (tester) async {
      await _pumpSheet(tester, weightPace);

      expect(find.text('View weight'), findsOneWidget);
      await tester.tap(find.text('View weight'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The sheet dismissed and the deep-link destination rendered.
      expect(find.text('weight'), findsOneWidget);
    });

    testWidgets('missing fields render gracefully with a fallback CTA', (
      tester,
    ) async {
      await _pumpSheet(tester, const {});

      // Null-safe: no headline/why/action still renders a coherent sheet.
      expect(find.text('Coach insight'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
