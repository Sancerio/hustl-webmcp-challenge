import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state_guest.dart';
import '../../../auth/presentation/widgets/account_sheet.dart';
import '../../domain/onboarding_telemetry.dart';

/// Value-timed "save your progress" upgrade block for the first-win summary.
///
/// Shown ONLY while the user is a guest (derived from [AuthBloc] state via the
/// shared [AuthStateGuestX.isGuest] source of truth) — the moment of peak value,
/// right after the first logged session. Wired to the real sign-in entry
/// ([showLoginSheet]); collapses to nothing once the user is signed in.
class SaveProgressUpgradeCard extends StatelessWidget {
  const SaveProgressUpgradeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (!state.isGuest) return const SizedBox.shrink();
        OnboardingTelemetry.instance.upgradePromptShown();

        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return Container(
          // Owns its trailing rhythm so the host can drop it inline and the gap
          // disappears with the card when the user is signed in.
          margin: const EdgeInsets.only(bottom: AppSpacing.x4),
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Semantics(
                    label: 'Back up your progress',
                    child: Icon(
                      Icons.cloud_sync_outlined,
                      size: 22,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Expanded(
                    child: Text(
                      'Save your progress',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                'Sign in to back up your training and sync across your devices. '
                'You can keep going as a guest.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    OnboardingTelemetry.instance.upgradeLinked();
                    // ignore: discarded_futures
                    showLoginSheet(context);
                  },
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: const Text('Sign in'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.controlRadius,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
