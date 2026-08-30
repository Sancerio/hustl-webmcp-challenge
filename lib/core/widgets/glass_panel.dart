import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';

/// The only sanctioned glass material in the app. Used ONLY for the bottom nav
/// bar, the rest-timer chip and the PR banner.
///
/// On web (where `BackdropFilter` is expensive and often janky) and when the
/// user has reduced transparency / disabled animations, this falls back to an
/// opaque surface — same footprint, no blur.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blurSigma,
    this.forceOpaque = false,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Override the per-theme blur sigma.
  final double? blurSigma;

  /// Force the opaque, no-blur path regardless of platform.
  final bool forceOpaque;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = borderRadius ?? AppRadius.cardRadius;

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final useOpaque = forceOpaque || kIsWeb || disableAnimations;

    final borderColor = isLight
        ? AppColors.glassBorderLight
        : AppColors.glassBorderDark;

    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);

    if (useOpaque) {
      final opaque = isLight
          ? AppColors.glassSurfaceLightOpaque
          : AppColors.glassSurfaceDarkOpaque;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: opaque,
          borderRadius: radius,
          border: Border.all(color: borderColor),
        ),
        child: content,
      );
    }

    final sigma =
        blurSigma ??
        (isLight ? AppColors.glassBlurLight : AppColors.glassBlurDark);
    final tint = isLight
        ? AppColors.glassSurfaceLight
        : AppColors.glassSurfaceDark;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: radius,
            border: Border.all(color: borderColor),
          ),
          child: content,
        ),
      ),
    );
  }
}
