import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../data/sources/health_connect_intent_bridge.dart';
import '../../domain/models/recovery_signal_availability.dart';
import '../../domain/repositories/health_metrics_repository.dart';
import '../bloc/health_overview_bloc.dart';
import '../bloc/health_permissions_bloc.dart';
import '../preview/health_overview_preview_repository.dart';
import '../widgets/health_overview_content.dart';
import '../widgets/health_overview_header.dart';
import '../widgets/health_overview_status_views.dart';
import 'connect_health_page.dart';

class HealthOverviewScreen extends StatelessWidget {
  const HealthOverviewScreen({
    super.key,
    this.repositoryOverride,
    this.previewMode = false,
  });

  const HealthOverviewScreen.preview({super.key})
    : repositoryOverride = const PreviewHealthMetricsRepository(),
      previewMode = true;

  final HealthMetricsRepository? repositoryOverride;
  final bool previewMode;

  @override
  Widget build(BuildContext context) {
    final repository = repositoryOverride ?? getIt<HealthMetricsRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<HealthPermissionsBloc>(
          create: (_) =>
              HealthPermissionsBloc(repository)
                ..add(const HealthPermissionsStatusRequested()),
        ),
        BlocProvider<HealthOverviewBloc>(
          create: (_) => HealthOverviewBloc(repository),
        ),
      ],
      child: _HealthOverviewView(
        previewMode: previewMode,
        repository: repository,
      ),
    );
  }
}

class _HealthOverviewView extends StatefulWidget {
  const _HealthOverviewView({
    required this.previewMode,
    required this.repository,
  });

  final bool previewMode;
  final HealthMetricsRepository repository;

  @override
  State<_HealthOverviewView> createState() => _HealthOverviewViewState();
}

class _HealthOverviewViewState extends State<_HealthOverviewView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<HealthPermissionsBloc>().state
          is HealthPermissionsGranted) {
        context.read<HealthOverviewBloc>().add(const HealthOverviewStarted());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Re-check permission status silently so an external grant/revoke in the
    // Health Connect / Apple Health app reflects without flashing the rendered
    // dashboard to a skeleton. Silent means Granted -> Granted produces no
    // emit at all (Equatable), so the Loading -> Granted listener below does
    // NOT re-fire on a routine resume; data freshness is handled by the
    // explicit refresh, which keeps old data visible while it runs.
    final permissions = context.read<HealthPermissionsBloc>();
    permissions.add(const HealthPermissionsStatusRequested(silent: true));
    if (permissions.state is HealthPermissionsGranted) {
      context.read<HealthOverviewBloc>().add(const HealthOverviewRefreshed());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Render in the user's theme — no forced-dark override.
    return BlocListener<HealthPermissionsBloc, HealthPermissionsState>(
      listenWhen: (previous, current) =>
          current is HealthPermissionsGranted &&
          previous is! HealthPermissionsGranted,
      listener: (context, state) {
        context.read<HealthOverviewBloc>().add(const HealthOverviewStarted());
      },
      child: MainScaffold(
        child: SafeArea(
          // The ready dashboard scrolls edge-to-edge under the home indicator
          // (its scroll content carries the bottom safe inset itself). A
          // bottom SafeArea + fixed bottom padding here letterboxed the scroll
          // viewport ~50pt above the physical bottom of the screen, cutting
          // the last visible card and leaving a dead band below it. States
          // that don't scroll edge-to-edge re-apply the bottom inset locally.
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x2,
              AppSpacing.x1,
              AppSpacing.x2,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlocBuilder<HealthPermissionsBloc, HealthPermissionsState>(
                  builder: (context, state) => HealthScreenHeader(
                    status: _headerStatusFor(
                      state,
                      previewMode: widget.previewMode,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                Expanded(
                  child: _HealthPermissionsGate(repository: widget.repository),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

HealthSyncHeaderStatus _headerStatusFor(
  HealthPermissionsState state, {
  required bool previewMode,
}) {
  if (previewMode) return HealthSyncHeaderStatus.preview;
  return switch (state) {
    HealthPermissionsInitial() ||
    HealthPermissionsLoading() => HealthSyncHeaderStatus.checking,
    HealthPermissionsGranted() => HealthSyncHeaderStatus.live,
    HealthPermissionsDenied() => HealthSyncHeaderStatus.notConnected,
    HealthPermissionsUnavailable() => HealthSyncHeaderStatus.mobileRequired,
    HealthPermissionsFailure() => HealthSyncHeaderStatus.unavailable,
    _ => HealthSyncHeaderStatus.unavailable,
  };
}

class _HealthPermissionsGate extends StatelessWidget {
  const _HealthPermissionsGate({required this.repository});

  final HealthMetricsRepository repository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HealthPermissionsBloc, HealthPermissionsState>(
      builder: (context, state) {
        if (state is HealthPermissionsLoading ||
            state is HealthPermissionsInitial) {
          return const HustlInlineSkeleton();
        }
        // The screen's SafeArea no longer consumes the bottom inset (the
        // dashboard draws under the home indicator), so these centered / CTA
        // surfaces restore it locally to keep their content and buttons clear
        // of the home indicator.
        if (state is HealthPermissionsUnavailable) {
          // Don't dead-end on "unsupported device" copy yet: on Android a
          // missing/out-of-date Health Connect reports unavailable too. Probe
          // provider reachability so a needsInstall result can route to the
          // install CTA; only a genuinely unsupported platform stays here.
          return SafeArea(
            top: false,
            child: _UnavailableGate(repository: repository),
          );
        }
        if (state is HealthPermissionsDenied) {
          return SafeArea(
            top: false,
            child: _DeniedConnectView(
              repository: repository,
              permanentlyDenied: state.permanentlyDenied,
            ),
          );
        }
        if (state is HealthPermissionsFailure) {
          return SafeArea(
            top: false,
            child: HealthPermissionsFailureView(message: state.message),
          );
        }

        return const HealthOverviewContent();
      },
    );
  }
}

/// The "service unavailable" surface, made capability-aware. The permissions
/// status reports unavailable both for genuinely unsupported platforms AND for
/// Android where Health Connect is simply missing/out-of-date — and the latter
/// can be fixed by installing it. We probe [getProviderAvailability] to tell
/// the two apart: a [HealthProviderAvailability.needsInstall] result routes to
/// the install CTA, while a genuinely [unsupported] device (or a pending/failed
/// probe) keeps the plain "unsupported device" copy, so it reads as today.
class _UnavailableGate extends StatelessWidget {
  const _UnavailableGate({required this.repository});

  final HealthMetricsRepository repository;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HealthProviderAvailability>(
      future: repository.getProviderAvailability(),
      builder: (context, snapshot) {
        final availability = snapshot.data;
        // Health Connect missing (needsInstall) OR installed-but-out-of-date
        // (needsUpdate) both report the permissions status as unavailable but
        // are fixable via the Play listing, so route both to the setup CTA.
        if (availability == HealthProviderAvailability.needsInstall ||
            availability == HealthProviderAvailability.needsUpdate) {
          return ConnectHealthPage(
            onConnectPressed: () => context.read<HealthPermissionsBloc>().add(
              const HealthPermissionsStatusRequested(),
            ),
            showPermissionInstructions: false,
            providerAvailability: availability!,
            onInstallHealthConnect: () async {
              await repository.installHealthConnect();
              if (context.mounted) {
                context.read<HealthPermissionsBloc>().add(
                  const HealthPermissionsStatusRequested(),
                );
              }
            },
          );
        }
        // Pending probe or a genuinely unsupported platform: keep the neutral
        // capability note rather than offering an install that can't help.
        return const HealthOverviewUnavailableView();
      },
    );
  }
}

/// The denied/connect surface, made capability-aware: it probes provider
/// reachability so Android can route to install Health Connect when missing.
/// Falls back to the plain connect page if the probe is pending or fails, so it
/// renders exactly as today.
class _DeniedConnectView extends StatelessWidget {
  const _DeniedConnectView({
    required this.repository,
    required this.permanentlyDenied,
  });

  final HealthMetricsRepository repository;
  final bool permanentlyDenied;

  void _requestGrant(BuildContext context) {
    if (permanentlyDenied) {
      context.read<HealthPermissionsBloc>().add(
        HealthPermissionsDenialCleared(),
      );
    }
    context.read<HealthPermissionsBloc>().add(
      HealthPermissionsGrantRequested(),
    );
  }

  // Health Connect's manage-permissions deep-link only exists on Android; the
  // CTA stays as a plain retry elsewhere.
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Android-14 escape: deep-link to Health Connect's manage-permissions
  /// surface. If no settings screen can be resolved, fall back to today's retry
  /// (clear the denial + re-request) so the button is never a dead end.
  Future<void> _openManagePermissions(BuildContext context) async {
    final opened = await HealthConnectIntentBridge().openManagePermissions();
    if (!context.mounted) return;
    if (opened) {
      // Re-check on return; the resume re-check (P2b) also covers this.
      context.read<HealthPermissionsBloc>().add(
        const HealthPermissionsStatusRequested(),
      );
    } else {
      _requestGrant(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HealthProviderAvailability>(
      future: repository.getProviderAvailability(),
      builder: (context, snapshot) {
        final availability =
            snapshot.data ?? HealthProviderAvailability.available;
        return ConnectHealthPage(
          onConnectPressed: () => _requestGrant(context),
          showPermissionInstructions: permanentlyDenied,
          permanentlyDenied: permanentlyDenied,
          providerAvailability: availability,
          onInstallHealthConnect: () async {
            await repository.installHealthConnect();
            if (context.mounted) {
              context.read<HealthPermissionsBloc>().add(
                const HealthPermissionsStatusRequested(),
              );
            }
          },
          onOpenManagePermissions: permanentlyDenied && _isAndroid
              ? () => _openManagePermissions(context)
              : null,
        );
      },
    );
  }
}
