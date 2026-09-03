import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';

class SetRowCompletionButton extends StatelessWidget {
  final int setIndex;
  final bool isCompleted;
  final bool isPr;
  final VoidCallback onComplete;
  final VoidCallback onUncomplete;

  const SetRowCompletionButton({
    super.key,
    required this.setIndex,
    required this.isCompleted,
    required this.isPr,
    required this.onComplete,
    required this.onUncomplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Container(
      alignment: Alignment.center,
      width: 34,
      height: 48,
      child: AnimatedSwitcher(
        duration: AppMotion.fast,
        reverseDuration: AppMotion.fast,
        switchInCurve: AppMotion.enterCurve,
        switchOutCurve: AppMotion.exitCurve,
        transitionBuilder: (child, animation) {
          final faded = FadeTransition(opacity: animation, child: child);
          if (reduceMotion) return faded;
          return ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
            child: faded,
          );
        },
        child: isCompleted
            ? Semantics(
                key: ValueKey('set-completion-complete-$isPr'),
                button: true,
                label: isPr
                    ? 'Uncomplete set ${setIndex + 1} (Personal Record)'
                    : 'Uncomplete set ${setIndex + 1}',
                child: Tooltip(
                  message: isPr
                      ? 'Personal Record! Tap to undo completion'
                      : 'Tap to undo completion',
                  preferBelow: false,
                  child: GestureDetector(
                    onTap: onUncomplete,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.tertiary,
                          size: 26,
                        ),
                        if (isPr)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: AppColors.accentWarningAmber,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.surface,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.shadow.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.star,
                                  color: theme.colorScheme.onTertiary,
                                  size: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            : ExcludeFocus(
                key: const ValueKey('set-completion-incomplete'),
                child: IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onComplete,
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.7),
                  splashRadius: 16,
                  tooltip: 'Mark set ${setIndex + 1} as completed',
                ),
              ),
      ),
    );
  }
}
