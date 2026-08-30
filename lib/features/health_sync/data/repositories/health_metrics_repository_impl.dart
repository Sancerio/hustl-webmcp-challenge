import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show compute;
import 'package:health/health.dart';

import '../../../../core/services/preferences_service.dart';
import '../../domain/models/daily_health_summary.dart';
import '../../domain/models/daily_recovery_snapshot.dart';
import '../../domain/models/health_metric_sample.dart';
import '../../domain/models/nutrition_log_entry.dart';
import '../../domain/models/recovery_signal_availability.dart';
import '../../domain/repositories/health_metrics_repository.dart';
import '../../domain/usecases/build_daily_health_summaries.dart';
import '../../domain/usecases/build_daily_recovery_snapshots.dart';
import '../services/health_cache_service.dart';
import '../sources/health_platform_source.dart';

class HealthMetricsRepositoryImpl implements HealthMetricsRepository {
  HealthMetricsRepositoryImpl({
    required HealthPlatformSource platformSource,
    required HealthCacheService cacheService,
    required PreferencesService preferencesService,
    BuildDailyHealthSummariesUseCase? buildDailySummaries,
    BuildDailyRecoverySnapshotsUseCase? buildDailyRecoverySnapshots,
  }) : _platformSource = platformSource,
       _cacheService = cacheService,
       _preferences = preferencesService,
       _deriveSnapshotsInBackground =
           buildDailySummaries == null && buildDailyRecoverySnapshots == null,
       _buildDailySummaries =
           buildDailySummaries ?? BuildDailyHealthSummariesUseCase(),
       _buildDailyRecoverySnapshots =
           buildDailyRecoverySnapshots ?? BuildDailyRecoverySnapshotsUseCase();

  final HealthPlatformSource _platformSource;
  final HealthCacheService _cacheService;
  final PreferencesService _preferences;
  final BuildDailyHealthSummariesUseCase _buildDailySummaries;
  final BuildDailyRecoverySnapshotsUseCase _buildDailyRecoverySnapshots;
  final bool _deriveSnapshotsInBackground;
  HealthSnapshot? _memorySnapshot;

  static const Duration _staleDuration = Duration(hours: 6);
  static const String _healthPermissionSchemaKey =
      'health_permissions_schema_version';
  static const String _healthPermissionSchemaVersion = 'recovery_v1';

  /// A single cancel/dismiss/partial-grant/Android-14 cap is treated as a
  /// transient non-grant, not a permanent denial. We only mark the user as
  /// permanently denied once this many CONSECUTIVE request attempts have
  /// produced no granted type, i.e. a confirmed re-denial after they returned to
  /// the connect flow and were asked again.
  static const int _confirmedReDenialAttempts = 2;

  String get _providerLabel {
    if (Platform.isAndroid) return 'Health Connect';
    if (Platform.isIOS) return 'Apple Health';
    return 'Health';
  }

  List<HealthDataType> get _allTypes => [
    ...HealthPlatformSource.bodyMetricTypes,
    ...HealthPlatformSource.recoveryMetricTypes,
    ...HealthPlatformSource.activityMetricTypes,
    HealthDataType.HEART_RATE,
  ];

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async {
    final serviceAvailable = await _platformSource.isServiceAvailable();
    if (!serviceAvailable) {
      return const HealthPermissionsStatus(
        hasPermissions: false,
        isServiceAvailable: false,
      );
    }

    final supportedTypes = await _platformSource.supportedTypes(_allTypes);
    final rawPermissionResult = supportedTypes.isEmpty
        ? false
        : await _platformSource.hasAnyPermission(supportedTypes);
    final assumedGranted = rawPermissionResult == null && Platform.isIOS;
    final hasPermissions = rawPermissionResult ?? assumedGranted;
    // An external grant (e.g. the user enabled access in system settings) can
    // flip hasPermissions to true without ever going through requestPermissions.
    // Clear any stale denied flag + attempt counter so a later state read after
    // an external revoke can never surface a stale permanent-denial. Only do so
    // on a CONFIRMED grant (rawPermissionResult == true). The iOS assumedGranted
    // (null) path is NOT a confirmed grant, so it must not reset the counter.
    final denied = hasPermissions
        ? false
        : await _preferences.getHealthPermissionsDenied();
    if (rawPermissionResult == true) {
      await _clearDenialState();
    }

    return HealthPermissionsStatus(
      hasPermissions: hasPermissions,
      isServiceAvailable: true,
      deniedPermanently: denied,
      rawPermissionResult: rawPermissionResult,
      assumedGranted: assumedGranted,
    );
  }

  @override
  Future<HealthPermissionsStatus> requestPermissions() async {
    final serviceAvailable = await _platformSource.isServiceAvailable();
    if (!serviceAvailable) {
      return const HealthPermissionsStatus(
        hasPermissions: false,
        isServiceAvailable: false,
      );
    }

    final supportedTypes = await _platformSource.supportedTypes(_allTypes);
    if (supportedTypes.isEmpty) {
      // No supported types to request — nothing to grant, nothing to deny.
      return const HealthPermissionsStatus(
        hasPermissions: false,
        isServiceAvailable: true,
      );
    }

    // Finding #5: pre-check. Skip the auth request ONLY when there is nothing
    // left to grant — i.e. EVERY supported type is already granted. This uses
    // the all-or-nothing `hasPermissions` (true only when all granted) rather
    // than `hasAnyPermission`, so an existing user who granted an older,
    // smaller set is still re-prompted for any newly-added types. Health
    // Connect only surfaces the ungranted subset, so requesting the full set is
    // safe and won't re-show already-granted toggles. iOS returns null here
    // (cannot report READ status), which is NOT treated as already-connected,
    // so the request still runs there.
    final preCheck = await _platformSource.hasPermissions(supportedTypes);
    if (preCheck == true) {
      await _markConnected();
      return HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
        rawPermissionResult: preCheck,
      );
    }

    final granted = await _platformSource.requestPermissions(supportedTypes);
    final rawPermissionResult = await _platformSource.hasAnyPermission(
      supportedTypes,
    );
    final assumedGranted =
        rawPermissionResult == null && Platform.isIOS && granted;

    // Finding #4: connectivity is decided by hasAnyPermission (any granted type
    // counts), NOT the all-or-nothing `granted`. A partial grant / Android-14
    // cap still leaves the user connected.
    final connected = (rawPermissionResult ?? assumedGranted);

    if (connected) {
      await _markConnected();
      return HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
        rawPermissionResult: rawPermissionResult,
        assumedGranted: assumedGranted,
      );
    }

    // Not connected: this attempt produced no granted type. Increment the
    // consecutive-attempt counter. The first-ever non-grant may just be a
    // transient cancel/dismiss, so we only mark permanently-denied once the
    // counter reaches the confirmed-re-denial threshold.
    final attempts = (await _preferences.getHealthPermissionRequestCount()) + 1;
    await _preferences.setHealthPermissionRequestCount(attempts);
    final deniedPermanently = attempts >= _confirmedReDenialAttempts;
    await _preferences.setHealthPermissionsDenied(deniedPermanently);

    return HealthPermissionsStatus(
      hasPermissions: false,
      isServiceAvailable: true,
      deniedPermanently: deniedPermanently,
      rawPermissionResult: rawPermissionResult,
      assumedGranted: assumedGranted,
    );
  }

  /// Clear the persisted denial state: the denied flag AND the consecutive
  /// re-denial attempt counter. Shared by the request path and the external-grant
  /// path so a connected user is never left in a stale permanent-denial.
  Future<void> _clearDenialState() async {
    await _preferences.setHealthPermissionsDenied(false);
    await _preferences.setHealthPermissionRequestCount(0);
  }

  /// Mark the user as connected after a request: clear the denial state and
  /// persist the recovery schema version (so the iOS "review access" prompt does
  /// not re-fire).
  Future<void> _markConnected() async {
    await _clearDenialState();
    await _preferences.setRawString(
      _healthPermissionSchemaKey,
      _healthPermissionSchemaVersion,
    );
  }

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    final memorySnapshot = _memorySnapshot;
    if (!forceRefresh &&
        memorySnapshot != null &&
        _canServeSnapshot(
          memorySnapshot,
          start: normalizedStart,
          end: normalizedEnd,
          now: now,
        )) {
      return memorySnapshot;
    }
    final inclusiveEnd = DateTime(
      normalizedEnd.year,
      normalizedEnd.month,
      normalizedEnd.day,
      23,
      59,
      59,
      999,
      999,
    );
    final cached = await _cacheService.loadSnapshot();

    bool cacheFresh = false;
    if (cached != null) {
      final withinRange =
          !normalizedStart.isBefore(cached.rangeStart) &&
          !normalizedEnd.isAfter(cached.rangeEnd);
      final notStale = cached.lastSyncedAt.isAfter(
        now.subtract(_staleDuration),
      );
      final hasContent =
          cached.metrics.isNotEmpty || cached.nutritionEntries.isNotEmpty;
      cacheFresh = withinRange && notStale && hasContent;
      if (!forceRefresh && cacheFresh) {
        return _remember(await _snapshotFromCache(cached));
      }
    }

    final status = await getPermissionsStatus();
    final needsPermissionRefresh = await _needsPermissionRefresh(status);
    if (!status.isServiceAvailable || !status.hasPermissions) {
      final warnings = _platformSource.drainWarnings();
      if (cached != null) {
        return _remember(await _snapshotFromCache(cached));
      }
      final provider = status.isServiceAvailable
          ? await _safeProviderAvailability()
          : HealthProviderAvailability.needsInstall;
      return _remember(
        HealthSnapshot(
          rangeStart: start,
          rangeEnd: end,
          metrics: const [],
          nutritionEntries: const [],
          dailySummaries: const [],
          recoverySnapshots: const [],
          lastSyncedAt: now,
          warnings: warnings,
          assumedPermissions: status.assumedGranted,
          rawPermissionResult: status.rawPermissionResult,
          signalAvailability: RecoverySignalAvailability(
            providerAvailability: provider,
          ),
        ),
      );
    }

    final metrics = await _platformSource.readMetricSamples(
      normalizedStart,
      inclusiveEnd,
    );
    final warnings = _platformSource.drainWarnings();
    if (needsPermissionRefresh &&
        !warnings.any(
          (warning) => warning.contains(
            'access once to enable newly added recovery signals',
          ),
        )) {
      warnings.add(
        'Review $_providerLabel access once to enable newly added recovery signals like HRV, resting heart rate, and blood oxygen.',
      );
    }

    const dedupedNutrition = <NutritionLogEntry>[];
    // A cache miss can return thousands of HealthKit points after the Train
    // list is already interactive. Keep dedupe and both multi-week projection
    // builders off the UI isolate in production; injected builders retain
    // their exact synchronous test behavior.
    final derived = _deriveSnapshotsInBackground
        ? await compute(
            _deriveFreshSnapshot,
            _FreshHealthDerivationInput(
              metrics: metrics,
              nutritionEntries: dedupedNutrition,
            ),
          )
        : _deriveFreshSnapshotWithInjectedBuilders(metrics, dedupedNutrition);
    var dedupedMetrics = derived.metrics;
    var summaries = derived.summaries;
    var recoverySnapshots = derived.recoverySnapshots;

    // Fallback: If there is no data in the selected window, try to fetch the
    // most recent body measurements so we can at least show a baseline.
    var fallbackUsed = false;
    if (summaries.isEmpty) {
      final latest = await _platformSource.readLatestMetricSamples([
        HealthDataType.WEIGHT,
        HealthDataType.HEIGHT,
        HealthDataType.BODY_MASS_INDEX,
        HealthDataType.BODY_FAT_PERCENTAGE,
      ]);

      if (latest.isNotEmpty) {
        double? latestWeight;
        double? latestHeight;
        double? latestBmi;
        double? latestBodyFat;

        for (final s in latest) {
          switch (s.type) {
            case HealthMetricType.weight:
              latestWeight = s.valueInPreferredUnit;
              break;
            case HealthMetricType.height:
              latestHeight = s.valueInPreferredUnit;
              break;
            case HealthMetricType.bodyMassIndex:
              latestBmi = s.valueInPreferredUnit;
              break;
            case HealthMetricType.bodyFatPercentage:
              latestBodyFat = s.valueInPreferredUnit;
              break;
            default:
              break;
          }
        }

        // Compute BMI from weight/height if direct BMI unavailable.
        double? derivedBmi = latestBmi;
        if (derivedBmi == null &&
            latestWeight != null &&
            latestHeight != null) {
          final meters = latestHeight / 100.0;
          if (meters > 0) derivedBmi = latestWeight / (meters * meters);
        }

        final adjustedFallback = latest
            .map(
              (sample) => sample.copyWith(
                startTime: normalizedEnd,
                endTime: normalizedEnd,
              ),
            )
            .toList();
        summaries = [
          DailyHealthSummary(
            date: normalizedEnd,
            latestWeightKg: latestWeight,
            latestHeightCm: latestHeight,
            bodyMassIndex: derivedBmi,
            bodyFatPercentage: latestBodyFat,
            basalMetabolicRate: null,
            metrics: adjustedFallback,
            nutritionLogs: const [],
            macros: const DailyMacroBreakdown(
              calories: 0,
              proteinGrams: 0,
              carbsGrams: 0,
              fatGrams: 0,
            ),
          ),
        ];
        // Keep fallback samples in the cache so subsequent loads retain the
        // baseline values until newer data arrives.
        dedupedMetrics = _dedupeHealthMetrics([
          ...dedupedMetrics,
          ...adjustedFallback,
        ]);
        recoverySnapshots = _buildDailyRecoverySnapshots(
          metrics: dedupedMetrics,
        );
        fallbackUsed = true;
        // Add a gentle heads-up so the UI can inform the user.
        if (!warnings.any((w) => w.contains('recent health data'))) {
          warnings.add(
            'No recent health data found in the last 14 days. Showing your most recent measurements from $_providerLabel.',
          );
        }
      }
    }

    await _cacheService.saveSnapshot(
      start: normalizedStart,
      end: normalizedEnd,
      metrics: dedupedMetrics,
      nutrition: dedupedNutrition,
      fetchedAt: now,
      warnings: warnings,
    );

    final signalAvailability = await _signalAvailabilityFrom(dedupedMetrics);

    return _remember(
      HealthSnapshot(
        rangeStart: normalizedStart,
        rangeEnd: normalizedEnd,
        metrics: dedupedMetrics,
        nutritionEntries: dedupedNutrition,
        dailySummaries: summaries,
        recoverySnapshots: recoverySnapshots,
        lastSyncedAt: now,
        warnings: warnings,
        fallbackUsed: fallbackUsed,
        assumedPermissions: status.assumedGranted,
        rawPermissionResult: status.rawPermissionResult,
        signalAvailability: signalAvailability,
      ),
    );
  }

  @override
  Future<void> clearCache() async {
    _memorySnapshot = null;
    await _cacheService.clear();
  }

  bool _canServeSnapshot(
    HealthSnapshot snapshot, {
    required DateTime start,
    required DateTime end,
    required DateTime now,
  }) {
    final withinRange =
        !start.isBefore(snapshot.rangeStart) && !end.isAfter(snapshot.rangeEnd);
    final notStale = snapshot.lastSyncedAt.isAfter(
      now.subtract(_staleDuration),
    );
    final hasContent =
        snapshot.metrics.isNotEmpty || snapshot.nutritionEntries.isNotEmpty;
    return withinRange && notStale && hasContent;
  }

  HealthSnapshot _remember(HealthSnapshot snapshot) {
    final current = _memorySnapshot;
    final replacesCurrent =
        current == null ||
        (!snapshot.loadedFromCache && current.loadedFromCache) ||
        (snapshot.loadedFromCache == current.loadedFromCache &&
            !snapshot.lastSyncedAt.isBefore(current.lastSyncedAt));
    if (replacesCurrent) {
      _memorySnapshot = snapshot;
    }
    return snapshot;
  }

  @override
  Future<void> resetPermissionDenialFlag() async {
    // Clear BOTH the denied flag AND the consecutive re-denial counter. Clearing
    // only the flag would leave the counter at/above the threshold, so the very
    // next "Retry" non-grant would immediately re-trip permanent denial.
    await _clearDenialState();
  }

  @override
  Future<HealthProviderAvailability> getProviderAvailability() {
    return _platformSource.providerAvailability();
  }

  @override
  Future<void> installHealthConnect() {
    return _platformSource.installHealthConnect();
  }

  Future<HealthProviderAvailability> _safeProviderAvailability() async {
    try {
      return await _platformSource.providerAvailability();
    } catch (_) {
      return HealthProviderAvailability.available;
    }
  }

  Future<bool> _needsPermissionRefresh(HealthPermissionsStatus status) async {
    if (!Platform.isIOS || !status.assumedGranted) {
      return false;
    }

    final storedVersion = await _preferences.getRawString(
      _healthPermissionSchemaKey,
    );
    return storedVersion != _healthPermissionSchemaVersion;
  }

  Future<HealthSnapshot> _snapshotFromCache(CachedHealthSnapshot cached) async {
    // Production uses the default pure builders, so derive the multi-week
    // summaries off the UI isolate. Tests and specialized callers that inject
    // builders keep their exact injected behavior on the current isolate.
    final derived = _deriveSnapshotsInBackground
        ? await compute(_deriveCachedSnapshot, cached)
        : _DerivedCachedSnapshot(
            summaries: _buildDailySummaries(
              metrics: cached.metrics,
              nutritionEntries: cached.nutritionEntries,
            ),
            recoverySnapshots: _buildDailyRecoverySnapshots(
              metrics: cached.metrics,
            ),
          );
    // Report per-signal availability identically to the fresh path so users
    // with cached HRV/sleep/RHR still see the targeted missing-signal /
    // provider prompts — instead of falling back to `empty` (which hides them
    // until a forced refresh). Derived from the cached metrics, not a
    // permission boolean, so it matches the fresh-load semantics exactly.
    final signalAvailability = await _signalAvailabilityFrom(cached.metrics);
    return HealthSnapshot(
      rangeStart: cached.rangeStart,
      rangeEnd: cached.rangeEnd,
      metrics: cached.metrics,
      nutritionEntries: cached.nutritionEntries,
      dailySummaries: derived.summaries,
      recoverySnapshots: derived.recoverySnapshots,
      lastSyncedAt: cached.lastSyncedAt,
      warnings: cached.warnings,
      loadedFromCache: true,
      signalAvailability: signalAvailability,
    );
  }

  /// Derive per-signal availability from the metrics we actually loaded plus a
  /// provider reachability probe. Data-driven, never a permission boolean: a
  /// signal counts as available only if a real sample came back. Provider probe
  /// failures degrade gracefully to "available" so the dashboard never hard
  /// fails — the connect page owns the Android install routing separately.
  Future<RecoverySignalAvailability> _signalAvailabilityFrom(
    List<HealthMetricSample> metrics,
  ) async {
    HealthProviderAvailability provider;
    try {
      provider = await _platformSource.providerAvailability();
    } catch (_) {
      provider = HealthProviderAvailability.available;
    }
    bool has(Set<HealthMetricType> types) =>
        metrics.any((m) => types.contains(m.type) && m.value.isFinite);
    return RecoverySignalAvailability(
      providerAvailability: provider,
      hrv: has({
        HealthMetricType.heartRateVariabilitySdnn,
        HealthMetricType.heartRateVariabilityRmssd,
      }),
      restingHeartRate: has({HealthMetricType.restingHeartRate}),
      // Mirror the recovery-snapshot sleep total exactly: it prefers staged
      // sleep (REM + deep + light) and only falls back to a plain "asleep"
      // sample. Modern Apple Watch nights write stages and no aggregate
      // `sleepAsleep`, so keying availability off asleep/in-bed alone marks
      // sleep "missing" while the card is happily showing a staged total — the
      // exact contradiction this list prevents. `sleepInBed` is intentionally
      // excluded: in-bed time never feeds `sleepMinutes`, so counting it here
      // would flip the inverse case (banner hidden while the card shows no
      // sleep).
      sleep: has({
        HealthMetricType.sleepAsleep,
        HealthMetricType.sleepRem,
        HealthMetricType.sleepDeep,
        HealthMetricType.sleepLight,
      }),
      respiratoryRate: has({HealthMetricType.respiratoryRate}),
    );
  }

  _DerivedFreshSnapshot _deriveFreshSnapshotWithInjectedBuilders(
    List<HealthMetricSample> metrics,
    List<NutritionLogEntry> nutritionEntries,
  ) {
    final deduped = _dedupeHealthMetrics(metrics);
    return _DerivedFreshSnapshot(
      metrics: deduped,
      summaries: _buildDailySummaries(
        metrics: deduped,
        nutritionEntries: nutritionEntries,
      ),
      recoverySnapshots: _buildDailyRecoverySnapshots(metrics: deduped),
    );
  }
}

class _FreshHealthDerivationInput {
  const _FreshHealthDerivationInput({
    required this.metrics,
    required this.nutritionEntries,
  });

  final List<HealthMetricSample> metrics;
  final List<NutritionLogEntry> nutritionEntries;
}

class _DerivedFreshSnapshot {
  const _DerivedFreshSnapshot({
    required this.metrics,
    required this.summaries,
    required this.recoverySnapshots,
  });

  final List<HealthMetricSample> metrics;
  final List<DailyHealthSummary> summaries;
  final List<DailyRecoverySnapshot> recoverySnapshots;
}

class _DerivedCachedSnapshot {
  const _DerivedCachedSnapshot({
    required this.summaries,
    required this.recoverySnapshots,
  });

  final List<DailyHealthSummary> summaries;
  final List<DailyRecoverySnapshot> recoverySnapshots;
}

_DerivedFreshSnapshot _deriveFreshSnapshot(_FreshHealthDerivationInput input) {
  final metrics = _dedupeHealthMetrics(input.metrics);
  return _DerivedFreshSnapshot(
    metrics: metrics,
    summaries: BuildDailyHealthSummariesUseCase()(
      metrics: metrics,
      nutritionEntries: input.nutritionEntries,
    ),
    recoverySnapshots: BuildDailyRecoverySnapshotsUseCase()(metrics: metrics),
  );
}

List<HealthMetricSample> _dedupeHealthMetrics(
  List<HealthMetricSample> metrics,
) {
  final byInterval = <String, HealthMetricSample>{};
  for (final sample in metrics) {
    final externalId = sample.externalId?.trim();
    final key = externalId != null && externalId.isNotEmpty
        ? '${sample.type.name}|id|$externalId'
        : '${sample.type.name}|${sample.startTime.toUtc().toIso8601String()}|'
              '${sample.endTime.toUtc().toIso8601String()}|'
              '${sample.valueInPreferredUnit.toStringAsFixed(6)}|'
              '${sample.type.preferredUnit}';
    final existing = byInterval[key];
    if (existing == null ||
        _healthSourcePrecedence(sample) > _healthSourcePrecedence(existing)) {
      byInterval[key] = sample;
    }
  }
  final deduped = byInterval.values.toList();
  deduped.sort((a, b) => a.endTime.compareTo(b.endTime));
  return deduped;
}

/// Prefer automatic device measurements over manual/app-derived duplicates,
/// then a named wearable over a phone/source-only record. Stable HealthKit
/// provenance is the final tie-breaker. Raw observations are still uploaded;
/// this precedence is only for the on-device derived daily read model.
int _healthSourcePrecedence(HealthMetricSample sample) {
  var score = sample.isUserEntered ? 0 : 40;
  if (sample.sourceDeviceId?.isNotEmpty == true) score += 20;
  final wearable = '${sample.deviceModel ?? ''} ${sample.source}'.toLowerCase();
  if (wearable.contains('watch') || wearable.contains('wear')) score += 10;
  if (sample.sourceId?.isNotEmpty == true) score += 5;
  if (sample.externalId?.isNotEmpty == true) score += 2;
  return score;
}

_DerivedCachedSnapshot _deriveCachedSnapshot(CachedHealthSnapshot cached) {
  return _DerivedCachedSnapshot(
    summaries: BuildDailyHealthSummariesUseCase()(
      metrics: cached.metrics,
      nutritionEntries: cached.nutritionEntries,
    ),
    recoverySnapshots: BuildDailyRecoverySnapshotsUseCase()(
      metrics: cached.metrics,
    ),
  );
}
