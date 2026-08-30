import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/features/learn/domain/learn_articles.dart';
import 'package:hustl_app/features/learn/presentation/screens/article_screen.dart';

void main() {
  group('learnArticleBySlug', () {
    test('returns the article for a known slug', () {
      final article = learnArticleBySlug(recoveryAndReadinessSlug);
      expect(article, isNotNull);
      expect(article!.slug, recoveryAndReadinessSlug);
      expect(article.title, 'How recovery & readiness work');
    });

    test('returns null for an unknown slug', () {
      expect(learnArticleBySlug('does-not-exist'), isNull);
    });
  });

  testWidgets('ArticleScreen renders the title and body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ArticleScreen(slug: recoveryAndReadinessSlug)),
    );
    await tester.pumpAndSettle();

    expect(find.text('How recovery & readiness work'), findsOneWidget);
    expect(find.textContaining('What the recovery ring means'), findsWidgets);
    // Always offers a way back into the app, even when opened as the initial
    // route (deep link / web refresh) where there is nothing to pop.
    expect(find.byType(HustlMenuButton), findsOneWidget);
  });

  testWidgets('ArticleScreen shows not-found state for an unknown slug', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ArticleScreen(slug: 'does-not-exist')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Article not found'), findsOneWidget);
  });
}
