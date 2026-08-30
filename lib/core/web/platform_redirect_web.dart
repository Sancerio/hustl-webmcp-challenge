import 'package:web/web.dart' as web;
import 'dart:js_interop';

void webRedirectTo(String url) {
  // Use assign to create a new entry in the session history
  web.window.location.assign(url);
}

void webDownloadTextFile({
  required String fileName,
  required String contents,
  String mimeType = 'text/plain',
}) {
  final blob = web.Blob(
    <web.BlobPart>[contents.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
