import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../widgets/connect_help_cards.dart';
import '../widgets/connect_help_data.dart'
    show ConnectHelpClient, connectHelpClients;
import '../widgets/connect_help_section.dart';
import '../widgets/connect_platform_tile.dart';
import '../widgets/connect_sample_prompts.dart';

/// In-app "How to connect" guide. The user picks their AI app FIRST (this
/// screen), then a platform's steps open as a PUSHED route
/// (`/connections/help/:client`, see [ConnectAiHelpArticleScreen]) — so the
/// AppBar back button AND the native iOS edge-swipe both return to this picker.
/// Mirrors `docs/help/connect-ai-to-hustl.md` (connector URL, read-only-vs-
/// propose framing, per-client steps for Claude, Claude Code, Codex, ChatGPT).
/// Reached via `/connections/help`.
class ConnectAiHelpScreen extends StatelessWidget {
  const ConnectAiHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      appBar: AppBar(title: const Text('How to connect')),
      child: ListView(
        key: const ValueKey('connect-help-picker'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x4,
        ),
        children: [
          const _Intro(),
          const SizedBox(height: AppSpacing.x2),
          const TrustCard(),
          // Horizontal-0 padding: the ListView already insets by x2; the header
          // supplies the x3 top / x1 bottom rhythm.
          const SectionHeader(
            'Choose your app',
            padding: EdgeInsets.fromLTRB(0, AppSpacing.x3, 0, AppSpacing.x1),
          ),
          for (final client in connectHelpClients) ...[
            ConnectPlatformTile(
              client: client,
              onTap: () => context.push('/connections/help/${client.id}'),
            ),
            const SizedBox(height: AppSpacing.x2),
          ],
          const SizedBox(height: AppSpacing.x1),
          const ConnectHelpManagingNote(),
        ],
      ),
    );
  }
}

/// Step 2: one platform's connector URL, steps, and sample prompts. Pushed as
/// its own route so back (button or native swipe) returns to the picker.
class ConnectAiHelpArticleScreen extends StatelessWidget {
  const ConnectAiHelpArticleScreen({super.key, required this.client});

  final ConnectHelpClient client;

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      appBar: AppBar(title: const Text('Connect your AI')),
      child: ListView(
        key: ValueKey('connect-help-article-${client.id}'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x4,
        ),
        children: [
          const ConnectorUrlCard(),
          const SizedBox(height: AppSpacing.x3),
          ConnectHelpSection(client: client),
          const SizedBox(height: AppSpacing.x3),
          const SamplePromptsCard(),
          const SizedBox(height: AppSpacing.x3),
          const ConnectHelpManagingNote(),
        ],
      ),
    );
  }
}

/// The opening explainer: what connecting your AI lets you do.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Use your own AI with Hustl',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          'Connect Claude, Codex, or ChatGPT once, then ask it to read your '
          'training data and draft workout templates or nutrition targets — all '
          'scoped to your account. Pick your app to see the steps.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
