import 'proposal_summary.dart';

/// A log proposal (food_log/workout_log) the connector AUTO-APPLIED without an
/// in-app tap. The app polls these to notify the user + offer undo. Mirrors the
/// backend `AutoLoggedProposalDTO`: `{ id, kind, summary, appliedAt }`.
class AutoLoggedProposal {
  const AutoLoggedProposal({
    required this.id,
    required this.kind,
    this.summary,
    this.appliedAt,
  });

  final String id;
  final ProposalKind kind;
  final String? summary;
  final DateTime? appliedAt;

  bool get isFood => kind == ProposalKind.foodLog;

  factory AutoLoggedProposal.fromJson(Map<String, dynamic> json) {
    final at = json['appliedAt'];
    return AutoLoggedProposal(
      id: json['id']?.toString() ?? '',
      kind: proposalKindFromString(json['kind']?.toString()),
      summary: json['summary']?.toString(),
      appliedAt: at is String && at.isNotEmpty ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }
}
