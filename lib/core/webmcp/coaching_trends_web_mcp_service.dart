import 'coaching_trends_api.dart';

typedef CoachingTrendsLocalContext =
    ({String endDate, int utcOffsetMinutes}) Function();

class CoachingTrendsWebMcpService {
  CoachingTrendsWebMcpService({
    required CoachingTrendsApi api,
    CoachingTrendsLocalContext? localContext,
  }) : _api = api,
       _localContext = localContext ?? _currentLocalContext;

  final CoachingTrendsApi _api;
  final CoachingTrendsLocalContext _localContext;

  Future<Map<String, Object?>> load({required int windowDays}) async {
    final context = _localContext();
    final response = await _api.load(
      windowDays: windowDays,
      endDate: context.endDate,
      utcOffsetMinutes: context.utcOffsetMinutes,
    );
    return {
      'status': 'ready',
      'range': _range(windowDays, context.endDate),
      'training': _training(response['training']),
      'recovery': _recovery(response['recovery']),
      'nutrition': _nutrition(response['nutrition']),
    };
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static ({String endDate, int utcOffsetMinutes}) _currentLocalContext() {
    final now = DateTime.now().toLocal();
    return (
      endDate: _date(now),
      utcOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
  }

  static Map<String, Object?> _range(int windowDays, String endDate) {
    final end = DateTime.parse('${endDate}T00:00:00.000Z');
    final start = end.subtract(Duration(days: windowDays - 1));
    final previousEnd = start.subtract(const Duration(days: 1));
    final previousStart = start.subtract(Duration(days: windowDays));
    return {
      'windowDays': windowDays,
      'start': _date(start),
      'end': endDate,
      'previousStart': _date(previousStart),
      'previousEnd': _date(previousEnd),
    };
  }

  static Map<String, Object?> _training(Object? raw) {
    final map = _map(raw);
    return {
      'state': _state(map['state']),
      'current': _trainingPeriod(map['current']),
      'previous': _trainingPeriod(map['previous']),
      'change': _trainingChange(map['change']),
    };
  }

  static Map<String, Object?> _trainingPeriod(Object? raw) {
    final map = _map(raw);
    return {
      'completedSessions': _integerInRange(map['completedSessions'], 0, 10000),
      'activeDays': _integerInRange(map['activeDays'], 0, 90),
      'knownDurationSessions': _integerInRange(
        map['knownDurationSessions'],
        0,
        10000,
      ),
      'totalDurationMinutes': _numberInRange(
        map['totalDurationMinutes'],
        0,
        10000000,
      ),
    };
  }

  static Map<String, Object?> _trainingChange(Object? raw) {
    final map = _map(raw);
    return {
      'completedSessions': _integerInRange(
        map['completedSessions'],
        -10000,
        10000,
      ),
      'activeDays': _integerInRange(map['activeDays'], -90, 90),
      'totalDurationMinutes': _numberInRange(
        map['totalDurationMinutes'],
        -10000000,
        10000000,
      ),
    };
  }

  static Map<String, Object?> _recovery(Object? raw) {
    final map = _map(raw);
    final hrvKind = map['hrvKind'];
    return {
      'state': _state(map['state']),
      'hrvKind': hrvKind == 'sdnn' || hrvKind == 'rmssd' ? hrvKind : null,
      'current': _recoveryPeriod(map['current']),
      'previous': _recoveryPeriod(map['previous']),
      'change': _recoveryChange(map['change']),
    };
  }

  static Map<String, Object?> _recoveryPeriod(Object? raw) {
    final map = _map(raw);
    return {
      'coverageDays': _integerInRange(map['coverageDays'], 0, 90),
      'sleepDays': _integerInRange(map['sleepDays'], 0, 90),
      'averageSleepHours': _numberInRange(map['averageSleepHours'], 0, 24),
      'hrvDays': _integerInRange(map['hrvDays'], 0, 90),
      'averageHrvMs': _numberInRange(map['averageHrvMs'], 0, 1000),
      'restingHrDays': _integerInRange(map['restingHrDays'], 0, 90),
      'averageRestingHrBpm': _numberInRange(map['averageRestingHrBpm'], 0, 300),
    };
  }

  static Map<String, Object?> _recoveryChange(Object? raw) {
    final map = _map(raw);
    return {
      'averageSleepHours': _numberInRange(map['averageSleepHours'], -24, 24),
      'averageHrvMs': _numberInRange(map['averageHrvMs'], -1000, 1000),
      'averageRestingHrBpm': _numberInRange(
        map['averageRestingHrBpm'],
        -300,
        300,
      ),
    };
  }

  static Map<String, Object?> _nutrition(Object? raw) {
    final map = _map(raw);
    return {
      'state': _state(map['state']),
      'current': _nutritionPeriod(map['current']),
      'previous': _nutritionPeriod(map['previous']),
      'change': _nutritionChange(map['change']),
    };
  }

  static Map<String, Object?> _nutritionPeriod(Object? raw) {
    final map = _map(raw);
    return {
      'daysLogged': _integerInRange(map['daysLogged'], 0, 90),
      'loggingCompleteness': _numberInRange(map['loggingCompleteness'], 0, 1),
      'averageCaloriesOnLoggedDays': _numberInRange(
        map['averageCaloriesOnLoggedDays'],
        0,
        50000,
      ),
      'averageProteinGramsOnLoggedDays': _numberInRange(
        map['averageProteinGramsOnLoggedDays'],
        0,
        5000,
      ),
    };
  }

  static Map<String, Object?> _nutritionChange(Object? raw) {
    final map = _map(raw);
    return {
      'loggingCompleteness': _numberInRange(map['loggingCompleteness'], -1, 1),
      'averageCaloriesOnLoggedDays': _numberInRange(
        map['averageCaloriesOnLoggedDays'],
        -50000,
        50000,
      ),
      'averageProteinGramsOnLoggedDays': _numberInRange(
        map['averageProteinGramsOnLoggedDays'],
        -5000,
        5000,
      ),
    };
  }

  static Map<Object?, Object?> _map(Object? raw) =>
      raw is Map ? raw : const <Object?, Object?>{};

  static String _state(Object? raw) => raw == 'available'
      ? 'available'
      : raw == 'no_data'
      ? 'no_data'
      : 'unavailable';

  static int? _integerInRange(Object? raw, int minimum, int maximum) {
    if (raw is! num || !raw.isFinite || raw.toInt() != raw) return null;
    final value = raw.toInt();
    return value >= minimum && value <= maximum ? value : null;
  }

  static double? _numberInRange(Object? raw, double minimum, double maximum) {
    if (raw is! num || !raw.isFinite) return null;
    final value = raw.toDouble();
    return value >= minimum && value <= maximum ? value : null;
  }
}
