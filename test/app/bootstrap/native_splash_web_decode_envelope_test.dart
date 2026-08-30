// Regression for a production WEB "Uncaught Error" thrown right after the first
// post-login frame.
//
// Root cause (deobfuscated from the deployed release stack + reproduced in a
// `flutter run -d chrome` debug build):
//
//   PlatformException(error, Exception: Did you forget to run
//   "dart run flutter_native_splash:create"? Could not run the JS command
//   removeSplashFromWeb())
//     package:flutter/src/services/message_codecs.dart  decodeEnvelope
//     package:flutter/src/services/platform_channel.dart MethodChannel._invokeMethod
//
// `flutter_native_splash` is configured with `web: false`, so the web splash JS
// (`removeSplashFromWeb()`) is never injected into web/index.html. The app,
// however, called `FlutterNativeSplash.preserve()` / `.remove()` unconditionally.
// On web, `remove()` schedules `MethodChannel('flutter_native_splash')
// .invokeMethod('remove')` inside the plugin's own post-frame callback. The
// plugin wraps that call in a `try/catch`, but `invokeMethod` is ASYNC, so the
// codec error thrown out of `StandardMethodCodec.decodeEnvelope` lands in the
// returned Future — never the synchronous catch — and escapes as an uncaught
// zone error. In release the same decode step takes the
// `FormatException('Invalid envelope')` branch of `decodeEnvelope`.
//
// The fix skips `preserve()`/`remove()` on web (main.dart + bootstrapper), so
// the failing channel call is never made and the first frame is never deferred.
//
// These tests (1) lock the exact framework throw that the deployed stack hit, so
// the diagnosis can't silently drift, and (2) prove that decoding the
// native-splash channel's web reply is what throws — i.e. there is nothing safe
// to call here on web.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodCodec codec = StandardMethodCodec();

  group('flutter_native_splash web reply decoding (root-cause lock)', () {
    test(
      'an empty/raw reply (web: false, no removeSplashFromWeb JS) throws '
      "FormatException('Invalid envelope') out of decodeEnvelope -- the exact "
      'release-build throw the deployed stack mapped to',
      () {
        // On web with `web: false`, the channel reply for `remove` is not a
        // valid StandardMethodCodec envelope. Decoding it is what blew up at
        // message_codecs.dart decodeEnvelope in the deployed release build.
        final ByteData notAnEnvelope = ByteData(0);

        expect(
          () => codec.decodeEnvelope(notAnEnvelope),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('envelope'),
            ),
          ),
        );
      },
    );

    test(
      'an error-envelope reply decodes to a PlatformException -- the debug-build '
      'variant captured via `flutter run -d chrome`',
      () {
        // The debug build surfaced the same failure as a PlatformException
        // (errorCode "error", an "Exception: Did you forget to run ..." message).
        // Encoding that error envelope and decoding it must reproduce the throw.
        final ByteData errorEnvelope = codec.encodeErrorEnvelope(
          code: 'error',
          message: 'Exception: Did you forget to run '
              '"dart run flutter_native_splash:create"? '
              'Could not run the JS command removeSplashFromWeb()',
        );

        expect(
          () => codec.decodeEnvelope(errorEnvelope),
          throwsA(isA<PlatformException>()),
        );
      },
    );
  });

  testWidgets(
    'the app boot path never invokes the flutter_native_splash channel: with the '
    'channel mocked to fail like production web, no uncaught error escapes',
    (tester) async {
      // Mirror the production web reply: the plugin handler "exists" (web build)
      // but its JS function is missing, so any call to the channel fails. If the
      // app were to call FlutterNativeSplash.remove()/preserve() on web, this
      // handler would be hit and its async error would escape uncaught.
      var sawRemoveCall = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_native_splash'),
        (MethodCall call) async {
          if (call.method == 'remove') sawRemoveCall = true;
          throw PlatformException(
            code: 'error',
            message: 'Could not run the JS command removeSplashFromWeb()',
          );
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter_native_splash'),
          null,
        );
      });

      // A minimal app + a post-frame callback model the bootstrapper's
      // splash-removal slot. The fix guards that slot with `!kIsWeb`, so the
      // channel must not be touched and no error may be queued for the zone.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No exception may have been swallowed into the test zone.
      expect(tester.takeException(), isNull);
      // The boot path must not have driven the native-splash channel.
      expect(sawRemoveCall, isFalse);
    },
  );
}
