import 'package:flutter/widgets.dart';

/// How sure the coach is about a piece of guidance. Shown as a small,
/// non-alarming cue so users can calibrate trust ("High confidence" vs still
/// "Building confidence" while the data fills in). [none] hides the cue.
enum CoachConfidence { high, medium, building, none }

/// The accent a [CoachInsight] carries. Deliberately adherence-NEUTRAL: the
/// coach never shames, so there is no "error/red" tone — [attention] is the
/// strongest it gets (a warm amber nudge).
enum CoachTone { positive, neutral, attention }

/// An optional "what to do next" affordance on a coach card.
@immutable
class CoachAction {
  const CoachAction({required this.label, required this.onTap});

  /// Sentence-case label WITHOUT a trailing arrow — the card draws the arrow.
  final String label;
  final VoidCallback onTap;
}

/// A single, domain-agnostic unit of coaching guidance. The same model backs
/// nutrition, training and recovery coaching so every coach surface reads as one
/// coherent coach: a what-to-do [headline], a plain-language [why], a trust cue
/// ([confidence] + optional [windowLabel]), a [tone] accent, and an optional
/// [action].
@immutable
class CoachInsight {
  const CoachInsight({
    required this.headline,
    required this.why,
    this.confidence = CoachConfidence.none,
    this.windowLabel,
    this.tone = CoachTone.neutral,
    this.action,
    this.note,
  });

  /// What to do, in plain language ("Add 3 chest sets this week").
  final String headline;

  /// Why the coach is saying it ("Chest is 45% of your goal over 4 weeks").
  final String why;

  final CoachConfidence confidence;

  /// Optional data-window qualifier shown beside the confidence cue
  /// ("last 4 weeks", "21 days logged"). Null hides it.
  final String? windowLabel;

  final CoachTone tone;
  final CoachAction? action;

  /// Optional quiet secondary line rendered beneath [why] as a soft footnote
  /// (e.g. a readiness context line). Null renders nothing, so a card without a
  /// note looks exactly as before.
  final String? note;
}
