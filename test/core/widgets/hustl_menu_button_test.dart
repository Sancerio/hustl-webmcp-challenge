import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';

/// Verifies the tab-root-aware leading control:
///
/// * A bare screen with no GoRouter ancestor shows the avatar (test-safe).
/// * A tab root always shows the avatar — even when `canPop()` is true because
///   a route lingers on the active branch navigator (the regression: the Train
///   tab root showed a back chevron instead of the account avatar).
/// * A genuinely pushed detail route shows the back button.
void main() {
  Finder backButton() => find.byType(BackButtonIcon);
  // The avatar is a CircleAvatar rendered inside the account IconButton.
  Finder avatar() => find.byType(CircleAvatar);

  testWidgets('bare screen (no GoRouter ancestor) shows the avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(appBar: null, body: Center(child: HustlMenuButton())),
      ),
    );
    await tester.pump();

    expect(avatar(), findsOneWidget);
    expect(backButton(), findsNothing);
  });

  GoRouter buildRouter() {
    final shellTrain = GlobalKey<NavigatorState>(debugLabel: 'train');
    return GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => shell,
          branches: [
            StatefulShellBranch(
              navigatorKey: shellTrain,
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(leading: const HustlMenuButton()),
                    body: Center(
                      child: ElevatedButton(
                        // A branch-scoped sheet (no useRootNavigator) leaves a
                        // poppable route on the Train branch navigator, so
                        // GoRouter.canPop() reports true on the tab root.
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => const SizedBox(height: 120),
                        ),
                        child: const Text('open sheet'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/nutrition',
                  builder: (context, state) =>
                      const Scaffold(body: Center(child: Text('nutrition'))),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) =>
              const Scaffold(body: Center(child: HustlMenuButton())),
        ),
      ],
    );
  }

  testWidgets('tab root shows the avatar even when canPop() is true', (
    tester,
  ) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Sanity: the tab root starts on the avatar.
    expect(avatar(), findsOneWidget);
    expect(backButton(), findsNothing);

    // Leave a poppable route on the Train branch navigator (a branch-scoped
    // sheet), so GoRouter.canPop() now reports true on the tab root — the exact
    // condition that used to flip the avatar to a back chevron.
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(
      router.canPop(),
      isTrue,
      reason: 'Branch-scoped sheet should make canPop() true.',
    );

    // The app-bar leading control on the tab root must remain the avatar even
    // though canPop() is true. (One avatar in the app bar; the sheet has none.)
    final appBarLeading = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(HustlMenuButton),
    );
    expect(
      find.descendant(of: appBarLeading, matching: avatar()),
      findsOneWidget,
      reason: 'A tab root must never show a back button.',
    );
    expect(
      find.descendant(of: appBarLeading, matching: backButton()),
      findsNothing,
    );
  });

  testWidgets('pushed detail route shows the back button', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/settings');
    await tester.pumpAndSettle();

    expect(router.canPop(), isTrue);
    expect(backButton(), findsOneWidget);
    expect(avatar(), findsNothing);
  });
}
