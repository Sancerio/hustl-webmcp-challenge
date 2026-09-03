import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

import '../../../domain/models/workout_session.dart';

/// A bottom sheet that lists recent completed sessions so the user can repeat
/// ANY of them — not just the most recent. Selecting one pops the sheet against
/// the live router, then hands the session to [onSelect], which spawns a fresh
/// draft via the existing repeat path; the source history is never mutated.
class RepeatSessionPicker extends StatelessWidget {
  const RepeatSessionPicker._({required this.sessions, required this.onSelect});

  final List<WorkoutSession> sessions;
  final ValueChanged<WorkoutSession> onSelect;

  static Future<void> show(
    BuildContext context, {
    required List<WorkoutSession> sessions,
    required ValueChanged<WorkoutSession> onSelect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // Root navigator (consistent with the quick-start sheet / nav fix) so the
      // sheet never lingers on the active tab branch after a tab switch.
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) =>
          RepeatSessionPicker._(sessions: sessions, onSelect: onSelect),
    );
  }

  /// Pops the sheet against the live router, then runs [onSelect] so the repeat
  /// navigation targets a mounted context rather than the disposed sheet.
  void _select(BuildContext context, WorkoutSession session) {
    Haptics.confirm();
    final router = GoRouter.of(context);
    if (router.canPop()) router.pop();
    onSelect(session);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cap the sheet so a long history scrolls instead of filling the screen.
    final maxHeight = MediaQuery.of(context).size.height * 0.6;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x1,
                AppSpacing.x3,
                AppSpacing.x2,
              ),
              child: Text(
                'Repeat a previous workout',
                style: theme.textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x2,
                  0,
                  AppSpacing.x2,
                  AppSpacing.x3,
                ),
                itemCount: sessions.length,
                itemBuilder: (context, i) => _SessionRow(
                  session: sessions[i],
                  onTap: () => _select(context, sessions[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single selectable session: a soft dumbbell holder, the session name, and a
/// quiet "<date> · N exercises" meta line — tappable across its full width.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onTap});

  final WorkoutSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = session.exercises.length;
    final meta =
        '${DateFormat('EEE, MMM d').format(session.startTime.toLocal())} · '
        '$count ${count == 1 ? 'exercise' : 'exercises'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x1),
      child: Material(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.10),
                  ),
                  alignment: Alignment.center,
                  child: HustlIcon(
                    asset: 'assets/icons/ic_dumbbell.svg',
                    size: 22,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        session.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
