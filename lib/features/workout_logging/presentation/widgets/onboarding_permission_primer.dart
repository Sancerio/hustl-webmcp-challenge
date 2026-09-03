import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

/// The user's response to an [OnboardingPermissionPrimer].
///
/// [dismissed] (a swipe-down or barrier tap) is deliberately distinct from
/// [decline] ("Not now"): callers should only burn a one-shot "seen" flag on an
/// explicit [allow] or [decline], never on a [dismissed], so an accidental
/// dismissal doesn't silently consume the single OS prompt opportunity.
enum PermissionPrimerChoice { allow, decline, dismissed }

/// A reusable in-context rationale sheet shown BEFORE an OS permission prompt.
/// Explains why the permission helps, then lets the user opt in or decline.
/// Resolves to [PermissionPrimerChoice.allow] only when the user taps the allow
/// action; "Not now" yields [PermissionPrimerChoice.decline] and a swipe/barrier
/// dismissal yields [PermissionPrimerChoice.dismissed].
class OnboardingPermissionPrimer extends StatelessWidget {
  const OnboardingPermissionPrimer({
    super.key,
    required this.assetIcon,
    required this.title,
    required this.message,
    this.allowLabel = 'Allow',
    this.notNowLabel = 'Not now',
  });

  final String assetIcon;
  final String title;
  final String message;
  final String allowLabel;
  final String notNowLabel;

  static Future<PermissionPrimerChoice> show(
    BuildContext context, {
    required String assetIcon,
    required String title,
    required String message,
    String allowLabel = 'Allow',
    String notNowLabel = 'Not now',
  }) async {
    final result = await showModalBottomSheet<PermissionPrimerChoice>(
      context: context,
      // Push on the root navigator so this sheet does not linger on the active
      // tab branch navigator after a tab switch (which would leave the tab
      // root's `canPop()` true and flip its avatar to a back chevron).
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (_) => OnboardingPermissionPrimer(
        assetIcon: assetIcon,
        title: title,
        message: message,
        allowLabel: allowLabel,
        notNowLabel: notNowLabel,
      ),
    );
    return result ?? PermissionPrimerChoice.dismissed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.x3,
        AppSpacing.x1,
        AppSpacing.x3,
        AppSpacing.x4 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _SoftGlyphHolder(asset: assetIcon, color: colors.primary),
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Semantics(
            button: true,
            label: allowLabel,
            child: FilledButton(
              onPressed: () {
                final router = GoRouter.of(context);
                if (router.canPop()) router.pop(PermissionPrimerChoice.allow);
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.controlRadius,
                ),
              ),
              child: Text(allowLabel),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Semantics(
            button: true,
            label: notNowLabel,
            child: TextButton(
              onPressed: () {
                final router = GoRouter.of(context);
                if (router.canPop()) {
                  router.pop(PermissionPrimerChoice.decline);
                }
              },
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(notNowLabel),
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) return content;
    return _EntranceAnimator(child: content);
  }
}

/// A softly held, blue-tinted circular glyph holder, matching the shared
/// empty-state visual language.
class _SoftGlyphHolder extends StatelessWidget {
  const _SoftGlyphHolder({required this.asset, required this.color});

  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 88,
        height: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.06),
        ),
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
          ),
          child: HustlIcon(asset: asset, size: 32, color: color),
        ),
      ),
    );
  }
}

/// A calm fade + rise entrance for sheet content.
class _EntranceAnimator extends StatefulWidget {
  const _EntranceAnimator({required this.child});

  final Widget child;

  @override
  State<_EntranceAnimator> createState() => _EntranceAnimatorState();
}

class _EntranceAnimatorState extends State<_EntranceAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.enterCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
