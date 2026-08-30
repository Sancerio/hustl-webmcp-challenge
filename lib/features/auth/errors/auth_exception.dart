class AuthException implements Exception {
  final String message; // user-friendly message
  final String? details; // optional technical details

  AuthException(this.message, {this.details});

  @override
  String toString() => message;
}

/// Thrown when the user dismisses a native sign-in flow without completing it
/// (e.g. backing out of the Google account picker). Callers should treat this
/// like Apple's cancellation path: return quietly to the prior state, with no
/// error surfaced.
class AuthCancelledException extends AuthException {
  AuthCancelledException([super.message = 'Sign-in was cancelled.']);
}
