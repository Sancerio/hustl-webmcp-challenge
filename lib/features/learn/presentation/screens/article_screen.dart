import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../../core/widgets/responsive_center.dart';
import '../../domain/learn_article.dart';
import '../../domain/learn_articles.dart';

/// Renders a single in-app Learn article (Markdown body) by slug. If the slug
/// is unknown, shows a quiet "Article not found" state instead of crashing.
class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final article = learnArticleBySlug(slug);
    final theme = Theme.of(context);

    if (article == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const HustlMenuButton(),
          title: const Text('Learn'),
        ),
        body: ResponsiveCenter(
          maxContentWidth: 720,
          wideMaxWidth: 1200,
          child: Center(
            child: Padding(
              padding: AppSpacing.screen,
              child: Text(
                'Article not found',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const HustlMenuButton(),
        title: Text(article.title),
      ),
      body: ResponsiveCenter(
        maxContentWidth: 720,
        wideMaxWidth: 1200,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppSpacing.sectionPadding,
            child: _ArticleBody(article: article),
          ),
        ),
      ),
    );
  }
}

/// The scrollable Markdown body, styled with theme tokens to match the rest of
/// the app's long-form copy surfaces.
class _ArticleBody extends StatelessWidget {
  const _ArticleBody({required this.article});

  final LearnArticle article;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          article.summary,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        MarkdownBody(
          data: article.body,
          styleSheet: MarkdownStyleSheet(
            h2: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
            strong: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            p: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              height: 1.6,
            ),
            listBullet: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
