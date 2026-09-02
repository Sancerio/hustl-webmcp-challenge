import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design.dart';

class EvaluatorShell extends StatelessWidget {
  const EvaluatorShell({super.key, required this.child});

  final Widget child;

  static const destinations = [
    ('Train', Icons.fitness_center_rounded, '/'),
    ('Recover', Icons.favorite_outline_rounded, '/health'),
    ('Nutrition', Icons.restaurant_rounded, '/nutrition'),
    ('Coach', Icons.forum_outlined, '/proposals'),
    ('Templates', Icons.view_list_outlined, '/templates'),
  ];

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selected = _selectedIndex(path);
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1060),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, narrow ? 20 : 36, 20, 32),
            child: child,
          ),
        ),
      ),
    );

    if (narrow) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: canvas,
          title: const _Brand(),
          centerTitle: false,
        ),
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (index) => context.go(destinations[index].$3),
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: Icon(destination.$2),
                label: destination.$1,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 220,
            color: Colors.white,
            child: SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 28),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Brand(),
                    ),
                  ),
                  Expanded(
                    child: NavigationRail(
                      backgroundColor: Colors.white,
                      extended: true,
                      selectedIndex: selected,
                      labelType: NavigationRailLabelType.none,
                      onDestinationSelected: (index) =>
                          context.go(destinations[index].$3),
                      destinations: [
                        for (final destination in destinations)
                          NavigationRailDestination(
                            icon: Icon(destination.$2),
                            label: Text(destination.$1),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  int _selectedIndex(String path) {
    if (path.startsWith('/health')) return 1;
    if (path.startsWith('/nutrition')) return 2;
    if (path.startsWith('/proposals')) return 3;
    if (path.startsWith('/templates')) return 4;
    return 0;
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
        ),
      ),
      SizedBox(width: 10),
      Text(
        'Hustl',
        style: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
      ),
    ],
  );
}
