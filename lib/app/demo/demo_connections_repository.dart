import '../../features/connections/domain/models/connection.dart';
import '../../features/connections/domain/repositories/connections_repository.dart';
import 'demo_state.dart';

/// Deterministic in-memory [ConnectionsRepository] for demo mode.
///
/// The real repository talks to the backend app-plane (`/api/mcp/connections`),
/// which is unreachable offline and errors in demo mode. This seeds a small,
/// believable set of connected AI apps — Claude (verified, can propose),
/// ChatGPT (verified, read-only), and Codex (a loopback CLI with no verifiable
/// domain) — so the connected-apps surface renders richly for screenshots
/// (spec §10). All timestamps derive from the demo [anchor] so the same day
/// always yields identical rows. The mutation methods update the in-memory list
/// so the screen stays consistent if a row action is exercised, but never hit
/// the network.
class DemoConnectionsRepository implements ConnectionsRepository {
  DemoConnectionsRepository({required DateTime anchor, DemoState? state})
    : _state = state ?? DemoState(),
      _connections = _seed(anchor);

  final DemoState _state;
  final List<Connection> _connections;

  /// Scope strings mirror the backend grant shapes. A `propose:` scope is what
  /// the UI keys [Connection.canPropose] off, so Claude reads as "Can propose"
  /// and ChatGPT / Codex read as "Read-only".
  static const String _readScope =
      'read:workouts read:nutrition read:health read:profile';
  static const String _writeScope =
      'read:workouts read:nutrition read:health read:profile '
      'propose:templates propose:nutrition';

  static List<Connection> _seed(DateTime anchor) {
    // The anchor is local midnight "today"; offset back into the day / prior
    // days so each row gets a distinct, plausible "last used" caption.
    final claudeUsed = anchor.add(const Duration(hours: 8, minutes: 12));
    final chatgptUsed = anchor.subtract(const Duration(hours: 5));
    final codexUsed = anchor.subtract(const Duration(days: 2, hours: 3));

    return [
      Connection(
        clientId: 'demo-claude',
        clientName: 'Claude',
        scope: _writeScope,
        resource: 'https://offline.invalid',
        lastUsedAt: claudeUsed,
        vendor: ConnectionVendor.claude,
        verifiedDomain: 'claude.ai',
      ),
      Connection(
        clientId: 'demo-chatgpt',
        clientName: 'ChatGPT',
        scope: _readScope,
        resource: 'https://offline.invalid',
        lastUsedAt: chatgptUsed,
        vendor: ConnectionVendor.chatgpt,
        verifiedDomain: 'chatgpt.com',
      ),
      Connection(
        clientId: 'demo-codex',
        clientName: 'Codex CLI',
        scope: _readScope,
        resource: 'https://offline.invalid',
        lastUsedAt: codexUsed,
        vendor: ConnectionVendor.codex,
        verifiedDomain: null,
      ),
    ];
  }

  @override
  Future<bool> getWebMcpFoodAutoLog() async => _state.webMcpFoodAutoLog;

  @override
  Future<bool> setWebMcpFoodAutoLog(bool enabled) async {
    _state.webMcpFoodAutoLog = enabled;
    return _state.webMcpFoodAutoLog;
  }

  Connection? _find(String clientId) {
    for (final c in _connections) {
      if (c.clientId == clientId) return c;
    }
    return null;
  }

  void _replace(String clientId, Connection updated) {
    final index = _connections.indexWhere((c) => c.clientId == clientId);
    if (index != -1) _connections[index] = updated;
  }

  Connection _withScope(Connection c, String scope) => Connection(
    clientId: c.clientId,
    clientName: c.clientName,
    scope: scope,
    resource: c.resource,
    lastUsedAt: c.lastUsedAt,
    vendor: c.vendor,
    verifiedDomain: c.verifiedDomain,
  );

  @override
  Future<List<Connection>> list() async =>
      List<Connection>.unmodifiable(_connections);

  @override
  Future<void> stepDown(String clientId) async {
    final existing = _find(clientId);
    if (existing != null) _replace(clientId, _withScope(existing, _readScope));
  }

  @override
  Future<void> stepUp(String clientId) async {
    final existing = _find(clientId);
    if (existing != null) _replace(clientId, _withScope(existing, _writeScope));
  }

  @override
  Future<void> revoke(String clientId) async {
    _connections.removeWhere((c) => c.clientId == clientId);
  }

  @override
  Future<void> setAutoApprove({
    required String clientId,
    required String kind,
    required bool enabled,
  }) async {
    // Demo mode is in-memory only and the seed carries no auto-approve state to
    // reflect, so this is a no-op (never hits the network).
  }
}
