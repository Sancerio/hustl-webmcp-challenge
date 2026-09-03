import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';

/// The Target / TDEE compare toggle for the energy-balance chart — made HONEST.
///
/// When there is no TDEE estimate yet ([hasTdee] false) the TDEE segment is
/// disabled with a "No TDEE yet" caption, and the screen compares to Target only
/// — instead of the old behaviour that silently drew the reference line at the
/// target while labelling it TDEE.
class EnergyCompareToggle extends StatelessWidget {
  const EnergyCompareToggle({
    super.key,
    required this.compareToExpenditure,
    required this.hasTdee,
    required this.onToggle,
  });

  final bool compareToExpenditure;
  final bool hasTdee;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // With no TDEE we can only compare to Target, whatever the stored flag says.
    final tdeeSelected = hasTdee && compareToExpenditure;

    Widget seg(
      String label, {
      required bool selected,
      required bool enabled,
      required VoidCallback onTap,
    }) {
      final fg = !enabled
          ? colors.onSurfaceVariant.withValues(alpha: 0.4)
          : (selected ? colors.onPrimary : colors.onSurfaceVariant);
      return Expanded(
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected ? colors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 150,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            children: [
              seg(
                'Target',
                selected: !tdeeSelected,
                enabled: true,
                onTap: () => onToggle(false),
              ),
              seg(
                'TDEE',
                selected: tdeeSelected,
                enabled: hasTdee,
                onTap: () => onToggle(true),
              ),
            ],
          ),
        ),
        if (!hasTdee) ...[
          const SizedBox(height: 4),
          Text(
            'No TDEE yet',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
