import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import 'watch_recording_copy.dart';
import 'watch_recording_medallion.dart';

/// The "Sonar" connect card: a calm searching banner that invites the user to
/// start a recording on their Apple Watch, then narrates looking -> connected
/// -> recording without ever raising a red alarm.
///
/// The public constructor is unchanged from the original utilitarian card so
/// the mount in `active_workout_screen.dart` needs no edit. Internally it layers
/// a synthetic [WatchConnectState] over the two real bools to tell the search
/// story; that view-state never touches the bridge or repository.
class WatchRecordingCard extends StatefulWidget {
  const WatchRecordingCard({
    super.key,
    required this.isRecording,
    required this.isRequested,
    required this.onRequestStart,
    required this.onRequestCancel,
    required this.onRequestStop,
  });

  final bool isRecording;
  final bool isRequested;
  final VoidCallback onRequestStart;
  final VoidCallback onRequestCancel;
  final VoidCallback onRequestStop;

  @override
  State<WatchRecordingCard> createState() => _WatchRecordingCardState();
}

class _WatchRecordingCardState extends State<WatchRecordingCard>
    with SingleTickerProviderStateMixin {
  static const Duration _watchdog = Duration(seconds: 22);
  static const Duration _retryRevert = Duration(milliseconds: 1600);
  static const Duration _connectedHold = Duration(milliseconds: 900);
  static const Duration _subSecondSkip = Duration(milliseconds: 400);
  // If the best-effort stop request is lost (watch closed/unreachable) the
  // parent can keep `isRecording: true` forever, leaving us stuck on
  // "Stopping…". After this grace window we re-enable a retryable Stop so the
  // user can re-send the stop instead of being trapped for the whole workout.
  static const Duration _stopWatchdog = Duration(seconds: 9);

  late final AnimationController _controller;
  late final Animation<double> _breath;

  WatchConnectState _state = WatchConnectState.idle;
  bool _retrySubtitle = false;
  bool _reduceMotion = false;

  Timer? _watchdogTimer;
  Timer? _retryRevertTimer;
  Timer? _connectedHoldTimer;
  Timer? _stopWatchdogTimer;
  DateTime? _searchingSince;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _breath = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_controller);
    _state = _restingState();
    // Mounting straight into `searching` (a default-enabled session seeds
    // `watchRecordingRequested: true`, so we enter the search story without a
    // Record press) must stamp `_searchingSince` too — exactly as
    // `_onRecordPressed`/`_resetFromExternalChange` do — so an instant connect
    // from this mounted-searching start still takes the sub-second fast-skip
    // instead of being forced onto the conservative full ~900ms hold.
    if (_state == WatchConnectState.searching) {
      _searchingSince = DateTime.now();
      _startWatchdog();
    }
  }

  WatchConnectState _restingState() {
    if (widget.isRecording) return WatchConnectState.recording;
    if (widget.isRequested) return WatchConnectState.searching;
    return WatchConnectState.idle;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncController();
  }

  @override
  void didUpdateWidget(covariant WatchRecordingCard old) {
    super.didUpdateWidget(old);
    // isRecording rising while we were searching/retrying is "connected".
    if (widget.isRecording && !old.isRecording) {
      _onRecordingStarted();
      return;
    }
    // isRecording dropping (stopped), or the request being cleared externally,
    // returns us to the resting state.
    final stopped = !widget.isRecording && old.isRecording;
    final requestCleared =
        !widget.isRequested && old.isRequested && !widget.isRecording;
    if (stopped || requestCleared) {
      _resetFromExternalChange();
      return;
    }
    // isRequested rising externally (the session started requesting watch
    // recording from somewhere other than our own button) while we're still
    // idle: resync into the searching story and arm the watchdog, exactly as if
    // Record had been pressed. The `_state == idle` guard skips our own
    // `_onRecordPressed`, which already drove us to `searching` *before* the
    // parent flipped the bool — so this never double-fires the local path.
    final requestRose = !old.isRequested && widget.isRequested;
    if (requestRose &&
        !widget.isRecording &&
        _state == WatchConnectState.idle) {
      _resetFromExternalChange();
    }
  }

  void _onRecordingStarted() {
    final fast =
        _searchingSince != null &&
        DateTime.now().difference(_searchingSince!) < _subSecondSkip;
    _cancelTimers();
    _controller.stop();
    setState(() {
      _state = WatchConnectState.connected;
      _retrySubtitle = false;
    });
    Haptics.confirm();
    // The sub-second skip still passes through connected, just without a
    // searching flash; either way we settle on the check, hold, then recording.
    _connectedHoldTimer = Timer(fast ? _subSecondSkip : _connectedHold, () {
      if (!mounted) return;
      setState(() => _state = WatchConnectState.recording);
    });
  }

  /// React to the parent bools changing underneath us by recomputing the rest.
  void _resetFromExternalChange() {
    _cancelTimers();
    final next = _restingState();
    setState(() {
      _state = next;
      _retrySubtitle = false;
    });
    if (next == WatchConnectState.searching) {
      _searchingSince = DateTime.now();
      _startWatchdog();
    }
    _syncController();
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(_watchdog, _onWatchdog);
  }

  void _onWatchdog() {
    if (!mounted) return;
    if (_state != WatchConnectState.searching &&
        _state != WatchConnectState.retrying) {
      return;
    }
    setState(() {
      _state = WatchConnectState.notFound;
      _retrySubtitle = false;
    });
    _syncController();
  }

  void _onRecordPressed() {
    Haptics.selection();
    widget.onRequestStart();
    setState(() {
      _state = WatchConnectState.searching;
      _retrySubtitle = false;
    });
    _searchingSince = DateTime.now();
    _startWatchdog();
    _syncController();
  }

  void _onSendAgainPressed() {
    Haptics.selection();
    widget.onRequestStart();
    _retryRevertTimer?.cancel();
    setState(() {
      _state = WatchConnectState.retrying;
      _retrySubtitle = true;
    });
    if (!_reduceMotion) {
      _controller
        ..forward(from: 0)
        ..repeat();
    }
    _startWatchdog();
    _retryRevertTimer = Timer(_retryRevert, () {
      if (!mounted) return;
      setState(() {
        _retrySubtitle = false;
        if (_state == WatchConnectState.retrying) {
          _state = WatchConnectState.searching;
        }
      });
    });
  }

  void _onCancelPressed() {
    widget.onRequestCancel();
    _toIdle();
  }

  void _onStopPressed() {
    widget.onRequestStop();
    // Don't go idle optimistically: the parent can keep `isRecording: true`
    // until the watch bridge confirms the stop. Hold a `stopping` state (with a
    // disabled control) so a stray start can't fire during the in-flight
    // window; we only fall to idle once `isRecording` actually drops to false
    // (handled by didUpdateWidget -> _resetFromExternalChange).
    _cancelTimers();
    setState(() {
      _state = WatchConnectState.stopping;
      _retrySubtitle = false;
    });
    // Arm the stop watchdog: if the stop never confirms (request lost, watch
    // unreachable) we'd otherwise sit on "Stopping…" forever. After the grace
    // window, fall back to `recording` so the Stop button goes live again and a
    // lost stop can be retried. Cancelled the moment we leave `stopping` (e.g.
    // `isRecording` dropping to false routes through `_cancelTimers`).
    _stopWatchdogTimer = Timer(_stopWatchdog, _onStopWatchdog);
    _syncController();
  }

  void _onStopWatchdog() {
    if (!mounted) return;
    // Only recover if we're still stuck stopping while the parent insists it's
    // recording — i.e. the stop genuinely didn't land. If `isRecording` already
    // dropped, the normal stopping->idle path has run and this is a no-op.
    if (_state != WatchConnectState.stopping || !widget.isRecording) return;
    setState(() {
      _state = WatchConnectState.recording;
      _retrySubtitle = false;
    });
    _syncController();
  }

  void _toIdle() {
    _cancelTimers();
    setState(() {
      _state = WatchConnectState.idle;
      _retrySubtitle = false;
    });
    _syncController();
  }

  bool get _wantsRings =>
      _state == WatchConnectState.searching ||
      _state == WatchConnectState.retrying;

  /// Run the controller only while rings should sweep and motion is allowed.
  void _syncController() {
    if (_reduceMotion || !_wantsRings) {
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    if (!_controller.isAnimating) _controller.repeat();
  }

  void _cancelTimers() {
    _watchdogTimer?.cancel();
    _retryRevertTimer?.cancel();
    _connectedHoldTimer?.cancel();
    _stopWatchdogTimer?.cancel();
    _watchdogTimer = null;
    _retryRevertTimer = null;
    _connectedHoldTimer = null;
    _stopWatchdogTimer = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncController();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final copy = watchConnectCopy(_state, retrySending: _retrySubtitle);

    // Build the medallion *inside* the builder so it reads the live
    // `_controller.value` every tick — the sonar rings would otherwise freeze
    // at the value captured when a static `child:` was first built.
    final medallion = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          ScaleTransition(scale: _breath, child: _buildMedallion(scheme)),
    );

    final content = Column(
      key: ValueKey(_state),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        medallion,
        const SizedBox(height: AppSpacing.x2),
        Text(
          copy.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          copy.subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (_actionsFor() case final actions?) ...[
          const SizedBox(height: AppSpacing.x2),
          actions,
        ],
      ],
    );

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.cardRadius,
            boxShadow: [AppShadows.subtle(context)],
          ),
          padding: AppSpacing.cardPadding,
          child: AnimatedSize(
            duration: AppMotion.slow,
            curve: AppMotion.emphasizedCurve,
            child: AnimatedSwitcher(
              duration: AppMotion.slow,
              transitionBuilder: appFadeSlideTransition,
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMedallion(ColorScheme scheme) {
    final isConnected = _state == WatchConnectState.connected;
    final isResolved =
        isConnected ||
        _state == WatchConnectState.recording ||
        _state == WatchConnectState.stopping;
    final isNotFound = _state == WatchConnectState.notFound;
    final tint = isNotFound
        ? AppColors.accentWarningAmber
        : (isResolved ? scheme.tertiary : scheme.primary);
    final glyph = isConnected
        ? Icon(Icons.check_rounded, size: 24, color: scheme.tertiary)
        : Icon(Icons.watch_outlined, size: 24, color: tint);
    return WatchRecordingMedallion(
      phase: _reduceMotion ? 0.0 : _controller.value,
      showRings: _wantsRings,
      glyph: glyph,
      discColor: tint.withValues(alpha: 0.10),
    );
  }

  Widget? _actionsFor() {
    switch (_state) {
      case WatchConnectState.idle:
        return FilledButton.tonal(
          onPressed: _onRecordPressed,
          child: const Text('Record on Apple Watch'),
        );
      case WatchConnectState.recording:
        return OutlinedButton.icon(
          onPressed: _onStopPressed,
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('Stop recording'),
        );
      case WatchConnectState.stopping:
        // Disabled while the stop is in flight — no start/stop can re-fire.
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('Stopping…'),
        );
      case WatchConnectState.connected:
        return null;
      case WatchConnectState.searching:
      case WatchConnectState.retrying:
        return _twoActions(promoted: false);
      case WatchConnectState.notFound:
        return _twoActions(promoted: true);
    }
  }

  /// Cancel + Send again, sized to content (centered) — never two Expanded
  /// halves. [promoted] swaps the tonal Send again for a solid FilledButton.
  ///
  /// A [Wrap] keeps the normal single centered line at default text sizes but
  /// lets the two buttons flow onto a second line on a narrow phone with large
  /// accessibility text (e.g. 320px + TextScaler 2.0), so neither action is
  /// ever clipped by a RenderFlex overflow.
  Widget _twoActions({required bool promoted}) {
    final sendAgain = promoted
        ? FilledButton(
            onPressed: _onSendAgainPressed,
            child: const Text('Send again'),
          )
        : FilledButton.tonal(
            onPressed: _onSendAgainPressed,
            child: const Text('Send again'),
          );
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.x1,
      runSpacing: AppSpacing.x1,
      children: [
        TextButton(onPressed: _onCancelPressed, child: const Text('Cancel')),
        sendAgain,
      ],
    );
  }
}
