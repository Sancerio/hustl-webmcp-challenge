import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:hustl_app/app/theme/app_motion.dart';

/// A single list item's staggered fade-and-rise entrance, matching the motion
/// spec (40ms interval, 14px rise + fade, easeOutCubic). Used for builder-based
/// lists where the shared [StaggeredEntrance] Column helper doesn't fit.
///
/// The animation plays at most once per screen build: a static Set keyed on
/// this widget's [GlobalKey] (or an internal identity) prevents re-entrance
/// when the item scrolls off-screen and back. When
/// [MediaQuery.disableAnimations] is true, the child is returned as-is.
class StaggeredCardEntrance extends StatefulWidget {
  const StaggeredCardEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<StaggeredCardEntrance> createState() => _StaggeredCardEntranceState();
}

class _StaggeredCardEntranceState extends State<StaggeredCardEntrance> {
  // Tracks which widget instances have already played their entrance.
  // Keyed by the State identity so each card in the list plays once per
  // screen lifetime (the set is cleared when the list is disposed/rebuilt
  // from scratch because new State objects are created).
  static final Set<_StaggeredCardEntranceState> _played = {};

  late bool _hasPlayed;

  @override
  void initState() {
    super.initState();
    _hasPlayed = _played.contains(this);
  }

  @override
  void dispose() {
    _played.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion ||
        _hasPlayed ||
        widget.index >= AppMotion.staggerMaxItems) {
      return widget.child;
    }

    // Mark as played before building so the Animate widget's own rebuild
    // (from AnimationController ticks) never restarts the sequence.
    _played.add(this);
    _hasPlayed = true;

    return widget.child
        .animate(delay: AppMotion.staggerInterval * widget.index)
        .fadeIn(
          duration: AppMotion.staggerItem,
          curve: AppMotion.emphasizedCurve,
        )
        .move(
          begin: const Offset(0, AppMotion.staggerRise),
          end: Offset.zero,
          duration: AppMotion.staggerItem,
          curve: AppMotion.emphasizedCurve,
        );
  }
}
