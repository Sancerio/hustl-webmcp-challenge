import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/onboarding/presentation/first_win/save_progress_upgrade_card.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final AuthUser? _user;

  @override
  Future<AuthUser?> getCurrentUser() async => _user;

  @override
  Future<AuthUser> signInWithGoogle() async =>
      _user ?? (throw UnimplementedError());

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) async => _user ?? (throw UnimplementedError());

  @override
  Future<void> deleteAccount() async {}
}

Future<void> _pump(WidgetTester tester, {required AuthUser? user}) async {
  final bloc = AuthBloc(_FakeAuthRepository(user))..add(AuthCheckRequested());
  addTearDown(bloc.close);
  // Provide the bloc ABOVE MaterialApp so the modal sheet (pushed on the app
  // Navigator's overlay) can still resolve AuthBloc.
  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: bloc,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SaveProgressUpgradeCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the upgrade block for a guest', (tester) async {
    await _pump(tester, user: null);
    expect(find.text('Save your progress'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('hides the upgrade block when signed in', (tester) async {
    await _pump(
      tester,
      user: const AuthUser(id: 'u', provider: AuthProvider.google),
    );
    expect(find.text('Save your progress'), findsNothing);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('tapping Sign in opens the real login sheet', (tester) async {
    await _pump(tester, user: null);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    // The shared account sheet (the real sign-in entry) appears.
    expect(find.text('Sign in to sync your data'), findsOneWidget);
  });
}
