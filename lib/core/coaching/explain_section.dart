import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';

/// A reusable, surface-agnostic "Explain my numbers" affordance for the shared
/// "explain any number" coach capability. Extracted from the nutrition Insights
/// `_NarrativeSection` so any surface (Insights, body-score / training balance,
/// recovery, ...) can drop in the same quiet affordance with identical behavior:
///
///  - a quiet "Explain my numbers" text button →
///  - a two-line shimmer while the fetch is in flight →
///  - on success: the note in a subtle surface pill →
///  - on a null/empty result (gated / not enough data / errored): a brief inline
///    line instead of snapping back to nothing, so the loading state never just
///    vanishes. The deterministic on-screen output stays authoritative.
///
/// The fetch is LAZY — nothing fires until the user taps the affordance. A
/// monotonic token guards against a stale fetch painting after the inputs change:
/// the token is bumped on every fetch AND whenever [resetKey] changes, and a
/// resolving fetch only writes its result if its token still matches. Pass a
/// [resetKey] that changes whenever the explained numbers change (e.g. the range
/// or the rec content) so a previously-shown note is cleared and the affordance
/// returns instead of hanging above fresh data.
class CoachExplainSection extends StatefulWidget {
  const CoachExplainSection({
    super.key,
    required this.fetchNarrative,
    this.resetKey,
    this.label = 'Explain my numbers',
    this.emptyMessage =
        'Not enough logged data to explain yet — keep logging.',
  });

  /// Lazy fetcher for the narrative. Returns the note string, or null when the
  /// backend has nothing to say (flag off / gated / capped / errored).
  final Future<String?> Function() fetchNarrative;

  /// An opaque value that changes whenever the explained numbers change. When it
  /// changes the section resets (clears the note, restores the affordance) and
  /// any in-flight fetch is discarded. Null disables reset-on-change.
  final Object? resetKey;

  /// The quiet affordance label.
  final String label;

  /// The brief inline line shown after a null/empty result.
  final String emptyMessage;

  @override
  State<CoachExplainSection> createState() => _CoachExplainSectionState();
}

class _CoachExplainSectionState extends State<CoachExplainSection> {
  bool _loading = false;
  bool _attempted = false;
  String? _narrative;

  /// Monotonic token for the in-flight explain request. Bumped whenever a fetch
  /// starts AND whenever [CoachExplainSection.resetKey] changes; a resolving
  /// fetch only writes its result if its token still matches — so a request that
  /// lands after the inputs changed can never paint a stale note.
  int _token = 0;

  @override
  void didUpdateWidget(covariant CoachExplainSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The narrative explains the CURRENT numbers. Reset is driven by [resetKey]
    // (the explicit input-identity the host owns) — NOT by the fetchNarrative
    // CLOSURE identity. The call sites pass INLINE closures, so an unrelated
    // rebuild recreates the callback every frame; keying the reset off closure
    // identity would clear a perfectly valid note even though resetKey and the
    // explained inputs are unchanged. When resetKey actually changes, the old
    // note is stale, so we clear it and bump the token to discard any in-flight
    // explain that resolves after the change. (The monotonic _token still guards
    // a stale fetch regardless of why a reset happened.)
    if (oldWidget.resetKey != widget.resetKey) {
      _token++;
      _narrative = null;
      _attempted = false;
      _loading = false;
    }
  }

  Future<void> _onExplain() async {
    if (_loading) return;
    Haptics.selection();
    final token = ++_token;
    setState(() {
      _loading = true;
      _attempted = true;
    });
    String? result;
    try {
      result = await widget.fetchNarrative();
    } catch (_) {
      result = null;
    }
    // Drop a result whose inputs have since changed (a newer token means this
    // note is already stale).
    if (!mounted || token != _token) return;
    setState(() {
      _narrative = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return AppSkeleton.lines(
        rows: 2,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
        semanticsLabel: 'Writing your coach note',
      );
    }

    final note = _narrative;
    if (note != null && note.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          note,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            height: 1.4,
          ),
        ),
      );
    }

    // After a failed/empty attempt, show a brief inline line so the loading
    // state doesn't just vanish into nothing. The on-screen output stays
    // authoritative.
    if (_attempted) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          widget.emptyMessage,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Initial state: the quiet affordance to opt into the note.
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _onExplain,
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: Text(widget.label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x1,
            vertical: AppSpacing.x1,
          ),
        ),
      ),
    );
  }
}
