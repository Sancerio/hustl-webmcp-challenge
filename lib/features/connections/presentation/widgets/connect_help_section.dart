import 'package:flutter/material.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_styles.dart';
import 'connect_client_glyph.dart';
import 'connect_help_data.dart';

/// A sectioned card for one connect client: a brand-mark heading row, then
/// numbered plain-sentence steps, then an optional monospace command block.
class ConnectHelpSection extends StatelessWidget {
  const ConnectHelpSection({super.key, required this.client});

  final ConnectHelpClient client;

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
          Row(
            children: [
              ConnectClientGlyph(client: client),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  client.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          for (var i = 0; i < client.steps.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.x2),
            _Step(index: i + 1, text: client.steps[i]),
          ],
          if (client.command != null) ...[
            const SizedBox(height: AppSpacing.x2),
            _CommandBlock(label: client.commandLabel, command: client.command!),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$index.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// A monospace command block on a quiet surface tint, for copy-paste snippets.
class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.command, this.label});

  final String command;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: AppRadius.controlRadius,
          ),
          child: SelectableText(
            command,
            style: AppTextStyles.mono(
              theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
