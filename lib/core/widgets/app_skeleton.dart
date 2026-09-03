import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import 'hustl_inline_skeleton.dart';

/// The single skeleton loading pattern for the app. Replaces the CPI / Shimmer /
/// HustlInlineSkeleton mixes. A skeleton box shimmers gently while mounted (the
/// loading state); the shimmer is disabled when `MediaQuery.disableAnimations`
/// is set, leaving a static placeholder so reduced-motion users see no movement.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = AppSpacing.x2,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.animate = true,
  });

  /// Convenience for a circular avatar/icon placeholder.
  const AppSkeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = null,
      shape = BoxShape.circle,
      animate = true;

  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  /// Whether this individual placeholder should shimmer. Dense loading
  /// surfaces can disable animation so they do not start several concurrent
  /// tickers while the first interactive screen is being assembled.
  final bool animate;

  /// A multi-line text-block placeholder. Internally reuses [HustlInlineSkeleton]
  /// so existing call sites converge on one implementation.
  static Widget lines({
    int rows = 4,
    EdgeInsetsGeometry padding = const EdgeInsets.all(AppSpacing.x2),
    String semanticsLabel = 'Loading content',
    bool liveRegion = false,
  }) {
    return HustlInlineSkeleton(
      rows: rows,
      padding: padding,
      semanticsLabel: semanticsLabel,
      liveRegion: liveRegion,
    );
  }

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool _animating = false;

  void _syncAnimation(bool reduceMotion) {
    if (reduceMotion || !widget.animate) {
      if (_animating) {
        _controller.stop();
        _animating = false;
      }
      return;
    }
    if (!_animating) {
      _controller.repeat();
      _animating = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimation(reduceMotion);

    final colors = Theme.of(context).colorScheme;
    // Flat canvas (Wave G): surface == background, so the placeholder reads
    // via the raised step and the shimmer band via a faint onSurface lift.
    final base = colors.surfaceContainerHighest;
    final highlight = Color.alphaBlend(
      colors.onSurface.withValues(alpha: 0.06),
      base,
    );

    final radius = widget.shape == BoxShape.circle
        ? null
        : (widget.borderRadius ?? BorderRadius.circular(AppRadius.control - 4));

    return Semantics(
      label: 'Loading',
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final shouldAnimate = widget.animate && !reduceMotion;
              final t = shouldAnimate ? _controller.value : 0.0;
              return DecoratedBox(
                decoration: BoxDecoration(
                  shape: widget.shape,
                  borderRadius: radius,
                  gradient: shouldAnimate
                      ? LinearGradient(
                          begin: Alignment(-1 - 2 * t, 0),
                          end: Alignment(1 - 2 * t, 0),
                          colors: [base, highlight, base],
                          stops: const [0.35, 0.5, 0.65],
                        )
                      : null,
                  color: shouldAnimate ? null : base,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
