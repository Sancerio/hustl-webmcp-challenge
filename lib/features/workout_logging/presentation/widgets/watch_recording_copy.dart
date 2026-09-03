/// The view-states the Sonar watch card can show. Public so the card and its
/// copy table share one source of truth (and tests can read it if needed).
enum WatchConnectState {
  idle,
  searching,
  retrying,
  connected,
  notFound,
  recording,
  stopping,
}

/// Title + subtitle pair for a given card state.
class WatchConnectCopy {
  const WatchConnectCopy(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// Resolves the sentence-case copy for each state. Failure copy is blame-free
/// (never red-alarm wording), and no string is reused across a state change.
/// [retrySending] flips the retrying subtitle to the transient "Sending again…"
/// acknowledgement before it reverts back to the searching subtitle.
WatchConnectCopy watchConnectCopy(
  WatchConnectState state, {
  required bool retrySending,
}) {
  switch (state) {
    case WatchConnectState.idle:
      return const WatchConnectCopy(
        'Record on Apple Watch',
        'Track heart rate and energy on your wrist.',
      );
    case WatchConnectState.searching:
      return const WatchConnectCopy(
        'Looking for your watch',
        'Open Hustl on your Apple Watch to start.',
      );
    case WatchConnectState.retrying:
      return WatchConnectCopy(
        'Looking for your watch',
        retrySending
            ? 'Sending again…'
            : 'Open Hustl on your Apple Watch to start.',
      );
    case WatchConnectState.connected:
      return const WatchConnectCopy('Connected', 'Recording on Apple Watch.');
    case WatchConnectState.recording:
      return const WatchConnectCopy(
        'Recording on Apple Watch',
        'Heart rate and energy will be saved with this workout.',
      );
    case WatchConnectState.stopping:
      return const WatchConnectCopy(
        'Stopping…',
        'Wrapping up the recording on your watch.',
      );
    case WatchConnectState.notFound:
      return const WatchConnectCopy(
        "We couldn't reach your watch",
        'Open Hustl on your watch, then send again — or keep logging here.',
      );
  }
}
