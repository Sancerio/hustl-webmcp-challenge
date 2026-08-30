import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class NutritionLabelOcrService {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<String> recognizeTextFromPath(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final text = await _recognizer.processImage(inputImage);
    return text.text;
  }

  Future<void> dispose() async {
    _recognizer.close();
  }
}
