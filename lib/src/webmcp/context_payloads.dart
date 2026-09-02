import '../model/evaluator_state.dart';

Map<String, Object?> todayContext(EvaluatorState state) => {
  'status': 'ready',
  'asOf': state.anchor.toUtc().toIso8601String(),
  'training': trainingContext(state),
  'recovery': recoveryContext(state),
  'nutrition': nutritionContext(state),
  'coaching': {
    'pendingProposalCount': state.pending.length,
    'recentDecisionCount': state.recent.length,
  },
};

Map<String, Object?> trainingContext(EvaluatorState state) => {
  'status': 'ready',
  'activeWorkout': null,
  'completedThisWeek': 4,
  'lastWorkout': {
    'id': 'workout-24',
    'name': 'Lower strength',
    'startAt': '2026-08-29T10:00:00.000Z',
    'endAt': '2026-08-29T11:04:00.000Z',
    'durationSeconds': 3840,
    'status': 'completed',
  },
  'recommendation': 'Use a lower-volume upper session while recovery is low.',
};

Map<String, Object?> recoveryContext(EvaluatorState state) => {
  'status': 'ready',
  'date': _date(state.anchor),
  'readinessScore': 42,
  'recoveryBand': 'recharge',
  'confidence': 'high',
  'sleepMinutes': 318,
  'hrvMs': 47.0,
  'restingHeartRateBpm': 61.0,
  'baseline': {'sleepMinutes': 432, 'hrvMs': 57.0, 'restingHeartRateBpm': 54.0},
  'missingSignals': const <String>[],
};

Map<String, Object?> nutritionContext(EvaluatorState state) {
  final date = _date(state.anchor);
  final calories = state.todayCalories;
  final protein = state.todayProtein;
  final carbs = state.todayCarbs;
  final fat = state.todayFat;
  return {
    'status': 'ready',
    'date': date,
    'totals': {
      'calories': calories,
      'proteinGrams': protein,
      'carbsGrams': carbs,
      'fatGrams': fat,
    },
    'targets': state.nutritionTargets.toJson(),
    'remainingCalories': state.nutritionTargets.calories - calories,
  };
}

Map<String, Object?> coachingTrends(int windowDays, EvaluatorState state) => {
  'status': 'ready',
  'range': _trendRange(windowDays, state.anchor),
  'training': {
    'state': 'available',
    'current': {
      'completedSessions': (windowDays * 4 / 7).round(),
      'activeDays': (windowDays * 4 / 7).round(),
      'knownDurationSessions': (windowDays * 4 / 7).round(),
      'totalDurationMinutes': (windowDays * 4 / 7).round() * 58,
    },
    'previous': {
      'completedSessions': (windowDays * 3 / 7).round(),
      'activeDays': (windowDays * 3 / 7).round(),
      'knownDurationSessions': (windowDays * 3 / 7).round(),
      'totalDurationMinutes': (windowDays * 3 / 7).round() * 56,
    },
    'change': {
      'completedSessions':
          (windowDays * 4 / 7).round() - (windowDays * 3 / 7).round(),
      'activeDays': (windowDays * 4 / 7).round() - (windowDays * 3 / 7).round(),
      'totalDurationMinutes':
          (windowDays * 4 / 7).round() * 58 - (windowDays * 3 / 7).round() * 56,
    },
  },
  'recovery': {
    'state': 'available',
    'hrvKind': 'sdnn',
    'current': {
      'coverageDays': windowDays,
      'averageSleepHours': 6.3,
      'averageHrvMs': 49.0,
      'averageRestingHrBpm': 59.0,
    },
    'previous': {
      'coverageDays': windowDays,
      'averageSleepHours': 7.2,
      'averageHrvMs': 57.0,
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
      'daysLogged': (windowDays * 0.86).round(),
      'loggingCompleteness': 0.86,
      'averageCaloriesOnLoggedDays': 2230.0,
      'averageProteinGramsOnLoggedDays': 153.0,
    },
    'previous': {
      'daysLogged': (windowDays * 0.71).round(),
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

Map<String, Object?> _trendRange(int windowDays, DateTime anchor) {
  final end = DateTime.utc(anchor.year, anchor.month, anchor.day);
  final start = end.subtract(Duration(days: windowDays - 1));
  final previousEnd = start.subtract(const Duration(days: 1));
  final previousStart = start.subtract(Duration(days: windowDays));
  return {
    'windowDays': windowDays,
    'start': _date(start),
    'end': _date(end),
    'previousStart': _date(previousStart),
    'previousEnd': _date(previousEnd),
  };
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
