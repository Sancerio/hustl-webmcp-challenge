import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/analytics_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

class _RecordingSink implements TelemetrySink {
  final List<TelemetryEvent> events = [];

  @override
  void add(TelemetryEvent event) => events.add(event);
}

class _ThrowingSink implements TelemetrySink {
  @override
  void add(TelemetryEvent event) => throw StateError('sink boom');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();
  });

  test('logEvent never throws when the sink fails', () {
    final service = AnalyticsService(preferences: prefs, sink: _ThrowingSink());
    expect(() => service.logEvent('boom', props: {'x': 1}), returnsNormally);
  });

  test('emits enabled events with a captured timestamp', () {
    final sink = _RecordingSink();
    final service = AnalyticsService(preferences: prefs, sink: sink);

    service.logEvent('welcome');

    expect(sink.events, hasLength(1));
    expect(sink.events.single.name, 'welcome');
    expect(sink.events.single.ts, greaterThan(0));
  });

  test('runtime opt-out suppresses all events (kill switch)', () async {
    final sink = _RecordingSink();
    final service = AnalyticsService(preferences: prefs, sink: sink);

    await prefs.setTelemetryOptOut(true);
    service.logEvent('a');
    service.logEvent('b', props: {'count': 1});

    expect(sink.events, isEmpty);
  });

  test('strips non-primitive and free-text props (PII-safe)', () {
    final sink = _RecordingSink();
    final service = AnalyticsService(preferences: prefs, sink: sink);

    service.logEvent(
      'e',
      props: {
        'count': 3, // kept (num)
        'ok': true, // kept (bool)
        'action': 'start', // kept (enum-like String)
        'email': 'jane@example.com', // dropped (email-ish, has @)
        'name': 'Jane Doe', // dropped (free text, has spaces)
        'note': 'typed a whole sentence', // dropped (free text)
        'payload': {'k': 'v'}, // dropped (Map)
        'tags': [1, 2], // dropped (List)
        'nothing': null, // dropped (null)
      },
    );

    final props = sink.events.single.props;
    expect(props['count'], 3);
    expect(props['ok'], true);
    expect(props['action'], 'start');
    expect(props.containsKey('email'), isFalse);
    expect(props.containsKey('name'), isFalse);
    expect(props.containsKey('note'), isFalse);
    expect(props.containsKey('payload'), isFalse);
    expect(props.containsKey('tags'), isFalse);
    expect(props.containsKey('nothing'), isFalse);
  });

  test('sanitizeProps drops an over-long token-like string', () {
    final out = AnalyticsService.sanitizeProps({
      'jwt': 'a' * 200,
      'kind': 'guestUpgrade',
    });

    expect(out.containsKey('jwt'), isFalse);
    expect(out['kind'], 'guestUpgrade');
  });

  test('install id is opaque + stable (hashed, never the raw seed)', () async {
    final service = AnalyticsService(
      preferences: prefs,
      sink: _RecordingSink(),
    );

    final hash = service.installIdHash;
    expect(hash, isNotEmpty);
    // Stable across reads within a process.
    expect(service.installIdHash, hash);

    // Let the fire-and-forget seed persist settle.
    await Future<void>.delayed(Duration.zero);
    final seed = prefs.telemetryInstallId;
    expect(seed, isNotNull);
    // We emit the hash, never the stored seed.
    expect(seed, isNot(hash));
  });
}
