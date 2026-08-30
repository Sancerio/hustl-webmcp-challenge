class HeartRateSample {
  const HeartRateSample({required this.time, required this.bpm, this.source});

  final DateTime time;
  final double bpm;
  final String? source;
}
