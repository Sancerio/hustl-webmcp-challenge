import 'dart:async';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/scheduler.dart' show Priority, SchedulerBinding;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:health/health.dart' show HealthDataType;

import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/token_storage.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/repositories/workout_repository.dart';
import '../../domain/models/external_activity.dart';
import '../../domain/models/health_metric_sample.dart';
import '../../domain/services/external_activity_filter.dart';
import '../../domain/usecases/build_daily_recovery_snapshots.dart';
import '../../domain/usecases/build_sleep_sessions.dart';
import '../datasources/hustl_backend_health_api.dart';
import '../sources/external_activity_reader.dart';
import '../sources/health_platform_source.dart';

class HealthBackendSyncService with WidgetsBindingObserver {
  HealthBackendSyncService({
    required HealthPlatformSource platformSource,
    required HustlBackendHealthApi api,
    required TokenStorage tokens,
    PreferencesService? preferences,
    ExternalActivityReader? externalActivityReader,
    ExternalActivityFilter externalActivityFilter =
        const ExternalActivityFilter(),
    WorkoutRepository? workoutRepository,
    bool enableCrossPlatformHealthSync = false,
    DateTime Function()? now,
    Duration resumeDebounce = const Duration(milliseconds: 500),
    Duration resumeCooldown = const Duration(minutes: 10),
    void Function(Future<void> Function())? scheduleWhenIdle,
    Future<void> Function()? yieldToUi,
  }) : _platformSource = platformSource,
       _api = api,
       _tokens = tokens,
       _preferences = preferences,
       _externalActivityReader = externalActivityReader,
       _externalActivityFilter = externalActivityFilter,
       _workoutRepository = workoutRepository,
       _enableCrossPlatformHealthSync = enableCrossPlatformHealthSync,
       _now = now ?? DateTime.now,
       _resumeDebounce = resumeDebounce,
       _resumeCooldown = resumeCooldown,
       _scheduleWhenIdle = scheduleWhenIdle ?? _defaultScheduleWhenIdle,
       _yieldToUi = yieldToUi ?? _defaultYieldToUi;

  final HealthPlatformSource _platformSource;
  final HustlBackendHealthApi _api;
  final TokenStorage _tokens;

  /// Persists the last-synced high-watermark so cold starts only re-read days
  /// newer than (watermark - [_overlapDays]) instead of the full [days] window.
  /// Null disables the cursor entirely (always full window) — keeps the legacy
  /// behavior for callers/tests that don't wire preferences.
  final PreferencesService? _preferences;
  final ExternalActivityReader? _externalActivityReader;
  final ExternalActivityFilter _externalActivityFilter;
  final WorkoutRepository? _workoutRepository;
  final bool _enableCrossPlatformHealthSync;
  final DateTime Function() _now;
  final Duration _resumeDebounce;
  final Duration _resumeCooldown;
  final void Function(Future<void> Function()) _scheduleWhenIdle;
  final Future<void> Function() _yieldToUi;

  bool _launchSyncPending = false;
  Timer? _resumeDebouncer;
  bool _observerAttached = false;
  bool _isSyncingAll = false;
  bool _syncPending = false;
  final Map<String, DateTime> _lastUploadedAt = {};
  int _syncEligibilityGeneration = 0;

  // Sync-kind keys for the per-kind watermark stored in [PreferencesService].
  static const String _kindWeight = 'weight';
  static const String _kindRecovery = 'recovery';
  static const String _kindObservations = 'observations';
  static const String _kindCrossPlatformMetrics =
      'cross_platform_health_metrics';
  static const String _kindExternalActivities = 'external_activities';

  static const List<HealthDataType> _crossPlatformMetricTypes = [
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
  ];

  /// Days re-included before the watermark on subsequent runs so a late edit to
  /// a recent day (e.g. a corrected weigh-in) is still picked up. The backend
  /// upsert is idempotent, so re-sending these days is harmless.
  static const int _overlapDays = 2;

  // Recovery metric_type names the backend reads (training_recovery_context.ts).
  static const String _kHrvSdnn = 'hrv_sdnn';
  static const String _kHrvRmssd = 'hrv_rmssd';
  static const String _kRestingHeartRate = 'resting_heart_rate';
  static const String _kSleepDuration = 'sleep_duration';

  /// Attach the app-lifecycle observer. Cold-start sync remains explicit in the
  /// app bootstrapper; subsequent foreground resumes are handled here.
  void startLifecycleSync() {
    if (_observerAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _observerAttached = true;
  }

  void stopLifecycleSync() {
    _launchSyncPending = false;
    _resumeDebouncer?.cancel();
    _resumeDebouncer = null;
    if (!_observerAttached) return;
    WidgetsBinding.instance.removeObserver(this);
    _observerAttached = false;
  }

  /// Clear account-scoped cooldown state after a guest upgrade or account
  /// switch. The generation prevents an old account's in-flight upload from
  /// re-arming eligibility after the reset.
  void resetSyncEligibility() {
    _syncEligibilityGeneration += 1;
    _lastUploadedAt.clear();
  }

  /// Schedule the cold-start refresh at Flutter idle priority without an
  /// arbitrary wall-clock delay. Explicit backend reads decode and normalize
  /// HealthKit payloads in a background isolate, so the launch path only needs
  /// scheduler ordering rather than a fixed grace period.
  void scheduleLaunchSync() {
    if (_launchSyncPending) return;
    _launchSyncPending = true;
    _scheduleWhenIdle(() async {
      if (!_launchSyncPending) return;
      _launchSyncPending = false;
      await syncAllRecent();
    });
  }

  /// Authentication can happen while the app is animating its destination
  /// screen. Use the same idle-aware path as lifecycle resumes instead of
  /// starting HealthKit queries directly from the auth listener.
  void scheduleAuthenticatedSync() {
    // Auth rehydration is part of a normal signed-in cold start. Keep the full
    // pending launch pass in that case; bootstrap has not attached the lifecycle
    // observer yet, and that pass will see the restored token. A
    // later interactive sign-in happens after attachment and still gets a prompt
    // refresh.
    if (!_observerAttached) return;
    if (_launchSyncPending) return;
    _scheduleResumeSync();
  }

  /// Run every eligible backend health pipeline once. Every trigger shares a
  /// per-pipeline cooldown earned only by an actual upload. Concurrent triggers
  /// queue one follow-up pass; it skips pipelines refreshed by the first pass
  /// while retrying anything that was empty, denied, or failed.
  Future<void> syncAllRecent() async {
    if (_isSyncingAll) {
      _syncPending = true;
      return;
    }
    _isSyncingAll = true;
    try {
      do {
        _syncPending = false;
        await _syncAllRecentPass();
      } while (_syncPending);
    } finally {
      _isSyncingAll = false;
    }
  }

  Future<void> _syncAllRecentPass() async {
    String? accessToken;
    try {
      accessToken = await _tokens.getAccessToken();
    } catch (error, stackTrace) {
      debugPrint('[HealthSync] token lookup failed: $error\n$stackTrace');
    }
    if (accessToken == null || accessToken.isEmpty) return;

    // Keep platform pressure bounded and uploads ordered/account-scoped.
    // Explicit HealthKit reads decode and normalize in a background isolate;
    // yielding between pipelines also keeps the remaining payload work and
    // cross-platform Health Connect path responsive after launch.
    await _syncBestEffort(
      _kindWeight,
      () => syncRecentWeights(days: _enableCrossPlatformHealthSync ? 90 : 30),
    );
    await _yieldToUi();
    await _syncBestEffort(
      _kindRecovery,
      () => syncRecentRecoveryMetrics(
        days: _enableCrossPlatformHealthSync ? 90 : 30,
      ),
    );
    await _yieldToUi();
    await _syncBestEffort(_kindObservations, syncRecentObservations);
    if (_enableCrossPlatformHealthSync) {
      await _yieldToUi();
      await _syncBestEffort(
        _kindCrossPlatformMetrics,
        syncRecentCrossPlatformMetrics,
      );
      if (_externalActivityReader != null && _workoutRepository != null) {
        await _yieldToUi();
        await _syncBestEffort(
          _kindExternalActivities,
          syncRecentExternalActivities,
        );
      }
    }
  }

  Future<void> _syncBestEffort(
    String kind,
    Future<bool> Function() sync,
  ) async {
    final now = _now();
    final lastUpload = _lastUploadedAt[kind];
    final elapsed = lastUpload == null ? null : now.difference(lastUpload);
    if (elapsed != null && !elapsed.isNegative && elapsed < _resumeCooldown) {
      return;
    }
    final generation = _syncEligibilityGeneration;
    try {
      final uploaded = await sync();
      if (uploaded && generation == _syncEligibilityGeneration) {
        _lastUploadedAt[kind] = _now();
      }
    } catch (error, stackTrace) {
      debugPrint('[HealthSync] $kind sync failed: $error\n$stackTrace');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Some iOS launches emit a resumed transition while the launch pass is
    // already queued. Do not schedule a duplicate pass.
    if (_launchSyncPending) return;
    _scheduleResumeSync();
  }

  void _scheduleResumeSync() {
    _resumeDebouncer?.cancel();
    _resumeDebouncer = Timer(_resumeDebounce, () {
      _resumeDebouncer = null;
      _scheduleWhenIdle(syncAllRecent);
    });
  }

  @visibleForTesting
  bool get observerAttached => _observerAttached;

  @visibleForTesting
  bool get isSyncingAll => _isSyncingAll;

  Future<bool> syncRecentWeights({int days = 30}) async {
    final prepared = await _prepare(
      days: days,
      kind: _kindWeight,
      gateMetricTypes: HealthPlatformSource.weightMetricTypes,
    );
    if (prepared == null) return false;

    final weightSamples =
        prepared.samples
            .where((s) => s.type == HealthMetricType.weight)
            .toList()
          ..sort((a, b) => a.endTime.compareTo(b.endTime));
    if (weightSamples.isEmpty) return false;

    // Latest weight sample per calendar day.
    final byDay = <String, HealthMetricSample>{};
    for (final s in weightSamples) {
      final dayKey = _dayKey(s.localEndTime);
      final existing = byDay[dayKey];
      if (existing == null || s.endTime.isAfter(existing.endTime)) {
        byDay[dayKey] = s;
      }
    }

    final items =
        byDay.entries
            .map(
              (e) => <String, dynamic>{
                'date': e.key,
                'metricType': 'weight',
                'value': e.value.valueInPreferredUnit,
                'unit': 'kg',
                'source': prepared.provider,
                'syncVersion': 1,
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['date'] as String).compareTo(b['date'] as String),
          );

    await _api.upsertDailyMetrics(
      provider: prepared.provider,
      lastSyncedAt: prepared.now.toUtc().toIso8601String(),
      items: items,
    );
    await _saveWatermark(_kindWeight, items);
    return true;
  }

  /// Upload daily recovery signals (HRV SDNN, HRV RMSSD when present, resting
  /// heart rate, sleep duration) into health_metrics_daily under the EXACT
  /// metric_type names + units the cross-domain coach reads. Reuses the same
  /// HealthKit source, transport, and (user_id,date,metric_type,source)
  /// idempotency as the weight sync.
  Future<bool> syncRecentRecoveryMetrics({int days = 30}) async {
    // Gate on the RECOVERY permissions (HRV/RHR/sleep), independent of weight:
    // a user who grants those but denies weight should still get recovery sync
    // so the cross-domain coach isn't left dormant.
    //
    // The gate is platform-correct and best-effort: Health Connect (Android)
    // does not expose every HealthKit type (e.g. HRV is SDNN on iOS, RMSSD on
    // Android), and the same signal can be granted while a sibling is not. So
    // we resolve which recovery signal GROUPS are supported AND granted on this
    // platform and proceed for any of them, reading/uploading only those groups
    // rather than returning early when the full union isn't granted.
    final prepared = await _prepareRecovery(days: days);
    if (prepared == null) return false;

    final granted = prepared.grantedRecoverySignals;

    final items = <Map<String, dynamic>>[];
    if (granted.contains(_kHrvSdnn)) {
      items.addAll(
        _dailyAverages(
          prepared.samples,
          HealthMetricType.heartRateVariabilitySdnn,
          metricType: _kHrvSdnn,
          unit: 'ms',
          provider: prepared.provider,
        ),
      );
    }
    if (granted.contains(_kHrvRmssd)) {
      items.addAll(
        _dailyAverages(
          prepared.samples,
          HealthMetricType.heartRateVariabilityRmssd,
          metricType: _kHrvRmssd,
          unit: 'ms',
          provider: prepared.provider,
        ),
      );
    }
    if (granted.contains(_kRestingHeartRate)) {
      items.addAll(
        _dailyAverages(
          prepared.samples,
          HealthMetricType.restingHeartRate,
          metricType: _kRestingHeartRate,
          unit: 'bpm',
          provider: prepared.provider,
        ),
      );
    }
    if (granted.contains(_kSleepDuration)) {
      items.addAll(
        _dailySleepDurations(prepared.samples, provider: prepared.provider),
      );
    }

    if (items.isEmpty) return false;

    items.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    await _api.upsertDailyMetrics(
      provider: prepared.provider,
      lastSyncedAt: prepared.now.toUtc().toIso8601String(),
      items: items,
    );
    await _saveWatermark(_kindRecovery, items);
    return true;
  }

  /// Upload the daily aggregates needed by authenticated native and web
  /// clients. Each permission is gated independently: denying body composition
  /// must not suppress steps or exercise, and an unsupported sibling type must
  /// not turn the projection into zero-filled data.
  Future<bool> syncRecentCrossPlatformMetrics({int days = 90}) async {
    // Replay the bounded window instead of sharing a cursor across metric
    // permissions. A user can grant (for example) body-fat access weeks after
    // steps; an incremental shared watermark would otherwise skip the newly
    // available history. Backend upserts keep the replay idempotent.
    final context = await _prepareContext(
      days: days,
      kind: _kindCrossPlatformMetrics,
      useWatermark: false,
    );
    if (context == null) return false;

    final grantedTypes = <HealthDataType>{};
    final supported = await _platformSource.supportedTypes(
      _crossPlatformMetricTypes,
    );
    for (final type in supported) {
      if (await _gateGranted([type], context.provider)) {
        grantedTypes.add(type);
      }
    }
    if (grantedTypes.isEmpty) return false;

    final samples = await _platformSource.readMetricSamples(
      context.start,
      context.end,
      types: grantedTypes,
    );
    if (samples.isEmpty) return false;

    final items = <Map<String, dynamic>>[];
    items.addAll(
      _dailyLatestValues(
        samples,
        HealthMetricType.bodyFatPercentage,
        metricType: 'body_fat_percentage',
        unit: '%',
        provider: context.provider,
      ),
    );
    final snapshots = BuildDailyRecoverySnapshotsUseCase()(
      metrics: samples,
      now: context.now,
    );
    for (final snapshot in snapshots) {
      final date = _dayKey(snapshot.date);
      if (snapshot.steps != null) {
        items.add(
          _dailyItem(
            date: date,
            metricType: 'steps',
            value: snapshot.steps!.toDouble(),
            unit: 'count',
            provider: context.provider,
          ),
        );
      }
      if (snapshot.exerciseMinutes != null) {
        items.add(
          _dailyItem(
            date: date,
            metricType: 'exercise_minutes',
            value: snapshot.exerciseMinutes!,
            unit: 'minutes',
            provider: context.provider,
          ),
        );
      }
      if (snapshot.activeEnergyKilocalories != null) {
        items.add(
          _dailyItem(
            date: date,
            metricType: 'active_energy_kcal',
            value: snapshot.activeEnergyKilocalories!,
            unit: 'kcal',
            provider: context.provider,
          ),
        );
      }
    }
    if (items.isEmpty) return false;
    items.sort((a, b) {
      final byDate = (a['date'] as String).compareTo(b['date'] as String);
      return byDate != 0
          ? byDate
          : (a['metricType'] as String).compareTo(b['metricType'] as String);
    });
    await _api.upsertDailyMetrics(
      provider: context.provider,
      lastSyncedAt: context.now.toUtc().toIso8601String(),
      items: items,
    );
    await _saveWatermark(_kindCrossPlatformMetrics, items);
    return true;
  }

  /// Sync external platform workouts as read-only health sessions for web.
  /// Hustl-authored writeback echoes are removed before upload using the same
  /// identities and overlap policy as native activity views. If any identity source
  /// is unavailable, this path fails closed and uploads nothing.
  Future<bool> syncRecentExternalActivities({int days = 90}) async {
    final reader = _externalActivityReader;
    final workouts = _workoutRepository;
    final preferences = _preferences;
    if (reader == null || workouts == null || preferences == null) return false;
    final context = await _prepareContext(
      days: days,
      kind: _kindExternalActivities,
      // Imported workouts and corrected activity metadata can arrive after the
      // platform workout date. Replaying this low-volume bounded window avoids
      // silently losing them behind a high-watermark.
      useWatermark: false,
    );
    if (context == null) return false;

    late final List<ExternalActivity> rawActivities;
    late final Map<String, String> writebackMappings;
    late final List<WorkoutSession> hustlSessions;
    try {
      rawActivities = await reader.readActivities(
        start: context.start,
        end: context.end,
      );
      writebackMappings = await preferences.getWorkoutWritebackMappings();
      hustlSessions = await workouts.getWorkoutSessions(
        startDate: context.start.subtract(const Duration(microseconds: 1)),
        endDate: context.end.add(const Duration(milliseconds: 1)),
      );
    } catch (_) {
      return false;
    }
    final filtered = _externalActivityFilter.filter(
      activities: rawActivities,
      hustlWritebackUuids: writebackMappings.values.toSet(),
      hustlSessions: hustlSessions,
    );
    if (filtered.isEmpty) return false;

    final sessions = filtered.map(_externalActivityPayload).toList();
    for (var start = 0; start < sessions.length; start += 100) {
      final end = (start + 100).clamp(0, sessions.length);
      await _api.upsertHealthData(
        provider: context.provider,
        lastSyncedAt: context.now.toUtc().toIso8601String(),
        sessions: sessions.sublist(start, end),
      );
    }
    await _saveWatermark(_kindExternalActivities, [
      for (final activity in filtered)
        {'date': _dayKey(activity.start.toLocal())},
    ]);
    return true;
  }

  /// Preserve bounded, timestamped HealthKit/Health Connect observations and
  /// derived sleep sessions. Daily tables remain a compatibility read model;
  /// future meal/workout/glucose analysis uses this raw timeline.
  Future<bool> syncRecentObservations({int days = 14}) async {
    // Always replay the full bounded window. Observation permissions are granted
    // per type, so a shared high-watermark would permanently skip older samples
    // for any type the user enables after the first sync. Backend upserts make
    // this bounded replay idempotent.
    final context = await _prepareContext(
      days: days,
      kind: _kindObservations,
      useWatermark: false,
    );
    if (context == null) return false;

    final grantedTypes = <HealthDataType>{};
    final supported = await _platformSource.supportedTypes(
      HealthPlatformSource.observationMetricTypes,
    );
    for (final type in supported) {
      if (await _gateGranted([type], context.provider)) grantedTypes.add(type);
    }
    if (grantedTypes.isEmpty) return false;

    final samples = await _platformSource.readMetricSamples(
      context.start,
      context.end,
      types: grantedTypes,
    );
    if (samples.isEmpty) return false;

    final sleepSessions = const BuildSleepSessionsUseCase()(
      samples
          .where(
            (sample) =>
                BuildSleepSessionsUseCase.sleepTypes.contains(sample.type),
          )
          .toList(),
      now: context.now,
    );
    final taggedSleep = <String, HealthMetricSample>{
      for (final session in sleepSessions)
        for (final sample in session.observations)
          sample.stableIdentity: sample,
    };
    final unique = <String, HealthMetricSample>{};
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      final tagged = taggedSleep[sample.stableIdentity] ?? sample;
      unique['${tagged.sourceId ?? tagged.source}|${tagged.stableIdentity}'] =
          tagged;
      if ((index + 1) % 250 == 0) await _yieldToUi();
    }
    final observations = <Map<String, dynamic>>[];
    var payloadIndex = 0;
    for (final sample in unique.values) {
      observations.add(sample.toObservationPayload(provider: context.provider));
      payloadIndex += 1;
      if (payloadIndex % 250 == 0) await _yieldToUi();
    }
    final sessions = sleepSessions
        .map((session) => session.toPayload(provider: context.provider))
        .toList();

    for (var start = 0; start < observations.length; start += 500) {
      final end = (start + 500).clamp(0, observations.length);
      await _api.upsertHealthData(
        provider: context.provider,
        lastSyncedAt: context.now.toUtc().toIso8601String(),
        observations: observations.sublist(start, end),
        sessions: start == 0 ? sessions.take(100).toList() : const [],
      );
    }
    await _saveWatermark(_kindObservations, [
      for (final sample in unique.values)
        {'date': _dayKey(sample.localEndTime)},
    ]);
    return true;
  }

  /// Shared gating + read used by both syncs: web/permission/service checks,
  /// provider resolution, and a [days]-deep HealthKit read window.
  ///
  /// [gateMetricTypes] are the permissions this sync requires: the weight
  /// sync gates on weight. This keeps the gate metric-specific so denying one
  /// domain (e.g. weight) doesn't suppress a sync for a domain the user did
  /// grant. The recovery sync uses [_prepareRecovery] for its best-effort,
  /// per-signal-group gate.
  Future<_PreparedSync?> _prepare({
    required int days,
    required String kind,
    required List<HealthDataType> gateMetricTypes,
  }) async {
    final context = await _prepareContext(days: days, kind: kind);
    if (context == null) return null;

    final hasPerms = await _gateGranted(gateMetricTypes, context.provider);
    if (!hasPerms) return null;

    final samples = await _platformSource.readMetricSamples(
      context.start,
      context.end,
      types: gateMetricTypes,
    );
    return _PreparedSync(
      provider: context.provider,
      now: context.now,
      samples: samples,
    );
  }

  /// Recovery-specific preparation: platform-correct, best-effort, per signal
  /// group. Resolves which recovery signal groups are both supported by this
  /// platform's health provider AND granted, then proceeds if ANY group passes
  /// (reading once and letting the caller upload only the granted groups). This
  /// avoids the all-or-nothing trap where one unsupported type on Android (e.g.
  /// HRV SDNN, which Health Connect doesn't expose) or one ungranted sibling
  /// would suppress the whole recovery sync.
  Future<_PreparedRecoverySync?> _prepareRecovery({required int days}) async {
    final context = await _prepareContext(days: days, kind: _kindRecovery);
    if (context == null) return null;

    final granted = <String>{};
    // The exact platform-supported types that are also granted, so the read
    // requests ONLY recovery signals — never the body/activity types a
    // weight-denied user hasn't authorized (which would leave irrelevant
    // permission warnings in the shared source for the next dashboard load).
    final grantedTypes = <HealthDataType>{};
    for (final entry in HealthPlatformSource.recoverySignalGroups.entries) {
      final supported = await _platformSource.supportedTypes(entry.value);
      if (supported.isEmpty) continue; // signal not exposed on this platform
      if (await _gateGranted(supported, context.provider)) {
        granted.add(entry.key);
        grantedTypes.addAll(supported);
      }
    }
    if (granted.isEmpty) return null;

    final samples = await _platformSource.readMetricSamples(
      context.start,
      context.end,
      types: grantedTypes,
    );
    return _PreparedRecoverySync(
      provider: context.provider,
      now: context.now,
      samples: samples,
      grantedRecoverySignals: granted,
    );
  }

  /// Web/days/token/service/provider checks plus the [days]-deep read window,
  /// shared by the weight and recovery preparation paths. Returns null when the
  /// sync cannot run at all (web, no token, service unavailable, or an
  /// unsupported platform).
  Future<_SyncContext?> _prepareContext({
    required int days,
    required String kind,
    bool useWatermark = true,
  }) async {
    if (kIsWeb) return null;
    if (days <= 0) return null;
    final token = await _tokens.getAccessToken();
    if (token == null) return null;

    final serviceAvailable = await _platformSource.isServiceAvailable();
    if (!serviceAvailable) return null;

    final provider = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'apple_health',
      // Keep the legacy 'google_fit' storage key: the backend upsert conflict key
      // includes `source`, so renaming to 'health_connect' would create parallel
      // rows alongside users' existing google_fit data. The UI already remaps this
      // to "Health Connect" for display (scale_weighin_list_card), so only the
      // internal key stays legacy.
      TargetPlatform.android => 'google_fit',
      _ => null,
    };
    if (provider == null) return null;

    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    // First run (or cursor disabled): read the full [days] window. On later runs
    // start just after the watermark, re-including [_overlapDays] for late edits
    // — but never before the full window's first day, so a long-idle install
    // still backfills at most [days].
    final fullWindowStart = today.subtract(Duration(days: days - 1));
    var start = fullWindowStart;
    var watermark = useWatermark ? await _readWatermark(kind) : null;
    // Clock-skew guard: a corrupt or future-dated watermark (device clock moved
    // back, or a bad persisted value) must never push the read window past today
    // and skip the sync. Clamp the watermark to start-of-today before deriving
    // the incremental start.
    if (watermark != null && watermark.isAfter(today)) {
      watermark = today;
    }
    if (watermark != null) {
      final since = watermark.subtract(const Duration(days: _overlapDays));
      if (since.isAfter(start)) start = since;
    }
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    // Final safety net: if anything still left start after end, fall back to the
    // full window so the sync runs sanely rather than reading an inverted/empty
    // range.
    if (start.isAfter(end)) start = fullWindowStart;
    return _SyncContext(provider: provider, now: now, start: start, end: end);
  }

  /// Reads the persisted last-synced day for [kind], or null when the cursor is
  /// disabled, unset (first run), or unparseable.
  Future<DateTime?> _readWatermark(String kind) async {
    final prefs = _preferences;
    if (prefs == null) return null;
    final raw = await prefs.getHealthSyncWatermark(kind);
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// Persists the latest uploaded day for [kind] as the new high-watermark.
  /// [items] each carry a 'date' (YYYY-MM-DD); we record the max so the next
  /// cold start can skip everything up to it (minus the overlap window).
  Future<void> _saveWatermark(
    String kind,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = _preferences;
    if (prefs == null || items.isEmpty) return;
    String? maxDay;
    for (final item in items) {
      final day = item['date'] as String?;
      if (day == null) continue;
      if (maxDay == null || day.compareTo(maxDay) > 0) maxDay = day;
    }
    if (maxDay == null) return;
    // Clamp the saved watermark to today's local date: never persist a future
    // day (e.g. from a sample with a skewed timestamp), so the next run's
    // incremental start can't be pushed past today.
    final now = _now();
    final todayKey = DateTime(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().substring(0, 10);
    if (maxDay.compareTo(todayKey) > 0) maxDay = todayKey;
    // Only ever advance the cursor. A later sync that returns only older overlap
    // data must not regress the watermark, which would needlessly widen future
    // incremental reads/re-uploads.
    final existing = await prefs.getHealthSyncWatermark(kind);
    // Only advance a VALID cursor; never regress it on an older overlap-only
    // sync. But if the stored cursor is itself in the future (clock skew /
    // corruption), still correct it back down to maxDay (already clamped to
    // today) rather than leaving the bad value in place.
    final existingIsValid =
        existing != null && existing.compareTo(todayKey) <= 0;
    if (existingIsValid && existing.compareTo(maxDay) >= 0) return;
    await prefs.setHealthSyncWatermark(kind, maxDay);
  }

  /// True when [types] are granted for reading. On iOS, some plugin versions
  /// return null for hasPermissions even when HealthKit access is effectively
  /// available; align with the UI's permissions logic and assume granted there
  /// so already-connected Apple Health users still get backend sync.
  Future<bool> _gateGranted(List<HealthDataType> types, String provider) async {
    final rawPermissions = await _platformSource.hasPermissions(types);
    final assumedGranted = rawPermissions == null && provider == 'apple_health';
    return rawPermissions ?? assumedGranted;
  }

  /// Per calendar-day mean of a point-in-time metric (HRV, resting HR).
  /// HealthKit can report several readings per day; the backend trend treats
  /// each day as a single value, so we average within the day.
  List<Map<String, dynamic>> _dailyAverages(
    List<HealthMetricSample> samples,
    HealthMetricType type, {
    required String metricType,
    required String unit,
    required String provider,
  }) {
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final s in samples) {
      if (s.type != type) continue;
      final value = s.valueInPreferredUnit;
      if (!value.isFinite) continue;
      final dayKey = _dayKey(s.localEndTime);
      sums[dayKey] = (sums[dayKey] ?? 0) + value;
      counts[dayKey] = (counts[dayKey] ?? 0) + 1;
    }
    return sums.entries
        .map(
          (e) => <String, dynamic>{
            'date': e.key,
            'metricType': metricType,
            'value': e.value / counts[e.key]!,
            'unit': unit,
            'source': provider,
            'syncVersion': 1,
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _dailyLatestValues(
    List<HealthMetricSample> samples,
    HealthMetricType type, {
    required String metricType,
    required String unit,
    required String provider,
  }) {
    final latest = <String, HealthMetricSample>{};
    for (final sample in samples.where((sample) => sample.type == type)) {
      if (!sample.valueInPreferredUnit.isFinite) continue;
      final day = _dayKey(sample.localEndTime);
      final existing = latest[day];
      if (existing == null || sample.endTime.isAfter(existing.endTime)) {
        latest[day] = sample;
      }
    }
    return [
      for (final entry in latest.entries)
        _dailyItem(
          date: entry.key,
          metricType: metricType,
          value: entry.value.valueInPreferredUnit,
          unit: unit,
          provider: provider,
        ),
    ];
  }

  Map<String, dynamic> _dailyItem({
    required String date,
    required String metricType,
    required double value,
    required String unit,
    required String provider,
  }) => {
    'date': date,
    'metricType': metricType,
    'value': value,
    'unit': unit,
    'source': provider,
    'syncVersion': 1,
  };

  Map<String, dynamic> _externalActivityPayload(ExternalActivity activity) => {
    'sessionKey': 'workout|${activity.platformUuid}',
    'sessionType': 'workout',
    'localDate': _dayKey(activity.start.toLocal()),
    'startTime': activity.start.toUtc().toIso8601String(),
    'endTime': activity.end.toUtc().toIso8601String(),
    'timezoneName': activity.start.toLocal().timeZoneName,
    'timezoneOffsetMinutes': activity.start.toLocal().timeZoneOffset.inMinutes,
    'sourceName': activity.sourceName,
    'durationMinutes': activity.durationMinutes,
    'quality': 'measured',
    'completeness': 'complete',
    'sampleCount': 1,
    'metadata': {
      'platformUuid': activity.platformUuid,
      'kind': activity.kind.name,
      'activityName': activity.activityName,
      'distanceMeters': activity.distanceMeters,
      'activeEnergyKcal': activity.activeEnergyKcal,
      'averageHeartRateBpm': activity.averageHeartRateBpm,
    },
  };

  /// Per calendar-day total sleep MINUTES. Mirrors the recovery snapshot
  /// builder: prefer the sum of staged sleep (REM+deep+light) and fall back to
  /// SLEEP_ASLEEP only when no stages exist, so we never double-count a night.
  List<Map<String, dynamic>> _dailySleepDurations(
    List<HealthMetricSample> samples, {
    required String provider,
  }) {
    return const BuildSleepSessionsUseCase()(samples, now: _now())
        .where(
          (session) => session.isComplete && session.durationMinutes != null,
        )
        .map(
          (session) => <String, dynamic>{
            'date': _dayKey(session.localDate),
            'metricType': _kSleepDuration,
            'value': session.durationMinutes,
            'unit': 'minutes',
            'source': provider,
            'syncVersion': 1,
          },
        )
        .toList();
  }

  /// Calendar-day key (local time) as YYYY-MM-DD, matching the weight sync.
  String _dayKey(DateTime time) {
    return DateTime(
      time.year,
      time.month,
      time.day,
    ).toIso8601String().substring(0, 10);
  }
}

void _defaultScheduleWhenIdle(Future<void> Function() task) {
  SchedulerBinding.instance.scheduleTask(
    () => unawaited(task()),
    Priority.idle,
    debugLabel: 'health sync',
  );
}

Future<void> _defaultYieldToUi() => SchedulerBinding.instance.endOfFrame;

class _SyncContext {
  const _SyncContext({
    required this.provider,
    required this.now,
    required this.start,
    required this.end,
  });

  final String provider;
  final DateTime now;
  final DateTime start;
  final DateTime end;
}

class _PreparedSync {
  const _PreparedSync({
    required this.provider,
    required this.now,
    required this.samples,
  });

  final String provider;
  final DateTime now;
  final List<HealthMetricSample> samples;
}

class _PreparedRecoverySync {
  const _PreparedRecoverySync({
    required this.provider,
    required this.now,
    required this.samples,
    required this.grantedRecoverySignals,
  });

  final String provider;
  final DateTime now;
  final List<HealthMetricSample> samples;

  /// The recovery signal-group keys (see
  /// [HealthPlatformSource.recoverySignalGroups]) that are supported on this
  /// platform AND granted, e.g. {'hrv_rmssd', 'resting_heart_rate',
  /// 'sleep_duration'} on Android where SDNN is unsupported.
  final Set<String> grantedRecoverySignals;
}
