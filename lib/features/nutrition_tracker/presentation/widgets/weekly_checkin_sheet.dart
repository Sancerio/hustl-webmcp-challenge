import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';

import '../../domain/models/nutrition_target_plan.dart';

class WeeklyCheckInSheet extends StatelessWidget {
  const WeeklyCheckInSheet({
    super.key,
    required this.plan,
    required this.payload,
    required this.onApply,
    required this.onSkip,
    this.isWorking = false,
  });

  /// The current plan — used to preview the RESULTING targets (current + delta).
  final NutritionTargetPlan plan;
  final Map<String, dynamic> payload;
  final VoidCallback onApply;
  final VoidCallback onSkip;
  final bool isWorking;

  String _fmtDelta(num? v, {String unit = ''}) {
    if (v == null) return '—';
    final value = v.toDouble();
    final sign = value >= 0 ? '+' : '−';
    final abs = value.abs();
    final text = abs % 1 == 0 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(1);
    return '$sign$text$unit';
  }

  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  /// The diagnostics, demoted into one muted line instead of a grey stack.
  String _metaLine(
    int? windowDays,
    double? confidence,
    bool capApplied,
    Map<String, dynamic> coverage,
  ) {
    final parts = <String>[];
    if (windowDays != null) parts.add('$windowDays-day window');
    if (confidence != null) {
      parts.add('${(confidence * 100).toStringAsFixed(0)}% confidence');
    }
    parts.add('${coverage['daysWithCaloriesLogged'] ?? 0}/7 logged');
    parts.add('${coverage['weighInDays'] ?? 0} weigh-ins');
    if (capApplied) parts.add('weekly cap applied');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deltas =
        (payload['deltas'] as Map?)?.cast<String, dynamic>() ?? const {};
    final why = (payload['why'] as Map?)?.cast<String, dynamic>() ?? const {};
    final coverage =
        (payload['coverage'] as Map?)?.cast<String, dynamic>() ?? const {};

    final capApplied = why['capApplied'] == true;
    final tdeeKcal = (why['tdeeKcal'] as num?)?.toDouble();
    final windowDays = (why['windowDays'] as num?)?.toInt();
    final confidence = (why['confidence'] as num?)?.toDouble();
    // Recovery/load-aware caveat (item 5) — only present when an aggressive
    // proposed deficit meets a confident low-recovery signal.
    final caveatRaw = why['caveat'];
    final caveat = caveatRaw is String && caveatRaw.trim().isNotEmpty
        ? caveatRaw.trim()
        : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ResponsiveCenter(
        maxContentWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Weekly check-in', style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  onPressed: isWorking ? null : () => context.pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // §12.1: flat section — what changed, as divider delta rows.
            const SectionHeader(
              'What changed',
              padding: EdgeInsets.only(bottom: 4),
            ),
            _deltaRow(
              context,
              label: 'Calories',
              value: _fmtDelta(deltas['calories'], unit: ' kcal'),
            ),
            const Divider(),
            _deltaRow(
              context,
              label: 'Protein',
              value: _fmtDelta(deltas['protein'], unit: ' g'),
            ),
            const Divider(),
            _deltaRow(
              context,
              label: 'Carbs',
              value: _fmtDelta(deltas['carbs'], unit: ' g'),
            ),
            const Divider(),
            _deltaRow(
              context,
              label: 'Fat',
              value: _fmtDelta(deltas['fat'], unit: ' g'),
            ),
            const SizedBox(height: 16),
            // The resulting plan (current + delta) so the user sees the OUTCOME,
            // not just the change.
            const SectionHeader(
              'New targets',
              padding: EdgeInsets.only(bottom: 8),
            ),
            Text(
              '${(plan.caloriesTarget + _d(deltas['calories'])).round()} kcal'
              ' · ${(plan.proteinTarget + _d(deltas['protein'])).round()}g P'
              ' · ${(plan.carbsTarget + _d(deltas['carbs'])).round()}g C'
              ' · ${(plan.fatTarget + _d(deltas['fat'])).round()}g F',
              style: AppTextStyles.metric(
                theme.textTheme.bodyLarge ?? const TextStyle(),
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader('Why', padding: EdgeInsets.only(bottom: 8)),
            Text(
              tdeeKcal == null
                  ? 'Based on your recent intake and weight trend.'
                  : 'TDEE estimate ${tdeeKcal.toStringAsFixed(0)} kcal',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _metaLine(windowDays, confidence, capApplied, coverage),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (caveat != null) ...[
              const SizedBox(height: 12),
              _CaveatNote(text: caveat),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: isWorking ? null : onApply,
                    child: isWorking
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: isWorking ? null : onSkip,
                    child: const Text('Skip this week'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _deltaRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(value, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}

/// The recovery/load-aware caveat (item 5): an honest, amber-tinted "ease the
/// rate" note shown only when the proposal pushes an aggressive deficit while
/// recovery is confidently low. Advisory, not blocking — the user still chooses.
class _CaveatNote extends StatelessWidget {
  const _CaveatNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accentWarningAmber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
