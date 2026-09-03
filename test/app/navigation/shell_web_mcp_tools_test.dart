import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/navigation/shell_web_mcp_tools.dart';
import 'package:hustl_app/core/webmcp/hustl_web_mcp_coordinator.dart';
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

  testWidgets('forwards every annotation through the handler proxy', (
    tester,
  ) async {
    final host = _FakeHost();
    final tool = WebMcpToolDefinition(
      name: 'annotated',
      title: 'Annotated',
      description: 'Exercises complete annotation forwarding',
      inputSchema: const {'type': 'object'},
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
      untrustedContentHint: true,
      handler: (_) async => const {'status': 'ready'},
    );

    await tester.pumpWidget(_app(host: host, tools: [tool]));
    await tester.pump();

    final registered = host.registeredTools.single;
    expect(registered.readOnlyHint, isFalse);
    expect(registered.destructiveHint, isTrue);
    expect(registered.idempotentHint, isFalse);
    expect(registered.openWorldHint, isTrue);
    expect(registered.untrustedContentHint, isTrue);
    expect(registered.toRegistrationJson(), tool.toRegistrationJson());
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

  testWidgets(
    'rebinds repeated Coach reviews without crossing descriptor budget',
    (tester) async {
      var route = '/proposals';
      final navigationChanges = ChangeNotifier();
      final host = _FakeHost();
      final coordinator = _RouteCoordinator(
        tools: (registeredRoute, currentRoute) =>
            _coachTools(registeredRoute, currentRoute),
        stableScope: (registeredRoute) =>
            registeredRoute == '/proposals' ||
                registeredRoute.startsWith('/proposals/')
            ? '/proposals'
            : null,
      );

      await tester.pumpWidget(
        _app(
          host: host,
          coordinator: coordinator,
          currentRoute: () => route,
          navigationChanges: navigationChanges,
        ),
      );
      await tester.pump();

      expect(host.registeredNames, _coachToolNames);
      expect(host.activeNames, _coachToolNames.toSet());
      host.beginDescriptorTracking(seed: 7, limit: 10);

      route = '/proposals/nutrition-target-1';
      navigationChanges.notifyListeners();
      expect(await host.invoke('hustl_get_coach_activity'), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(await host.invoke('hustl_get_coach_activity'), {
        'status': 'ready',
        'route': '/proposals/nutrition-target-1',
      });

      for (final nextRoute in [
        '/proposals',
        '/proposals/upper-a-1',
        '/proposals',
        '/proposals/lower-a-1',
        '/proposals',
        '/proposals/upper-b-1',
        '/proposals',
        '/proposals/lower-b-1',
        '/proposals',
      ]) {
        route = nextRoute;
        navigationChanges.notifyListeners();
        await tester.pump(const Duration(milliseconds: 300));

        expect(await host.invoke('hustl_get_coach_activity'), {
          'status': 'ready',
          'route': nextRoute,
        });
      }

      expect(host.registeredNames, _coachToolNames);
      expect(host.activeNames, _coachToolNames.toSet());
      expect(host.descriptorChanges, 7);
    },
  );

  testWidgets('requires full descriptor identity before Coach rebinding', (
    tester,
  ) async {
    var route = '/proposals';
    final navigationChanges = ChangeNotifier();
    final disposed = <String>[];
    final host = _FakeHost(
      onRegister: (tool) async =>
          _FakeRegistration(() => disposed.add(tool.name)),
    );
    final coordinator = _RouteCoordinator(
      tools: (registeredRoute, currentRoute) => [
        WebMcpToolDefinition(
          name: 'coach_route_probe',
          title: 'Coach route probe',
          description: registeredRoute == '/proposals'
              ? 'Inbox descriptor'
              : 'Changed detail descriptor',
          inputSchema: const {'type': 'object'},
          readOnlyHint: true,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: false,
          handler: (_) async => currentRoute() == registeredRoute
              ? {'status': 'ready', 'route': registeredRoute}
              : const {'status': 'unavailable', 'code': 'stale_route'},
        ),
      ],
      stableScope: (_) => '/proposals',
    );

    await tester.pumpWidget(
      _app(
        host: host,
        coordinator: coordinator,
        currentRoute: () => route,
        navigationChanges: navigationChanges,
      ),
    );
    await tester.pump();
    final retainedProbe = host.activeTool('coach_route_probe');

    route = '/proposals/proposal-1';
    navigationChanges.notifyListeners();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(host.registeredNames, ['coach_route_probe', 'coach_route_probe']);
    expect(disposed, ['coach_route_probe']);
    expect(await retainedProbe.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    expect(await host.invoke('coach_route_probe'), {
      'status': 'ready',
      'route': '/proposals/proposal-1',
    });
  });

  testWidgets('keeps template detail registrations exact-resource scoped', (
    tester,
  ) async {
    var route = '/templates/template-a';
    final navigationChanges = ChangeNotifier();
    final disposed = <String>[];
    final host = _FakeHost(
      onRegister: (tool) async =>
          _FakeRegistration(() => disposed.add(tool.name)),
    );
    final coordinator = _RouteCoordinator(
      tools: (registeredRoute, currentRoute) =>
          _templateTools(registeredRoute, currentRoute),
    );

    await tester.pumpWidget(
      _app(
        host: host,
        coordinator: coordinator,
        currentRoute: () => route,
        navigationChanges: navigationChanges,
      ),
    );
    await tester.pump();
    final retainedEdit = host.activeTool('template_edit');

    route = '/templates/template-b';
    navigationChanges.notifyListeners();
    expect(await retainedEdit.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(host.registeredNames, [
      'common',
      'template_edit',
      'common',
      'template_edit',
    ]);
    expect(disposed, ['template_edit', 'common']);
    expect(await retainedEdit.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    expect(await host.invoke('template_edit'), {
      'status': 'ready',
      'route': '/templates/template-b',
    });
  });

  testWidgets('removes a partial replacement catalog after failure', (
    tester,
  ) async {
    var route = '/first';
    final navigationChanges = ChangeNotifier();
    final disposed = <String>[];
    final host = _FakeHost(
      onRegister: (tool) async => tool.name == 'four'
          ? null
          : _FakeRegistration(() => disposed.add(tool.name)),
    );
    final coordinator = _RouteCoordinator(
      tools: (registeredRoute, currentRoute) => registeredRoute == '/first'
          ? [
              _routeTool(
                name: 'one',
                expectedRoute: registeredRoute,
                currentRoute: currentRoute,
              ),
              _routeTool(
                name: 'two',
                expectedRoute: registeredRoute,
                currentRoute: currentRoute,
              ),
            ]
          : [
              _routeTool(
                name: 'three',
                expectedRoute: registeredRoute,
                currentRoute: currentRoute,
              ),
              _routeTool(
                name: 'four',
                expectedRoute: registeredRoute,
                currentRoute: currentRoute,
              ),
            ],
    );

    await tester.pumpWidget(
      _app(
        host: host,
        coordinator: coordinator,
        currentRoute: () => route,
        navigationChanges: navigationChanges,
      ),
    );
    await tester.pump();
    final retainedOne = host.activeTool('one');

    route = '/second';
    navigationChanges.notifyListeners();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(host.registeredNames, ['one', 'two', 'three', 'four']);
    expect(host.activeNames, isEmpty);
    expect(disposed, ['two', 'one', 'three']);
    expect(await retainedOne.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    expect(await host.registeredTools[2].handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
  });

  testWidgets('provisional callbacks stay inactive until full batch commit', (
    tester,
  ) async {
    final laterRegistration = Completer<WebMcpRegistration?>();
    var proposalWrites = 0;
    final host = _FakeHost(
      onRegister: (tool) => tool.name == 'later_tool'
          ? laterRegistration.future
          : Future.value(_FakeRegistration(() {})),
    );
    final tools = [
      WebMcpToolDefinition(
        name: 'proposal_writer',
        title: 'Proposal writer',
        description: 'Writes one test proposal',
        inputSchema: const {'type': 'object'},
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
        handler: (_) async {
          proposalWrites += 1;
          return const {'status': 'created'};
        },
      ),
      WebMcpToolDefinition(
        name: 'later_tool',
        title: 'Later tool',
        description: 'Completes the registration batch',
        inputSchema: const {'type': 'object'},
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
        handler: (_) async => const {'status': 'ready'},
      ),
    ];

    await tester.pumpWidget(_app(host: host, tools: tools));
    await tester.pump();
    expect(host.registeredNames, ['proposal_writer', 'later_tool']);

    expect(await host.registeredTools.first.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    expect(proposalWrites, 0);

    laterRegistration.complete(null);
    await tester.pump();

    expect(host.activeNames, isEmpty);
    expect(proposalWrites, 0);
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

  testWidgets('teardown disposes a completed partial registration batch', (
    tester,
  ) async {
    final second = Completer<WebMcpRegistration?>();
    final disposed = <String>[];
    final host = _FakeHost(
      onRegister: (tool) => tool.name == 'two'
          ? second.future
          : Future.value(_FakeRegistration(() => disposed.add(tool.name))),
    );

    await tester.pumpWidget(_app(host: host, tools: _tools));
    await tester.pump();
    expect(host.registeredNames, ['one', 'two']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(disposed, ['one']);

    second.complete(_FakeRegistration(() => disposed.add('two')));
    await tester.pump();

    expect(disposed, ['one', 'two']);
    expect(host.activeNames, isEmpty);
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

  testWidgets('registers global tools for an unmatched nested proposal route', (
    tester,
  ) async {
    final router = _proposalRouter('/proposals/one/two');
    addTearDown(router.dispose);
    final gate = ValueNotifier(false);
    addTearDown(gate.dispose);
    final host = _FakeHost();

    await tester.pumpWidget(
      _routerApp(
        router: router,
        gate: gate,
        host: host,
        coordinator: _proposalRouteCoordinator(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('not found'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.matches, isEmpty);
    expect(webMcpRouteForRouter(router), '/proposals/one/two');
    expect(host.registeredNames, isEmpty);

    gate.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(host.registeredNames, _globalToolNames);
    expect(host.activeNames, _globalToolNames.toSet());
  });

  testWidgets('keeps the proposal identifier length boundary exact', (
    tester,
  ) async {
    for (final testCase in [
      (length: 129, expectedNames: _globalToolNames),
      (length: 128, expectedNames: _coachToolNames),
    ]) {
      final route = '/proposals/${'a' * testCase.length}';
      final router = _proposalRouter(route);
      final gate = ValueNotifier(true);
      final host = _FakeHost();

      await tester.pumpWidget(
        _routerApp(
          router: router,
          gate: gate,
          host: host,
          coordinator: _proposalRouteCoordinator(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('proposal detail'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.matches, isNotEmpty);
      expect(webMcpRouteForRouter(router), route);
      expect(host.registeredNames, testCase.expectedNames);
      expect(host.activeNames, testCase.expectedNames.toSet());

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      gate.dispose();
      router.dispose();
    }
  });

  testWidgets(
    'replaces Coach tools with globals on nested invalid navigation',
    (tester) async {
      final route = '/proposals/${'a' * 128}';
      final router = _proposalRouter(route);
      addTearDown(router.dispose);
      final gate = ValueNotifier(true);
      addTearDown(gate.dispose);
      final host = _FakeHost();

      await tester.pumpWidget(
        _routerApp(
          router: router,
          gate: gate,
          host: host,
          coordinator: _proposalRouteCoordinator(),
        ),
      );
      await tester.pumpAndSettle();
      expect(host.activeNames, _coachToolNames.toSet());

      router.go('/proposals/one/two');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('not found'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.matches, isEmpty);
      expect(webMcpRouteForRouter(router), '/proposals/one/two');
      expect(host.registeredNames, [..._coachToolNames, ..._globalToolNames]);
      expect(host.activeNames, _globalToolNames.toSet());
    },
  );
}

Widget _routerApp({
  required GoRouter router,
  required ValueNotifier<bool> gate,
  required WebMcpHost host,
  required HustlWebMcpCoordinator coordinator,
}) => MaterialApp.router(
  routerConfig: router,
  builder: (context, child) => ValueListenableBuilder<bool>(
    valueListenable: gate,
    child: child ?? const SizedBox.shrink(),
    builder: (context, enabled, child) => ShellWebMcpTools(
      enabled: enabled,
      host: host,
      coordinator: coordinator,
      navigate: router.go,
      currentRoute: () => webMcpRouteForRouter(router),
      navigationChanges: router.routerDelegate,
      child: child!,
    ),
  ),
);

GoRouter _proposalRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('home')),
    GoRoute(path: '/proposals', builder: (_, _) => const Text('proposals')),
    GoRoute(
      path: '/proposals/:id',
      builder: (_, _) => const Text('proposal detail'),
    ),
  ],
  errorBuilder: (_, _) => const Text('not found'),
);

_RouteCoordinator _proposalRouteCoordinator() => _RouteCoordinator(
  tools: (route, currentRoute) {
    final names = _hasValidProposalId(route)
        ? _coachToolNames
        : _globalToolNames;
    return names
        .map(
          (name) => _routeTool(
            name: name,
            expectedRoute: route,
            currentRoute: currentRoute,
          ),
        )
        .toList(growable: false);
  },
  stableScope: (route) =>
      route == '/proposals' || _hasValidProposalId(route) ? '/proposals' : null,
);

bool _hasValidProposalId(String route) {
  final segments = Uri.parse(route).pathSegments;
  return segments.length == 2 &&
      segments.first == 'proposals' &&
      segments.last.isNotEmpty &&
      segments.last.length <= 128;
}

Widget _app({
  required WebMcpHost host,
  List<WebMcpToolDefinition>? tools,
  HustlWebMcpCoordinator? coordinator,
  WebMcpCurrentRoute? currentRoute,
  Listenable? navigationChanges,
  bool enabled = true,
}) => MaterialApp(
  home: ShellWebMcpTools(
    enabled: enabled,
    host: host,
    tools: tools,
    coordinator: coordinator,
    currentRoute: currentRoute,
    navigate: (_) {},
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
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    handler: (_) async => const {'status': 'ok'},
  ),
  WebMcpToolDefinition(
    name: 'two',
    title: 'Two',
    description: 'Two test tool',
    inputSchema: const {'type': 'object'},
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    handler: (_) async => const {'status': 'ok'},
  ),
];

const _coachToolNames = [
  'hustl_get_today_context',
  'hustl_open_surface',
  'hustl_get_coach_activity',
  'hustl_get_coaching_trends',
  'hustl_open_proposal',
  'hustl_propose_nutrition_targets',
  'hustl_propose_food_log',
];

const _globalToolNames = ['hustl_get_today_context', 'hustl_open_surface'];

List<WebMcpToolDefinition> _coachTools(
  String route,
  WebMcpCurrentRoute currentRoute,
) => _coachToolNames
    .map(
      (name) => _routeTool(
        name: name,
        expectedRoute: route,
        currentRoute: currentRoute,
      ),
    )
    .toList(growable: false);

List<WebMcpToolDefinition> _templateTools(
  String route,
  WebMcpCurrentRoute currentRoute,
) => [
  _routeTool(name: 'common', expectedRoute: route, currentRoute: currentRoute),
  _routeTool(
    name: 'template_edit',
    expectedRoute: route,
    currentRoute: currentRoute,
  ),
];

WebMcpToolDefinition _routeTool({
  required String name,
  required String expectedRoute,
  required WebMcpCurrentRoute currentRoute,
}) => WebMcpToolDefinition(
  name: name,
  title: name,
  description: '$name test tool',
  inputSchema: const {'type': 'object'},
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
  handler: (_) async => currentRoute() == expectedRoute
      ? {'status': 'ready', 'route': expectedRoute}
      : const {'status': 'unavailable', 'code': 'stale_route'},
);

class _RouteCoordinator implements HustlWebMcpCoordinator {
  _RouteCoordinator({required this.tools, this.stableScope});

  final List<WebMcpToolDefinition> Function(
    String route,
    WebMcpCurrentRoute currentRoute,
  )
  tools;
  final String? Function(String route)? stableScope;

  @override
  List<WebMcpToolDefinition> toolsForRoute({
    required String route,
    required WebMcpCurrentRoute currentRoute,
    required WebMcpNavigate navigate,
  }) => tools(route, currentRoute);

  @override
  String? stableRegistrationScopeForRoute(String route) =>
      stableScope?.call(route);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHost implements WebMcpHost {
  _FakeHost({this.supported = true, this.onRegister});

  final bool supported;
  final Future<WebMcpRegistration?> Function(WebMcpToolDefinition tool)?
  onRegister;
  final List<String> registeredNames = [];
  final List<WebMcpToolDefinition> registeredTools = [];
  final Set<String> _activeNames = {};
  final Map<String, WebMcpToolDefinition> _activeTools = {};
  bool _trackDescriptors = false;
  int? _descriptorLimit;
  int descriptorChanges = 0;

  Set<String> get activeNames => Set.unmodifiable(_activeNames);

  WebMcpToolDefinition activeTool(String name) => _activeTools[name]!;

  Future<Map<String, Object?>> invoke(String name) =>
      activeTool(name).handler(const {});

  void beginDescriptorTracking({required int seed, required int limit}) {
    descriptorChanges = seed;
    _descriptorLimit = limit;
    _trackDescriptors = true;
  }

  @override
  bool get isSupported => supported;

  @override
  Future<WebMcpRegistration?> registerTool(WebMcpToolDefinition tool) async {
    if (_trackDescriptors) {
      descriptorChanges += 1;
      if (descriptorChanges > _descriptorLimit!) return null;
    }
    if (!_activeNames.add(tool.name)) {
      throw StateError('duplicate tool name: ${tool.name}');
    }
    registeredNames.add(tool.name);
    registeredTools.add(tool);
    _activeTools[tool.name] = tool;
    WebMcpRegistration? registration;
    try {
      registration =
          await (onRegister?.call(tool) ??
              Future.value(_FakeRegistration(() {})));
    } catch (_) {
      _activeNames.remove(tool.name);
      _activeTools.remove(tool.name);
      rethrow;
    }
    if (registration == null) {
      _activeNames.remove(tool.name);
      _activeTools.remove(tool.name);
      return null;
    }
    final activeRegistration = registration;
    return _FakeRegistration(() {
      activeRegistration.dispose();
      _activeNames.remove(tool.name);
      _activeTools.remove(tool.name);
      if (_trackDescriptors && _activeNames.isEmpty) {
        descriptorChanges += 1;
      }
    });
  }
}

class _FakeRegistration implements WebMcpRegistration {
  _FakeRegistration(this.onDispose);

  final void Function() onDispose;

  @override
  void dispose() => onDispose();
}
