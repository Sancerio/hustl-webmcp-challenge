/// An immutable in-app "Learn" article. The [body] is Markdown rendered by the
/// same widget the rest of the app uses for long-form copy.
class LearnArticle {
  const LearnArticle({
    required this.slug,
    required this.title,
    required this.summary,
    required this.body,
  });

  /// Stable URL fragment used for routing (e.g. `/learn/<slug>`).
  final String slug;

  /// Screen / app-bar title.
  final String title;

  /// One-line description used by nav rows and link affordances.
  final String summary;

  /// Markdown body of the article.
  final String body;
}
