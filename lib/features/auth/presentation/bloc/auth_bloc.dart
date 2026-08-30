import 'dart:convert';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../errors/auth_exception.dart';

/// Signature for the Apple credential request, injected so the BLoC can be
/// driven by a fake in tests without invoking the platform plugin.
typedef AppleCredentialRequester =
    Future<AuthorizationCredentialAppleID> Function(String hashedNonce);

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthSignInWithGoogleRequested extends AuthEvent {}

class AuthSignInWithAppleRequested extends AuthEvent {}

class AuthSignOutRequested extends AuthEvent {}

class AuthDeleteAccountRequested extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthUnauthenticated extends AuthState {}

class AuthLoading extends AuthState {}

/// One-time startup state used while we rehydrate an existing session.
///
/// This lets the app block the "logged out" UI until we know whether the user
/// has a valid session.
class AuthHydrating extends AuthState {}

class AuthAuthenticated extends AuthState {
  final AuthUser user;
  const AuthAuthenticated(this.user);
  @override
  List<Object?> get props => [user];
}

class AuthFailure extends AuthState {
  final String message;
  const AuthFailure(this.message);
  @override
  List<Object?> get props => [message];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  /// Requests an Apple ID credential. Defaults to the real plugin call; tests
  /// inject a fake so the platform channel is never touched.
  final AppleCredentialRequester _requestAppleCredential;

  /// Side effect run ONLY on an explicit [AuthSignOutRequested] (after the
  /// repository sign-out, before emitting [AuthUnauthenticated]). This is where
  /// the destructive local-data wipe ([AccountMigrationService.onUnauthenticated])
  /// is hooked — it must never fire on a generic [AuthUnauthenticated] produced by
  /// a transient auth-check / refresh failure, which would delete a returning
  /// user's local workouts during a temporary outage. Best-effort: never throws
  /// into the auth flow.
  final Future<void> Function()? onExplicitSignOut;

  bool _hasHydratedOnce = false;

  AuthBloc(
    this.authRepository, {
    AppleCredentialRequester? requestAppleCredential,
    this.onExplicitSignOut,
  }) : _requestAppleCredential =
           requestAppleCredential ?? _defaultAppleCredentialRequester,
       super(AuthHydrating()) {
    on<AuthCheckRequested>(_onCheck);
    on<AuthSignInWithGoogleRequested>(_onGoogle);
    on<AuthSignInWithAppleRequested>(_onApple);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthDeleteAccountRequested>(_onDeleteAccount);
  }

  static Future<AuthorizationCredentialAppleID>
  _defaultAppleCredentialRequester(String hashedNonce) {
    return SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
  }

  Future<void> _onCheck(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(_hasHydratedOnce ? AuthLoading() : AuthHydrating());
    try {
      final user = await authRepository.getCurrentUser();
      if (user == null) {
        emit(AuthUnauthenticated());
      } else {
        emit(AuthAuthenticated(user));
      }
    } catch (_) {
      emit(AuthUnauthenticated());
    } finally {
      _hasHydratedOnce = true;
    }
  }

  Future<void> _onGoogle(
    AuthSignInWithGoogleRequested event,
    Emitter<AuthState> emit,
  ) async {
    final priorState = state;
    emit(AuthLoading());
    try {
      final user = await authRepository.signInWithGoogle();
      emit(AuthAuthenticated(user));
    } on AuthCancelledException {
      // User backed out of the picker — return quietly to the prior state,
      // same as the Apple cancel path. No error surfaced.
      emit(priorState);
    } catch (e) {
      emit(AuthFailure(e.toString()));
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onApple(
    AuthSignInWithAppleRequested event,
    Emitter<AuthState> emit,
  ) async {
    final priorState = state;
    emit(AuthLoading());
    try {
      final rawNonce = _generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await _requestAppleCredential(hashedNonce);

      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        emit(const AuthFailure('Apple sign-in failed. Please try again.'));
        emit(AuthUnauthenticated());
        return;
      }

      // Apple only returns the name on the first authorization; on repeat
      // logins these are null — pass an empty string through in that case.
      final fullName = [
        credential.givenName,
        credential.familyName,
      ].whereType<String>().where((p) => p.isNotEmpty).join(' ');

      final user = await authRepository.signInWithApple(
        identityToken: identityToken,
        rawNonce: rawNonce,
        fullName: fullName.isEmpty ? null : fullName,
      );
      emit(AuthAuthenticated(user));
    } on SignInWithAppleAuthorizationException catch (e) {
      // User dismissed the sheet — return quietly to the prior state, no error.
      if (e.code == AuthorizationErrorCode.canceled) {
        emit(priorState);
        return;
      }
      emit(AuthFailure(e.message));
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthFailure(e.toString()));
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    await authRepository.signOut();
    // Run the explicit-sign-out side effect (local-data wipe) here, so it only
    // fires on a deliberate sign-out — never on a transient AuthUnauthenticated.
    final onSignedOut = onExplicitSignOut;
    if (onSignedOut != null) {
      try {
        await onSignedOut();
      } catch (_) {
        // Best-effort: a failed wipe must not block sign-out.
      }
    }
    emit(AuthUnauthenticated());
  }

  Future<void> _onDeleteAccount(
    AuthDeleteAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    final priorState = state;
    emit(AuthLoading());
    try {
      await authRepository.deleteAccount();
      // A successful deletion must also run the explicit local-data wipe (the
      // same hook a deliberate sign-out uses), so a user whose account no longer
      // exists isn't left with workouts/templates cached on device. Best-effort:
      // a failed wipe must not change the deletion outcome.
      final onSignedOut = onExplicitSignOut;
      if (onSignedOut != null) {
        try {
          await onSignedOut();
        } catch (_) {}
      }
      emit(AuthUnauthenticated());
    } catch (e) {
      // Deletion failed: the account (and its tokens) still exist, so the user
      // is still signed in. Surface the error, then RESTORE the prior
      // authenticated state instead of leaving the app globally unauthenticated
      // (app-wide listeners treat any non-AuthAuthenticated state as signed out,
      // which would stop sync and clear user-scoped UI on a failed delete).
      emit(AuthFailure(e.toString()));
      if (priorState is AuthAuthenticated) {
        emit(priorState);
      }
    }
  }

  /// Generates a cryptographically-random, url-safe nonce. Apple requires the
  /// SHA-256 of this raw value to be passed to the credential request, and the
  /// raw value to be sent to the backend for verification.
  static String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
