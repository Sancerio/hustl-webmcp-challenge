import 'package:flutter/material.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import 'connect_client_glyph.dart';
import 'connect_help_data.dart';

/// A tappable picker row for one platform: brand mark, name, a short kind
/// caption, and a chevron. Selecting it reveals that platform's steps.
class ConnectPlatformTile extends StatelessWidget {
  const ConnectPlatformTile({
    super.key,
    required this.client,
    required this.onTap,
  });

  final ConnectHelpClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kind =
        client.command != null ? 'Command-line setup' : 'Connector setup';
    // One action-oriented node for screen readers: the InkWell already supplies
    // the button role, so exclude the inner labels to avoid re-announcing the
    // raw "Command-line setup" caption and chevron as separate nodes.
    return Semantics(
      container: true,
      button: true,
      label: '${client.title}. $kind. Show setup steps.',
      child: Material(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  ConnectClientGlyph(client: client),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          kind,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
