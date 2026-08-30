import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/recovery_flow_copy.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/recovery_band_tint.dart';

/// A single quiet post-workout note that pairs the just-finished session's
/// effort with the day's recovery band (spec "Post-workout note"). It sits
/// AFTER the summary details and stays subordinate to the celebration hero / PRs.
///
/// Strictly additive: [maybe] returns `null` when there is no snapshot, the
/// snapshot is calibrating / low-confidence, or the band is absent — so the
/// summary renders exactly as today. The accent is band-tinted via the token
/// mapping (warm amber for low, never red); color is always paired with text.
class StrainRecoveryNote extends StatelessWidget {
  const StrainRecoveryNote({super.key, required this.snapshot});

  final DailyRecoverySnapshot snapshot;

  /// Builds the note only when [RecoveryFlowCopy.postWorkoutNote] yields a line,
  /// else `null` so the caller renders nothing. All gating lives in one place.
  static Widget? maybe(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null) return null;
    if (RecoveryFlowCopy.postWorkoutNote(snapshot) == null) return null;
    return StrainRecoveryNote(snapshot: snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bandColors = RecoveryBandColors.resolve(colors, snapshot.flowBand);
    final note = RecoveryFlowCopy.postWorkoutNote(snapshot);
    if (note == null) return const SizedBox.shrink();

    final bandLabel = snapshot.flowBand?.displayLabel ?? 'Recovery';
    final strain = snapshot.strainScore;
    final meta = strain != null
        ? 'Today\'s recovery · $bandLabel · strain $strain'
        : 'Today\'s recovery · $bandLabel';

    return Semantics(
      container: true,
      label: '$meta. $note',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            color: bandColors.container,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 36,
                margin: const EdgeInsets.only(top: 2, right: AppSpacing.x2),
                decoration: BoxDecoration(
                  color: bandColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
