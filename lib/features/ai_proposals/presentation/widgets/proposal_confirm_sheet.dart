import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/widgets/sheet_grabber.dart';
import '../../domain/models/proposal_summary.dart';

/// The typed result of the confirm sheet.
enum ProposalConfirmAction { approve, reject }

class ProposalConfirmResult {
  const ProposalConfirmResult(this.action, {this.reason});
  final ProposalConfirmAction action;
  final String? reason;
}

/// A confirm bottom sheet for approving or rejecting a proposal. Mirrors the
/// `save_template_sheet.dart` modal pattern (isScrollControlled, useSafeArea,
/// `AppRadius.sheetRadius`), returning a typed [ProposalConfirmResult]. The
/// approve copy adapts to [kind] (template / nutrition / food log / workout log).
Future<ProposalConfirmResult?> showProposalConfirmSheet(
  BuildContext context, {
  required ProposalConfirmAction action,
  required String templateName,
  ProposalKind kind = ProposalKind.templateCreate,
}) {
  return showModalBottomSheet<ProposalConfirmResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _ProposalConfirmSheet(
        action: action,
        templateName: templateName,
        kind: kind,
      ),
    ),
  );
}

class _ProposalConfirmSheet extends StatefulWidget {
  const _ProposalConfirmSheet({
    required this.action,
    required this.templateName,
    required this.kind,
  });

  final ProposalConfirmAction action;
  final String templateName;
  final ProposalKind kind;

  @override
  State<_ProposalConfirmSheet> createState() => _ProposalConfirmSheetState();
}

class _ProposalConfirmSheetState extends State<_ProposalConfirmSheet> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _isApprove => widget.action == ProposalConfirmAction.approve;
  bool get _isNutrition => widget.kind == ProposalKind.nutritionTargets;
  bool get _isFoodLog => widget.kind == ProposalKind.foodLog;
  bool get _isWorkoutLog => widget.kind == ProposalKind.workoutLog;
  bool get _isFoodLogEdit => widget.kind == ProposalKind.foodLogEdit;
  bool get _isFoodLogDelete => widget.kind == ProposalKind.foodLogDelete;

  String get _approveTitle {
    if (_isNutrition) return 'Apply these targets?';
    if (_isFoodLog) return 'Log this meal?';
    if (_isWorkoutLog) return 'Log this workout?';
    if (_isFoodLogEdit) return 'Update this entry?';
    if (_isFoodLogDelete) return 'Remove this entry?';
    return 'Apply this template?';
  }

  String get _approveBody {
    if (_isNutrition) {
      return 'This will set your calorie and macro targets for the week. You can '
          'adjust them afterwards.';
    }
    if (_isFoodLog) {
      return 'This logs the items to your food diary. You can undo it right after, '
          'or remove any entry from the diary.';
    }
    if (_isWorkoutLog) {
      return 'This logs the workout to your history. You can undo it right after, '
          'or edit the session later.';
    }
    if (_isFoodLogEdit) {
      return 'This updates the entry in your food diary. You can undo it right '
          'after, or edit it again from the diary.';
    }
    if (_isFoodLogDelete) {
      return 'This removes the entry from your food diary. You can undo it right '
          'after if it was a mistake.';
    }
    return 'This will apply "${widget.templateName}" to your templates. You can '
        'edit or delete it afterwards.';
  }

  String get _approveCta {
    if (_isNutrition) return 'Apply targets';
    if (_isFoodLog) return 'Log it';
    if (_isWorkoutLog) return 'Log workout';
    if (_isFoodLogEdit) return 'Apply change';
    if (_isFoodLogDelete) return 'Remove entry';
    return 'Apply template';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x3,
          AppSpacing.x2,
          AppSpacing.x3,
          AppSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetGrabber(),
            const SizedBox(height: AppSpacing.x2),
            Text(
              _isApprove ? _approveTitle : 'Dismiss this proposal?',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              _isApprove
                  ? _approveBody
                  : 'This proposal will be dismissed and won\'t apply any '
                        'changes. Your AI can propose again later.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (!_isApprove) ...[
              const SizedBox(height: AppSpacing.x2),
              TextField(
                controller: _reasonController,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.x3),
            FilledButton(
              // Dismiss is NOT destructive (it applies nothing; the AI can
              // re-propose), so it uses the default button — red is reserved for
              // genuinely destructive actions.
              onPressed: () {
                Haptics.confirm();
                context.pop(
                  ProposalConfirmResult(
                    widget.action,
                    reason: _isApprove
                        ? null
                        : _reasonController.text.trim().isEmpty
                        ? null
                        : _reasonController.text.trim(),
                  ),
                );
              },
              child: Text(_isApprove ? _approveCta : 'Dismiss'),
            ),
            const SizedBox(height: AppSpacing.x1),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
