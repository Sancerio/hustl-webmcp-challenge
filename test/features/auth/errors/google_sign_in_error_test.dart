import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/auth/errors/google_sign_in_error.dart';

void main() {
  group('googleApiExceptionCode', () {
    test('extracts DEVELOPER_ERROR (10) from the fully-qualified message', () {
      final e = PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 10: ',
      );
      expect(googleApiExceptionCode(e), GoogleApiStatus.developerError);
    });

    test('extracts a bare leading "<code>:" form', () {
      final e = PlatformException(
        code: 'sign_in_failed',
        message: '12500: sign in failed',
      );
      expect(googleApiExceptionCode(e), GoogleApiStatus.signInFailed);
    });

    test('returns null when the message carries no numeric status', () {
      final e = PlatformException(
        code: 'network_error',
        message: 'Network error, no status code here',
      );
      expect(googleApiExceptionCode(e), isNull);
    });

    test('returns null for a null message', () {
      final e = PlatformException(code: 'sign_in_failed');
      expect(googleApiExceptionCode(e), isNull);
    });
  });
}
