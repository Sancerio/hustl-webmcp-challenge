import 'package:health/health.dart';

/// Shared Hustl-authorship detection for external workout points.
///
/// Extracted verbatim from `AppleHealthDuplicateCleanupService` so the
/// duplicate-cleanup path and the external-activity read path (plan 011) agree
/// on exactly what counts as "a workout Hustl wrote". This is deliberately a
/// pure predicate over a [HealthDataPoint] with no service state — behavior is
/// identical to the previous private `_isLikelyHustlWorkout` method.
///
/// A point is treated as Hustl-authored when any of the following hold:
/// - its metadata carries `platform: hustl`;
/// - its `sourceId` or `sourceName` mentions "hustl" (e.g. the app's bundle id
///   or Apple Health source name);
/// - its `HKMetadataKeyWorkoutBrandName` metadata mentions "hustl" (Hustl's
///   writeback stamps a `Hustl …` brand/title on the workout).
bool isLikelyHustlWorkout(HealthDataPoint point) {
  final metadata = point.metadata ?? const <String, dynamic>{};
  final platformTag =
      metadata['platform']?.toString().toLowerCase().trim() ?? '';
  if (platformTag == 'hustl') return true;

  final sourceId = point.sourceId.toLowerCase();
  final sourceName = point.sourceName.toLowerCase();
  if (sourceId.contains('hustl') || sourceName.contains('hustl')) {
    return true;
  }

  final brandName =
      metadata['HKMetadataKeyWorkoutBrandName']?.toString().toLowerCase() ?? '';
  return brandName.contains('hustl');
}
