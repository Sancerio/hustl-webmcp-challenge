import '../../domain/models/external_activity.dart';

class ExternalActivityReader {
  static const maxWorkoutLookback = Duration(hours: 24);
  Future<List<ExternalActivity>> readActivities({
    required DateTime start,
    required DateTime end,
  }) async => const [];
}
