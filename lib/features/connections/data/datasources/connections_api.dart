import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/services/token_storage.dart';

/// Structured error for the connections app-plane endpoints. Mirrors
/// [ProposalsApiException] — parses the `{success:false, error:{code,message,
/// details}}` envelope.
class ConnectionsApiException implements Exception {
  ConnectionsApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => message;
}

/// Data client for the connector-management app-plane endpoints (all under the
/// user's app JWT). Copies the [ProposalsApi] shape verbatim: injected
/// [TokenStorage], `_authHeaders()` Bearer, the `{success,data,error}` envelope,
/// `ApiConfig.baseUrl` + `createHttpClient()`. 401s surface (no auto-refresh).
class ConnectionsApi {
  ConnectionsApi({http.Client? client, String? baseUrl, required this.tokens})
    : _client = client ?? createHttpClient(),
      _base = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _base;
  final TokenStorage tokens;

  Future<Map<String, String>> _authHeaders() async {
    final token = await tokens.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Never _throwApiError(
    http.Response res, {
    required String fallbackCode,
    required String fallbackMessage,
  }) {
    ConnectionsApiException? parsed;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final success = decoded['success'];
        final error = decoded['error'];
        if (success == false && error is Map) {
          final code = error['code']?.toString() ?? fallbackCode;
          final message = error['message']?.toString() ?? fallbackMessage;
          final details = error['details'];
          parsed = ConnectionsApiException(
            statusCode: res.statusCode,
            code: code,
            message: message,
            details: details,
          );
        }
      }
    } catch (_) {
      // Fall through to the fallback below.
    }

    if (parsed != null) throw parsed;
    throw ConnectionsApiException(
      statusCode: res.statusCode,
      code: fallbackCode,
      message: fallbackMessage,
    );
  }

  Map<String, dynamic> _requireDataMap(http.Response res) {
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw ConnectionsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw ConnectionsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  /// GET /api/mcp/connections → { items: [...] }
  ///
  /// Each item carries `{ clientId, clientName, scope, resource, lastUsedAt,
  /// vendor, verifiedDomain }`. The raw maps are forwarded verbatim so
  /// [Connection.fromJson] can parse the trusted server-derived `vendor` /
  /// `verifiedDomain` brand signals alongside the existing fields.
  Future<List<Map<String, dynamic>>> list() async {
    final uri = Uri.parse('$_base/api/mcp/connections');
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'list_failed',
        fallbackMessage: 'Failed to load connected apps',
      );
    }
    final data = _requireDataMap(res);
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  /// GET /api/webmcp/food-auto-log → { enabled: bool }.
  Future<bool> getWebMcpFoodAutoLog() async {
    final uri = Uri.parse('$_base/api/webmcp/food-auto-log');
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'settings_failed',
        fallbackMessage: 'We couldn\'t load Web auto-log',
      );
    }
    return _requireDataMap(res)['enabled'] == true;
  }

  /// POST /api/webmcp/food-auto-log body { enabled } → { enabled: bool }.
  Future<bool> setWebMcpFoodAutoLog(bool enabled) async {
    final uri = Uri.parse('$_base/api/webmcp/food-auto-log');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'enabled': enabled}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'settings_failed',
        fallbackMessage: 'We couldn\'t update Web auto-log',
      );
    }
    return _requireDataMap(res)['enabled'] == true;
  }

  /// POST /api/mcp/connections body { client_id } → step down to read-only →
  /// { status:'stepped_down' }
  Future<String> stepDown(String clientId) async {
    final uri = Uri.parse('$_base/api/mcp/connections');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'client_id': clientId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'step_down_failed',
        fallbackMessage: 'We couldn\'t limit this app to read-only',
      );
    }
    return _requireDataMap(res)['status']?.toString() ?? 'stepped_down';
  }

  /// POST /api/mcp/connections body { client_id, action:'step_up' } → grant the
  /// propose scope → { status:'stepped_up' }
  Future<String> stepUp(String clientId) async {
    final uri = Uri.parse('$_base/api/mcp/connections');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'client_id': clientId, 'action': 'step_up'}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'step_up_failed',
        fallbackMessage: 'We couldn\'t enable proposals for this app',
      );
    }
    return _requireDataMap(res)['status']?.toString() ?? 'stepped_up';
  }

  /// POST /api/mcp/connections body { client_id, action:'set_auto_approve',
  /// kind, enabled } → { status:'auto_approve_set' }. [kind] is 'food_log' or
  /// 'workout_log'. When enabled, that log kind from this app applies on arrival
  /// instead of waiting in the inbox (still undoable in-app).
  Future<String> setAutoApprove({
    required String clientId,
    required String kind,
    required bool enabled,
  }) async {
    final uri = Uri.parse('$_base/api/mcp/connections');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        'client_id': clientId,
        'action': 'set_auto_approve',
        'kind': kind,
        'enabled': enabled,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'set_auto_approve_failed',
        fallbackMessage: 'We couldn\'t update auto-approve for this app',
      );
    }
    return _requireDataMap(res)['status']?.toString() ?? 'auto_approve_set';
  }

  /// DELETE /api/mcp/connections body { client_id } → revoke (disconnect) →
  /// { status:'revoked' }
  Future<String> revoke(String clientId) async {
    final uri = Uri.parse('$_base/api/mcp/connections');
    final res = await _client.delete(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'client_id': clientId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'revoke_failed',
        fallbackMessage: 'We couldn\'t disconnect this app',
      );
    }
    return _requireDataMap(res)['status']?.toString() ?? 'revoked';
  }
}
