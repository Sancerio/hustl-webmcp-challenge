import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/data/repositories/health_metrics_repository_impl.dart';
import 'package:hustl_app/features/health_sync/data/services/health_cache_service.dart';
import 'package:hustl_app/features/health_sync/data/sources/health_platform_source.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/models/nutrition_log_entry.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/build_daily_health_summaries.dart';

class _MockHealthPlatformSource extends Mock implements HealthPlatformSource {}

class _MockHealthCacheService extends Mock implements HealthCacheService {}

class _MockPreferencesService extends Mock implements PreferencesService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(<HealthDataType>[]);
    registerFallbackValue(<HealthMetricSample>[]);
    registerFallbackValue(<NutritionLogEntry>[]);
  });

  group('HealthMetricsRepositoryImpl', () {
    late _MockHealthPlatformSource platformSource;
    late _MockHealthCacheService cacheService;
    late _MockPreferencesService preferencesService;
    late HealthMetricsRepositoryImpl repository;

    setUp(() {
      platformSource = _MockHealthPlatformSource();
      cacheService = _MockHealthCacheService();
      preferencesService = _MockPreferencesService();

      repository = HealthMetricsRepositoryImpl(
        platformSource: platformSource,
        cacheService: cacheService,
        preferencesService: preferencesService,
        buildDailySummaries: BuildDailyHealthSummariesUseCase(),
      );

      when(() => cacheService.loadSnapshot()).thenAnswer((_) async => null);
      when(() => cacheService.clear()).thenAnswer((_) async {});
      when(
        () => cacheService.saveSnapshot(
          start: any(named: 'start'),
          end: any(named: 'end'),
          metrics: any(named: 'metrics'),
          nutrition: any(named: 'nutrition'),
          fetchedAt: any(named: 'fetchedAt'),
          warnings: any(named: 'warnings'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => platformSource.isServiceAvailable(),
      ).thenAnswer((_) async => true);
      when(() => platformSource.supportedTypes(any())).thenAnswer((
        invocation,
      ) async {
        return List<HealthDataType>.from(
          invocation.positionalArguments.first as List<HealthDataType>,
        );
      });
      // Pre-check (Finding #5) reads the all-or-nothing `hasPermissions`.
      // Default it to false so requestPermissions tests run the real auth
      // request; the short-circuit test opts in explicitly.
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => false);
      when(
        () => platformSource.hasAnyPermission(any()),
      ).thenAnswer((_) async => true);
      when(
        () => preferencesService.getHealthPermissionsDenied(),
      ).thenAnswer((_) async => false);
      when(
        () => preferencesService.setHealthPermissionsDenied(any()),
      ).thenAnswer((_) async {});
      when(
        () => preferencesService.getHealthPermissionRequestCount(),
      ).thenAnswer((_) async => 0);
      when(
        () => preferencesService.setHealthPermissionRequestCount(any()),
      ).thenAnswer((_) async {});
      when(
        () => preferencesService.getRawString(any()),
      ).thenAnswer((_) async => null);
      when(
        () => preferencesService.setRawString(any(), any()),
      ).thenAnswer((_) async {});
      when(() => platformSource.readMetricSamples(any(), any())).thenAnswer(
        (_) async => [
          HealthMetricSample(
            type: HealthMetricType.weight,
            value: 82.3,
            unit: 'kg',
            startTime: DateTime(2024, 1, 1, 8),
            endTime: DateTime(2024, 1, 1, 9),
            source: 'test-device',
          ),
          HealthMetricSample(
            type: HealthMetricType.sleepAsleep,
            value: 450,
            unit: 'min',
            startTime: DateTime(2024, 1, 1, 0),
            endTime: DateTime(2024, 1, 1, 7),
            source: 'test-device',
          ),
          HealthMetricSample(
            type: HealthMetricType.restingHeartRate,
            value: 56,
            unit: 'bpm',
            startTime: DateTime(2024, 1, 1, 7),
            endTime: DateTime(2024, 1, 1, 7, 5),
            source: 'test-device',
          ),
        ],
      );
      when(() => platformSource.drainWarnings()).thenReturn(const []);
      when(
        () => platformSource.providerAvailability(),
      ).thenAnswer((_) async => HealthProviderAvailability.available);
    });

    test('expands range end to include entire final day', () async {
      final start = DateTime(2024, 1, 4, 12, 30);
      final end = DateTime(2024, 1, 5, 6, 45);

      await repository.loadSnapshot(start: start, end: end);

      final metricInvocation = verify(
        () => platformSource.readMetricSamples(captureAny(), captureAny()),
      );
      metricInvocation.called(1);

      final capturedMetricStart = metricInvocation.captured[0] as DateTime;
      final capturedMetricEnd = metricInvocation.captured[1] as DateTime;

      expect(capturedMetricStart, DateTime(2024, 1, 4));

      final expectedEnd = DateTime(2024, 1, 5, 23, 59, 59, 999, 999);
      expect(capturedMetricEnd, expectedEnd);
    });

    test(
      'reuses the in-memory snapshot when Train readiness opens Health',
      () async {
        final end = DateTime.now();
        final start = end.subtract(const Duration(days: 56));

        final first = await repository.loadSnapshot(start: start, end: end);
        final second = await repository.loadSnapshot(
          start: start.add(const Duration(days: 1)),
          end: end,
        );

        expect(second, same(first));
        verify(() => cacheService.loadSnapshot()).called(1);
        verify(() => platformSource.readMetricSamples(any(), any())).called(1);
      },
    );

    test(
      'force refresh and clearCache bypass the in-memory snapshot',
      () async {
        final end = DateTime.now();
        final start = end.subtract(const Duration(days: 56));

        await repository.loadSnapshot(start: start, end: end);
        await repository.loadSnapshot(
          start: start,
          end: end,
          forceRefresh: true,
        );

        verify(() => cacheService.loadSnapshot()).called(2);
        verify(() => platformSource.readMetricSamples(any(), any())).called(2);

        await repository.clearCache();
        await repository.loadSnapshot(start: start, end: end);

        verify(() => cacheService.clear()).called(1);
        verify(() => cacheService.loadSnapshot()).called(1);
        verify(() => platformSource.readMetricSamples(any(), any())).called(1);
      },
    );

    test('returns warnings from platform source', () async {
      when(
        () => platformSource.drainWarnings(),
      ).thenReturn(const ['Weight access denied']);

      final snapshot = await repository.loadSnapshot(
        start: DateTime.now(),
        end: DateTime.now(),
      );

      expect(snapshot.warnings, equals(['Weight access denied']));
    });

    test('builds recovery snapshots from expanded metric payloads', () async {
      final snapshot = await repository.loadSnapshot(
        start: DateTime(2024, 1, 1),
        end: DateTime(2024, 1, 1),
      );

      expect(snapshot.recoverySnapshots, isNotEmpty);
      expect(snapshot.recoverySnapshots.first.sleepDurationMinutes, 450);
      expect(snapshot.recoverySnapshots.first.restingHeartRateBpm, 56);
    });

    test('keeps different values that share the same interval', () async {
      final instant = DateTime(2024, 1, 1, 7);
      when(() => platformSource.readMetricSamples(any(), any())).thenAnswer(
        (_) async => [
          HealthMetricSample(
            type: HealthMetricType.restingHeartRate,
            value: 52,
            unit: 'bpm',
            startTime: instant,
            endTime: instant,
            source: 'Watch A',
          ),
          HealthMetricSample(
            type: HealthMetricType.restingHeartRate,
            value: 61,
            unit: 'bpm',
            startTime: instant,
            endTime: instant,
            source: 'Watch B',
          ),
        ],
      );

      final snapshot = await repository.loadSnapshot(
        start: DateTime(2024, 1, 1),
        end: DateTime(2024, 1, 1),
      );

      expect(snapshot.metrics, hasLength(2));
      expect(
        snapshot.metrics.map((sample) => sample.value),
        containsAll([52, 61]),
      );
    });

    test('filters permission checks to supported data types', () async {
      when(() => platformSource.supportedTypes(any())).thenAnswer((_) async {
        return const [HealthDataType.WEIGHT];
      });

      await repository.getPermissionsStatus();

      verify(
        () => platformSource.hasAnyPermission([HealthDataType.WEIGHT]),
      ).called(1);
    });

    test(
      'stays connected on a partial grant (any granted type counts)',
      () async {
        // Health Connect granted some-but-not-all types: hasAnyPermission resolves
        // true, so the dashboard must NOT dead-end to the denied/empty state.
        when(
          () => platformSource.hasAnyPermission(any()),
        ).thenAnswer((_) async => true);

        final status = await repository.getPermissionsStatus();

        expect(status.hasPermissions, isTrue);
        expect(status.isServiceAvailable, isTrue);
      },
    );

    test(
      'getPermissionsStatus clears stale denial state when connected externally',
      () async {
        // The user previously hit the confirmed-re-denial threshold (denied
        // flag true + counter >= 2) but has since granted access outside the
        // app (e.g. via system settings). hasAnyPermission now resolves true,
        // so a state read must wipe the stale denial state — otherwise a later
        // read after an external revoke would surface a stale permanent-denial.
        when(
          () => preferencesService.getHealthPermissionsDenied(),
        ).thenAnswer((_) async => true);
        when(
          () => preferencesService.getHealthPermissionRequestCount(),
        ).thenAnswer((_) async => 2);
        when(
          () => platformSource.hasAnyPermission(any()),
        ).thenAnswer((_) async => true);

        final status = await repository.getPermissionsStatus();

        expect(status.hasPermissions, isTrue);
        expect(status.deniedPermanently, isFalse);
        verify(
          () => preferencesService.setHealthPermissionsDenied(false),
        ).called(1);
        verify(
          () => preferencesService.setHealthPermissionRequestCount(0),
        ).called(1);
      },
    );

    test('requests heart rate alongside overview health permissions', () async {
      // Pre-check (all-or-nothing hasPermissions) resolves false so the actual
      // auth request runs and we can assert the requested type set (Finding #5
      // pre-check would otherwise short-circuit). The post-request probe then
      // resolves true.
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => false);
      when(
        () => platformSource.hasAnyPermission(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.requestPermissions(any()),
      ).thenAnswer((_) async => true);

      await repository.requestPermissions();

      final captured =
          verify(
                () => platformSource.requestPermissions(captureAny()),
              ).captured.single
              as List<HealthDataType>;

      expect(captured, contains(HealthDataType.HEART_RATE));
    });

    test(
      'fresh cache path reports per-signal availability identically to fresh '
      'load (does not fall back to empty)',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        when(() => cacheService.loadSnapshot()).thenAnswer(
          (_) async => CachedHealthSnapshot(
            rangeStart: today.subtract(const Duration(days: 13)),
            rangeEnd: today,
            // Recent enough to be considered fresh (< 6h stale window).
            lastSyncedAt: now.subtract(const Duration(minutes: 5)),
            metrics: [
              HealthMetricSample(
                type: HealthMetricType.heartRateVariabilitySdnn,
                value: 65,
                unit: 'ms',
                startTime: today,
                endTime: today,
                source: 'watch',
              ),
              HealthMetricSample(
                type: HealthMetricType.sleepAsleep,
                value: 430,
                unit: 'min',
                startTime: today,
                endTime: today,
                source: 'watch',
              ),
              HealthMetricSample(
                type: HealthMetricType.restingHeartRate,
                value: 54,
                unit: 'bpm',
                startTime: today,
                endTime: today,
                source: 'watch',
              ),
            ],
            nutritionEntries: const [],
          ),
        );

        final snapshot = await repository.loadSnapshot(
          start: today.subtract(const Duration(days: 13)),
          end: today,
        );

        // Served from cache — but availability is computed, not `empty`.
        expect(snapshot.loadedFromCache, isTrue);
        expect(
          snapshot.signalAvailability,
          isNot(RecoverySignalAvailability.empty),
        );
        expect(snapshot.signalAvailability.hrv, isTrue);
        expect(snapshot.signalAvailability.sleep, isTrue);
        expect(snapshot.signalAvailability.restingHeartRate, isTrue);
        expect(snapshot.signalAvailability.hasAnySignal, isTrue);
        // No forced refresh / device read should have happened.
        verifyNever(() => platformSource.readMetricSamples(any(), any()));
      },
    );

    test(
      'production cache derivation returns summaries from compute',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        when(() => cacheService.loadSnapshot()).thenAnswer(
          (_) async => CachedHealthSnapshot(
            rangeStart: today.subtract(const Duration(days: 55)),
            rangeEnd: today,
            lastSyncedAt: now.subtract(const Duration(minutes: 5)),
            metrics: [
              HealthMetricSample(
                type: HealthMetricType.sleepAsleep,
                value: 430,
                unit: 'min',
                startTime: today.subtract(const Duration(hours: 8)),
                endTime: today.subtract(const Duration(hours: 1)),
                source: 'watch',
              ),
              HealthMetricSample(
                type: HealthMetricType.restingHeartRate,
                value: 54,
                unit: 'bpm',
                startTime: today.subtract(const Duration(hours: 1)),
                endTime: today,
                source: 'watch',
              ),
            ],
            nutritionEntries: const [],
          ),
        );
        final productionRepository = HealthMetricsRepositoryImpl(
          platformSource: platformSource,
          cacheService: cacheService,
          preferencesService: preferencesService,
        );

        final snapshot = await productionRepository.loadSnapshot(
          start: today.subtract(const Duration(days: 55)),
          end: today,
        );

        expect(snapshot.loadedFromCache, isTrue);
        expect(snapshot.dailySummaries, isNotEmpty);
        expect(snapshot.recoverySnapshots, isNotEmpty);
        verifyNever(() => platformSource.readMetricSamples(any(), any()));
      },
    );

    test(
      'production cache miss derives and deduplicates a fresh snapshot',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final sleep = HealthMetricSample(
          type: HealthMetricType.sleepAsleep,
          value: 430,
          unit: 'min',
          startTime: today.subtract(const Duration(hours: 8)),
          endTime: today.subtract(const Duration(hours: 1)),
          source: 'watch',
          externalId: 'sleep-today',
        );
        when(() => platformSource.readMetricSamples(any(), any())).thenAnswer(
          (_) async => [
            sleep,
            sleep,
            HealthMetricSample(
              type: HealthMetricType.restingHeartRate,
              value: 54,
              unit: 'bpm',
              startTime: today.subtract(const Duration(hours: 1)),
              endTime: today,
              source: 'watch',
              externalId: 'rhr-today',
            ),
          ],
        );
        final productionRepository = HealthMetricsRepositoryImpl(
          platformSource: platformSource,
          cacheService: cacheService,
          preferencesService: preferencesService,
        );

        final snapshot = await productionRepository.loadSnapshot(
          start: today.subtract(const Duration(days: 55)),
          end: today,
        );

        expect(snapshot.loadedFromCache, isFalse);
        expect(snapshot.metrics, hasLength(2));
        expect(snapshot.dailySummaries, isNotEmpty);
        expect(snapshot.recoverySnapshots, isNotEmpty);
        verify(
          () => cacheService.saveSnapshot(
            start: any(named: 'start'),
            end: any(named: 'end'),
            metrics: any(named: 'metrics'),
            nutrition: any(named: 'nutrition'),
            fetchedAt: any(named: 'fetchedAt'),
            warnings: any(named: 'warnings'),
          ),
        ).called(1);
      },
    );

    test(
      'production empty-window cache miss uses the latest-metric fallback',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        when(
          () => platformSource.readMetricSamples(any(), any()),
        ).thenAnswer((_) async => const []);
        when(() => platformSource.readLatestMetricSamples(any())).thenAnswer(
          (_) async => [
            HealthMetricSample(
              type: HealthMetricType.weight,
              value: 71.35,
              unit: 'kg',
              startTime: today.subtract(const Duration(days: 90)),
              endTime: today.subtract(const Duration(days: 90)),
              source: 'scale',
              externalId: 'older-weight',
            ),
          ],
        );
        when(() => platformSource.drainWarnings()).thenReturn([]);
        final productionRepository = HealthMetricsRepositoryImpl(
          platformSource: platformSource,
          cacheService: cacheService,
          preferencesService: preferencesService,
        );

        final snapshot = await productionRepository.loadSnapshot(
          start: today.subtract(const Duration(days: 55)),
          end: today,
        );

        expect(snapshot.fallbackUsed, isTrue);
        expect(snapshot.metrics.single.value, 71.35);
        expect(snapshot.dailySummaries.single.latestWeightKg, 71.35);
        verify(() => platformSource.readLatestMetricSamples(any())).called(1);
      },
    );

    test(
      'stale cache completion cannot replace a concurrent forced refresh',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final start = today.subtract(const Duration(days: 55));
        final staleCache = CachedHealthSnapshot(
          rangeStart: start,
          rangeEnd: today,
          lastSyncedAt: now.subtract(const Duration(minutes: 5)),
          metrics: [
            HealthMetricSample(
              type: HealthMetricType.weight,
              value: 70,
              unit: 'kg',
              startTime: today,
              endTime: today,
              source: 'stale-cache',
            ),
          ],
          nutritionEntries: const [],
        );
        final staleCacheRead = Completer<CachedHealthSnapshot?>();
        var cacheReads = 0;
        when(() => cacheService.loadSnapshot()).thenAnswer((_) {
          cacheReads += 1;
          return cacheReads == 1
              ? staleCacheRead.future
              : Future<CachedHealthSnapshot?>.value(null);
        });
        when(() => platformSource.readMetricSamples(any(), any())).thenAnswer(
          (_) async => [
            HealthMetricSample(
              type: HealthMetricType.weight,
              value: 71,
              unit: 'kg',
              startTime: today,
              endTime: today,
              source: 'fresh-healthkit',
            ),
          ],
        );
        final productionRepository = HealthMetricsRepositoryImpl(
          platformSource: platformSource,
          cacheService: cacheService,
          preferencesService: preferencesService,
        );

        final staleLoad = productionRepository.loadSnapshot(
          start: start,
          end: today,
        );
        await Future<void>.delayed(Duration.zero);
        final refreshed = await productionRepository.loadSnapshot(
          start: start,
          end: today,
          forceRefresh: true,
        );
        staleCacheRead.complete(staleCache);
        final staleResult = await staleLoad;
        final remembered = await productionRepository.loadSnapshot(
          start: start,
          end: today,
        );

        expect(refreshed.loadedFromCache, isFalse);
        expect(staleResult.loadedFromCache, isTrue);
        expect(remembered, same(refreshed));
        expect(remembered.metrics.single.value, 71);
        verify(() => cacheService.loadSnapshot()).called(2);
      },
    );

    test(
      'staged-only sleep (REM/deep/light, no SLEEP_ASLEEP) still reports sleep '
      'available so the missing-sleep banner stays hidden',
      () async {
        // Modern Apple Watch nights write per-stage samples and no aggregate
        // SLEEP_ASLEEP. The recovery card sums the stages and shows a real
        // sleep total, so availability must agree — otherwise the Biology
        // screen contradicts itself (card shows sleep, banner says it's
        // missing).
        when(() => platformSource.readMetricSamples(any(), any())).thenAnswer(
          (_) async => [
            HealthMetricSample(
              type: HealthMetricType.sleepRem,
              value: 90,
              unit: 'min',
              startTime: DateTime(2024, 1, 1, 2),
              endTime: DateTime(2024, 1, 1, 3),
              source: 'watch',
            ),
            HealthMetricSample(
              type: HealthMetricType.sleepDeep,
              value: 80,
              unit: 'min',
              startTime: DateTime(2024, 1, 1, 3),
              endTime: DateTime(2024, 1, 1, 4),
              source: 'watch',
            ),
            HealthMetricSample(
              type: HealthMetricType.sleepLight,
              value: 264,
              unit: 'min',
              startTime: DateTime(2024, 1, 1, 4),
              endTime: DateTime(2024, 1, 1, 7),
              source: 'watch',
            ),
          ],
        );

        final snapshot = await repository.loadSnapshot(
          start: DateTime(2024, 1, 1),
          end: DateTime(2024, 1, 1),
        );

        expect(snapshot.signalAvailability.sleep, isTrue);
        expect(
          snapshot.signalAvailability.missingSignals,
          isNot(contains(RecoverySignal.sleep)),
        );
      },
    );

    test('stores permission schema version after a successful grant', () async {
      when(
        () => platformSource.requestPermissions(any()),
      ).thenAnswer((_) async => true);

      await repository.requestPermissions();

      verify(
        () => preferencesService.setRawString(
          'health_permissions_schema_version',
          'recovery_v1',
        ),
      ).called(1);
    });

    test(
      'first non-grant does NOT mark permanently denied (transient cancel)',
      () async {
        // requestAuthorization returned false AND nothing is granted: a single
        // cancel/dismiss. With no prior attempts this must NOT route the user to
        // the permanent-denial / device-settings surface.
        when(
          () => platformSource.requestPermissions(any()),
        ).thenAnswer((_) async => false);
        when(
          () => platformSource.hasAnyPermission(any()),
        ).thenAnswer((_) async => false);
        when(
          () => preferencesService.getHealthPermissionRequestCount(),
        ).thenAnswer((_) async => 0);

        final status = await repository.requestPermissions();

        expect(status.hasPermissions, isFalse);
        expect(status.deniedPermanently, isFalse);
        // The attempt counter is incremented to 1...
        verify(
          () => preferencesService.setHealthPermissionRequestCount(1),
        ).called(1);
        // ...and the denied flag is explicitly cleared (false), not set.
        verify(
          () => preferencesService.setHealthPermissionsDenied(false),
        ).called(1);
        verifyNever(() => preferencesService.setHealthPermissionsDenied(true));
      },
    );

    test('second consecutive non-grant DOES mark permanently denied', () async {
      // A prior non-grant already recorded one attempt; this second
      // consecutive non-grant is a confirmed re-denial.
      when(
        () => platformSource.requestPermissions(any()),
      ).thenAnswer((_) async => false);
      when(
        () => platformSource.hasAnyPermission(any()),
      ).thenAnswer((_) async => false);
      when(
        () => preferencesService.getHealthPermissionRequestCount(),
      ).thenAnswer((_) async => 1);

      final status = await repository.requestPermissions();

      expect(status.hasPermissions, isFalse);
      expect(status.deniedPermanently, isTrue);
      verify(
        () => preferencesService.setHealthPermissionRequestCount(2),
      ).called(1);
      verify(
        () => preferencesService.setHealthPermissionsDenied(true),
      ).called(1);
    });

    test(
      'a grant clears the denied flag and resets the attempt counter',
      () async {
        // hasAnyPermission resolves true after the request — the user granted at
        // least one useful type.
        when(
          () => platformSource.requestPermissions(any()),
        ).thenAnswer((_) async => true);
        when(
          () => platformSource.hasAnyPermission(any()),
        ).thenAnswer((_) async => true);

        final status = await repository.requestPermissions();

        expect(status.hasPermissions, isTrue);
        expect(status.deniedPermanently, isFalse);
        verify(
          () => preferencesService.setHealthPermissionsDenied(false),
        ).called(1);
        verify(
          () => preferencesService.setHealthPermissionRequestCount(0),
        ).called(1);
        verifyNever(() => preferencesService.setHealthPermissionsDenied(true));
      },
    );

    test(
      'pre-check short-circuits the auth request when already granted',
      () async {
        // Already-granted (Finding #5): the all-or-nothing `hasPermissions`
        // resolves true on the pre-check (EVERY supported type is granted), so
        // we must NOT call requestPermissions (no dialog / no Android-14 attempt
        // consumed) and stay connected.
        when(
          () => platformSource.hasPermissions(any()),
        ).thenAnswer((_) async => true);

        final status = await repository.requestPermissions();

        expect(status.hasPermissions, isTrue);
        expect(status.deniedPermanently, isFalse);
        verifyNever(() => platformSource.requestPermissions(any()));
        verify(
          () => preferencesService.setHealthPermissionRequestCount(0),
        ).called(1);
      },
    );

    test('partial grant still requests permissions (newly-added perms are '
        'requested)', () async {
      // Existing user granted an older, smaller set: the all-or-nothing
      // `hasPermissions` is false (not EVERY supported type granted) even
      // though `hasAnyPermission` is true. The pre-check must NOT
      // short-circuit — requestPermissions must run so Health Connect can
      // prompt for the ungranted, newly-added types.
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => false);
      when(
        () => platformSource.hasAnyPermission(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.requestPermissions(any()),
      ).thenAnswer((_) async => true);

      final status = await repository.requestPermissions();

      expect(status.hasPermissions, isTrue);
      verify(() => platformSource.requestPermissions(any())).called(1);
    });

    test('null pre-check (iOS) still requests permissions', () async {
      // iOS HealthKit cannot report READ status: hasPermissions returns null.
      // The pre-check must fall through to the real request (not short-circuit
      // on null), matching the unchanged iOS behaviour.
      when(
        () => platformSource.hasPermissions(any()),
      ).thenAnswer((_) async => null);
      when(
        () => platformSource.hasAnyPermission(any()),
      ).thenAnswer((_) async => true);
      when(
        () => platformSource.requestPermissions(any()),
      ).thenAnswer((_) async => true);

      final status = await repository.requestPermissions();

      expect(status.hasPermissions, isTrue);
      verify(() => platformSource.requestPermissions(any())).called(1);
    });
  });
}
