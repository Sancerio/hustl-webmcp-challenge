import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/food_log_csv_export_service.dart';

void main() {
  const exporter = FoodLogCsvExportService();

  const expectedHeader =
      'date,logged_at,food_name,brand,portion,serving_grams,calories,'
      'protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,source';

  FoodLogEntry entry({
    required String id,
    required DateTime date,
    required DateTime loggedAt,
    String? foodName,
    Food? food,
    String? portionLabel,
    double servingGrams = 100,
    double calories = 200,
    double protein = 10,
    double carbs = 20,
    double fat = 5,
    double? fiber,
    double? sugar,
    double? sodium,
    String source = 'self',
  }) => FoodLogEntry(
    id: id,
    date: date,
    loggedAt: loggedAt,
    servingGrams: servingGrams,
    calories: calories,
    proteinGrams: protein,
    carbsGrams: carbs,
    fatGrams: fat,
    fiberGrams: fiber,
    sugarGrams: sugar,
    sodiumMg: sodium,
    foodName: foodName,
    food: food,
    portionLabel: portionLabel,
    source: source,
  );

  test('happy path: header + one row per entry, sorted by date then time', () {
    final csv = exporter.buildCsv([
      entry(
        id: 'b',
        date: DateTime(2024, 7, 2),
        loggedAt: DateTime(2024, 7, 2, 12, 30),
        foodName: 'Chicken bowl',
        calories: 520.5,
      ),
      entry(
        id: 'a',
        date: DateTime(2024, 7, 1),
        loggedAt: DateTime(2024, 7, 1, 8, 0),
        food: const Food(id: 'f1', name: 'Oats', brand: 'QuakerCo'),
        portionLabel: '1 cup',
        fiber: 6,
        sugar: 1.25,
        sodium: 120,
      ),
    ]);

    final lines = csv.split('\n');
    expect(lines.first, expectedHeader);
    expect(lines, hasLength(3));
    // Oldest entry first despite input order; name falls back to food.name,
    // brand/portion/optional macros populated, grams/kcal unconverted.
    expect(
      lines[1],
      '2024-07-01,2024-07-01 08:00:00,Oats,QuakerCo,1 cup,100,200,10,20,5,'
      '6,1.25,120,self',
    );
    // Nullable fields export as empty strings.
    expect(
      lines[2],
      '2024-07-02,2024-07-02 12:30:00,Chicken bowl,,,100,520.5,10,20,5,,,,'
      'self',
    );
  });

  test('empty history exports just the header', () {
    expect(exporter.buildCsv(const []), expectedHeader);
  });

  test('names with commas and quotes are RFC-4180 quoted', () {
    final csv = exporter.buildCsv([
      entry(
        id: 'a',
        date: DateTime(2024, 7, 1),
        loggedAt: DateTime(2024, 7, 1, 9, 0),
        foodName: 'Chicken "spicy", grilled',
      ),
    ]);

    expect(csv, contains('"Chicken ""spicy"", grilled"'));
  });

  test('a multi-meal day keeps every entry, ordered by logged-at', () {
    final day = DateTime(2024, 7, 1);
    final csv = exporter.buildCsv([
      entry(id: 'lunch', date: day, loggedAt: DateTime(2024, 7, 1, 13, 0), foodName: 'Lunch'),
      entry(id: 'breakfast', date: day, loggedAt: DateTime(2024, 7, 1, 8, 0), foodName: 'Breakfast'),
      entry(id: 'dinner', date: day, loggedAt: DateTime(2024, 7, 1, 19, 30), foodName: 'Dinner'),
    ]);

    final names = csv
        .split('\n')
        .skip(1)
        .map((line) => line.split(',')[2])
        .toList();
    expect(names, ['Breakfast', 'Lunch', 'Dinner']);
  });

  test('file name is dated', () {
    expect(
      exporter.fileName(now: DateTime(2024, 7, 5)),
      'hustl-nutrition-20240705.csv',
    );
  });
}
