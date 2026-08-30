import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../../domain/models/health_metric_sample.dart';
import '../../domain/models/heart_rate_sample.dart';
import '../../domain/models/recovery_signal_availability.dart';

class HealthPlatformSource {
  HealthPlatformSource({Health? health})
    : _health = health ?? Health(),
      _useBackgroundMetricReads = health == null;

  HealthPlatformSource._background()
    : _health = Health(),
      _useBackgroundMetricReads = false;

  final Health _health;
  final bool _useBackgroundMetricReads;
  bool _configured = false;
  final List<String> _pendingWarnings = [];

  String get _providerLabel {
    if (Platform.isAndroid) return 'Health Connect';
    if (Platform.isIOS) return 'Apple Health';
    return 'Health';
  }

  static const List<HealthDataType> bodyMetricTypes = [
    HealthDataType.WEIGHT,
    HealthDataType.HEIGHT,
    HealthDataType.BODY_MASS_INDEX,
    HealthDataType.BODY_FAT_PERCENTAGE,
  ];

  static const List<HealthDataType> recoveryMetricTypes = [
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.BODY_TEMPERATURE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
    // Android Health Connect exposes the overall sleep period (= time in bed) as
    // SLEEP_SESSION, not SLEEP_IN_BED (which is iOS/HealthKit only). Reading both
    // is safe: each platform filters out the type it does not support via
    // isDataTypeAvailable. Without this, time-in-bed and sleep efficiency never
    // computed on Android.
    HealthDataType.SLEEP_SESSION,
  ];

  /// HRV is reported as SDNN on iOS (HealthKit) and RMSSD on Android (Health
  /// Connect). The two are not numerically interchangeable, so the recovery
  /// model must prefer the platform-native kind and never mix them into one
  /// baseline. This returns the type to *prefer* at request/read time; the
  /// other type is still read where available, but tagged with its own kind so
  /// the snapshot builder can keep the trend lines separate.
  static HealthDataType? get platformHrvType {
    if (Platform.isIOS) return HealthDataType.HEART_RATE_VARIABILITY_SDNN;
    if (Platform.isAndroid) return HealthDataType.HEART_RATE_VARIABILITY_RMSSD;
    return null;
  }

  /// The HRV types to read for the current platform, platform-native first so a
  /// user is not mixing SDNN and RMSSD into one baseline. Both are still read
  /// where the platform exposes them.
  static List<HealthDataType> get hrvTypesForPlatform {
    const sdnn = HealthDataType.HEART_RATE_VARIABILITY_SDNN;
    const rmssd = HealthDataType.HEART_RATE_VARIABILITY_RMSSD;
    if (Platform.isAndroid) return const [rmssd, sdnn];
    // iOS and unknown platforms: SDNN is the HealthKit-native kind.
    return const [sdnn, rmssd];
  }

  static const List<HealthDataType> activityMetricTypes = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
    HealthDataType.WALKING_HEART_RATE,
    HealthDataType.DISTANCE_WALKING_RUNNING,
    HealthDataType.DISTANCE_CYCLING,
    HealthDataType.DISTANCE_SWIMMING,
  ];

  /// High-resolution observations are uploaded separately from the dashboard's
  /// daily read model. HEART_RATE is intentionally kept out of
  /// [activityMetricTypes] so opening the dashboard does not fetch thousands of
  /// points; the bounded backend sync opts into this list explicitly.
  static const List<HealthDataType> observationMetricTypes = [
    ...bodyMetricTypes,
    ...recoveryMetricTypes,
    ...activityMetricTypes,
    HealthDataType.HEART_RATE,
  ];

  static const Set<HealthDataType> _optionalRecoveryTypes = {
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.BODY_TEMPERATURE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
  };

  static const List<HealthDataType> weightMetricTypes = [HealthDataType.WEIGHT];

  /// Recovery signals the backend recovery sync uploads (HRV SDNN/RMSSD,
  /// resting heart rate, and the sleep types that feed sleep_duration).
  /// Used to gate the recovery sync independently of weight: a user who
  /// grants HRV/RHR/sleep but denies weight should still sync recovery.
  static const List<HealthDataType> recoverySyncMetricTypes = [
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
  ];

  /// Recovery signal groups for the backend recovery sync, keyed by the signal
  /// the cross-domain coach reads. Health Connect (Android) does not expose
  /// every HealthKit (iOS) type — e.g. HRV is SDNN on iOS but RMSSD on Android —
  /// so the recovery sync gates and uploads PER GROUP: it proceeds for any group
  /// whose types are platform-supported and granted, and skips the rest, rather
  /// than treating the union as one all-or-nothing permission list.
  static const Map<String, List<HealthDataType>> recoverySignalGroups = {
    'hrv_sdnn': [HealthDataType.HEART_RATE_VARIABILITY_SDNN],
    'hrv_rmssd': [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
    'resting_heart_rate': [HealthDataType.RESTING_HEART_RATE],
    'sleep_duration': [
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
    ],
  };

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _health.configure();
      _configured = true;
    } catch (_) {
      // ignore configuration errors; platform may not support health data
    }
  }

  Future<bool> isServiceAvailable() async {
    if (kIsWeb) return false;
    await _ensureConfigured();
    if (Platform.isAndroid) {
      try {
        return await _health.isHealthConnectAvailable();
      } catch (_) {
        return false;
      }
    }
    if (Platform.isIOS) {
      // HealthKit availability can be inferred by checking a known data type.
      return _health.isDataTypeAvailable(HealthDataType.WEIGHT);
    }
    return false;
  }

  /// Reachability of the underlying provider. iOS HealthKit is built in, so it
  /// reports [HealthProviderAvailability.available]; the real gap there is
  /// per-signal data. Android probes Health Connect's SDK status so a missing
  /// or out-of-date app can be routed to an install/update action.
  ///
  /// Availability is NEVER used to gate readiness — empty reads are treated as
  /// "no data yet", not "denied". This only powers the connect-flow copy.
  Future<HealthProviderAvailability> providerAvailability() async {
    if (kIsWeb) return HealthProviderAvailability.unsupported;
    await _ensureConfigured();
    if (Platform.isIOS) {
      final available = _health.isDataTypeAvailable(HealthDataType.WEIGHT);
      return available
          ? HealthProviderAvailability.available
          : HealthProviderAvailability.unsupported;
    }
    if (Platform.isAndroid) {
      try {
        final status = await _health.getHealthConnectSdkStatus();
        switch (status) {
          case HealthConnectSdkStatus.sdkAvailable:
            return HealthProviderAvailability.available;
          case HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
            return HealthProviderAvailability.needsUpdate;
          case HealthConnectSdkStatus.sdkUnavailable:
          case null:
            return HealthProviderAvailability.needsInstall;
        }
      } catch (_) {
        return HealthProviderAvailability.needsInstall;
      }
    }
    return HealthProviderAvailability.unsupported;
  }

  /// Routes the user to install / update Health Connect (Android only). No-op on
  /// other platforms.
  Future<void> installHealthConnect() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _ensureConfigured();
    try {
      await _health.installHealthConnect();
    } catch (_) {
      // Best-effort: the user can still install from the store manually.
    }
  }

  /// Derive which recovery signals are actually flowing by reading the most
  /// recent value for each over a recent window. Availability is data-driven,
  /// never a permission boolean: a "connected" user supplying zero HRV reads as
  /// `hrv: false` so the UI can offer a targeted re-grant prompt.
  Future<RecoverySignalAvailability> recoverySignalAvailability({
    Duration lookback = const Duration(days: 14),
  }) async {
    final provider = await providerAvailability();
    if (kIsWeb || provider == HealthProviderAvailability.unsupported) {
      return RecoverySignalAvailability(providerAvailability: provider);
    }

    final now = DateTime.now();
    final start = now.subtract(lookback);

    Future<bool> hasData(List<HealthDataType> types) async {
      for (final type in types) {
        if (!_health.isDataTypeAvailable(type)) continue;
        try {
          final points = await _health.getHealthDataFromTypes(
            types: [type],
            startTime: start,
            endTime: now,
          );
          if (points.any((p) => _extractNumericValue(p.value) != null)) {
            return true;
          }
        } catch (_) {
          // Treat read failures as "no data" — availability stays best-effort.
        }
      }
      return false;
    }

    final hrv = await hasData(hrvTypesForPlatform);
    final rhr = await hasData(const [HealthDataType.RESTING_HEART_RATE]);
    // Count staged sleep too: modern Apple Watch nights write REM/deep/light
    // (Core) stages and no aggregate SLEEP_ASLEEP, so probing asleep/in-bed
    // alone reports sleep "missing" for users who clearly have sleep data.
    final sleep = await hasData(const [
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
    ]);
    final respiratory = await hasData(const [HealthDataType.RESPIRATORY_RATE]);

    return RecoverySignalAvailability(
      providerAvailability: provider,
      hrv: hrv,
      restingHeartRate: rhr,
      sleep: sleep,
      respiratoryRate: respiratory,
    );
  }

  Future<bool?> hasPermissions(List<HealthDataType> types) async {
    if (kIsWeb) return false;
    await _ensureConfigured();
    try {
      return await _health.hasPermissions(
        types,
        permissions: List<HealthDataAccess>.filled(
          types.length,
          HealthDataAccess.READ,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Best-effort connectivity check: returns `true` if AT LEAST ONE of [types]
  /// is granted, `false` if none are, and `null` when the platform cannot
  /// report READ status (iOS HealthKit).
  ///
  /// This deliberately avoids [hasPermissions], whose underlying Health Connect
  /// call is all-or-nothing (it returns `true` only when EVERY requested type is
  /// granted). A single ungranted — or never-grantable — type would otherwise
  /// report the whole set as denied and dead-end the dashboard. The dashboard
  /// gate should consider a user connected if they granted anything useful, then
  /// surface per-signal availability for the rest (matching the per-group
  /// best-effort pattern the backend recovery sync already uses).
  Future<bool?> hasAnyPermission(List<HealthDataType> types) async {
    if (kIsWeb) return false;
    await _ensureConfigured();
    // iOS cannot report READ permission status; a single aggregate call returns
    // null, which the repository maps to `assumedGranted`. Avoid N per-type
    // probes that would each just return null.
    if (Platform.isIOS) {
      return hasPermissions(types);
    }
    var sawNull = false;
    for (final type in types) {
      if (!_health.isDataTypeAvailable(type)) continue;
      try {
        final granted = await _health.hasPermissions(
          [type],
          permissions: const [HealthDataAccess.READ],
        );
        if (granted == true) return true;
        if (granted == null) sawNull = true;
      } catch (_) {
        // Treat an errored probe as unknown for this type.
      }
    }
    return sawNull ? null : false;
  }

  Future<bool> requestPermissions(List<HealthDataType> types) async {
    if (kIsWeb) return false;
    await _ensureConfigured();
    try {
      return await _health.requestAuthorization(
        types,
        permissions: List<HealthDataAccess>.filled(
          types.length,
          HealthDataAccess.READ,
        ),
      );
    } catch (error) {
      // A thrown error here is NOT a clean denial: surface it as a warning so
      // it isn't silently conflated with the user declining. The repository
      // decides connectivity via hasAnyPermission post-request, so returning
      // false stays safe and the signature is unchanged.
      _recordWarning(
        "We couldn't open the $_providerLabel permission prompt "
        '(${error.runtimeType}). Please try again.',
      );
      return false;
    }
  }

  Future<List<HealthDataType>> supportedTypes(
    List<HealthDataType> types,
  ) async {
    if (kIsWeb) return const [];
    await _ensureConfigured();
    return types.where(_health.isDataTypeAvailable).toList();
  }

  /// Read metric samples in [start]..[end].
  ///
  /// When [types] is null the full body+recovery+activity union is read (the
  /// default the dashboard relies on) with best-effort per-type isolation. Pass
  /// explicit [types] for a backend-sync read: only those types are queried and
  /// any unexpected platform read failure is rethrown after recording its
  /// warning. Production metric reads run in a worker isolate so HealthKit
  /// mapping and normalization never contend with Train scrolling. The injected
  /// source used by unit tests retains the current-isolate path.
  Future<List<HealthMetricSample>> readMetricSamples(
    DateTime start,
    DateTime end, {
    Iterable<HealthDataType>? types,
  }) async {
    if (kIsWeb) return const [];
    await _ensureConfigured();

    final isBackendSyncRead = types != null;
    final readTypes =
        types ??
        const [
          ...bodyMetricTypes,
          ...recoveryMetricTypes,
          ...activityMetricTypes,
        ];

    final availableTypes = readTypes
        .where(_health.isDataTypeAvailable)
        .toList(growable: false);
    if (_useBackgroundMetricReads && availableTypes.isNotEmpty) {
      final rootToken = ServicesBinding.rootIsolateToken;
      if (rootToken != null) {
        final result = await compute(
          _readHealthMetricsInBackground,
          _BackgroundHealthReadRequest(
            rootToken: rootToken,
            start: start,
            end: end,
            types: availableTypes,
            isBackendSyncRead: isBackendSyncRead,
          ),
        );
        for (final warning in result.warnings) {
          _recordWarning(warning);
        }
        final error = result.error;
        if (error != null) {
          final exception = error.platformCode == null
              ? StateError(error.message)
              : PlatformException(
                  code: error.platformCode!,
                  message: error.message,
                );
          Error.throwWithStackTrace(
            exception,
            StackTrace.fromString(error.stackTrace),
          );
        }
        return result.samples;
      }
    }

    return _readMetricSamplesOnCurrentIsolate(
      start,
      end,
      types: availableTypes,
      isBackendSyncRead: isBackendSyncRead,
      chunkHeartRateByDay: isBackendSyncRead && _useBackgroundMetricReads,
    );
  }

  Future<List<HealthMetricSample>> _readMetricSamplesOnCurrentIsolate(
    DateTime start,
    DateTime end, {
    required List<HealthDataType> types,
    required bool isBackendSyncRead,
    bool chunkHeartRateByDay = false,
  }) async {
    Future<List<HealthMetricSample>> readWindow(
      HealthDataType type,
      DateTime windowStart,
      DateTime windowEnd,
    ) async {
      try {
        final points = await _health.getHealthDataFromTypes(
          types: [type],
          startTime: windowStart,
          endTime: windowEnd,
        );
        return points
            .map(_mapMetricPoint)
            .whereType<HealthMetricSample>()
            .toList();
      } catch (error, stackTrace) {
        final expectedUnavailable = _handleReadFailure(
          type,
          error,
          permissionFiltered: isBackendSyncRead,
        );
        if (isBackendSyncRead && !expectedUnavailable) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        return const <HealthMetricSample>[];
      }
    }

    Future<List<HealthMetricSample>> readType(HealthDataType type) async {
      if (!chunkHeartRateByDay || type != HealthDataType.HEART_RATE) {
        return readWindow(type, start, end);
      }

      // health 13.1.3 still completes iOS reads through DispatchQueue.main.
      // Keep high-volume heart-rate replies bounded even though Dart decoding,
      // mapping, and normalization happen in this worker isolate. This is
      // payload chunking only; there is no timer or frame delay between days.
      final samples = <HealthMetricSample>[];
      var chunkStart = start;
      while (!chunkStart.isAfter(end)) {
        final nextDay = chunkStart.isUtc
            ? DateTime.utc(
                chunkStart.year,
                chunkStart.month,
                chunkStart.day + 1,
              )
            : DateTime(chunkStart.year, chunkStart.month, chunkStart.day + 1);
        final candidateEnd = nextDay.subtract(const Duration(milliseconds: 1));
        final chunkEnd = candidateEnd.isBefore(end) ? candidateEnd : end;
        samples.addAll(await readWindow(type, chunkStart, chunkEnd));
        chunkStart = nextDay;
      }
      return samples;
    }

    // Interactive dashboard reads retain their parallel, best-effort behavior.
    // Explicit backend reads run sequentially inside the worker isolate so a
    // large set of HealthKit replies cannot land as one decode burst.
    if (!isBackendSyncRead) {
      final perType = await Future.wait(types.map(readType));
      return [for (final batch in perType) ...batch];
    }

    final samples = <HealthMetricSample>[];
    for (final type in types) {
      samples.addAll(await readType(type));
    }
    return samples;
  }

  Future<List<HeartRateSample>> readHeartRateSamples(
    DateTime start,
    DateTime end,
  ) async {
    if (kIsWeb) return const [];
    await _ensureConfigured();
    const type = HealthDataType.HEART_RATE;
    if (!_health.isDataTypeAvailable(type)) {
      _recordWarning(
        '${_describeType(type)} is not supported on this device yet.',
      );
      return const [];
    }

    try {
      final points = await _health.getHealthDataFromTypes(
        types: [type],
        startTime: start,
        endTime: end,
      );
      return points
          .map(_mapHeartRatePoint)
          .whereType<HeartRateSample>()
          .toList();
    } catch (error) {
      _handleReadFailure(type, error);
      return const [];
    }
  }

  /// Fetch the most recent available sample for the given [types].
  ///
  /// This is used as a fallback when the selected date range yields no data
  /// (e.g., user hasn’t logged weight recently but has an older entry).
  Future<List<HealthMetricSample>> readLatestMetricSamples(
    List<HealthDataType> types,
  ) async {
    if (kIsWeb) return const [];
    await _ensureConfigured();

    final now = DateTime.now();
    // Look back a long time but avoid Unix epoch related issues on platforms.
    final lookbackStart = DateTime(now.year - 10, 1, 1);
    final availableTypes = types
        .where(_health.isDataTypeAvailable)
        .toList(growable: false);
    if (_useBackgroundMetricReads && availableTypes.isNotEmpty) {
      final rootToken = ServicesBinding.rootIsolateToken;
      if (rootToken != null) {
        final result = await compute(
          _readHealthMetricsInBackground,
          _BackgroundHealthReadRequest(
            rootToken: rootToken,
            start: lookbackStart,
            end: now,
            types: availableTypes,
            isBackendSyncRead: false,
            latestOnly: true,
          ),
        );
        return result.samples;
      }
    }

    return _readLatestMetricSamplesOnCurrentIsolate(
      availableTypes,
      lookbackStart: lookbackStart,
      now: now,
    );
  }

  Future<List<HealthMetricSample>> _readLatestMetricSamplesOnCurrentIsolate(
    List<HealthDataType> types, {
    required DateTime lookbackStart,
    required DateTime now,
  }) async {
    final latestByType = <HealthMetricType, HealthMetricSample>{};

    for (final type in types) {
      if (!_health.isDataTypeAvailable(type)) {
        continue;
      }
      try {
        final points = await _health.getHealthDataFromTypes(
          types: [type],
          startTime: lookbackStart,
          endTime: now,
        );
        final mapped = points
            .map(_mapMetricPoint)
            .whereType<HealthMetricSample>()
            .toList();
        if (mapped.isEmpty) continue;
        mapped.sort((a, b) => a.endTime.compareTo(b.endTime));
        final latest = mapped.last;
        latestByType[latest.type] = latest;
      } catch (_) {
        // Ignore errors here; this is a best-effort fallback probe.
      }
    }

    // Return in a stable order.
    final result = <HealthMetricSample>[];
    for (final t in [
      HealthMetricType.weight,
      HealthMetricType.height,
      HealthMetricType.bodyMassIndex,
      HealthMetricType.bodyFatPercentage,
    ]) {
      final s = latestByType[t];
      if (s != null) result.add(s);
    }
    return result;
  }

  List<String> drainWarnings() {
    final warnings = List<String>.from(_pendingWarnings);
    _pendingWarnings.clear();
    return warnings;
  }

  HealthMetricSample? _mapMetricPoint(HealthDataPoint point) {
    final type = _mapMetricType(point.type);
    if (type == null) return null;
    final numericValue = _extractNumericValue(point.value);
    if (numericValue == null) return null;

    final mapped = _mapMetricValue(point, type, numericValue);
    if (mapped == null) return null;
    final userEntered = _isManual(point);
    return mapped.copyWith(
      startTime: point.dateFrom.toUtc(),
      endTime: point.dateTo.toUtc(),
      externalId: point.uuid,
      sourceId: point.sourceId,
      sourceDeviceId: point.sourceDeviceId,
      deviceModel: point.deviceModel,
      platform: point.sourcePlatform.name,
      recordingMethod: point.recordingMethod.name,
      timezoneName: point.dateTo.timeZoneName,
      timezoneOffsetMinutes: point.dateTo.timeZoneOffset.inMinutes,
      quality: userEntered
          ? HealthDataQuality.userEntered
          : HealthDataQuality.measured,
      completeness: HealthDataCompleteness.complete,
    );
  }

  HealthMetricSample? _mapMetricValue(
    HealthDataPoint point,
    HealthMetricType type,
    double numericValue,
  ) {
    switch (point.type) {
      case HealthDataType.WEIGHT:
        return HealthMetricSample(
          type: type,
          value: _normalizeWeight(numericValue, point.unit),
          unit: 'kg',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.HEIGHT:
        return HealthMetricSample(
          type: type,
          value: _normalizeHeight(numericValue, point.unit),
          unit: 'cm',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.BODY_FAT_PERCENTAGE:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: '%',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.BODY_MASS_INDEX:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: 'kg/m²',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.STEPS:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: 'count',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return HealthMetricSample(
          type: type,
          value: _normalizeEnergy(numericValue, point.unit),
          unit: 'kcal',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.EXERCISE_TIME:
        return HealthMetricSample(
          type: type,
          value: _normalizeMinutes(numericValue, point.unit),
          unit: 'min',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.HEART_RATE:
      case HealthDataType.WALKING_HEART_RATE:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: 'bpm',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: 'ms',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: 'ms',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.RESTING_HEART_RATE:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: 'bpm',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.RESPIRATORY_RATE:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: 'breaths/min',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.BLOOD_OXYGEN:
        return HealthMetricSample(
          type: type,
          value: numericValue,
          unit: '%',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.BODY_TEMPERATURE:
        return HealthMetricSample(
          type: type,
          value: _normalizeTemperature(numericValue, point.unit),
          unit: 'C',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
      case HealthDataType.SLEEP_SESSION:
      case HealthDataType.SLEEP_REM:
      case HealthDataType.SLEEP_DEEP:
      case HealthDataType.SLEEP_LIGHT:
      case HealthDataType.SLEEP_AWAKE:
        return HealthMetricSample(
          type: type,
          value: _normalizeMinutes(numericValue, point.unit),
          unit: 'min',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      case HealthDataType.DISTANCE_WALKING_RUNNING:
      case HealthDataType.DISTANCE_CYCLING:
      case HealthDataType.DISTANCE_SWIMMING:
        return HealthMetricSample(
          type: type,
          value: _normalizeDistance(numericValue, point.unit),
          unit: 'km',
          startTime: point.dateFrom,
          endTime: point.dateTo,
          source: point.sourceName,
          isUserEntered: _isManual(point),
        );
      default:
        return null;
    }
  }

  bool _isManual(HealthDataPoint point) {
    return point.recordingMethod == RecordingMethod.manual ||
        (point.metadata?['was_user_entered'] == true);
  }

  /// Records a useful warning and reports whether [error] means the requested
  /// signal is expectedly unavailable rather than the read itself failing.
  /// HealthKit cannot disclose read authorization up front, so denied or
  /// not-yet-determined optional signals must degrade to an empty per-type read;
  /// transient/provider errors return false so backend sync fails closed and
  /// remains immediately retryable.
  bool _handleReadFailure(
    HealthDataType type,
    Object error, {
    bool permissionFiltered = false,
  }) {
    final label = _describeType(type);
    if (error is PlatformException) {
      final message = (error.message ?? error.code).trim();
      if (_shouldIgnoreNotDetermined(
        type,
        message,
        permissionFiltered: permissionFiltered,
      )) {
        return true;
      }
      if (message.contains('errorAuthorizationDenied') ||
          message.contains('error 4')) {
        _recordWarning(
          Platform.isAndroid
              ? 'Health Connect denied access to $label. Double-check the $label permission under Health Connect → App permissions → Hustl and try again.'
              : 'Apple Health denied access to $label. Double-check the $label toggle under Apple Health → Apps → Hustl and try again.',
        );
        return true;
      }
      _recordWarning(
        "We couldn't read $label from $_providerLabel ($message). Make sure $label is enabled for Hustl and try again.",
      );
      return false;
    }

    _recordWarning(
      "We couldn't read $label from $_providerLabel (${error.runtimeType}).",
    );
    return false;
  }

  bool _shouldIgnoreNotDetermined(
    HealthDataType type,
    String message, {
    required bool permissionFiltered,
  }) {
    // Explicit backend-sync reads have already permission-filtered each type.
    // HealthKit cannot reveal read authorization, so "not determined" can be
    // the normal result for any requested observation (including heart rate
    // and activity), not only the optional recovery subset. Dashboard reads
    // keep the older iOS-only optional-signal suppression.
    if (!permissionFiltered && !Platform.isIOS) {
      return false;
    }

    final normalized = message.toLowerCase();
    final notDetermined =
        normalized.contains('authorization not determined') ||
        normalized.contains('errorauthorizationnotdetermined');
    if (!notDetermined) {
      return false;
    }

    return permissionFiltered || _optionalRecoveryTypes.contains(type);
  }

  void _recordWarning(String message) {
    if (_pendingWarnings.contains(message)) return;
    _pendingWarnings.add(message);
    if (kDebugMode) {
      debugPrint('HealthPlatformSource warning: $message');
    }
  }

  String _describeType(HealthDataType type) {
    switch (type) {
      case HealthDataType.WEIGHT:
        return 'Weight';
      case HealthDataType.HEIGHT:
        return 'Height';
      case HealthDataType.BODY_MASS_INDEX:
        return 'Body Mass Index';
      case HealthDataType.BODY_FAT_PERCENTAGE:
        return 'Body Fat Percentage';
      case HealthDataType.STEPS:
        return 'Steps';
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return 'Active energy';
      case HealthDataType.EXERCISE_TIME:
        return 'Exercise time';
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        return 'HRV (SDNN)';
      case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
        return 'HRV (RMSSD)';
      case HealthDataType.RESTING_HEART_RATE:
        return 'Resting heart rate';
      case HealthDataType.RESPIRATORY_RATE:
        return 'Respiratory rate';
      case HealthDataType.BLOOD_OXYGEN:
        return 'Blood oxygen';
      case HealthDataType.BODY_TEMPERATURE:
        return 'Body temperature';
      case HealthDataType.SLEEP_ASLEEP:
        return 'Sleep';
      case HealthDataType.SLEEP_IN_BED:
      case HealthDataType.SLEEP_SESSION:
        return 'Time in bed';
      case HealthDataType.SLEEP_REM:
        return 'REM sleep';
      case HealthDataType.SLEEP_DEEP:
        return 'Deep sleep';
      case HealthDataType.SLEEP_LIGHT:
        return 'Light sleep';
      case HealthDataType.SLEEP_AWAKE:
        return 'Awake time';
      case HealthDataType.HEART_RATE:
        return 'Heart rate';
      default:
        return type.name;
    }
  }

  HeartRateSample? _mapHeartRatePoint(HealthDataPoint point) {
    final numericValue = _extractNumericValue(point.value);
    if (numericValue == null) return null;
    if (!numericValue.isFinite || numericValue <= 0) return null;
    return HeartRateSample(
      time: point.dateFrom,
      bpm: numericValue,
      source: point.sourceName,
    );
  }

  double? _extractNumericValue(HealthValue value) {
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    return null;
  }

  HealthMetricType? _mapMetricType(HealthDataType type) {
    switch (type) {
      case HealthDataType.WEIGHT:
        return HealthMetricType.weight;
      case HealthDataType.HEIGHT:
        return HealthMetricType.height;
      case HealthDataType.BODY_MASS_INDEX:
        return HealthMetricType.bodyMassIndex;
      case HealthDataType.BODY_FAT_PERCENTAGE:
        return HealthMetricType.bodyFatPercentage;
      case HealthDataType.STEPS:
        return HealthMetricType.steps;
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return HealthMetricType.activeEnergyBurned;
      case HealthDataType.EXERCISE_TIME:
        return HealthMetricType.exerciseTime;
      case HealthDataType.HEART_RATE:
        return HealthMetricType.heartRate;
      case HealthDataType.WALKING_HEART_RATE:
        return HealthMetricType.walkingHeartRate;
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        return HealthMetricType.heartRateVariabilitySdnn;
      case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
        return HealthMetricType.heartRateVariabilityRmssd;
      case HealthDataType.RESTING_HEART_RATE:
        return HealthMetricType.restingHeartRate;
      case HealthDataType.RESPIRATORY_RATE:
        return HealthMetricType.respiratoryRate;
      case HealthDataType.BLOOD_OXYGEN:
        return HealthMetricType.bloodOxygen;
      case HealthDataType.BODY_TEMPERATURE:
        return HealthMetricType.bodyTemperature;
      case HealthDataType.SLEEP_ASLEEP:
        return HealthMetricType.sleepAsleep;
      case HealthDataType.SLEEP_IN_BED:
      case HealthDataType.SLEEP_SESSION:
        return HealthMetricType.sleepInBed;
      case HealthDataType.SLEEP_REM:
        return HealthMetricType.sleepRem;
      case HealthDataType.SLEEP_DEEP:
        return HealthMetricType.sleepDeep;
      case HealthDataType.SLEEP_LIGHT:
        return HealthMetricType.sleepLight;
      case HealthDataType.SLEEP_AWAKE:
        return HealthMetricType.sleepAwake;
      case HealthDataType.DISTANCE_WALKING_RUNNING:
        return HealthMetricType.distanceWalkingRunning;
      case HealthDataType.DISTANCE_CYCLING:
        return HealthMetricType.distanceCycling;
      case HealthDataType.DISTANCE_SWIMMING:
        return HealthMetricType.distanceSwimming;
      default:
        return null;
    }
  }

  double _normalizeWeight(double value, HealthDataUnit unit) {
    switch (unit) {
      case HealthDataUnit.POUND:
        return value * 0.45359237;
      case HealthDataUnit.OUNCE:
        return value * 0.0283495231;
      case HealthDataUnit.GRAM:
        return value / 1000.0;
      default:
        return value;
    }
  }

  double _normalizeHeight(double value, HealthDataUnit unit) {
    switch (unit) {
      case HealthDataUnit.METER:
        return value * 100.0;
      case HealthDataUnit.INCH:
        return value * 2.54;
      case HealthDataUnit.FOOT:
        return value * 30.48;
      case HealthDataUnit.YARD:
        return value * 91.44;
      default:
        return value;
    }
  }

  double _normalizeEnergy(double value, HealthDataUnit unit) {
    switch (unit) {
      case HealthDataUnit.JOULE:
        return value / 4184.0;
      case HealthDataUnit.LARGE_CALORIE:
      case HealthDataUnit.KILOCALORIE:
        return value;
      case HealthDataUnit.SMALL_CALORIE:
        return value / 1000.0;
      default:
        return value;
    }
  }

  double _normalizeMinutes(double value, HealthDataUnit unit) {
    switch (unit) {
      case HealthDataUnit.SECOND:
        return value / 60.0;
      case HealthDataUnit.HOUR:
        return value * 60.0;
      case HealthDataUnit.DAY:
        return value * 1440.0;
      default:
        return value;
    }
  }

  double _normalizeDistance(double value, HealthDataUnit unit) {
    switch (unit) {
      case HealthDataUnit.METER:
        return value / 1000.0;
      case HealthDataUnit.MILE:
        return value * 1.609344;
      default:
        return value;
    }
  }

  double _normalizeTemperature(double value, HealthDataUnit unit) {
    switch (unit) {
      case HealthDataUnit.DEGREE_FAHRENHEIT:
        return (value - 32.0) * 5.0 / 9.0;
      case HealthDataUnit.KELVIN:
        return value - 273.15;
      default:
        return value;
    }
  }
}

class _BackgroundHealthReadRequest {
  const _BackgroundHealthReadRequest({
    required this.rootToken,
    required this.start,
    required this.end,
    required this.types,
    required this.isBackendSyncRead,
    this.latestOnly = false,
  });

  final RootIsolateToken rootToken;
  final DateTime start;
  final DateTime end;
  final List<HealthDataType> types;
  final bool isBackendSyncRead;
  final bool latestOnly;
}

class _BackgroundHealthReadError {
  const _BackgroundHealthReadError({
    required this.message,
    required this.stackTrace,
    this.platformCode,
  });

  final String message;
  final String stackTrace;
  final String? platformCode;
}

class _BackgroundHealthReadResult {
  const _BackgroundHealthReadResult({
    required this.samples,
    required this.warnings,
    this.error,
  });

  final List<HealthMetricSample> samples;
  final List<String> warnings;
  final _BackgroundHealthReadError? error;
}

Future<_BackgroundHealthReadResult> _readHealthMetricsInBackground(
  _BackgroundHealthReadRequest request,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(request.rootToken);
  final source = HealthPlatformSource._background();
  await source._ensureConfigured();
  try {
    final samples = request.latestOnly
        ? await source._readLatestMetricSamplesOnCurrentIsolate(
            request.types,
            lookbackStart: request.start,
            now: request.end,
          )
        : await source._readMetricSamplesOnCurrentIsolate(
            request.start,
            request.end,
            types: request.types,
            isBackendSyncRead: request.isBackendSyncRead,
            chunkHeartRateByDay: request.isBackendSyncRead,
          );
    return _BackgroundHealthReadResult(
      samples: samples,
      warnings: source.drainWarnings(),
    );
  } catch (error, stackTrace) {
    return _BackgroundHealthReadResult(
      samples: const [],
      warnings: source.drainWarnings(),
      error: _BackgroundHealthReadError(
        platformCode: error is PlatformException ? error.code : null,
        message: error is PlatformException
            ? (error.message ?? error.code)
            : error.toString(),
        stackTrace: stackTrace.toString(),
      ),
    );
  }
}
