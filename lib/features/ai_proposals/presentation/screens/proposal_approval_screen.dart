import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../../nutrition_tracker/domain/models/nutrition_target_plan.dart';
import '../../../nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import '../../../nutrition_tracker/presentation/diary_refresh_signal.dart';
import '../../../workout_logging/data/services/workout_sync_service.dart';
import '../../../workout_templates/domain/models/workout_template.dart';
import '../../../workout_templates/domain/repositories/template_repository.dart';
import '../../domain/models/proposal_detail.dart';
import '../../domain/repositories/proposals_repository.dart';
import '../bloc/proposals_bloc.dart';
import '../bloc/proposals_event.dart';
import '../bloc/proposals_state.dart';
import '../widgets/proposal_approval_header.dart';
import '../widgets/proposal_confirm_sheet.dart';
import '../widgets/proposal_diff_view.dart';
import '../widgets/proposal_food_log_view.dart';
import '../widgets/proposal_food_log_revision_view.dart';
import '../widgets/proposal_nutrition_diff_view.dart';
import '../widgets/proposal_terminal_notice.dart';
import '../widgets/proposal_workout_log_view.dart';

/// The approval surface for a single proposal. Pushes over the shell at
/// `/proposals/:id`. Renders a create card or an edit diff, the resolved
/// snapshot, and approve/reject actions routed through [ProposalsBloc] so the
/// count, template sync, and sibling re-validation all run.
class ProposalApprovalScreen extends StatelessWidget {
  const ProposalApprovalScreen({super.key, required this.proposalId});

  final String proposalId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProposalsBloc>(
      // Load the list so the bloc can re-validate siblings after an approve.
      create: (_) =>
          GetIt.instance<ProposalsBloc>()..add(const LoadProposals()),
      child: _ApprovalView(proposalId: proposalId),
    );
  }
}

class _ApprovalView extends StatefulWidget {
  const _ApprovalView({required this.proposalId});

  final String proposalId;

  @override
  State<_ApprovalView> createState() => _ApprovalViewState();
}

class _ApprovalViewState extends State<_ApprovalView> {
  final ProposalsRepository _repository = GetIt.instance<ProposalsRepository>();
  final TemplateRepository _templateRepository =
      GetIt.instance<TemplateRepository>();
  final NutritionTargetsRepository _nutritionRepository =
      GetIt.instance<NutritionTargetsRepository>();

  ProposalDetail? _detail;
  WorkoutTemplate? _currentTemplate;
  NutritionTargetPlan? _currentPlan;
  bool _loading = true;
  String? _error;
  // A stable idempotency key per approve attempt, reused on retry.
  String? _idempotencyKey;
  // True once the user taps Approve/Reject. Gates the success toast + auto-pop
  // so merely opening a proposal that isn't in the loaded pending page (or
  // arrived via a stale notification) can't be mistaken for "Done."
  bool _actionDispatched = false;
  // Whether the dispatched action was an APPROVE (vs a dismiss). The "applied"
  // success toasts must only show on approve — a dismiss changes nothing.
  bool _approving = false;
  // True while undoing an already-applied log opened from its notification.
  bool _reverting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _repository.getProposal(widget.proposalId);
      WorkoutTemplate? current;
      NutritionTargetPlan? currentPlan;
      if (detail.isEdit && detail.targetTemplateId != null) {
        try {
          current = await _templateRepository.getWorkoutTemplate(
            detail.targetTemplateId!,
          );
        } catch (_) {
          current = null;
        }
      } else if (detail.isNutrition) {
        // Compare against THIS (local) week's target — the same week approval
        // will apply to (the backend resolves the week from the local date we
        // send on approve). readOnly: opening a review must NOT materialize a row.
        try {
          currentPlan = await _nutritionRepository.getCurrentPlan(
            DateTime.now(),
            readOnly: true,
          );
        } catch (_) {
          currentPlan = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _currentTemplate = current;
        _currentPlan = currentPlan;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// True when the edit's base snapshot is older than the current template — the
  /// authoritative check is server-side, but we disable approve to pre-empt the
  /// "approve then instant-conflict" UX. Template edits only.
  bool get _isStale {
    final detail = _detail;
    if (detail == null || !detail.isEdit) return false;
    final base = detail.baseTemplateUpdatedAt;
    final current = _currentTemplate?.updatedAt;
    if (base == null || current == null) return false;
    return base.toUtc().isBefore(current.toUtc());
  }

  /// SOFT signal for a nutrition proposal: a current week target already exists
  /// and its numbers differ from the proposed ones, so approving overwrites it.
  /// This is informational only — it never blocks approval.
  bool get _nutritionPlanChangedSoft {
    final detail = _detail;
    final n = detail?.proposedNutrition;
    final cur = _currentPlan;
    if (detail == null || !detail.isNutrition || n == null || cur == null) {
      return false;
    }
    return n.caloriesTarget.round() != cur.caloriesTarget.round() ||
        n.proteinTarget.round() != cur.proteinTarget.round() ||
        n.carbsTarget.round() != cur.carbsTarget.round() ||
        n.fatTarget.round() != cur.fatTarget.round();
  }

  Future<void> _onApprove() async {
    final detail = _detail;
    if (detail == null) return;
    final result = await showProposalConfirmSheet(
      context,
      action: ProposalConfirmAction.approve,
      templateName: detail.templateName,
      kind: detail.kind,
    );
    if (result == null || result.action != ProposalConfirmAction.approve) {
      return;
    }
    if (!mounted) return;
    _idempotencyKey ??= '${detail.id}-${DateTime.now().millisecondsSinceEpoch}';
    _actionDispatched = true;
    _approving = true;
    context.read<ProposalsBloc>().add(
      ApproveProposal(detail.id, idempotencyKey: _idempotencyKey!),
    );
  }

  Future<void> _onReject() async {
    final detail = _detail;
    if (detail == null) return;
    final result = await showProposalConfirmSheet(
      context,
      action: ProposalConfirmAction.reject,
      templateName: detail.templateName,
    );
    if (result == null || result.action != ProposalConfirmAction.reject) return;
    if (!mounted) return;
    _actionDispatched = true;
    _approving = false;
    context.read<ProposalsBloc>().add(
      RejectProposal(detail.id, reason: result.reason),
    );
  }

  /// Undo an APPLIED log proposal from the success toast. Reverts via the
  /// repository (a captured field — safe to use after this screen pops) and
  /// refreshes the affected surface. Best-effort: a failure leaves the logged
  /// data in place, which the user can still remove manually.
  Future<void> _undoLog(String id, {required bool isFood}) async {
    try {
      await _repository.revert(id);
      final getIt = GetIt.instance;
      if (isFood) {
        if (getIt.isRegistered<DiaryRefreshSignal>()) {
          getIt<DiaryRefreshSignal>().ping();
        }
      } else if (getIt.isRegistered<WorkoutSyncService>()) {
        await getIt<WorkoutSyncService>().syncNow();
      }
    } catch (_) {
      // Leave the logged data in place; it remains removable in-app.
    }
  }

  /// Undo an ALREADY-applied log opened from its notification (it's not in the
  /// pending list, so this goes straight through the repository rather than the
  /// bloc). Surfaces explicit success/failure, then pops.
  Future<void> _onUndoApplied() async {
    final detail = _detail;
    if (detail == null) return;
    setState(() => _reverting = true);
    try {
      await _repository.revert(detail.id);
      final getIt = GetIt.instance;
      if (detail.touchesFoodDiary) {
        if (getIt.isRegistered<DiaryRefreshSignal>()) {
          getIt<DiaryRefreshSignal>().ping();
        }
      } else if (getIt.isRegistered<WorkoutSyncService>()) {
        await getIt<WorkoutSyncService>().syncNow();
      }
      if (!mounted) return;
      HustlSnack.show(
        context,
        detail.isWorkoutLog
            ? 'Workout removed'
            : detail.isFoodLogRevision
            ? 'Change undone'
            : 'Removed from your diary',
        variant: HustlSnackVariant.success,
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/proposals');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _reverting = false);
      HustlSnack.show(
        context,
        "Couldn't undo — remove it manually instead",
        variant: HustlSnackVariant.error,
      );
    }
  }

  void _onStateChange(BuildContext context, ProposalsState state) {
    if (state is ProposalsLoaded) {
      // Only treat absence as success when the user actually acted here.
      // Otherwise opening a proposal that isn't in the loaded pending page would
      // be misread as "Done." and pop the screen out from under the user.
      final stillPresent = state.items.any((p) => p.id == widget.proposalId);
      final inFlight = state.inFlightIds.contains(widget.proposalId);
      if (_actionDispatched && !stillPresent && !inFlight) {
        final templateId = state.appliedTemplateId;
        // Capture the router before popping so the snack action runs on a live
        // context (this screen's context is disposed after the pop).
        final router = GoRouter.of(context);
        // "Applied" toasts only on APPROVE — a dismiss changes nothing, so it
        // falls through to the neutral "Done." message. Log kinds offer Undo
        // (the action reverts via the repository — safe after this screen pops,
        // since it captures no disposed context).
        if (_approving && _detail?.isFoodLogRevision == true) {
          final id = _detail!.id;
          final isDelete = _detail!.isFoodLogDelete;
          HustlSnack.show(
            context,
            isDelete ? 'Entry removed' : 'Diary updated',
            variant: HustlSnackVariant.success,
            actionLabel: 'Undo',
            onAction: () => _undoLog(id, isFood: true),
          );
        } else if (_approving && _detail?.isFoodLog == true) {
          final id = _detail!.id;
          HustlSnack.show(
            context,
            'Logged to your diary',
            variant: HustlSnackVariant.success,
            actionLabel: 'Undo',
            onAction: () => _undoLog(id, isFood: true),
          );
        } else if (_approving && _detail?.isWorkoutLog == true) {
          final id = _detail!.id;
          HustlSnack.show(
            context,
            'Workout logged',
            variant: HustlSnackVariant.success,
            actionLabel: 'Undo',
            onAction: () => _undoLog(id, isFood: false),
          );
        } else if (_approving && _detail?.isNutrition == true) {
          HustlSnack.show(
            context,
            'Targets applied',
            variant: HustlSnackVariant.success,
            actionLabel: 'View',
            onAction: () => router.push('/nutrition/strategy'),
          );
        } else if (_approving && templateId != null && templateId.isNotEmpty) {
          HustlSnack.show(
            context,
            'Template applied',
            variant: HustlSnackVariant.success,
            actionLabel: 'View',
            onAction: () => router.push('/templates/$templateId'),
          );
        } else {
          HustlSnack.show(context, 'Done.', variant: HustlSnackVariant.success);
        }
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/proposals');
        }
      }
    } else if (state is ProposalsFailure && _actionDispatched) {
      // The action failed (e.g. a terminal target_missing/target_changed conflict
      // on a food-log revision). Clear the dispatched flag FIRST so the
      // conflict-driven inbox refresh the bloc queues next — which drops the
      // now-terminal proposal from the pending list — is NOT misread by the
      // ProposalsLoaded branch above as a successful approval (a false "Entry
      // removed"/"Diary updated"). The user re-arms it by tapping again.
      _actionDispatched = false;
      // Only surface the failure toast when the user actually tapped
      // Approve/Reject here. A background LoadProposals/refresh failure must not
      // pop a red toast over a fully-rendered approval screen (mirrors the
      // success branch, which is likewise gated on _actionDispatched).
      HustlSnack.show(context, state.message, variant: HustlSnackVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProposalsBloc, ProposalsState>(
      listener: _onStateChange,
      child: MainScaffold(
        appBar: AppBar(title: const Text('Review proposal')),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const HustlInlineSkeleton();
    if (_error != null || _detail == null) {
      return ScreenEmptyState(
        icon: Icons.error_outline,
        title: "We couldn't load this proposal",
        message: _error ?? 'It may have expired or been withdrawn.',
        actionLabel: 'Back',
        onAction: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/proposals');
          }
        },
      );
    }
    final detail = _detail!;
    final busy = context.select<ProposalsBloc, bool>((b) {
      final s = b.state;
      return s is ProposalsLoaded && s.inFlightIds.contains(detail.id);
    });

    // An ALREADY-applied (or reverted) log — opened from its auto-approve
    // notification. Offer Undo (or show it's already undone) instead of approve.
    // Rejected/expired logs fall through to the read-only terminal view below;
    // they were never applied, so offering Undo would be misleading.
    if (detail.isLog &&
        (detail.summary.status == 'applied' ||
            detail.summary.status == 'reverted')) {
      final reverted = detail.summary.status == 'reverted';
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (detail.summary.isFirstPartyWebAutoLog) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: Text(
                  reverted
                      ? 'Hustl Web auto-log undone'
                      : 'Auto-logged by Hustl Web',
                ),
                subtitle: Text(
                  reverted
                      ? 'This entry is no longer in your food diary.'
                      : 'This entry is in your food diary. Use Undo below to remove it safely.',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
          ],
          ProposalApprovalHeader(detail: detail),
          const SizedBox(height: AppSpacing.x2),
          if (detail.isFoodLogRevision)
            ProposalFoodLogRevisionView(detail: detail, terminal: reverted)
          else if (detail.isFoodLog)
            ProposalFoodLogView(detail: detail, terminal: reverted)
          else
            ProposalWorkoutLogView(detail: detail, terminal: reverted),
          const SizedBox(height: AppSpacing.x3),
          if (reverted)
            Text(
              'This was already undone — nothing is logged.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            FilledButton.icon(
              onPressed: _reverting ? null : _onUndoApplied,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Undo'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
            const SizedBox(height: AppSpacing.x1),
          ],
          OutlinedButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/proposals');
              }
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('Close'),
          ),
        ],
      );
    }

    if (!detail.isPending) {
      return _buildTerminalProposal(context, detail);
    }

    if (detail.isFoodLogRevision) {
      final isDelete = detail.isFoodLogDelete;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ProposalApprovalHeader(detail: detail),
          const SizedBox(height: AppSpacing.x2),
          ProposalFoodLogRevisionView(detail: detail),
          const SizedBox(height: AppSpacing.x3),
          FilledButton.icon(
            onPressed: busy ? null : _onApprove,
            icon: Icon(isDelete ? Icons.delete_outline : Icons.check_rounded),
            label: Text(isDelete ? 'Remove entry' : 'Apply change'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
          const SizedBox(height: AppSpacing.x1),
          OutlinedButton(
            onPressed: busy ? null : _onReject,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('Dismiss'),
          ),
        ],
      );
    }

    if (detail.isFoodLog || detail.isWorkoutLog) {
      final isFood = detail.isFoodLog;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ProposalApprovalHeader(detail: detail),
          const SizedBox(height: AppSpacing.x2),
          if (isFood)
            ProposalFoodLogView(detail: detail)
          else
            ProposalWorkoutLogView(detail: detail),
          const SizedBox(height: AppSpacing.x3),
          FilledButton.icon(
            onPressed: busy ? null : _onApprove,
            icon: const Icon(Icons.check_rounded),
            label: Text(isFood ? 'Log it' : 'Log workout'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
          const SizedBox(height: AppSpacing.x1),
          OutlinedButton(
            onPressed: busy ? null : _onReject,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('Dismiss'),
          ),
        ],
      );
    }

    if (detail.isNutrition) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ProposalApprovalHeader(detail: detail),
          const SizedBox(height: AppSpacing.x2),
          if (_nutritionPlanChangedSoft) ...[
            const ProposalNutritionChangedNotice(),
            const SizedBox(height: AppSpacing.x2),
          ],
          ProposalNutritionDiffView(detail: detail, currentPlan: _currentPlan),
          const SizedBox(height: AppSpacing.x3),
          FilledButton.icon(
            // Soft notice never blocks: nutrition apply is always enabled.
            onPressed: busy ? null : _onApprove,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Apply targets'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
          const SizedBox(height: AppSpacing.x1),
          OutlinedButton(
            onPressed: busy ? null : _onReject,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('Dismiss'),
          ),
        ],
      );
    }

    final snapshot = ProposalDiffView.resolvedSnapshot(context, detail);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ProposalApprovalHeader(detail: detail),
        const SizedBox(height: AppSpacing.x2),
        if (_isStale) ...[
          const ProposalStaleNotice(),
          const SizedBox(height: AppSpacing.x2),
        ],
        ProposalDiffView(detail: detail, currentTemplate: _currentTemplate),
        if (snapshot != null) ...[
          const SizedBox(height: AppSpacing.x2),
          snapshot,
        ],
        const SizedBox(height: AppSpacing.x3),
        FilledButton.icon(
          onPressed: (busy || _isStale) ? null : _onApprove,
          icon: const Icon(Icons.check_rounded),
          label: Text(_isStale ? 'Needs re-propose' : 'Apply template'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
        const SizedBox(height: AppSpacing.x1),
        OutlinedButton(
          onPressed: busy ? null : _onReject,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _buildTerminalProposal(BuildContext context, ProposalDetail detail) {
    final snapshot = ProposalDiffView.resolvedSnapshot(
      context,
      detail,
      terminal: true,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ProposalApprovalHeader(detail: detail),
        const SizedBox(height: AppSpacing.x2),
        ProposalTerminalNotice(status: detail.summary.status),
        const SizedBox(height: AppSpacing.x2),
        if (detail.isFoodLogRevision)
          ProposalFoodLogRevisionView(detail: detail, terminal: true)
        else if (detail.isFoodLog)
          ProposalFoodLogView(detail: detail, terminal: true)
        else if (detail.isWorkoutLog)
          ProposalWorkoutLogView(detail: detail, terminal: true)
        else if (detail.isNutrition)
          ProposalNutritionDiffView(
            detail: detail,
            currentPlan: _currentPlan,
            terminal: true,
          )
        else ...[
          ProposalDiffView(detail: detail, currentTemplate: _currentTemplate),
          if (snapshot != null) ...[
            const SizedBox(height: AppSpacing.x2),
            snapshot,
          ],
        ],
        const SizedBox(height: AppSpacing.x3),
        OutlinedButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/proposals');
            }
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
