import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation/app_shell.dart';
import '../../app/navigation/shell_bottom_nav.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/ai_proposals/presentation/widgets/pending_proposal_banner.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import '../widgets/responsive_center.dart';
import '../widgets/active_workout_banner.dart';
import 'route_observer.dart';
import 'workout_minimize_intent.dart';
import 'workout_minimize_sheet_controller.dart';

Page<void> workoutMinimizePage(
  GoRouterState state,
  Widget child, {
  bool expandFromMiniPlayer = false,
  String? returnLocation,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name ?? state.fullPath,
    // The app shell and its already-mounted MiniPlayer must remain painted
    // beneath the expanded workout while the sheet is dragged away.
    opaque: false,
    transitionDuration: AppMotion.persistentSheet,
    reverseTransitionDuration: AppMotion.persistentSheet,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        WorkoutMinimizeTransition(
          animation: animation,
          expandFromMiniPlayer: expandFromMiniPlayer,
          returnLocation: returnLocation,
          child: child,
        ),
  );
}

/// Responsive persistent-player transition for the active workout.
///
/// Narrow screens expose a controller to the workout header. Direct drag and
/// the collapse control drive [_sheet] together; once the sheet is fully below
/// the viewport the route is popped while remaining offscreen. Wide screens
/// keep pointer input explicit and reveal the shell's top-docked MiniPlayer
/// with the same spatial settle. Other navigation uses the ordinary app
/// fade-slide.
class WorkoutMinimizeTransition extends StatefulWidget {
  const WorkoutMinimizeTransition({
    super.key,
    required this.animation,
    this.expandFromMiniPlayer = false,
    this.returnLocation,
    required this.child,
  });

  final Animation<double> animation;
  final bool expandFromMiniPlayer;
  final String? returnLocation;
  final Widget child;

  @override
  State<WorkoutMinimizeTransition> createState() =>
      _WorkoutMinimizeTransitionState();
}

class _WorkoutMinimizeTransitionState extends State<WorkoutMinimizeTransition>
    with SingleTickerProviderStateMixin {
  static const double _mobileNavigationHeight = 60;

  late final AnimationController _sheet;
  late final WorkoutMinimizeSheetController _sheetHandle;
  final GlobalKey _fallbackDesktopTopChromeKey = GlobalKey(
    debugLabel: 'workoutMinimizeFallbackTopChrome',
  );
  final GlobalKey _fallbackMobileBottomChromeKey = GlobalKey(
    debugLabel: 'workoutMinimizeFallbackBottomChrome',
  );
  bool _persistentPlayerRun = false;
  bool _minimizeInFlight = false;
  bool? _minimizeDestinationIsShell;
  bool _reduceMotionExitInFlight = false;
  bool? _wasDragEligible;
  bool _dragInProgress = false;
  bool _playerExpansionScheduled = false;
  bool _playerExpansionFinished = false;

  @override
  void initState() {
    super.initState();
    _sheet = AnimationController(
      vsync: this,
      duration: AppMotion.persistentSheet,
    );
    _sheetHandle = WorkoutMinimizeSheetController(
      canDrag: _canDrag,
      dragBy: _dragBy,
      release: _release,
      cancel: _cancel,
      minimize: _minimize,
    );
    widget.animation.addStatusListener(_handleStatus);
    _handleStatus(widget.animation.status);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePlayerExpansion();
    final dragEligible = _canDrag(context);
    if (_wasDragEligible == true && !dragEligible && !_minimizeInFlight) {
      // A resize or accessibility change can remove the gesture detector
      // without delivering its cancel callback, including between drag start
      // and the first non-zero update. Clear any accepted manipulation and
      // restore preparation state without touching button-driven minimize.
      if (_dragInProgress) {
        _dragInProgress = false;
        _sheet.stop();
        _sheet.value = 0;
      }
      ActiveWorkoutBanner.restoreAfterCancelledMinimize();
    }
    _wasDragEligible = dragEligible;
  }

  @override
  void didUpdateWidget(WorkoutMinimizeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    oldWidget.animation.removeStatusListener(_handleStatus);
    widget.animation.addStatusListener(_handleStatus);
    _handleStatus(widget.animation.status);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    _sheet.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.forward:
        // Keep consuming the one-shot intent for compatibility, but the
        // MiniPlayer expansion itself is owned by an internal controller. A
        // route animation starts before the destination finishes its first
        // build, so tying the visual motion to it can spend most of the 300 ms
        // offscreen and then jump when the first frame finally paints.
        final legacyPushIntent = WorkoutMinimizeIntent.consume(
          WorkoutMinimizeDirection.push,
        );
        _persistentPlayerRun = widget.expandFromMiniPlayer || legacyPushIntent;
      case AnimationStatus.reverse:
        _persistentPlayerRun = WorkoutMinimizeIntent.consume(
          WorkoutMinimizeDirection.pop,
        );
      case AnimationStatus.completed:
        _persistentPlayerRun = false;
      case AnimationStatus.dismissed:
        _persistentPlayerRun = false;
    }
  }

  void _schedulePlayerExpansion() {
    if (_playerExpansionScheduled || !widget.expandFromMiniPlayer) return;
    _playerExpansionScheduled = true;

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _playerExpansionFinished = true;
      return;
    }

    // Hold the expanded workout at the MiniPlayer destination for its first
    // rendered frame. Start the spatial motion only after that frame exists,
    // giving the user the complete transition even when route construction or
    // local session hydration occupies the route's own animation interval.
    _sheet.value = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sheet
          .animateBack(
            0,
            duration: AppMotion.persistentSheet,
            curve: AppMotion.persistentPlayerCurve,
          )
          .whenComplete(() {
            if (mounted) {
              setState(() => _playerExpansionFinished = true);
            }
          });
    });
  }

  bool _canDrag(BuildContext context) =>
      MediaQuery.sizeOf(context).width < ResponsiveCenter.wideBreakpoint &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _dragBy(BuildContext context, double deltaFraction) {
    if (!_canDrag(context) || _sheet.isAnimating) return;
    final nextValue = (_sheet.value + deltaFraction).clamp(0.0, 1.0);
    if (nextValue == _sheet.value) return;
    _dragInProgress = true;
    _sheet.value = nextValue;
  }

  Future<void> _release(BuildContext context, double velocity) async {
    // Eligibility can change while a gesture is in flight (for example when
    // browser resizing crosses the wide breakpoint). Once drag progress has
    // been accepted, always settle it instead of leaving [_sheet] stranded.
    _dragInProgress = false;
    final minimize = velocity.abs() >= 500
        ? velocity > 0
        : _sheet.value >= 0.34;
    if (minimize) {
      await _minimize(context);
      return;
    }
    await _cancel(context);
  }

  Future<void> _cancel(BuildContext context) async {
    _dragInProgress = false;
    // A platform accessibility change can disable motion while the gesture
    // recognizer is cancelling. Clear progress synchronously in that case so
    // it cannot reappear if animations are enabled again later.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _sheet.value = 0;
      ActiveWorkoutBanner.restoreAfterCancelledMinimize();
      return;
    }
    await _sheet.animateBack(
      0,
      duration: AppMotion.persistentSheet,
      curve: AppMotion.persistentPlayerCurve,
    );
    ActiveWorkoutBanner.restoreAfterCancelledMinimize();
  }

  Future<void> _minimize(BuildContext context) async {
    if (_minimizeInFlight) return;
    _dragInProgress = false;
    _minimizeInFlight = true;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isWide =
        MediaQuery.sizeOf(context).width >= ResponsiveCenter.wideBreakpoint;
    final router = GoRouter.of(context);
    final returnToShellPredecessor = _hasShellDestination(context);
    _minimizeDestinationIsShell = returnToShellPredecessor;

    ActiveWorkoutBanner.prepareForMinimizeDestination();

    if (reduceMotion) {
      setState(() => _reduceMotionExitInFlight = true);
    }

    final needsManualSettle = !isWide || !returnToShellPredecessor;
    if (!reduceMotion && needsManualSettle) {
      await _sheet.animateTo(
        1,
        duration: AppMotion.persistentSheet,
        curve: AppMotion.persistentPlayerCurve,
      );
      if (!context.mounted) {
        _minimizeInFlight = false;
        return;
      }
    }

    if (returnToShellPredecessor && router.canPop()) {
      WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
      router.pop();
    } else {
      router.go(widget.returnLocation ?? '/');
    }
    _minimizeInFlight = false;
  }

  @override
  Widget build(BuildContext context) {
    final scopedChild = WorkoutMinimizeSheetScope(
      controller: _sheetHandle,
      child: widget.child,
    );
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (!_reduceMotionExitInFlight) return scopedChild;
      return _withDestinationBackdrop(
        context,
        const AbsorbPointer(
          key: Key('workoutReducedMotionExitBlocker'),
          absorbing: true,
          child: SizedBox.expand(),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _sheet,
      child: scopedChild,
      builder: (context, child) {
        final playerExpansionActive =
            widget.expandFromMiniPlayer && !_playerExpansionFinished;
        if (_sheet.value > 0 || playerExpansionActive) {
          if (MediaQuery.sizeOf(context).width >=
              ResponsiveCenter.wideBreakpoint) {
            return _withDestinationBackdrop(
              context,
              _desktopDock(
                context,
                child!,
                AlwaysStoppedAnimation(1 - _sheet.value),
                applyCurve: false,
              ),
            );
          }
          return _withDestinationBackdrop(
            context,
            _mobileSheet(
              context,
              child!,
              _sheet.value,
              alignToPlayerBoundary: playerExpansionActive,
            ),
          );
        }

        final anim = widget.animation;
        if (widget.expandFromMiniPlayer &&
            anim.status != AnimationStatus.reverse &&
            anim.status != AnimationStatus.dismissed) {
          return _withDestinationBackdrop(context, child!);
        }
        if (anim.isCompleted) return _withDestinationBackdrop(context, child!);
        if (!_persistentPlayerRun) return appFadeSlideTransition(child!, anim);

        if (MediaQuery.sizeOf(context).width >=
            ResponsiveCenter.wideBreakpoint) {
          return _withDestinationBackdrop(
            context,
            _desktopDock(context, child!, anim),
          );
        }

        final curved = CurvedAnimation(
          parent: anim,
          curve: AppMotion.persistentPlayerCurve,
          reverseCurve: AppMotion.persistentPlayerCurve,
        );
        return AnimatedBuilder(
          key: const Key('workoutPlayerSheetTransition'),
          animation: curved,
          builder: (context, _) => _withDestinationBackdrop(
            context,
            _mobileSheet(context, child!, 1 - curved.value),
          ),
        );
      },
    );
  }

  Widget _withDestinationBackdrop(BuildContext context, Widget sheet) {
    // A normally-pushed workout already has the real app shell painted below
    // this non-opaque route. Let that exact destination show through while the
    // user drags; covering it with a surface-coloured facsimile creates a grey
    // flash on web and makes the interaction feel disconnected on iOS.
    //
    // Keep the lightweight fallback for direct/deep-linked workouts and for
    // workouts pushed from a root overlay, where revealing the predecessor
    // would expose the wrong destination instead of the compact player.
    if (_hasShellDestination(context)) return sheet;

    final isWide =
        MediaQuery.sizeOf(context).width >= ResponsiveCenter.wideBreakpoint;
    final destinationIsRevealing =
        _reduceMotionExitInFlight ||
        _sheet.value > 0 ||
        !widget.animation.isCompleted;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: TickerMode(
            enabled: destinationIsRevealing,
            child: IgnorePointer(
              child: _WorkoutMinimizeDestinationBackdrop(
                isWide: isWide,
                desktopTopChromeKey: _fallbackDesktopTopChromeKey,
                mobileBottomChromeKey: _fallbackMobileBottomChromeKey,
              ),
            ),
          ),
        ),
        sheet,
      ],
    );
  }

  bool _hasShellDestination(BuildContext context) {
    final cached = _minimizeDestinationIsShell;
    if (cached != null) return cached;
    final route = ModalRoute.of(context);
    if (route == null || route.isFirst) return false;
    return routeObserver.predecessorNameOf(route) == appShellRouteName;
  }

  Widget _mobileSheet(
    BuildContext context,
    Widget child,
    double rawProgress, {
    bool alignToPlayerBoundary = false,
  }) {
    final progress = rawProgress.clamp(0.0, 1.0);
    final height = MediaQuery.sizeOf(context).height;
    final landingChromeHeight =
        AppShell.mobileBottomChromeHeight ??
        _fallbackMobileBottomChromeHeight ??
        ActiveWorkoutBanner.mobileLandingHeight(context) +
            _mobileNavigationHeight +
            MediaQuery.viewPaddingOf(context).bottom;
    final travelDistance = alignToPlayerBoundary
        ? (height - landingChromeHeight).clamp(0.0, height)
        : height;
    final landingReveal = alignToPlayerBoundary
        ? landingChromeHeight * progress
        : (height * progress).clamp(0.0, landingChromeHeight);
    final colors = Theme.of(context).colorScheme;

    return AbsorbPointer(
      key: const Key('workoutPlayerSheetInputBlocker'),
      absorbing: progress > 0,
      child: ClipRect(
        key: const Key('workoutPlayerLandingClip'),
        clipper: _WorkoutLandingClipper(bottomInset: landingReveal),
        child: Stack(
          children: [
            Transform.translate(
              key: const Key('workoutPlayerSheet'),
              offset: Offset(0, travelDistance * progress),
              // Keep one square player layer fully rendered for the complete
              // translation. Corner morphing makes the route read as a modal
              // card, while fading exposes a blank grey sheet near landing.
              child: ColoredBox(color: colors.surface, child: child),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopDock(
    BuildContext context,
    Widget child,
    Animation<double> animation, {
    bool applyCurve = true,
  }) {
    final motion = applyCurve
        ? CurvedAnimation(
            parent: animation,
            curve: AppMotion.persistentPlayerCurve,
            reverseCurve: AppMotion.persistentPlayerCurve,
          )
        : animation;
    final position = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(motion);
    final dockBoundary =
        AppShell.desktopTopChromeHeight ??
        _fallbackDesktopTopChromeHeight ??
        ActiveWorkoutBanner.mobileLandingHeight(context) + 16;
    return AbsorbPointer(
      key: const Key('workoutDesktopDockInputBlocker'),
      absorbing: !animation.isCompleted,
      child: ClipRect(
        key: const Key('workoutDesktopDockClip'),
        clipper: _WorkoutDesktopDockClipper(topInset: dockBoundary),
        child: SlideTransition(
          key: const Key('workoutDesktopDockTransition'),
          position: position,
          child: child,
        ),
      ),
    );
  }

  double? get _fallbackDesktopTopChromeHeight {
    final renderBox =
        _fallbackDesktopTopChromeKey.currentContext?.findRenderObject()
            as RenderBox?;
    return renderBox?.hasSize == true ? renderBox!.size.height : null;
  }

  double? get _fallbackMobileBottomChromeHeight {
    final renderBox =
        _fallbackMobileBottomChromeKey.currentContext?.findRenderObject()
            as RenderBox?;
    return renderBox?.hasSize == true ? renderBox!.size.height : null;
  }
}

class _WorkoutDesktopDockClipper extends CustomClipper<Rect> {
  const _WorkoutDesktopDockClipper({required this.topInset});

  final double topInset;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    topInset.clamp(0.0, size.height),
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_WorkoutDesktopDockClipper oldClipper) =>
      oldClipper.topInset != topInset;
}

class _WorkoutLandingClipper extends CustomClipper<Rect> {
  const _WorkoutLandingClipper({required this.bottomInset});

  final double bottomInset;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    0,
    0,
    size.width,
    (size.height - bottomInset).clamp(0.0, size.height),
  );

  @override
  bool shouldReclip(_WorkoutLandingClipper oldClipper) =>
      oldClipper.bottomInset != bottomInset;
}

class _WorkoutMinimizeDestinationBackdrop extends StatelessWidget {
  const _WorkoutMinimizeDestinationBackdrop({
    required this.isWide,
    required this.desktopTopChromeKey,
    required this.mobileBottomChromeKey,
  });

  final bool isWide;
  final GlobalKey desktopTopChromeKey;
  final GlobalKey mobileBottomChromeKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!GetIt.instance.isRegistered<WorkoutRepository>()) {
      return const SizedBox.shrink(
        key: Key('workoutMinimizeDestinationBackdrop'),
      );
    }
    if (isWide) {
      return ColoredBox(
        key: const Key('workoutMinimizeDestinationBackdrop'),
        color: colors.surface,
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              ShellNavigationRail(
                key: const Key('workoutMinimizeFallbackRail'),
                index: 0,
                extended:
                    MediaQuery.sizeOf(context).width >=
                    AppShell.extendedRailBreakpoint,
                onSelect: (_) {},
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    KeyedSubtree(
                      key: const Key('workoutMinimizeFallbackTopChrome'),
                      child: Column(
                        key: desktopTopChromeKey,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Padding(
                            padding: EdgeInsets.only(top: AppSpacing.x1),
                            child: PendingProposalBanner(),
                          ),
                          Padding(
                            padding: EdgeInsets.only(top: AppSpacing.x1),
                            child: ActiveWorkoutBanner(),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      key: const Key('workoutMinimizeDestinationBackdrop'),
      color: colors.surface,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Column(
              key: mobileBottomChromeKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                const PendingProposalBanner(includeBottomSafeArea: false),
                const ActiveWorkoutBanner(includeBottomSafeArea: false),
                ShellBottomNav(currentIndex: 0, onTap: (_) {}),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
