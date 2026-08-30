import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/navigation/shell_web_mcp_tools.dart';
import 'package:hustl_app/core/webmcp/web_mcp_models.dart';

void main() {
  testWidgets('registers each tool once and disposes in reverse order', (
    tester,
  ) async {
    final events = <String>[];
    final host = _FakeHost(
      onRegister: (tool) async =>
          _FakeRegistration(() => events.add('dispose:${tool.name}')),
    );

    await tester.pumpWidget(_app(host: host, tools: _tools));
    await tester.pump();

    expect(host.registeredNames, ['one', 'two']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(events, ['dispose:two', 'dispose:one']);
  });

  testWidgets('does nothing when the browser host is unsupported', (
    tester,
  ) async {
    final host = _FakeHost(supported: false);

    await tester.pumpWidget(_app(host: host, tools: _tools));
    await tester.pump();

    expect(host.registeredNames, isEmpty);
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets('adds fresh registrations after SPA navigation', (tester) async {
    final navigationChanges = ChangeNotifier();
    final disposed = <String>[];
    final host = _FakeHost(
      onRegister: (tool) async =>
          _FakeRegistration(() => disposed.add(tool.name)),
    );

    await tester.pumpWidget(
      _app(host: host, tools: _tools, navigationChanges: navigationChanges),
    );
    await tester.pump();
    navigationChanges.notifyListeners();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(host.registeredNames, ['one', 'two', 'one', 'two']);
    expect(disposed, ['two', 'one']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(disposed, ['two', 'one', 'two', 'one']);
  });

  testWidgets('cancels a delayed navigation refresh when access is disabled', (
    tester,
  ) async {
    final navigationChanges = ChangeNotifier();
    final disposed = <String>[];
    final host = _FakeHost(
      onRegister: (tool) async =>
          _FakeRegistration(() => disposed.add(tool.name)),
    );

    await tester.pumpWidget(
      _app(host: host, tools: _tools, navigationChanges: navigationChanges),
    );
    await tester.pump();
    navigationChanges.notifyListeners();
    await tester.pumpWidget(
      _app(
        host: host,
        tools: _tools,
        navigationChanges: navigationChanges,
        enabled: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(host.registeredNames, ['one', 'two']);
    expect(disposed, ['two', 'one']);
  });

  testWidgets('disposes a registration that completes after shell teardown', (
    tester,
  ) async {
    final completer = Completer<WebMcpRegistration?>();
    var disposed = false;
    final host = _FakeHost(onRegister: (_) => completer.future);

    await tester.pumpWidget(_app(host: host, tools: [_tools.first]));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    completer.complete(_FakeRegistration(() => disposed = true));
    await tester.pump();

    expect(disposed, isTrue);
  });

  testWidgets('does not continue registration after shell teardown', (
    tester,
  ) async {
    final completer = Completer<WebMcpRegistration?>();
    var disposed = false;
    final host = _FakeHost(
      onRegister: (tool) => tool.name == 'one'
          ? completer.future
          : Future.value(_FakeRegistration(() {})),
    );

    await tester.pumpWidget(_app(host: host, tools: _tools));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    completer.complete(_FakeRegistration(() => disposed = true));
    await tester.pump();

    expect(disposed, isTrue);
    expect(host.registeredNames, ['one']);
  });

  testWidgets(
    'serializes a pending registration across disable and re-enable',
    (tester) async {
      final first = Completer<WebMcpRegistration?>();
      var calls = 0;
      final host = _FakeHost(
        onRegister: (_) {
          calls += 1;
          return calls == 1
              ? first.future
              : Future.value(_FakeRegistration(() {}));
        },
      );

      await tester.pumpWidget(_app(host: host, tools: [_tools.first]));
      await tester.pumpWidget(
        _app(host: host, tools: [_tools.first], enabled: false),
      );
      await tester.pumpWidget(_app(host: host, tools: [_tools.first]));

      first.complete(_FakeRegistration(() {}));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(host.registeredNames, ['one', 'one']);
    },
  );
}

Widget _app({
  required WebMcpHost host,
  required List<WebMcpToolDefinition> tools,
  Listenable? navigationChanges,
  bool enabled = true,
}) => MaterialApp(
  home: ShellWebMcpTools(
    enabled: enabled,
    host: host,
    tools: tools,
    navigationChanges: navigationChanges,
    child: const Text('shell'),
  ),
);

final _tools = [
  WebMcpToolDefinition(
    name: 'one',
    title: 'One',
    description: 'One test tool',
    inputSchema: const {'type': 'object'},
    handler: (_) async => const {'status': 'ok'},
  ),
  WebMcpToolDefinition(
    name: 'two',
    title: 'Two',
    description: 'Two test tool',
    inputSchema: const {'type': 'object'},
    handler: (_) async => const {'status': 'ok'},
  ),
];

class _FakeHost implements WebMcpHost {
  _FakeHost({this.supported = true, this.onRegister});

  final bool supported;
  final Future<WebMcpRegistration?> Function(WebMcpToolDefinition tool)?
  onRegister;
  final List<String> registeredNames = [];
  final Set<String> _activeNames = {};

  @override
  bool get isSupported => supported;

  @override
  Future<WebMcpRegistration?> registerTool(WebMcpToolDefinition tool) async {
    if (!_activeNames.add(tool.name)) {
      throw StateError('duplicate tool name: ${tool.name}');
    }
    registeredNames.add(tool.name);
    final registration =
        await (onRegister?.call(tool) ??
            Future.value(_FakeRegistration(() {})));
    if (registration == null) {
      _activeNames.remove(tool.name);
      return null;
    }
    return _FakeRegistration(() {
      registration.dispose();
      _activeNames.remove(tool.name);
    });
  }
}

class _FakeRegistration implements WebMcpRegistration {
  _FakeRegistration(this.onDispose);

  final void Function() onDispose;

  @override
  void dispose() => onDispose();
}
