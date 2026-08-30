import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

import 'onboarding_intro_art.dart';
import 'onboarding_summit_art.dart';

/// First-run intro: the Summit carousel. One contour mountain fills the
/// canvas; a blue route climbs camp to camp as the user swipes, with the
/// app icon as the climber. Each slide is a camp: the coach at base camp,
/// then training, nutrition, and the connected-plan push.
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key});

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _Slide {
  const _Slide({
    required this.eyebrow,
    required this.title,
    required this.accent,
    required this.body,
    required this.pillar,
    this.next,
  });
  final String eyebrow;

  /// Title prefix; [accent] renders in the primary color after it.
  final String title;
  final String accent;
  final String body;
  final _Pillar pillar;
  final String? next;
}

enum _Pillar { coach, training, nutrition, connected }

const _slides = <_Slide>[
  _Slide(
    eyebrow: 'Base camp',
    title: 'Every climb\nneeds a ',
    accent: 'guide.',
    body:
        'Your AI coach reads your training, nutrition, and recovery — and '
        'routes the next step of the climb. You approve every move.',
    pillar: _Pillar.coach,
    next: 'Your training',
  ),
  _Slide(
    eyebrow: 'Camp 1 · Training',
    title: 'Log the work.\nGain ',
    accent: 'ground.',
    body:
        'Start a workout in seconds — no account. Every set you log is '
        'ground gained on the route.',
    pillar: _Pillar.training,
    next: 'Nutrition',
  ),
  _Slide(
    eyebrow: 'Camp 2 · Nutrition',
    title: 'Fuel the ',
    accent: 'ascent.',
    body:
        'Snap a meal or set a macro target. Every log sharpens tomorrow’s '
        'plan — no shaming, no rigidity.',
    pillar: _Pillar.nutrition,
    next: 'The summit',
  ),
  _Slide(
    eyebrow: 'The push',
    title: 'One route.\n',
    accent: 'Yours.',
    body:
        'Workouts, nutrition, and health feed one coach that proposes your '
        'next move. You always approve it.',
    pillar: _Pillar.connected,
  ),
];

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  // Monotonic ambient clock (seconds). Started only when motion is allowed
  // (see didChangeDependencies), so reduce-motion gets a still frame at
  // time 0 and goldens (which disable animations) never spin a ticker.
  late final Ticker _ticker = createTicker(
    (elapsed) => _clock.value = elapsed.inMicroseconds / 1e6,
  );
  final _clock = ValueNotifier<double>(0);
  // One-shot arrival choreography (camp pop + amber spark) fired when the
  // climber settles on a new camp after a real move.
  late final AnimationController _spark = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  bool _wasMoving = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final page = _livePage;
    final moving = (page - page.roundToDouble()).abs() > .003;
    if (_wasMoving && !moving) {
      // Settled on a camp after travelling — celebrate the arrival.
      _spark.forward(from: 0);
      Haptics.selection();
    }
    _wasMoving = moving;
  }

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
    _spark.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toWelcome() {
    Haptics.selection();
    context.go('/onboarding/welcome');
  }

  void _onCta() {
    if (_page < _slides.length - 1) {
      Haptics.selection();
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _controller.jumpToPage(_page + 1);
      } else {
        _controller.nextPage(
          duration: AppMotion.emphasized,
          curve: AppMotion.emphasizedCurve,
        );
      }
    } else {
      _toWelcome();
    }
  }

  double get _livePage => _controller.hasClients
      ? (_controller.page ?? _controller.initialPage.toDouble())
      : 0.0;

  /// The three camp artifacts, positioned relative to their camp anchors in
  /// terrain coordinates. Visibility keys off proximity to the owning slide,
  /// so a card is solid at rest, gone mid-swipe, and rises back on arrival.
  List<Widget> _campCallouts(Size size, double page, ColorScheme colors) {
    const specs = [
      (
        slide: 1,
        campT: 0.42,
        cardOffset: Offset(40, -150),
        eyebrow: 'SET LOGGED',
        title: 'Bench · 60 kg × 8',
        detail: '+120 kg volume today',
        kind: _BadgeKind.check,
      ),
      (
        slide: 2,
        campT: 0.68,
        cardOffset: Offset(-168, -128),
        eyebrow: 'MEAL LOGGED',
        title: 'Chicken & rice bowl',
        detail: '520 kcal · 42P · 50C · 16F',
        kind: _BadgeKind.macros,
      ),
      (
        slide: 3,
        campT: 0.92,
        cardOffset: Offset(-240, 30),
        eyebrow: 'COACH PROPOSES',
        title: '+2.5 kg on bench',
        detail: 'Last 3 sessions at RPE 7 — you have room.',
        kind: _BadgeKind.none,
      ),
    ];
    final out = <Widget>[];
    for (final c in specs) {
      final sel = (1 - (page - c.slide).abs()).clamp(0.0, 1.0);
      // Solid only near settle; hidden through most of the swipe.
      final visible = ((sel - .45) / .55).clamp(0.0, 1.0);
      if (visible == 0) continue;
      final o = Curves.easeOutCubic.transform(visible);
      final anchor = SummitTerrainPainter.markerPositionFor(size, c.campT);
      final topLeft = anchor + c.cardOffset;
      const cardWidth = 204.0;
      // Leader attaches to whichever card edge faces the camp.
      final attach = Offset(
        c.cardOffset.dx >= 0 ? topLeft.dx + 10 : topLeft.dx + cardWidth - 10,
        c.cardOffset.dy >= 0 ? topLeft.dy + 6 : topLeft.dy + 58,
      );
      out
        ..add(
          Positioned.fill(
            child: Opacity(
              opacity: o,
              child: CustomPaint(
                painter: _LeaderPainter(
                  from: anchor,
                  to: attach,
                  color: colors.primary,
                ),
              ),
            ),
          ),
        )
        ..add(
          Positioned(
            left: topLeft.dx,
            top: topLeft.dy + 10 * (1 - o),
            width: cardWidth,
            child: Opacity(
              opacity: o,
              child: _CampCallout(
                eyebrow: c.eyebrow,
                title: c.title,
                detail: c.detail,
                kind: c.kind,
              ),
            ),
          ),
        );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          // The mountain is shared across slides; the route (and the icon
          // climbing it) tracks the live swipe position, so progress is the
          // terrain itself rather than a separate indicator.
          Positioned.fill(
            bottom: 322,
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_controller, _clock, _spark]),
                  builder: (_, _) {
                    final page = _livePage;
                    final progress = SummitTerrainPainter.routeStopForPage(
                      page,
                    );
                    final fraction = page - page.floorToDouble();
                    final moving = fraction > .003 && fraction < .997;
                    // Depth-weighted horizontal drift while travelling, so
                    // the mountain shifts under the climber (Expedition).
                    final parallax = moving
                        ? math.sin(fraction * math.pi) * -10
                        : 0.0;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final at = SummitTerrainPainter.markerPositionFor(
                          constraints.biggest,
                          progress,
                        );
                        final lift = SummitTerrainPainter.markerLift(
                          _clock.value,
                          moving: moving,
                        );
                        final lean = SummitTerrainPainter.markerLean(
                          constraints.biggest,
                          progress,
                          moving: moving,
                        );
                        const iconSize = 30.0;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: SummitTerrainPainter(
                                  canvasColor: colors.surface,
                                  contour: colors.outlineVariant,
                                  contourStrong: colors.onSurfaceVariant
                                      .withValues(
                                        alpha:
                                            theme.brightness == Brightness.dark
                                            ? 0.60
                                            : 0.45,
                                      ),
                                  route: colors.primary,
                                  ink: colors.onSurface,
                                  flag: AppColors.accentWarningAmber,
                                  sun: AppColors.accentWarningAmber,
                                  progress: progress,
                                  time: _clock.value,
                                  moving: moving,
                                  spark: _spark.isAnimating ? _spark.value : 0,
                                  parallax: parallax,
                                  echoStrength:
                                      theme.brightness == Brightness.dark
                                      ? 0
                                      : 1,
                                ),
                              ),
                            ),
                            // Camp callouts: real product artifacts pinned
                            // to their camps — a logged set at Camp 1, a
                            // logged meal at Camp 2, the coach proposal at
                            // the push. Each fades out mid-swipe and rises
                            // back in as its slide settles.
                            ..._campCallouts(constraints.biggest, page, colors),
                            // The climber is the real app icon, riding the
                            // route head the painter exposes — bobbing and
                            // leaning into the slope while it travels.
                            Positioned(
                              left: at.dx - iconSize / 2 + lift.dx,
                              top: at.dy - iconSize / 2 + lift.dy,
                              child: Transform.rotate(
                                angle: lean,
                                child: const LogoMark(
                                  size: iconSize,
                                  radius: 9,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x1,
                AppSpacing.x3,
                AppSpacing.x3,
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _toWelcome,
                      child: Text(
                        'Skip',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: _slides.length,
                      itemBuilder: (_, i) => _SlideView(data: _slides[i]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Semantics(
                    label: 'Step ${_page + 1} of ${_slides.length}',
                    child: _NextCampCue(label: _slides[_page].next),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  FilledButton(
                    onPressed: _onCta,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.pillRadius,
                      ),
                    ),
                    child: Text(isLast ? 'Get started' : 'Keep climbing'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One slide: waypoint glyph floating over the terrain, then a left-aligned
/// eyebrow / title / body block that rises in a stagger — eyebrow first,
/// title lines, then body (Kinetic seasoning on the Expedition core).
class _SlideView extends StatelessWidget {
  const _SlideView({required this.data});
  final _Slide data;

  Widget _staggered(double t, double from, double to, Widget child) {
    final k = ((t - from) / (to - from)).clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(k);
    return Opacity(
      opacity: e,
      child: Transform.translate(offset: Offset(0, 14 * (1 - e)), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return TweenAnimationBuilder<double>(
      key: ValueKey(data.pillar),
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 800),
      curve: Curves.linear,
      builder: (context, t, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: SizedBox.expand()),
          _staggered(
            t,
            0,
            .4,
            Text(
              data.eyebrow.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          _staggered(
            t,
            .15,
            .65,
            RichText(
              text: TextSpan(
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1.06,
                  letterSpacing: -0.8,
                  color: colors.onSurface,
                ),
                children: [
                  TextSpan(text: data.title),
                  TextSpan(
                    text: data.accent,
                    style: TextStyle(color: colors.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          _staggered(
            t,
            .35,
            .9,
            Text(
              data.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _BadgeKind { none, check, macros }

/// A product-artifact card pinned to a camp: eyebrow with the coach dot,
/// one concrete line of product truth, and a quiet detail row. Shares one
/// visual system across all three story slides.
class _CampCallout extends StatelessWidget {
  const _CampCallout({
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.kind,
  });
  final String eyebrow;
  final String title;
  final String detail;
  final _BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                eyebrow,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (kind == _BadgeKind.check)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CustomPaint(painter: _CheckBadge()),
                ),
              if (kind == _BadgeKind.macros)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(painter: _MacroRingMini()),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// The thin curved line pinning a callout card to its camp dot.
class _LeaderPainter extends CustomPainter {
  const _LeaderPainter({
    required this.from,
    required this.to,
    required this.color,
  });
  final Offset from;
  final Offset to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        (from.dx + to.dx) / 2 + 10,
        (from.dy + to.dy) / 2,
        to.dx,
        to.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: .55),
    );
  }

  @override
  bool shouldRepaint(_LeaderPainter old) =>
      old.from != from || old.to != to || old.color != color;
}

/// Painted emerald check badge (no icon font, golden-safe).
class _CheckBadge extends CustomPainter {
  const _CheckBadge();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = AppColors.accentEmeraldGreen);
    final tick = Path()
      ..moveTo(c.dx - r * .42, c.dy + r * .02)
      ..lineTo(c.dx - r * .10, c.dy + r * .38)
      ..lineTo(c.dx + r * .46, c.dy - r * .34);
    canvas.drawPath(
      tick,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .28
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Mini macro donut: protein / carbs / fat arcs in the app's macro colors.
class _MacroRingMini extends CustomPainter {
  const _MacroRingMini();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    const gap = .16; // radians between segments
    var start = -math.pi / 2;
    for (final (frac, color) in [
      (.40, AppColors.macroProtein),
      (.38, AppColors.macroCarbs),
      (.22, AppColors.macroFat),
    ]) {
      final sweep = frac * (2 * math.pi) - gap;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The `Next camp:` cue under the page area; the terrain route itself is the
/// progress indicator.
class _NextCampCue extends StatelessWidget {
  const _NextCampCue({required this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (label == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'The summit is yours to start.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
          children: [
            const TextSpan(text: 'Next camp: '),
            TextSpan(
              text: label,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
