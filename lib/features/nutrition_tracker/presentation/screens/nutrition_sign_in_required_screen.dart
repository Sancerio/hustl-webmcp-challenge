import 'package:flutter/material.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/widgets/account_sheet.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/hustl_menu_button.dart';

class NutritionSignInRequiredScreen extends StatelessWidget {
  const NutritionSignInRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Nutrition'),
        centerTitle: true,
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.cardRadius,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.restaurant_rounded,
                        size: 30,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Track your nutrition',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to set targets, log meals, and see your macro and '
                      'energy insights — synced across your devices.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    const _NutritionBenefitsRow(),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => showLoginSheet(context),
                        icon: const Icon(Icons.login_outlined, size: 20),
                        label: const Text('Sign in'),
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

/// The three things sign-in unlocks for nutrition, mirroring the account
/// sign-in card's benefit row so the two prompts read as one system.
class _NutritionBenefitsRow extends StatelessWidget {
  const _NutritionBenefitsRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: const Row(
        children: [
          Expanded(
            child: _NutritionBenefit(icon: Icons.flag_outlined, label: 'Targets'),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _NutritionBenefit(
              icon: Icons.pie_chart_outline,
              label: 'Macros',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _NutritionBenefit(
              icon: Icons.insights_outlined,
              label: 'Insights',
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionBenefit extends StatelessWidget {
  const _NutritionBenefit({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class NutritionAuthGate extends StatelessWidget {
  const NutritionAuthGate({
    super.key,
    required this.authenticatedBuilder,
    required this.unauthenticatedBuilder,
  });

  final WidgetBuilder authenticatedBuilder;
  final WidgetBuilder unauthenticatedBuilder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthAuthenticated) {
          return authenticatedBuilder(context);
        }
        if (state is AuthLoading || state is AuthHydrating) {
          return const _NutritionAuthLoadingScreen();
        }
        return unauthenticatedBuilder(context);
      },
    );
  }
}

class _NutritionAuthLoadingScreen extends StatelessWidget {
  const _NutritionAuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Nutrition'),
        centerTitle: true,
      ),
      child: AppSkeleton.lines(semanticsLabel: 'Loading nutrition'),
    );
  }
}
