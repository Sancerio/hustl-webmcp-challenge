import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/data/writeback/apple_health_duplicate_cleanup_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockHealth extends Mock implements Health {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<HealthDataType>[]);
    registerFallbackValue(<HealthDataAccess>[]);
    registerFallbackValue(<RecordingMethod>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  HealthDataPoint workoutPoint({
    required String uuid,
    required DateTime start,
    required DateTime end,
    required bool hustl,
    HealthValue? value,
    HealthWorkoutActivityType activityType =
        HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
    String workoutType = 'FUNCTIONAL_STRENGTH_TRAINING',
  }) {
    return HealthDataPoint(
      uuid: uuid,
      value: value ?? WorkoutHealthValue(workoutActivityType: activityType),
      type: HealthDataType.WORKOUT,
      unit: HealthDataUnit.NO_UNIT,
      dateFrom: start,
      dateTo: end,
      sourcePlatform: HealthPlatformType.appleHealth,
      sourceDeviceId: 'device-id',
      sourceId: hustl ? 'com.hustl.app' : 'com.apple.Workout',
      sourceName: hustl ? 'Hustl' : 'Workout',
      workoutSummary: WorkoutSummary(
        workoutType: workoutType,
        totalDistance: 0,
        totalEnergyBurned: 0,
        totalSteps: 0,
      ),
      metadata: hustl ? const {'platform': 'hustl'} : null,
    );
  }

  test('deletes duplicate Hustl workouts while keeping mapped UUID', () async {
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.upsertWorkoutWritebackMapping('hustl:session-1', 'uuid-keep');

    final start = DateTime.utc(2025, 1, 1, 10);
    final end = DateTime.utc(2025, 1, 1, 11);

    final keep = workoutPoint(
      uuid: 'uuid-keep',
      start: start,
      end: end,
      hustl: true,
    );
    final duplicate = workoutPoint(
      uuid: 'uuid-delete',
      start: start,
      end: end,
      hustl: true,
    );
    final unique = workoutPoint(
      uuid: 'uuid-unique',
      start: start.add(const Duration(hours: 2)),
      end: end.add(const Duration(hours: 2)),
      hustl: true,
    );

    final health = _MockHealth();
    when(health.configure).thenAnswer((_) async {});
    when(
      () => health.requestAuthorization(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => health.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async => [keep, duplicate, unique]);
    when(
      () => health.deleteByUUID(
        uuid: any(named: 'uuid'),
        type: any(named: 'type'),
      ),
    ).thenAnswer((_) async => true);

    final service = AppleHealthDuplicateCleanupService(
      health: health,
      preferences: prefs,
      iosOverride: true,
    );

    final result = await service.cleanupDuplicates(
      start: start.subtract(const Duration(days: 1)),
      end: end.add(const Duration(days: 1)),
    );

    expect(result.supported, isTrue);
    expect(result.permissionsGranted, isTrue);
    expect(result.scannedCount, 3);
    expect(result.hustlWorkoutCount, 3);
    expect(result.duplicateGroupCount, 1);
    expect(result.deletedCount, 1);
    verify(
      () => health.deleteByUUID(
        uuid: 'uuid-delete',
        type: HealthDataType.WORKOUT,
      ),
    ).called(1);
    verifyNever(
      () =>
          health.deleteByUUID(uuid: 'uuid-keep', type: HealthDataType.WORKOUT),
    );
    verifyNever(
      () => health.deleteByUUID(
        uuid: 'uuid-unique',
        type: HealthDataType.WORKOUT,
      ),
    );
  });

  test('dry run does not delete but reports the would-delete count', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final start = DateTime.utc(2025, 1, 2, 10);
    final end = DateTime.utc(2025, 1, 2, 11);

    final points = [
      workoutPoint(uuid: 'uuid-1', start: start, end: end, hustl: true),
      workoutPoint(uuid: 'uuid-2', start: start, end: end, hustl: true),
    ];

    final health = _MockHealth();
    when(health.configure).thenAnswer((_) async {});
    when(
      () => health.requestAuthorization(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => health.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async => points);

    final service = AppleHealthDuplicateCleanupService(
      health: health,
      preferences: prefs,
      iosOverride: true,
    );

    final result = await service.cleanupDuplicates(
      start: start.subtract(const Duration(days: 1)),
      end: end.add(const Duration(days: 1)),
      dryRun: true,
    );

    expect(result.deletedCount, 1);
    verifyNever(
      () => health.deleteByUUID(
        uuid: any(named: 'uuid'),
        type: any(named: 'type'),
      ),
    );
  });

  test('ignores non-Hustl workouts', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final start = DateTime.utc(2025, 1, 3, 10);
    final end = DateTime.utc(2025, 1, 3, 11);

    final points = [
      workoutPoint(uuid: 'uuid-a', start: start, end: end, hustl: false),
      workoutPoint(uuid: 'uuid-b', start: start, end: end, hustl: false),
    ];

    final health = _MockHealth();
    when(health.configure).thenAnswer((_) async {});
    when(
      () => health.requestAuthorization(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => health.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async => points);

    final service = AppleHealthDuplicateCleanupService(
      health: health,
      preferences: prefs,
      iosOverride: true,
    );

    final result = await service.cleanupDuplicates(
      start: start.subtract(const Duration(days: 1)),
      end: end.add(const Duration(days: 1)),
    );

    expect(result.hustlWorkoutCount, 0);
    expect(result.duplicateGroupCount, 0);
    expect(result.deletedCount, 0);
    verifyNever(
      () => health.deleteByUUID(
        uuid: any(named: 'uuid'),
        type: any(named: 'type'),
      ),
    );
  });

  test(
    'clusters duplicates even when workoutSummary type strings differ',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final start = DateTime.utc(2025, 1, 4, 10);
      final end = DateTime.utc(2025, 1, 4, 11);

      final points = [
        workoutPoint(
          uuid: 'uuid-string-type-a',
          start: start,
          end: end,
          hustl: true,
          workoutType: 'functionalStrengthTraining',
        ),
        workoutPoint(
          uuid: 'uuid-string-type-b',
          start: start,
          end: end,
          hustl: true,
          workoutType: 'FUNCTIONAL_STRENGTH_TRAINING',
        ),
      ];

      final health = _MockHealth();
      when(health.configure).thenAnswer((_) async {});
      when(
        () => health.requestAuthorization(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => points);
      when(
        () => health.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);

      final service = AppleHealthDuplicateCleanupService(
        health: health,
        preferences: prefs,
        iosOverride: true,
      );

      final result = await service.cleanupDuplicates(
        start: start.subtract(const Duration(days: 1)),
        end: end.add(const Duration(days: 1)),
      );

      expect(result.duplicateGroupCount, 1);
      expect(result.deletedCount, 1);
    },
  );

  test(
    'does not cluster different workoutSummary types when value is not WorkoutHealthValue',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final start = DateTime.utc(2025, 1, 5, 10);
      final end = DateTime.utc(2025, 1, 5, 11);

      final points = [
        workoutPoint(
          uuid: 'uuid-summary-strength',
          start: start,
          end: end,
          hustl: true,
          value: NumericHealthValue(numericValue: 120),
          workoutType: 'FUNCTIONAL_STRENGTH_TRAINING',
        ),
        workoutPoint(
          uuid: 'uuid-summary-cycle',
          start: start,
          end: end,
          hustl: true,
          value: NumericHealthValue(numericValue: 120),
          workoutType: 'CYCLING',
        ),
      ];

      final health = _MockHealth();
      when(health.configure).thenAnswer((_) async {});
      when(
        () => health.requestAuthorization(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => points);

      final service = AppleHealthDuplicateCleanupService(
        health: health,
        preferences: prefs,
        iosOverride: true,
      );

      final result = await service.cleanupDuplicates(
        start: start.subtract(const Duration(days: 1)),
        end: end.add(const Duration(days: 1)),
      );

      expect(result.duplicateGroupCount, 0);
      expect(result.deletedCount, 0);
      verifyNever(
        () => health.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      );
    },
  );
}
