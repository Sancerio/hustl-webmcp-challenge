abstract interface class CoachingTrendsApi {
  Future<Map<String, dynamic>> load({
    required int windowDays,
    required String endDate,
    required int utcOffsetMinutes,
  });
}

class CoachingTrendsApiException implements Exception {
  const CoachingTrendsApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });
  final int statusCode;
  final String code;
  final String message;
}
