import 'package:flutter/material.dart';

import '../../../../../core/widgets/hustl_icon.dart';

/// A 40px circular "soft holder" button (Wave I) hosting a single custom line
/// glyph. The fill is a quiet [ColorScheme.surfaceContainerHighest] disc with a
/// centered [HustlIcon] tinted to `onSurface`, and a circular ripple on tap.
///
/// When [showDot] is true a small primary-color badge is drawn at the top-right
/// with a surface-colored ring so it reads as a status badge (e.g. "has notes").
class SoftHolderButton extends StatelessWidget {
  const SoftHolderButton({
    super.key,
    required this.asset,
    required this.onTap,
    required this.semanticsLabel,
    this.tooltip,
    this.showDot = false,
    this.size = 40,
    this.iconSize = 20,
  });

  /// Asset path of the custom SVG glyph, e.g. `'assets/icons/ic_note.svg'`.
  final String asset;

  /// Invoked when the holder is tapped.
  final VoidCallback onTap;

  /// Accessibility label announced for the button.
  final String semanticsLabel;

  /// Optional hover/long-press tooltip.
  final String? tooltip;

  /// Whether to render the small primary badge at the top-right corner.
  final bool showDot;

  /// Diameter of the circular holder.
  final double size;

  /// Rendered size of the centered glyph.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget holder = Material(
      color: colors.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: HustlIcon(
              asset: asset,
              size: iconSize,
              color: colors.onSurface,
            ),
          ),
        ),
      ),
    );

    if (showDot) {
      holder = Stack(
        clipBehavior: Clip.none,
        children: [
          holder,
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                // Surface-colored ring so the dot reads as a distinct badge.
                border: Border.all(color: colors.surface, width: 2),
              ),
            ),
          ),
        ],
      );
    }

    final button = Semantics(
      button: true,
      label: semanticsLabel,
      child: SizedBox(width: size, height: size, child: holder),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
