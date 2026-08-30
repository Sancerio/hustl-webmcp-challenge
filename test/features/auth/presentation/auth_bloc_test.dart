import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/errors/auth_exception.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';

class _FakeAuthRepository implements AuthRepository {
  AuthUser? currentUser;
  bool failGoogle = false;
  bool cancelGoogle = false;
  bool failApple = false;
  bool failDelete = false;

  // Captured arguments from the most recent signInWithApple call.
  String? lastAppleIdentityToken;
  String? lastAppleRawNonce;
  String? lastAppleFullName;
  bool failCheck = false;

  @override
  Future<AuthUser?> getCurrentUser() async {
    // Mirror the real repo: transient network/refresh failures surface as a
    // thrown error (or a null user), both of which map to AuthUnauthenticated.
    if (failCheck) throw Exception('transient outage');
    return currentUser;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    if (cancelGoogle) throw AuthCancelledException();
    if (failGoogle) throw Exception('google fail');
    return currentUser = const AuthUser(
      id: 'g_1',
      provider: AuthProvider.google,
      displayName: 'G User',
      email: 'g@example.com',
      photoUrl: null,
    );
  }

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) async {
    lastAppleIdentityToken = identityToken;
    lastAppleRawNonce = rawNonce;
    lastAppleFullName = fullName;
    if (failApple) throw Exception('apple fail');
    return currentUser = const AuthUser(
      id: 'a_1',
      provider: AuthProvider.apple,
      displayName: 'A User',
      email: 'a@example.com',
      photoUrl: null,
    );
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
  }

  @override
  Future<void> deleteAccount() async {
    if (failDelete) throw Exception('delete fail');
    currentUser = null;
  }
}

/// Builds an [AuthorizationCredentialAppleID] for tests without touching the
/// platform channel.
AuthorizationCredentialAppleID _fakeAppleCredential({
  String? identityToken = 'apple_id_token',
  String? givenName = 'Ada',
  String? familyName = 'Lovelace',
}) {
  return AuthorizationCredentialAppleID(
    userIdentifier: 'apple_user',
    givenName: givenName,
    familyName: familyName,
    authorizationCode: 'auth_code',
    email: 'a@example.com',
    identityToken: identityToken,
    state: null,
  );
}

void main() {
  group('AuthBloc', () {
    test('initial state is AuthHydrating', () {
      final repo = _FakeAuthRepository();
      final bloc = AuthBloc(repo);
      expect(bloc.state, isA<AuthHydrating>());
      bloc.close();
    });

    blocTest<AuthBloc, AuthState>(
      'emits unauthenticated when no current user',
      build: () => AuthBloc(_FakeAuthRepository()),
      act: (b) => b.add(AuthCheckRequested()),
      expect: () => [isA<AuthHydrating>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits authenticated when current user exists',
      build: () {
        final repo = _FakeAuthRepository()
          ..currentUser = const AuthUser(
            id: 'u1',
            provider: AuthProvider.google,
            displayName: 'Test',
            email: 't@example.com',
            photoUrl: null,
          );
        return AuthBloc(repo);
      },
      act: (b) => b.add(AuthCheckRequested()),
      expect: () => [isA<AuthHydrating>(), isA<AuthAuthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits AuthLoading on subsequent checks',
      build: () {
        final repo = _FakeAuthRepository()
          ..currentUser = const AuthUser(
            id: 'u1',
            provider: AuthProvider.google,
            displayName: 'Test',
            email: 't@example.com',
            photoUrl: null,
          );
        return AuthBloc(repo);
      },
      act: (b) async {
        b.add(AuthCheckRequested());
        await b.stream.firstWhere((s) => s is AuthAuthenticated);
        b.add(AuthCheckRequested());
      },
      expect: () => [
        isA<AuthHydrating>(),
        isA<AuthAuthenticated>(),
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'google sign in success',
      build: () => AuthBloc(_FakeAuthRepository()),
      act: (b) => b.add(AuthSignInWithGoogleRequested()),
      expect: () => [isA<AuthLoading>(), isA<AuthAuthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'google sign in failure',
      build: () {
        final repo = _FakeAuthRepository()..failGoogle = true;
        return AuthBloc(repo);
      },
      act: (b) => b.add(AuthSignInWithGoogleRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthFailure>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'google sign in cancel returns quietly to the prior state',
      build: () {
        final repo = _FakeAuthRepository()..cancelGoogle = true;
        return AuthBloc(repo);
      },
      // Prime a known prior state so the quiet return is observable.
      seed: () => AuthUnauthenticated(),
      act: (b) => b.add(AuthSignInWithGoogleRequested()),
      // Loading is emitted, then we return to the (unauthenticated) prior
      // state. No AuthFailure is emitted on cancel — mirrors the Apple path.
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'sign out',
      build: () {
        final repo = _FakeAuthRepository()
          ..currentUser = const AuthUser(
            id: 'u1',
            provider: AuthProvider.google,
            displayName: 'Test',
            email: 't@example.com',
            photoUrl: null,
          );
        return AuthBloc(repo);
      },
      act: (b) => b.add(AuthSignOutRequested()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'delete account success -> Unauthenticated',
      build: () {
        final repo = _FakeAuthRepository()
          ..currentUser = const AuthUser(
            id: 'u1',
            provider: AuthProvider.google,
          );
        return AuthBloc(repo);
      },
      act: (b) => b.add(AuthDeleteAccountRequested()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'delete account failure surfaces error then restores authenticated state',
      build: () {
        final repo = _FakeAuthRepository()
          ..currentUser = const AuthUser(
            id: 'u1',
            provider: AuthProvider.google,
          )
          ..failDelete = true;
        return AuthBloc(repo);
      },
      // A signed-in user requests deletion; if it fails, the account still
      // exists, so the bloc must not leave the app globally unauthenticated.
      seed: () => const AuthAuthenticated(
        AuthUser(id: 'u1', provider: AuthProvider.google),
      ),
      act: (b) => b.add(AuthDeleteAccountRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthFailure>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'apple sign in success -> Authenticated and passes a hashed nonce',
      build: () {
        final repo = _FakeAuthRepository();
        return AuthBloc(
          repo,
          requestAppleCredential: (hashedNonce) async {
            // The BLoC must hash the raw nonce before requesting the credential:
            // a SHA-256 hex digest is 64 lowercase chars.
            expect(hashedNonce.length, 64);
            return _fakeAppleCredential();
          },
        );
      },
      act: (b) => b.add(AuthSignInWithAppleRequested()),
      expect: () => [isA<AuthLoading>(), isA<AuthAuthenticated>()],
      verify: (b) {
        final repo = b.authRepository as _FakeAuthRepository;
        expect(repo.lastAppleIdentityToken, 'apple_id_token');
        // The RAW (unhashed) nonce is forwarded to the repository/backend.
        expect(repo.lastAppleRawNonce, isNotNull);
        expect(repo.lastAppleRawNonce!.length, 32);
        expect(repo.lastAppleFullName, 'Ada Lovelace');
      },
    );

    blocTest<AuthBloc, AuthState>(
      'apple sign in repeat login (null name) passes null fullName through',
      build: () {
        final repo = _FakeAuthRepository();
        return AuthBloc(
          repo,
          requestAppleCredential: (_) async =>
              _fakeAppleCredential(givenName: null, familyName: null),
        );
      },
      act: (b) => b.add(AuthSignInWithAppleRequested()),
      expect: () => [isA<AuthLoading>(), isA<AuthAuthenticated>()],
      verify: (b) {
        final repo = b.authRepository as _FakeAuthRepository;
        expect(repo.lastAppleFullName, isNull);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'apple sign in missing identity token -> Failure',
      build: () {
        final repo = _FakeAuthRepository();
        return AuthBloc(
          repo,
          requestAppleCredential: (_) async =>
              _fakeAppleCredential(identityToken: null),
        );
      },
      act: (b) => b.add(AuthSignInWithAppleRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthFailure>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'apple sign in cancel returns quietly to the prior state',
      build: () {
        final repo = _FakeAuthRepository();
        return AuthBloc(
          repo,
          requestAppleCredential: (_) async =>
              throw const SignInWithAppleAuthorizationException(
                code: AuthorizationErrorCode.canceled,
                message: 'canceled',
              ),
        );
      },
      // Prime a known prior state so the quiet return is observable.
      seed: () => AuthUnauthenticated(),
      act: (b) => b.add(AuthSignInWithAppleRequested()),
      // Loading is emitted, then we return to the (unauthenticated) prior state.
      // No AuthFailure is emitted on cancel.
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'apple sign in repository failure -> Failure',
      build: () {
        final repo = _FakeAuthRepository()..failApple = true;
        return AuthBloc(
          repo,
          requestAppleCredential: (_) async => _fakeAppleCredential(),
        );
      },
      act: (b) => b.add(AuthSignInWithAppleRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthFailure>(),
        isA<AuthUnauthenticated>(),
      ],
    );
    group('explicit-sign-out side effect (local-data wipe gating)', () {
      late bool sideEffectRan;

      AuthUser user() => const AuthUser(
        id: 'u1',
        provider: AuthProvider.google,
        displayName: 'Test',
        email: 't@example.com',
        photoUrl: null,
      );

      blocTest<AuthBloc, AuthState>(
        'runs onExplicitSignOut on an explicit sign-out',
        build: () {
          sideEffectRan = false;
          final repo = _FakeAuthRepository()..currentUser = user();
          return AuthBloc(
            repo,
            onExplicitSignOut: () async => sideEffectRan = true,
          );
        },
        act: (b) => b.add(AuthSignOutRequested()),
        expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
        verify: (_) => expect(sideEffectRan, isTrue),
      );

      blocTest<AuthBloc, AuthState>(
        'does NOT run onExplicitSignOut when an auth-check returns no user',
        build: () {
          sideEffectRan = false;
          return AuthBloc(
            _FakeAuthRepository(),
            onExplicitSignOut: () async => sideEffectRan = true,
          );
        },
        act: (b) => b.add(AuthCheckRequested()),
        expect: () => [isA<AuthHydrating>(), isA<AuthUnauthenticated>()],
        verify: (_) => expect(sideEffectRan, isFalse),
      );

      blocTest<AuthBloc, AuthState>(
        'does NOT run onExplicitSignOut on a transient auth-check failure',
        build: () {
          sideEffectRan = false;
          final repo = _FakeAuthRepository()..failCheck = true;
          return AuthBloc(
            repo,
            onExplicitSignOut: () async => sideEffectRan = true,
          );
        },
        act: (b) => b.add(AuthCheckRequested()),
        expect: () => [isA<AuthHydrating>(), isA<AuthUnauthenticated>()],
        verify: (_) => expect(sideEffectRan, isFalse),
      );

      blocTest<AuthBloc, AuthState>(
        'a failing onExplicitSignOut never blocks sign-out',
        build: () {
          final repo = _FakeAuthRepository()..currentUser = user();
          return AuthBloc(
            repo,
            onExplicitSignOut: () async => throw Exception('wipe failed'),
          );
        },
        act: (b) => b.add(AuthSignOutRequested()),
        expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      );

      blocTest<AuthBloc, AuthState>(
        'successful account deletion also runs the local-data wipe',
        build: () {
          sideEffectRan = false;
          final repo = _FakeAuthRepository()..currentUser = user();
          return AuthBloc(
            repo,
            onExplicitSignOut: () async => sideEffectRan = true,
          );
        },
        act: (b) => b.add(AuthDeleteAccountRequested()),
        expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
        verify: (_) => expect(sideEffectRan, isTrue),
      );
    });
  });
}
