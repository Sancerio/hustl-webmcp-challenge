import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

class SyncPromptCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onCtaPressed;
  final VoidCallback? onDismiss;
  final bool showBenefits;

  const SyncPromptCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onCtaPressed,
    this.onDismiss,
    this.showBenefits = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.surface,
      elevation: theme.brightness == Brightness.light ? 1 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: theme.brightness == Brightness.dark
                        ? null
                        : Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/icon/hustl-icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onDismiss,
                    icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                    tooltip: 'Dismiss',
                  ),
                ],
              ],
            ),
            if (showBenefits) ...[
              const SizedBox(height: AppSpacing.x2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: _BenefitItem(
                        icon: Icons.backup_outlined,
                        label: 'Backup',
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _BenefitItem(
                        icon: Icons.devices_outlined,
                        label: 'Cross-device',
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _BenefitItem(
                        icon: Icons.security_outlined,
                        label: 'Secure',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.x2),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCtaPressed,
                icon: const Icon(Icons.login_outlined, size: 20),
                label: Text(ctaLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _BenefitItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
