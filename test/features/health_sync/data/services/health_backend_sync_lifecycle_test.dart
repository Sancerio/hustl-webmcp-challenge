import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/health_sync/data/datasources/hustl_backend_health_api.dart';
import 'package:hustl_app/features/health_sync/data/services/health_backend_sync_service.dart';
import 'package:hustl_app/features/health_sync/data/sources/health_platform_source.dart';

class _MockHealthPlatformSource extends Mock implements HealthPlatformSource {}

class _MockHustlBackendHealthApi extends Mock
    implements HustlBackendHealthApi {}

class _FakeTokenStorage extends Fake implements TokenStorage {
  String? accessToken = 'test-access-token';

  @override
  Future<String?> getAccessToken() async => accessToken;
}

class _LifecycleTestService extends HealthBackendSyncService {
  factory _LifecycleTestService({
    DateTime Function()? now,
    Duration resumeCooldown = Duration.zero,
    _FakeTokenStorage? tokens,
    void Function(Future<void> Function())? scheduleWhenIdle,
  }) {
    final storage = tokens ?? _FakeTokenStorage();
    return _LifecycleTestService._(
      storage,
      now: now,
      resumeCooldown: resumeCooldown,
      scheduleWhenIdle: scheduleWhenIdle ?? (task) => unawaited(task()),
    );
  }

  _LifecycleTestService._(
    this.tokens, {
    super.now,
    super.resumeCooldown = Duration.zero,
    required void Function(Future<void> Function()) scheduleWhenIdle,
  }) : super(
         platformSource: _MockHealthPlatformSource(),
         api: _MockHustlBackendHealthApi(),
         tokens: tokens,
         resumeDebounce: Duration.zero,
         scheduleWhenIdle: scheduleWhenIdle,
         yieldToUi: () async {},
       );

  final _FakeTokenStorage tokens;
  int weightCalls = 0;
  int recoveryCalls = 0;
  int observationCalls = 0;
  bool failWeight = false;
  bool uploadWeight = true;
  bool uploadRecovery = true;
  bool uploadObservations = true;
  Completer<void>? blocker;

  @override
  Future<bool> syncRecentWeights({int days = 30}) async {
    weightCalls += 1;
    if (failWeight) throw StateError('weight failed');
    await blocker?.future;
    return uploadWeight;
  }

  @override
  Future<bool> syncRecentRecoveryMetrics({int days = 30}) async {
    recoveryCalls += 1;
    return uploadRecovery;
  }

  @override
  Future<bool> syncRecentObservations({int days = 14}) async {
    observationCalls += 1;
    return uploadObservations;
  }
}

Future<void> _flushResumeTimer() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start and stop attach the lifecycle observer idempotently', () {
    final service = _LifecycleTestService();

    service.startLifecycleSync();
    service.startLifecycleSync();
    expect(service.observerAttached, isTrue);

    service.stopLifecycleSync();
    service.stopLifecycleSync();
    expect(service.observerAttached, isFalse);
  });

  test('cold-start sync runs when the scheduler becomes idle', () async {
    Future<void> Function()? scheduled;
    final service = _LifecycleTestService(
      scheduleWhenIdle: (task) => scheduled = task,
    );

    service.scheduleLaunchSync();
    expect(service.weightCalls, 0);
    expect(service.recoveryCalls, 0);
    expect(service.observationCalls, 0);

    await scheduled!();
    expect(service.weightCalls, 1);
    expect(service.recoveryCalls, 1);
    expect(service.observationCalls, 1);
  });

  test('auth rehydration cannot duplicate the queued launch pass', () async {
    Future<void> Function()? scheduled;
    var scheduledCount = 0;
    final service = _LifecycleTestService(
      scheduleWhenIdle: (task) {
        scheduledCount += 1;
        scheduled = task;
      },
    );

    service.scheduleLaunchSync();
    service.scheduleAuthenticatedSync();
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);

    expect(scheduledCount, 1);
    expect(service.weightCalls, 0);

    await scheduled!();
    expect(service.weightCalls, 1);
  });

  test('auth before bootstrap cannot queue a sync', () async {
    Future<void> Function()? scheduled;
    final service = _LifecycleTestService(
      scheduleWhenIdle: (task) => scheduled = task,
    );

    service.scheduleAuthenticatedSync();
    expect(scheduled, isNull);
    expect(service.weightCalls, 0);

    service.startLifecycleSync();
    service.scheduleLaunchSync();
    expect(service.weightCalls, 0);

    await scheduled!();
    expect(service.weightCalls, 1);
    service.stopLifecycleSync();
  });

  test('interactive auth after bootstrap still refreshes promptly', () async {
    final service = _LifecycleTestService();
    service.startLifecycleSync();

    service.scheduleAuthenticatedSync();
    await _flushResumeTimer();

    expect(service.weightCalls, 1);
    service.stopLifecycleSync();
  });

  test('stopping lifecycle sync cancels pending launch work', () async {
    Future<void> Function()? scheduled;
    final service = _LifecycleTestService(
      scheduleWhenIdle: (task) => scheduled = task,
    );

    service.scheduleLaunchSync();
    service.stopLifecycleSync();
    await scheduled!();

    expect(service.weightCalls, 0);
    expect(service.recoveryCalls, 0);
    expect(service.observationCalls, 0);
  });

  test('resume refreshes weight, recovery, and raw observations', () async {
    final service = _LifecycleTestService();

    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();

    expect(service.weightCalls, 1);
    expect(service.recoveryCalls, 1);
    expect(service.observationCalls, 1);
  });

  test('rapid resume events coalesce into one refresh', () async {
    final service = _LifecycleTestService();

    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    service.didChangeAppLifecycleState(AppLifecycleState.inactive);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();

    expect(service.weightCalls, 1);
    expect(service.recoveryCalls, 1);
    expect(service.observationCalls, 1);
  });

  test('a resume does not overlap an in-flight refresh', () async {
    final service = _LifecycleTestService()..blocker = Completer<void>();

    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();
    expect(service.isSyncingAll, isTrue);

    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();
    expect(service.weightCalls, 1);
    expect(service.recoveryCalls, 0);
    expect(service.observationCalls, 0);

    service.blocker!.complete();
    await _flushResumeTimer();
    expect(service.isSyncingAll, isFalse);
  });

  test(
    'health pipelines run serially to bound HealthKit query pressure',
    () async {
      final service = _LifecycleTestService()..blocker = Completer<void>();

      final sync = service.syncAllRecent();
      await _flushResumeTimer();

      expect(service.weightCalls, 1);
      expect(service.recoveryCalls, 0);
      expect(service.observationCalls, 0);

      service.blocker!.complete();
      await sync;

      expect(service.recoveryCalls, 1);
      expect(service.observationCalls, 1);
    },
  );

  test('one failed pipeline does not suppress the others', () async {
    final service = _LifecycleTestService()..failWeight = true;

    await service.syncAllRecent();

    expect(service.weightCalls, 1);
    expect(service.recoveryCalls, 1);
    expect(service.observationCalls, 1);
    expect(service.isSyncingAll, isFalse);
  });

  test('logged-out launch stays immediately retryable after sign-in', () async {
    final tokens = _FakeTokenStorage()..accessToken = null;
    final service = _LifecycleTestService(
      tokens: tokens,
      resumeCooldown: const Duration(minutes: 10),
    );

    await service.syncAllRecent();
    expect(service.weightCalls, 0);

    tokens.accessToken = 'authenticated-access-token';
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();

    expect(service.weightCalls, 1);
    expect(service.recoveryCalls, 1);
    expect(service.observationCalls, 1);
  });

  test('failed pipeline does not arm the resume cooldown', () async {
    final service = _LifecycleTestService(
      resumeCooldown: const Duration(minutes: 10),
    )..failWeight = true;

    await service.syncAllRecent();
    service.failWeight = false;
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();

    expect(service.weightCalls, 2);
    expect(service.recoveryCalls, 1);
    expect(service.observationCalls, 1);
  });

  test(
    'no-data pipelines remain retryable while uploaded pipelines cool down',
    () async {
      final service =
          _LifecycleTestService(resumeCooldown: const Duration(minutes: 10))
            ..uploadWeight = false
            ..uploadObservations = false;

      await service.syncAllRecent();
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _flushResumeTimer();

      expect(service.weightCalls, 2);
      expect(service.recoveryCalls, 1);
      expect(service.observationCalls, 2);
    },
  );

  test(
    'account transition clears cooldowns and invalidates in-flight state',
    () async {
      final service = _LifecycleTestService(
        resumeCooldown: const Duration(minutes: 10),
      )..blocker = Completer<void>();

      final firstSync = service.syncAllRecent();
      await _flushResumeTimer();
      service.resetSyncEligibility();
      await service.syncAllRecent();
      service.blocker!.complete();
      await firstSync;
      await _flushResumeTimer();

      expect(service.weightCalls, 2);
      // The serial pass reaches these pipelines only after the account reset,
      // so that execution is already the new account's first eligible sync.
      expect(service.recoveryCalls, 1);
      expect(service.observationCalls, 1);
    },
  );

  test('resume cooldown avoids repeated bounded raw replays', () async {
    var now = DateTime(2026, 8, 16, 12);
    final service = _LifecycleTestService(
      now: () => now,
      resumeCooldown: const Duration(minutes: 10),
    );

    await service.syncAllRecent();
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();
    expect(service.weightCalls, 1);

    now = now.add(const Duration(minutes: 11));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushResumeTimer();
    expect(service.weightCalls, 2);
    expect(service.recoveryCalls, 2);
    expect(service.observationCalls, 2);
  });
}
