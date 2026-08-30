import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/meal_scan_result.dart';
import '../../domain/repositories/meal_scan_repository.dart';
import '../datasources/hustl_backend_nutrition_api.dart';

class MealScanRepositoryImpl implements MealScanRepository {
  MealScanRepositoryImpl({required this.api});

  final HustlBackendNutritionApi api;

  @override
  Future<MealScanResult> scanMealPhoto({
    required Uint8List imageBytes,
    required String mimeType,
    String? notes,
    String? restaurant,
    String? locale,
  }) async {
    final map = await api.scanMealPhoto(
      imageBase64: base64Encode(imageBytes),
      mimeType: mimeType,
      notes: notes,
      restaurant: restaurant,
      locale: locale,
    );
    return MealScanResult.fromMap(map);
  }

  @override
  Future<MealScanResult> describeMeal({
    required String text,
    String? notes,
    String? restaurant,
    String? locale,
  }) async {
    final map = await api.describeMeal(
      text: text,
      notes: notes,
      restaurant: restaurant,
      locale: locale,
    );
    return MealScanResult.fromMap(map);
  }
}
