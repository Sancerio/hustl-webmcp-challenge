import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/auth_user.dart';
import '../bloc/auth_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../domain/services/auth_redirect_service.dart';
import '../../../../core/navigation/current_route_service.dart';
import '../../../../app/navigation/app_routes.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/widgets/legal_links_text.dart';
import 'sign_out_confirmation.dart';
import 'package:go_router/go_router.dart';

class AccountSheet extends StatelessWidget {
  const AccountSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x3,
        ),
        child: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthFailure) {
              HustlSnack.show(
                context,
                state.message,
                variant: HustlSnackVariant.error,
              );
            } else if (state is AuthAuthenticated) {
              // Pop using GoRouter so the context is never disposed before pop.
              final canPop = context.canPop();
              if (canPop) context.pop();
            }
          },
          builder: (context, state) {
            if (state is AuthLoading || state is AuthHydrating) {
              return const _AccountSheetSkeleton();
            }

            if (state is AuthAuthenticated) {
              final user = state.user;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: user.photoUrl != null
                            ? NetworkImage(user.photoUrl!)
                            : null,
                        child: user.photoUrl == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName ?? 'Account',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (user.email != null)
                              Text(
                                user.email!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            Text(
                              'Signed in with ${_providerLabel(user.provider)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        // Capture router before popping to avoid disposed context.
                        final router = GoRouter.of(context);
                        if (context.canPop()) context.pop();
                        await router.push('/account');
                      },
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: const Text('Manage account'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // Capture the bloc before the async confirmation gap.
                        final authBloc = context.read<AuthBloc>();
                        if (await confirmSignOut(context)) {
                          authBloc.add(AuthSignOutRequested());
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                  ),
                ],
              );
            }

            // Guest / unauthenticated
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Semantics(
                      label: 'Hustl app icon',
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/icon/hustl-icon.png',
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome to Hustl',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Currently using as guest',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x2),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.x2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Semantics(
                            label: 'Cloud sync for data backup',
                            child: Icon(
                              Icons.cloud_sync_outlined,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.x1),
                          Text(
                            'Sign in to sync your data',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        'Your workouts are stored locally. Sign in to back up and sync across all your devices.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.8,
                          ),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                // Apple sign-in is shown only on iOS, above Google at equal
                // prominence (App Store guideline 4.8 when offering Google).
                if (_showAppleButton) ...[
                  const _AppleSignInButton(),
                  const SizedBox(height: AppSpacing.x1),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<AuthBloc>().add(
                      AuthSignInWithGoogleRequested(),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: AppSpacing.x2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                    icon: const ExcludeSemantics(
                      child: Icon(Icons.account_circle_outlined, size: 20),
                    ),
                    label: const Text(
                      'Sign in with Google',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                const Center(
                  child: LegalLinksText(
                    leading: 'Read how we handle your data in our',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _providerLabel(AuthProvider provider) {
    switch (provider) {
      case AuthProvider.google:
        return 'Google';
      case AuthProvider.apple:
        return 'Apple';
      case AuthProvider.guest:
        return 'Guest';
    }
  }

  /// Apple sign-in is iOS-only. We gate on the platform (never web) so the
  /// button never renders where the native flow is unavailable.
  bool get _showAppleButton =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

/// iOS-only "Sign in with Apple" CTA. Styled to mirror the Google button beneath
/// it (same outlined shape, padding, and radius) so the two read at equal
/// prominence, and dispatches [AuthSignInWithAppleRequested].
class _AppleSignInButton extends StatelessWidget {
  const _AppleSignInButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () =>
            context.read<AuthBloc>().add(AuthSignInWithAppleRequested()),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: AppSpacing.x2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        icon: const ExcludeSemantics(child: Icon(Icons.apple, size: 22)),
        label: const Text(
          'Sign in with Apple',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// Skeleton placeholder that mirrors the authenticated account layout
/// (avatar circle + name/email lines) while auth state hydrates.
class _AccountSheetSkeleton extends StatelessWidget {
  const _AccountSheetSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppSkeleton.circle(size: 56),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 140, height: AppSpacing.x2),
                  SizedBox(height: AppSpacing.x1),
                  AppSkeleton(width: 200, height: AppSpacing.x2),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<T?> showLoginSheet<T>(BuildContext context) {
  // Prefer globally tracked current route; fall back safely if DI is incomplete.
  final getIt = GetIt.instance;
  String afterLoginRoute;
  if (getIt.isRegistered<CurrentRouteService>()) {
    try {
      afterLoginRoute = getIt<CurrentRouteService>().getAllowedRoute();
    } catch (_) {
      afterLoginRoute =
          ModalRoute.of(context)?.settings.name ??
          AppRoutes.defaultAfterLoginRoute;
    }
  } else {
    afterLoginRoute =
        ModalRoute.of(context)?.settings.name ??
        AppRoutes.defaultAfterLoginRoute;
  }

  if (getIt.isRegistered<AuthRedirectService>()) {
    getIt<AuthRedirectService>().setAfterLoginRoute(afterLoginRoute);
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // Consistent dismiss affordance — every other app sheet shows a drag
    // handle; this one was the lone exception.
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (_) => const AccountSheet(),
  );
}
