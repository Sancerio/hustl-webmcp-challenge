import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';

/// Shows a one-time consent gate before any AI meal capture. Returns `true`
/// once the user has agreed (now or previously), or `false` if they declined.
///
/// If consent was already granted, this returns immediately without any UI.
Future<bool> ensureAiCaptureConsent(BuildContext context) async {
  final prefs = GetIt.instance<PreferencesService>();
  if (await prefs.getAiCaptureConsent()) return true;
  if (!context.mounted) return false;

  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) => const _AiCaptureConsentSheet(),
  );
  return agreed ?? false;
}

class _AiCaptureConsentSheet extends StatelessWidget {
  const _AiCaptureConsentSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.x2,
        right: AppSpacing.x2,
        top: AppSpacing.x2,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.x3,
      ),
      child: ResponsiveCenter(
        maxContentWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Use AI to estimate macros?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Hustl uses Google Gemini, a third-party AI service, to estimate '
              'macros from your photo or meal description. What you send is '
              'processed by Google for this estimate and is not stored '
              'afterward. You can turn this off anytime in Settings.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            FilledButton(
              onPressed: () async {
                final router = GoRouter.of(context);
                await GetIt.instance<PreferencesService>().setAiCaptureConsent(
                  true,
                );
                router.pop(true);
              },
              child: const Text('Continue'),
            ),
            const SizedBox(height: AppSpacing.x1),
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
