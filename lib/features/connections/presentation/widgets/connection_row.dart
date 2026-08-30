import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../domain/models/connection.dart';
import 'brand_mark.dart';

/// A single connected-app card, in the app's flat settings idiom (surface card +
/// hairline dividers, no invented chrome): a header row (brand mark + name +
/// verified domain + an access chip), the per-kind auto-log toggles when the app
/// can propose, and the access actions — "Limit to read-only"/"Allow proposals"
/// and "Disconnect".
class ConnectionRow extends StatelessWidget {
  const ConnectionRow({
    super.key,
    required this.connection,
    required this.onStepDown,
    required this.onStepUp,
    required this.onRevoke,
    required this.onSetAutoApprove,
    this.isBusy = false,
    this.now,
  });

  final Connection connection;
  final VoidCallback onStepDown;
  final VoidCallback onStepUp;
  final VoidCallback onRevoke;

  /// Toggle auto-approve for a log kind ('food_log' / 'workout_log').
  final void Function(String kind, bool enabled) onSetAutoApprove;
  final bool isBusy;

  /// Injectable clock for deterministic "last used" formatting in tests.
  final DateTime? now;

  String _lastUsed() {
    final at = connection.lastUsedAt;
    if (at == null) return 'Not used yet';
    final reference = now ?? DateTime.now();
    final diff = reference.difference(at);
    if (diff.inMinutes < 1) return 'Used just now';
    if (diff.inMinutes < 60) return 'Used ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Used ${diff.inHours}h ago';
    if (diff.inDays < 30) return 'Used ${diff.inDays}d ago';
    return 'Used ${(diff.inDays / 30).floor()}mo ago';
  }

  // Pair a light haptic with each row action; the confirm sheet + toast are the
  // visual half of the feedback.
  void _tap(VoidCallback action) {
    Haptics.selection();
    action();
  }

  Widget _autoLogToggle(
    BuildContext context,
    String label,
    bool value,
    String kind,
  ) {
    final theme = Theme.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: isBusy
          ? null
          : (v) {
              Haptics.selection();
              onSetAutoApprove(kind, v);
            },
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        0,
        AppSpacing.x2,
        0,
      ),
      title: Text(label, style: theme.textTheme.bodyLarge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canPropose = connection.canPropose;
    // The display name is attacker-controlled; clamp + plain Text only.
    final name = connection.clientName.trim().isEmpty
        ? 'Unnamed app'
        : connection.clientName.trim();
    // The verified sign-in domain is a server-derived trust signal — safe to
    // surface as a small caption near the (untrusted) name.
    final domain = connection.verifiedDomain;
    final showAutoLog =
        connection.canProposeFoodLog || connection.canProposeWorkoutLog;

    final rows = <Widget>[
      // Header: brand mark + name/domain/last-used + access chip. A Wrap (not a
      // Row) so on a very narrow / large-text screen the chip drops to its own
      // line instead of overflowing; the identity is width-capped so a long,
      // untrusted name ellipsizes rather than pushing the chip off-screen.
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x1 + 4,
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.x1,
          runSpacing: AppSpacing.x1,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The brand is keyed ONLY off the trusted vendor, never the name.
                  BrandMark(vendor: connection.vendor),
                  const SizedBox(width: AppSpacing.x2),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (domain != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'via $domain',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _lastUsed(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // amber = can propose (elevated write capability); quiet = read-only.
            AppChip(
              label: canPropose ? 'Can propose' : 'Read-only',
              variant: AppChipVariant.status,
              color: canPropose
                  ? AppColors.accentWarningAmber
                  : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ];

    // Auto-log toggles: only for the log kinds this connection can propose.
    if (showAutoLog) {
      rows.add(const Divider(height: 1));
      if (connection.canProposeFoodLog) {
        rows.add(
          _autoLogToggle(
            context,
            'Auto-log food',
            connection.autoApproveFoodLog,
            'food_log',
          ),
        );
      }
      if (connection.canProposeWorkoutLog) {
        if (connection.canProposeFoodLog) rows.add(const Divider(height: 1));
        rows.add(
          _autoLogToggle(
            context,
            'Auto-log workouts',
            connection.autoApproveWorkoutLog,
            'workout_log',
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            0,
            AppSpacing.x2,
            AppSpacing.x1 + 2,
          ),
          child: Text(
            'Auto-logged items skip the inbox — you can undo any of them.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Actions: OverflowBar stacks them on narrow / large-text so the long
    // "Limit to read-only" label can never overflow.
    rows.add(const Divider(height: 1));
    rows.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
        child: OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.start,
          spacing: AppSpacing.x1,
          overflowSpacing: AppSpacing.x1 / 2,
          children: [
            if (canPropose)
              TextButton(
                onPressed: isBusy ? null : () => _tap(onStepDown),
                child: const Text('Limit to read-only'),
              )
            else
              TextButton(
                onPressed: isBusy ? null : () => _tap(onStepUp),
                child: const Text('Allow proposals'),
              ),
            if (isBusy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.x2),
                child: SizedBox(
                  width: AppSpacing.x3,
                  height: AppSpacing.x3,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: () => _tap(onRevoke),
                style: TextButton.styleFrom(foregroundColor: colors.error),
                child: const Text('Disconnect'),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label:
          '$name. ${canPropose ? 'Can propose changes' : 'Read-only'}. '
          '${domain != null ? 'Verified via $domain. ' : ''}'
          '${_lastUsed()}',
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.cardRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        ),
      ),
    );
  }
}
