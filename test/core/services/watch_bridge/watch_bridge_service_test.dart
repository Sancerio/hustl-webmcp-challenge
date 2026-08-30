import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_command.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_handler.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';

class _MockPreferencesService extends Mock implements PreferencesService {}

class _MockRestTimerService extends Mock implements RestTimerService {}

class _MockWatchBridgeHandler extends Mock implements WatchBridgeHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('com.hustl.app/watch_bridge');
  const eventsChannel = MethodChannel('com.hustl.app/watch_bridge/events');
  const eventCodec = StandardMethodCodec();

  setUpAll(() {
    registerFallbackValue(
      const WatchCommand(id: 'fallback', type: WatchCommandType.restStart),
    );
  });

  Future<void> drainMicrotasks() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await GetIt.instance.reset();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, null);
    debugDefaultTargetPlatformOverride = null;
    await GetIt.instance.reset();
  });

  test('dispose allows the bridge to initialize again', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final ticks = StreamController<int>.broadcast();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(ticks.close);
    addTearDown(statuses.close);

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.timerStream).thenAnswer((_) => ticks.stream);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer(
      (_) async => <String, dynamic>{
        'v': 1,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'sessionId': 's1',
      },
    );

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);

    final updates = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'updateState') {
            updates.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);

    await service.init();
    await drainMicrotasks();
    expect(updates, hasLength(1));

    await service.dispose();
    updates.clear();

    await service.init();
    await drainMicrotasks();
    expect(updates, hasLength(1));
  });

  test('refreshEnabled restarts without duplicate status listeners', () async {
    var enabled = true;
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final ticks = StreamController<int>.broadcast();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(ticks.close);
    addTearDown(statuses.close);

    when(
      () => prefs.getWatchCompanionEnabled(),
    ).thenAnswer((_) async => enabled);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.timerStream).thenAnswer((_) => ticks.stream);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer(
      (_) async => <String, dynamic>{
        'v': 1,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'sessionId': 's1',
      },
    );

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);

    final updates = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'updateState') {
            updates.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);

    await service.init();
    await drainMicrotasks();

    enabled = false;
    await service.refreshEnabled();
    updates.clear();
    statuses.add(TimerStatus.running);
    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(updates, isEmpty);

    enabled = true;
    await service.refreshEnabled();
    await drainMicrotasks();
    updates.clear();

    ticks.add(2);
    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(updates, isEmpty);

    statuses.add(TimerStatus.running);
    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(updates, hasLength(1));

    await service.refreshEnabled();
    updates.clear();
    statuses.add(TimerStatus.paused);
    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(updates, hasLength(1));
  });

  test('publish requests coalesce while an update is in flight', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(statuses.close);
    final firstPayload = Completer<Map<String, dynamic>>();
    final secondPayload = Completer<Map<String, dynamic>>();
    var buildCalls = 0;

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer((_) {
      buildCalls += 1;
      if (buildCalls == 1) return firstPayload.future;
      if (buildCalls == 2) return secondPayload.future;
      return Future.value(<String, dynamic>{
        'v': 1,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'sessionId': null,
      });
    });

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);

    final updates = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'updateState') {
            updates.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);

    await service.init();
    await drainMicrotasks();
    expect(buildCalls, 1);

    service.schedulePublish();
    service.schedulePublish();
    statuses.add(TimerStatus.running);
    await drainMicrotasks();
    expect(buildCalls, 1);

    firstPayload.complete(<String, dynamic>{
      'v': 1,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'sessionId': 's1',
    });
    await drainMicrotasks();
    expect(buildCalls, 2);
    expect(updates, hasLength(1));

    secondPayload.complete(<String, dynamic>{
      'v': 1,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'sessionId': 's1',
    });
    await drainMicrotasks();
    expect(buildCalls, 2);
    expect(updates, hasLength(2));
  });

  test(
    'identical idle payloads are not republished just for timestamp churn',
    () async {
      final prefs = _MockPreferencesService();
      final restTimer = _MockRestTimerService();
      final handler = _MockWatchBridgeHandler();
      final statuses = StreamController<TimerStatus>.broadcast();
      addTearDown(statuses.close);

      when(
        () => prefs.getWatchCompanionEnabled(),
      ).thenAnswer((_) async => true);
      when(
        () => prefs.getWatchCompanionDebugOverride(),
      ).thenAnswer((_) async => null);
      when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
      when(() => handler.buildStatePayload()).thenAnswer(
        (_) async => <String, dynamic>{
          'v': 1,
          'ts': DateTime.now().millisecondsSinceEpoch,
          'sessionId': null,
          'rest': {
            'status': 'idle',
            'active': false,
            'ts': DateTime.now().millisecondsSinceEpoch,
            'remainingSec': 0,
            'elapsedSec': 0,
          },
        },
      );

      GetIt.instance.registerSingleton<RestTimerService>(restTimer);

      final updates = <Map<String, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'updateState') {
              updates.add(Map<String, dynamic>.from(call.arguments as Map));
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(eventsChannel, (_) async => null);

      final service = WatchBridgeService(handler: handler, preferences: prefs);
      addTearDown(service.dispose);

      await service.init();
      await drainMicrotasks();
      expect(updates, hasLength(1));

      await service.publishNow();
      await service.publishNow();
      await drainMicrotasks();
      expect(updates, hasLength(1));
    },
  );

  test('passive connected time does not poll active workout state', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(statuses.close);
    var builds = 0;

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer((_) async {
      builds++;
      return <String, dynamic>{
        'v': 1,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'sessionId': 'active-session',
      };
    });

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);
    await service.init();
    await drainMicrotasks();
    expect(builds, 1);

    // The removed implementation rebuilt this active-session payload at five
    // seconds even though the user and Watch were idle between set entries.
    await Future<void>.delayed(const Duration(milliseconds: 5200));
    expect(builds, 1);
  });

  test('each recording start retry sends a distinct command', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(statuses.close);

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer((_) async => null);

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);
    final commands = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'sendCommand') {
            commands.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);
    await service.init();

    await service.requestStartRecording(sessionId: 'active-session');
    await service.requestStartRecording(sessionId: 'active-session');

    expect(commands, hasLength(2));
    expect(
      commands.map((command) => command['type']),
      everyElement('health_recording_start_request'),
    );
    expect(
      commands.map((command) => command['sessionId']),
      everyElement('active-session'),
    );
    expect(commands[0]['id'], isNotEmpty);
    expect(commands[1]['id'], isNotEmpty);
    expect(commands[0]['id'], isNot(commands[1]['id']));
    expect(commands[1]['ts'] as int, greaterThan(commands[0]['ts'] as int));
  });

  test('native activation requests one fresh state snapshot', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(statuses.close);
    var builds = 0;

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer((_) async {
      builds++;
      return <String, dynamic>{
        'v': 1,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'sessionId': 'active-session',
      };
    });

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);
    await service.init();
    await drainMicrotasks();
    expect(builds, 1);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          eventsChannel.name,
          eventCodec.encodeSuccessEnvelope(
            jsonEncode(<String, dynamic>{
              'v': 1,
              'type': 'bridge_refresh_requested',
              'reason': 'activated',
            }),
          ),
          (_) {},
        );
    await drainMicrotasks();
    expect(builds, 2);
  });

  test('startup failure stops cleanly and can be retried', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final ticks = StreamController<int>.broadcast();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(ticks.close);
    addTearDown(statuses.close);

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.timerStream).thenAnswer((_) => ticks.stream);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer(
      (_) async => <String, dynamic>{
        'v': 1,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'sessionId': null,
      },
    );

    final updates = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'updateState') {
            updates.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);

    await service.init();
    await drainMicrotasks();
    expect(service.isEnabled, isFalse);
    expect(updates, isEmpty);

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);
    await service.refreshEnabled();
    await drainMicrotasks();

    expect(service.isEnabled, isTrue);
    expect(updates, hasLength(1));
  });

  test('watch event is acked only after the handler completes', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final statuses = StreamController<TimerStatus>.broadcast();
    final handled = Completer<void>();
    addTearDown(statuses.close);

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer((_) async => null);
    when(
      () => handler.handleCommand(any(), propagateErrors: true),
    ).thenAnswer((_) => handled.future);

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);

    final acked = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'ackWatchEvent') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            acked.add(args['ackId'] as String);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);

    await service.init();
    await drainMicrotasks();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          eventsChannel.name,
          eventCodec.encodeSuccessEnvelope(
            jsonEncode(<String, dynamic>{
              '_bridgeAckId': 'ack-1',
              'v': 1,
              'id': 'cmd-1',
              'type': 'rest_start',
              'sessionId': 's1',
              'durationSec': 90,
            }),
          ),
          (_) {},
        );
    await drainMicrotasks();

    expect(acked, isEmpty);
    handled.complete();
    await drainMicrotasks();

    final command =
        verify(
              () => handler.handleCommand(captureAny(), propagateErrors: true),
            ).captured.single
            as WatchCommand;
    expect(command.id, 'cmd-1');
    expect(command.type, WatchCommandType.restStart);
    expect(acked, ['ack-1']);
  });

  test('failed watch event handling is not acked', () async {
    final prefs = _MockPreferencesService();
    final restTimer = _MockRestTimerService();
    final handler = _MockWatchBridgeHandler();
    final statuses = StreamController<TimerStatus>.broadcast();
    addTearDown(statuses.close);

    when(() => prefs.getWatchCompanionEnabled()).thenAnswer((_) async => true);
    when(
      () => prefs.getWatchCompanionDebugOverride(),
    ).thenAnswer((_) async => null);
    when(() => restTimer.statusStream).thenAnswer((_) => statuses.stream);
    when(() => handler.buildStatePayload()).thenAnswer((_) async => null);
    when(
      () => handler.handleCommand(any(), propagateErrors: true),
    ).thenAnswer((_) => Future<void>.error(Exception('boom')));

    GetIt.instance.registerSingleton<RestTimerService>(restTimer);

    final acked = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'ackWatchEvent') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            acked.add(args['ackId'] as String);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (_) async => null);

    final service = WatchBridgeService(handler: handler, preferences: prefs);
    addTearDown(service.dispose);

    await service.init();
    await drainMicrotasks();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          eventsChannel.name,
          eventCodec.encodeSuccessEnvelope(
            jsonEncode(<String, dynamic>{
              '_bridgeAckId': 'ack-failed',
              'v': 1,
              'id': 'cmd-failed',
              'type': 'rest_stop',
              'sessionId': 's1',
            }),
          ),
          (_) {},
        );
    await drainMicrotasks();

    verify(() => handler.handleCommand(any(), propagateErrors: true)).called(1);
    expect(acked, isEmpty);
  });
}
