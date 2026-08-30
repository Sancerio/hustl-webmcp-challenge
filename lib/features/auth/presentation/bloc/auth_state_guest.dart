import '../../domain/entities/auth_user.dart';
import 'auth_bloc.dart';

/// Single source of truth for guest detection across the app.
///
/// A user is a guest UNLESS the auth state is [AuthAuthenticated] with a real
/// provider (google/facebook). Everything else — unauthenticated, hydrating,
/// loading, failure, and the defensive `AuthProvider.guest` case — counts as a
/// guest. This replaces ad-hoc, prefs-derived checks (which went stale and could
/// not see live auth state) with one derivation off the [AuthBloc] state.
extension AuthStateGuestX on AuthState {
  bool get isGuest {
    final state = this;
    if (state is AuthAuthenticated) {
      return state.user.provider == AuthProvider.guest;
    }
    return true;
  }
}
