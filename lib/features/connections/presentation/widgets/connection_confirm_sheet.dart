import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/widgets/sheet_grabber.dart';

/// The action a connection-confirm sheet confirms.
enum ConnectionConfirmAction { stepDown, stepUp, revoke }

/// A confirm bottom sheet for stepping a connection down to read-only or
/// disconnecting it. Mirrors `showProposalConfirmSheet` (isScrollControlled,
/// useSafeArea, `AppRadius.sheetRadius`), returning `true` on confirm.
Future<bool?> showConnectionConfirmSheet(
  BuildContext context, {
  required ConnectionConfirmAction action,
  required String clientName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (sheetContext) =>
        _ConnectionConfirmSheet(action: action, clientName: clientName),
  );
}

class _ConnectionConfirmSheet extends StatelessWidget {
  const _ConnectionConfirmSheet({
    required this.action,
    required this.clientName,
  });

  final ConnectionConfirmAction action;
  final String clientName;

  bool get _isRevoke => action == ConnectionConfirmAction.revoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // [clientName] is untrusted; render it as plain text only (Text never
    // interprets markup), and clamp it so a hostile name can't dominate the UI.
    final safeName = clientName.trim().isEmpty ? 'this app' : clientName.trim();
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
              switch (action) {
                ConnectionConfirmAction.revoke => 'Disconnect this app?',
                ConnectionConfirmAction.stepUp => 'Allow proposals?',
                ConnectionConfirmAction.stepDown => 'Limit to read-only?',
              },
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              switch (action) {
                ConnectionConfirmAction.revoke =>
                  'This disconnects "$safeName" and cancels any proposals it has '
                      'waiting for your review. It can reconnect later if you '
                      'allow it again.',
                ConnectionConfirmAction.stepUp =>
                  '"$safeName" will be able to propose new or edited workout '
                      'templates and nutrition targets. Nothing changes until you '
                      'approve each one in Hustl — it can never write on its own. '
                      'Can take up to 30 min to take effect — reconnect the app '
                      'from your AI tool to apply it right away.',
                ConnectionConfirmAction.stepDown =>
                  '"$safeName" will keep read access but can no longer propose '
                      'changes. Any proposals already waiting stay until you '
                      'review them.',
              },
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.x3),
            FilledButton(
              onPressed: () {
                Haptics.confirm();
                context.pop(true);
              },
              style: _isRevoke
                  ? FilledButton.styleFrom(
                      backgroundColor: colors.errorContainer,
                      foregroundColor: colors.onErrorContainer,
                    )
                  : null,
              child: Text(switch (action) {
                ConnectionConfirmAction.revoke => 'Disconnect',
                ConnectionConfirmAction.stepUp => 'Allow proposals',
                ConnectionConfirmAction.stepDown => 'Limit to read-only',
              }),
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
