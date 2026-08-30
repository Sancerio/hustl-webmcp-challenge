import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart' show HealthDataType;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/health_sync/data/datasources/hustl_backend_health_api.dart';
import 'package:hustl_app/features/health_sync/data/services/health_backend_sync_service.dart';
import 'package:hustl_app/features/health_sync/data/sources/external_activity_reader.dart';
import 'package:hustl_app/features/health_sync/data/sources/health_platform_source.dart';
import 'package:hustl_app/features/health_sync/domain/models/external_activity.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/services/external_activity_filter.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _MockHealthPlatformSource extends Mock implements HealthPlatformSource {}

class _MockHustlBackendHealthApi extends Mock
    implements HustlBackendHealthApi {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockExternalActivityReader extends Mock
    implements ExternalActivityReader {}

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockPreferencesService extends Mock implements PreferencesService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'syncRecentObservations uploads provenance and complete sleep session',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final now = DateTime(2026, 8, 15, 9);
      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(() => platformSource.supportedTypes(any())).thenAnswer(
        (_) async => [HealthDataType.SLEEP_ASLEEP, HealthDataType.HEART_RATE],
      );
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => null);
      final sleepSample = HealthMetricSample(
        type: HealthMetricType.sleepAsleep,
        value: 420,
        unit: 'min',
        startTime: DateTime(2026, 8, 14, 23),
        endTime: DateTime(2026, 8, 15, 6),
        source: 'Apple Watch',
        externalId: 'sleep-1',
        sourceId: 'com.apple.Health',
        sourceDeviceId: 'watch-1',
        deviceModel: 'Apple Watch',
        timezoneName: 'Asia/Singapore',
        timezoneOffsetMinutes: 480,
      );
      final heartRateSample = HealthMetricSample(
        type: HealthMetricType.heartRate,
        value: 72,
        unit: 'bpm',
        startTime: DateTime(2026, 8, 15, 6),
        endTime: DateTime(2026, 8, 15, 6, 1),
        source: 'Apple Watch',
        externalId: 'hr-1',
        sourceId: 'com.apple.Health',
        sourceDeviceId: 'watch-1',
        deviceModel: 'Apple Watch',
        timezoneName: 'Asia/Singapore',
        timezoneOffsetMinutes: 480,
      );
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((_) async => [sleepSample, heartRateSample]);
      when(
        () => api.upsertHealthData(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          observations: any(named: 'observations'),
          sessions: any(named: 'sessions'),
        ),
      ).thenAnswer((_) async {});
      var uiYields = 0;

      await HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        now: () => now,
        yieldToUi: () async {
          uiYields += 1;
        },
      ).syncRecentObservations(days: 2);

      final reads = verify(
        () => platformSource.readMetricSamples(
          captureAny(),
          captureAny(),
          types: captureAny(named: 'types'),
        ),
      ).captured;
      expect(reads, hasLength(3));
      expect(reads[0], DateTime(2026, 8, 14));
      expect(reads[1], DateTime(2026, 8, 15, 23, 59, 59, 999));
      expect(
        reads[2] as Iterable<HealthDataType>,
        containsAll([HealthDataType.SLEEP_ASLEEP, HealthDataType.HEART_RATE]),
      );
      expect(uiYields, 0);

      final captured = verify(
        () => api.upsertHealthData(
          provider: captureAny(named: 'provider'),
          lastSyncedAt: captureAny(named: 'lastSyncedAt'),
          observations: captureAny(named: 'observations'),
          sessions: captureAny(named: 'sessions'),
        ),
      ).captured;
      final observations = (captured[2] as List).cast<Map<String, dynamic>>();
      final sessions = (captured[3] as List).cast<Map<String, dynamic>>();
      expect(captured[0], 'apple_health');
      expect(observations, hasLength(2));
      expect(
        observations.firstWhere((item) => item['metricType'] == 'heartRate'),
        containsPair('sourceDeviceId', 'watch-1'),
      );
      expect(sessions.single, containsPair('completeness', 'complete'));
      expect(
        observations.firstWhere(
          (item) => item['metricType'] == 'sleepAsleep',
        )['sessionKey'],
        sessions.single['sessionKey'],
      );
    },
  );

  test(
    'syncRecentCrossPlatformMetrics uploads body and activity aggregates',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final now = DateTime(2026, 8, 24, 9);
      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(() => platformSource.supportedTypes(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as List<HealthDataType>,
      );
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((invocation) async {
        final types =
            invocation.namedArguments[#types] as Iterable<HealthDataType>;
        final samples = <HealthMetricSample>[];
        for (final type in types) {
          final metric = switch (type) {
            HealthDataType.BODY_FAT_PERCENTAGE =>
              HealthMetricType.bodyFatPercentage,
            HealthDataType.STEPS => HealthMetricType.steps,
            HealthDataType.ACTIVE_ENERGY_BURNED =>
              HealthMetricType.activeEnergyBurned,
            HealthDataType.EXERCISE_TIME => HealthMetricType.exerciseTime,
            _ => null,
          };
          if (metric == null) continue;
          final (value, unit) = switch (metric) {
            HealthMetricType.bodyFatPercentage => (17.7, '%'),
            HealthMetricType.steps => (9000.0, 'count'),
            HealthMetricType.activeEnergyBurned => (720.0, 'kcal'),
            HealthMetricType.exerciseTime => (60.0, 'min'),
            _ => (0.0, ''),
          };
          samples.add(
            HealthMetricSample(
              type: metric,
              value: value,
              unit: unit,
              startTime: now,
              endTime: now,
              source: 'Apple Watch',
            ),
          );
        }
        return samples;
      });
      when(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async {});

      final uploaded = await HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        now: () => now,
        yieldToUi: () async {},
      ).syncRecentCrossPlatformMetrics(days: 1);

      expect(uploaded, isTrue);
      final captured = verify(
        () => api.upsertDailyMetrics(
          provider: captureAny(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: captureAny(named: 'items'),
        ),
      ).captured;
      expect(captured.first, 'apple_health');
      final items = (captured.last as List).cast<Map<String, dynamic>>();
      expect(items.map((item) => item['metricType']).toSet(), {
        'body_fat_percentage',
        'steps',
        'exercise_minutes',
        'active_energy_kcal',
      });
      expect(
        items.firstWhere((item) => item['metricType'] == 'steps')['value'],
        9000,
      );
    },
  );

  test(
    'syncRecentCrossPlatformMetrics replays the full bounded window despite a '
    'shared watermark',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final preferences = _MockPreferencesService();
      final now = DateTime(2026, 8, 24, 9);
      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.supportedTypes(any()),
      ).thenAnswer((_) async => [HealthDataType.STEPS]);
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);
      DateTime? requestedStart;
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((invocation) async {
        requestedStart = invocation.positionalArguments.first as DateTime;
        return [
          HealthMetricSample(
            type: HealthMetricType.steps,
            value: 9000,
            unit: 'count',
            startTime: now,
            endTime: now,
            source: 'Apple Watch',
          ),
        ];
      });
      when(
        () => preferences.getHealthSyncWatermark(any()),
      ).thenAnswer((_) async => '2026-08-24');
      when(
        () => preferences.setHealthSyncWatermark(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async {});

      final uploaded = await HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        preferences: preferences,
        now: () => now,
        yieldToUi: () async {},
      ).syncRecentCrossPlatformMetrics(days: 7);

      expect(uploaded, isTrue);
      expect(requestedStart, DateTime(2026, 8, 18));
      // The only read is the post-upload monotonicity check in
      // _saveWatermark; window preparation itself ignores the shared cursor.
      verify(() => preferences.getHealthSyncWatermark(any())).called(1);
    },
  );

  test(
    'syncRecentExternalActivities uploads only filtered platform workouts',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final reader = _MockExternalActivityReader();
      final workouts = _MockWorkoutRepository();
      final preferences = _MockPreferencesService();
      final now = DateTime(2026, 8, 24, 9);
      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => preferences.getHealthSyncWatermark(any()),
      ).thenAnswer((_) async => null);
      when(
        () => preferences.setHealthSyncWatermark(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => reader.readActivities(
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).thenAnswer(
        (_) async => [
          _activity('echo', 'Strength'),
          _activity('football', 'Football'),
        ],
      );
      when(
        () => preferences.getWorkoutWritebackMappings(),
      ).thenAnswer((_) async => {'session': 'echo'});
      when(
        () => workouts.getWorkoutSessions(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => api.upsertHealthData(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          sessions: any(named: 'sessions'),
        ),
      ).thenAnswer((_) async {});

      final uploaded = await HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        preferences: preferences,
        externalActivityReader: reader,
        externalActivityFilter: const ExternalActivityFilter(),
        workoutRepository: workouts,
        now: () => now,
      ).syncRecentExternalActivities(days: 7);

      expect(uploaded, isTrue);
      final captured = verify(
        () => api.upsertHealthData(
          provider: captureAny(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          sessions: captureAny(named: 'sessions'),
        ),
      ).captured;
      expect(captured.first, 'apple_health');
      final sessions = (captured.last as List).cast<Map<String, dynamic>>();
      expect(sessions, hasLength(1));
      expect(sessions.single['sessionKey'], 'workout|football');
      expect(sessions.single['sessionType'], 'workout');
      expect(
        sessions.single['metadata'],
        containsPair('activityName', 'Football'),
      );
    },
  );

  test(
    'syncRecentExternalActivities fails closed when mappings are unavailable',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final reader = _MockExternalActivityReader();
      final workouts = _MockWorkoutRepository();
      final preferences = _MockPreferencesService();
      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => preferences.getHealthSyncWatermark(any()),
      ).thenAnswer((_) async => null);
      when(
        () => reader.readActivities(
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).thenAnswer((_) async => [_activity('football', 'Football')]);
      when(
        () => preferences.getWorkoutWritebackMappings(),
      ).thenThrow(Exception('preferences unavailable'));

      final uploaded = await HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        preferences: preferences,
        externalActivityReader: reader,
        workoutRepository: workouts,
        now: () => DateTime(2026, 8, 24, 9),
      ).syncRecentExternalActivities(days: 7);

      expect(uploaded, isFalse);
      verifyNever(
        () => api.upsertHealthData(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          sessions: any(named: 'sessions'),
        ),
      );
    },
  );

  test(
    'syncRecentWeights proceeds on iOS when hasPermissions returns null',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => null);

      final now = DateTime(2026, 1, 26, 9);
      final sample = HealthMetricSample(
        type: HealthMetricType.weight,
        value: 80.0,
        unit: 'kg',
        startTime: now,
        endTime: now,
        source: 'Apple Health',
      );
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((_) async => [sample]);

      when(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async {});

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        now: () => now,
      );

      await service.syncRecentWeights(days: 1);

      final captured = verify(
        () => api.upsertDailyMetrics(
          provider: captureAny(named: 'provider'),
          lastSyncedAt: captureAny(named: 'lastSyncedAt'),
          items: captureAny(named: 'items'),
        ),
      ).captured;

      expect(captured[0], 'apple_health');
      final items = (captured[2] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(1));
      expect(items.first['source'], 'apple_health');
      expect(items.first['metricType'], 'weight');
    },
  );

  test('syncRecentWeights uses midnight start and end-of-day window', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final platformSource = _MockHealthPlatformSource();
    final api = _MockHustlBackendHealthApi();
    final tokens = _MockTokenStorage();

    when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
    when(
      () => platformSource.isServiceAvailable(),
    ).thenAnswer((_) async => true);
    when(
      () => platformSource.hasPermissions(any()),
    ).thenAnswer((_) async => true);

    final now = DateTime(2026, 1, 26, 9, 15, 30, 123);
    final sample = HealthMetricSample(
      type: HealthMetricType.weight,
      value: 80.0,
      unit: 'kg',
      startTime: now,
      endTime: now,
      source: 'Apple Health',
    );
    when(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: any(named: 'types'),
      ),
    ).thenAnswer((_) async => [sample]);
    when(
      () => api.upsertDailyMetrics(
        provider: any(named: 'provider'),
        lastSyncedAt: any(named: 'lastSyncedAt'),
        items: any(named: 'items'),
      ),
    ).thenAnswer((_) async {});

    final service = HealthBackendSyncService(
      platformSource: platformSource,
      api: api,
      tokens: tokens,
      now: () => now,
    );

    await service.syncRecentWeights(days: 3);

    final capturedWindow = verify(
      () => platformSource.readMetricSamples(
        captureAny(),
        captureAny(),
        types: captureAny(named: 'types'),
      ),
    ).captured;

    expect(capturedWindow, hasLength(3));
    expect(capturedWindow[0], DateTime(2026, 1, 24));
    expect(capturedWindow[1], DateTime(2026, 1, 26, 23, 59, 59, 999));
    expect(capturedWindow[2], HealthPlatformSource.weightMetricTypes);
  });

  test('syncRecentWeights assigns the source-local day without a second '
      'device-timezone conversion', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final platformSource = _MockHealthPlatformSource();
    final api = _MockHustlBackendHealthApi();
    final tokens = _MockTokenStorage();
    when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
    when(
      () => platformSource.isServiceAvailable(),
    ).thenAnswer((_) async => true);
    when(
      () => platformSource.hasPermissions(any()),
    ).thenAnswer((_) async => true);
    when(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: any(named: 'types'),
      ),
    ).thenAnswer(
      (_) async => [
        HealthMetricSample(
          type: HealthMetricType.weight,
          value: 80,
          unit: 'kg',
          startTime: DateTime.utc(2026, 1, 1, 23, 30),
          endTime: DateTime.utc(2026, 1, 1, 23, 30),
          source: 'Travel scale',
          timezoneName: 'America/New_York',
          timezoneOffsetMinutes: -300,
        ),
      ],
    );
    when(
      () => api.upsertDailyMetrics(
        provider: any(named: 'provider'),
        lastSyncedAt: any(named: 'lastSyncedAt'),
        items: any(named: 'items'),
      ),
    ).thenAnswer((_) async {});

    await HealthBackendSyncService(
      platformSource: platformSource,
      api: api,
      tokens: tokens,
      now: () => DateTime(2026, 1, 2, 9),
    ).syncRecentWeights(days: 2);

    final captured =
        verify(
              () => api.upsertDailyMetrics(
                provider: any(named: 'provider'),
                lastSyncedAt: any(named: 'lastSyncedAt'),
                items: captureAny(named: 'items'),
              ),
            ).captured.single
            as List<Map<String, dynamic>>;
    expect(captured.single['date'], '2026-01-01');
  });

  test('syncRecentRecoveryMetrics maps HRV, resting HR and sleep with correct '
      'types and units', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final platformSource = _MockHealthPlatformSource();
    final api = _MockHustlBackendHealthApi();
    final tokens = _MockTokenStorage();

    when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
    when(
      () => platformSource.isServiceAvailable(),
    ).thenAnswer((_) async => true);
    when(
      () => platformSource.hasPermissions(any()),
    ).thenAnswer((_) async => true);
    // iOS supports every recovery type, so supportedTypes echoes the input.
    when(() => platformSource.supportedTypes(any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as List<HealthDataType>,
    );

    final day = DateTime(2026, 1, 26, 8);
    final samples = <HealthMetricSample>[
      // Two HRV SDNN reads in one day -> averaged to 60.
      HealthMetricSample(
        type: HealthMetricType.heartRateVariabilitySdnn,
        value: 50,
        unit: 'ms',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
      HealthMetricSample(
        type: HealthMetricType.heartRateVariabilitySdnn,
        value: 70,
        unit: 'ms',
        startTime: day.add(const Duration(hours: 1)),
        endTime: day.add(const Duration(hours: 1)),
        source: 'Apple Watch',
      ),
      HealthMetricSample(
        type: HealthMetricType.heartRateVariabilityRmssd,
        value: 42,
        unit: 'ms',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
      HealthMetricSample(
        type: HealthMetricType.restingHeartRate,
        value: 58,
        unit: 'bpm',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
      // Sleep reported in seconds -> normalised to minutes (25200 s = 420 m).
      HealthMetricSample(
        type: HealthMetricType.sleepAsleep,
        value: 25200,
        unit: 's',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
    ];
    when(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: any(named: 'types'),
      ),
    ).thenAnswer((_) async => samples);
    when(
      () => api.upsertDailyMetrics(
        provider: any(named: 'provider'),
        lastSyncedAt: any(named: 'lastSyncedAt'),
        items: any(named: 'items'),
      ),
    ).thenAnswer((_) async {});

    final service = HealthBackendSyncService(
      platformSource: platformSource,
      api: api,
      tokens: tokens,
      now: () => DateTime(2026, 1, 26, 9),
      yieldToUi: () async {},
    );

    await service.syncRecentRecoveryMetrics(days: 1);

    final captured = verify(
      () => api.upsertDailyMetrics(
        provider: captureAny(named: 'provider'),
        lastSyncedAt: captureAny(named: 'lastSyncedAt'),
        items: captureAny(named: 'items'),
      ),
    ).captured;

    expect(captured[0], 'apple_health');
    final items = (captured[2] as List).cast<Map<String, dynamic>>();

    Map<String, dynamic> byType(String t) =>
        items.firstWhere((i) => i['metricType'] == t);

    final sdnn = byType('hrv_sdnn');
    expect(sdnn['unit'], 'ms');
    expect(sdnn['value'], 60); // (50 + 70) / 2
    expect(sdnn['source'], 'apple_health');
    expect(sdnn['date'], '2026-01-26');

    final rmssd = byType('hrv_rmssd');
    expect(rmssd['unit'], 'ms');
    expect(rmssd['value'], 42);

    final rhr = byType('resting_heart_rate');
    expect(rhr['unit'], 'bpm');
    expect(rhr['value'], 58);

    final sleep = byType('sleep_duration');
    expect(sleep['unit'], 'minutes');
    expect(sleep['value'], 420); // 25200 s -> 420 min
  });

  test('syncRecentRecoveryMetrics prefers staged sleep over SLEEP_ASLEEP and '
      'sums stages', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final platformSource = _MockHealthPlatformSource();
    final api = _MockHustlBackendHealthApi();
    final tokens = _MockTokenStorage();

    when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
    when(
      () => platformSource.isServiceAvailable(),
    ).thenAnswer((_) async => true);
    when(
      () => platformSource.hasPermissions(any()),
    ).thenAnswer((_) async => true);
    // iOS supports every recovery type, so supportedTypes echoes the input.
    when(() => platformSource.supportedTypes(any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as List<HealthDataType>,
    );

    final day = DateTime(2026, 1, 26, 2);
    final samples = <HealthMetricSample>[
      HealthMetricSample(
        type: HealthMetricType.sleepRem,
        value: 90,
        unit: 'min',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
      HealthMetricSample(
        type: HealthMetricType.sleepDeep,
        value: 100,
        unit: 'min',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
      HealthMetricSample(
        type: HealthMetricType.sleepLight,
        value: 200,
        unit: 'min',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
      // SLEEP_ASLEEP present but must be ignored once stages exist (no
      // double-count).
      HealthMetricSample(
        type: HealthMetricType.sleepAsleep,
        value: 999,
        unit: 'min',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
    ];
    when(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: any(named: 'types'),
      ),
    ).thenAnswer((_) async => samples);
    when(
      () => api.upsertDailyMetrics(
        provider: any(named: 'provider'),
        lastSyncedAt: any(named: 'lastSyncedAt'),
        items: any(named: 'items'),
      ),
    ).thenAnswer((_) async {});

    final service = HealthBackendSyncService(
      platformSource: platformSource,
      api: api,
      tokens: tokens,
      now: () => DateTime(2026, 1, 26, 9),
      yieldToUi: () async {},
    );

    await service.syncRecentRecoveryMetrics(days: 1);

    final captured = verify(
      () => api.upsertDailyMetrics(
        provider: captureAny(named: 'provider'),
        lastSyncedAt: captureAny(named: 'lastSyncedAt'),
        items: captureAny(named: 'items'),
      ),
    ).captured;
    final items = (captured[2] as List).cast<Map<String, dynamic>>();
    final sleep = items.firstWhere((i) => i['metricType'] == 'sleep_duration');
    expect(sleep['value'], 390); // 90 + 100 + 200, ignoring SLEEP_ASLEEP
    expect(sleep['unit'], 'minutes');
  });

  test(
    'syncRecentRecoveryMetrics does not call the API when no recovery samples',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);
      // iOS supports every recovery type, so supportedTypes echoes the input.
      when(() => platformSource.supportedTypes(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as List<HealthDataType>,
      );

      final now = DateTime(2026, 1, 26, 9);
      // Only a weight sample exists -> recovery sync should be a no-op.
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer(
        (_) async => [
          HealthMetricSample(
            type: HealthMetricType.weight,
            value: 80,
            unit: 'kg',
            startTime: now,
            endTime: now,
            source: 'Apple Health',
          ),
        ],
      );

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        now: () => now,
        yieldToUi: () async {},
      );

      await service.syncRecentRecoveryMetrics(days: 1);

      verifyNever(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      );
    },
  );
  test('syncRecentRecoveryMetrics proceeds when weight is denied but recovery '
      'permissions are granted', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final platformSource = _MockHealthPlatformSource();
    final api = _MockHustlBackendHealthApi();
    final tokens = _MockTokenStorage();

    when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
    when(
      () => platformSource.isServiceAvailable(),
    ).thenAnswer((_) async => true);
    // Weight permission denied, but recovery signals granted: recovery sync
    // must still proceed so the cross-domain coach isn't left dormant. iOS
    // supports every recovery type, so supportedTypes echoes the input and the
    // per-group permission checks all resolve granted.
    when(() => platformSource.supportedTypes(any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as List<HealthDataType>,
    );
    when(
      () => platformSource.hasPermissions(any()),
    ).thenAnswer((_) async => true);
    when(
      () =>
          platformSource.hasPermissions(HealthPlatformSource.weightMetricTypes),
    ).thenAnswer((_) async => false);

    final day = DateTime(2026, 1, 26, 8);
    final samples = <HealthMetricSample>[
      HealthMetricSample(
        type: HealthMetricType.heartRateVariabilitySdnn,
        value: 60,
        unit: 'ms',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
      HealthMetricSample(
        type: HealthMetricType.restingHeartRate,
        value: 55,
        unit: 'bpm',
        startTime: day,
        endTime: day,
        source: 'Apple Watch',
      ),
    ];
    when(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: any(named: 'types'),
      ),
    ).thenAnswer((_) async => samples);
    when(
      () => api.upsertDailyMetrics(
        provider: any(named: 'provider'),
        lastSyncedAt: any(named: 'lastSyncedAt'),
        items: any(named: 'items'),
      ),
    ).thenAnswer((_) async {});

    final service = HealthBackendSyncService(
      platformSource: platformSource,
      api: api,
      tokens: tokens,
      now: () => DateTime(2026, 1, 26, 9),
      yieldToUi: () async {},
    );

    await service.syncRecentRecoveryMetrics(days: 1);

    // The recovery read happened despite weight being denied.
    final recoveryReads = verify(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: captureAny(named: 'types'),
      ),
    ).captured;
    expect(recoveryReads, hasLength(1));
    expect(
      recoveryReads.single as Iterable<HealthDataType>,
      containsAll(HealthPlatformSource.recoverySyncMetricTypes),
    );
    final captured = verify(
      () => api.upsertDailyMetrics(
        provider: captureAny(named: 'provider'),
        lastSyncedAt: captureAny(named: 'lastSyncedAt'),
        items: captureAny(named: 'items'),
      ),
    ).captured;
    final items = (captured[2] as List).cast<Map<String, dynamic>>();
    expect(
      items.map((i) => i['metricType']),
      containsAll(<String>['hrv_sdnn', 'resting_heart_rate']),
    );
  });

  test(
    'syncRecentWeights does not upload when only recovery permissions granted',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      // Weight denied: the weight sync must gate on weight and stay a no-op.
      when(
        () => platformSource.hasPermissions(
          HealthPlatformSource.weightMetricTypes,
        ),
      ).thenAnswer((_) async => false);

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        now: () => DateTime(2026, 1, 26, 9),
      );

      await service.syncRecentWeights(days: 1);

      verifyNever(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      );
      verifyNever(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      );
    },
  );

  test(
    'syncRecentRecoveryMetrics on Android uploads RMSSD/RHR/sleep when granted '
    'and SDNN is unsupported',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      // Health Connect does not expose HRV SDNN: that group filters to empty so
      // the gate skips it. The RMSSD, resting HR and sleep groups are supported.
      when(() => platformSource.supportedTypes(any())).thenAnswer((
        invocation,
      ) async {
        final requested =
            invocation.positionalArguments.first as List<HealthDataType>;
        return requested
            .where((t) => t != HealthDataType.HEART_RATE_VARIABILITY_SDNN)
            .toList();
      });
      // All supported recovery signals are granted on Android.
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);

      final day = DateTime(2026, 1, 26, 8);
      final samples = <HealthMetricSample>[
        HealthMetricSample(
          type: HealthMetricType.heartRateVariabilityRmssd,
          value: 42,
          unit: 'ms',
          startTime: day,
          endTime: day,
          source: 'Pixel Watch',
        ),
        HealthMetricSample(
          type: HealthMetricType.restingHeartRate,
          value: 55,
          unit: 'bpm',
          startTime: day,
          endTime: day,
          source: 'Pixel Watch',
        ),
        // Sleep reported in minutes (Health Connect sleep stages).
        HealthMetricSample(
          type: HealthMetricType.sleepDeep,
          value: 120,
          unit: 'min',
          startTime: day,
          endTime: day,
          source: 'Pixel Watch',
        ),
        HealthMetricSample(
          type: HealthMetricType.sleepLight,
          value: 300,
          unit: 'min',
          startTime: day,
          endTime: day,
          source: 'Pixel Watch',
        ),
      ];
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((_) async => samples);
      when(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async {});

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        now: () => DateTime(2026, 1, 26, 9),
        yieldToUi: () async {},
      );

      await service.syncRecentRecoveryMetrics(days: 1);

      // The recovery read happened despite SDNN being unsupported.
      final recoveryReads = verify(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: captureAny(named: 'types'),
        ),
      ).captured;
      expect(recoveryReads, hasLength(1));
      expect(
        recoveryReads.single as Iterable<HealthDataType>,
        isNot(contains(HealthDataType.HEART_RATE_VARIABILITY_SDNN)),
      );
      final captured = verify(
        () => api.upsertDailyMetrics(
          provider: captureAny(named: 'provider'),
          lastSyncedAt: captureAny(named: 'lastSyncedAt'),
          items: captureAny(named: 'items'),
        ),
      ).captured;

      expect(
        captured[0],
        'google_fit',
      ); // legacy key; UI shows "Health Connect"
      final items = (captured[2] as List).cast<Map<String, dynamic>>();
      final types = items.map((i) => i['metricType']).toSet();
      // RMSSD, resting HR and sleep all upload...
      expect(
        types,
        containsAll(<String>[
          'hrv_rmssd',
          'resting_heart_rate',
          'sleep_duration',
        ]),
      );
      // ...and the unsupported SDNN signal is never uploaded.
      expect(types, isNot(contains('hrv_sdnn')));

      final sleep = items.firstWhere(
        (i) => i['metricType'] == 'sleep_duration',
      );
      expect(sleep['value'], 420); // 120 deep + 300 light
      expect(sleep['source'], 'google_fit');
    },
  );

  test(
    'syncRecentRecoveryMetrics on Android is a no-op when all recovery signals '
    'are denied',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      // SDNN unsupported (empty), the rest supported but all denied.
      when(() => platformSource.supportedTypes(any())).thenAnswer((
        invocation,
      ) async {
        final requested =
            invocation.positionalArguments.first as List<HealthDataType>;
        return requested
            .where((t) => t != HealthDataType.HEART_RATE_VARIABILITY_SDNN)
            .toList();
      });
      // No assumed-grant on Android, so a false here means denied.
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => false);

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        now: () => DateTime(2026, 1, 26, 9),
      );

      await service.syncRecentRecoveryMetrics(days: 1);

      // No granted recovery group -> no read and no upload.
      verifyNever(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      );
      verifyNever(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      );
    },
  );

  test('syncRecentRecoveryMetrics reads ONLY the granted recovery types when '
      'weight is denied (no denied weight/body/activity reads)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final platformSource = _MockHealthPlatformSource();
    final api = _MockHustlBackendHealthApi();
    final tokens = _MockTokenStorage();

    when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
    when(
      () => platformSource.isServiceAvailable(),
    ).thenAnswer((_) async => true);
    // iOS supports every recovery type, so supportedTypes echoes the input.
    when(() => platformSource.supportedTypes(any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as List<HealthDataType>,
    );
    // Recovery granted, weight denied: the recovery read must NOT request the
    // weight/body/activity types the user never authorized — otherwise it
    // leaves irrelevant permission warnings for the next dashboard load.
    when(
      () => platformSource.hasPermissions(any()),
    ).thenAnswer((_) async => true);
    when(
      () =>
          platformSource.hasPermissions(HealthPlatformSource.weightMetricTypes),
    ).thenAnswer((_) async => false);

    final day = DateTime(2026, 1, 26, 8);
    when(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: any(named: 'types'),
      ),
    ).thenAnswer(
      (_) async => [
        HealthMetricSample(
          type: HealthMetricType.heartRateVariabilitySdnn,
          value: 60,
          unit: 'ms',
          startTime: day,
          endTime: day,
          source: 'Apple Watch',
        ),
      ],
    );
    when(
      () => api.upsertDailyMetrics(
        provider: any(named: 'provider'),
        lastSyncedAt: any(named: 'lastSyncedAt'),
        items: any(named: 'items'),
      ),
    ).thenAnswer((_) async {});

    final service = HealthBackendSyncService(
      platformSource: platformSource,
      api: api,
      tokens: tokens,
      now: () => DateTime(2026, 1, 26, 9),
      yieldToUi: () async {},
    );

    await service.syncRecentRecoveryMetrics(days: 1);

    final captured = verify(
      () => platformSource.readMetricSamples(
        any(),
        any(),
        types: captureAny(named: 'types'),
      ),
    ).captured;
    final requestedBatches = captured
        .cast<Iterable<HealthDataType>>()
        .map((batch) => batch.toSet())
        .toList();
    expect(requestedBatches, hasLength(1));
    final requestedTypes = requestedBatches.expand((batch) => batch).toSet();

    // The read requests EXACTLY the granted recovery signal types...
    final expectedRecoveryTypes = {
      for (final group in HealthPlatformSource.recoverySignalGroups.values)
        ...group,
    };
    expect(requestedTypes, equals(expectedRecoveryTypes));

    // ...and never the weight/body/activity types the user denied or didn't
    // authorize for this sync (which would leave denied-permission warnings).
    expect(requestedTypes, isNot(contains(HealthDataType.WEIGHT)));
    for (final t in HealthPlatformSource.bodyMetricTypes) {
      expect(requestedTypes, isNot(contains(t)));
    }
    for (final t in HealthPlatformSource.activityMetricTypes) {
      expect(requestedTypes, isNot(contains(t)));
    }
  });

  group('sync window cursor (#21)', () {
    PreferencesService freshPrefs() {
      final prefs = PreferencesService();
      prefs.resetForTests();
      return prefs;
    }

    HealthMetricSample weightOn(DateTime day) => HealthMetricSample(
      type: HealthMetricType.weight,
      value: 80.0,
      unit: 'kg',
      startTime: day,
      endTime: day,
      source: 'Apple Health',
    );

    test('first run with no watermark reads the full window', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = freshPrefs();
      await prefs.init();

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final now = DateTime(2026, 1, 26, 9);

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((_) async => [weightOn(now)]);
      when(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async {});

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        preferences: prefs,
        now: () => now,
      );

      await service.syncRecentWeights(days: 30);

      final window = verify(
        () => platformSource.readMetricSamples(
          captureAny(),
          captureAny(),
          types: captureAny(named: 'types'),
        ),
      ).captured;
      // Full 30-day window: start = today - 29 days.
      expect(window[0], DateTime(2025, 12, 28));
      expect(window[1], DateTime(2026, 1, 26, 23, 59, 59, 999));

      // A successful sync records the latest uploaded day as the watermark.
      expect(await prefs.getHealthSyncWatermark('weight'), '2026-01-26');
    });

    test('observation replay ignores the shared watermark so newly granted '
        'types receive the full bounded backfill', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'health_sync_watermark_observations': '2026-01-26',
      });
      final prefs = freshPrefs();
      await prefs.init();
      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final now = DateTime(2026, 1, 26, 9);
      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.supportedTypes(any()),
      ).thenAnswer((_) async => [HealthDataType.HEART_RATE]);
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer(
        (_) async => [
          HealthMetricSample(
            type: HealthMetricType.heartRate,
            value: 70,
            unit: 'bpm',
            startTime: now,
            endTime: now,
            source: 'Apple Watch',
            externalId: 'hr-full-window',
          ),
        ],
      );
      when(
        () => api.upsertHealthData(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          observations: any(named: 'observations'),
          sessions: any(named: 'sessions'),
        ),
      ).thenAnswer((_) async {});

      await HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        preferences: prefs,
        now: () => now,
        yieldToUi: () async {},
      ).syncRecentObservations(days: 14);

      final window = verify(
        () => platformSource.readMetricSamples(
          captureAny(),
          captureAny(),
          types: any(named: 'types'),
        ),
      ).captured;
      expect(window.first, DateTime(2026, 1, 13));
      expect(window.last, DateTime(2026, 1, 26, 23, 59, 59, 999));
    });

    test(
      'subsequent run reads only since the watermark minus the overlap window',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // Watermark from a prior sync: 2026-01-20.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'health_sync_watermark_weight': '2026-01-20',
        });
        final prefs = freshPrefs();
        await prefs.init();

        final platformSource = _MockHealthPlatformSource();
        final api = _MockHustlBackendHealthApi();
        final tokens = _MockTokenStorage();
        final now = DateTime(2026, 1, 26, 9);

        when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
        when(
          () => platformSource.isServiceAvailable(),
        ).thenAnswer((_) async => true);
        when(
          () => platformSource.hasPermissions(any()),
        ).thenAnswer((_) async => true);
        when(
          () => platformSource.readMetricSamples(
            any(),
            any(),
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [weightOn(now)]);
        when(
          () => api.upsertDailyMetrics(
            provider: any(named: 'provider'),
            lastSyncedAt: any(named: 'lastSyncedAt'),
            items: any(named: 'items'),
          ),
        ).thenAnswer((_) async {});

        final service = HealthBackendSyncService(
          platformSource: platformSource,
          api: api,
          tokens: tokens,
          preferences: prefs,
          now: () => now,
        );

        await service.syncRecentWeights(days: 30);

        final window = verify(
          () => platformSource.readMetricSamples(
            captureAny(),
            captureAny(),
            types: captureAny(named: 'types'),
          ),
        ).captured;
        // Start = watermark (2026-01-20) - 2-day overlap = 2026-01-18, which is
        // well within the 30-day full window so the overlap-trimmed start wins.
        expect(window[0], DateTime(2026, 1, 18));
        expect(window[1], DateTime(2026, 1, 26, 23, 59, 59, 999));

        // Watermark advances to the newest uploaded day.
        expect(await prefs.getHealthSyncWatermark('weight'), '2026-01-26');
      },
    );

    test('watermark never reaches before the full window first day', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // A stale watermark far in the past must not widen the window beyond
      // the [days] cap.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'health_sync_watermark_weight': '2025-01-01',
      });
      final prefs = freshPrefs();
      await prefs.init();

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final now = DateTime(2026, 1, 26, 9);

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((_) async => [weightOn(now)]);
      when(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async {});

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        preferences: prefs,
        now: () => now,
      );

      await service.syncRecentWeights(days: 30);

      final window = verify(
        () => platformSource.readMetricSamples(
          captureAny(),
          captureAny(),
          types: captureAny(named: 'types'),
        ),
      ).captured;
      // Clamped to the full 30-day window start, not the stale watermark.
      expect(window[0], DateTime(2025, 12, 28));
    });

    test('future-dated watermark does NOT skip sync (clock-skew guard)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // A corrupt/future-dated watermark (e.g. device clock jumped forward, or a
      // bad persisted value). Without the clamp, start = watermark - overlap
      // would land after end-of-today and the sync would read an inverted/empty
      // window — silently skipping. The guard must clamp to today so the sync
      // still runs sanely.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'health_sync_watermark_weight': '2026-02-10',
      });
      final prefs = freshPrefs();
      await prefs.init();

      final platformSource = _MockHealthPlatformSource();
      final api = _MockHustlBackendHealthApi();
      final tokens = _MockTokenStorage();
      final now = DateTime(2026, 1, 26, 9);

      when(() => tokens.getAccessToken()).thenAnswer((_) async => 'token');
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.readMetricSamples(
          any(),
          any(),
          types: any(named: 'types'),
        ),
      ).thenAnswer((_) async => [weightOn(now)]);
      when(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async {});

      final service = HealthBackendSyncService(
        platformSource: platformSource,
        api: api,
        tokens: tokens,
        preferences: prefs,
        now: () => now,
      );

      await service.syncRecentWeights(days: 30);

      final window = verify(
        () => platformSource.readMetricSamples(
          captureAny(),
          captureAny(),
          types: captureAny(named: 'types'),
        ),
      ).captured;
      // Watermark clamped to today (2026-01-26), then minus the 2-day overlap =
      // 2026-01-24. Crucially start <= end, so the read window is valid and the
      // sync runs instead of being skipped.
      final start = window[0] as DateTime;
      final end = window[1] as DateTime;
      expect(start, DateTime(2026, 1, 24));
      expect(end, DateTime(2026, 1, 26, 23, 59, 59, 999));
      expect(start.isAfter(end), isFalse);

      // The sync actually uploaded (was not silently skipped) and the persisted
      // watermark is clamped to today, never the future sample/window.
      verify(
        () => api.upsertDailyMetrics(
          provider: any(named: 'provider'),
          lastSyncedAt: any(named: 'lastSyncedAt'),
          items: any(named: 'items'),
        ),
      ).called(1);
      expect(await prefs.getHealthSyncWatermark('weight'), '2026-01-26');
    });
  });
}

ExternalActivity _activity(String id, String name) => ExternalActivity(
  platformUuid: id,
  sourceName: 'Apple Watch',
  kind: name == 'Strength'
      ? ExternalActivityKind.strengthTraining
      : ExternalActivityKind.other,
  activityName: name,
  start: DateTime(2026, 8, 20, 19),
  end: DateTime(2026, 8, 20, 20),
  activeEnergyKcal: 640,
);
