import '../../domain/models/auto_logged_proposal.dart';
import '../../domain/models/food_log_revision_proposal_result.dart';
import '../../domain/models/food_log_proposal_result.dart';
import '../../domain/models/proposal_detail.dart';
import '../../domain/models/proposal_summary.dart';
import '../../domain/models/starter_proposal_result.dart';
import '../../domain/models/nutrition_proposal_result.dart';
import '../../domain/models/template_proposal_result.dart';
import '../../domain/repositories/proposals_repository.dart';
import '../../domain/repositories/food_log_revision_proposal_repository.dart';
import '../datasources/proposals_api.dart';

/// [ProposalsRepository] backed by the backend app-plane endpoints via
/// [ProposalsApi]. Maps the raw envelope payloads onto domain models.
class ApiProposalsRepository
    implements ProposalsRepository, FoodLogRevisionProposalRepository {
  ApiProposalsRepository(this._api);

  final ProposalsApi _api;

  @override
  Future<List<ProposalSummary>> listPending({int limit = 50}) async {
    final items = await _api.listPending(limit: limit);
    return items.map(ProposalSummary.fromJson).toList(growable: false);
  }

  @override
  Future<List<ProposalSummary>> listDecided({
    List<String> statuses = const ['applied', 'reverted', 'rejected'],
    int limit = 50,
  }) async {
    final items = await _api.listDecided(statuses: statuses, limit: limit);
    return items.map(ProposalSummary.fromJson).toList(growable: false);
  }

  @override
  Future<ProposalDetail> getProposal(String id) async {
    final json = await _api.getProposal(id);
    return ProposalDetail.fromJson(json);
  }

  @override
  Future<ApproveResult> approve(
    String id, {
    required String idempotencyKey,
    String? asOfDate,
  }) async {
    final data = await _api.approve(
      id,
      idempotencyKey: idempotencyKey,
      asOfDate: asOfDate,
    );
    return ApproveResult(
      templateId: data['templateId']?.toString(),
      syncVersion: (data['syncVersion'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> reject(String id, {String? reason}) async {
    await _api.reject(id, reason: reason);
  }

  @override
  Future<void> revert(String id) async {
    await _api.revert(id);
  }

  @override
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({
    DateTime? since,
  }) async {
    final items = await _api.listAutoLogs(
      since: since?.toUtc().toIso8601String(),
    );
    return items.map(AutoLoggedProposal.fromJson).toList(growable: false);
  }

  @override
  Future<StarterProposalResult> generateStarter() => _api.generateStarter();

  @override
  Future<NutritionProposalResult> proposeNutritionTargets(
    NutritionProposalInput input,
  ) => _api.proposeNutritionTargets(input);

  @override
  Future<FoodLogProposalResult> proposeFoodLog(FoodLogProposalInput input) =>
      _api.proposeFoodLog(input);

  @override
  Future<FoodLogRevisionProposalResult> proposeFoodLogEdit(
    FoodLogEditProposalInput input,
  ) => _api.proposeFoodLogEdit(input);

  @override
  Future<FoodLogRevisionProposalResult> proposeFoodLogDelete(
    FoodLogDeleteProposalInput input,
  ) => _api.proposeFoodLogDelete(input);

  @override
  Future<TemplateProposalResult> proposeTemplate(TemplateProposalPlan plan) =>
      _api.proposeTemplate(plan);

  @override
  Future<TemplateProposalResult> proposeTemplateEdit(
    String targetTemplateId,
    DateTime baseUpdatedAt,
    TemplateProposalPlan plan,
  ) => _api.proposeTemplateEdit(targetTemplateId, baseUpdatedAt, plan);
}
