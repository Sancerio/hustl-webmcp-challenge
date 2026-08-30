void webRedirectTo(String url) {
  // No-op on non-web platforms
}

void webDownloadTextFile({
  required String fileName,
  required String contents,
  String mimeType = 'text/plain',
}) {
  // No-op on non-web platforms
}
