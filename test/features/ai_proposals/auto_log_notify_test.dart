import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/auto_logged_proposal.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_count_service.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_events_service.dart';

// Minimal repo: only listPending + listAutoAppliedLogs matter here; noSuchMethod
// no-ops the rest of the interface (none of which these tests invoke).
class _Repo implements ProposalsRepository {
  _Repo(this.autoLogs);
  List<AutoLoggedProposal> autoLogs;
  DateTime? lastSince;

  @override
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({DateTime? since}) async {
    lastSince = since;
    return autoLogs;
  }

  @override
  Future<List<ProposalSummary>> listPending({int limit = 50}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

// Records which proposals it was asked to notify about; noSuchMethod no-ops the
// rest of NotificationService (whose real methods touch platform plugins).
class _Notif implements NotificationService {
  final List<String> shownIds = [];

  @override
  Future<void> showAutoLoggedProposal({
    required String id,
    required bool isFood,
    required String body,
  }) async {
    shownIds.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

AutoLoggedProposal _log(String id, DateTime appliedAt) => AutoLoggedProposal(
  id: id,
  kind: ProposalKind.foodLog,
  summary: 'Log 1 item — 200 kcal',
  appliedAt: appliedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProposalCountService build(_Repo repo, _Notif notif) => ProposalCountService(
    TokenStorage(),
    repo,
    ProposalEventsService(),
    notifications: notif,
    preferences: PreferencesService(),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first run with a backlog sets the watermark WITHOUT notifying', () async {
    final repo = _Repo([
      _log('a', DateTime(2026, 6, 27, 9)),
      _log('b', DateTime(2026, 6, 27, 8)),
    ]);
    final notif = _Notif();
    await build(repo, notif).debugNotifyAutoLogs();

    expect(notif.shownIds, isEmpty, reason: 'must not backfill history');
    expect(
      await PreferencesService().getAiAutoLogLastSeen(),
      DateTime(2026, 6, 27, 9),
    );
  });

  test('subsequent run notifies only logs newer than the watermark', () async {
    await PreferencesService().setAiAutoLogLastSeen(DateTime(2026, 6, 27, 9));
    final repo = _Repo([_log('c', DateTime(2026, 6, 27, 12))]);
    final notif = _Notif();
    await build(repo, notif).debugNotifyAutoLogs();

    expect(repo.lastSince, DateTime(2026, 6, 27, 9), reason: 'bounds the query');
    expect(notif.shownIds, ['c']);
    expect(
      await PreferencesService().getAiAutoLogLastSeen(),
      DateTime(2026, 6, 27, 12),
    );
  });

  test('empty result leaves an existing watermark untouched', () async {
    await PreferencesService().setAiAutoLogLastSeen(DateTime(2026, 6, 27, 9));
    final notif = _Notif();
    await build(_Repo(const []), notif).debugNotifyAutoLogs();

    expect(notif.shownIds, isEmpty);
    expect(
      await PreferencesService().getAiAutoLogLastSeen(),
      DateTime(2026, 6, 27, 9),
    );
  });
}
