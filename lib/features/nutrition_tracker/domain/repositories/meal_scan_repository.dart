import 'dart:typed_data';

import '../models/meal_scan_result.dart';

abstract class MealScanRepository {
  Future<MealScanResult> scanMealPhoto({
    required Uint8List imageBytes,
    required String mimeType,
    String? notes,
    String? restaurant,
    String? locale,
  });

  Future<MealScanResult> describeMeal({
    required String text,
    String? notes,
    String? restaurant,
    String? locale,
  });
}
