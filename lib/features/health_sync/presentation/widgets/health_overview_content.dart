import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../bloc/health_overview_bloc.dart';
import 'health_debug_panel.dart';
import 'health_dashboard_view.dart';
import 'health_overview_empty_state.dart';
import 'health_overview_error_state.dart';
import 'health_sync_warnings_banner.dart';

class HealthOverviewContent extends StatelessWidget {
  const HealthOverviewContent({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HealthOverviewBloc, HealthOverviewState>(
      listenWhen: (previous, current) =>
          current.refreshError != null &&
          previous.refreshError != current.refreshError,
      listener: (context, state) {
        HustlSnack.show(
          context,
          state.refreshError!,
          variant: HustlSnackVariant.warning,
        );
      },
      builder: (context, state) {
        // The screen's SafeArea no longer consumes the bottom inset (the
        // ready dashboard scrolls edge-to-edge under the home indicator), so
        // the non-dashboard states restore it locally to keep their content
        // and buttons clear of the home indicator.
        late final Widget child;
        switch (state.status) {
          case HealthOverviewStatus.initial:
          case HealthOverviewStatus.loading:
            child = const _LoadingState();
            break;
          case HealthOverviewStatus.error:
            child = SafeArea(
              top: false,
              child: HealthOverviewErrorState(message: state.errorMessage),
            );
            break;
          case HealthOverviewStatus.empty:
            child = SafeArea(
              top: false,
              child: HealthOverviewEmptyState(
                lastSyncedAt: state.lastSyncedAt,
                warnings: state.syncWarnings,
                debugPanel: HealthDebugPanel(state: state),
              ),
            );
            break;
          case HealthOverviewStatus.ready:
            child = _ReadyContent(state: state);
            break;
        }

        return AnimatedSwitcher(
          duration: AppMotion.medium,
          switchInCurve: AppMotion.enterCurve,
          switchOutCurve: AppMotion.exitCurve,
          transitionBuilder: appFadeSlideTransition,
          child: KeyedSubtree(
            key: ValueKey<String>(state.status.name),
            child: child,
          ),
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x4,
      ),
      children: const [
        HustlInlineSkeleton(
          padding: EdgeInsets.zero,
          rows: 4,
          semanticsLabel: 'Loading health insights',
        ),
        SizedBox(height: AppSpacing.x3),
        HustlInlineSkeleton(
          padding: EdgeInsets.zero,
          rows: 5,
          semanticsLabel: 'Loading recovery sections',
        ),
      ],
    );
  }
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent({required this.state});

  final HealthOverviewState state;

  @override
  Widget build(BuildContext context) {
    // The recovery-signal prompt lives inside the dashboard's scroll content
    // (see HealthDashboardView) — a pinned slot here reserved a dead strip
    // even when the prompt rendered nothing. Only the warnings banner and the
    // debug panel stay pinned, and the home-indicator inset is applied ONLY
    // when at least one of them is visible: an unconditional inset (or a
    // SafeArea around an always-present zero-height child) would recreate the
    // letterboxed band under the edge-to-edge dashboard.
    final showWarnings = state.syncWarnings.isNotEmpty;
    final showDebugPanel =
        state.loadedFromCache ||
        state.fallbackUsed ||
        state.assumedPermissions ||
        state.rawPermissionResult == null;

    return Column(
      children: [
        Expanded(child: HealthDashboardView(state: state)),
        if (showWarnings)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x1,
              0,
              AppSpacing.x1,
              AppSpacing.x2,
            ),
            child: HealthSyncWarningsBanner(warnings: state.syncWarnings),
          ),
        if (showDebugPanel)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x1,
              0,
              AppSpacing.x1,
              AppSpacing.x2,
            ),
            child: HealthDebugPanel(state: state),
          ),
        if (showWarnings || showDebugPanel)
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}
