import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/main.dart' show createRouter;

void main() {
  testWidgets('Router lands on /auth/google/callback deep link', (
    tester,
  ) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.defaultRouteNameTestValue =
        '/auth/google/callback?code=abc&state=xyz';
    addTearDown(() {
      binding.platformDispatcher.defaultRouteNameTestValue = '/';
    });

    final router = createRouter(
      oauthCallbackBuilder: (context, state) {
        final code = state.uri.queryParameters['code'];
        final stateParam = state.uri.queryParameters['state'];
        return Scaffold(
          body: Text('oauth-callback code=$code state=$stateParam'),
        );
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.text('oauth-callback code=abc state=xyz'), findsOneWidget);
  });
}
