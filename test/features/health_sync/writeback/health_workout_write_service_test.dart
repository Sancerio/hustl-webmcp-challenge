import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/data/writeback/health_workout_write_service.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_record.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_write_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockHealth extends Mock implements Health {}

const _fastRetryDelays = <Duration>[
  Duration.zero,
  Duration.zero,
  Duration.zero,
  Duration.zero,
  Duration.zero,
];
late DebugPrintCallback _originalDebugPrint;

HealthWorkoutWriteService _createService({
  required _MockHealth mockHealth,
  required PreferencesService prefs,
  WorkoutWritePlatform platform = WorkoutWritePlatform.iosHealthKit,
  List<Duration> captureRetryDelays = _fastRetryDelays,
  List<Duration> preDeleteVerificationDelays = _fastRetryDelays,
}) {
  return HealthWorkoutWriteService(
    health: mockHealth,
    preferences: prefs,
    platformOverride: platform,
    captureRetryDelays: captureRetryDelays,
    preDeleteVerificationDelays: preDeleteVerificationDelays,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<HealthDataType>[]);
    registerFallbackValue(<HealthDataAccess>[]);
    registerFallbackValue(<RecordingMethod>[]);
    registerFallbackValue(HealthWorkoutActivityType.OTHER);
    registerFallbackValue(HealthDataType.WORKOUT);
    registerFallbackValue(HealthDataUnit.NO_UNIT);
    _originalDebugPrint = debugPrint;
    debugPrint = (String? _, {int? wrapWidth}) {};
  });

  tearDownAll(() {
    debugPrint = _originalDebugPrint;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('requests correct permissions for workout writeback', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final mockHealth = _MockHealth();
    when(mockHealth.configure).thenAnswer((_) async {});
    when(
      () => mockHealth.hasPermissions(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.requestAuthorization(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);

    final service = _createService(mockHealth: mockHealth, prefs: prefs);

    final granted = await service.requestPermissions({
      WorkoutPermissionScope.workouts,
      WorkoutPermissionScope.energy,
      WorkoutPermissionScope.distance,
    });

    expect(granted, isTrue);
    final captured = verify(
      () => mockHealth.requestAuthorization(
        captureAny(),
        permissions: captureAny(named: 'permissions'),
      ),
    ).captured;
    final capturedTypes = captured[0] as List<HealthDataType>;
    final capturedPermissions = captured[1] as List<HealthDataAccess>;

    expect(
      capturedTypes,
      containsAll(<HealthDataType>[
        HealthDataType.WORKOUT,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.DISTANCE_CYCLING,
        HealthDataType.DISTANCE_WALKING_RUNNING,
      ]),
    );
    expect(capturedPermissions.length, capturedTypes.length);
    // All types now request READ_WRITE to enable UUID capture.
    for (final permission in capturedPermissions) {
      expect(permission, HealthDataAccess.READ_WRITE);
    }
  });

  test(
    'getCapabilities treats workouts as granted even if energy/distance are not',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});

      // hasPermissions should return true for WORKOUT only, false otherwise
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((invocation) async {
        final types = invocation.positionalArguments[0] as List<HealthDataType>;
        // Single WORKOUT request → granted
        if (types.length == 1 && types.first == HealthDataType.WORKOUT) {
          return true;
        }
        // Distance/energy requests → not granted
        return false;
      });

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final capability = await service.getCapabilities();

      expect(capability.supported, isTrue);
      expect(capability.platform, WorkoutWritePlatform.iosHealthKit);
      // Core fix: workouts permission is recognized independently
      expect(capability.hasWorkoutPermission, isTrue);
      // Optional scopes remain ungranted in this scenario
      expect(
        capability.grantedScopes.contains(WorkoutPermissionScope.energy),
        isFalse,
      );
      expect(
        capability.grantedScopes.contains(WorkoutPermissionScope.distance),
        isFalse,
      );
    },
  );

  test(
    'getCapabilities treats workouts as granted when only WRITE is granted',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});

      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((invocation) async {
        final types = invocation.positionalArguments[0] as List<HealthDataType>;
        final permissions =
            invocation.namedArguments[#permissions] as List<HealthDataAccess>;

        if (types.length == 1 && types.first == HealthDataType.WORKOUT) {
          return permissions.length == 1 &&
              permissions.first == HealthDataAccess.WRITE;
        }
        return false;
      });

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final capability = await service.getCapabilities();

      expect(capability.supported, isTrue);
      expect(capability.platform, WorkoutWritePlatform.iosHealthKit);
      expect(capability.hasWorkoutPermission, isTrue);
    },
  );

  test(
    'getCapabilities treats heart-rate as granted when WRITE is granted',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});

      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((invocation) async {
        final types = invocation.positionalArguments[0] as List<HealthDataType>;
        final permissions =
            invocation.namedArguments[#permissions] as List<HealthDataAccess>;
        if (types.length == 1 && types.first == HealthDataType.WORKOUT) {
          return permissions.length == 1 &&
              permissions.first == HealthDataAccess.WRITE;
        }
        if (types.length == 1 && types.first == HealthDataType.HEART_RATE) {
          return permissions.length == 1 &&
              permissions.first == HealthDataAccess.WRITE;
        }
        return false;
      });

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final capability = await service.getCapabilities();

      expect(capability.supported, isTrue);
      expect(capability.hasWorkoutPermission, isTrue);
      expect(
        capability.grantedScopes.contains(WorkoutPermissionScope.heartRate),
        isTrue,
      );
    },
  );

  test(
    'getCapabilities keeps workout permission when heart-rate probe throws',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((invocation) async {
        final types = invocation.positionalArguments[0] as List<HealthDataType>;
        final permissions =
            invocation.namedArguments[#permissions] as List<HealthDataAccess>;

        if (types.length == 1 && types.first == HealthDataType.WORKOUT) {
          return permissions.length == 1 &&
              permissions.first == HealthDataAccess.WRITE;
        }
        if (types.length == 1 && types.first == HealthDataType.HEART_RATE) {
          throw PlatformException(code: 'HR_PROBE_FAILED');
        }
        return false;
      });

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final capability = await service.getCapabilities();

      expect(capability.supported, isTrue);
      expect(capability.hasWorkoutPermission, isTrue);
      expect(
        capability.grantedScopes.contains(WorkoutPermissionScope.heartRate),
        isFalse,
      );
    },
  );

  test('deleteWorkout returns true when no UUID mapping exists', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final mockHealth = _MockHealth();
    when(mockHealth.configure).thenAnswer((_) async {});
    when(
      () => mockHealth.hasPermissions(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);

    final service = _createService(mockHealth: mockHealth, prefs: prefs);

    final result = await service.deleteWorkout('missing');

    expect(result, isTrue);
    final mappings = await prefs.getWorkoutWritebackMappings();
    expect(mappings, isEmpty);
    verifyNever(
      () => mockHealth.deleteByUUID(
        uuid: any(named: 'uuid'),
        type: any(named: 'type'),
      ),
    );
  });

  test(
    'deleteWorkout removes mapping and calls plugin when UUID exists',
    () async {
      final prefs = PreferencesService();
      await prefs.init();
      await prefs.upsertWorkoutWritebackMapping('session-1', 'uuid-123');

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkout('session-1');

      expect(result, isTrue);
      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings, isEmpty);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-123',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
    },
  );

  test(
    'deleteWorkoutByRecord keeps watch UUID and deletes phone duplicate',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-by-record',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
      );

      HealthDataPoint point(String uuid, {required String sourceDeviceId}) {
        return HealthDataPoint(
          uuid: uuid,
          value: WorkoutHealthValue(
            workoutActivityType:
                HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
          ),
          type: HealthDataType.WORKOUT,
          unit: HealthDataUnit.NO_UNIT,
          dateFrom: record.startedAt,
          dateTo: record.endedAt,
          sourcePlatform: HealthPlatformType.appleHealth,
          sourceDeviceId: sourceDeviceId,
          sourceId: 'com.hustl.app',
          sourceName: 'Hustl',
          workoutSummary: WorkoutSummary(
            workoutType: 'functionalStrengthTraining',
            totalDistance: 0,
            totalEnergyBurned: 0,
            totalSteps: 0,
          ),
        );
      }

      final phonePoint = point('uuid-phone', sourceDeviceId: 'phone');
      final watchPoint = point('uuid-watch', sourceDeviceId: 'watch');

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => [phonePoint, watchPoint]);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(
        record,
        keepUuid: 'uuid-watch',
      );

      expect(result, isTrue);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-phone',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      verifyNever(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-watch',
          type: HealthDataType.WORKOUT,
        ),
      );
    },
  );

  test(
    'deleteWorkoutByRecord matches same-start Hustl duplicate when watch end time differs',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-by-start-time',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
      );

      HealthDataPoint point(
        String uuid, {
        required String sourceDeviceId,
        required DateTime end,
      }) {
        return HealthDataPoint(
          uuid: uuid,
          value: WorkoutHealthValue(
            workoutActivityType:
                HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
          ),
          type: HealthDataType.WORKOUT,
          unit: HealthDataUnit.NO_UNIT,
          dateFrom: record.startedAt,
          dateTo: end,
          sourcePlatform: HealthPlatformType.appleHealth,
          sourceDeviceId: sourceDeviceId,
          sourceId: 'com.hustl.app',
          sourceName: 'Hustl',
          workoutSummary: WorkoutSummary(
            workoutType: 'functionalStrengthTraining',
            totalDistance: 0,
            totalEnergyBurned: 0,
            totalSteps: 0,
          ),
        );
      }

      final phonePoint = point(
        'uuid-phone',
        sourceDeviceId: 'phone',
        end: record.endedAt,
      );
      final watchPoint = point(
        'uuid-watch',
        sourceDeviceId: 'watch',
        end: record.endedAt.add(const Duration(minutes: 12)),
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => [phonePoint, watchPoint]);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(
        record,
        keepUuid: 'uuid-watch',
      );

      expect(result, isTrue);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-phone',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      verifyNever(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-watch',
          type: HealthDataType.WORKOUT,
        ),
      );
    },
  );

  test(
    'deleteWorkoutByRecord keeps mapping when mapped UUID delete fails',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-failure',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
      );
      await prefs.upsertWorkoutWritebackMapping(
        record.externalId,
        'uuid-mapped',
      );

      final mappedPoint = HealthDataPoint(
        uuid: 'uuid-mapped',
        value: WorkoutHealthValue(
          workoutActivityType:
              HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: record.startedAt,
        dateTo: record.endedAt,
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'device',
        sourceId: 'com.hustl.app',
        sourceName: 'Hustl',
        workoutSummary: WorkoutSummary(
          workoutType: 'functionalStrengthTraining',
          totalDistance: 0,
          totalEnergyBurned: 0,
          totalSteps: 0,
        ),
        metadata: const {'platform': 'hustl'},
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => [mappedPoint]);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => false);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isFalse);
      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings[record.externalId], 'uuid-mapped');
    },
  );

  test(
    'deleteWorkoutByRecord returns false when matching workouts have no UUID yet',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-pending-uuid',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
      );

      final unresolvedPoint = HealthDataPoint(
        uuid: '',
        value: WorkoutHealthValue(
          workoutActivityType:
              HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: record.startedAt,
        dateTo: record.endedAt,
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'device',
        sourceId: 'com.hustl.app',
        sourceName: 'Hustl',
        workoutSummary: WorkoutSummary(
          workoutType: 'functionalStrengthTraining',
          totalDistance: 0,
          totalEnergyBurned: 0,
          totalSteps: 0,
        ),
        metadata: const {'platform': 'hustl'},
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => [unresolvedPoint]);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isFalse);
      verifyNever(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      );
    },
  );

  test(
    'deleteWorkoutByRecord retries when unresolved UUID-less matches remain after deleting known UUIDs',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-partial-uuid-resolution',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
      );

      final resolvedPoint = HealthDataPoint(
        uuid: 'uuid-phone-1',
        value: WorkoutHealthValue(
          workoutActivityType:
              HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: record.startedAt,
        dateTo: record.endedAt,
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'device',
        sourceId: 'com.hustl.app',
        sourceName: 'Hustl',
        workoutSummary: WorkoutSummary(
          workoutType: 'functionalStrengthTraining',
          totalDistance: 0,
          totalEnergyBurned: 0,
          totalSteps: 0,
        ),
        metadata: const {'platform': 'hustl'},
      );
      final unresolvedPoint = HealthDataPoint(
        uuid: '',
        value: WorkoutHealthValue(
          workoutActivityType:
              HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: record.startedAt,
        dateTo: record.endedAt,
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'device',
        sourceId: 'com.hustl.app',
        sourceName: 'Hustl',
        workoutSummary: WorkoutSummary(
          workoutType: 'functionalStrengthTraining',
          totalDistance: 0,
          totalEnergyBurned: 0,
          totalSteps: 0,
        ),
        metadata: const {'platform': 'hustl'},
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => [resolvedPoint, unresolvedPoint]);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.delete(
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => true);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isFalse);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-phone-1',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      verifyNever(
        () => mockHealth.delete(
          type: HealthDataType.HEART_RATE,
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      );
    },
  );

  test(
    'deleteWorkoutByRecord returns false when workout lookup fails',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-read-failure',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenThrow(Exception('read failed'));

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isFalse);
      verifyNever(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      );
    },
  );

  test(
    'deleteWorkoutByRecord falls back to mapped UUID when workout lookup fails',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-read-failure-with-mapping',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
      );
      await prefs.upsertWorkoutWritebackMapping(
        record.externalId,
        'uuid-mapped',
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenThrow(Exception('read failed'));
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isTrue);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-mapped',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings.containsKey(record.externalId), isFalse);
    },
  );

  test(
    'deleteWorkoutByRecord retries when no candidates remain but HR marker cleanup fails',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-no-candidates',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
        averageHeartRateBpm: 123,
        maxHeartRateBpm: 166,
      );

      final midpointEpoch = DateTime.utc(
        2025,
        10,
        10,
        12,
        30,
      ).millisecondsSinceEpoch;
      final endEpoch = DateTime.utc(2025, 10, 10, 13).millisecondsSinceEpoch;
      await prefs.setRawString(
        'workout_writeback_hr_markers_v1',
        json.encode({
          record.externalId: [midpointEpoch, endEpoch],
        }),
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => const []);
      when(
        () => mockHealth.delete(
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => false);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isFalse);
      final rawMarkers = await prefs.getRawString(
        'workout_writeback_hr_markers_v1',
      );
      expect(rawMarkers, isNotNull);
      final decoded = json.decode(rawMarkers!) as Map<String, dynamic>;
      expect(decoded.containsKey(record.externalId), isTrue);
      verify(
        () => mockHealth.delete(
          type: HealthDataType.HEART_RATE,
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).called(2);
      verifyNever(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      );
    },
  );

  test(
    'deleteWorkoutByRecord succeeds when workout delete works but HR cleanup fails',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-hr-cleanup-failure',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
        averageHeartRateBpm: 123,
        maxHeartRateBpm: 166,
      );
      await prefs.upsertWorkoutWritebackMapping(
        record.externalId,
        'uuid-mapped',
      );

      final midpointEpoch = DateTime.utc(
        2025,
        10,
        10,
        12,
        30,
      ).millisecondsSinceEpoch;
      final endEpoch = DateTime.utc(2025, 10, 10, 13).millisecondsSinceEpoch;
      await prefs.setRawString(
        'workout_writeback_hr_markers_v1',
        json.encode({
          record.externalId: [midpointEpoch, endEpoch],
        }),
      );

      final mappedPoint = HealthDataPoint(
        uuid: 'uuid-mapped',
        value: WorkoutHealthValue(
          workoutActivityType:
              HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: record.startedAt,
        dateTo: record.endedAt,
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'device',
        sourceId: 'com.hustl.app',
        sourceName: 'Hustl',
        workoutSummary: WorkoutSummary(
          workoutType: 'functionalStrengthTraining',
          totalDistance: 0,
          totalEnergyBurned: 0,
          totalSteps: 0,
        ),
        metadata: const {'platform': 'hustl'},
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => [mappedPoint]);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.delete(
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => false);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isTrue);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-mapped',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      verify(
        () => mockHealth.delete(
          type: HealthDataType.HEART_RATE,
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).called(2);

      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings.containsKey(record.externalId), isFalse);

      final rawMarkers = await prefs.getRawString(
        'workout_writeback_hr_markers_v1',
      );
      expect(rawMarkers, isNotNull);
      final decoded = json.decode(rawMarkers!) as Map<String, dynamic>;
      expect(decoded.containsKey(record.externalId), isTrue);
    },
  );

  test(
    'deleteWorkoutByRecord does not delete heart rate by fallback timestamp when no markers exist',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-delete-no-hr-markers',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 12),
        endedAt: DateTime.utc(2025, 10, 10, 13),
        duration: const Duration(hours: 1).inSeconds,
        averageHeartRateBpm: 124,
        maxHeartRateBpm: 167,
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => const []);
      when(
        () => mockHealth.delete(
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => false);

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.deleteWorkoutByRecord(record);

      expect(result, isTrue);
      verifyNever(
        () => mockHealth.delete(
          type: HealthDataType.HEART_RATE,
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      );
      verifyNever(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      );
    },
  );

  test('upsertWorkout deletes existing duplicates before writing', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final mockHealth = _MockHealth();
    when(mockHealth.configure).thenAnswer((_) async {});
    when(
      () => mockHealth.hasPermissions(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.deleteByUUID(
        uuid: any(named: 'uuid'),
        type: any(named: 'type'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.writeWorkoutData(
        activityType: any(named: 'activityType'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async => true);

    final record = WorkoutRecord(
      sessionId: 'session-1',
      activityType: WorkoutActivityType.strength,
      startedAt: DateTime.utc(2025, 10, 9, 17, 29),
      endedAt: DateTime.utc(2025, 10, 9, 18, 52, 38),
      duration: const Duration(hours: 1, minutes: 23, seconds: 38).inSeconds,
    );

    HealthDataPoint hustlPoint(String uuid) {
      return HealthDataPoint(
        uuid: uuid,
        value: WorkoutHealthValue(
          workoutActivityType:
              HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: record.startedAt,
        dateTo: record.endedAt,
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'device-id',
        sourceId: 'com.hustl.app',
        sourceName: 'Hustl',
        workoutSummary: WorkoutSummary(
          workoutType: 'functionalStrengthTraining',
          totalDistance: 0,
          totalEnergyBurned: 0,
          totalSteps: 0,
        ),
        metadata: {
          'platform': 'hustl',
          'HKMetadataKeySyncIdentifier': record.sessionId,
          'HKMetadataKeyExternalUUID': record.externalId,
        },
      );
    }

    final existingPoint = hustlPoint('uuid-existing');
    final writtenPoint = hustlPoint('uuid-written');

    var getCalls = 0;
    when(
      () => mockHealth.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async {
      getCalls += 1;
      if (getCalls == 1) return [existingPoint];
      if (getCalls == 2) return [];
      return [writtenPoint];
    });

    final service = _createService(mockHealth: mockHealth, prefs: prefs);

    final result = await service.upsertWorkout(record);

    expect(result.success, isTrue);
    verify(
      () => mockHealth.deleteByUUID(
        uuid: 'uuid-existing',
        type: HealthDataType.WORKOUT,
      ),
    ).called(1);
    verify(
      () => mockHealth.writeWorkoutData(
        activityType: any(named: 'activityType'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).called(1);
    final mappings = await prefs.getWorkoutWritebackMappings();
    expect(mappings['hustl:${record.sessionId}'], 'uuid-written');
  });

  test(
    'upsertWorkout writes heart-rate samples when permission is granted',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeHealthData(
          value: any(named: 'value'),
          unit: any(named: 'unit'),
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => const []);

      final record = WorkoutRecord(
        sessionId: 'session-hr',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 17, 0),
        endedAt: DateTime.utc(2025, 10, 10, 18, 0),
        duration: const Duration(hours: 1).inSeconds,
        averageHeartRateBpm: 128.54,
        maxHeartRateBpm: 169.96,
      );

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.upsertWorkout(record);

      expect(result.success, isTrue);
      verify(
        () => mockHealth.writeHealthData(
          value: 128.5,
          unit: HealthDataUnit.BEATS_PER_MINUTE,
          type: HealthDataType.HEART_RATE,
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).called(1);
      verify(
        () => mockHealth.writeHealthData(
          value: 170.0,
          unit: HealthDataUnit.BEATS_PER_MINUTE,
          type: HealthDataType.HEART_RATE,
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).called(1);
    },
  );

  test(
    'upsertWorkout removes previously written HR samples before rewrite',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeHealthData(
          value: any(named: 'value'),
          unit: any(named: 'unit'),
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.delete(
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => const []);

      final record = WorkoutRecord(
        sessionId: 'session-hr-rewrite',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 17, 0),
        endedAt: DateTime.utc(2025, 10, 10, 18, 0),
        duration: const Duration(hours: 1).inSeconds,
        averageHeartRateBpm: 129,
        maxHeartRateBpm: 171,
      );

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final first = await service.upsertWorkout(record);
      final second = await service.upsertWorkout(record);

      expect(first.success, isTrue);
      expect(second.success, isTrue);
      verify(
        () => mockHealth.delete(
          type: HealthDataType.HEART_RATE,
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).called(2);
    },
  );

  test(
    'upsertWorkout merges existing and new HR markers when cleanup fails',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeHealthData(
          value: any(named: 'value'),
          unit: any(named: 'unit'),
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => const []);
      when(
        () => mockHealth.delete(
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => false);

      final original = WorkoutRecord(
        sessionId: 'session-hr-marker-merge',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 17, 0),
        endedAt: DateTime.utc(2025, 10, 10, 18, 0),
        duration: const Duration(hours: 1).inSeconds,
        averageHeartRateBpm: 129,
        maxHeartRateBpm: 171,
      );
      final edited = WorkoutRecord(
        sessionId: 'session-hr-marker-merge',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 17, 0),
        endedAt: DateTime.utc(2025, 10, 10, 18, 30),
        duration: const Duration(minutes: 90).inSeconds,
        averageHeartRateBpm: 132,
        maxHeartRateBpm: 176,
      );

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final first = await service.upsertWorkout(original);
      final second = await service.upsertWorkout(edited);

      expect(first.success, isTrue);
      expect(second.success, isTrue);

      final rawMarkers = await prefs.getRawString(
        'workout_writeback_hr_markers_v1',
      );
      expect(rawMarkers, isNotNull);
      final decoded = json.decode(rawMarkers!) as Map<String, dynamic>;
      final stored = (decoded[original.externalId] as List)
          .whereType<num>()
          .map((value) => value.toInt())
          .toSet();

      expect(
        stored,
        equals({
          DateTime.utc(2025, 10, 10, 17, 30).millisecondsSinceEpoch,
          DateTime.utc(2025, 10, 10, 18, 0).millisecondsSinceEpoch,
          DateTime.utc(2025, 10, 10, 17, 45).millisecondsSinceEpoch,
          DateTime.utc(2025, 10, 10, 18, 30).millisecondsSinceEpoch,
        }),
      );
    },
  );

  test(
    'upsertWorkout keeps HR markers when cleanup fails and new payload has no HR',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeHealthData(
          value: any(named: 'value'),
          unit: any(named: 'unit'),
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => const []);

      var deleteHeartRateCalls = 0;
      when(
        () => mockHealth.delete(
          type: any(named: 'type'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async {
        deleteHeartRateCalls += 1;
        return false;
      });

      final withHeartRate = WorkoutRecord(
        sessionId: 'session-hr-markers',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 17, 0),
        endedAt: DateTime.utc(2025, 10, 10, 18, 0),
        duration: const Duration(hours: 1).inSeconds,
        averageHeartRateBpm: 125,
        maxHeartRateBpm: 165,
      );
      final withoutHeartRate = WorkoutRecord(
        sessionId: 'session-hr-markers',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 10, 17, 0),
        endedAt: DateTime.utc(2025, 10, 10, 18, 0),
        duration: const Duration(hours: 1).inSeconds,
      );

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final first = await service.upsertWorkout(withHeartRate);
      final second = await service.upsertWorkout(withoutHeartRate);

      expect(first.success, isTrue);
      expect(second.success, isTrue);
      expect(deleteHeartRateCalls, greaterThan(0));

      final rawMarkers = await prefs.getRawString(
        'workout_writeback_hr_markers_v1',
      );
      expect(rawMarkers, isNotNull);
      final decoded = json.decode(rawMarkers!) as Map<String, dynamic>;
      expect(decoded.containsKey(withHeartRate.externalId), isTrue);
    },
  );

  test('upsertWorkout succeeds even when UUID capture fails', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final mockHealth = _MockHealth();
    when(mockHealth.configure).thenAnswer((_) async {});
    when(
      () => mockHealth.hasPermissions(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.writeWorkoutData(
        activityType: any(named: 'activityType'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async => const []);

    final record = WorkoutRecord(
      sessionId: 'session-no-uuid',
      activityType: WorkoutActivityType.strength,
      startedAt: DateTime.utc(2025, 10, 12, 10),
      endedAt: DateTime.utc(2025, 10, 12, 11),
      duration: const Duration(hours: 1).inSeconds,
    );

    final service = _createService(mockHealth: mockHealth, prefs: prefs);

    final result = await service.upsertWorkout(record);

    expect(result.success, isTrue);
    final mappings = await prefs.getWorkoutWritebackMappings();
    expect(mappings, isEmpty);
  });

  test('upsertWorkout maps cardio to mixed cardio on iOS', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final mockHealth = _MockHealth();
    when(mockHealth.configure).thenAnswer((_) async {});
    when(
      () => mockHealth.hasPermissions(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.writeWorkoutData(
        activityType: any(named: 'activityType'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async => const []);

    final service = _createService(mockHealth: mockHealth, prefs: prefs);

    final record = WorkoutRecord(
      sessionId: 'session-cardio',
      activityType: WorkoutActivityType.cardio,
      startedAt: DateTime.utc(2025, 10, 12, 10),
      endedAt: DateTime.utc(2025, 10, 12, 10, 30),
      duration: const Duration(minutes: 30).inSeconds,
    );

    final result = await service.upsertWorkout(record);

    expect(result.success, isTrue);
    verify(
      () => mockHealth.writeWorkoutData(
        activityType: HealthWorkoutActivityType.MIXED_CARDIO,
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).called(1);
  });

  test('upsertWorkout maps cardio to other on Android', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final mockHealth = _MockHealth();
    when(mockHealth.configure).thenAnswer((_) async {});
    when(
      () => mockHealth.hasPermissions(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.writeWorkoutData(
        activityType: any(named: 'activityType'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async => const []);

    final service = _createService(
      mockHealth: mockHealth,
      prefs: prefs,
      platform: WorkoutWritePlatform.androidHealthConnect,
    );

    final record = WorkoutRecord(
      sessionId: 'session-cardio-android',
      activityType: WorkoutActivityType.cardio,
      startedAt: DateTime.utc(2025, 10, 12, 10),
      endedAt: DateTime.utc(2025, 10, 12, 10, 30),
      duration: const Duration(minutes: 30).inSeconds,
    );

    final result = await service.upsertWorkout(record);

    expect(result.success, isTrue);
    verify(
      () => mockHealth.writeWorkoutData(
        activityType: HealthWorkoutActivityType.OTHER,
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).called(1);
  });

  test('upsertWorkout skips deleting workouts from other sources', () async {
    final prefs = PreferencesService();
    await prefs.init();

    final mockHealth = _MockHealth();
    when(mockHealth.configure).thenAnswer((_) async {});
    when(
      () => mockHealth.hasPermissions(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.deleteByUUID(
        uuid: any(named: 'uuid'),
        type: any(named: 'type'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockHealth.writeWorkoutData(
        activityType: any(named: 'activityType'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async => true);

    final record = WorkoutRecord(
      sessionId: 'session-2',
      activityType: WorkoutActivityType.strength,
      startedAt: DateTime.utc(2025, 10, 10, 12),
      endedAt: DateTime.utc(2025, 10, 10, 13, 10),
      duration: const Duration(minutes: 70).inSeconds,
    );

    final foreignPoint = HealthDataPoint(
      uuid: 'uuid-foreign',
      value: WorkoutHealthValue(
        workoutActivityType:
            HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
      ),
      type: HealthDataType.WORKOUT,
      unit: HealthDataUnit.NO_UNIT,
      dateFrom: record.startedAt,
      dateTo: record.endedAt,
      sourcePlatform: HealthPlatformType.appleHealth,
      sourceDeviceId: 'watch',
      sourceId: 'com.apple.Workout',
      sourceName: 'Activity',
      workoutSummary: WorkoutSummary(
        workoutType: 'functionalStrengthTraining',
        totalDistance: 0,
        totalEnergyBurned: 0,
        totalSteps: 0,
      ),
    );

    final writtenPoint = HealthDataPoint(
      uuid: 'uuid-written',
      value: foreignPoint.value,
      type: foreignPoint.type,
      unit: foreignPoint.unit,
      dateFrom: foreignPoint.dateFrom,
      dateTo: foreignPoint.dateTo,
      sourcePlatform: foreignPoint.sourcePlatform,
      sourceDeviceId: foreignPoint.sourceDeviceId,
      sourceId: 'com.hustl.app',
      sourceName: 'Hustl',
      workoutSummary: foreignPoint.workoutSummary,
    );

    var getCalls = 0;
    when(
      () => mockHealth.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenAnswer((_) async {
      getCalls += 1;
      if (getCalls == 1) return [foreignPoint];
      return [writtenPoint];
    });

    final service = _createService(mockHealth: mockHealth, prefs: prefs);

    final result = await service.upsertWorkout(record);

    expect(result.success, isTrue);
    verifyNever(
      () => mockHealth.deleteByUUID(
        uuid: 'uuid-foreign',
        type: HealthDataType.WORKOUT,
      ),
    );
    verify(
      () => mockHealth.writeWorkoutData(
        activityType: any(named: 'activityType'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        totalEnergyBurned: any(named: 'totalEnergyBurned'),
        totalDistance: any(named: 'totalDistance'),
        title: any(named: 'title'),
      ),
    ).called(1);
  });

  test(
    'upsertWorkout deletes source-only phone duplicates for mapped non-watch device',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-phone-source-only-duplicates',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 15, 9),
        endedAt: DateTime.utc(2025, 10, 15, 10),
        duration: const Duration(hours: 1).inSeconds,
      );
      await prefs.upsertWorkoutWritebackMapping(
        record.externalId,
        'uuid-phone-1',
      );

      HealthDataPoint point(
        String uuid, {
        required String sourceDeviceId,
        Map<String, dynamic>? metadata,
      }) {
        return HealthDataPoint(
          uuid: uuid,
          value: WorkoutHealthValue(
            workoutActivityType:
                HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
          ),
          type: HealthDataType.WORKOUT,
          unit: HealthDataUnit.NO_UNIT,
          dateFrom: record.startedAt,
          dateTo: record.endedAt,
          sourcePlatform: HealthPlatformType.appleHealth,
          sourceDeviceId: sourceDeviceId,
          sourceId: 'com.hustl.app',
          sourceName: 'Hustl',
          workoutSummary: WorkoutSummary(
            workoutType: 'functionalStrengthTraining',
            totalDistance: 0,
            totalEnergyBurned: 0,
            totalSteps: 0,
          ),
          metadata: metadata,
        );
      }

      final phonePoint1 = point('uuid-phone-1', sourceDeviceId: 'iphone-1');
      final phonePoint2 = point('uuid-phone-2', sourceDeviceId: 'iphone-1');
      final writtenPoint = point(
        'uuid-written',
        sourceDeviceId: 'iphone-1',
        metadata: const {'platform': 'hustl'},
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);

      var getCalls = 0;
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async {
        getCalls += 1;
        if (getCalls == 1) return [phonePoint1, phonePoint2];
        if (getCalls == 2) return const [];
        return [writtenPoint];
      });

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.upsertWorkout(record);

      expect(result.success, isTrue);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-phone-1',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-phone-2',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings[record.externalId], 'uuid-written');
    },
  );

  test(
    'upsertWorkout does not delete source-only watch-device matches',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-watch-source-only',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 15, 11),
        endedAt: DateTime.utc(2025, 10, 15, 12),
        duration: const Duration(hours: 1).inSeconds,
      );

      HealthDataPoint point(
        String uuid, {
        required String sourceDeviceId,
        Map<String, dynamic>? metadata,
      }) {
        return HealthDataPoint(
          uuid: uuid,
          value: WorkoutHealthValue(
            workoutActivityType:
                HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
          ),
          type: HealthDataType.WORKOUT,
          unit: HealthDataUnit.NO_UNIT,
          dateFrom: record.startedAt,
          dateTo: record.endedAt,
          sourcePlatform: HealthPlatformType.appleHealth,
          sourceDeviceId: sourceDeviceId,
          sourceId: 'com.hustl.app',
          sourceName: 'Hustl',
          workoutSummary: WorkoutSummary(
            workoutType: 'functionalStrengthTraining',
            totalDistance: 0,
            totalEnergyBurned: 0,
            totalSteps: 0,
          ),
          metadata: metadata,
        );
      }

      final watchPoint = point(
        'uuid-watch-old',
        sourceDeviceId: 'watch-series-9',
      );
      final writtenPoint = point(
        'uuid-written',
        sourceDeviceId: 'iphone-1',
        metadata: const {'platform': 'hustl'},
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);

      var getCalls = 0;
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async {
        getCalls += 1;
        if (getCalls <= 4) return [watchPoint];
        return [writtenPoint];
      });

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.upsertWorkout(record);

      expect(result.success, isTrue);
      verifyNever(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-watch-old',
          type: HealthDataType.WORKOUT,
        ),
      );
      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings[record.externalId], 'uuid-written');
    },
  );

  test(
    'upsertWorkout ignores low-confidence UUID matches and captures strong UUID on retry',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-capture-retry',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 14, 9),
        endedAt: DateTime.utc(2025, 10, 14, 10),
        duration: const Duration(hours: 1).inSeconds,
      );

      final lowConfidencePoint = HealthDataPoint(
        uuid: 'uuid-low-confidence',
        value: WorkoutHealthValue(
          workoutActivityType:
              HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: record.startedAt,
        dateTo: record.endedAt,
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'watch',
        sourceId: 'com.apple.Workout',
        sourceName: 'Workout',
        workoutSummary: WorkoutSummary(
          workoutType: 'functionalStrengthTraining',
          totalDistance: 0,
          totalEnergyBurned: 0,
          totalSteps: 0,
        ),
        metadata: const {
          // This passes _isLikelyHustlWorkout but should remain low-confidence.
          'title': 'Hustl Workout',
        },
      );

      final strongPoint = HealthDataPoint(
        uuid: 'uuid-strong',
        value: lowConfidencePoint.value,
        type: lowConfidencePoint.type,
        unit: lowConfidencePoint.unit,
        dateFrom: lowConfidencePoint.dateFrom,
        dateTo: lowConfidencePoint.dateTo,
        sourcePlatform: lowConfidencePoint.sourcePlatform,
        sourceDeviceId: lowConfidencePoint.sourceDeviceId,
        sourceId: 'com.hustl.app',
        sourceName: 'Hustl',
        workoutSummary: lowConfidencePoint.workoutSummary,
        metadata: const {'platform': 'hustl'},
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);

      var getCalls = 0;
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async {
        getCalls += 1;
        if (getCalls == 1) return const [];
        if (getCalls == 2) return [lowConfidencePoint];
        return [strongPoint];
      });

      final service = _createService(
        mockHealth: mockHealth,
        prefs: prefs,
        captureRetryDelays: const [Duration.zero, Duration.zero],
      );

      final result = await service.upsertWorkout(record);

      expect(result.success, isTrue);
      expect(getCalls, 3);

      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings[record.externalId], 'uuid-strong');
      expect(mappings[record.externalId], isNot('uuid-low-confidence'));
    },
  );

  test(
    'upsertWorkout deletes all matches even when a UUID mapping exists',
    () async {
      final prefs = PreferencesService();
      await prefs.init();

      final record = WorkoutRecord(
        sessionId: 'session-3',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2025, 10, 11, 10),
        endedAt: DateTime.utc(2025, 10, 11, 11),
        duration: const Duration(hours: 1).inSeconds,
        energyKilocalories: 123,
      );

      await prefs.upsertWorkoutWritebackMapping(
        record.externalId,
        'uuid-mapped',
      );

      final mockHealth = _MockHealth();
      when(mockHealth.configure).thenAnswer((_) async {});
      when(
        () => mockHealth.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.deleteByUUID(
          uuid: any(named: 'uuid'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockHealth.writeWorkoutData(
          activityType: any(named: 'activityType'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          totalEnergyBurned: any(named: 'totalEnergyBurned'),
          totalDistance: any(named: 'totalDistance'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => true);

      HealthDataPoint workoutPoint(String uuid) {
        return HealthDataPoint(
          uuid: uuid,
          value: WorkoutHealthValue(
            workoutActivityType:
                HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
          ),
          type: HealthDataType.WORKOUT,
          unit: HealthDataUnit.NO_UNIT,
          dateFrom: record.startedAt,
          dateTo: record.endedAt,
          sourcePlatform: HealthPlatformType.appleHealth,
          sourceDeviceId: 'device-id',
          sourceId: 'com.hustl.app',
          sourceName: 'Hustl',
          workoutSummary: WorkoutSummary(
            workoutType: 'functionalStrengthTraining',
            totalDistance: 0,
            totalEnergyBurned: 123,
            totalSteps: 0,
          ),
          metadata: const {'platform': 'hustl'},
        );
      }

      final mappedPoint = workoutPoint('uuid-mapped');
      final extraPoint = workoutPoint('uuid-extra');
      final writtenPoint = workoutPoint('uuid-written');

      var getCalls = 0;
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async {
        getCalls += 1;
        if (getCalls == 1) return [mappedPoint, extraPoint];
        if (getCalls == 2) return [];
        return [writtenPoint];
      });

      final service = _createService(mockHealth: mockHealth, prefs: prefs);

      final result = await service.upsertWorkout(record);

      expect(result.success, isTrue);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-mapped',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      verify(
        () => mockHealth.deleteByUUID(
          uuid: 'uuid-extra',
          type: HealthDataType.WORKOUT,
        ),
      ).called(1);
      final mappings = await prefs.getWorkoutWritebackMappings();
      expect(mappings[record.externalId], 'uuid-written');
    },
  );
}
