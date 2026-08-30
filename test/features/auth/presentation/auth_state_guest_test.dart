import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_state_guest.dart';

void main() {
  group('AuthState.isGuest (single source of truth)', () {
    test('authenticated with a real provider is NOT a guest', () {
      expect(
        const AuthAuthenticated(
          AuthUser(id: 'u', provider: AuthProvider.google),
        ).isGuest,
        isFalse,
      );
      expect(
        const AuthAuthenticated(
          AuthUser(id: 'u', provider: AuthProvider.google),
        ).isGuest,
        isFalse,
      );
    });

    test('authenticated with the guest provider IS a guest', () {
      expect(
        const AuthAuthenticated(
          AuthUser(id: 'g', provider: AuthProvider.guest),
        ).isGuest,
        isTrue,
      );
    });

    test('every non-authenticated state is a guest', () {
      expect(AuthUnauthenticated().isGuest, isTrue);
      expect(AuthHydrating().isGuest, isTrue);
      expect(AuthLoading().isGuest, isTrue);
      expect(const AuthFailure('boom').isGuest, isTrue);
    });
  });
}
