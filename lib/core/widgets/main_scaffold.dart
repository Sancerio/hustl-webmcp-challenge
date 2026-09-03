import 'package:flutter/material.dart';

import 'responsive_center.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.drawer,
    this.scaffoldKey,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final Widget? drawer;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: scaffoldKey,
    appBar: appBar,
    drawer: drawer,
    floatingActionButton: floatingActionButton,
    floatingActionButtonLocation: floatingActionButtonLocation,
    backgroundColor: backgroundColor,
    body: ResponsiveCenter(
      maxContentWidth: 720,
      wideMaxWidth: 1200,
      child: child,
    ),
  );
}
