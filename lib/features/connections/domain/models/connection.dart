import 'package:equatable/equatable.dart';

/// The brand a connection belongs to, derived server-side.
///
/// SECURITY: for hosted vendors ([claude], [chatgpt]) this comes from the app's
/// VALIDATED OAuth redirect domain and is a trust signal (paired with
/// [Connection.verifiedDomain]). [codex] is the exception: Codex is a loopback
/// CLI with no verifiable domain, so it's a COSMETIC brand inferred from the
/// self-reported name only — never trust it for identity ([verifiedDomain] stays
/// null). [unknown] covers other loopback CLIs and unattributable clients.
enum ConnectionVendor { claude, chatgpt, codex, unknown }

/// A connected AI app (an OAuth client that has linked to the user's account).
///
/// Mirrors the backend `/api/mcp/connections` item contract:
/// `{ clientId, clientName, scope, resource, lastUsedAt, vendor,
/// verifiedDomain }`.
///
/// SECURITY: [clientName] is attacker-controlled display text supplied at OAuth
/// registration. It is shown for recognition only and must NEVER be treated as a
/// trust signal. The trust signals are [canPropose] (derived from [scope]),
/// [vendor], and [verifiedDomain] — all derived server-side.
class Connection extends Equatable {
  const Connection({
    required this.clientId,
    required this.clientName,
    required this.scope,
    this.resource,
    this.lastUsedAt,
    this.vendor = ConnectionVendor.unknown,
    this.verifiedDomain,
    this.autoApproveFoodLog = false,
    this.autoApproveWorkoutLog = false,
  });

  final String clientId;

  /// Untrusted display name supplied by the connecting app.
  final String clientName;

  /// Space-delimited OAuth scope string granted to this connection.
  final String scope;

  final String? resource;
  final DateTime? lastUsedAt;

  /// The TRUSTED brand, derived server-side from the validated OAuth redirect
  /// domain. Drives the brand mark; never inferred from [clientName].
  final ConnectionVendor vendor;

  /// The verified sign-in domain, e.g. `claude.ai` / `chatgpt.com`, or null for
  /// loopback CLIs / unknown clients. A trust caption near the name.
  final String? verifiedDomain;

  /// Per-connection auto-approve opt-ins. When true, a food_log / workout_log
  /// proposal from this app applies immediately instead of waiting in the
  /// proposals inbox. Auto-approved logs remain undoable in the app. Default
  /// false; the UI only exposes each toggle when the matching propose scope is
  /// granted ([canProposeFoodLog] / [canProposeWorkoutLog]).
  final bool autoApproveFoodLog;
  final bool autoApproveWorkoutLog;

  /// Whether this connection currently holds write/propose access — the trust
  /// signal the UI gates the "Limit to read-only" action on. True when any
  /// granted scope is a `propose:` scope.
  bool get canPropose =>
      scope.split(RegExp(r'\s+')).any((s) => s.startsWith('propose:'));

  /// Whether this connection holds the propose scope for a given log kind — the
  /// gate the corresponding auto-approve toggle is shown behind.
  bool get canProposeFoodLog =>
      scope.split(RegExp(r'\s+')).contains('propose:food_log');
  bool get canProposeWorkoutLog =>
      scope.split(RegExp(r'\s+')).contains('propose:workout_log');

  Connection copyWith({
    String? clientId,
    String? clientName,
    String? scope,
    String? resource,
    DateTime? lastUsedAt,
    ConnectionVendor? vendor,
    String? verifiedDomain,
    bool? autoApproveFoodLog,
    bool? autoApproveWorkoutLog,
  }) {
    return Connection(
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      scope: scope ?? this.scope,
      resource: resource ?? this.resource,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      vendor: vendor ?? this.vendor,
      verifiedDomain: verifiedDomain ?? this.verifiedDomain,
      autoApproveFoodLog: autoApproveFoodLog ?? this.autoApproveFoodLog,
      autoApproveWorkoutLog:
          autoApproveWorkoutLog ?? this.autoApproveWorkoutLog,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  /// Maps the trusted server-supplied `vendor` string to the enum. Anything
  /// other than the two known brands (including null) is [unknown].
  static ConnectionVendor _parseVendor(Object? raw) {
    switch (raw?.toString()) {
      case 'claude':
        return ConnectionVendor.claude;
      case 'chatgpt':
        return ConnectionVendor.chatgpt;
      case 'codex':
        return ConnectionVendor.codex;
      default:
        return ConnectionVendor.unknown;
    }
  }

  static String? _parseDomain(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      clientId: json['clientId']?.toString() ?? '',
      clientName: json['clientName']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      resource: json['resource']?.toString(),
      lastUsedAt: _parseDate(json['lastUsedAt']),
      vendor: _parseVendor(json['vendor']),
      verifiedDomain: _parseDomain(json['verifiedDomain']),
      autoApproveFoodLog: json['autoApproveFoodLog'] == true,
      autoApproveWorkoutLog: json['autoApproveWorkoutLog'] == true,
    );
  }

  @override
  List<Object?> get props => [
    clientId,
    clientName,
    scope,
    resource,
    lastUsedAt,
    vendor,
    verifiedDomain,
    autoApproveFoodLog,
    autoApproveWorkoutLog,
  ];
}
