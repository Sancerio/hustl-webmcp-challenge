import 'package:flutter/material.dart';

/// Branded onboarding-intro art: a small toolkit of CustomPainters (all drawn,
/// no font icons) for the signature dark intro carousel. Colors are passed in by
/// callers from the theme (`colorScheme.*` / `AppColors.*`) — nothing here hard-
/// codes a hue. The look leans premium: soft single-hue luminosity (radial
/// glows), glossy fills (lightness ramps, not multi-color gradients), and quiet
/// instrument detail.

// --- shared helpers -------------------------------------------------------

/// Lighten a hue toward white via HSL (no hard-coded `Colors.white`), for

// --- painters -------------------------------------------------------------

/// A glowing radar halo: a soft luminous core, fading concentric rings, a quiet
/// "sweep" arc highlight, and a few data dots — the energy behind the mark.
class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    this.size = 84,
    this.radius = 26,
    this.onDark = true,
  });
  final double size;
  final double radius;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: onDark ? colors.onSurface.withValues(alpha: 0.04) : null,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: onDark
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.35),
                  blurRadius: size * 0.34,
                  spreadRadius: -size * 0.06,
                ),
              ]
            : null,
      ),
      child: Image.asset('assets/icon/hustl-icon.png', fit: BoxFit.cover),
    );
  }
}
