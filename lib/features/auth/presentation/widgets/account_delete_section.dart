import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';

import '../bloc/auth_bloc.dart';

/// Destructive "Delete account" affordance for the authenticated account body.
///
/// Tapping the row opens a confirmation dialog; on confirm it notifies
/// [onConfirmed] and dispatches [AuthDeleteAccountRequested]. The auth listener
/// resets navigation once the resulting [AuthUnauthenticated] state lands, so
/// this widget only needs to confirm intent and fire the event.
class AccountDeleteSection extends StatelessWidget {
  const AccountDeleteSection({super.key, this.onConfirmed});

  /// Invoked just before the deletion event is dispatched, so the host screen
  /// can flag that a delete-driven sign-out is in progress.
  final VoidCallback? onConfirmed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      label: 'Delete account. This permanently deletes your account and data.',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _confirmDelete(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 22, color: colors.error),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    'Delete account',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    // Capture the bloc before the async gap so we never touch a stale context.
    final authBloc = context.read<AuthBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _DeleteAccountDialog(),
    );
    if (confirmed == true) {
      onConfirmed?.call();
      authBloc.add(AuthDeleteAccountRequested());
    }
  }
}

/// Confirmation dialog for permanent account deletion. The confirm action is
/// styled with [ColorScheme.error] to signal its destructive, irreversible
/// nature.
class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Delete account?'),
      content: const Text(
        'This permanently deletes your account and all your data — workouts, '
        'nutrition, health, and photos. This can\'t be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: () => context.pop(true),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
