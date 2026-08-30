import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/active_workout_banner.dart';
import '../../core/widgets/hustl_icon.dart';
import '../../features/ai_proposals/presentation/widgets/pending_proposal_banner.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'shell_bottom_nav.dart';

/// Inherited marker placed by [AppShell]. Lets nested [MainScaffold]s know they
/// are rendered inside the shell so they suppress their own nav chrome (the
/// shell owns the single nav bar + banner + rail).
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>() != null;

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

/// The single application shell. Hosts the [StatefulNavigationShell] (the five
/// indexed-stack tab branches), and instantiates the bottom nav bar, the
/// active-workout banner, and the desktop [NavigationRail] exactly once.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  static const double extendedRailBreakpoint = 1200;

  /// Rendered desktop chrome above the branch body.
  ///
  /// This is measured rather than inferred because the optional proposal
  /// banner and accessibility text scaling both change the player's position.
  static final GlobalKey desktopTopChromeKey = GlobalKey(
    debugLabel: 'appShellDesktopTopChrome',
  );

  static double? get desktopTopChromeHeight {
    final renderBox =
        desktopTopChromeKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.hasSize == true ? renderBox!.size.height : null;
  }

  /// Rendered mobile chrome below the branch body.
  ///
  /// This includes the optional proposal banner, active-workout player, and
  /// bottom navigation so route handoffs can clip against the real layout.
  static final GlobalKey mobileBottomChromeKey = GlobalKey(
    debugLabel: 'appShellMobileBottomChrome',
  );

  static double? get mobileBottomChromeHeight {
    final renderBox =
        mobileBottomChromeKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.hasSize == true ? renderBox!.size.height : null;
  }

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      // Tapping the active tab returns to its initial route, matching the old
      // bottom-nav behaviour.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bool isWide = width >= 900;
    final bool extendRail = width >= extendedRailBreakpoint;
    final int index = navigationShell.currentIndex;

    final Widget body = ShellScope(
      child: _BranchFadeThrough(index: index, child: navigationShell),
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            ShellNavigationRail(
              index: index,
              extended: extendRail,
              onSelect: _goBranch,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Column(
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
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: Column(
        key: mobileBottomChromeKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PendingProposalBanner(includeBottomSafeArea: false),
          const ActiveWorkoutBanner(includeBottomSafeArea: false),
          ShellBottomNav(currentIndex: index, onTap: _goBranch),
        ],
      ),
    );
  }
}

/// A clean fade-in for shell branch switches.
///
/// The underlying [StatefulNavigationShell] keeps every branch mounted in its
/// internal `IndexedStack` and swaps to the new branch *instantly* on an index
/// change — so [widget.child] is already the destination branch when this sees
/// the change. The previous implementation reversed (faded the just-arrived
/// branch back out) then forwarded again, which read as a flash/flicker. We now
/// only ever fade the incoming branch *in* from 0 → 1: no blink, no lost state,
/// no extra shell build. Honours `MediaQuery.disableAnimations` by holding the
/// content fully opaque.
class _BranchFadeThrough extends StatefulWidget {
  const _BranchFadeThrough({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_BranchFadeThrough> createState() => _BranchFadeThroughState();
}

class _BranchFadeThroughState extends State<_BranchFadeThrough>
    with SingleTickerProviderStateMixin {
  // A single, crisp fade-in — fast enough to feel instant, soft enough to
  // avoid a hard cut.
  static const Duration _fadeIn = Duration(milliseconds: 150);

  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _fadeIn,
      value: 1.0,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.enterCurve,
    );
  }

  @override
  void didUpdateWidget(_BranchFadeThrough old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.value = 1.0;
      return;
    }
    // Reset to transparent and fade the (already-swapped) new branch in. No
    // reverse pass, so the destination never blinks out before settling.
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// The desktop navigation chrome shared by the mounted shell and temporary
/// minimize destinations that must visually land on that shell.
class ShellNavigationRail extends StatelessWidget {
  const ShellNavigationRail({
    super.key,
    required this.index,
    required this.extended,
    required this.onSelect,
  });

  final int index;
  final bool extended;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Brand emphasis: the active destination reads in the emerald primary; the
    // rest sit at the muted onSurfaceVariant tone.
    final Color selectedColor = theme.colorScheme.primary;
    final Color unselectedColor = theme.colorScheme.onSurfaceVariant;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.x1),
        IconButton(
          tooltip: 'Account',
          // Push so Account overlays the rail with a back button rather than
          // replacing the whole shell.
          onPressed: () => context.push('/account'),
          icon: const Icon(Icons.account_circle_outlined),
        ),
        const SizedBox(height: AppSpacing.x1),
        Expanded(
          child: NavigationRail(
            selectedIndex: index,
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.selected,
            groupAlignment: -1,
            indicatorColor: selectedColor.withValues(alpha: 0.16),
            destinations: [
              for (final d in kShellDestinations)
                NavigationRailDestination(
                  icon: HustlIcon(
                    asset: d.asset,
                    color: unselectedColor,
                    semanticsLabel: d.label,
                  ),
                  selectedIcon: HustlIcon(
                    asset: d.asset,
                    color: selectedColor,
                    semanticsLabel: d.label,
                  ),
                  label: Text(d.label),
                ),
            ],
            onDestinationSelected: onSelect,
          ),
        ),
      ],
    );
  }
}
