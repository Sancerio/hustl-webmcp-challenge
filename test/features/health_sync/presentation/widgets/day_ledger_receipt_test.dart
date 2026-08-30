import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/features/health_sync/domain/models/external_activity.dart';
import 'package:hustl_app/features/health_sync/domain/models/strain_ledger.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/day_ledger_receipt.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/recovery_band_tint.dart';

StrainLedger _fixtureLedger() => StrainLedger(
  strainScore: 14,
  ambientLoadPoints: 10.9,
  entries: [
    StrainLedgerEntry(
      id: 'ext-run',
      source: StrainSource.external,
      kind: ExternalActivityKind.run,
      label: 'Apple Watch',
      start: DateTime(2026, 7, 6, 7, 2),
      end: DateTime(2026, 7, 6, 7, 33),
      share: 0.1,
      loadPoints: 1.4,
    ),
    StrainLedgerEntry(
      id: 'hustl-push',
      source: StrainSource.hustl,
      kind: ExternalActivityKind.strengthTraining,
      label: 'Push day',
      start: DateTime(2026, 7, 6, 17, 10),
      end: DateTime(2026, 7, 6, 18, 14),
      share: 0.12,
      loadPoints: 1.7,
    ),
  ],
);

Future<void> _pump(WidgetTester tester, StrainLedger ledger) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: DayLedgerReceipt(ledger: ledger)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('DayLedgerReceipt', () {
    testWidgets('renders three itemized rows plus the strain total', (
      tester,
    ) async {
      await _pump(tester, _fixtureLedger());

      // Hustl session shows its own name; the external row shows a kind-derived
      // title with the prettified source in the "Kind · Source" sub-line.
      expect(find.text('Push day'), findsOneWidget);
      expect(find.text('Strength · Hustl'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Run · Apple Watch'), findsOneWidget);

      // Ambient remainder is itemized as its own row.
      expect(find.text('Ambient movement'), findsOneWidget);
      expect(find.text('Steps · everyday activity'), findsOneWidget);

      // Load-point column (1 dp), one per row.
      expect(find.text('1.4'), findsOneWidget);
      expect(find.text('1.7'), findsOneWidget);
      expect(find.text('10.9'), findsOneWidget);

      // Total row + honesty label + footnote, verbatim per spec.
      expect(find.byKey(const Key('dayLedgerTotal')), findsOneWidget);
      expect(find.text('Strain'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(
        find.text('load points, estimated from energy and duration'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Shares are estimates — sessions split the day’s measured load.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('displayed rows plus ambient sum exactly to the strain score', (
      tester,
    ) async {
      final ledger = _fixtureLedger();
      await _pump(tester, ledger);

      final displayedTenths =
          ledger.entries.fold<int>(
            0,
            (acc, e) => acc + (e.loadPoints * 10).round(),
          ) +
          (ledger.ambientLoadPoints * 10).round();
      expect(displayedTenths / 10, ledger.strainScore.toDouble());
    });

    testWidgets('omits the ambient row when there is no ambient remainder', (
      tester,
    ) async {
      final ledger = StrainLedger(
        strainScore: 6,
        ambientLoadPoints: 0,
        entries: [
          StrainLedgerEntry(
            id: 'hustl-push',
            source: StrainSource.hustl,
            kind: ExternalActivityKind.strengthTraining,
            label: 'Push day',
            start: DateTime(2026, 7, 6, 17, 10),
            end: DateTime(2026, 7, 6, 18, 14),
            share: 1,
            loadPoints: 6,
          ),
        ],
      );
      await _pump(tester, ledger);

      expect(find.text('Push day'), findsOneWidget);
      expect(find.text('Ambient movement'), findsNothing);
    });

    testWidgets('omits the typical sub-line when no typical strain is given', (
      tester,
    ) async {
      await _pump(tester, _fixtureLedger());
      expect(find.textContaining('typical'), findsNothing);
    });

    testWidgets(
      'an external other-kind entry with a preserved activity name shows '
      'the real name instead of "Workout"',
      (tester) async {
        final ledger = StrainLedger(
          strainScore: 6,
          ambientLoadPoints: 0,
          entries: [
            StrainLedgerEntry(
              id: 'ext-soccer',
              source: StrainSource.external,
              kind: ExternalActivityKind.other,
              label: "Limiardi's Apple Watch",
              start: DateTime(2026, 7, 6, 17, 10),
              end: DateTime(2026, 7, 6, 18, 14),
              share: 1,
              loadPoints: 6,
              activityName: 'Soccer',
            ),
          ],
        );
        await _pump(tester, ledger);

        expect(find.text('Soccer'), findsOneWidget);
        expect(find.text("Soccer · Limiardi's Apple Watch"), findsOneWidget);
        expect(find.text('Workout'), findsNothing);
      },
    );

    testWidgets(
      'an external other-kind entry without an activity name falls back to '
      '"Workout"',
      (tester) async {
        final ledger = StrainLedger(
          strainScore: 6,
          ambientLoadPoints: 0,
          entries: [
            StrainLedgerEntry(
              id: 'ext-unknown',
              source: StrainSource.external,
              kind: ExternalActivityKind.other,
              label: "Limiardi's Apple Watch",
              start: DateTime(2026, 7, 6, 17, 10),
              end: DateTime(2026, 7, 6, 18, 14),
              share: 1,
              loadPoints: 6,
            ),
          ],
        );
        await _pump(tester, ledger);

        expect(find.text('Workout'), findsOneWidget);
      },
    );

    testWidgets(
      'a recognized kind shows its real activity name, not the coarse label',
      (tester) async {
        // Pilates maps to the coarse `yoga` kind but must display "Pilates".
        final ledger = StrainLedger(
          strainScore: 6,
          ambientLoadPoints: 0,
          entries: [
            StrainLedgerEntry(
              id: 'ext-pilates',
              source: StrainSource.external,
              kind: ExternalActivityKind.yoga,
              label: 'Apple Watch',
              start: DateTime(2026, 7, 6, 17, 10),
              end: DateTime(2026, 7, 6, 18, 14),
              share: 1,
              loadPoints: 6,
              activityName: 'Pilates',
            ),
          ],
        );
        await _pump(tester, ledger);

        expect(find.text('Pilates'), findsOneWidget);
        expect(find.text('Pilates · Apple Watch'), findsOneWidget);
        expect(find.text('Yoga'), findsNothing);
      },
    );

    testWidgets(
      'an external with no activity name falls back to the coarse kind label',
      (tester) async {
        // No preserved name (e.g. HealthKit OTHER) -> the generic label.
        final ledger = StrainLedger(
          strainScore: 6,
          ambientLoadPoints: 0,
          entries: [
            StrainLedgerEntry(
              id: 'ext-run',
              source: StrainSource.external,
              kind: ExternalActivityKind.run,
              label: 'Strava',
              start: DateTime(2026, 7, 6, 17, 10),
              end: DateTime(2026, 7, 6, 18, 14),
              share: 1,
              loadPoints: 6,
            ),
          ],
        );
        await _pump(tester, ledger);

        expect(find.text('Run'), findsOneWidget);
        expect(find.text('Run · Strava'), findsOneWidget);
      },
    );

    testWidgets(
      'a Hustl entry never honors a stray activityName (source-gated)',
      (tester) async {
        // Hustl sessions must always show their kind label in the sub-line; a
        // malformed activityName must not render "Soccer · Hustl".
        final ledger = StrainLedger(
          strainScore: 6,
          ambientLoadPoints: 0,
          entries: [
            StrainLedgerEntry(
              id: 'hustl-push',
              source: StrainSource.hustl,
              kind: ExternalActivityKind.strengthTraining,
              label: 'Push day',
              start: DateTime(2026, 7, 6, 17, 10),
              end: DateTime(2026, 7, 6, 18, 14),
              share: 1,
              loadPoints: 6,
              activityName: 'Soccer',
            ),
          ],
        );
        await _pump(tester, ledger);

        expect(find.text('Push day'), findsOneWidget); // its own session name
        expect(find.text('Strength · Hustl'), findsOneWidget);
        expect(find.text('Soccer'), findsNothing);
      },
    );
  });

  group('DayLedgerReceipt activity glyphs', () {
    StrainLedger glyphFixtureLedger() => StrainLedger(
      strainScore: 20,
      ambientLoadPoints: 5,
      entries: [
        StrainLedgerEntry(
          id: 'ext-soccer',
          source: StrainSource.external,
          kind: ExternalActivityKind.other,
          label: 'Apple Watch',
          start: DateTime(2026, 7, 6, 9, 0),
          end: DateTime(2026, 7, 6, 10, 0),
          share: 0.3,
          loadPoints: 6,
          activityName: 'Soccer',
        ),
        StrainLedgerEntry(
          id: 'ext-run',
          source: StrainSource.external,
          kind: ExternalActivityKind.run,
          label: 'Strava',
          start: DateTime(2026, 7, 6, 7, 0),
          end: DateTime(2026, 7, 6, 7, 30),
          share: 0.2,
          loadPoints: 4,
        ),
        StrainLedgerEntry(
          id: 'hustl-push',
          source: StrainSource.hustl,
          kind: ExternalActivityKind.strengthTraining,
          label: 'Push day',
          start: DateTime(2026, 7, 6, 17, 0),
          end: DateTime(2026, 7, 6, 18, 0),
          share: 0.25,
          loadPoints: 5,
        ),
      ],
    );

    testWidgets('shows a source-tinted sport glyph for a soccer entry', (
      tester,
    ) async {
      await _pump(tester, glyphFixtureLedger());

      expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
      final soccerIcon = tester.widget<Icon>(find.byIcon(Icons.sports_soccer));
      expect(soccerIcon.color, kExternalWorkoutTint);
    });

    testWidgets('shows the run glyph for a run-kind entry', (tester) async {
      await _pump(tester, glyphFixtureLedger());

      expect(find.byIcon(Icons.directions_run), findsOneWidget);
      final runIcon = tester.widget<Icon>(find.byIcon(Icons.directions_run));
      expect(runIcon.color, kExternalWorkoutTint);
    });

    testWidgets('shows the emerald-tinted strength glyph for a Hustl entry', (
      tester,
    ) async {
      await _pump(tester, glyphFixtureLedger());

      expect(find.byIcon(Icons.fitness_center), findsOneWidget);
      final hustlIcon = tester.widget<Icon>(find.byIcon(Icons.fitness_center));
      expect(hustlIcon.color, AppColors.accentEmeraldGreen);
    });

    testWidgets('shows the walk glyph for the ambient row', (tester) async {
      await _pump(tester, glyphFixtureLedger());

      expect(find.byIcon(Icons.directions_walk), findsOneWidget);
      // Ambient is slate: exactly the theme's onSurfaceVariant, never a source
      // tint (nor any other stray color).
      final walk = tester.widget<Icon>(find.byIcon(Icons.directions_walk));
      final slate = Theme.of(
        tester.element(find.byType(DayLedgerReceipt)),
      ).colorScheme.onSurfaceVariant;
      expect(walk.color, slate);
    });

    StrainLedger otherLedger({String? activityName}) => StrainLedger(
      strainScore: 6,
      ambientLoadPoints: 0,
      entries: [
        StrainLedgerEntry(
          id: 'ext-other',
          source: StrainSource.external,
          kind: ExternalActivityKind.other,
          label: 'Apple Watch',
          start: DateTime(2026, 7, 6, 9, 0),
          end: DateTime(2026, 7, 6, 10, 0),
          share: 1,
          loadPoints: 6,
          activityName: activityName,
        ),
      ],
    );

    testWidgets(
      'an unknown named sport falls back to the generic sport glyph',
      (tester) async {
        await _pump(tester, otherLedger(activityName: 'Fencing'));

        expect(find.byIcon(Icons.sports), findsOneWidget);
        expect(find.text('Fencing'), findsOneWidget);
      },
    );

    testWidgets('a multi-word sport name normalizes to its glyph', (
      tester,
    ) async {
      // Exercises token normalization (spaces stripped), not just casing.
      await _pump(tester, otherLedger(activityName: 'Table tennis'));

      expect(find.byIcon(Icons.sports_tennis), findsOneWidget);
    });

    testWidgets('a common gym-cardio type gets a fitting (non-whistle) glyph', (
      tester,
    ) async {
      await _pump(tester, otherLedger(activityName: 'Stair climbing'));

      expect(find.byIcon(Icons.stairs), findsOneWidget);
      expect(find.byIcon(Icons.sports), findsNothing);
    });

    testWidgets(
      'a nameless "other" workout uses the SAME neutral sport glyph (not a '
      'dumbbell)',
      (tester) async {
        await _pump(tester, otherLedger());

        expect(find.byIcon(Icons.sports), findsOneWidget);
        expect(find.byIcon(Icons.fitness_center), findsNothing);
        expect(find.text('Workout'), findsOneWidget);
      },
    );
  });

  group('prettySourceName', () {
    test('maps a known reverse-domain package id to its brand name', () {
      expect(prettySourceName('com.strava'), 'Strava');
      expect(prettySourceName('com.sec.android.app.shealth'), 'Samsung Health');
      expect(prettySourceName('com.google.android.apps.fitness'), 'Google Fit');
    });

    test('leaves an already-friendly source name unchanged', () {
      expect(prettySourceName('Apple Watch'), 'Apple Watch');
      expect(prettySourceName('Strava'), 'Strava');
    });

    test('title-cases the last segment of an unknown reverse-domain id', () {
      expect(prettySourceName('com.example.flow'), 'Flow');
    });

    test('falls back to Unknown for an empty source', () {
      expect(prettySourceName('   '), 'Unknown');
    });
  });
}
