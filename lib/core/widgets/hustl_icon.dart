import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a bundled custom SVG glyph from the `assets/icons/` family, tinted to
/// [color] via a `srcIn` color filter.
///
/// The source SVGs are 24x24 `fill="none" stroke="currentColor"` line icons with
/// no hardcoded color, so a single asset serves every state — the app drives the
/// appearance purely through [color] (e.g. selected vs. unselected nav tabs).
///
/// Pass a theme token (never a hardcoded `Color`) for [color], and supply a
/// [semanticsLabel] when the icon carries meaning that isn't already announced
/// by an enclosing semantics node.
class HustlIcon extends StatelessWidget {
  const HustlIcon({
    super.key,
    required this.asset,
    this.size = 24,
    required this.color,
    this.semanticsLabel,
  });

  /// Asset path of the SVG, e.g. `'assets/icons/nav_train.svg'`.
  final String asset;

  /// Rendered width and height in logical pixels.
  final double size;

  /// Tint applied to the line glyph.
  final Color color;

  /// Optional accessibility label for the rendered glyph.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: semanticsLabel,
    );
  }
}
