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
    final compact = MediaQuery.sizeOf(context).width < 900;
    final content = SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1220),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 28,
              compact ? 18 : 26,
              compact ? 16 : 28,
              compact ? 92 : 36,
            ),
            child: child,
          ),
        ),
      ),
    );

    if (compact) {
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              const _Mark(),
              const SizedBox(width: 10),
              Text(_title(path)),
            ],
          ),
          actions: const [
            Padding(padding: EdgeInsets.only(right: 16), child: HustlAvatar()),
          ],
        ),
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (index) => context.go(destinations[index].$3),
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: Icon(destination.$2),
                selectedIcon: Icon(destination.$2, color: hustleBlue),
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
            width: 214,
            decoration: const BoxDecoration(
              color: hustleSurface,
              border: Border(right: BorderSide(color: hustleBorder)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(22, 22, 22, 30),
                    child: Row(
                      children: [
                        _Mark(),
                        SizedBox(width: 10),
                        Text(
                          'Hustl',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var index = 0; index < destinations.length; index++)
                    _RailDestination(
                      label: destinations[index].$1,
                      icon: destinations[index].$2,
                      selected: selected == index,
                      onTap: () => context.go(destinations[index].$3),
                    ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      children: [
                        HustlAvatar(),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Athlete',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Demo profile',
                                style: TextStyle(
                                  color: hustleMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
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

  String _title(String path) {
    if (path.startsWith('/health')) return 'Biology';
    if (path.startsWith('/nutrition')) return 'Nutrition';
    if (path.startsWith('/proposals')) return 'AI activity';
    if (path.startsWith('/templates')) return 'Templates';
    return 'Train';
  }
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: hustleText,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.bolt_rounded, color: hustleCanvas, size: 21),
  );
}

class _RailDestination extends StatelessWidget {
  const _RailDestination({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: Material(
      color: selected ? hustleSurfaceHigh : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: selected ? hustleText : hustleMuted, size: 20),
              const SizedBox(width: 13),
              Text(
                label,
                style: TextStyle(
                  color: selected ? hustleText : hustleMuted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
