class NutritionLabelOcrService {
  Future<String> recognizeTextFromPath(String imagePath) async {
    throw UnsupportedError(
      'Nutrition label scanning is not supported on this platform.',
    );
  }

  Future<void> dispose() async {}
}
