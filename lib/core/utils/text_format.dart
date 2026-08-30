String formatExerciseName(String raw) {
  final cleaned = raw.replaceAll('_', ' ').replaceAll('-', ' ');
  return cleaned
      .split(' ')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + (p.length > 1 ? p.substring(1) : ''))
      .join(' ');
}
