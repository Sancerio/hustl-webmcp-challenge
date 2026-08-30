import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';

import '../../domain/models/nutrition_target_plan.dart';
import 'nutrition_chart_kit.dart';

/// Returns a patch map of the edited targets (or null if dismissed). The patch
/// shape is unchanged from the original sheet — only the presentation is
/// premium: a drag-handle sheet, macro-coloured fields, and a live proportion
/// bar so the macros read as part of the calorie budget (like the Strategy
/// hero). Editing an auto plan flips coaching to manual (carried in the patch).
///
/// Carbs are the single remainder bucket: they are DERIVED live from
/// calories − protein − fat (the same Atwater split the backend persists), so
/// the four fields can never desync. The carbs row is read-only and updates as
/// the user types calories/protein/fat. The backend additionally reconciles the
/// patch (see reconcileMacros), so the stored row is always self-consistent
/// (protein*4 + carbs*4 + fat*9 === calories) even if a client sends stale
/// values.
Future<Map<String, dynamic>?> showTargetsEditorSheet(
  BuildContext context,
  NutritionTargetPlan plan,
) async {
  final calController = TextEditingController(
    text: plan.caloriesTarget.toStringAsFixed(0),
  );
  final proteinController = TextEditingController(
    text: plan.proteinTarget.toStringAsFixed(0),
  );
  final fatController = TextEditingController(
    text: plan.fatTarget.toStringAsFixed(0),
  );

  double parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  // Carbs as the exact remainder of the calorie budget after protein and fat.
  // Clamped at 0 so an over-allocated protein+fat never shows negative carbs.
  double deriveCarbs(double calories, double protein, double fat) {
    final remaining = calories - protein * 4 - fat * 9;
    final carbs = (remaining / 4).round().toDouble();
    return carbs < 0 ? 0 : carbs;
  }

  final patch = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) {
      final theme = Theme.of(context);
      return StatefulBuilder(
        builder: (context, setState) {
          final cal = parse(calController);
          final p = parse(proteinController);
          final f = parse(fatController);
          final c = deriveCarbs(cal, p, f);
          // Protein/carbs = 4 kcal/g, fat = 9 — the same split that fills the
          // calorie budget on the Strategy hero.
          final pCal = p * 4, cCal = c * 4, fCal = f * 9;
          final macroCal = pCal + cCal + fCal;

          Widget macroField(
            TextEditingController controller,
            String label,
            Color dot,
          ) {
            return Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: label),
                  ),
                ),
              ],
            );
          }

          // Carbs are derived, not typed — show them as a read-only row so the
          // user sees the remainder update as they edit calories/protein/fat.
          Widget carbsRow() {
            return Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.macroCarbs,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Carbs (g)',
                      helperText: 'Auto — fills the remaining calories',
                    ),
                    child: Text(
                      c.toStringAsFixed(0),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.x2,
              right: AppSpacing.x2,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.x2,
            ),
            child: ResponsiveCenter(
              maxContentWidth: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adjust targets',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (plan.mode == 'auto') ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      'Editing your targets switches coaching to manual.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x2),
                  TextField(
                    controller: calController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Calories (kcal)'),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  macroField(proteinController, 'Protein (g)', AppColors.macroProtein),
                  const SizedBox(height: AppSpacing.x2),
                  carbsRow(),
                  const SizedBox(height: AppSpacing.x2),
                  macroField(fatController, 'Fat (g)', AppColors.macroFat),
                  if (macroCal > 0) ...[
                    const SizedBox(height: AppSpacing.x3),
                    ProportionBar(
                      segments: [
                        (fraction: pCal / macroCal, color: AppColors.macroProtein),
                        (fraction: cCal / macroCal, color: AppColors.macroCarbs),
                        (fraction: fCal / macroCal, color: AppColors.macroFat),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      'Protein ${(pCal / macroCal * 100).round()}% · '
                      'Carbs ${(cCal / macroCal * 100).round()}% · '
                      'Fat ${(fCal / macroCal * 100).round()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x3),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () {
                        final calOut = double.tryParse(
                          calController.text.trim().replaceAll(',', '.'),
                        );
                        final pp = double.tryParse(
                          proteinController.text.trim().replaceAll(',', '.'),
                        );
                        final ff = double.tryParse(
                          fatController.text.trim().replaceAll(',', '.'),
                        );
                        // Carbs ride along as the derived remainder so the patch
                        // is already self-consistent; the backend reconciles it
                        // again as the safety net.
                        final cc = deriveCarbs(
                          calOut ?? 0,
                          pp ?? 0,
                          ff ?? 0,
                        );
                        context.pop({
                          if (plan.mode == 'auto') 'mode': 'manual',
                          if (calOut != null) 'caloriesTarget': calOut,
                          if (pp != null) 'proteinTarget': pp,
                          'carbsTarget': cc,
                          if (ff != null) 'fatTarget': ff,
                        });
                      },
                      child: const Text('Save targets'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  calController.dispose();
  proteinController.dispose();
  fatController.dispose();

  return patch;
}
