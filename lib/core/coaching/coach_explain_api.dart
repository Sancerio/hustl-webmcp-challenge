import 'dart:async';
import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../network/http_client.dart';
import '../services/token_storage.dart';

/// Shared client for the domain-agnostic "explain any number" endpoint
/// (`POST /api/coach/explain`). Any surface (nutrition Insights, training
/// balance, recovery, ...) calls [explain] with its `domain` key and a PII-free,
/// pre-rounded `facts` map; the backend stitches the on-screen numbers into one
/// short coach note.
///
/// The narrative is purely additive sugar — the deterministic on-screen output is
/// always authoritative — so EVERY failure path (network down, non-2xx, server
/// flag off, gate fail, cap reached, malformed body) degrades to `null` and the
/// caller's cards/cues stand alone. This client never throws.
class CoachExplainApi {
  CoachExplainApi({http.Client? client, String? baseUrl, TokenStorage? tokens})
    : _client = client ?? createHttpClient(),
      _base = baseUrl ?? ApiConfig.baseUrl,
      _tokens =
          tokens ??
          (GetIt.instance.isRegistered<TokenStorage>()
              ? GetIt.instance<TokenStorage>()
              : TokenStorage());

  final http.Client _client;
  final String _base;
  final TokenStorage _tokens;

  /// POST the [facts] for [domain] and return the coach note, or null when the
  /// backend has nothing to say (flag off / gated / capped) or anything errors.
  Future<String?> explain(String domain, Map<String, dynamic> facts) async {
    try {
      final token = await _tokens.getAccessToken();
      final uri = Uri.parse('$_base/api/coach/explain');
      final res = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'domain': domain, 'facts': facts}),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Additive sugar — never surface an error; degrade to no narrative.
        return null;
      }
      final decoded = jsonDecode(res.body);
      final data = decoded is Map ? decoded['data'] : null;
      final narrative = data is Map ? data['narrative'] : null;
      if (narrative is String && narrative.trim().isNotEmpty) {
        return narrative.trim();
      }
      return null;
    } catch (_) {
      // Network failure, JSON parse error, missing token — all degrade to null.
      return null;
    }
  }
}
