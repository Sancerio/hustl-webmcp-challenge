import 'dart:convert';
import 'dart:js_interop';

import 'tool.dart';

ToolHost createToolHost() => const BrowserToolHost();

@JS('hustlEvaluatorWebMcp')
external _Bridge get _bridge;

extension type _Bridge._(JSObject _) implements JSObject {
  external bool get supported;
  external JSPromise<JSString> registerTool(
    JSString definitionJson,
    JSFunction handler,
  );
  external void unregisterTool(JSString registrationId);
}

class BrowserToolHost implements ToolHost {
  const BrowserToolHost();

  @override
  bool get supported {
    try {
      return _bridge.supported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ToolRegistration?> register(ToolDefinition definition) async {
    if (!supported) return null;

    JSPromise<JSString> execute(JSString raw) => _execute(
      definition,
      raw.toDart,
    ).then((value) => jsonEncode(value).toJS).toJS;

    final callback = execute.toJS;
    try {
      final id =
          (await _bridge
                  .registerTool(
                    jsonEncode(definition.registrationJson()).toJS,
                    callback,
                  )
                  .toDart)
              .toDart;
      if (id.isEmpty) return null;
      return _BrowserRegistration(id, callback);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> _execute(
    ToolDefinition definition,
    String raw,
  ) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const {'status': 'invalid_request', 'code': 'invalid_arguments'};
      }
      return definition.handler(Map<String, Object?>.from(decoded));
    } catch (_) {
      return const {'status': 'error', 'code': 'tool_execution_failed'};
    }
  }
}

class _BrowserRegistration implements ToolRegistration {
  _BrowserRegistration(this.id, this.callback);

  final String id;
  final JSFunction callback;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _bridge.unregisterTool(id.toJS);
    } catch (_) {
      // Browser teardown is best-effort and never reaches product state.
    }
  }
}
