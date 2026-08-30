import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../../../core/webmcp/web_mcp_config.dart';
import '../bloc/connections_bloc.dart';
import '../bloc/connections_event.dart';
import '../bloc/connections_state.dart';
import '../widgets/connection_confirm_sheet.dart';
import '../widgets/connection_row.dart';
import '../widgets/web_mcp_food_auto_log_card.dart';

/// Connected AI apps management. Pushes over the shell at `/connections`. Lists
/// each connection (client name shown for recognition only — never as a trust
/// signal), its access level, and last-used, with "Limit to read-only" and
/// "Disconnect" actions behind a confirm sheet.
class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ConnectionsBloc>(
      create: (_) =>
          GetIt.instance<ConnectionsBloc>()..add(const LoadConnections()),
      child: const _ConnectionsView(),
    );
  }
}

class _ConnectionsView extends StatelessWidget {
  const _ConnectionsView();

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      appBar: AppBar(
        title: const Text('Connected AI apps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How to connect',
            onPressed: () => context.push('/connections/help'),
          ),
        ],
      ),
      child: BlocConsumer<ConnectionsBloc, ConnectionsState>(
        listenWhen: (prev, next) =>
            next is ConnectionsLoaded &&
            (next.lastOutcome != null ||
                (next.webMcpSettingError != null &&
                    next.webMcpSettingError !=
                        (prev is ConnectionsLoaded
                            ? prev.webMcpSettingError
                            : null))),
        listener: (context, state) {
          if (state is! ConnectionsLoaded) return;
          if (state.webMcpSettingError != null) {
            HustlSnack.show(
              context,
              state.webMcpSettingError!,
              variant: HustlSnackVariant.error,
            );
            return;
          }
          final outcome = state.lastOutcome;
          if (outcome == null) return;
          final name = outcome.clientName.trim().isEmpty
              ? 'That app'
              : outcome.clientName.trim();
          final message = switch (outcome.kind) {
            ConnectionActionKind.steppedDown => '$name is now read-only',
            ConnectionActionKind.steppedUp =>
              '$name can now propose changes — live within ~30 min (reconnect it to apply now)',
            ConnectionActionKind.revoked => '$name disconnected',
          };
          HustlSnack.show(context, message, variant: HustlSnackVariant.success);
        },
        builder: (context, state) {
          if (state is ConnectionsLoading || state is ConnectionsInitial) {
            return const HustlInlineSkeleton();
          }
          if (state is ConnectionsFailure) {
            return ScreenEmptyState(
              icon: Icons.cloud_off_rounded,
              title: "We couldn't load connected apps",
              message: state.message,
              actionLabel: 'Try again',
              onAction: () =>
                  context.read<ConnectionsBloc>().add(const LoadConnections()),
            );
          }
          final loaded = state as ConnectionsLoaded;
          if (loaded.items.isEmpty && !kWebMcpEnabled) {
            return RefreshIndicator(
              onRefresh: () async => context.read<ConnectionsBloc>().add(
                const RefreshConnections(),
              ),
              child: ListView(
                children: [
                  const SizedBox(height: 80),
                  ScreenEmptyState(
                    icon: Icons.hub_outlined,
                    title: 'No connected apps',
                    message:
                        'When you connect Claude, Codex, or ChatGPT to Hustl, '
                        'they show up here so you can manage their access.',
                    actionLabel: 'Connect an AI app',
                    onAction: () => context.push('/connections/help'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                context.read<ConnectionsBloc>().add(const RefreshConnections()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x2,
                AppSpacing.x2,
                AppSpacing.x2,
                AppSpacing.x3,
              ),
              children: [
                if (kWebMcpEnabled) ...[
                  WebMcpFoodAutoLogCard(
                    enabled: loaded.webMcpFoodAutoLogEnabled,
                    busy: loaded.webMcpFoodAutoLogBusy,
                    onChanged: (enabled) => context.read<ConnectionsBloc>().add(
                      SetWebMcpFoodAutoLog(enabled),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                ],
                if (loaded.items.isEmpty) ...[
                  ScreenEmptyState(
                    icon: Icons.hub_outlined,
                    title: 'No external apps connected',
                    message:
                        'Claude, Codex, and ChatGPT connections will appear here. '
                        'Hustl Web auto-log is an account setting and works separately.',
                    actionLabel: 'Connect an AI app',
                    onAction: () => context.push('/connections/help'),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                ],
                // Each connection is its own surface card (settings idiom), with
                // a quiet gap between — not one big grouped list.
                for (final c in loaded.items) ...[
                  ConnectionRow(
                    connection: c,
                    isBusy: loaded.inFlightIds.contains(c.clientId),
                    onStepDown: () =>
                        _confirmStepDown(context, c.clientId, c.clientName),
                    onStepUp: () =>
                        _confirmStepUp(context, c.clientId, c.clientName),
                    onRevoke: () =>
                        _confirmRevoke(context, c.clientId, c.clientName),
                    onSetAutoApprove: (kind, enabled) =>
                        context.read<ConnectionsBloc>().add(
                          SetAutoApprove(
                            clientId: c.clientId,
                            kind: kind,
                            enabled: enabled,
                          ),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                ],
                if (loaded.items.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x1),
                  const _DisconnectNote(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmStepDown(
    BuildContext context,
    String clientId,
    String clientName,
  ) async {
    final bloc = context.read<ConnectionsBloc>();
    final ok = await showConnectionConfirmSheet(
      context,
      action: ConnectionConfirmAction.stepDown,
      clientName: clientName,
    );
    if (ok == true) bloc.add(StepDownConnection(clientId));
  }

  Future<void> _confirmStepUp(
    BuildContext context,
    String clientId,
    String clientName,
  ) async {
    final bloc = context.read<ConnectionsBloc>();
    final ok = await showConnectionConfirmSheet(
      context,
      action: ConnectionConfirmAction.stepUp,
      clientName: clientName,
    );
    if (ok == true) bloc.add(StepUpConnection(clientId));
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    String clientId,
    String clientName,
  ) async {
    final bloc = context.read<ConnectionsBloc>();
    final ok = await showConnectionConfirmSheet(
      context,
      action: ConnectionConfirmAction.revoke,
      clientName: clientName,
    );
    if (ok == true) bloc.add(RevokeConnection(clientId));
  }
}

/// A quiet footnote making the revoke side-effect explicit: disconnecting also
/// cancels that connection's pending proposals.
class _DisconnectNote extends StatelessWidget {
  const _DisconnectNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              'Disconnecting an app stops new proposals and cancels any waiting '
              'for your review. An app already signed in may keep reading for a '
              'few minutes until its session expires. App names come from the '
              'app itself, so treat them as a label, not proof of identity.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
