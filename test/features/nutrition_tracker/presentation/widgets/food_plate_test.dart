import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/food_entry_avatar.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/food_plate.dart';

FoodLogEntry _entry({
  required double grams,
  double calories = 100,
  double protein = 10,
  double carbs = 20,
  double fat = 5,
  double? fiber,
  double? sugar,
  double? sodium,
}) {
  return FoodLogEntry(
    id: 'e-$grams',
    date: DateTime(2026, 1, 23),
    loggedAt: DateTime(2026, 1, 23, 8),
    servingGrams: grams,
    calories: calories,
    proteinGrams: protein,
    carbsGrams: carbs,
    fatGrams: fat,
    fiberGrams: fiber,
    sugarGrams: sugar,
    sodiumMg: sodium,
    foodName: 'Food $grams',
  );
}

/// A named entry with an explicit id, so the cluster's per-disc keys stay unique
/// when several entries are staged in one test.
FoodLogEntry _named(String id, String name) {
  return FoodLogEntry(
    id: id,
    date: DateTime(2026, 1, 23),
    loggedAt: DateTime(2026, 1, 23, 8),
    servingGrams: 100,
    calories: 100,
    proteinGrams: 10,
    carbsGrams: 20,
    fatGrams: 5,
    foodName: name,
  );
}

void main() {
  group('plateTotals', () {
    test('zeroes for an empty plate', () {
      final t = plateTotals(const []);
      expect(t.calories, 0);
      expect(t.protein, 0);
      expect(t.carbs, 0);
      expect(t.fat, 0);
    });

    test('sums calories and macros across entries', () {
      final t = plateTotals([
        _entry(grams: 100, calories: 100, protein: 10, carbs: 20, fat: 5),
        _entry(grams: 50, calories: 50, protein: 5, carbs: 8, fat: 2),
      ]);
      expect(t.calories, 150);
      expect(t.protein, 15);
      expect(t.carbs, 28);
      expect(t.fat, 7);
    });
  });

  group('rescaleEntryToGrams', () {
    test('scales calories and macros proportionally', () {
      final e = _entry(
        grams: 100,
        calories: 200,
        protein: 20,
        carbs: 30,
        fat: 10,
        fiber: 4,
        sugar: 6,
        sodium: 80,
      );
      final scaled = rescaleEntryToGrams(e, 50);
      expect(scaled.servingGrams, 50);
      expect(scaled.calories, 100);
      expect(scaled.proteinGrams, 10);
      expect(scaled.carbsGrams, 15);
      expect(scaled.fatGrams, 5);
      expect(scaled.fiberGrams, 2);
      expect(scaled.sugarGrams, 3);
      expect(scaled.sodiumMg, 40);
    });

    test('leaves null sub-macros null after rescaling', () {
      final scaled = rescaleEntryToGrams(_entry(grams: 100), 200);
      expect(scaled.fiberGrams, isNull);
      expect(scaled.sugarGrams, isNull);
      expect(scaled.sodiumMg, isNull);
    });

    test('guards a non-positive old serving with a factor of 1', () {
      final e = _entry(grams: 0, calories: 120, protein: 12);
      final scaled = rescaleEntryToGrams(e, 80);
      // No ratio to apply: grams update, macros stay put.
      expect(scaled.servingGrams, 80);
      expect(scaled.calories, 120);
      expect(scaled.proteinGrams, 12);
    });
  });

  group('PlatePreviewCluster', () {
    Future<void> pump(WidgetTester tester, List<FoodLogEntry> entries) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: PlatePreviewCluster(entries: entries)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders one avatar per entry below the cap (no +K)', (
      tester,
    ) async {
      await pump(tester, [_named('a', 'Apple'), _named('b', 'Banana')]);

      // Two selected foods -> a two-avatar plate preview, no overflow chip.
      expect(find.byType(FoodEntryAvatar), findsNWidgets(2));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('caps the avatars and shows a +K overflow chip', (
      tester,
    ) async {
      await pump(tester, [
        _named('a', 'Apple'),
        _named('b', 'Banana'),
        _named('c', 'Carrot'),
        _named('d', 'Donut'),
        _named('e', 'Egg'),
        _named('f', 'Fish'),
      ]);

      // Six staged with maxVisible: 4 -> 3 avatars + a "+3" remainder chip.
      expect(find.byType(FoodEntryAvatar), findsNWidgets(3));
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('updates live as an item is removed', (tester) async {
      final entries = [
        _named('a', 'Apple'),
        _named('b', 'Banana'),
        _named('c', 'Carrot'),
      ];

      Widget host(List<FoodLogEntry> e) => MaterialApp(
        home: Scaffold(body: Center(child: PlatePreviewCluster(entries: e))),
      );

      await tester.pumpWidget(host(entries));
      await tester.pumpAndSettle();
      expect(find.byType(FoodEntryAvatar), findsNWidgets(3));

      // Remove one item and rebuild: the cluster drops to two avatars.
      await tester.pumpWidget(host(entries.sublist(0, 2)));
      await tester.pumpAndSettle();
      expect(find.byType(FoodEntryAvatar), findsNWidgets(2));
    });

    testWidgets('renders nothing for an empty selection', (tester) async {
      await pump(tester, const []);
      expect(find.byType(FoodEntryAvatar), findsNothing);
      expect(find.byType(PlatePreviewCluster), findsOneWidget);
    });

    testWidgets('every disc (incl. ring inset) fits within the cluster box', (
      tester,
    ) async {
      // Overflow case: the front-most ring is the one most at risk of painting
      // past the SizedBox / being clipped by PlateBar's ClipRect. If the cluster
      // is laid out from the bare avatar diameter instead of the ring diameter,
      // the trailing ring overshoots width by ~4px and height by ~2px.
      await pump(tester, [
        _named('a', 'Apple'),
        _named('b', 'Banana'),
        _named('c', 'Carrot'),
        _named('d', 'Donut'),
        _named('e', 'Egg'),
      ]);

      // The cluster's allocated box is the SizedBox just inside the cluster.
      final clusterBox = tester.getRect(
        find
            .descendant(
              of: find.byType(PlatePreviewCluster),
              matching: find.byType(SizedBox),
            )
            .first,
      );

      // Each painted disc is a ringed Container (avatar/chip + the ring inset).
      // Every one of them must sit fully inside the cluster's allocated box, or
      // it gets clipped inside PlateBar's ClipRect even with room to spare.
      final discs = find.descendant(
        of: find.byType(PlatePreviewCluster),
        matching: find.byType(Container),
      );
      expect(discs, findsWidgets);

      const epsilon = 0.01;
      for (final disc in discs.evaluate()) {
        final discBox = tester.getRect(find.byWidget(disc.widget));
        expect(
          discBox.left,
          greaterThanOrEqualTo(clusterBox.left - epsilon),
          reason: 'disc paints past the cluster left edge (clips)',
        );
        expect(
          discBox.right,
          lessThanOrEqualTo(clusterBox.right + epsilon),
          reason: 'disc paints past the cluster right edge (clips)',
        );
        expect(
          discBox.top,
          greaterThanOrEqualTo(clusterBox.top - epsilon),
          reason: 'disc paints past the cluster top edge (clips)',
        );
        expect(
          discBox.bottom,
          lessThanOrEqualTo(clusterBox.bottom + epsilon),
          reason: 'disc paints past the cluster bottom edge (clips)',
        );
      }
    });
  });
}
