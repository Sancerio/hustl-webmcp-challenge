import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/webmcp/coaching_trends_api.dart';
import 'package:hustl_app/core/webmcp/coaching_trends_web_mcp_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockCoachingTrendsApi extends Mock implements CoachingTrendsApi {}

void main() {
  late _MockCoachingTrendsApi api;
  late CoachingTrendsWebMcpService service;

  setUp(() {
    api = _MockCoachingTrendsApi();
    service = CoachingTrendsWebMcpService(
      api: api,
      localContext: () => (endDate: '2026-08-29', utcOffsetMinutes: 480),
    );
  });

  test('derives local context and whitelists every returned field', () async {
    when(
      () => api.load(
        windowDays: any(named: 'windowDays'),
        endDate: any(named: 'endDate'),
        utcOffsetMinutes: any(named: 'utcOffsetMinutes'),
      ),
    ).thenAnswer(
      (_) async => {
        'accountId': 'must-not-escape',
        'range': {
          'windowDays': 30,
          'start': '2026-07-31',
          'end': '2026-08-29',
          'previousStart': '2026-07-01',
          'previousEnd': '2026-07-30',
          'daily': ['must-not-escape'],
        },
        'training': {
          'state': 'available',
          'current': {
            'completedSessions': 0,
            'activeDays': 3,
            'knownDurationSessions': 2,
            'totalDurationMinutes': 90,
            'notes': 'must-not-escape',
          },
          'previous': {
            'completedSessions': 4,
            'activeDays': 4,
            'knownDurationSessions': 0,
            'totalDurationMinutes': 0,
          },
          'change': {
            'completedSessions': -4,
            'activeDays': -1,
            'totalDurationMinutes': 90,
          },
        },
        'recovery': {
          'state': 'available',
          'hrvKind': 'sdnn',
          'source': 'must-not-escape',
          'current': {
            'coverageDays': 1,
            'sleepDays': 0,
            'averageSleepHours': null,
            'hrvDays': 1,
            'averageHrvMs': 0,
            'restingHrDays': 0,
            'averageRestingHrBpm': double.infinity,
          },
          'previous': <String, Object?>{},
          'change': <String, Object?>{},
        },
        'nutrition': {
          'state': 'no_data',
          'current': {
            'daysLogged': 0,
            'loggingCompleteness': 0,
            'averageCaloriesOnLoggedDays': null,
            'averageProteinGramsOnLoggedDays': null,
            'meals': ['must-not-escape'],
          },
          'previous': <String, Object?>{},
          'change': <String, Object?>{},
        },
      },
    );

    final result = await service.load(windowDays: 30);

    verify(
      () => api.load(
        windowDays: 30,
        endDate: '2026-08-29',
        utcOffsetMinutes: 480,
      ),
    ).called(1);
    expect(result['status'], 'ready');
    final training = result['training']! as Map<String, Object?>;
    final trainingCurrent = training['current']! as Map<String, Object?>;
    expect(trainingCurrent['completedSessions'], 0);
    expect(trainingCurrent['notes'], isNull);
    final recovery = result['recovery']! as Map<String, Object?>;
    final recoveryCurrent = recovery['current']! as Map<String, Object?>;
    expect(recoveryCurrent['averageHrvMs'], 0.0);
    expect(recoveryCurrent['averageSleepHours'], isNull);
    expect(recoveryCurrent['averageRestingHrBpm'], isNull);
    final nutrition = result['nutrition']! as Map<String, Object?>;
    final nutritionCurrent = nutrition['current']! as Map<String, Object?>;
    expect(nutritionCurrent['loggingCompleteness'], 0.0);
    expect(result.toString(), isNot(contains('must-not-escape')));
  });

  test('uses safe placeholder fields for malformed backend sections', () async {
    when(
      () => api.load(
        windowDays: any(named: 'windowDays'),
        endDate: any(named: 'endDate'),
        utcOffsetMinutes: any(named: 'utcOffsetMinutes'),
      ),
    ).thenAnswer((_) async => {'training': 'wrong type'});

    final result = await service.load(windowDays: 7);

    expect(result['range'], {
      'windowDays': 7,
      'start': '2026-08-23',
      'end': '2026-08-29',
      'previousStart': '2026-08-16',
      'previousEnd': '2026-08-22',
    });
    expect(
      (result['training']! as Map<String, Object?>)['state'],
      'unavailable',
    );
    expect((result['recovery']! as Map<String, Object?>)['hrvKind'], isNull);
  });
}
