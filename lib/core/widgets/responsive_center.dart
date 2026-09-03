import 'package:flutter/material.dart';

/// A helper widget that centers its child and constrains the maximum width on
/// larger viewports. This helps make screens look better on tablet and desktop
/// sizes while keeping mobile layouts unchanged.
///
/// Wrap a Scaffold *body* (not the whole Scaffold — the app bar should keep
/// spanning the full width). Two width tiers are supported:
///
///  * the tablet band caps at [maxContentWidth];
///  * the wide band (`>= wideBreakpoint`, landscape tablet / desktop) caps at
///    [wideMaxWidth] when one is provided, otherwise it stays at
///    [maxContentWidth].
///
/// Below the active cap the [child] is returned untouched, so phone layouts
/// render exactly as before.
class ResponsiveCenter extends StatelessWidget {
  /// The widget below this widget in the tree.
  final Widget child;

  /// The maximum width the [child] should take on larger screens.
  /// Defaults to 600 which matches typical handset content width.
  final double maxContentWidth;

  /// Optional wider cap applied at and above [wideBreakpoint] (landscape
  /// tablet / desktop). When null the content stays at [maxContentWidth] at all
  /// widths, preserving the original single-cap behaviour.
  final double? wideMaxWidth;

  /// Optional padding applied inside the constrained area.
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxContentWidth = 600,
    this.wideMaxWidth,
    this.padding,
  });

  /// Width at and above which the shell shows the navigation rail and content
  /// is allowed to grow to [wideMaxWidth].
  static const double wideBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final double cap = (width >= wideBreakpoint && wideMaxWidth != null)
        ? wideMaxWidth!
        : maxContentWidth;
    Widget content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;
    if (width > cap) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cap),
          child: content,
        ),
      );
    }
    return content;
  }
}
