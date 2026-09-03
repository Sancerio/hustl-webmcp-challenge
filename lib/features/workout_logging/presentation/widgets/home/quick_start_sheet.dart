import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

/// The Train-home quick-start sheet: a premium modal that opens from the
/// extended "Start workout" FAB and offers the three ways to begin a session,
/// in priority order — repeat the last workout, start from a template, or
/// start an empty workout.
///
/// Each option pops the sheet first (capturing the GoRouter beforehand) and
/// then runs its callback, so navigation always happens against a live router
/// rather than a disposed sheet context.
class QuickStartSheet extends StatelessWidget {
  const QuickStartSheet._({
    required this.hasLastSession,
    required this.lastSessionName,
    required this.hasPreviousSessions,
    required this.onRepeatLast,
    required this.onRepeatPrevious,
    required this.onFromTemplate,
    required this.onEmpty,
  });

  /// Whether there is a last completed session to repeat. When false the
  /// "Repeat …" row is omitted entirely.
  final bool hasLastSession;

  /// Name of the last completed session, shown in the "Repeat …" row title.
  final String? lastSessionName;

  /// Whether there is more than one completed session, so a "Repeat a previous
  /// workout" picker row is worth offering beyond repeating just the last one.
  final bool hasPreviousSessions;

  final VoidCallback onRepeatLast;
  final VoidCallback onRepeatPrevious;
  final VoidCallback onFromTemplate;
  final VoidCallback onEmpty;

  /// Opens the quick-start sheet. Rows render in priority order: repeat the
  /// last session, repeat an earlier one (when [hasPreviousSessions]), start
  /// from a template, then start an empty workout.
  static Future<void> show(
    BuildContext context, {
    required bool hasLastSession,
    required String? lastSessionName,
    required bool hasPreviousSessions,
    required VoidCallback onRepeatLast,
    required VoidCallback onRepeatPrevious,
    required VoidCallback onFromTemplate,
    required VoidCallback onEmpty,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // Root navigator (consistent with the home template picker / nav fix) so
      // the sheet never lingers on the active tab branch after a tab switch.
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) => QuickStartSheet._(
        hasLastSession: hasLastSession,
        lastSessionName: lastSessionName,
        hasPreviousSessions: hasPreviousSessions,
        onRepeatLast: onRepeatLast,
        onRepeatPrevious: onRepeatPrevious,
        onFromTemplate: onFromTemplate,
        onEmpty: onEmpty,
      ),
    );
  }

  /// Pops the sheet against the live router, then runs [action] so navigation
  /// targets a mounted context rather than the disposed sheet.
  void _select(BuildContext context, VoidCallback action) {
    Haptics.confirm();
    final router = GoRouter.of(context);
    if (router.canPop()) router.pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The content is intrinsically short, but a scroll view keeps the sheet
    // overflow-safe on compact viewports (small phones, split-screen) instead
    // of clipping a row.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x1,
          AppSpacing.x2,
          AppSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
              child: Text('Start a workout', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: AppSpacing.x2),
            if (hasLastSession)
              _QuickStartRow(
                icon: 'assets/icons/ic_dumbbell.svg',
                title: 'Repeat ${lastSessionName ?? 'last workout'}',
                subtitle: 'Pick up your most recent session',
                onTap: () => _select(context, onRepeatLast),
              ),
            if (hasPreviousSessions)
              _QuickStartRow(
                icon: 'assets/icons/nav_history.svg',
                title: 'Repeat a previous workout',
                subtitle: 'Pick from your recent sessions',
                onTap: () => _select(context, onRepeatPrevious),
              ),
            _QuickStartRow(
              icon: 'assets/icons/nav_library.svg',
              title: 'From a template',
              subtitle: 'Start from one of your saved routines',
              onTap: () => _select(context, onFromTemplate),
            ),
            _QuickStartRow(
              icon: 'assets/icons/ic_add.svg',
              title: 'Empty workout',
              subtitle: 'Build a session as you go',
              onTap: () => _select(context, onEmpty),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single quick-start option: a soft glyph holder, a title with an optional
/// subtitle, and a trailing chevron — tappable across its full width.
class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

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
                    asset: icon,
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
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
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
