import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';

import '../../../workout_logging/domain/models/workout_session.dart';
import '../../domain/import_summary.dart';
import '../../domain/workout_import_runner.dart';
import 'import_ui.dart';

/// Onboarding import preview — reframes the utilitarian "147 sessions found"
/// dialog into a confident step: confirm the real counts, reassure nothing is
/// lost or overwritten, then commit. The primary CTA runs the real
/// [WorkoutImportRunner] and hands the outcome to the restored celebration.
class OnboardingImportPreviewScreen extends StatefulWidget {
  const OnboardingImportPreviewScreen({
    super.key,
    required this.sessions,
    required this.summary,
  });

  final List<WorkoutSession> sessions;
  final ImportSummary summary;

  @override
  State<OnboardingImportPreviewScreen> createState() =>
      _OnboardingImportPreviewScreenState();
}

class _OnboardingImportPreviewScreenState
    extends State<OnboardingImportPreviewScreen> {
  static final _rowDate = DateFormat('MMM d, yyyy');
  static final _monthYear = DateFormat('MMM yyyy');

  bool _importing = false;
  double _progress = 0;

  Future<void> _runImport() async {
    if (_importing) return;
    Haptics.confirm();
    setState(() {
      _importing = true;
      _progress = 0;
    });
    try {
      final outcome = await WorkoutImportRunner().run(
        widget.sessions,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _progress = total == 0 ? 1 : done / total);
          }
        },
      );
      if (!mounted) return;
      context.push(
        '/onboarding/import/restored',
        extra: {'outcome': outcome, 'summary': widget.summary},
      );
    } catch (e) {
      // A failed write must leave a recoverable screen, not an uncaught error
      // with a permanently-disabled CTA (mirrors the Settings import).
      if (!mounted) return;
      HustlSnack.show(
        context,
        "Couldn't import your history: $e",
        variant: HustlSnackVariant.error,
      );
    } finally {
      // Always re-enable the CTA so the user can retry.
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final s = widget.summary;
    final since = s.firstDate != null ? _monthYear.format(s.firstDate!) : null;
    final recent = widget.sessions.reversed.take(3).toList();
    final moreCount = s.workouts - recent.length;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(title: const Text('Import from Strong')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.x3),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Text(
                        'Found in strong.csv',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '${s.workouts} workouts ready to restore',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    '${s.exercises} exercises · ${s.totalSets} sets'
                    '${since != null ? ' · your full history since $since' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Container(
                    decoration: importCard(context),
                    child: Column(
                      children: [
                        for (var i = 0; i < recent.length; i++) ...[
                          if (i > 0) const _Divider(),
                          _PreviewRow(
                            name: recent[i].name,
                            meta:
                                '${_rowDate.format(recent[i].startTime)} · '
                                '${recent[i].exercises.length} exercises',
                          ),
                        ],
                        if (moreCount > 0) ...[
                          const _Divider(),
                          _PreviewRow(
                            name: '+ $moreCount more workouts',
                            meta: s.firstDate != null
                                ? 'back to ${_rowDate.format(s.firstDate!)}'
                                : 'your full history',
                            muted: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  const ImportReassurance(
                    'We keep your dates, weights, and reps exactly as logged.',
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  const ImportReassurance(
                    'A workout that matches one already in Hustl (same name and '
                    'time) is replaced, not duplicated.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                0,
                AppSpacing.x3,
                AppSpacing.x3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_importing) ...[
                    LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                  ],
                  FilledButton(
                    onPressed: _importing ? null : _runImport,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      textStyle: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.controlRadius,
                      ),
                    ),
                    child: Text(
                      _importing
                          ? 'Restoring your history…'
                          : 'Import ${s.workouts} workouts',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () {
                            Haptics.selection();
                            if (context.canPop()) context.pop();
                          },
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.name,
    required this.meta,
    this.muted = false,
  });

  final String name;
  final String meta;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1 + 4,
      ),
      child: Row(
        children: [
          Icon(
            muted ? Icons.more_horiz_rounded : Icons.fitness_center_rounded,
            size: 18,
            color: muted ? colors.onSurfaceVariant : colors.primary,
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: muted ? colors.onSurfaceVariant : colors.onSurface,
                  ),
                ),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
}
