import 'package:bloc/bloc.dart';

import '../../domain/entities/auth_user.dart';

sealed class AuthState {
  const AuthState();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final AuthUser user;
}

class AuthBloc extends Cubit<AuthState> {
  AuthBloc() : super(const AuthUnauthenticated());
}
