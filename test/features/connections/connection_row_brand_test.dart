import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/connections/domain/models/connection.dart';
import 'package:hustl_app/features/connections/presentation/widgets/brand_mark.dart';
import 'package:hustl_app/features/connections/presentation/widgets/connection_row.dart';

Connection _conn({
  required ConnectionVendor vendor,
  String name = 'Some App',
  String? verifiedDomain,
}) {
  return Connection(
    clientId: 'c1',
    clientName: name,
    scope: 'read:workouts',
    vendor: vendor,
    verifiedDomain: verifiedDomain,
    lastUsedAt: DateTime(2026, 6, 1),
  );
}

Widget _host(Connection connection) {
  return MaterialApp(
    home: Scaffold(
      body: ConnectionRow(
        connection: connection,
        now: DateTime(2026, 6, 2),
        onStepDown: () {},
        onStepUp: () {},
        onRevoke: () {},
        onSetAutoApprove: (_, __) {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows the Claude brand mark when vendor==claude', (tester) async {
    await tester.pumpWidget(_host(_conn(vendor: ConnectionVendor.claude)));

    expect(find.byType(BrandMark), findsOneWidget);
    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = svg.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/icons/brand_claude.svg');
    // The generic fallback glyph must NOT render for a known vendor.
    expect(find.byIcon(Icons.hub_outlined), findsNothing);
  });

  testWidgets('shows the ChatGPT brand mark when vendor==chatgpt',
      (tester) async {
    await tester.pumpWidget(_host(_conn(vendor: ConnectionVendor.chatgpt)));

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = svg.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/icons/brand_chatgpt.svg');
  });

  testWidgets('shows the Codex brand mark when vendor==codex', (tester) async {
    await tester.pumpWidget(_host(_conn(vendor: ConnectionVendor.codex)));

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = svg.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/icons/brand_codex.svg');
    expect(find.byIcon(Icons.hub_outlined), findsNothing);
  });

  testWidgets('falls back to the generic hub avatar when vendor is unknown',
      (tester) async {
    await tester.pumpWidget(_host(_conn(vendor: ConnectionVendor.unknown)));

    expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('shows the trusted "via <domain>" caption when verified',
      (tester) async {
    await tester.pumpWidget(
      _host(_conn(
        vendor: ConnectionVendor.claude,
        verifiedDomain: 'claude.ai',
      )),
    );

    expect(find.text('via claude.ai'), findsOneWidget);
  });

  testWidgets('brand mark is keyed off vendor, NOT the client name',
      (tester) async {
    // Attacker-controlled name claims "ChatGPT" but the trusted vendor is
    // unknown — the UI must show the generic fallback, never the ChatGPT mark.
    await tester.pumpWidget(
      _host(_conn(vendor: ConnectionVendor.unknown, name: 'ChatGPT')),
    );

    expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });
}
