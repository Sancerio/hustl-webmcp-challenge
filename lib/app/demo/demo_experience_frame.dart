import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'demo_reset.dart';

/// Persistent evaluator chrome shown above every shell and overlay route.
class DemoExperienceFrame extends StatelessWidget {
  const DemoExperienceFrame({
    super.key,
    required this.child,
    this.onReset = resetDemoExperience,
  });

  final Widget child;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Material(
              color: colors.secondaryContainer,
              child: Semantics(
                container: true,
                label: 'Demo data controls',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2,
                    vertical: AppSpacing.x1,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        size: 20,
                        color: colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Expanded(
                        child: Text(
                          'Demo data',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: colors.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onReset,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reset demo'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.onSecondaryContainer,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
