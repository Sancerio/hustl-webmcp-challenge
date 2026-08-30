import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/widgets/hustl_snack.dart';
import 'connect_help_data.dart';

/// Shared framing cards for the "How to connect" guide (intro/trust/connector
/// URL/managing note). The picker tile lives in connect_platform_tile.dart.
/// Extracted from connect_ai_help_screen.dart so the screen stays focused.

/// The connector URL the steps refer to, shown in a copyable block.
class ConnectorUrlCard extends StatelessWidget {
  const ConnectorUrlCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connector URL',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            'Paste this when your AI app asks for the connector (MCP server) URL.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x2,
              vertical: AppSpacing.x1,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: AppRadius.controlRadius,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    kConnectorUrl,
                    style: AppTextStyles.mono(theme.textTheme.bodySmall),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Copy connector URL',
                  color: colors.primary,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    Haptics.selection();
                    await Clipboard.setData(
                      const ClipboardData(text: kConnectorUrl),
                    );
                    if (!context.mounted) return;
                    HustlSnack.show(
                      context,
                      'Connector URL copied',
                      variant: HustlSnackVariant.success,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two-line trust framing: read is read-only, writes need your approval.
class TrustCard extends StatelessWidget {
  const TrustCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrustRow(
            icon: Icons.visibility_outlined,
            title: 'Read is read-only',
            body:
                'The assistant can read your profile, workouts, health metrics, '
                'and nutrition — only your data, nothing else.',
          ),
          SizedBox(height: AppSpacing.x2),
          _TrustRow(
            icon: Icons.verified_user_outlined,
            title: 'Writes need your approval',
            body:
                'When it "creates" a template it really makes a proposal. '
                'Nothing changes until you review and apply it in the app.',
          ),
        ],
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The closing footnote on where to manage connected apps and the name caveat.
class ConnectHelpManagingNote extends StatelessWidget {
  const ConnectHelpManagingNote({super.key});

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
              'Manage every connected app under Connected AI apps. The '
              'read-only or can-propose badge and the verified sign-in domain '
              'are the real trust signal — the app name is just a label.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

