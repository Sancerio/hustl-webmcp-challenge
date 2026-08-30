import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/coach_card.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/insights_coach_recommendations.dart';

/// Pumps the recommendations widget inside a GoRouter so action taps exercise
/// real navigation (the deep-link is the point — not advisory copy).
Future<void> _pumpRecs(
  WidgetTester tester,
  List recs, {
  bool momentumOptIn = false,
  bool coachExplainsOptIn = false,
  Future<String?> Function()? fetchNarrative,
}) async {
  final router = GoRouter(
    initialLocation: '/insights',
    routes: [
      GoRoute(
        path: '/insights',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: InsightsCoachRecommendations(
              recommendations: recs,
              momentumOptIn: momentumOptIn,
              coachExplainsOptIn: coachExplainsOptIn,
              fetchNarrative: fetchNarrative,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/nutrition/strategy',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('strategy'))),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  // Flush the chart/coach entrance + the coach-intro post-frame (a no-op
  // without a prefs mock).
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('InsightsCoachRecommendations', () {
    testWidgets('renders one CoachCard per recommendation', (tester) async {
      await _pumpRecs(tester, const [
        {
          'key': 'energy_trend',
          'headline': 'In a slight deficit',
          'why': 'Avg intake 1950 vs ~2400 kcal TDEE over the last 10 days.',
          'tone': 'neutral',
          'confidence': 'high',
          'windowLabel': '10-day average',
        },
        {
          'key': 'protein',
          'headline': 'Protein is on point',
          'why': 'Averaging 150 g over the week.',
          'tone': 'positive',
          'confidence': 'medium',
        },
      ]);

      expect(find.byType(CoachCard), findsNWidgets(2));
      expect(find.text('In a slight deficit'), findsOneWidget);
      expect(find.text('Protein is on point'), findsOneWidget);
      // Confidence cue + window label render from the map.
      expect(find.text('High confidence · 10-day average'), findsOneWidget);
    });

    testWidgets('an action taps through to its route via push', (tester) async {
      await _pumpRecs(tester, const [
        {
          'key': 'energy_trend',
          'headline': 'In a slight deficit',
          'why': 'Avg intake below TDEE.',
          'tone': 'neutral',
          'confidence': 'high',
          'action': {'label': 'Adjust targets', 'route': '/nutrition/strategy'},
        },
      ]);

      expect(find.text('Adjust targets'), findsOneWidget);
      await tester.tap(find.text('Adjust targets'));
      await tester.pumpAndSettle();

      // The pushed destination renders — the action is a real deep-link, not
      // advisory copy.
      expect(tester.takeException(), isNull);
      expect(find.text('strategy'), findsOneWidget);
    });

    testWidgets('an unknown route renders no action affordance', (
      tester,
    ) async {
      await _pumpRecs(tester, const [
        {
          'key': 'mystery',
          'headline': 'Something happened',
          'why': 'But the drill-down does not exist.',
          'tone': 'neutral',
          'confidence': 'building',
          'action': {'label': 'Open the void', 'route': '/nope'},
        },
      ]);

      expect(find.byType(CoachCard), findsOneWidget);
      // The guard drops a route that is not one of the four known surfaces.
      expect(find.text('Open the void'), findsNothing);
    });

    testWidgets('an empty list renders nothing', (tester) async {
      await _pumpRecs(tester, const []);
      expect(find.byType(CoachCard), findsNothing);
    });

    testWidgets(
      'behavioral_momentum is hidden when not opted in (belt-and-suspenders gate)',
      (tester) async {
        await _pumpRecs(tester, const [
          {
            'key': 'energy_trend',
            'headline': 'In a slight deficit',
            'why': 'Avg intake below TDEE.',
            'tone': 'neutral',
            'confidence': 'high',
          },
          {
            'key': 'behavioral_momentum',
            'headline': 'On a check-in streak — habits locking in',
            'why': 'You applied your check-in 3 weeks running.',
            'tone': 'positive',
            'confidence': 'medium',
          },
        ]);

        // Only the non-opt-in rec renders; the momentum card is filtered out.
        expect(find.byType(CoachCard), findsOneWidget);
        expect(find.text('In a slight deficit'), findsOneWidget);
        expect(
          find.text('On a check-in streak — habits locking in'),
          findsNothing,
        );
      },
    );

    const oneRec = [
      {
        'key': 'energy_trend',
        'headline': 'In a slight deficit',
        'why': 'Avg intake below TDEE.',
        'tone': 'neutral',
        'confidence': 'high',
      },
    ];

    testWidgets(
      'no "Explain my numbers" affordance when coach-explains is off',
      (tester) async {
        await _pumpRecs(tester, oneRec);
        expect(find.text('Explain my numbers'), findsNothing);
      },
    );

    testWidgets(
      'opted in: tapping "Explain my numbers" fetches and renders the note',
      (tester) async {
        var calls = 0;
        await _pumpRecs(
          tester,
          oneRec,
          coachExplainsOptIn: true,
          fetchNarrative: () async {
            calls++;
            return 'You averaged 1950 kcal — keep nudging protein up.';
          },
        );

        expect(find.text('Explain my numbers'), findsOneWidget);
        await tester.tap(find.text('Explain my numbers'));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(
          find.text('You averaged 1950 kcal — keep nudging protein up.'),
          findsOneWidget,
        );
        // The deterministic card is unchanged and still present.
        expect(find.byType(CoachCard), findsOneWidget);
      },
    );

    testWidgets(
      'opted in: a null narrative shows the inline "keep logging" line (cards stand alone)',
      (tester) async {
        await _pumpRecs(
          tester,
          oneRec,
          coachExplainsOptIn: true,
          fetchNarrative: () async => null,
        );

        await tester.tap(find.text('Explain my numbers'));
        await tester.pumpAndSettle();

        // After a null result the affordance is gone and, instead of snapping
        // back to nothing, a brief inline line is shown so the loading state
        // doesn't just vanish. The card is untouched.
        expect(find.text('Explain my numbers'), findsNothing);
        expect(
          find.text('Not enough logged data to explain yet — keep logging.'),
          findsOneWidget,
        );
        expect(find.byType(CoachCard), findsOneWidget);
      },
    );

    testWidgets(
      'opted in: an empty-string narrative also shows the inline line',
      (tester) async {
        await _pumpRecs(
          tester,
          oneRec,
          coachExplainsOptIn: true,
          fetchNarrative: () async => '',
        );

        await tester.tap(find.text('Explain my numbers'));
        await tester.pumpAndSettle();

        expect(
          find.text('Not enough logged data to explain yet — keep logging.'),
          findsOneWidget,
        );
        expect(find.byType(CoachCard), findsOneWidget);
      },
    );

    testWidgets(
      'opted in: switching inputs resets a previously fetched narrative',
      (tester) async {
        // A live host that can swap the recommendations the widget receives —
        // mirrors the insights screen switching the range / refetching recs.
        // Swapping in place keeps the same State element so didUpdateWidget fires
        // (a fresh pumpWidget would lose the state we are asserting about).
        var recs = const [
          {
            'key': 'energy_trend',
            'headline': 'Day-10 deficit',
            'why': 'Avg intake below TDEE over 10 days.',
            'tone': 'neutral',
            'confidence': 'high',
          },
        ];
        late void Function(void Function()) hostSetState;

        final router = GoRouter(
          initialLocation: '/insights',
          routes: [
            GoRoute(
              path: '/insights',
              builder: (context, state) => Scaffold(
                body: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      hostSetState = setState;
                      return InsightsCoachRecommendations(
                        recommendations: recs,
                        coachExplainsOptIn: true,
                        fetchNarrative: () async =>
                            'You averaged 1950 kcal over 10 days.',
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump(const Duration(milliseconds: 400));

        // Fetch and render the note for the day-10 numbers.
        await tester.tap(find.text('Explain my numbers'));
        await tester.pumpAndSettle();
        expect(
          find.text('You averaged 1950 kcal over 10 days.'),
          findsOneWidget,
        );

        // Switch the range: new recommendations flow in (content differs).
        hostSetState(() {
          recs = const [
            {
              'key': 'energy_trend',
              'headline': 'Day-30 surplus',
              'why': 'Avg intake above TDEE over 30 days.',
              'tone': 'attention',
              'confidence': 'high',
            },
          ];
        });
        await tester.pumpAndSettle();

        // The stale note is gone and the affordance is back — the narrative
        // reset to its initial state instead of hanging above the fresh card.
        expect(find.text('You averaged 1950 kcal over 10 days.'), findsNothing);
        expect(find.text('Explain my numbers'), findsOneWidget);
        // The fresh card rendered (and is the only one).
        expect(find.text('Day-30 surplus'), findsOneWidget);
        expect(find.byType(CoachCard), findsOneWidget);
      },
    );

    testWidgets(
      'opted in: an explain that resolves after an input change is discarded',
      (tester) async {
        // Hold the fetch open so we can switch inputs WHILE it is in flight, then
        // resolve it — the late note must not paint over the fresh card.
        final completer = Completer<String?>();
        var recs = const [
          {
            'key': 'energy_trend',
            'headline': 'Day-10 deficit',
            'why': 'Avg intake below TDEE over 10 days.',
            'tone': 'neutral',
            'confidence': 'high',
          },
        ];
        late void Function(void Function()) hostSetState;

        final router = GoRouter(
          initialLocation: '/insights',
          routes: [
            GoRoute(
              path: '/insights',
              builder: (context, state) => Scaffold(
                body: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      hostSetState = setState;
                      return InsightsCoachRecommendations(
                        recommendations: recs,
                        coachExplainsOptIn: true,
                        fetchNarrative: () => completer.future,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump(const Duration(milliseconds: 400));

        // Kick off the (still-pending) explain request.
        await tester.tap(find.text('Explain my numbers'));
        await tester.pump();

        // Switch the range while the fetch is in flight.
        hostSetState(() {
          recs = const [
            {
              'key': 'energy_trend',
              'headline': 'Day-30 surplus',
              'why': 'Avg intake above TDEE over 30 days.',
              'tone': 'attention',
              'confidence': 'high',
            },
          ];
        });
        await tester.pump();

        // The stale fetch resolves AFTER the input change — it must be dropped.
        completer.complete('You averaged 1950 kcal over 10 days.');
        await tester.pumpAndSettle();

        expect(find.text('You averaged 1950 kcal over 10 days.'), findsNothing);
        expect(find.text('Explain my numbers'), findsOneWidget);
        expect(find.text('Day-30 surplus'), findsOneWidget);
      },
    );

    testWidgets('behavioral_momentum renders when opted in', (tester) async {
      await _pumpRecs(
        tester,
        const [
          {
            'key': 'behavioral_momentum',
            'headline': 'On a check-in streak — habits locking in',
            'why': 'You applied your check-in 3 weeks running.',
            'tone': 'positive',
            'confidence': 'medium',
          },
        ],
        momentumOptIn: true,
      );

      expect(find.byType(CoachCard), findsOneWidget);
      expect(
        find.text('On a check-in streak — habits locking in'),
        findsOneWidget,
      );
    });
  });
}
