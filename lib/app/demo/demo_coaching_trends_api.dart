import '../../core/webmcp/coaching_trends_api.dart';

/// Deterministic aggregate-only coaching trends for the offline evaluator.
///
/// The WebMCP service performs the final field allowlisting. This source keeps
/// the evaluator credential-free and intentionally contains no daily rows,
/// account identifiers, raw health samples, food entries, or workout detail.
class DemoCoachingTrendsApi implements CoachingTrendsApi {
  const DemoCoachingTrendsApi();

  @override
  Future<Map<String, dynamic>> load({
    required int windowDays,
    required String endDate,
    required int utcOffsetMinutes,
  }) async {
    final days = windowDays.clamp(1, 90).toInt();
    final trainingDays = (days * 4 / 7).round();
    final previousTrainingDays = (days * 3 / 7).round();
    final loggedDays = (days * 0.86).round();
    final previousLoggedDays = (days * 0.71).round();
    return {
      'training': {
        'state': 'available',
        'current': {
          'completedSessions': trainingDays,
          'activeDays': trainingDays,
          'knownDurationSessions': trainingDays,
          'totalDurationMinutes': trainingDays * 58,
        },
        'previous': {
          'completedSessions': previousTrainingDays,
          'activeDays': previousTrainingDays,
          'knownDurationSessions': previousTrainingDays,
          'totalDurationMinutes': previousTrainingDays * 56,
        },
        'change': {
          'completedSessions': trainingDays - previousTrainingDays,
          'activeDays': trainingDays - previousTrainingDays,
          'totalDurationMinutes': trainingDays * 58 - previousTrainingDays * 56,
        },
      },
      'recovery': {
        'state': 'available',
        'hrvKind': 'sdnn',
        'current': {
          'coverageDays': days,
          'sleepDays': days,
          'averageSleepHours': 6.3,
          'hrvDays': days,
          'averageHrvMs': 49.0,
          'restingHrDays': days,
          'averageRestingHrBpm': 59.0,
        },
        'previous': {
          'coverageDays': days,
          'sleepDays': days,
          'averageSleepHours': 7.2,
          'hrvDays': days,
          'averageHrvMs': 57.0,
          'restingHrDays': days,
          'averageRestingHrBpm': 54.0,
        },
        'change': {
          'averageSleepHours': -0.9,
          'averageHrvMs': -8.0,
          'averageRestingHrBpm': 5.0,
        },
      },
      'nutrition': {
        'state': 'available',
        'current': {
          'daysLogged': loggedDays,
          'loggingCompleteness': 0.86,
          'averageCaloriesOnLoggedDays': 2230.0,
          'averageProteinGramsOnLoggedDays': 153.0,
        },
        'previous': {
          'daysLogged': previousLoggedDays,
          'loggingCompleteness': 0.71,
          'averageCaloriesOnLoggedDays': 2175.0,
          'averageProteinGramsOnLoggedDays': 141.0,
        },
        'change': {
          'loggingCompleteness': 0.15,
          'averageCaloriesOnLoggedDays': 55.0,
          'averageProteinGramsOnLoggedDays': 12.0,
        },
      },
    };
  }
}
