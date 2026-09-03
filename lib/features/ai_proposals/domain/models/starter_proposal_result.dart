import 'proposal_detail.dart';

/// Typed outcome of `POST /api/proposals/starter` (the onboarding "AI magic
/// moment"). The envelope is always `{success:true, data:{...}}` for the 2xx
/// cases and `{success:false, error:{...}}` for the failures — this collapses
/// both into a single total result so the magic-moment screen can switch on it
/// without try/catch and never dead-end.
///
/// Cases mirror the backend contract:
/// - [StarterProposalCreated]   — `data.status == 'pending'` (a fresh draft).
/// - [StarterProposalDuplicate] — `data.status == 'duplicate'` (an identical
///   pending draft already exists; same shape, carries the existing proposal).
/// - [StarterProposalNotEnoughData] — `data.status == 'not_enough_data'`.
/// - [StarterProposalError]     — any 4xx/5xx or transport failure.
sealed class StarterProposalResult {
  const StarterProposalResult();
}

/// Shared base for the two success cases that carry a full [ProposalDetail].
sealed class StarterProposalSucceeded extends StarterProposalResult {
  const StarterProposalSucceeded({
    required this.proposal,
    required this.proposalId,
    this.humanMessage,
    this.summary,
    this.approveDeepLink,
    this.completedWorkouts,
    this.loggedSets,
  });

  /// The full proposal, parsed from `data.proposal` (a ProposalDetailDTO).
  final ProposalDetail proposal;

  /// `data.proposalId` (falls back to [proposal.id] when absent).
  final String proposalId;

  /// `data.humanMessage` — a friendly one-liner from the coach.
  final String? humanMessage;

  /// `data.summary` — e.g. `Create "Push Day" — 4 exercises`.
  final String? summary;

  /// `data.approveDeepLink` — e.g. `hustl://proposal/<uuid>`.
  final String? approveDeepLink;

  /// `data.training.completedWorkouts` — the depth behind the draft.
  final int? completedWorkouts;

  /// `data.training.loggedSets` — the depth behind the draft.
  final int? loggedSets;

  /// True for the duplicate case (an identical pending draft already existed).
  bool get isDuplicate => this is StarterProposalDuplicate;
}

/// A fresh starter proposal was created (`status == 'pending'`).
final class StarterProposalCreated extends StarterProposalSucceeded {
  const StarterProposalCreated({
    required super.proposal,
    required super.proposalId,
    super.humanMessage,
    super.summary,
    super.approveDeepLink,
    super.completedWorkouts,
    super.loggedSets,
  });
}

/// An identical pending starter proposal already existed (`status ==
/// 'duplicate'`). The user can still approve it through the same pipeline.
final class StarterProposalDuplicate extends StarterProposalSucceeded {
  const StarterProposalDuplicate({
    required super.proposal,
    required super.proposalId,
    super.humanMessage,
    super.summary,
    super.approveDeepLink,
    super.completedWorkouts,
    super.loggedSets,
  });
}

/// The coach does not yet know enough to draft a plan (`status ==
/// 'not_enough_data'`). Never an error — the user just keeps logging.
final class StarterProposalNotEnoughData extends StarterProposalResult {
  const StarterProposalNotEnoughData({
    required this.reason,
    this.humanMessage,
    this.requiredCompletedWorkouts,
    this.requiredLoggedSets,
    this.completedWorkouts,
    this.loggedSets,
  });

  /// `data.reason` — `no_completed_workouts` | `not_enough_sets`.
  final String reason;
  final String? humanMessage;

  /// `data.required.completedWorkouts` / `data.required.loggedSets`.
  final int? requiredCompletedWorkouts;
  final int? requiredLoggedSets;

  /// `data.training.*` — how much the coach has so far.
  final int? completedWorkouts;
  final int? loggedSets;
}

/// A request that failed (auth, quota/cap, server error, or a transport
/// failure). Carries the parsed `error.code` + `error.message`.
final class StarterProposalError extends StarterProposalResult {
  const StarterProposalError({required this.code, required this.message});

  final String code;
  final String message;
}
