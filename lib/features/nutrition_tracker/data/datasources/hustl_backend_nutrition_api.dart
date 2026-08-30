import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/services/token_storage.dart';

class HustlBackendNutritionApiException implements Exception {
  HustlBackendNutritionApiException({
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

/// Raw search payload from `GET /api/nutrition/foods/search`. Carries the
/// `isStale`/`staleAgeMs` demotion flags from the backend so the UI can show
/// "showing saved results — tap to refresh" when the provider fell back to a
/// past-TTL cache.
class FoodSearchApiResult {
  const FoodSearchApiResult({
    required this.items,
    this.isStale = false,
    this.staleAgeMs,
  });

  final List<Map<String, dynamic>> items;
  final bool isStale;
  final int? staleAgeMs;
}

class HustlBackendNutritionApi {
  HustlBackendNutritionApi({
    http.Client? client,
    String? baseUrl,
    required this.tokens,
  }) : _client = client ?? createHttpClient(),
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

  /// Converts transport-level failures (no/sleeping connection, a socket torn
  /// down when iOS suspends the app mid-upload — surfaced as
  /// "ClientException: Bad file descriptor" — or a timeout) into a friendly
  /// typed error, so a backgrounded scan never leaks a raw exception string to
  /// the UI. HTTP error *responses* are untouched (handled by _throwApiError).
  Future<http.Response> _send(Future<http.Response> Function() op) async {
    try {
      return await op();
    } on http.ClientException catch (e) {
      throw HustlBackendNutritionApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message:
            'Couldn’t reach Hustl — check your connection and try again.',
        details: e.message,
      );
    } on TimeoutException catch (e) {
      throw HustlBackendNutritionApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'That took too long — check your connection and try again.',
        details: e.message,
      );
    }
  }

  Future<http.Response> _get(Uri uri) async {
    final headers = await _authHeaders();
    return _send(() => _client.get(uri, headers: headers));
  }

  Future<http.Response> _post(Uri uri, {Object? body}) async {
    final headers = await _authHeaders();
    return _send(
      () => _client.post(uri, headers: headers, body: jsonEncode(body)),
    );
  }

  Future<http.Response> _patch(Uri uri, {Object? body}) async {
    final headers = await _authHeaders();
    return _send(
      () => _client.patch(uri, headers: headers, body: jsonEncode(body)),
    );
  }

  Future<http.Response> _delete(Uri uri) async {
    final headers = await _authHeaders();
    return _send(() => _client.delete(uri, headers: headers));
  }

  String _userFriendlyErrorMessage({
    required int statusCode,
    required String code,
    required String message,
    String? cannotEstimateMessage,
  }) {
    if (statusCode == 401) return 'Please sign in to continue.';
    if (statusCode == 413 || code == 'payload_too_large') {
      return 'That photo is too large. Try taking it again.';
    }
    if (code == 'ai_scan_daily_cap') {
      return 'You have reached today’s AI scan limit. Log manually or try again tomorrow.';
    }
    if (statusCode == 429 || code == 'rate_limited') {
      return 'Too many requests. Please wait a bit and try again.';
    }
    if (statusCode == 422 || code == 'cannot_estimate') {
      // Callers (e.g. the NL "describe a meal" path) can supply copy that fits
      // their surface instead of the photo-specific guidance below.
      return cannotEstimateMessage ??
          'Couldn’t estimate macros from that photo. Try a clearer photo (full plate visible), or enter macros manually.';
    }
    if (statusCode >= 500) {
      return 'Something went wrong on our side. Please try again.';
    }
    final trimmed = message.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return 'Something went wrong. Please try again.';
  }

  Never _throwApiError(
    http.Response res, {
    required String fallbackCode,
    required String fallbackMessage,
    String? cannotEstimateMessage,
  }) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final success = decoded['success'];
        final error = decoded['error'];
        if (success == false && error is Map) {
          final code = error['code']?.toString() ?? fallbackCode;
          final message = error['message']?.toString() ?? fallbackMessage;
          final details = error['details'];
          throw HustlBackendNutritionApiException(
            statusCode: res.statusCode,
            code: code,
            message: _userFriendlyErrorMessage(
              statusCode: res.statusCode,
              code: code,
              message: message,
              cannotEstimateMessage: cannotEstimateMessage,
            ),
            details: details,
          );
        }
      }
    } on HustlBackendNutritionApiException {
      // A mapped error (with the backend code/message) must surface as-is;
      // don't let it collapse into the generic fallback below.
      rethrow;
    } catch (_) {
      // Body wasn't the expected JSON shape — fall through to the fallback.
    }

    throw HustlBackendNutritionApiException(
      statusCode: res.statusCode,
      code: fallbackCode,
      message: _userFriendlyErrorMessage(
        statusCode: res.statusCode,
        code: fallbackCode,
        message: fallbackMessage,
        cannotEstimateMessage: cannotEstimateMessage,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> searchFoods(
    String query, {
    int limit = 20,
  }) async {
    final result = await searchFoodsResult(query, limit: limit);
    return result.items;
  }

  /// Full search payload including the `isStale`/`staleAgeMs` cache-demotion
  /// flags, used by the search surface to show "showing saved results".
  Future<FoodSearchApiResult> searchFoodsResult(
    String query, {
    int limit = 20,
  }) async {
    final uri = Uri.parse(
      '$_base/api/nutrition/foods/search',
    ).replace(queryParameters: {'q': query, 'limit': '$limit'});
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_search_failed',
        fallbackMessage: 'Couldn’t search foods. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'] as Map?;
    final items = (data?['items'] as List?) ?? const [];
    final rawAge = data?['staleAgeMs'];
    final staleAgeMs = rawAge is num ? rawAge.round() : null;
    return FoodSearchApiResult(
      items: items.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      isStale: data?['isStale'] == true,
      staleAgeMs: staleAgeMs,
    );
  }

  /// `GET /api/nutrition/foods/suggestions` — the single call powering the
  /// add-food empty state, replacing the old 7×listFoodLogs fan-out. Returns the
  /// `suggestions` ("Suggested for now") and `recents` arrays as raw maps; the
  /// caller parses each via `FoodLogEntry.fromSnapshot`.
  Future<Map<String, List<Map<String, dynamic>>>> getFoodSuggestions({
    int tzOffsetMinutes = 0,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async {
    final uri = Uri.parse('$_base/api/nutrition/foods/suggestions').replace(
      queryParameters: {
        'tzOffsetMinutes': '$tzOffsetMinutes',
        'recentLimit': '$recentLimit',
        'suggestionLimit': '$suggestionLimit',
      },
    );
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_suggestions_failed',
        fallbackMessage: 'Couldn’t load suggestions. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'] as Map?;
    List<Map<String, dynamic>> list(String key) =>
        ((data?[key] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    return {'suggestions': list('suggestions'), 'recents': list('recents')};
  }

  Future<Map<String, dynamic>?> lookupBarcode(String code) async {
    final uri = Uri.parse('$_base/api/nutrition/foods/barcode/$code');
    final res = await _get(uri);
    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'barcode_lookup_failed',
        fallbackMessage: 'Couldn’t look up that barcode. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> listCustomFoods() async {
    final uri = Uri.parse('$_base/api/nutrition/foods/custom');
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'custom_foods_list_failed',
        fallbackMessage: 'Couldn’t load custom foods. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createCustomFood(
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$_base/api/nutrition/foods/custom');
    final res = await _post(uri, body: payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'custom_food_create_failed',
        fallbackMessage: 'Couldn’t save that food. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> listFoodFavorites({int limit = 10}) async {
    final uri = Uri.parse(
      '$_base/api/nutrition/favorites',
    ).replace(queryParameters: {'limit': '$limit'});
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'favorites_list_failed',
        fallbackMessage: 'Couldn’t load favorites. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<String>> listFoodFavoriteIds({int limit = 5000}) async {
    final uri = Uri.parse(
      '$_base/api/nutrition/favorites',
    ).replace(queryParameters: {'idsOnly': '1', 'limit': '$limit'});
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'favorites_list_failed',
        fallbackMessage: 'Couldn’t load favorites. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> addFoodFavorite(String foodId) async {
    final uri = Uri.parse('$_base/api/nutrition/favorites');
    final res = await _post(uri, body: {'foodId': foodId});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'favorite_add_failed',
        fallbackMessage: 'Couldn’t save favorite. Please try again.',
      );
    }
  }

  Future<void> removeFoodFavorite(String foodId) async {
    final uri = Uri.parse('$_base/api/nutrition/favorites/$foodId');
    final res = await _delete(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'favorite_remove_failed',
        fallbackMessage: 'Couldn’t remove favorite. Please try again.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> listFoodLogs(DateTime date) async {
    final day = date.toIso8601String().substring(0, 10);
    final uri = Uri.parse(
      '$_base/api/nutrition/logs',
    ).replace(queryParameters: {'date': day});
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_logs_fetch_failed',
        fallbackMessage: 'Couldn’t load your food log. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// `GET /api/nutrition/logs?start=&end=` — the range mode used by the data
  /// export. Inclusive bounds; the backend caps a window at 366 days, so
  /// callers walk longer history one window at a time.
  Future<List<Map<String, dynamic>>> listFoodLogsRange(
    DateTime start,
    DateTime end,
  ) async {
    final uri = Uri.parse('$_base/api/nutrition/logs').replace(
      queryParameters: {
        'start': start.toIso8601String().substring(0, 10),
        'end': end.toIso8601String().substring(0, 10),
      },
    );
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_logs_fetch_failed',
        fallbackMessage: 'Couldn’t load your food log. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> addFoodLogs(
    List<Map<String, dynamic>> payloads,
  ) async {
    final uri = Uri.parse('$_base/api/nutrition/logs');
    final res = await _post(uri, body: {'items': payloads});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_logs_insert_failed',
        fallbackMessage: 'Couldn’t save your food log. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> updateFoodLog(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final uri = Uri.parse('$_base/api/nutrition/logs/$id');
    final res = await _patch(uri, body: patch);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_log_update_failed',
        fallbackMessage: 'Couldn’t update that entry. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> deleteFoodLog(String id) async {
    final uri = Uri.parse('$_base/api/nutrition/logs/$id');
    final res = await _delete(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_log_delete_failed',
        fallbackMessage: 'Couldn’t delete that entry. Please try again.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> copyFoodLogs({
    required String fromDate,
    required String toDate,
    bool replaceExisting = false,
    int tzOffsetMinutes = 0,
  }) async {
    final uri = Uri.parse('$_base/api/nutrition/logs/copy');
    final res = await _post(
      uri,
      body: {
        'fromDate': fromDate,
        'toDate': toDate,
        'replaceExisting': replaceExisting,
        'tzOffsetMinutes': tzOffsetMinutes,
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'food_logs_copy_failed',
        fallbackMessage: 'Couldn’t copy entries. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listRecipes() async {
    final uri = Uri.parse('$_base/api/nutrition/recipes');
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'recipes_list_failed',
        fallbackMessage: 'Couldn’t load recipes. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['data']?['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createRecipe(
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$_base/api/nutrition/recipes');
    final res = await _post(uri, body: payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'recipe_create_failed',
        fallbackMessage: 'Couldn’t save that recipe. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> updateRecipe(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$_base/api/nutrition/recipes/$id');
    final res = await _patch(uri, body: payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'recipe_update_failed',
        fallbackMessage: 'Couldn’t update that recipe. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> deleteRecipe(String id) async {
    final uri = Uri.parse('$_base/api/nutrition/recipes/$id');
    final res = await _delete(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'recipe_delete_failed',
        fallbackMessage: 'Couldn’t delete that recipe. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> getTargets(DateTime date, {bool readOnly = false}) async {
    final day = date.toIso8601String().substring(0, 10);
    // readOnly -> peek=1: a strictly read-only lookup that never creates/carries
    // over a weekly plan (used when previewing an AI nutrition-target proposal,
    // where merely opening the review must not materialize a target row).
    final uri = Uri.parse('$_base/api/nutrition/targets').replace(
      queryParameters: {'date': day, if (readOnly) 'peek': '1'},
    );
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'targets_fetch_failed',
        fallbackMessage: 'Couldn’t load targets. Please try again.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> recalcTargets(
    DateTime date,
    Map<String, dynamic> body,
  ) async {
    final day = date.toIso8601String().substring(0, 10);
    final uri = Uri.parse('$_base/api/nutrition/targets');
    final res = await _post(
      uri,
      body: {'date': day, 'recalculate': true, ...body},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'targets_recalc_failed',
        fallbackMessage: 'Couldn’t update targets. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> patchTargets(
    String weekStart,
    Map<String, dynamic> patch,
  ) async {
    // Send the user's LOCAL today so the backend can anchor its forward-cleanup
    // guard to the user's current week (not server UTC) and correctly decide
    // whether a manual edit is for the current week (propagate) or a past week
    // (don't). DateTime.now() is local.
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$_base/api/nutrition/targets');
    final res = await _patch(
      uri,
      body: {'weekStart': weekStart, ...patch, 'date': today},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'targets_update_failed',
        fallbackMessage: 'Couldn’t update targets. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> getWeightTrend(
    DateTime start,
    DateTime end,
  ) async {
    final uri = Uri.parse('$_base/api/nutrition/weight-trend').replace(
      queryParameters: {
        'start': start.toIso8601String().substring(0, 10),
        'end': end.toIso8601String().substring(0, 10),
      },
    );
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'weight_trend_failed',
        fallbackMessage: 'Couldn’t load weight trend. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart) async {
    final uri = Uri.parse('$_base/api/nutrition/adherence').replace(
      queryParameters: {
        'weekStart': weekStart.toIso8601String().substring(0, 10),
      },
    );
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'adherence_failed',
        fallbackMessage: 'Couldn’t load adherence. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> getInsights(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async {
    final uri = Uri.parse('$_base/api/nutrition/insights').replace(
      queryParameters: {
        'start': start.toIso8601String().substring(0, 10),
        'end': end.toIso8601String().substring(0, 10),
        // Opt-in gate for the behavioral-momentum coach rec (item 4). Only sent
        // when enabled, so the backend stays silent by default.
        if (momentumOptIn) 'momentum': '1',
      },
    );
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'insights_failed',
        fallbackMessage: 'Couldn’t load insights. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  /// Lazy, off-the-critical-path fetch for the optional "Coach Explains"
  /// narrative (item 6). Returns the note string or null. Hits a SEPARATE
  /// endpoint so the main insights load never pays for it. Sends
  /// `coach_explains=1` only when the user has opted in; the backend stays silent
  /// (null) when its server flag is off, the confidence gate fails, or anything
  /// errors — the deterministic cards are always authoritative.
  Future<String?> getCoachExplains(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async {
    final uri = Uri.parse('$_base/api/nutrition/insights/coach-explains')
        .replace(
          queryParameters: {
            'start': start.toIso8601String().substring(0, 10),
            'end': end.toIso8601String().substring(0, 10),
            'coach_explains': '1',
            if (momentumOptIn) 'momentum': '1',
          },
        );
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      // Additive sugar — never surface an error; degrade to no narrative.
      return null;
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final data = decoded['data'];
    final narrative = data is Map ? data['coachNarrative'] : null;
    if (narrative is String && narrative.trim().isNotEmpty) {
      return narrative.trim();
    }
    return null;
  }

  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date) async {
    final day = date.toIso8601String().substring(0, 10);
    final uri = Uri.parse(
      '$_base/api/nutrition/check-in',
    ).replace(queryParameters: {'date': day});
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'checkin_failed',
        fallbackMessage: 'Couldn’t load check-in. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> postWeeklyCheckInAction(
    DateTime date,
    String action,
  ) async {
    final day = date.toIso8601String().substring(0, 10);
    final uri = Uri.parse('$_base/api/nutrition/check-in');
    final res = await _post(uri, body: {'date': day, 'action': action});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'checkin_update_failed',
        fallbackMessage: 'Couldn’t update check-in. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> scanMealPhoto({
    required String imageBase64,
    required String mimeType,
    String? notes,
    String? restaurant,
    String? locale,
  }) async {
    final uri = Uri.parse('$_base/api/nutrition/meal-scan');
    final payload = <String, dynamic>{
      'imageBase64': imageBase64,
      'mimeType': mimeType,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (restaurant != null && restaurant.trim().isNotEmpty)
        'restaurant': restaurant.trim(),
      if (locale != null && locale.trim().isNotEmpty) 'locale': locale.trim(),
    };
    final res = await _post(uri, body: payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'meal_scan_failed',
        fallbackMessage: 'Couldn’t scan that meal photo. Please try again.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, dynamic>> describeMeal({
    required String text,
    String? notes,
    String? restaurant,
    String? locale,
  }) async {
    final uri = Uri.parse('$_base/api/nutrition/meal-describe');
    final payload = <String, dynamic>{
      'text': text,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (restaurant != null && restaurant.trim().isNotEmpty)
        'restaurant': restaurant.trim(),
      if (locale != null && locale.trim().isNotEmpty) 'locale': locale.trim(),
    };
    final res = await _post(uri, body: payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'meal_describe_failed',
        fallbackMessage:
            'Couldn’t read that meal description. Please try again.',
        cannotEstimateMessage:
            'Couldn’t estimate macros from that description. Add a bit more detail (portions, ingredients), or enter macros manually.',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<void> postWeightMetric(DateTime date, double weightKg) async {
    final uri = Uri.parse('$_base/api/health/metrics');
    final payload = {
      'date': date.toIso8601String().substring(0, 10),
      'metricType': 'weight',
      'value': weightKg,
      'unit': 'kg',
      'source': 'self',
    };
    final res = await _post(uri, body: payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'weight_log_failed',
        fallbackMessage: 'Couldn’t log weight. Please try again.',
      );
    }
  }
}
