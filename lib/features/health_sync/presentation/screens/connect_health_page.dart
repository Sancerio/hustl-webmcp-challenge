import 'package:flutter/material.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/health_platform_labels.dart';
import '../../../../core/widgets/hustl_icon.dart';
import '../../domain/models/recovery_signal_availability.dart';

/// First-run connect / permissions-denied hero. Wave I: composed in the shared
/// [ScreenEmptyState] language — a soft blue-tinted icon holder carrying the
/// [HustlIcon] heart glyph, a confident sentence-case headline, a supportive
/// line, the value-prop bullets, and a single blue connect CTA.
///
/// Connect reliability (R1 phase 2): the page is capability-aware. On Android it
/// can route to install Health Connect when the provider is missing, and it can
/// surface a targeted re-grant prompt for the specific recovery signals that
/// are not yet flowing — never a generic reconnect. All new behavior is
/// additive: with the defaults it renders exactly as before.
class ConnectHealthPage extends StatelessWidget {
  const ConnectHealthPage({
    super.key,
    required this.onConnectPressed,
    required this.showPermissionInstructions,
    this.permanentlyDenied = false,
    this.providerAvailability = HealthProviderAvailability.available,
    this.missingSignals = const [],
    this.onInstallHealthConnect,
    this.onOpenManagePermissions,
  });

  final VoidCallback onConnectPressed;
  final bool showPermissionInstructions;
  final bool permanentlyDenied;

  /// Reachability of the underlying provider. When
  /// [HealthProviderAvailability.needsInstall] (Android Health Connect missing
  /// or out of date) the page leads with an install/update route.
  final HealthProviderAvailability providerAvailability;

  /// Recovery signals that are not yet flowing. When non-empty the page adds a
  /// kind, targeted "turn on …" prompt instead of a generic reconnect.
  final List<RecoverySignal> missingSignals;

  /// Routes the user to install / update Health Connect. Required for the
  /// install state to show its action; ignored otherwise.
  final VoidCallback? onInstallHealthConnect;

  /// Android-14 escape: opens the Health Connect manage-permissions surface so a
  /// permanently-denied user can re-grant access (the system no longer
  /// re-prompts after a hard denial). When provided and [permanentlyDenied] is
  /// true, the page leads with an "Open Health Connect settings" CTA instead of
  /// a retry that the OS would silently swallow. Null elsewhere keeps today's
  /// retry behavior.
  final VoidCallback? onOpenManagePermissions;

  bool get _needsInstall =>
      providerAvailability == HealthProviderAvailability.needsInstall;

  bool get _needsUpdate =>
      providerAvailability == HealthProviderAvailability.needsUpdate;

  /// True when Health Connect must be installed OR updated before it can supply
  /// data. Both lead with a Play-listing CTA; the copy differs per state.
  bool get _needsSetup => _needsInstall || _needsUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final providerLabel = healthPlatformLabel(platform: theme.platform);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Soft layered blue holder with the heart glyph — the same
                // welcoming language as ScreenEmptyState.
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.06),
                  ),
                  child: Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                    child: HustlIcon(
                      asset: 'assets/icons/ic_heart.svg',
                      size: 40,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  _needsUpdate
                      ? 'Update $providerLabel'
                      : _needsInstall
                      ? 'Set up $providerLabel'
                      : 'Connect $providerLabel',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  _needsUpdate
                      ? 'Health Connect is out of date, so it can\'t share your '
                            'sleep and recovery yet. Update it, then pair Hustl '
                            'to see your readiness next to your training.'
                      : _needsInstall
                      ? 'Health Connect collects your sleep and recovery from '
                            'your watch. Install it, then pair Hustl to see your '
                            'readiness next to your training.'
                      : 'Pair your body metrics with your training so weight '
                            'and body fat trends sit right next to your workout '
                            'volume.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                _buildBullet(
                  context,
                  'See weight and body fat trends next to workout volume.',
                ),
                _buildBullet(
                  context,
                  'Keep your progress synced across Hustl and $providerLabel.',
                ),
                if (_needsSetup)
                  _buildBullet(
                    context,
                    'A compatible watch keeps your sleep and recovery flowing.',
                  ),
                if (missingSignals.isNotEmpty && !_needsSetup)
                  _buildSignalPrompt(context, providerLabel),
                if (permanentlyDenied && showPermissionInstructions) ...[
                  const SizedBox(height: AppSpacing.x2),
                  _buildNote(
                    context,
                    onOpenManagePermissions != null
                        ? 'Health access was turned off before. Open '
                              '$providerLabel settings to turn it back on for '
                              'Hustl, then come back.'
                        : 'Health access was turned off before. Re-enable it '
                              'for Hustl in $providerLabel, then try again.',
                  ),
                ],
                const SizedBox(height: AppSpacing.x3),
                if (_needsSetup && onInstallHealthConnect != null) ...[
                  FilledButton(
                    onPressed: onInstallHealthConnect,
                    style: _ctaStyle(),
                    child: Text(
                      _needsUpdate
                          ? 'Update Health Connect'
                          : 'Get Health Connect',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  TextButton(
                    onPressed: onConnectPressed,
                    child: Text(
                      _needsUpdate ? 'It\'s already up to date' : 'I already have it',
                    ),
                  ),
                ] else if (permanentlyDenied &&
                    onOpenManagePermissions != null) ...[
                  FilledButton(
                    onPressed: onOpenManagePermissions,
                    style: _ctaStyle(),
                    child: Text('Open $providerLabel settings'),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  TextButton(
                    onPressed: onConnectPressed,
                    child: const Text('Retry connection'),
                  ),
                ] else
                  FilledButton(
                    onPressed: onConnectPressed,
                    style: _ctaStyle(),
                    child: Text(_connectLabel()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _connectLabel() {
    if (permanentlyDenied) return 'Retry connection';
    if (missingSignals.isNotEmpty) return 'Turn on these signals';
    return 'Connect now';
  }

  ButtonStyle _ctaStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.controlRadius,
      ),
    );
  }

  Widget _buildSignalPrompt(BuildContext context, String providerLabel) {
    final labels = missingSignals.map((s) => s.displayLabel).toList();
    final joined = _joinNaturally(labels);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x2),
      child: _buildNote(
        context,
        "You're connected, but $joined isn't coming through yet. Turn it on "
        'for Hustl in $providerLabel to unlock your full readiness picture.',
      ),
    );
  }

  Widget _buildNote(BuildContext context, String text) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    );
  }

  static String _joinNaturally(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    final head = items.sublist(0, items.length - 1).join(', ');
    return '$head, and ${items.last}';
  }

  Widget _buildBullet(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
