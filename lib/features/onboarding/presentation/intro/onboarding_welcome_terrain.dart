import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:hustl_app/app/theme/app_colors.dart';

import 'onboarding_intro_art.dart';
import 'onboarding_summit_art.dart';

/// The climb ahead as a living scene: the Summit terrain with the ambient
/// layer on — breathing ridges, drifting clouds, sun breath, and a periodic
/// energy pulse up the route. Runs its own ticker; reduce-motion (and
/// goldens) keep the clock at zero for a byte-identical still frame.
///
/// The "you are here" marker sits at [progress] — the trailhead, not the
/// summit, on the redesigned welcome screen: the climb is ahead, not
/// completed. The summit flag still plants at the route's fixed endpoint
/// regardless of [progress].
class LivingSummit extends StatefulWidget {
  const LivingSummit({super.key, this.progress = 0.12});

  final double progress;

  @override
  State<LivingSummit> createState() => _LivingSummitState();
}

class _LivingSummitState extends State<LivingSummit>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(
    (elapsed) => _clock.value = elapsed.inMicroseconds / 1e6,
  );
  final _clock = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      if (_ticker.isActive) _ticker.stop();
      _clock.value = 0;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final at = SummitTerrainPainter.markerPositionFor(
          constraints.biggest,
          widget.progress,
        );
        const iconSize = 28.0;
        return ValueListenableBuilder<double>(
          valueListenable: _clock,
          builder: (_, time, _) => Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: SummitTerrainPainter(
                    canvasColor: colors.surface,
                    contour: colors.outlineVariant,
                    contourStrong: colors.onSurfaceVariant.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.60 : 0.45,
                    ),
                    route: colors.primary,
                    ink: colors.onSurface,
                    flag: AppColors.accentWarningAmber,
                    sun: AppColors.accentWarningAmber,
                    progress: widget.progress,
                    time: time,
                    ambientLife: true,
                    summit: true,
                    sunFraction: const Offset(.50, .175),
                    echoStrength: theme.brightness == Brightness.dark ? 0 : 1,
                  ),
                ),
              ),
              Positioned(
                left: at.dx - iconSize / 2,
                top: at.dy - iconSize / 2,
                child: const LogoMark(size: iconSize, radius: 8),
              ),
            ],
          ),
        );
      },
    );
  }
}
