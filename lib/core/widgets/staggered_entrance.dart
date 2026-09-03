import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme/app_motion.dart';

/// Wraps a list of children in a staggered fade-and-rise entrance per the
/// motion spec: 40ms interval, 14px rise + fade-in, at most 8 items animated
/// (the rest appear instantly), total sequence <= 400ms.
///
/// The sequence plays only on the first build of a given [animationKey] per app
/// session; revisits render the children statically. Honours
/// `MediaQuery.disableAnimations`.
class StaggeredEntrance extends StatelessWidget {
  const StaggeredEntrance({
    super.key,
    required this.animationKey,
    required this.children,
  });

  /// Stable identifier for the screen/section. Used to ensure the entrance
  /// plays once per app session.
  final String animationKey;

  final List<Widget> children;

  /// Keys whose entrance has already played this app session.
  static final Set<String> _played = <String>{};

  /// Resets the played-key registry. Intended for tests only.
  @visibleForTesting
  static void resetForTest() => _played.clear();

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final alreadyPlayed = _played.contains(animationKey);

    // An entrance is decorative polish; it must never gate content visibility.
    // flutter_animate renders each child at its `begin` state (opacity 0, plus
    // the rise offset) until that child's controller has ticked to completion.
    // If tickers are muted for this subtree (`TickerMode.of == false`) those
    // controllers can never advance, so the children would stay invisible while
    // still occupying scroll space — the "content reserves space but paints
    // blank" failure. Render the static column in that case so content always
    // paints.
    final tickerEnabled = TickerMode.of(context);

    if (reduceMotion || alreadyPlayed || !tickerEnabled) {
      // If we're skipping the entrance because tickers are muted, mark the key
      // as played so a later ticker-enable rebuild keeps the content static
      // instead of remounting the already-visible children into a fresh
      // animation (which flutter_animate can leave stuck at opacity 0). Losing
      // the one-time entrance polish for this screen is a fair trade for never
      // hiding content.
      if (!tickerEnabled) _played.add(animationKey);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    // Mark as played for the rest of the session.
    _played.add(animationKey);

    final animated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i >= AppMotion.staggerMaxItems) {
        animated.add(children[i]);
        continue;
      }
      final delay = AppMotion.staggerInterval * i;
      animated.add(
        children[i]
            .animate(delay: delay)
            .fadeIn(
              duration: AppMotion.staggerItem,
              curve: AppMotion.emphasizedCurve,
            )
            .move(
              begin: const Offset(0, AppMotion.staggerRise),
              end: Offset.zero,
              duration: AppMotion.staggerItem,
              curve: AppMotion.emphasizedCurve,
            ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: animated,
    );
  }
}
