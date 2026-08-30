import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '../network/http_client.dart';
import 'preferences_service.dart';
import 'token_storage.dart';

/// Compile-time kill switch for ALL client telemetry. Build with
/// `--dart-define=HUSTL_TELEMETRY=false` to strip telemetry to a no-op without
/// touching call sites. Defaults on.
const bool kTelemetryEnabled = bool.fromEnvironment(
  'HUSTL_TELEMETRY',
  defaultValue: true,
);

/// A single, already PII-sanitized telemetry event.
class TelemetryEvent {
  const TelemetryEvent({
    required this.name,
    required this.ts,
    this.props = const {},
  });

  /// Stable, PII-free event identifier (e.g. `onboarding_welcome_shown`).
  final String name;

  /// Epoch milliseconds captured at `logEvent` time.
  final int ts;

  /// PII-safe primitive props (num / bool / enum-like String only).
  final Map<String, Object?> props;

  Map<String, Object?> toJson() => {
    'name': name,
    'ts': ts,
    if (props.isNotEmpty) 'props': props,
  };
}

/// Pluggable delivery sink. Implementations MUST batch + flush fire-and-forget
/// and MUST NOT throw — telemetry can never break a caller.
abstract class TelemetrySink {
  void add(TelemetryEvent event);
}

/// Drops everything. Used in tests and whenever a transport isn't wired.
class NoopTelemetrySink implements TelemetrySink {
  const NoopTelemetrySink();

  @override
  void add(TelemetryEvent event) {}
}

/// Default production sink: batches events and POSTs them fire-and-forget to
/// `/api/telemetry/events` with body
/// `{ "installId": <hash>, "sessionId": <id>, "events": [ { name, ts, props } ] }`.
/// Every failure is swallowed — the endpoint may not exist yet, and a transport
/// error must never surface to a caller.
class HttpTelemetrySink implements TelemetrySink {
  HttpTelemetrySink({
    required String Function() installId,
    required String Function() sessionId,
    http.Client? client,
    String? baseUrl,
    TokenStorage? tokens,
    Duration flushInterval = const Duration(seconds: 5),
    int maxBatch = 32,
  }) : _installId = installId,
       _sessionId = sessionId,
       _client = client ?? createHttpClient(),
       _base = baseUrl ?? ApiConfig.baseUrl,
       _tokens = tokens ?? TokenStorage(),
       _flushInterval = flushInterval,
       _maxBatch = maxBatch;

  final String Function() _installId;
  final String Function() _sessionId;
  final http.Client _client;
  final String _base;
  final TokenStorage _tokens;
  final Duration _flushInterval;
  final int _maxBatch;

  final List<TelemetryEvent> _queue = [];
  Timer? _flushTimer;

  @override
  void add(TelemetryEvent event) {
    try {
      _queue.add(event);
      if (_queue.length >= _maxBatch) {
        _flush();
      } else {
        _flushTimer ??= Timer(_flushInterval, _flush);
      }
    } catch (_) {
      // Never throw into a caller.
    }
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_queue.isEmpty) return;
    final batch = List<TelemetryEvent>.of(_queue);
    _queue.clear();
    unawaited(_post(batch));
  }

  Future<void> _post(List<TelemetryEvent> batch) async {
    try {
      final token = await _tokens.getAccessToken();
      final uri = Uri.parse('$_base/api/telemetry/events');
      final body = jsonEncode({
        'installId': _installId(),
        'sessionId': _sessionId(),
        'events': batch.map((e) => e.toJson()).toList(),
      });
      await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: body,
      );
    } catch (_) {
      // Silently ignored — telemetry is best-effort.
    }
  }
}

/// Fire-and-forget, privacy-safe client analytics.
///
/// Design invariants:
/// - **Never blocks or throws into a caller.** `logEvent` enqueues + returns;
///   every path is wrapped in try/catch.
/// - **Kill switch.** Compiled off via `--dart-define=HUSTL_TELEMETRY=false`
///   ([kTelemetryEnabled]) AND a runtime opt-out pref; either makes `logEvent`
///   a no-op.
/// - **PII-safe by construction.** Only primitives survive: num, bool, and short
///   enum-like Strings. Free text, emails (`@`), names (spaces), and tokens
///   (over-long) are dropped before anything leaves the process.
/// - **No device identifiers.** The install id is a random seed minted once and
///   stored locally; only its opaque SHA-256 hash is ever emitted.
class AnalyticsService {
  AnalyticsService({
    required PreferencesService preferences,
    TelemetrySink? sink,
    String? sessionId,
  }) : _prefs = preferences,
       _sessionId = sessionId ?? const Uuid().v4() {
    _sink =
        sink ??
        HttpTelemetrySink(
          installId: () => _installIdHash,
          sessionId: () => _sessionId,
        );
  }

  final PreferencesService _prefs;
  final String _sessionId;
  late final TelemetrySink _sink;

  String? _cachedInstallIdHash;

  /// A stable, opaque per-install hash. The raw seed is a random UUID minted
  /// once and persisted; we only ever expose its (truncated) SHA-256. Resolved
  /// lazily + cached so one seed is used for the whole process.
  String get _installIdHash => _cachedInstallIdHash ??= _resolveInstallIdHash();

  /// The per-process session id attached to every event batch.
  String get sessionId => _sessionId;

  /// Visible for tests/inspection: the opaque install hash that would be
  /// emitted. Never the raw seed.
  String get installIdHash => _installIdHash;

  String _resolveInstallIdHash() {
    var seed = _prefs.telemetryInstallId;
    if (seed == null || seed.isEmpty) {
      seed = const Uuid().v4();
      // Fire-and-forget persist; the cached hash keeps this process stable even
      // if the write loses a race.
      unawaited(_prefs.setTelemetryInstallId(seed));
    }
    return sha256.convert(utf8.encode(seed)).toString().substring(0, 16);
  }

  /// Enqueue an event for fire-and-forget delivery. No-op when telemetry is
  /// compiled off or the user has opted out. Never awaits, never throws.
  void logEvent(String name, {Map<String, Object?> props = const {}}) {
    if (!kTelemetryEnabled) return;
    try {
      if (_prefs.telemetryOptOut) return;
      final event = TelemetryEvent(
        name: name,
        ts: DateTime.now().millisecondsSinceEpoch,
        props: sanitizeProps(props),
      );
      _sink.add(event);
    } catch (_) {
      // Telemetry must never throw into a caller.
    }
  }

  /// Drop everything that isn't a privacy-safe primitive. Static + visible for
  /// tests so the PII contract can be asserted directly.
  static Map<String, Object?> sanitizeProps(Map<String, Object?> props) {
    final out = <String, Object?>{};
    props.forEach((key, value) {
      if (value is bool || value is num) {
        out[key] = value;
      } else if (value is String && _isSafeToken(value)) {
        out[key] = value;
      }
      // Everything else (free text, null, List, Map, objects) is dropped.
    });
    return out;
  }

  // Enum-like tokens only: no spaces, no `@`, bounded length. This drops free
  // text, names, emails, and tokens by construction.
  static final RegExp _safeToken = RegExp(r'^[A-Za-z0-9_.:\-]{1,40}$');

  static bool _isSafeToken(String value) => _safeToken.hasMatch(value);
}
