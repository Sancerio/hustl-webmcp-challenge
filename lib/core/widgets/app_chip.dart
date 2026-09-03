import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';

/// The single chip vocabulary for the app. Replaces InfoChip, _InfoPill,
/// _InfoTag, _MetricChip, _StatPill and ad-hoc Container badges.
enum AppChipVariant {
  /// Tappable selection state (e.g. region/filter rows). Reflects [selected].
  filter,

  /// Read-only status pill (e.g. "Over budget", "Rest day"). Tinted by [color].
  status,

  /// Compact label + value data badge (e.g. "Volume · 12.4k kg").
  data,
}

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.variant = AppChipVariant.status,
    this.icon,
    this.value,
    this.color,
    this.selected = false,
    this.onTap,
    this.semanticsLabel,
    this.tooltip,
  });

  final String label;
  final AppChipVariant variant;
  final IconData? icon;

  /// Trailing emphasised value, only used by [AppChipVariant.data].
  final String? value;

  /// Accent colour for status/data tinting. Defaults to the theme's primary.
  final Color? color;

  /// Selected state for [AppChipVariant.filter].
  final bool selected;

  final VoidCallback? onTap;
  final String? semanticsLabel;

  /// Optional tooltip message shown on long-press (e.g. for body-score region
  /// chips that need a one-line explanation of the metric).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Wave G (§12.1): flat 12px text chips — no border, no resting fill.
    // The ONLY fill is a blue 10% tint when a filter chip is selected.
    // Status/data chips may still pass a semantic data colour (orange
    // over-budget, macro tokens); when none is given they fall back to blue.
    final accent = color ?? AppColors.accentElectricBlue;

    final ({Color background, Color foreground}) palette = switch (variant) {
      AppChipVariant.filter =>
        selected
            ? (
                background: AppColors.accentElectricBlue.withValues(
                  alpha: 0.10,
                ),
                foreground: AppColors.accentElectricBlue,
              )
            : (
                background: Colors.transparent,
                foreground: colors.onSurfaceVariant,
              ),
      AppChipVariant.status => (
        background: accent.withValues(alpha: 0.10),
        foreground: accent,
      ),
      AppChipVariant.data => (
        background: Colors.transparent,
        foreground: colors.onSurface,
      ),
    };

    final labelStyle = TextStyle(
      color: palette.foreground,
      fontSize: 12,
      fontWeight: selected || variant == AppChipVariant.status
          ? FontWeight.w600
          : FontWeight.w500,
      height: 16 / 12,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: palette.foreground),
          const SizedBox(width: 4),
        ],
        Text(label, style: labelStyle),
        if (variant == AppChipVariant.data && value != null) ...[
          const SizedBox(width: 4),
          Text(
            value!,
            style: labelStyle.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );

    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x1 + 2,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: AppRadius.pillRadius,
      ),
      child: content,
    );

    final Widget interactive = onTap == null
        ? chip
        : Material(
            color: Colors.transparent,
            borderRadius: AppRadius.pillRadius,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.pillRadius,
              child: chip,
            ),
          );

    // Fold the chip into a single semantics node so screen readers announce
    // one element with the right role and selection state. The InkWell's own
    // node is excluded to avoid a duplicate; the tap action is re-declared here.
    final semanticsNode = Semantics(
      container: true,
      label: semanticsLabel ?? label,
      button: onTap != null,
      selected: variant == AppChipVariant.filter ? selected : null,
      onTap: onTap,
      child: ExcludeSemantics(child: interactive),
    );

    if (tooltip == null) return semanticsNode;
    return Tooltip(message: tooltip!, child: semanticsNode);
  }
}
