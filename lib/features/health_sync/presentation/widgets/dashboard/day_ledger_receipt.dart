import 'package:flutter/material.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../domain/models/external_activity.dart';
import '../../../domain/models/strain_ledger.dart';
import 'recovery_band_tint.dart';

/// "The day's ledger" — the strain receipt.
///
/// A typographic itemization of what drove today's strain: each session that
/// contributed, plus an ambient remainder, totalling to the strain number the
/// hero already shows. Pure presentation: it renders whatever [StrainLedger] it
/// is handed and is intentionally day-agnostic so a future drill-down can reuse
/// it with another day's ledger.
///
/// Translated from the approved cut-D receipt prototype into production tokens:
/// theme `colorScheme` + `AppColors`, DM Sans via [AppTextStyles], hairline
/// rules at the `outlineVariant` tier, tabular numerals in the time/points
/// columns, and source-tinted activity glyphs (Hustl emerald / external
/// violet / ambient slate) that name the activity rather than a plain dot.
class DayLedgerReceipt extends StatelessWidget {
  const DayLedgerReceipt({super.key, required this.ledger, this.typicalStrain});

  /// Coarse-kind fallback glyphs.
  static const Map<ExternalActivityKind, IconData> _kindIcons = {
    ExternalActivityKind.run: Icons.directions_run,
    ExternalActivityKind.ride: Icons.directions_bike,
    ExternalActivityKind.swim: Icons.pool,
    ExternalActivityKind.walk: Icons.directions_walk,
    ExternalActivityKind.hike: Icons.hiking,
    ExternalActivityKind.strengthTraining: Icons.fitness_center,
    ExternalActivityKind.hiit: Icons.bolt,
    ExternalActivityKind.yoga: Icons.self_improvement,
    // Generic/unclassified external workout ("Workout") — a neutral sport
    // glyph, not the strength dumbbell, so it doesn't imply a lift. Matches the
    // `_sportIcons` miss fallback so both "unknown external" cases look the same.
    ExternalActivityKind.other: Icons.sports,
  };

  /// Specific glyphs for common `other`-bucket sports, keyed by the normalized
  /// (lowercase-alphanumeric) activity name.
  static const Map<String, IconData> _sportIcons = {
    'soccer': Icons.sports_soccer,
    'basketball': Icons.sports_basketball,
    'tennis': Icons.sports_tennis,
    'tabletennis': Icons.sports_tennis,
    'americanfootball': Icons.sports_football,
    'australianfootball': Icons.sports_football,
    'rugby': Icons.sports_rugby,
    'volleyball': Icons.sports_volleyball,
    'cricket': Icons.sports_cricket,
    'hockey': Icons.sports_hockey,
    'baseball': Icons.sports_baseball,
    'softball': Icons.sports_baseball,
    'golf': Icons.sports_golf,
    'boxing': Icons.sports_mma,
    'kickboxing': Icons.sports_mma,
    'martialarts': Icons.sports_martial_arts,
    'handball': Icons.sports_handball,
    'rowing': Icons.rowing,
    'downhillskiing': Icons.downhill_skiing,
    'snowboarding': Icons.snowboarding,
    'surfing': Icons.surfing,
    // Common gym-cardio `other`-bucket types — a fitting glyph beats the
    // generic whistle for the activities users log most.
    'stairclimbing': Icons.stairs,
    'elliptical': Icons.fitness_center,
    'crosstraining': Icons.fitness_center,
    'cardiodance': Icons.music_note,
    'socialdance': Icons.music_note,
  };

  /// The glyph for an entry: Hustl -> strength; an external `other`-bucket
  /// sport with a known name -> its specific sport glyph; otherwise the
  /// coarse kind glyph. Ambient is handled at its own call site
  /// (Icons.directions_walk).
  static IconData _activityIcon(StrainLedgerEntry entry) {
    if (entry.source == StrainSource.hustl) return Icons.fitness_center;
    final name = entry.activityName;
    if (entry.kind == ExternalActivityKind.other && name != null) {
      // Same normalization the name was built from, so keys can't drift.
      return _sportIcons[normalizeActivityToken(name)] ?? Icons.sports;
    }
    return _kindIcons[entry.kind] ?? Icons.sports;
  }

  final StrainLedger ledger;

  /// The user's typical/baseline strain, rendered as a "typical {n}" sub-line
  /// under the total. Sourced from `DailyRecoverySnapshot.typicalStrainScore`
  /// (the median-load baseline); null while the baseline is still calibrating,
  /// in which case the sub-line is omitted.
  final int? typicalStrain;

  static const double _timeColumnWidth = 46;

  TextStyle _style(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
  }) {
    return TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static String _hhmm(DateTime time) {
    final local = time.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _points(double value) => value.toStringAsFixed(1);

  /// Coarse display name for an activity kind.
  static String kindLabel(ExternalActivityKind kind) {
    switch (kind) {
      case ExternalActivityKind.run:
        return 'Run';
      case ExternalActivityKind.ride:
        return 'Ride';
      case ExternalActivityKind.swim:
        return 'Swim';
      case ExternalActivityKind.walk:
        return 'Walk';
      case ExternalActivityKind.hike:
        return 'Hike';
      case ExternalActivityKind.strengthTraining:
        return 'Strength';
      case ExternalActivityKind.hiit:
        return 'HIIT';
      case ExternalActivityKind.yoga:
        return 'Yoga';
      case ExternalActivityKind.other:
        return 'Workout';
    }
  }

  /// The best human name for an entry's activity: the real platform activity
  /// name (`Tennis`, `Pilates`, `Soccer`, `Running`) when the source preserved
  /// one, else the coarse [kindLabel] as a fallback. The preserved name is
  /// honored ONLY for external entries — Hustl sessions always resolve to their
  /// kind label ("Strength"), so a malformed Hustl `activityName` can never leak
  /// into a `… · Hustl` sub-line.
  String _displayKind(StrainLedgerEntry entry) =>
      entry.source == StrainSource.external
      ? (entry.activityName ?? kindLabel(entry.kind))
      : kindLabel(entry.kind);

  String _entryTitle(StrainLedgerEntry entry) {
    // Hustl sessions carry the user's own session name ("Push day"); externals
    // show a kind-derived title, with their source in the sub-line.
    return entry.source == StrainSource.hustl
        ? entry.label
        : _displayKind(entry);
  }

  String _entrySubtitle(StrainLedgerEntry entry) {
    final kind = _displayKind(entry);
    final origin = entry.source == StrainSource.hustl
        ? 'Hustl'
        : prettySourceName(entry.label);
    return '$kind · $origin';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ink = colors.onSurface;
    final sub = colors.onSurfaceVariant;
    final rule = colors.outlineVariant;
    final ruleHeavy = colors.outline;

    return Column(
      key: const Key('dayLedgerReceipt'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: rule),
        const SizedBox(height: 4),
        for (final entry in ledger.entries)
          _ReceiptRow(
            time: _hhmm(entry.start),
            icon: _activityIcon(entry),
            iconColor: entry.source == StrainSource.hustl
                ? AppColors.accentEmeraldGreen
                : kExternalWorkoutTint,
            title: _entryTitle(entry),
            subtitle: _entrySubtitle(entry),
            points: _points(entry.loadPoints),
            titleStyle: _style(15, FontWeight.w500, ink),
            subtitleStyle: _style(11.5, FontWeight.w400, sub),
            timeStyle: _style(12.5, FontWeight.w400, sub),
            pointsStyle: _style(15, FontWeight.w600, ink),
          ),
        if (ledger.ambientLoadPoints > 0)
          _ReceiptRow(
            time: '—',
            icon: Icons.directions_walk,
            iconColor: sub,
            title: 'Ambient movement',
            subtitle: 'Steps · everyday activity',
            points: _points(ledger.ambientLoadPoints),
            titleStyle: _style(15, FontWeight.w500, ink),
            subtitleStyle: _style(11.5, FontWeight.w400, sub),
            timeStyle: _style(12.5, FontWeight.w400, sub),
            pointsStyle: _style(15, FontWeight.w600, ink),
          ),
        const SizedBox(height: 4),
        Container(height: 2, color: ruleHeavy),
        const SizedBox(height: 12),
        Row(
          key: const Key('dayLedgerTotal'),
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Strain', style: _style(14, FontWeight.w600, ink)),
            const Spacer(),
            Text(
              '${ledger.strainScore}',
              style: _style(15, FontWeight.w700, ink),
            ),
          ],
        ),
        if (typicalStrain != null) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'typical $typicalStrain',
              style: _style(11, FontWeight.w400, sub),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'load points, estimated from energy and duration',
            style: _style(10.5, FontWeight.w400, sub),
          ),
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: rule),
        const SizedBox(height: 12),
        Text(
          'Shares are estimates — sessions split the day’s measured load.',
          style: _style(11, FontWeight.w400, sub, height: 1.4),
        ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.timeStyle,
    required this.pointsStyle,
  });

  final String time;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String points;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final TextStyle timeStyle;
  final TextStyle pointsStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: DayLedgerReceipt._timeColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(time, style: timeStyle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 12),
            child: Icon(icon, size: 19, color: iconColor),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Single-line + ellipsis: an unusually long activity name (e.g.
                // "Swimming open water") degrades gracefully instead of wrapping
                // and breaking the row rhythm on a narrow receipt.
                Text(
                  title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: subtitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 1, left: 12),
            child: Text(points, style: pointsStyle),
          ),
        ],
      ),
    );
  }
}

/// Prettifies a workout's raw source string for display.
///
/// Apple Health hands back friendly names ("Apple Watch", "Strava"); Android /
/// Health Connect hands back reverse-domain package ids ("com.strava",
/// "com.example.flow"). This maps a small set of known sources to their brand
/// names and, for anything else that looks like a package id, strips the
/// reverse-domain prefix and title-cases the last segment. Already-friendly
/// names are returned unchanged.
String prettySourceName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Unknown';

  final lower = trimmed.toLowerCase();

  // Known sources, matched as substrings so both friendly names and package
  // ids resolve (e.g. "com.strava" and "Strava" both -> "Strava").
  if (lower.contains('strava')) return 'Strava';
  if (lower.contains('peloton')) return 'Peloton';
  if (lower.contains('garmin')) return 'Garmin';
  if (lower.contains('whoop')) return 'WHOOP';
  if (lower.contains('nike')) return 'Nike Run Club';
  if (lower.contains('fitbit')) return 'Fitbit';
  if (lower.contains('google') && lower.contains('fit')) return 'Google Fit';
  if (lower.contains('shealth') || lower.contains('samsung')) {
    return 'Samsung Health';
  }

  // Reverse-domain package id (a dotted token with no spaces): keep the last
  // segment and title-case it.
  if (trimmed.contains('.') && !trimmed.contains(' ')) {
    final segment = trimmed.split('.').last;
    if (segment.isEmpty) return trimmed;
    return segment[0].toUpperCase() + segment.substring(1);
  }

  return trimmed;
}
