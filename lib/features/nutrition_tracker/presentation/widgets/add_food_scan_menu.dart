import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

/// The three capture flows reachable from the add-food scan menu.
enum AddFoodScanChoice { meal, barcode, label }

/// Presents the compact "Scan" chooser as a bottom sheet and resolves to the
/// picked [AddFoodScanChoice] (or null if dismissed). Keeping the capture flows
/// behind one camera tap is what lets the add-food screen stay search-first
/// instead of showing every action at once.
///
/// [includeMeal] gates the AI "Scan a meal" option: the diary flow offers it,
/// but the recipe ingredient picker hides it (you capture ONE product per
/// ingredient — a barcode or a nutrition label — not a whole plate).
Future<AddFoodScanChoice?> showAddFoodScanMenu(
  BuildContext context, {
  bool includeMeal = true,
}) {
  return showModalBottomSheet<AddFoodScanChoice>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) => _AddFoodScanMenu(includeMeal: includeMeal),
  );
}

class _AddFoodScanMenu extends StatelessWidget {
  const _AddFoodScanMenu({required this.includeMeal});

  final bool includeMeal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.x1,
                bottom: AppSpacing.x1,
              ),
              child: Text('Scan', style: theme.textTheme.titleMedium),
            ),
            if (includeMeal)
              _ScanOption(
                icon: Icons.restaurant_outlined,
                title: 'Scan a meal',
                subtitle: 'Snap a photo and let AI break it down',
                onTap: () => context.pop(AddFoodScanChoice.meal),
              ),
            _ScanOption(
              icon: Icons.qr_code_scanner_outlined,
              title: 'Barcode',
              subtitle: 'Look up a packaged product',
              onTap: () => context.pop(AddFoodScanChoice.barcode),
            ),
            _ScanOption(
              icon: Icons.document_scanner_outlined,
              title: 'Nutrition label',
              subtitle: 'Read the macros off the panel',
              onTap: () => context.pop(AddFoodScanChoice.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanOption extends StatelessWidget {
  const _ScanOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}
