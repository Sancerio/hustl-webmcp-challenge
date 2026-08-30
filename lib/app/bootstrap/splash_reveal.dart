import 'package:flutter/material.dart';

/// One-shot reveal overlay that hands off seamlessly from the native splash.
///
/// The native splash and the app canvas share the same fill (`#000000` dark /
/// `#FFFFFF` light) and the same bare dumbbell glyph, so the handoff frame is
/// identical — then the glyph performs a single rep (anticipation dip, lift
/// with a hint of overshoot, settle) while the wordmark stamps in beneath it,
/// and the overlay fades through to the content. One moment of character on
/// an otherwise stark canvas.
///
/// Plays once per app launch and only on a cold start. The controller runs a
/// single forward pass and stops — no perpetual ticker. Honours
/// `MediaQuery.disableAnimations` by snapping straight to the dissolved state.
class SplashReveal extends StatefulWidget {
  const SplashReveal({super.key, this.onCompleted, this.launchedAt});

  /// Called once the reveal has fully dissolved and can be torn down.
  final VoidCallback? onCompleted;

  /// When the app process began booting. When provided, the reveal trims its
  /// duration by however long the native splash was already on screen, so the
  /// branded moment doesn't stack on top of a slow cold start. When null
  /// (e.g. tests), the full duration plays.
  final DateTime? launchedAt;

  /// Glyph edge length, matched to the native splash image footprint.
  static const double logoSize = 84;

  /// The wordmark rendered beneath the glyph while the overlay holds.
  static const String wordmark = 'Hustl';

  @override
  State<SplashReveal> createState() => _SplashRevealState();
}

class _SplashRevealState extends State<SplashReveal>
    with SingleTickerProviderStateMixin {
  // Budget: rep (~460ms) + hold + fade-through (~270ms), all <= 950ms.
  static const Duration _baseTotal = Duration(milliseconds: 950);

  // Floor so the rep still reads even after a very slow cold start.
  static const Duration _minTotal = Duration(milliseconds: 550);

  // Don't penalize fast boots: only trim for init beyond this grace window.
  static const Duration _initGrace = Duration(milliseconds: 250);

  /// Resolved once, from how long the native splash was already up. The
  /// animation intervals are fractions of the controller, so the whole
  /// choreography compresses proportionally when [_total] shrinks.
  late final Duration _total = _resolveTotal();

  Duration _resolveTotal() {
    final launchedAt = widget.launchedAt;
    if (launchedAt == null) return _baseTotal;
    final overrun = DateTime.now().difference(launchedAt) - _initGrace;
    if (overrun <= Duration.zero) return _baseTotal;
    final trimmed = _baseTotal - overrun;
    return trimmed < _minTotal ? _minTotal : trimmed;
  }

  late final AnimationController _controller;
  late final Animation<double> _wordmarkIn;
  late final Animation<double> _dissolve;

  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);

    // Wordmark stamps in while the rep finishes.
    _wordmarkIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.55, curve: Curves.easeOutCubic),
    );

    // After a steady hold, the overlay fades through to the content.
    _dissolve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.72, 1.0, curve: Curves.easeOut),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completed) {
        _completed = true;
        widget.onCompleted?.call();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      // Snap to the end so content shows immediately.
      if (!_completed) {
        _completed = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onCompleted?.call(),
        );
      }
    } else if (!_controller.isAnimating &&
        _controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The rep, as piecewise vertical travel over the controller timeline:
  /// rest -> dip (anticipation) -> lift with overshoot -> settle at rest.
  static double _repY(double t) {
    if (t < 0.13) {
      // Anticipation: sink 7px.
      return 7 * Curves.easeOut.transform(t / 0.13);
    }
    if (t < 0.34) {
      // The lift: travel from +7 to -14 with an eased push.
      final u = Curves.easeOutCubic.transform((t - 0.13) / 0.21);
      return 7 - 21 * u;
    }
    if (t < 0.48) {
      // Settle back to rest from the top of the rep.
      final u = Curves.easeOut.transform((t - 0.34) / 0.14);
      return -14 * (1 - u);
    }
    return 0;
  }

  /// Squash-and-stretch paired with the travel: compressed at the dip,
  /// slightly stretched at the top of the lift.
  static double _repScaleY(double t) {
    final y = _repY(t);
    if (y > 0) return 1.0 - 0.012 * y; // dip: up to ~0.92 squash at +7
    return 1.0 - 0.005 * y; // lift: up to ~1.07 stretch at -14
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final ink = theme.colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = (1.0 - _dissolve.value).clamp(0.0, 1.0);
        if (opacity <= 0) return const SizedBox.shrink();

        final t = _controller.value;
        final wordmark = _wordmarkIn.value;
        final tracking = 4.0 - 3.5 * wordmark;

        return IgnorePointer(
          ignoring: _dissolve.value > 0,
          child: Opacity(
            opacity: opacity,
            // Material (not ColoredBox) so the wordmark Text has a Material
            // ancestor — this overlay sits above the app's Navigator.
            child: Material(
              color: background,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Glyph pinned at the native-splash position; tinted to the
                  // theme ink so one asset serves both themes.
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, _repY(t)),
                      child: Transform.scale(
                        scaleY: _repScaleY(t),
                        child: Image.asset(
                          'assets/icon/hustl-glyph-white.png',
                          width: SplashReveal.logoSize,
                          height: SplashReveal.logoSize,
                          color: ink,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, SplashReveal.logoSize - 4.0 * wordmark),
                      child: Opacity(
                        opacity: wordmark,
                        child: Text(
                          SplashReveal.wordmark,
                          style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: tracking,
                            color: ink,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
