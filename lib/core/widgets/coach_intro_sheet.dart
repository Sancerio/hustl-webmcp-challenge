import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

// In-memory guard so two coach cards mounting in the same frame can't both fire
// the auto-show before the persisted flag has been written.
bool _coachIntroShownThisSession = false;

/// Resets the in-memory once-per-session guard. Test-only — lets a widget test
/// exercise the first-time auto-intro path deterministically across cases.
@visibleForTesting
void debugResetCoachIntroSessionGuard() {
  _coachIntroShownThisSession = false;
}

/// Proactively introduce the Coach ONCE — the first time a coach card appears
/// anywhere. Gated by a persisted flag plus a session guard, and wrapped so a
/// missing-prefs test environment simply skips it. Safe to call from every
/// [CoachCard] post-frame.
Future<void> maybeAutoShowCoachIntro(BuildContext context) async {
  if (_coachIntroShownThisSession) return;
  try {
    final prefs = PreferencesService();
    if (await prefs.getCoachIntroSeen()) {
      _coachIntroShownThisSession = true;
      return;
    }
    _coachIntroShownThisSession = true;
    await prefs.setCoachIntroSeen(true);
  } catch (_) {
    // No prefs available (e.g. a widget test without a SharedPreferences mock):
    // don't introduce, don't crash.
    _coachIntroShownThisSession = true;
    return;
  }
  if (!context.mounted) return;
  await showCoachIntro(context);
}

/// The "Meet your Coach" explainer — also reachable any time by tapping the
/// "Coach" eyebrow on any [CoachCard].
Future<void> showCoachIntro(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) => const _CoachIntroSheet(),
  );
}

class _CoachIntroSheet extends StatelessWidget {
  const _CoachIntroSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x3,
          AppSpacing.x2,
          AppSpacing.x3,
          AppSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: AppColors.accentElectricBlue,
                ),
                const SizedBox(width: AppSpacing.x1),
                Text('Meet your Coach', style: theme.textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.x1 + 4),
            Text(
              'Your Coach turns what you log into simple, plain-language guidance '
              '— across training, nutrition and recovery. Every coach card has the '
              'same three parts:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            const _IntroPoint(
              icon: Icons.flag_outlined,
              title: 'What to do',
              detail: 'One clear next step.',
            ),
            const _IntroPoint(
              icon: Icons.lightbulb_outline,
              title: 'Why',
              detail: 'The reason behind it, drawn from your own data.',
            ),
            const _IntroPoint(
              icon: Icons.signal_cellular_alt,
              title: 'How sure',
              detail: 'A confidence cue, so you know when it’s still learning.',
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'It’s guidance from your activity and logs — not medical advice.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPoint extends StatelessWidget {
  const _IntroPoint({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
