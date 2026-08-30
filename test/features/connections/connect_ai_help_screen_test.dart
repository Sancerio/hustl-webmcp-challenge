import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/connections/presentation/screens/connect_ai_help_screen.dart';
import 'package:hustl_app/features/connections/presentation/widgets/connect_help_data.dart';

// The picker and the per-platform article are now SEPARATE routes (so the AppBar
// back button and the native iOS swipe both return to the picker, and an article
// URL is deep-linkable / refreshable on web). These tests drive a real GoRouter.
GoRouter _router({String initial = '/connections/help'}) {
  return GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/connections/help',
        builder: (_, __) => const ConnectAiHelpScreen(),
      ),
      GoRoute(
        path: '/connections/help/:client',
        builder: (_, state) {
          final client = connectHelpClientById(state.pathParameters['client']);
          return client == null
              ? const ConnectAiHelpScreen()
              : ConnectAiHelpArticleScreen(client: client);
        },
      ),
    ],
  );
}

Future<void> pump(WidgetTester tester, {String initial = '/connections/help'}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router(initial: initial)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picker lists every platform, with no steps shown yet',
      (tester) async {
    await pump(tester);

    for (final title in const [
      'Claude (claude.ai / Desktop)',
      'Claude Code (CLI)',
      'Codex',
      'ChatGPT',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing: $title');
    }
    // Steps, commands, and the connector URL stay hidden until a platform is
    // chosen — that is the whole point of the picker-first flow.
    expect(find.text('Connector URL'), findsNothing);
    expect(
      find.textContaining('claude mcp add --transport http hustl'),
      findsNothing,
    );
  });

  testWidgets('tapping a platform navigates to its article route',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Claude Code (CLI)'));
    await tester.pumpAndSettle();

    expect(find.text('Connector URL'), findsOneWidget);
    expect(
      find.textContaining('claude mcp add --transport http hustl'),
      findsOneWidget,
    );
    // A real, copyable connector URL is shown — never the unfillable placeholder.
    expect(find.textContaining('offline.invalid/mcp'), findsWidgets);
    expect(find.textContaining('<your-mcp-host>'), findsNothing);
  });

  testWidgets('back from an article returns to the picker', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[mcp_servers.hustl]'), findsOneWidget);

    // AppBar back button (and, on iOS, the native swipe) pops to the picker.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Choose your app'), findsOneWidget);
    expect(find.text('ChatGPT'), findsOneWidget);
  });

  testWidgets('an article URL renders directly (deep link / web refresh)',
      (tester) async {
    await pump(tester, initial: '/connections/help/codex');

    // No picker step needed — the article renders straight from its URL.
    expect(find.text('Connector URL'), findsOneWidget);
    expect(find.textContaining('[mcp_servers.hustl]'), findsOneWidget);
  });

  testWidgets('an unknown platform slug falls back to the picker',
      (tester) async {
    await pump(tester, initial: '/connections/help/bogus');

    expect(find.text('Choose your app'), findsOneWidget);
    expect(find.text('Connector URL'), findsNothing);
  });
}
