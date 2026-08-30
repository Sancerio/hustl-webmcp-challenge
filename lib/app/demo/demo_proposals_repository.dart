import 'dart:async';

import '../../features/ai_proposals/domain/models/proposal_detail.dart';
import '../../features/ai_proposals/domain/models/food_log_proposal_result.dart';
import '../../features/ai_proposals/domain/models/food_log_revision_proposal_result.dart';
import '../../features/ai_proposals/domain/models/proposal_summary.dart';
import '../../features/ai_proposals/domain/models/proposed_exercise.dart';
import '../../features/ai_proposals/domain/models/proposed_food_log.dart';
import '../../features/ai_proposals/domain/models/proposed_food_log_revision.dart';
import '../../features/ai_proposals/domain/models/proposed_nutrition_target.dart';
import '../../features/ai_proposals/domain/models/auto_logged_proposal.dart';
import '../../features/ai_proposals/domain/models/starter_proposal_result.dart';
import '../../features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import '../../features/ai_proposals/domain/models/template_proposal_result.dart';
import '../../features/ai_proposals/domain/repositories/proposals_repository.dart';
import '../../features/ai_proposals/domain/repositories/food_log_revision_proposal_repository.dart';
import '../../features/nutrition_tracker/domain/models/food_log_entry.dart';
import '../../features/workout_templates/domain/models/workout_template.dart';
import 'demo_food_log_repository.dart';
import 'demo_nutrition_targets_repository.dart';
import 'demo_state.dart';
import 'demo_template_repository.dart';

/// Deterministic in-memory [ProposalsRepository] for demo mode.
///
/// The real repository talks to the backend app-plane (`/api/proposals`), which
/// is unreachable offline and errors in demo mode. This seeds a small, believable
/// inbox of PENDING proposals so the AI-proposals surface renders richly for
/// screenshots (spec §10):
///   1. A **nutrition-target update proposed by Claude** — the headline shot:
///      raise protein 160 → 180 g and calories 2200 → 2350 kcal (carbs balanced
///      to the new calories), with a short coach rationale.
///   2. A template tweak proposed by Codex (a fuller inbox).
///
/// The numbers line up with [DemoNutritionTargetsRepository]'s current week plan
/// (2200 / 160 / 220 / 70) so the approval screen shows clean old → new deltas.
/// Every timestamp derives from the demo [anchor] so the same day always yields
/// identical rows. Approve / reject mutate the in-memory list (so a row action
/// stays consistent on screen) but never hit the network.
class DemoProposalsRepository
    implements ProposalsRepository, FoodLogRevisionProposalRepository {
  DemoProposalsRepository({
    required DateTime anchor,
    DemoState? state,
    DemoFoodLogRepository? foodLogRepository,
    DemoNutritionTargetsRepository? nutritionTargetsRepository,
    DemoTemplateRepository? templateRepository,
  }) : _anchor = DateTime(anchor.year, anchor.month, anchor.day),
       _state = state ?? DemoState(),
       _foodLogRepository =
           foodLogRepository ?? DemoFoodLogRepository(anchor: anchor),
       _nutritionTargetsRepository =
           nutritionTargetsRepository ??
           DemoNutritionTargetsRepository(anchor: anchor),
       _templateRepository =
           templateRepository ?? DemoTemplateRepository(anchor: anchor),
       _details = _seedDetails(DateTime(anchor.year, anchor.month, anchor.day));

  final DateTime _anchor;
  final DemoState _state;
  final DemoFoodLogRepository _foodLogRepository;
  final DemoNutritionTargetsRepository _nutritionTargetsRepository;
  final DemoTemplateRepository _templateRepository;

  /// Stable proposal ids — the inbox routes to `/proposals/<id>` and the detail
  /// screen looks the id back up here.
  static const String nutritionId = 'demo-proposal-nutrition';
  static const String templateId = 'demo-proposal-template';

  /// Keyed by id so the inbox and detail views share one source of truth.
  final Map<String, ProposalDetail> _details;
  final Map<String, FoodLogProposalInput> _webMcpFoodInputs = {};
  final Map<String, Object> _webMcpFoodRevisionInputs = {};
  final Map<String, int> _webMcpFoodEntryNamespaces = {};
  final Map<String, TemplateProposalPlan> _webMcpTemplateInputs = {};
  final Map<String, String?> _webMcpTemplateTargets = {};
  final Map<String, DateTime?> _webMcpTemplateBaseVersions = {};
  final Map<String, Future<void> Function()> _revertActions = {};
  final Map<String, Future<ApproveResult>> _approveInFlight = {};
  Future<void> _templateOperationTail = Future<void>.value();
  int _webMcpProposalSequence = 0;

  Future<T> _withTemplateLock<T>(Future<T> Function() operation) async {
    final previous = _templateOperationTail;
    final release = Completer<void>();
    _templateOperationTail = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  /// Monday of the demo week — the nutrition proposal's resolved target week.
  static DateTime _weekStart(DateTime anchor) =>
      anchor.subtract(Duration(days: anchor.weekday - 1));

  static bool _matchesStatus(List<String> statuses, String status) {
    // Keep this as an explicit iteration. dart2js release builds can
    // devirtualize higher-order List membership calls against a const default
    // argument to a method that is absent on the JavaScript array.
    for (final candidate in statuses) {
      if (candidate == status) return true;
    }
    return false;
  }

  static bool _sameInstant(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == null && right == null;
    return left.isAtSameMomentAs(right);
  }

  static Map<String, ProposalDetail> _seedDetails(DateTime anchor) {
    // The nutrition proposal lands a few hours into "today"; the template tweak
    // is from yesterday afternoon — distinct, plausible "created" captions.
    final nutritionCreated = anchor.add(const Duration(hours: 8, minutes: 5));
    final templateCreated = anchor.subtract(
      const Duration(hours: 18, minutes: 40),
    );

    // Nutrition: raise protein 160 → 180 g and calories 2200 → 2350 kcal. Fat
    // holds at 70 g; carbs are balanced to the new calories
    // (2350 - 180*4 - 70*9 = 1000 kcal → 250 g), so the diff reads cleanly:
    // calories +150, protein +20, carbs +30, fat 0.
    final nutritionSummary = ProposalSummary(
      id: nutritionId,
      kind: ProposalKind.nutritionTargets,
      status: 'pending',
      templateName: 'Higher protein, slight calorie bump',
      exerciseCount: 0,
      summary: 'Proposed by Claude · +20 g protein',
      createdAt: nutritionCreated,
      expiresAt: nutritionCreated.add(const Duration(days: 7)),
    );
    final nutritionDetail = ProposalDetail(
      summary: nutritionSummary,
      description:
          'Proposed by Claude. Your protein has trended a touch low on training '
          'days — this nudges it up while keeping the cut on pace.',
      proposedExercises: const [],
      resolvedExercises: const [],
      proposedNutrition: ProposedNutritionTarget(
        caloriesTarget: 2350,
        proteinTarget: 180,
        carbsTarget: 250,
        fatTarget: 70,
        weekStart: _weekStart(anchor),
        rationale:
            'You averaged ~142 g protein over the last two weeks against a '
            '160 g target, mostly on heavier training days. Lifting protein to '
            '180 g protects lean mass through the cut, and the extra 150 kcal '
            '(carbs) fuels those sessions without stalling fat loss.',
      ),
    );

    // Template tweak from Codex: add a back-off set to the favourite push day.
    final templateSummary = ProposalSummary(
      id: templateId,
      kind: ProposalKind.templateEdit,
      status: 'pending',
      templateName: 'Chest Power',
      exerciseCount: 5,
      targetTemplateId: 'demo-template-push',
      summary: 'Proposed by Codex · adds a bench back-off set',
      createdAt: templateCreated,
      expiresAt: templateCreated.add(const Duration(days: 7)),
    );
    final templateDetail = ProposalDetail(
      summary: templateSummary,
      description:
          'Proposed by Codex. Adds one lighter back-off set on the bench to add '
          'volume without taxing your top set.',
      baseTemplateUpdatedAt: anchor.subtract(const Duration(days: 2)),
      proposedExercises: const [
        ProposedExercise(
          name: 'Barbell Bench Press',
          sets: 4,
          restTimerSeconds: 180,
          repsTarget: 6,
          weightTarget: 92.5,
          rpeTarget: 8,
          slug: 'barbell-bench-press',
        ),
        ProposedExercise(
          name: 'Incline Dumbbell Press',
          sets: 3,
          restTimerSeconds: 120,
          repsTarget: 10,
          weightTarget: 34,
          rpeTarget: 8,
          slug: 'incline-dumbbell-press',
        ),
        ProposedExercise(
          name: 'Cable Fly',
          sets: 3,
          restTimerSeconds: 90,
          repsTarget: 14,
          weightTarget: 18,
          rpeTarget: 9,
          slug: 'cable-fly',
        ),
      ],
      resolvedExercises: const [
        ResolvedExercise(
          name: 'Barbell Bench Press',
          resolvedAs: ResolvedAs.catalog,
          exerciseId: 'barbell-bench-press',
          slug: 'barbell-bench-press',
        ),
        ResolvedExercise(
          name: 'Incline Dumbbell Press',
          resolvedAs: ResolvedAs.catalog,
          exerciseId: 'incline-dumbbell-press',
          slug: 'incline-dumbbell-press',
        ),
        ResolvedExercise(
          name: 'Cable Fly',
          resolvedAs: ResolvedAs.catalog,
          exerciseId: 'cable-fly',
          slug: 'cable-fly',
        ),
      ],
    );

    return {nutritionId: nutritionDetail, templateId: templateDetail};
  }

  /// Pending summaries, newest-first (matches the backend `listPending` order).
  List<ProposalSummary> get _pending {
    final pending = _details.values
        .map((d) => d.summary)
        .where((s) => s.isPending)
        .toList();
    pending.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return pending;
  }

  @override
  Future<List<ProposalSummary>> listPending({int limit = 50}) async {
    final pending = _pending;
    return List<ProposalSummary>.unmodifiable(
      pending.length > limit ? pending.sublist(0, limit) : pending,
    );
  }

  /// Decided proposals for the History tab. Seeded rows start pending; once the
  /// demo user approves/rejects one it flips (via [_resolve]) and surfaces here,
  /// newest-decided first, so an action doesn't just vanish from Pending.
  @override
  Future<List<ProposalSummary>> listDecided({
    List<String> statuses = const ['applied', 'reverted', 'rejected'],
    int limit = 50,
  }) async {
    final decided =
        _details.values
            .map((d) => d.summary)
            .where((s) => _matchesStatus(statuses, s.status))
            .toList()
          ..sort(
            (a, b) => (b.decidedAt ?? b.createdAt).compareTo(
              a.decidedAt ?? a.createdAt,
            ),
          );
    return List<ProposalSummary>.unmodifiable(
      decided.length > limit ? decided.sublist(0, limit) : decided,
    );
  }

  @override
  Future<ProposalDetail> getProposal(String id) async {
    final detail = _details[id];
    if (detail == null) {
      throw StateError('Unknown demo proposal: $id');
    }
    return detail;
  }

  @override
  Future<ApproveResult> approve(
    String id, {
    required String idempotencyKey,
    String? asOfDate,
  }) async {
    final existing = _approveInFlight[id];
    if (existing != null) return existing;
    final operation = _approveOnce(id);
    _approveInFlight[id] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_approveInFlight[id], operation)) {
        _approveInFlight.remove(id);
      }
    }
  }

  Future<ApproveResult> _approveOnce(String id) async {
    final detail = _details[id];
    if (detail == null) throw StateError('Unknown demo proposal: $id');
    if (detail.summary.isApplied) {
      return ApproveResult(
        templateId: detail.summary.targetTemplateId,
        syncVersion: 1,
      );
    }
    if (!detail.isPending) {
      throw StateError('Demo proposal $id is already ${detail.summary.status}');
    }
    final result = await _apply(detail);
    _resolve(id, 'applied', appliedResult: result.appliedResult);
    return ApproveResult(
      templateId: result.templateId ?? detail.summary.targetTemplateId,
      syncVersion: 1,
    );
  }

  @override
  Future<void> reject(String id, {String? reason}) async {
    if (_details[id]?.isPending ?? false) _resolve(id, 'rejected');
  }

  /// Drop a proposal out of the pending set after an action so the inbox and
  /// badge stay consistent if the action is exercised on screen.
  void _resolve(
    String id,
    String status, {
    Map<String, dynamic>? appliedResult,
    bool? autoApplied,
    String? autoSource,
  }) {
    final existing = _details[id];
    if (existing == null) return;
    final s = existing.summary;
    _details[id] = ProposalDetail(
      summary: ProposalSummary(
        id: s.id,
        kind: s.kind,
        status: status,
        templateName: s.templateName,
        exerciseCount: s.exerciseCount,
        targetTemplateId: s.targetTemplateId,
        summary: s.summary,
        conflictReason: s.conflictReason,
        createdAt: s.createdAt,
        expiresAt: s.expiresAt,
        // Deterministic terminal time so History groups the row on a plausible
        // day (just after it was proposed) without a non-reproducible now().
        decidedAt: s.createdAt.add(const Duration(minutes: 5)),
        autoApplied: autoApplied ?? s.autoApplied,
        autoSource: autoSource ?? s.autoSource,
      ),
      description: existing.description,
      proposedExercises: existing.proposedExercises,
      resolvedExercises: existing.resolvedExercises,
      baseTemplateUpdatedAt: existing.baseTemplateUpdatedAt,
      appliedResult: appliedResult ?? existing.appliedResult,
      proposedNutrition: existing.proposedNutrition,
      proposedFoodLog: existing.proposedFoodLog,
      proposedWorkoutLog: existing.proposedWorkoutLog,
      proposedFoodLogRevision: existing.proposedFoodLogRevision,
    );
  }

  @override
  Future<void> revert(String id) async {
    final detail = _details[id];
    if (detail == null || detail.summary.status == 'reverted') return;
    if (!detail.summary.isApplied || !detail.summary.isLog) {
      throw StateError('Demo proposal $id cannot be reverted');
    }
    final undo = _revertActions[id];
    if (undo == null) {
      throw StateError('Demo proposal $id has no undo snapshot');
    }
    await undo();
    _resolve(id, 'reverted');
  }

  @override
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({
    DateTime? since,
  }) async {
    final logs =
        _details.values
            .map((detail) => detail.summary)
            .where(
              (summary) =>
                  summary.isApplied &&
                  summary.isFirstPartyWebAutoLog &&
                  (since == null ||
                      (summary.decidedAt?.isAfter(since) ?? false)),
            )
            .map(
              (summary) => AutoLoggedProposal(
                id: summary.id,
                kind: summary.kind,
                summary: summary.summary,
                appliedAt: summary.decidedAt,
              ),
            )
            .toList()
          ..sort(
            (a, b) =>
                (b.appliedAt ?? _anchor).compareTo(a.appliedAt ?? _anchor),
          );
    return List<AutoLoggedProposal>.unmodifiable(logs);
  }

  @override
  Future<StarterProposalResult> generateStarter() async {
    // Demo mode doesn't synthesize a starter plan; return the benign
    // "not enough data" outcome (never an error) so the magic-moment screen
    // resolves cleanly without a network call.
    return const StarterProposalNotEnoughData(
      reason: 'no_completed_workouts',
      humanMessage: 'Keep logging to unlock a starter plan.',
    );
  }

  @override
  Future<NutritionProposalResult> proposeNutritionTargets(
    NutritionProposalInput input,
  ) async {
    for (final detail in _details.values) {
      if (!detail.id.startsWith('demo-proposal-webmcp-nutrition-')) continue;
      final nutrition = detail.proposedNutrition;
      if (nutrition == null) continue;
      if (nutrition.caloriesTarget == input.caloriesTarget &&
          nutrition.proteinTarget == input.proteinTarget &&
          nutrition.carbsTarget == input.carbsTarget &&
          nutrition.fatTarget == input.fatTarget) {
        return NutritionProposalResult(
          status: detail.isPending ? 'duplicate' : detail.summary.status,
          proposalId: detail.id,
          proposal: detail,
        );
      }
    }

    _webMcpProposalSequence += 1;
    final id = 'demo-proposal-webmcp-nutrition-$_webMcpProposalSequence';
    final createdAt = _anchor.add(
      Duration(hours: 10, minutes: _webMcpProposalSequence),
    );
    final summary = ProposalSummary(
      id: id,
      kind: ProposalKind.nutritionTargets,
      status: 'pending',
      templateName: 'Nutrition target update',
      exerciseCount: 0,
      summary: 'Proposed in Hustl · ${input.caloriesTarget} kcal',
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(days: 7)),
    );
    final detail = ProposalDetail(
      summary: summary,
      description:
          input.rationale ??
          'Review these suggested targets before applying them to this week.',
      proposedExercises: const [],
      resolvedExercises: const [],
      proposedNutrition: ProposedNutritionTarget(
        caloriesTarget: input.caloriesTarget.toDouble(),
        proteinTarget: input.proteinTarget,
        carbsTarget: input.carbsTarget,
        fatTarget: input.fatTarget,
        weekStart: _weekStart(_anchor),
        rationale: input.rationale,
      ),
    );
    _details[id] = detail;
    return NutritionProposalResult(
      status: 'pending',
      proposalId: id,
      proposal: detail,
    );
  }

  @override
  Future<FoodLogProposalResult> proposeFoodLog(
    FoodLogProposalInput input,
  ) async {
    for (final entry in _webMcpFoodInputs.entries) {
      final detail = _details[entry.key];
      if (entry.value != input || detail == null) continue;
      if (detail.isPending) {
        return FoodLogProposalResult(
          status: 'duplicate',
          proposalId: entry.key,
          proposal: detail,
        );
      }
      if (detail.summary.isApplied) {
        return FoodLogProposalResult(
          status: 'applied',
          proposalId: entry.key,
          proposal: detail,
        );
      }
    }

    _webMcpProposalSequence += 1;
    final id = 'demo-proposal-webmcp-food-$_webMcpProposalSequence';
    final createdAt = _anchor.add(
      Duration(hours: 11, minutes: _webMcpProposalSequence),
    );
    final proposalSummary = ProposalSummary(
      id: id,
      kind: ProposalKind.foodLog,
      status: 'pending',
      templateName: 'Food log',
      exerciseCount: 0,
      summary:
          'Proposed in Hustl · ${input.items.length} item${input.items.length == 1 ? '' : 's'}',
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(days: 7)),
    );
    final detail = ProposalDetail(
      summary: proposalSummary,
      description: input.note ?? 'Review this food log before applying it.',
      proposedExercises: const [],
      resolvedExercises: const [],
      proposedFoodLog: ProposedFoodLog(
        date: DateTime.parse(input.date),
        note: input.note,
        items: input.items
            .map(
              (item) => ProposedFoodItem(
                foodName: item.foodName,
                servingGrams: item.servingGrams,
                calories: item.calories,
                proteinGrams: item.proteinGrams,
                carbsGrams: item.carbsGrams,
                fatGrams: item.fatGrams,
                fiberGrams: item.fiberGrams,
                sugarGrams: item.sugarGrams,
                sodiumMg: item.sodiumMg,
              ),
            )
            .toList(growable: false),
      ),
    );
    _details[id] = detail;
    _webMcpFoodInputs[id] = input;
    _webMcpFoodEntryNamespaces[id] = _webMcpProposalSequence;
    if (_state.webMcpFoodAutoLog) {
      final applied = await _apply(detail);
      _resolve(
        id,
        'applied',
        appliedResult: applied.appliedResult,
        autoApplied: true,
        autoSource: 'first_party_webmcp',
      );
      return FoodLogProposalResult(
        status: 'applied',
        proposalId: id,
        proposal: _details[id]!,
        humanMessage: 'Logged to your demo diary. Undo remains available.',
      );
    }
    return FoodLogProposalResult(
      status: 'pending',
      proposalId: id,
      proposal: detail,
    );
  }

  @override
  Future<FoodLogRevisionProposalResult> proposeFoodLogEdit(
    FoodLogEditProposalInput input,
  ) => _proposeFoodLogRevision(input, isDelete: false);

  @override
  Future<FoodLogRevisionProposalResult> proposeFoodLogDelete(
    FoodLogDeleteProposalInput input,
  ) => _proposeFoodLogRevision(input, isDelete: true);

  Future<FoodLogRevisionProposalResult> _proposeFoodLogRevision(
    Object input, {
    required bool isDelete,
  }) async {
    for (final entry in _webMcpFoodRevisionInputs.entries) {
      final detail = _details[entry.key];
      if (entry.value != input || detail == null) continue;
      return FoodLogRevisionProposalResult(
        status: detail.isPending ? 'duplicate' : detail.summary.status,
        proposalId: entry.key,
        proposal: detail,
      );
    }

    final targetEntryId = switch (input) {
      FoodLogEditProposalInput(:final targetEntryId) => targetEntryId,
      FoodLogDeleteProposalInput(:final targetEntryId) => targetEntryId,
      _ => throw ArgumentError.value(input, 'input'),
    };
    final target = _foodLogRepository.findEntry(targetEntryId);
    if (target == null) throw const FoodLogRevisionTargetUnavailable();
    _webMcpProposalSequence += 1;
    final id = 'demo-proposal-webmcp-food-revision-$_webMcpProposalSequence';
    final createdAt = _anchor.add(
      Duration(hours: 11, minutes: _webMcpProposalSequence),
    );
    final proposalSummary = ProposalSummary(
      id: id,
      kind: isDelete ? ProposalKind.foodLogDelete : ProposalKind.foodLogEdit,
      status: 'pending',
      templateName: isDelete ? 'Remove food entry' : 'Correct food entry',
      exerciseCount: 0,
      summary: isDelete
          ? 'Proposed in Hustl · remove one diary entry'
          : 'Proposed in Hustl · correct one diary entry',
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(days: 7)),
    );
    final revisionPayload = <String, Object?>{
      'targetEntryId': targetEntryId,
      'target': <String, Object?>{
        'date': target.date.toIso8601String().substring(0, 10),
        'foodName': target.foodName ?? target.food?.name,
        'servingGrams': target.servingGrams,
        'calories': target.calories,
        'proteinGrams': target.proteinGrams,
        'carbsGrams': target.carbsGrams,
        'fatGrams': target.fatGrams,
        'fiberGrams': target.fiberGrams,
        'sugarGrams': target.sugarGrams,
        'sodiumMg': target.sodiumMg,
      },
      if (input case FoodLogEditProposalInput(:final changes))
        'changes': changes.toJson(),
    };
    final detail = ProposalDetail(
      summary: proposalSummary,
      description:
          'Review this diary revision before applying it. Undo remains available.',
      proposedExercises: const [],
      resolvedExercises: const [],
      proposedFoodLogRevision: ProposedFoodLogRevision.fromJson(
        revisionPayload,
        isDelete: isDelete,
      ),
    );
    _details[id] = detail;
    _webMcpFoodRevisionInputs[id] = input;
    return FoodLogRevisionProposalResult(
      status: 'pending',
      proposalId: id,
      proposal: detail,
    );
  }

  @override
  Future<TemplateProposalResult> proposeTemplate(TemplateProposalPlan plan) =>
      _proposeTemplate(plan: plan);

  @override
  Future<TemplateProposalResult> proposeTemplateEdit(
    String targetTemplateId,
    DateTime baseUpdatedAt,
    TemplateProposalPlan plan,
  ) => _proposeTemplate(
    targetTemplateId: targetTemplateId,
    baseUpdatedAt: baseUpdatedAt,
    plan: plan,
  );

  Future<TemplateProposalResult> _proposeTemplate({
    String? targetTemplateId,
    DateTime? baseUpdatedAt,
    required TemplateProposalPlan plan,
  }) => _withTemplateLock(
    () => _proposeTemplateLocked(
      targetTemplateId: targetTemplateId,
      baseUpdatedAt: baseUpdatedAt,
      plan: plan,
    ),
  );

  Future<TemplateProposalResult> _proposeTemplateLocked({
    String? targetTemplateId,
    DateTime? baseUpdatedAt,
    required TemplateProposalPlan plan,
  }) async {
    for (final entry in _webMcpTemplateInputs.entries) {
      final detail = _details[entry.key];
      if (entry.value != plan ||
          _webMcpTemplateTargets[entry.key] != targetTemplateId ||
          !_sameInstant(
            _webMcpTemplateBaseVersions[entry.key],
            baseUpdatedAt,
          ) ||
          detail == null) {
        continue;
      }
      return TemplateProposalResult(
        status: detail.isPending ? 'duplicate' : detail.summary.status,
        proposalId: entry.key,
        proposal: detail,
      );
    }

    if (targetTemplateId != null) {
      final target = await _templateRepository.getWorkoutTemplate(
        targetTemplateId,
      );
      if (target == null ||
          baseUpdatedAt == null ||
          !target.updatedAt.isAtSameMomentAs(baseUpdatedAt)) {
        throw const TemplateProposalConflict();
      }
    }

    _webMcpProposalSequence += 1;
    final id = 'demo-proposal-webmcp-template-$_webMcpProposalSequence';
    final createdAt = _anchor.add(
      Duration(hours: 12, minutes: _webMcpProposalSequence),
    );
    final proposalSummary = ProposalSummary(
      id: id,
      kind: targetTemplateId == null
          ? ProposalKind.templateCreate
          : ProposalKind.templateEdit,
      status: 'pending',
      templateName: plan.name,
      exerciseCount: plan.exercises.length,
      targetTemplateId: targetTemplateId,
      summary:
          'Proposed in Hustl · ${plan.exercises.length} exercise${plan.exercises.length == 1 ? '' : 's'}',
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(days: 7)),
    );
    final detail = ProposalDetail(
      summary: proposalSummary,
      description: plan.description,
      proposedExercises: plan.exercises
          .map(
            (exercise) => ProposedExercise(
              name: exercise.exerciseId,
              sets: exercise.sets,
              restTimerSeconds: exercise.restTimerSeconds,
              repsTarget: exercise.repsTarget,
              weightTarget: exercise.weightTarget,
              rpeTarget: exercise.rpeTarget?.toDouble(),
              slug: exercise.slug,
              notes: exercise.notes,
            ),
          )
          .toList(growable: false),
      resolvedExercises: plan.exercises
          .map(
            (exercise) => ResolvedExercise(
              name: exercise.exerciseId,
              resolvedAs: ResolvedAs.catalog,
              exerciseId: exercise.slug ?? exercise.exerciseId,
              slug: exercise.slug,
            ),
          )
          .toList(growable: false),
      baseTemplateUpdatedAt: baseUpdatedAt,
    );
    _details[id] = detail;
    _webMcpTemplateInputs[id] = plan;
    _webMcpTemplateTargets[id] = targetTemplateId;
    _webMcpTemplateBaseVersions[id] = baseUpdatedAt;
    return TemplateProposalResult(
      status: 'pending',
      proposalId: id,
      proposal: detail,
    );
  }

  Future<({String? templateId, Map<String, dynamic>? appliedResult})> _apply(
    ProposalDetail detail,
  ) async {
    switch (detail.kind) {
      case ProposalKind.foodLog:
        return _applyFoodLog(detail);
      case ProposalKind.foodLogEdit:
      case ProposalKind.foodLogDelete:
        return _applyFoodLogRevision(detail);
      case ProposalKind.nutritionTargets:
        final proposal = detail.proposedNutrition;
        if (proposal == null) {
          throw StateError(
            'Demo nutrition proposal ${detail.id} has no payload',
          );
        }
        _nutritionTargetsRepository.applyTargets(
          calories: proposal.caloriesTarget,
          protein: proposal.proteinTarget,
          carbs: proposal.carbsTarget,
          fat: proposal.fatTarget,
        );
        return (
          templateId: null,
          appliedResult: <String, dynamic>{
            'weekStart': (proposal.weekStart ?? _weekStart(_anchor))
                .toIso8601String()
                .substring(0, 10),
          },
        );
      case ProposalKind.templateCreate:
      case ProposalKind.templateEdit:
        return _withTemplateLock(() => _applyTemplate(detail));
      case ProposalKind.workoutLog:
      case ProposalKind.unknown:
        throw StateError('Demo proposal ${detail.id} is not executable');
    }
  }

  Future<({String? templateId, Map<String, dynamic>? appliedResult})>
  _applyFoodLog(ProposalDetail detail) async {
    final proposal = detail.proposedFoodLog;
    if (proposal == null) {
      throw StateError('Demo food proposal ${detail.id} has no payload');
    }
    final day = proposal.date ?? _anchor;
    final entryNamespace = _webMcpFoodEntryNamespaces[detail.id];
    if (entryNamespace == null) {
      throw StateError(
        'Demo food proposal ${detail.id} has no entry namespace',
      );
    }
    final entries = <FoodLogEntry>[];
    for (var index = 0; index < proposal.items.length; index++) {
      final item = proposal.items[index];
      final sequence = (entryNamespace * 100 + index + 1).toString().padLeft(
        12,
        '0',
      );
      entries.add(
        FoodLogEntry(
          id: '90000000-0000-4000-8000-$sequence',
          date: DateTime(day.year, day.month, day.day),
          loggedAt: DateTime(day.year, day.month, day.day, 12, index),
          servingGrams: item.servingGrams,
          calories: item.calories,
          proteinGrams: item.proteinGrams,
          carbsGrams: item.carbsGrams,
          fatGrams: item.fatGrams,
          fiberGrams: item.fiberGrams,
          sugarGrams: item.sugarGrams,
          sodiumMg: item.sodiumMg,
          foodName: item.foodName,
          source: 'ai',
        ),
      );
    }
    await _foodLogRepository.addEntries(entries);
    final entryIds = entries.map((entry) => entry.id).toList(growable: false);
    _revertActions[detail.id] = () async {
      _foodLogRepository.removeEntries(entryIds);
    };
    return (
      templateId: null,
      appliedResult: <String, dynamic>{'foodLogEntryIds': entryIds},
    );
  }

  Future<({String? templateId, Map<String, dynamic>? appliedResult})>
  _applyFoodLogRevision(ProposalDetail detail) async {
    final input = _webMcpFoodRevisionInputs[detail.id];
    if (input == null) {
      throw StateError('Demo food revision ${detail.id} has no input');
    }
    final targetId = switch (input) {
      FoodLogEditProposalInput(:final targetEntryId) => targetEntryId,
      FoodLogDeleteProposalInput(:final targetEntryId) => targetEntryId,
      _ => throw StateError('Unsupported demo food revision input'),
    };
    final before = _foodLogRepository.findEntry(targetId);
    if (before == null) throw const FoodLogRevisionTargetUnavailable();

    if (input case FoodLogEditProposalInput(:final changes)) {
      await _foodLogRepository.updateEntry(targetId, changes.toJson());
    } else {
      await _foodLogRepository.deleteEntry(targetId);
    }
    _revertActions[detail.id] = () async {
      _foodLogRepository.restoreEntry(before);
    };
    return (
      templateId: null,
      appliedResult: <String, dynamic>{'targetEntryId': targetId},
    );
  }

  Future<({String? templateId, Map<String, dynamic>? appliedResult})>
  _applyTemplate(ProposalDetail detail) async {
    final plan = _webMcpTemplateInputs[detail.id];
    final targetId = detail.summary.targetTemplateId;
    final current = targetId == null
        ? null
        : await _templateRepository.getWorkoutTemplate(targetId);
    if (targetId != null && current == null) {
      throw const TemplateProposalConflict();
    }
    if (targetId != null) {
      final expectedVersion =
          _webMcpTemplateBaseVersions[detail.id] ??
          detail.baseTemplateUpdatedAt;
      if (expectedVersion == null ||
          !current!.updatedAt.isAtSameMomentAs(expectedVersion)) {
        throw const TemplateProposalConflict();
      }
    }

    final templateId = targetId ?? 'demo-template-webmcp-${detail.id}';
    final exercises = plan != null
        ? plan.exercises
              .map(
                (exercise) => <String, dynamic>{
                  'exerciseId': exercise.exerciseId,
                  if (exercise.slug != null) 'slug': exercise.slug,
                  'sets': exercise.sets,
                  if (exercise.repsTarget != null)
                    'repsTarget': exercise.repsTarget,
                  'restTimerSeconds': exercise.restTimerSeconds,
                  if (exercise.weightTarget != null)
                    'weightTarget': exercise.weightTarget,
                  if (exercise.rpeTarget != null)
                    'rpeTarget': exercise.rpeTarget,
                  if (exercise.notes != null) 'notes': exercise.notes,
                },
              )
              .toList(growable: false)
        : detail.proposedExercises
              .map((exercise) => exercise.toRenderMap())
              .toList(growable: false);
    final updatedAt = detail.summary.createdAt.add(const Duration(minutes: 5));
    final template = WorkoutTemplate(
      id: templateId,
      name: plan?.name ?? detail.templateName,
      description: plan?.description ?? detail.description ?? '',
      exercises: exercises,
      createdAt: current?.createdAt ?? detail.summary.createdAt,
      updatedAt: updatedAt,
    );
    if (current == null) {
      await _templateRepository.createWorkoutTemplate(template);
    } else {
      await _templateRepository.updateWorkoutTemplate(template);
    }
    return (
      templateId: templateId,
      appliedResult: <String, dynamic>{'templateId': templateId},
    );
  }

  // Exposed for the demo anchor sanity in tests / future seeds.
  DateTime get anchor => _anchor;
}
