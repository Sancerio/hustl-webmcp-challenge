class ProposalsApiException implements Exception {
  const ProposalsApiException({required this.code, required this.message});
  final String code;
  final String message;
}
