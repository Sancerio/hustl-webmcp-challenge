import 'strong_csv_import_service.dart' show StrongCsvImportResult;

/// Source-agnostic contract for importing a training history from another app's
/// export. Strong is the first implementation; Hevy (and future sources) plug in
/// behind this same interface so the onboarding switcher flow stays generic.
abstract class WorkoutHistoryImporter {
  /// Human-readable source name (e.g. "Strong"). Drives onboarding copy.
  String get sourceName;

  /// Parses [text] (a decoded export file) into sessions + warnings.
  Future<StrongCsvImportResult> parse(String text);
}
