import '../../features/auth/domain/entities/auth_user.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import 'demo_persona.dart';

/// Instantly-authenticated [AuthRepository] for demo mode.
///
/// `getCurrentUser()` returns the demo persona synchronously (no hydration
/// wait, no OAuth), so `AuthBloc` emits `AuthAuthenticated` on the first
/// `AuthCheckRequested` and the app boots straight into the home screen.
class DemoAuthRepository implements AuthRepository {
  AuthUser? _user = DemoPersona.user;

  @override
  Future<AuthUser?> getCurrentUser() async => _user;

  @override
  Future<AuthUser> signInWithGoogle() async {
    _user = DemoPersona.user;
    return DemoPersona.user;
  }

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) async {
    _user = DemoPersona.user;
    return DemoPersona.user;
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }

  @override
  Future<void> deleteAccount() async {
    _user = null;
  }
}
