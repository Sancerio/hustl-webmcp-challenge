import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';

/// §12.1: active filters render as flat 12px text chips with a blue 10% tint
/// (the selected-filter signal) and a small inline remove affordance.
class ActiveFiltersDisplay extends StatelessWidget {
  final List<String> activeFilters;
  final ValueChanged<String>? onFilterRemoved;

  const ActiveFiltersDisplay({
    super.key,
    required this.activeFilters,
    this.onFilterRemoved,
  });

  @override
  Widget build(BuildContext context) {
    if (activeFilters.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: activeFilters.map((filter) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _RemovableFilterChip(
                label: filter,
                onRemoved: onFilterRemoved == null
                    ? null
                    : () => onFilterRemoved!(filter),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _RemovableFilterChip extends StatelessWidget {
  const _RemovableFilterChip({required this.label, this.onRemoved});

  final String label;
  final VoidCallback? onRemoved;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentElectricBlue;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 16 / 12,
            ),
          ),
          if (onRemoved != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.close, size: 14, color: accent),
          ],
        ],
      ),
    );

    if (onRemoved == null) return content;
    return Semantics(
      button: true,
      label: 'Remove $label filter',
      child: InkWell(
        onTap: onRemoved,
        borderRadius: BorderRadius.circular(999),
        child: content,
      ),
    );
  }
}
