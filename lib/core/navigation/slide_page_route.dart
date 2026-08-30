import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

class SlideFromBottomPageRoute<T> extends PageRouteBuilder<T> {
  SlideFromBottomPageRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: AppMotion.sheet,
        reverseTransitionDuration: AppMotion.sheet,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          // Full-height slide for a natural, predictable movement
          final offsetTween = Tween<Offset>(
            begin: const Offset(0, 1.0),
            end: Offset.zero,
          );
          return SlideTransition(
            position: offsetTween.animate(curved),
            child: child,
          );
        },
      );
}
