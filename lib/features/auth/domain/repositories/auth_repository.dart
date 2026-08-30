import '../entities/auth_user.dart';

abstract class AuthRepository {
  Future<AuthUser?> getCurrentUser();
  Future<AuthUser> signInWithGoogle();
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  });
  Future<void> signOut();

  /// Permanently deletes the signed-in account on the server, then clears the
  /// local session so the app returns to an unauthenticated state. Idempotent:
  /// a server response indicating the account was already deleted still
  /// resolves successfully.
  Future<void> deleteAccount();
}
