import '../models/food_log_revision_proposal_result.dart';

abstract interface class FoodLogRevisionProposalRepository {
  Future<FoodLogRevisionProposalResult> proposeFoodLogEdit(
    FoodLogEditProposalInput input,
  );

  Future<FoodLogRevisionProposalResult> proposeFoodLogDelete(
    FoodLogDeleteProposalInput input,
  );
}
