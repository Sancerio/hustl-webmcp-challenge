import 'package:flutter/material.dart';

import '../../../../core/widgets/hustl_icon.dart';
import '../../../../core/widgets/responsive_center.dart';
import 'active/soft_holder_button.dart';

/// Soft Holders row for the active-workout app bar (Wave I): the rest control
/// (idle pill or running chip, supplied by the screen), the notes holder, and
/// the responsive minimize control. Finishing the workout lives in the sticky
/// bottom CTA.
class ActiveWorkoutAppBarActions extends StatelessWidget {
  final Widget restControl;
  final bool hasNotes;
  final VoidCallback onMinimize;
  final VoidCallback onOpenNotes;

  const ActiveWorkoutAppBarActions({
    super.key,
    required this.restControl,
    required this.hasNotes,
    required this.onMinimize,
    required this.onOpenNotes,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        restControl,
        const SizedBox(width: 8),
        SoftHolderButton(
          asset: 'assets/icons/ic_note.svg',
          showDot: hasNotes,
          semanticsLabel: hasNotes ? 'Edit notes' : 'Add notes',
          tooltip: hasNotes ? 'Edit notes' : 'Add notes',
          onTap: onOpenNotes,
        ),
        const SizedBox(width: 8),
        _MinimizeControl(onTap: onMinimize),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// Touch uses the music-player convention: a compact downward chevron paired
/// with the sheet's drag handle. Wide/pointer layouts keep an explicit label
/// because there is no direct-manipulation gesture to discover.
class _MinimizeControl extends StatelessWidget {
  const _MinimizeControl({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < ResponsiveCenter.wideBreakpoint) {
      return SoftHolderButton(
        asset: 'assets/icons/ic_minimize.svg',
        semanticsLabel: 'Minimize workout',
        tooltip: 'Minimize workout',
        onTap: onTap,
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Minimize workout',
      child: Tooltip(
        message: 'Minimize workout',
        child: Material(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                height: 40,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HustlIcon(
                      asset: 'assets/icons/ic_minimize.svg',
                      size: 18,
                      color: colors.onSurface,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Minimize',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
