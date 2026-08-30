import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/token_storage.dart';
import '../domain/models/proposal_summary.dart';
import '../domain/repositories/proposals_repository.dart';
import 'proposal_events_service.dart';

/// Polls the pending-proposal count and broadcasts it via
/// [ProposalEventsService]. Poll-on-resume + periodic, modeled on
/// `WorkoutSyncService`/`TemplateSyncService`:
/// - `didChangeAppLifecycleState(resumed)` with a 500ms debounce + a short
///   cooldown so a flurry of resume events triggers at most one refresh,
/// - a `Timer.periodic(10min)` with exponential backoff on failure.
///
/// The count always reflects SERVER state (the user's pending proposals), never
/// the local write-consent preference — so a grant created on another device, a
/// grant created before the toggle, or a failed kill-switch can't hide real
/// pending proposals behind a local flag. The toggle enforces write access
/// server-side (kill-switch); the badge just reports reality.
class ProposalCountService with WidgetsBindingObserver {
  ProposalCountService(
    this._tokens,
    this._repository,
    this._events, {
    NotificationService? notifications,
    PreferencesService? preferences,
  })  : _notifications = notifications,
        _preferences = preferences;

  final TokenStorage _tokens;
  final ProposalsRepository _repository;
  final ProposalEventsService _events;
  // Optional: when both are present, each poll also surfaces a local notification
  // (with undo) for newly AUTO-applied logs. Absent in tests / on web.
  final NotificationService? _notifications;
  final PreferencesService? _preferences;

  Timer? _timer;
  bool _isRefreshing = false;
  bool _observerAttached = false;
  Duration _backoff = Duration.zero;
  // When a refresh last ran (success or failure). Drives elapsed-vs-backoff so a
  // short backoff doesn't burn a whole periodic tick.
  DateTime? _lastAttemptAt;

  static const Duration _minInterval = Duration(minutes: 10);
  static const Duration _maxBackoff = Duration(minutes: 30);
  static const Duration _resumeCooldown = Duration(seconds: 2);

  Timer? _resumeDebouncer;
  DateTime? _lastRefreshAt;

  /// Refresh the pending count immediately. No-ops if unauthenticated or if a
  /// refresh is already in flight. Always reads server state (not the local
  /// consent flag) so real pending proposals are never hidden.
  Future<void> refreshNow() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final token = await _tokens.getAccessToken();
      if (token == null || token.isEmpty) {
        // Unauthenticated: clear any prior account's badge so a sign-out can't
        // leave a stale count visible.
        _events.setCount(0);
        _backoff = Duration.zero;
        return;
      }
      _lastAttemptAt = DateTime.now();
      final items = await _repository.listPending(limit: 50);
      _events.setCount(items.length);
      _lastRefreshAt = DateTime.now();
      _backoff = Duration.zero;
      // Best-effort: notify (with undo) about any auto-applied logs since last
      // poll. Never let this disturb the count refresh or its backoff.
      unawaited(_notifyAutoLogs());
    } catch (_) {
      _lastAttemptAt = DateTime.now();
      _backoff = _backoff == Duration.zero
          ? const Duration(minutes: 2)
          : _backoff * 2;
      if (_backoff > _maxBackoff) _backoff = _maxBackoff;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Surface a local notification (with undo) for each newly auto-applied log
  /// since the last poll. Uses an applied_at watermark in prefs so each is shown
  /// once. On the FIRST run (no watermark) it only records the watermark — it
  /// never backfills a notification for logs created before the feature existed.
  Future<void> _notifyAutoLogs() async {
    final notifications = _notifications;
    final prefs = _preferences;
    if (notifications == null || prefs == null) return;
    try {
      final lastSeen = await prefs.getAiAutoLogLastSeen();
      // Capture BEFORE the query so a log auto-applied between the query running
      // and the watermark write isn't skipped on the first (empty) run.
      final pollStartedAt = DateTime.now();
      final logs = await _repository.listAutoAppliedLogs(since: lastSeen);
      if (logs.isEmpty) {
        if (lastSeen == null) await prefs.setAiAutoLogLastSeen(pollStartedAt);
        return;
      }
      if (lastSeen == null) {
        // First run with a backlog: adopt the newest as the watermark without
        // notifying, so we don't fire a burst for history.
        await prefs.setAiAutoLogLastSeen(logs.first.appliedAt ?? DateTime.now());
        return;
      }
      // Oldest → newest so the most recent ends up on top of the shade.
      var maxSeen = lastSeen;
      for (final log in logs.reversed) {
        await notifications.showAutoLoggedProposal(
          id: log.id,
          isFood: log.kind == ProposalKind.foodLog,
          body: log.summary ?? 'Tap to review or undo',
        );
        final at = log.appliedAt;
        if (at != null && at.isAfter(maxSeen)) maxSeen = at;
      }
      await prefs.setAiAutoLogLastSeen(maxSeen);
    } catch (_) {
      // Best-effort: a notification failure must never affect the badge poll.
    }
  }

  /// Start periodic polling + attach the lifecycle observer (idempotent).
  void start() {
    if (_timer?.isActive == true) {
      // Already polling (e.g. started unauthenticated at bootstrap). A later
      // start() — e.g. AuthSyncListeners on sign-in — must still refresh NOW so
      // pending proposals aren't hidden until the next ~10-minute tick.
      unawaited(refreshNow());
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(_minInterval, (_) async {
      // While backing off, only skip the tick if not enough time has ELAPSED
      // since the last attempt. Comparing elapsed-vs-backoff (instead of
      // decrementing the backoff by a whole _minInterval per tick) means a short
      // backoff resolves on the next tick rather than burning a full interval.
      if (_backoff > Duration.zero) {
        final last = _lastAttemptAt;
        if (last != null && DateTime.now().difference(last) < _backoff) {
          return;
        }
      }
      await refreshNow();
    });
    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }
    // Fire one immediate refresh so the badge is correct on launch.
    unawaited(refreshNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _resumeDebouncer?.cancel();
    _resumeDebouncer = null;
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _resumeDebouncer?.cancel();
    _resumeDebouncer = Timer(const Duration(milliseconds: 500), () {
      final now = DateTime.now();
      if (_lastRefreshAt != null &&
          now.difference(_lastRefreshAt!) < _resumeCooldown) {
        return;
      }
      unawaited(refreshNow());
    });
  }

  /// Drive the auto-log notification pass directly (bypassing auth/poll) so the
  /// watermark + first-run behavior is unit-testable.
  @visibleForTesting
  Future<void> debugNotifyAutoLogs() => _notifyAutoLogs();

  @visibleForTesting
  bool get observerAttached => _observerAttached;

  @visibleForTesting
  Timer? get timer => _timer;
}
