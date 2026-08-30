import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/connections/data/datasources/connections_api.dart';
import 'package:hustl_app/features/connections/domain/models/connection.dart';
import 'package:hustl_app/features/connections/domain/repositories/connections_repository.dart';
import 'package:hustl_app/features/connections/presentation/bloc/connections_bloc.dart';
import 'package:hustl_app/features/connections/presentation/bloc/connections_event.dart';
import 'package:hustl_app/features/connections/presentation/bloc/connections_state.dart';
import 'package:hustl_app/features/connections/presentation/widgets/connection_row.dart';
import 'package:hustl_app/features/connections/presentation/widgets/web_mcp_food_auto_log_card.dart';
import 'package:hustl_app/core/webmcp/web_mcp_access_gate.dart';

Connection _conn(String id, {bool canPropose = true, String? name}) {
  return Connection(
    clientId: id,
    clientName: name ?? 'App $id',
    scope: canPropose ? 'read:workouts propose:templates' : 'read:workouts',
    lastUsedAt: DateTime(2026, 6, 1),
  );
}

class _FakeRepo implements ConnectionsRepository {
  _FakeRepo(this._items, {this.throwOn});

  List<Connection> _items;

  /// When set, the matching action throws a [ConnectionsApiException].
  final String? throwOn; // 'step' | 'stepup' | 'revoke'

  int stepDownCount = 0;
  int stepUpCount = 0;
  int revokeCount = 0;
  bool webMcpFoodAutoLog = false;
  int getWebMcpFoodAutoLogCount = 0;
  int setWebMcpFoodAutoLogCount = 0;
  Completer<List<Connection>>? listCompleter;
  Completer<bool>? setWebMcpFoodAutoLogCompleter;

  @override
  Future<bool> getWebMcpFoodAutoLog() async {
    getWebMcpFoodAutoLogCount++;
    return webMcpFoodAutoLog;
  }

  @override
  Future<bool> setWebMcpFoodAutoLog(bool enabled) async {
    setWebMcpFoodAutoLogCount++;
    if (throwOn == 'webmcp') {
      throw ConnectionsApiException(
        statusCode: 500,
        code: 'settings_failed',
        message: 'not saved',
      );
    }
    final completer = setWebMcpFoodAutoLogCompleter;
    setWebMcpFoodAutoLogCompleter = null;
    if (completer != null) return completer.future;
    webMcpFoodAutoLog = enabled;
    return webMcpFoodAutoLog;
  }

  @override
  Future<List<Connection>> list() async {
    final completer = listCompleter;
    listCompleter = null;
    return completer?.future ?? _items;
  }

  @override
  Future<void> stepDown(String clientId) async {
    stepDownCount++;
    if (throwOn == 'step') {
      throw ConnectionsApiException(
        statusCode: 409,
        code: 'conflict',
        message: 'nope',
      );
    }
    _items = [
      for (final c in _items)
        if (c.clientId == clientId)
          Connection(
            clientId: c.clientId,
            clientName: c.clientName,
            scope: 'read:workouts',
            lastUsedAt: c.lastUsedAt,
          )
        else
          c,
    ];
  }

  @override
  Future<void> stepUp(String clientId) async {
    stepUpCount++;
    if (throwOn == 'stepup') {
      throw ConnectionsApiException(
        statusCode: 409,
        code: 'conflict',
        message: 'nope',
      );
    }
    _items = [
      for (final c in _items)
        if (c.clientId == clientId)
          Connection(
            clientId: c.clientId,
            clientName: c.clientName,
            scope: 'read:workouts propose:templates',
            lastUsedAt: c.lastUsedAt,
          )
        else
          c,
    ];
  }

  @override
  Future<void> revoke(String clientId) async {
    revokeCount++;
    if (throwOn == 'revoke') {
      throw ConnectionsApiException(
        statusCode: 401,
        code: 'unauthorized',
        message: 'signed out',
      );
    }
    _items = _items.where((c) => c.clientId != clientId).toList();
  }

  int setAutoApproveCount = 0;

  @override
  Future<void> setAutoApprove({
    required String clientId,
    required String kind,
    required bool enabled,
  }) async {
    setAutoApproveCount++;
    if (throwOn == 'auto') {
      throw ConnectionsApiException(
        statusCode: 500,
        code: 'set_auto_approve_failed',
        message: 'nope',
      );
    }
  }
}

void main() {
  group('ConnectionsBloc', () {
    test(
      'LoadConnections emits Loading then Loaded with scope-derived access',
      () async {
        final bloc = ConnectionsBloc(
          repository: _FakeRepo([
            _conn('a', canPropose: true),
            _conn('b', canPropose: false),
          ]),
        );
        final future = expectLater(
          bloc.stream,
          emitsInOrder([
            isA<ConnectionsLoading>(),
            isA<ConnectionsLoaded>().having((s) => s.items.length, 'len', 2),
          ]),
        );
        bloc.add(const LoadConnections());
        await future;
        final loaded = bloc.state as ConnectionsLoaded;
        expect(loaded.items[0].canPropose, isTrue);
        expect(loaded.items[1].canPropose, isFalse);
        await bloc.close();
      },
    );

    test(
      'ordinary builds do not read the WebMCP-only setting endpoint',
      () async {
        final repo = _FakeRepo([_conn('a')])..webMcpFoodAutoLog = true;
        final bloc = ConnectionsBloc(repository: repo);

        bloc.add(const LoadConnections());
        await bloc.stream.firstWhere((state) => state is ConnectionsLoaded);

        expect(repo.getWebMcpFoodAutoLogCount, 0);
        expect(
          (bloc.state as ConnectionsLoaded).webMcpFoodAutoLogEnabled,
          isFalse,
        );
        await bloc.close();
      },
    );

    test(
      'enabled WebMCP builds load the authoritative account setting',
      () async {
        final repo = _FakeRepo([_conn('a')])..webMcpFoodAutoLog = true;
        final bloc = ConnectionsBloc(repository: repo, webMcpEnabled: true);

        bloc.add(const LoadConnections());
        await bloc.stream.firstWhere((state) => state is ConnectionsLoaded);

        expect(repo.getWebMcpFoodAutoLogCount, 1);
        expect(
          (bloc.state as ConnectionsLoaded).webMcpFoodAutoLogEnabled,
          isTrue,
        );
        await bloc.close();
      },
    );

    test('account transition discards an old account setting load', () async {
      final gate = WebMcpAccessGate()..setReady(true);
      final oldLoad = Completer<List<Connection>>();
      final repo = _FakeRepo([_conn('new-account')])
        ..listCompleter = oldLoad
        ..webMcpFoodAutoLog = false;
      final bloc = ConnectionsBloc(
        repository: repo,
        webMcpEnabled: true,
        accessGate: gate,
      );

      bloc.add(const LoadConnections());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<ConnectionsLoading>());

      final generation = gate.closeForTransition();
      oldLoad.complete([_conn('old-account')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state, isA<ConnectionsLoading>());

      final reloaded = bloc.stream.firstWhere(
        (state) => state is ConnectionsLoaded,
      );
      gate.openIfCurrent(generation);
      await reloaded;

      final state = bloc.state as ConnectionsLoaded;
      expect(state.items.single.clientId, 'new-account');
      expect(state.webMcpFoodAutoLogEnabled, isFalse);
      await bloc.close();
    });

    test('account transition discards an old account setting save', () async {
      final gate = WebMcpAccessGate()..setReady(true);
      final save = Completer<bool>();
      final repo = _FakeRepo([_conn('old-account')])
        ..setWebMcpFoodAutoLogCompleter = save;
      final bloc = ConnectionsBloc(
        repository: repo,
        webMcpEnabled: true,
        accessGate: gate,
      );

      bloc.add(const LoadConnections());
      await bloc.stream.firstWhere((state) => state is ConnectionsLoaded);
      bloc.add(const SetWebMcpFoodAutoLog(true));
      await bloc.stream.firstWhere(
        (state) => state is ConnectionsLoaded && state.webMcpFoodAutoLogBusy,
      );

      gate.closeForTransition();
      save.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state, isA<ConnectionsLoading>());
      await bloc.close();
    });

    blocTest<ConnectionsBloc, ConnectionsState>(
      'Web auto-log changes only after the authoritative save succeeds',
      build: () => ConnectionsBloc(
        repository: _FakeRepo([_conn('a')]),
        webMcpEnabled: true,
      ),
      act: (bloc) async {
        bloc.add(const LoadConnections());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SetWebMcpFoodAutoLog(true));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final state = bloc.state as ConnectionsLoaded;
        expect(state.webMcpFoodAutoLogEnabled, isTrue);
        expect(state.webMcpFoodAutoLogBusy, isFalse);
        expect(state.webMcpSettingError, isNull);
      },
    );

    blocTest<ConnectionsBloc, ConnectionsState>(
      'a failed Web auto-log save retains OFF and exposes a retryable error',
      build: () => ConnectionsBloc(
        repository: _FakeRepo([_conn('a')], throwOn: 'webmcp'),
        webMcpEnabled: true,
      ),
      act: (bloc) async {
        bloc.add(const LoadConnections());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SetWebMcpFoodAutoLog(true));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final state = bloc.state as ConnectionsLoaded;
        expect(state.webMcpFoodAutoLogEnabled, isFalse);
        expect(state.webMcpFoodAutoLogBusy, isFalse);
        expect(state.webMcpSettingError, 'not saved');
      },
    );

    blocTest<ConnectionsBloc, ConnectionsState>(
      'step-down drops propose scope, keeps the row, and reports the outcome',
      build: () => ConnectionsBloc(repository: _FakeRepo([_conn('a')])),
      act: (bloc) async {
        bloc.add(const LoadConnections());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const StepDownConnection('a'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final s = bloc.state as ConnectionsLoaded;
        expect(s.items.map((c) => c.clientId), ['a']);
        expect(s.items.single.canPropose, isFalse);
        expect(s.inFlightIds, isEmpty);
        expect(s.lastOutcome?.kind, ConnectionActionKind.steppedDown);
      },
    );

    blocTest<ConnectionsBloc, ConnectionsState>(
      'step-up grants propose scope, keeps the row, and reports the outcome',
      build: () => ConnectionsBloc(
        repository: _FakeRepo([_conn('a', canPropose: false)]),
      ),
      act: (bloc) async {
        bloc.add(const LoadConnections());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const StepUpConnection('a'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final s = bloc.state as ConnectionsLoaded;
        expect(s.items.map((c) => c.clientId), ['a']);
        expect(s.items.single.canPropose, isTrue);
        expect(s.inFlightIds, isEmpty);
        expect(s.lastOutcome?.kind, ConnectionActionKind.steppedUp);
      },
    );

    blocTest<ConnectionsBloc, ConnectionsState>(
      'revoke removes the row and reports the outcome',
      build: () =>
          ConnectionsBloc(repository: _FakeRepo([_conn('a'), _conn('b')])),
      act: (bloc) async {
        bloc.add(const LoadConnections());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const RevokeConnection('a'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final s = bloc.state as ConnectionsLoaded;
        expect(s.items.map((c) => c.clientId), ['b']);
        expect(s.lastOutcome?.kind, ConnectionActionKind.revoked);
        expect(s.lastOutcome?.clientName, 'App a');
      },
    );

    blocTest<ConnectionsBloc, ConnectionsState>(
      'a failing action surfaces ConnectionsFailure and clears in-flight',
      build: () => ConnectionsBloc(
        repository: _FakeRepo([_conn('a')], throwOn: 'revoke'),
      ),
      act: (bloc) async {
        bloc.add(const LoadConnections());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const RevokeConnection('a'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state, isA<ConnectionsFailure>());
        final f = bloc.state as ConnectionsFailure;
        expect(f.code, 'unauthorized');
      },
    );

    test('Connection.canPropose is true only for propose: scopes', () {
      expect(_conn('x', canPropose: true).canPropose, isTrue);
      expect(_conn('x', canPropose: false).canPropose, isFalse);
      expect(
        const Connection(clientId: 'x', clientName: 'n', scope: '').canPropose,
        isFalse,
      );
    });
  });

  group('ConnectionRow', () {
    Future<void> pump(
      WidgetTester tester,
      Connection c, {
      VoidCallback? onStepDown,
      VoidCallback? onStepUp,
      VoidCallback? onRevoke,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionRow(
              connection: c,
              onStepDown: onStepDown ?? () {},
              onStepUp: onStepUp ?? () {},
              onRevoke: onRevoke ?? () {},
              onSetAutoApprove: (_, __) {},
              now: DateTime(2026, 6, 2),
            ),
          ),
        ),
      );
    }

    testWidgets('write access shows "Can propose" and the read-only action', (
      tester,
    ) async {
      await pump(tester, _conn('a', canPropose: true, name: 'Claude'));
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Can propose'), findsOneWidget);
      expect(find.text('Limit to read-only'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('read-only connection shows the allow-proposals action', (
      tester,
    ) async {
      await pump(tester, _conn('b', canPropose: false, name: 'Codex'));
      expect(find.text('Read-only'), findsOneWidget);
      expect(find.text('Limit to read-only'), findsNothing);
      expect(find.text('Allow proposals'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('tapping the actions fires the callbacks', (tester) async {
      var stepped = 0;
      var revoked = 0;
      await pump(
        tester,
        _conn('a', canPropose: true),
        onStepDown: () => stepped++,
        onRevoke: () => revoked++,
      );
      await tester.tap(find.text('Limit to read-only'));
      await tester.tap(find.text('Disconnect'));
      expect(stepped, 1);
      expect(revoked, 1);
    });

    testWidgets('tapping "Allow proposals" on a read-only row fires onStepUp', (
      tester,
    ) async {
      var steppedUp = 0;
      await pump(
        tester,
        _conn('b', canPropose: false),
        onStepUp: () => steppedUp++,
      );
      await tester.tap(find.text('Allow proposals'));
      expect(steppedUp, 1);
    });

    testWidgets(
      'actions stack without overflow on a narrow / large-text screen',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(1.5)),
                      child: ConnectionRow(
                        connection: _conn(
                          'a',
                          canPropose: true,
                          name: 'Claude',
                        ),
                        onStepDown: () {},
                        onStepUp: () {},
                        onRevoke: () {},
                        onSetAutoApprove: (_, __) {},
                        now: DateTime(2026, 6, 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // OverflowBar wraps the actions vertically rather than overflowing.
        expect(tester.takeException(), isNull);
        expect(find.text('Limit to read-only'), findsOneWidget);
        expect(find.text('Disconnect'), findsOneWidget);
      },
    );
  });

  group('WebMcpFoodAutoLogCard', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool enabled,
      bool busy = false,
      double width = 390,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: WebMcpFoodAutoLogCard(
                  enabled: enabled,
                  busy: busy,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('OFF explains Coach review and never implies persistence', (
      tester,
    ) async {
      await pump(tester, enabled: false);

      expect(find.text('Review before logging'), findsOneWidget);
      expect(find.textContaining('wait in Coach'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('ON communicates immediate logging, audit, and Undo', (
      tester,
    ) async {
      await pump(tester, enabled: true);

      expect(find.text('Food logs apply immediately'), findsOneWidget);
      expect(find.textContaining('AI Activity'), findsOneWidget);
      expect(find.textContaining('Undo'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('narrow ON state renders without overflow', (tester) async {
      await pump(tester, enabled: true, width: 300);
      expect(tester.takeException(), isNull);
      expect(find.text('Hustl Web auto-log'), findsOneWidget);
    });
  });
}
