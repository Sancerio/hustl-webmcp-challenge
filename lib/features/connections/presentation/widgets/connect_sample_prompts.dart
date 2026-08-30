import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/widgets/hustl_snack.dart';

/// Example prompts shown at the end of a platform's connect guide so the user
/// can try the connector right after setting it up. Tap a prompt to copy it.
class SamplePromptsCard extends StatelessWidget {
  const SamplePromptsCard({super.key});

  static const List<String> _prompts = [
    'Summarize my last two weeks of training.',
    'What is my bench press trend?',
    'How is my nutrition adherence this week?',
    'Draft a push day and propose it as a Hustl template.',
    'Add an incline press to my Push Day.',
  ];

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
            'Try asking',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap to copy, then paste into your AI app. The last two create a '
            'proposal you approve in Hustl.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x1 + 4),
          for (final prompt in _prompts) _PromptRow(prompt: prompt),
        ],
      ),
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x1),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            Haptics.selection();
            await Clipboard.setData(ClipboardData(text: prompt));
            if (!context.mounted) return;
            HustlSnack.show(
              context,
              'Prompt copied',
              variant: HustlSnackVariant.success,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x1 + 4,
              vertical: AppSpacing.x1 + 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '"$prompt"',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                Icon(Icons.copy_rounded, size: 16, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
