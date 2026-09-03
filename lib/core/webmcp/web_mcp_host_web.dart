import 'dart:convert';
import 'dart:js_interop';

import 'web_mcp_models.dart';

WebMcpHost createWebMcpHost() => const BrowserWebMcpHost();

@JS('hustlWebMcp')
external _HustlWebMcpBridge get _bridge;

extension type _HustlWebMcpBridge._(JSObject _) implements JSObject {
  external bool get supported;

  external JSPromise<JSString> registerTool(
    JSString definitionJson,
    JSFunction handler,
  );

  external void unregisterTool(JSString registrationId);
}

class BrowserWebMcpHost implements WebMcpHost {
  const BrowserWebMcpHost();

  @override
  bool get isSupported {
    try {
      return _bridge.supported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<WebMcpRegistration?> registerTool(WebMcpToolDefinition tool) async {
    if (!isSupported) return null;

    JSPromise<JSString> execute(JSString rawArguments) {
      return _executeSafely(tool, rawArguments.toDart).then((result) {
        return jsonEncode(result).toJS;
      }).toJS;
    }

    final callback = execute.toJS;
    try {
      final registrationId =
          (await _bridge
                  .registerTool(
                    jsonEncode(tool.toRegistrationJson()).toJS,
                    callback,
                  )
                  .toDart)
              .toDart;
      if (registrationId.isEmpty) return null;
      return _BrowserWebMcpRegistration(registrationId, callback);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> _executeSafely(
    WebMcpToolDefinition tool,
    String rawArguments,
  ) async {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is! Map) {
        return const {'status': 'invalid_request', 'code': 'invalid_arguments'};
      }
      return await tool.handler(Map<String, Object?>.from(decoded));
    } catch (_) {
      return const {'status': 'error', 'code': 'tool_execution_failed'};
    }
  }
}

class _BrowserWebMcpRegistration implements WebMcpRegistration {
  _BrowserWebMcpRegistration(this._registrationId, this._retainedCallback);

  final String _registrationId;

  // Retain the exported Dart callback for exactly as long as the browser tool.
  // ignore: unused_field
  final JSFunction _retainedCallback;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _bridge.unregisterTool(_registrationId.toJS);
    } catch (_) {
      // Browser teardown must never throw into Flutter widget disposal.
    }
  }
}
