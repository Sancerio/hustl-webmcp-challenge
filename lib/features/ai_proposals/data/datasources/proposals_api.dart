import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/services/token_storage.dart';
import '../../domain/models/food_log_revision_proposal_result.dart';
import '../../domain/models/proposal_detail.dart';
import '../../domain/models/food_log_proposal_result.dart';
import '../../domain/models/starter_proposal_result.dart';
import '../../domain/models/nutrition_proposal_result.dart';
import '../../domain/models/template_proposal_result.dart';

/// Structured error for the proposals app-plane endpoints. Mirrors
/// [HustlBackendWorkoutHistoryApiException] — parses the
/// `{success:false, error:{code,message,details}}` envelope.
class ProposalsApiException implements Exception {
  ProposalsApiException({
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

String? _proposalUnavailableCode(String code) {
  if (code == 'pending_cap_exceeded') return code;
  if (code == 'proposal_rate_limited' || code == 'daily_quota_exceeded') {
    return 'proposal_rate_limited';
  }
  return null;
}

/// Data client for the proposal app-plane endpoints (all under the user's app
/// JWT). Copies the [HustlBackendWorkoutHistoryApi] shape verbatim: injected
/// [TokenStorage], `_authHeaders()` Bearer, the `{success,data,error}` envelope,
/// `ApiConfig.baseUrl` + `createHttpClient()`. 401s surface (no auto-refresh).
class ProposalsApi {
  ProposalsApi({http.Client? client, String? baseUrl, required this.tokens})
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
    ProposalsApiException? parsed;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final success = decoded['success'];
        final error = decoded['error'];
        if (success == false && error is Map) {
          final code = error['code']?.toString() ?? fallbackCode;
          final message = error['message']?.toString() ?? fallbackMessage;
          final details = error['details'];
          parsed = ProposalsApiException(
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
    throw ProposalsApiException(
      statusCode: res.statusCode,
      code: fallbackCode,
      message: fallbackMessage,
    );
  }

  Map<String, dynamic> _requireDataMap(http.Response res) {
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw ProposalsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw ProposalsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  /// GET /api/proposals?status=pending&limit=50 → { items: [...] }
  Future<List<Map<String, dynamic>>> listPending({
    int limit = 50,
    String? cursor,
  }) async {
    final uri = Uri.parse('$_base/api/proposals').replace(
      queryParameters: {
        'status': 'pending',
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'list_failed',
        fallbackMessage: 'Failed to load proposals',
      );
    }
    final data = _requireDataMap(res);
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  /// GET /api/proposals?statuses=applied,reverted,rejected&limit=50 → { items: [...] }
  /// The history sibling of [listPending]: plural `statuses` (comma-separated)
  /// filters to the user's DECIDED proposals instead of the pending inbox.
  Future<List<Map<String, dynamic>>> listDecided({
    required List<String> statuses,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$_base/api/proposals').replace(
      queryParameters: {'statuses': statuses.join(','), 'limit': '$limit'},
    );
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'list_failed',
        fallbackMessage: 'Failed to load proposals',
      );
    }
    final data = _requireDataMap(res);
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  /// GET /api/proposals/:id → ProposalDetail
  Future<Map<String, dynamic>> getProposal(String id) async {
    final uri = Uri.parse('$_base/api/proposals/$id');
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'fetch_failed',
        fallbackMessage: 'Failed to load this proposal',
      );
    }
    return _requireDataMap(res);
  }

  /// POST /api/proposals/:id/approve → { status:'applied', templateId,
  /// syncVersion }. Conflicts surface as a [ProposalsApiException] (HTTP 409
  /// with `error.code` ∈ {base_version_stale, template_cap, proposal_expired,
  /// not_claimable}; 404 not_found).
  Future<Map<String, dynamic>> approve(
    String id, {
    required String idempotencyKey,
    String? asOfDate,
  }) async {
    final uri = Uri.parse('$_base/api/proposals/$id/approve');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      // as_of_date = the user's LOCAL date, so a nutrition proposal applies to the
      // week the user is actually in (not the server's UTC week).
      body: jsonEncode({
        'idempotency_key': idempotencyKey,
        if (asOfDate != null) 'as_of_date': asOfDate,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'approve_failed',
        fallbackMessage: 'We couldn\'t approve this proposal',
      );
    }
    return _requireDataMap(res);
  }

  /// POST /api/proposals/starter (app JWT bearer auth, NO body). Drafts a
  /// first-party "starter" proposal from the user's own logs. Collapses the
  /// whole contract into a total [StarterProposalResult] (never throws): the
  /// `{success:false,error}` envelope and transport failures map to
  /// [StarterProposalError], so the magic-moment screen can branch without a
  /// try/catch and always offer a retry / exit instead of dead-ending.
  Future<StarterProposalResult> generateStarter() async {
    final http.Response res;
    try {
      final uri = Uri.parse('$_base/api/proposals/starter');
      res = await _client.post(uri, headers: await _authHeaders());
    } catch (_) {
      return const StarterProposalError(
        code: 'network_error',
        message:
            "We couldn't reach your coach. Check your connection and "
            'try again.',
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      try {
        _throwApiError(
          res,
          fallbackCode: 'starter_failed',
          fallbackMessage: "We couldn't draft your starter plan",
        );
      } on ProposalsApiException catch (e) {
        return StarterProposalError(code: e.code, message: e.message);
      }
    }

    try {
      final data = _requireDataMap(res);
      final status = data['status']?.toString();

      if (status == 'not_enough_data') {
        final required = data['required'];
        final training = data['training'];
        return StarterProposalNotEnoughData(
          reason: data['reason']?.toString() ?? 'not_enough_data',
          humanMessage: data['humanMessage']?.toString(),
          requiredCompletedWorkouts: required is Map
              ? (required['completedWorkouts'] as num?)?.toInt()
              : null,
          requiredLoggedSets: required is Map
              ? (required['loggedSets'] as num?)?.toInt()
              : null,
          completedWorkouts: training is Map
              ? (training['completedWorkouts'] as num?)?.toInt()
              : null,
          loggedSets: training is Map
              ? (training['loggedSets'] as num?)?.toInt()
              : null,
        );
      }

      final proposalJson = data['proposal'];
      if (proposalJson is! Map) {
        return const StarterProposalError(
          code: 'invalid_response',
          message: 'Invalid response from server',
        );
      }
      final detail = ProposalDetail.fromJson(
        Map<String, dynamic>.from(proposalJson),
      );
      final proposalId = data['proposalId']?.toString() ?? detail.id;
      final humanMessage = data['humanMessage']?.toString();
      final summary = data['summary']?.toString();
      final approveDeepLink = data['approveDeepLink']?.toString();
      final training = data['training'];
      final completedWorkouts = training is Map
          ? (training['completedWorkouts'] as num?)?.toInt()
          : null;
      final loggedSets = training is Map
          ? (training['loggedSets'] as num?)?.toInt()
          : null;

      if (status == 'duplicate') {
        return StarterProposalDuplicate(
          proposal: detail,
          proposalId: proposalId,
          humanMessage: humanMessage,
          summary: summary,
          approveDeepLink: approveDeepLink,
          completedWorkouts: completedWorkouts,
          loggedSets: loggedSets,
        );
      }
      return StarterProposalCreated(
        proposal: detail,
        proposalId: proposalId,
        humanMessage: humanMessage,
        summary: summary,
        approveDeepLink: approveDeepLink,
        completedWorkouts: completedWorkouts,
        loggedSets: loggedSets,
      );
    } catch (_) {
      return const StarterProposalError(
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
  }

  /// POST /api/proposals/nutrition under the signed-in app user's JWT. The
  /// backend creates a pending proposal only; approval stays in the app UI.
  Future<NutritionProposalResult> proposeNutritionTargets(
    NutritionProposalInput input,
  ) async {
    final uri = Uri.parse('$_base/api/proposals/nutrition');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode(input.toJson()),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      try {
        _throwApiError(
          res,
          fallbackCode: 'nutrition_proposal_failed',
          fallbackMessage: 'We couldn\'t draft these nutrition targets',
        );
      } on ProposalsApiException catch (error) {
        final code = _proposalUnavailableCode(error.code);
        if (code != null) throw ProposalUnavailable(code);
        rethrow;
      }
    }
    final data = _requireDataMap(res);
    final proposalJson = data['proposal'];
    if (proposalJson is! Map) {
      throw ProposalsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final proposal = ProposalDetail.fromJson(
      Map<String, dynamic>.from(proposalJson),
    );
    return NutritionProposalResult(
      status: data['status']?.toString() ?? 'pending',
      proposalId: data['proposalId']?.toString() ?? proposal.id,
      proposal: proposal,
    );
  }

  /// POST /api/proposals/food-log under the signed-in app user's JWT. Fresh
  /// proposals stay pending by default; an applied status is either an
  /// idempotent replay or a fresh account-authorized Web auto-log.
  Future<FoodLogProposalResult> proposeFoodLog(
    FoodLogProposalInput input,
  ) async {
    final uri = Uri.parse('$_base/api/proposals/food-log');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode(input.toJson()),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      try {
        _throwApiError(
          res,
          fallbackCode: 'food_log_proposal_failed',
          fallbackMessage: 'We couldn\'t draft this food log',
        );
      } on ProposalsApiException catch (error) {
        final code = _proposalUnavailableCode(error.code);
        if (code != null) throw ProposalUnavailable(code);
        rethrow;
      }
    }
    final data = _requireDataMap(res);
    final proposalJson = data['proposal'];
    if (proposalJson is! Map) {
      throw ProposalsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final proposal = ProposalDetail.fromJson(
      Map<String, dynamic>.from(proposalJson),
    );
    return FoodLogProposalResult(
      status: data['status']?.toString() ?? 'pending',
      proposalId: data['proposalId']?.toString() ?? proposal.id,
      proposal: proposal,
      humanMessage: data['humanMessage']?.toString(),
    );
  }

  Future<FoodLogRevisionProposalResult> proposeFoodLogEdit(
    FoodLogEditProposalInput input,
  ) => _proposeFoodLogRevision('food_log_edit', input.toJson());

  Future<FoodLogRevisionProposalResult> proposeFoodLogDelete(
    FoodLogDeleteProposalInput input,
  ) => _proposeFoodLogRevision('food_log_delete', input.toJson());

  Future<FoodLogRevisionProposalResult> _proposeFoodLogRevision(
    String kind,
    Map<String, Object?> payload,
  ) async {
    final uri = Uri.parse('$_base/api/proposals/food-log-revision');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'kind': kind, 'payload': payload}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      try {
        _throwApiError(
          res,
          fallbackCode: 'food_log_revision_proposal_failed',
          fallbackMessage: 'We couldn\'t draft this food-log revision',
        );
      } on ProposalsApiException catch (error) {
        if (error.code == 'not_found') {
          throw const FoodLogRevisionTargetUnavailable();
        }
        final code = _proposalUnavailableCode(error.code);
        if (code != null) throw ProposalUnavailable(code);
        rethrow;
      }
    }
    final data = _requireDataMap(res);
    final proposalJson = data['proposal'];
    if (proposalJson is! Map) {
      throw ProposalsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final proposal = ProposalDetail.fromJson(
      Map<String, dynamic>.from(proposalJson),
    );
    return FoodLogRevisionProposalResult(
      status: data['status']?.toString() ?? 'pending',
      proposalId: data['proposalId']?.toString() ?? proposal.id,
      proposal: proposal,
      humanMessage: data['humanMessage']?.toString(),
    );
  }

  Future<TemplateProposalResult> proposeTemplate(TemplateProposalPlan plan) =>
      _proposeTemplate(kind: 'template_create', plan: plan);

  Future<TemplateProposalResult> proposeTemplateEdit(
    String targetTemplateId,
    DateTime baseUpdatedAt,
    TemplateProposalPlan plan,
  ) => _proposeTemplate(
    kind: 'template_edit',
    targetTemplateId: targetTemplateId,
    baseUpdatedAt: baseUpdatedAt,
    plan: plan,
  );

  /// POST /api/proposals/template under the signed-in app user's JWT. The
  /// shared backend proposal pipeline owns validation, idempotency, and target
  /// ownership. This client never invokes approval.
  Future<TemplateProposalResult> _proposeTemplate({
    required String kind,
    String? targetTemplateId,
    DateTime? baseUpdatedAt,
    required TemplateProposalPlan plan,
  }) async {
    final uri = Uri.parse('$_base/api/proposals/template');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        'kind': kind,
        if (targetTemplateId != null) 'targetTemplateId': targetTemplateId,
        if (baseUpdatedAt != null)
          'baseUpdatedAt': baseUpdatedAt.toUtc().toIso8601String(),
        'plan': plan.toJson(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      try {
        _throwApiError(
          res,
          fallbackCode: 'template_proposal_failed',
          fallbackMessage: 'We couldn\'t draft this workout template',
        );
      } on ProposalsApiException catch (error) {
        if (error.code == 'template_changed') {
          throw const TemplateProposalConflict();
        }
        final unavailableCode = _proposalUnavailableCode(error.code);
        if (unavailableCode != null) {
          throw TemplateProposalUnavailable(unavailableCode);
        }
        rethrow;
      }
    }
    final data = _requireDataMap(res);
    final proposalJson = data['proposal'];
    if (proposalJson is! Map) {
      throw ProposalsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final proposal = ProposalDetail.fromJson(
      Map<String, dynamic>.from(proposalJson),
    );
    return TemplateProposalResult(
      status: data['status']?.toString() ?? 'pending',
      proposalId: data['proposalId']?.toString() ?? proposal.id,
      proposal: proposal,
    );
  }

  /// GET /api/proposals/auto-logs?since=<ISO> → { items: [...] }. Recently
  /// auto-applied log proposals (food_log/workout_log) the connector applied
  /// without an in-app tap, for the notify-with-undo flow.
  Future<List<Map<String, dynamic>>> listAutoLogs({String? since}) async {
    final uri = Uri.parse('$_base/api/proposals/auto-logs').replace(
      queryParameters: {if (since != null && since.isNotEmpty) 'since': since},
    );
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'list_failed',
        fallbackMessage: 'Failed to load auto logs',
      );
    }
    final data = _requireDataMap(res);
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  /// POST /api/proposals/:id/revert → { status:'reverted', kind, date }. Undoes an
  /// APPLIED log proposal (food_log/workout_log) by deleting exactly what was
  /// logged. Idempotent server-side.
  Future<Map<String, dynamic>> revert(String id) async {
    final uri = Uri.parse('$_base/api/proposals/$id/revert');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode(const <String, dynamic>{}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'revert_failed',
        fallbackMessage: 'We couldn\'t undo this',
      );
    }
    return _requireDataMap(res);
  }

  /// POST /api/proposals/:id/reject body { reason? } → { status:'rejected' }
  Future<Map<String, dynamic>> reject(String id, {String? reason}) async {
    final uri = Uri.parse('$_base/api/proposals/$id/reject');
    final res = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'reject_failed',
        fallbackMessage: 'We couldn\'t dismiss this proposal',
      );
    }
    return _requireDataMap(res);
  }
}
