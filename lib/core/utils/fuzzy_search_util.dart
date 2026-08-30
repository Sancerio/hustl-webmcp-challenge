import 'dart:math' as math;

/// Utility class for fuzzy searching
class FuzzySearchUtil {
  /// Calculate Levenshtein distance between two strings
  /// Returns the number of edits (insertions, deletions, substitutions) required
  /// to transform string a into string b
  static int levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> previousRow = List<int>.generate(b.length + 1, (i) => i);
    List<int> currentRow = List<int>.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      currentRow[0] = i + 1;

      for (int j = 0; j < b.length; j++) {
        int insertions = previousRow[j + 1] + 1;
        int deletions = currentRow[j] + 1;
        int substitutions = previousRow[j] + (a[i] != b[j] ? 1 : 0);

        currentRow[j + 1] = math.min(
          math.min(insertions, deletions),
          substitutions,
        );
      }

      previousRow = List.from(currentRow);
    }

    return currentRow[b.length];
  }

  /// Check if a string is fuzzy similar to a search query
  /// Returns true if the source contains the query or is within maxDistance edits
  static bool isFuzzyMatch(String source, String query, {int maxDistance = 2}) {
    if (source.contains(query)) return true; // Direct substring match

    // For short queries, be more strict
    final allowedDistance = query.length <= 2 ? 0 : maxDistance;

    // Check if query is fuzzy similar to any word in source
    final words = source.split(' ');
    for (final word in words) {
      // For efficiency, only check words with similar length
      if ((word.length - query.length).abs() <= maxDistance + 1) {
        if (levenshteinDistance(word.toLowerCase(), query.toLowerCase()) <=
            allowedDistance) {
          return true;
        }
      }
    }
    return false;
  }

  /// Calculate a fuzzy search score for an item
  /// Higher scores indicate better matches
  static int calculateFuzzyScore<T>(
    T item,
    String searchQuery,
    List<String> Function(T) getSearchableFields, {
    List<int> fieldWeights = const [100, 80],
  }) {
    if (searchQuery.isEmpty) return 0;

    final searchQueryLower = searchQuery.toLowerCase();
    final fields = getSearchableFields(item);

    // Ensure we have enough weights for all fields
    final weights = List<int>.from(fieldWeights);
    while (weights.length < fields.length) {
      weights.add(weights.last - 20);
    }

    int score = 0;
    bool hasExactMatch = false;

    // Check each field for matches
    for (int i = 0; i < fields.length; i++) {
      final field = fields[i].toLowerCase();
      final weight = weights[i];

      // Check for direct matches
      if (field.contains(searchQueryLower)) {
        hasExactMatch = true;
        score += weight;

        // Bonus for starts with
        if (field.startsWith(searchQueryLower)) {
          score += weight ~/ 2;
        }
      }
    }

    // Check for fuzzy matches if no exact match was found
    if (!hasExactMatch) {
      for (int i = 0; i < fields.length; i++) {
        final field = fields[i];
        final weight = weights[i];

        if (isFuzzyMatch(field, searchQuery)) {
          score += weight * 0.6 ~/ 1; // ~60% of the weight for fuzzy matches
          break; // Only count the best fuzzy match
        }
      }
    }

    return score;
  }
}
