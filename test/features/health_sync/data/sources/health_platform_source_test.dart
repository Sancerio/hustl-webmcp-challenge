import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/features/health_sync/data/sources/health_platform_source.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';

class _MockHealth extends Mock implements Health {}

void main() {
  late _MockHealth mockHealth;
  late HealthPlatformSource source;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(<HealthDataType>[]);
    registerFallbackValue(<RecordingMethod>[]);
    registerFallbackValue(RecordingMethod.automatic);
    registerFallbackValue(HealthDataType.WEIGHT);
  });

  setUp(() {
    mockHealth = _MockHealth();
    source = HealthPlatformSource(health: mockHealth);

    when(() => mockHealth.configure()).thenAnswer((_) async {});
    when(() => mockHealth.isDataTypeAvailable(any())).thenReturn(true);
  });

  test(
    'continues fetching when one metric type fails and records a warning',
    () async {
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((invocation) async {
        final types = invocation.namedArguments[#types] as List<HealthDataType>;
        final requested = types.first;
        if (requested == HealthDataType.BODY_FAT_PERCENTAGE) {
          throw PlatformException(
            code: 'HEALTH_ERROR',
            message: 'errorAuthorizationDenied',
          );
        }
        if (requested == HealthDataType.WEIGHT) {
          return [
            HealthDataPoint(
              uuid: 'weight-1',
              value: NumericHealthValue(numericValue: 82.0),
              type: HealthDataType.WEIGHT,
              unit: HealthDataUnit.KILOGRAM,
              dateFrom: DateTime(2024, 5, 20, 8),
              dateTo: DateTime(2024, 5, 20, 8, 5),
              sourcePlatform: HealthPlatformType.appleHealth,
              sourceDeviceId: 'device',
              sourceId: 'source',
              sourceName: 'Scale',
              recordingMethod: RecordingMethod.manual,
            ),
          ];
        }
        return <HealthDataPoint>[];
      });

      final samples = await source.readMetricSamples(
        DateTime(2024, 5, 19),
        DateTime(2024, 5, 20),
      );

      expect(samples.length, equals(1));
      final warnings = source.drainWarnings();
      expect(warnings.length, equals(1));
      expect(warnings.first, contains('Body Fat'));
      expect(source.drainWarnings(), isEmpty);
    },
  );

  test(
    'explicit backend-sync read rethrows a platform failure after warning',
    () async {
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenThrow(
        PlatformException(code: 'HEALTH_ERROR', message: 'temporary failure'),
      );

      await expectLater(
        source.readMetricSamples(
          DateTime(2024, 5, 19),
          DateTime(2024, 5, 20),
          types: const [HealthDataType.HEART_RATE],
        ),
        throwsA(isA<PlatformException>()),
      );

      expect(source.drainWarnings(), hasLength(1));
    },
  );

  test(
    'explicit backend-sync read skips an authorization-denied signal',
    () async {
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenThrow(
        PlatformException(
          code: 'HEALTH_ERROR',
          message: 'errorAuthorizationDenied',
        ),
      );

      final samples = await source.readMetricSamples(
        DateTime(2024, 5, 19),
        DateTime(2024, 5, 20),
        types: const [HealthDataType.BLOOD_OXYGEN],
      );

      expect(samples, isEmpty);
      expect(source.drainWarnings(), hasLength(1));
    },
  );

  test('explicit backend-sync read skips not-determined heart rate', () async {
    when(
      () => mockHealth.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
        recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
      ),
    ).thenThrow(
      PlatformException(
        code: 'HEALTH_ERROR',
        message: 'Error getting health data: Authorization not determined',
      ),
    );

    final samples = await source.readMetricSamples(
      DateTime(2024, 5, 19),
      DateTime(2024, 5, 20),
      types: const [HealthDataType.HEART_RATE],
    );

    expect(samples, isEmpty);
    expect(source.drainWarnings(), isEmpty);
  });

  test(
    'ignores not-determined warnings for optional recovery metrics on iOS',
    () async {
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((invocation) async {
        final types = invocation.namedArguments[#types] as List<HealthDataType>;
        final requested = types.first;
        if (requested == HealthDataType.HEART_RATE_VARIABILITY_SDNN) {
          throw PlatformException(
            code: 'HEALTH_ERROR',
            message: 'Error getting health data: Authorization not determined',
          );
        }
        if (requested == HealthDataType.WEIGHT) {
          return [
            HealthDataPoint(
              uuid: 'weight-1',
              value: NumericHealthValue(numericValue: 82.0),
              type: HealthDataType.WEIGHT,
              unit: HealthDataUnit.KILOGRAM,
              dateFrom: DateTime(2024, 5, 20, 8),
              dateTo: DateTime(2024, 5, 20, 8, 5),
              sourcePlatform: HealthPlatformType.appleHealth,
              sourceDeviceId: 'device',
              sourceId: 'source',
              sourceName: 'Scale',
              recordingMethod: RecordingMethod.manual,
            ),
          ];
        }
        return <HealthDataPoint>[];
      });

      final samples = await source.readMetricSamples(
        DateTime(2024, 5, 19),
        DateTime(2024, 5, 20),
      );

      expect(samples.length, equals(1));
      expect(source.drainWarnings(), isEmpty);
    },
    skip: !Platform.isIOS,
  );

  test(
    'provider availability reports needs-install when Health Connect is absent',
    () async {
      when(
        () => mockHealth.getHealthConnectSdkStatus(),
      ).thenAnswer((_) async => HealthConnectSdkStatus.sdkUnavailable);

      final availability = await source.providerAvailability();

      if (Platform.isAndroid) {
        expect(availability, HealthProviderAvailability.needsInstall);
      } else if (Platform.isIOS) {
        // HealthKit is built in; WEIGHT availability stands in for reachability.
        expect(availability, HealthProviderAvailability.available);
      } else {
        // Desktop/test host: health data is unsupported.
        expect(availability, HealthProviderAvailability.unsupported);
      }
    },
  );

  test(
    'per-signal availability is data-driven: a signal with no samples reads false',
    () async {
      // Every read returns empty → no signal is "flowing", even though the
      // service is technically reachable. Availability must never be a
      // permission boolean.
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((_) async => <HealthDataPoint>[]);
      when(
        () => mockHealth.getHealthConnectSdkStatus(),
      ).thenAnswer((_) async => HealthConnectSdkStatus.sdkAvailable);

      final availability = await source.recoverySignalAvailability();

      if (Platform.isAndroid || Platform.isIOS) {
        expect(availability.hrv, isFalse);
        expect(availability.restingHeartRate, isFalse);
        expect(availability.sleep, isFalse);
        expect(availability.respiratoryRate, isFalse);
        expect(availability.hasAnySignal, isFalse);
      } else {
        // Desktop host: provider unsupported, all signals false.
        expect(availability.hasAnySignal, isFalse);
      }
    },
  );

  test(
    'maps Android SLEEP_SESSION to a time-in-bed (sleepInBed) sample',
    () async {
      // Android Health Connect reports the overall sleep period as SLEEP_SESSION
      // (SLEEP_IN_BED is iOS-only), so it must surface as time-in-bed.
      when(
        () => mockHealth.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          recordingMethodsToFilter: any(named: 'recordingMethodsToFilter'),
        ),
      ).thenAnswer((invocation) async {
        final types = invocation.namedArguments[#types] as List<HealthDataType>;
        if (types.first == HealthDataType.SLEEP_SESSION) {
          return [
            HealthDataPoint(
              uuid: 'sleep-session-1',
              value: NumericHealthValue(numericValue: 480),
              type: HealthDataType.SLEEP_SESSION,
              unit: HealthDataUnit.MINUTE,
              dateFrom: DateTime(2024, 5, 20, 23),
              dateTo: DateTime(2024, 5, 21, 7),
              sourcePlatform: HealthPlatformType.appleHealth,
              sourceDeviceId: 'device',
              sourceId: 'source',
              sourceName: 'Pixel Watch',
              recordingMethod: RecordingMethod.automatic,
            ),
          ];
        }
        return <HealthDataPoint>[];
      });

      final samples = await source.readMetricSamples(
        DateTime(2024, 5, 20),
        DateTime(2024, 5, 21),
      );

      final timeInBed = samples
          .where((s) => s.type == HealthMetricType.sleepInBed)
          .toList();
      expect(timeInBed, hasLength(1));
      expect(timeInBed.first.value, 480);
    },
  );

  test('prefers the platform-native HRV kind first, keeping both readable', () {
    final hrvTypes = HealthPlatformSource.hrvTypesForPlatform;
    expect(hrvTypes, hasLength(2));
    expect(
      hrvTypes,
      containsAll(const [
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      ]),
    );

    final preferred = HealthPlatformSource.platformHrvType;
    if (Platform.isAndroid) {
      expect(preferred, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
      expect(hrvTypes.first, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
    } else if (Platform.isIOS) {
      expect(preferred, HealthDataType.HEART_RATE_VARIABILITY_SDNN);
      expect(hrvTypes.first, HealthDataType.HEART_RATE_VARIABILITY_SDNN);
    } else {
      // Desktop/test host: SDNN-first is the HealthKit-native default.
      expect(hrvTypes.first, HealthDataType.HEART_RATE_VARIABILITY_SDNN);
    }
  });
}
