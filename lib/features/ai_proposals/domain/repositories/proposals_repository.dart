import '../models/auto_logged_proposal.dart';
import '../models/food_log_proposal_result.dart';
import '../models/proposal_detail.dart';
import '../models/proposal_summary.dart';
import '../models/starter_proposal_result.dart';
import '../models/nutrition_proposal_result.dart';
import '../models/template_proposal_result.dart';

/// Result of an approve call.
class ApproveResult {
  const ApproveResult({this.templateId, this.syncVersion});

  final String? templateId;
  final int? syncVersion;
}

abstract class ProposalsRepository {
  /// List the user's pending proposals (newest first).
  Future<List<ProposalSummary>> listPending({int limit});

  /// List the user's DECIDED proposals (newest first) — the history tab.
  /// Defaults to the three terminal statuses worth showing: applied, reverted,
  /// and rejected (expired proposals are excluded).
  Future<List<ProposalSummary>> listDecided({List<String> statuses, int limit});

  /// Fetch a single proposal's full detail.
  Future<ProposalDetail> getProposal(String id);

  /// Approve a proposal, applying the write server-side. [idempotencyKey] is a
  /// stable key generated once per attempt and reused on retry. [asOfDate] is the
  /// user's LOCAL date (YYYY-MM-DD); the backend uses it to resolve a nutrition
  /// proposal's target week (ignored for template kinds).
  Future<ApproveResult> approve(
    String id, {
    required String idempotencyKey,
    String? asOfDate,
  });

  /// Reject (dismiss) a proposal with an optional reason.
  Future<void> reject(String id, {String? reason});

  /// Undo an APPLIED log proposal (food_log/workout_log): deletes exactly what was
  /// logged on approve. Idempotent server-side.
  Future<void> revert(String id);

  /// Recently auto-applied log proposals (applied by a connector without an in-app
  /// tap), newest first. [since] bounds it to applied_at after that instant so each
  /// is surfaced once.
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({DateTime? since});

  /// Generate a first-party "starter" proposal from the user's own logs (the
  /// onboarding magic moment). Returns a total [StarterProposalResult] — never
  /// throws; failures surface as [StarterProposalError].
  Future<StarterProposalResult> generateStarter();

  /// Draft a nutrition-target change through the first-party app plane. This
  /// creates or replays a PENDING proposal and never applies target values.
  Future<NutritionProposalResult> proposeNutritionTargets(
    NutritionProposalInput input,
  );

  /// Draft a food-log change through the first-party app plane. Fresh drafts
  /// stay pending; this method never approves or writes diary entries directly.
  Future<FoodLogProposalResult> proposeFoodLog(FoodLogProposalInput input);

  /// Draft a new workout template through the first-party app plane. Fresh
  /// proposals remain pending until reviewed in Hustl.
  Future<TemplateProposalResult> proposeTemplate(TemplateProposalPlan plan);

  /// Draft a full replacement for an existing workout template. This never
  /// writes the template directly.
  Future<TemplateProposalResult> proposeTemplateEdit(
    String targetTemplateId,
    DateTime baseUpdatedAt,
    TemplateProposalPlan plan,
  );
}
