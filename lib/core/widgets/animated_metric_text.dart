import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_text_styles.dart';
import '../utils/number_format_util.dart';

/// A number that tweens smoothly to a new value, rendered with tabular figures
/// so the layout never shifts as digits change width.
///
/// Honours `MediaQuery.disableAnimations` (snaps straight to the target). Use
/// for any live or count-up metric (weights, calories, totals).
class AnimatedMetricText extends StatelessWidget {
  const AnimatedMetricText({
    super.key,
    required this.value,
    this.style,
    this.fractionDigits = 0,
    this.prefix = '',
    this.suffix = '',
    this.duration,
    this.curve = AppMotion.emphasizedCurve,
    this.textAlign,
    this.semanticsLabel,
    this.grouped = false,
  });

  /// Target numeric value to animate toward.
  final double value;

  /// Base text style. Tabular figures are applied on top via
  /// [AppTextStyles.metric].
  final TextStyle? style;

  /// Decimal places to render.
  final int fractionDigits;

  final String prefix;
  final String suffix;

  /// Defaults to [AppMotion.emphasized].
  final Duration? duration;
  final Curve curve;
  final TextAlign? textAlign;
  final String? semanticsLabel;

  /// Render with locale digit grouping (e.g. 31,662) instead of bare digits.
  final bool grouped;

  String _format(double v) {
    final number = grouped
        ? NumberFormatUtil.formatDouble(v, decimalDigits: fractionDigits)
        : v.toStringAsFixed(fractionDigits);
    return '$prefix$number$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final metricStyle = AppTextStyles.metric(baseStyle);

    return Semantics(
      label: semanticsLabel,
      value: _format(value),
      liveRegion: !disableAnimations,
      child: ExcludeSemantics(
        // TweenAnimationBuilder animates from the currently displayed value to
        // `end` whenever `end` changes; `begin` only seeds the first build.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value),
          duration: disableAnimations
              ? Duration.zero
              : (duration ?? AppMotion.emphasized),
          curve: curve,
          builder: (context, v, _) {
            return Text(_format(v), style: metricStyle, textAlign: textAlign);
          },
        ),
      ),
    );
  }
}
