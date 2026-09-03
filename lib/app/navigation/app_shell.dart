import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/hustl_icon.dart';
import '../../features/ai_proposals/presentation/widgets/pending_proposal_banner.dart';
import '../theme/app_spacing.dart';

class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>() != null;

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = ShellScope(child: navigationShell);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              leading: IconButton(
                tooltip: 'Coach',
                onPressed: () => context.push('/proposals'),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: HustlIcon(
                    asset: 'assets/icons/nav_train.svg',
                    color: Colors.grey,
                  ),
                  label: Text('Train'),
                ),
                NavigationRailDestination(
                  icon: HustlIcon(
                    asset: 'assets/icons/nav_nutrition.svg',
                    color: Colors.grey,
                  ),
                  label: Text('Nutrition'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.x1),
                    child: PendingProposalBanner(),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          const PendingProposalBanner(includeBottomSafeArea: false),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _go,
            destinations: const [
              NavigationDestination(
                icon: HustlIcon(
                  asset: 'assets/icons/nav_train.svg',
                  color: Colors.grey,
                ),
                label: 'Train',
              ),
              NavigationDestination(
                icon: HustlIcon(
                  asset: 'assets/icons/nav_nutrition.svg',
                  color: Colors.grey,
                ),
                label: 'Nutrition',
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Coach',
        onPressed: () => context.push('/proposals'),
        child: const Icon(Icons.auto_awesome_outlined),
      ),
    );
  }
}
