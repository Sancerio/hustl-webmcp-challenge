import 'package:flutter/foundation.dart';

/// A tiny broadcast of the current pending-proposal count.
///
/// Mirrors the app's other `ValueNotifier`-based event services (e.g.
/// `ThemeService.themeMode`). The [PendingProposalBanner], the Account "More"
/// row chip, and any home card listen via `ValueListenableBuilder`. The
/// [ProposalCountService] poller and the [ProposalsBloc] push counts here.
class ProposalEventsService {
  /// The latest known number of pending proposals (0 when none / unknown).
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  void setCount(int count) {
    final next = count < 0 ? 0 : count;
    if (pendingCount.value != next) {
      pendingCount.value = next;
    }
  }

  void dispose() {
    pendingCount.dispose();
  }
}
