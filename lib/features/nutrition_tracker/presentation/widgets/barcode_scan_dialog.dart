import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of [BarcodeScanDialog]. `null` (dialog dismissed) means the user
/// backed out entirely.
sealed class BarcodeScanResult {
  const BarcodeScanResult();
}

/// A barcode was detected.
class BarcodeScanCode extends BarcodeScanResult {
  const BarcodeScanCode(this.code);

  final String code;
}

/// The user asked to type the code instead (camera denied/unavailable, or
/// nothing scanned) — the caller should open its manual-entry prompt.
class BarcodeScanManualEntry extends BarcodeScanResult {
  const BarcodeScanManualEntry();
}

class BarcodeScanDialog extends StatefulWidget {
  const BarcodeScanDialog({
    super.key,
    this.previewBuilder,
    this.simulatedError,
  });

  /// Builds the camera preview. Defaults to a live [MobileScanner]. Overridable
  /// in tests so the dialog can be exercised without a camera plugin.
  @visibleForTesting
  final Widget Function(void Function(BarcodeCapture) onDetect)? previewBuilder;

  /// When set, the dialog renders the camera-error recovery panel immediately.
  /// Test-only — lets widget tests exercise the error surface without a
  /// camera.
  @visibleForTesting
  final MobileScannerException? simulatedError;

  @override
  State<BarcodeScanDialog> createState() => _BarcodeScanDialogState();
}

class _BarcodeScanDialogState extends State<BarcodeScanDialog> {
  /// Auto-dismiss the dialog if no barcode is seen within this window.
  static const Duration _inactivityTimeout = Duration(seconds: 9);

  /// How long the success flash stays on screen before the dialog closes, so
  /// the cue is perceptible rather than instantaneous.
  static const Duration _successLinger = Duration(milliseconds: 160);

  /// Copy shown when the scanner gives up after no barcode is detected.
  static const String _timedOutMessage = 'No barcode found yet.';

  MobileScannerController? _controller;
  Timer? _inactivityTimer;
  Timer? _successTimer;
  bool _hasScanned = false;
  bool _showSuccessFlash = false;
  bool _timedOut = false;
  MobileScannerException? _cameraError;

  @override
  void initState() {
    super.initState();
    _cameraError = widget.simulatedError;
    if (widget.previewBuilder == null && _cameraError == null) {
      _controller = MobileScannerController();
    }
    if (_cameraError == null) _startInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _successTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, _onInactivityTimeout);
  }

  void _onInactivityTimeout() {
    if (_hasScanned || _timedOut || !mounted) return;
    setState(() => _timedOut = true);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere(
          (v) => v != null && v.trim().isNotEmpty,
          orElse: () => null,
        );
    if (barcode == null) return;
    _hasScanned = true;
    final code = barcode.trim();
    _inactivityTimer?.cancel();
    unawaited(Haptics.confirm());
    // Show the flash cue for a beat so it registers, then close with the code.
    setState(() => _showSuccessFlash = true);
    _successTimer = Timer(_successLinger, () {
      if (!mounted) return;
      context.pop(BarcodeScanCode(code));
    });
  }

  Future<void> _openSettings() async {
    final uri = Uri.parse('app-settings:');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      HustlSnack.show(
        context,
        'Open Settings, then enable camera access for Hustl.',
        variant: HustlSnackVariant.warning,
      );
    }
  }

  Widget _buildCloseButton(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + AppSpacing.x1,
      left: AppSpacing.x1,
      child: IconButton(
        icon: const Icon(Icons.close),
        color: AppColors.brandCloudWhite,
        onPressed: () => context.pop(),
      ),
    );
  }

  /// A contained, legible recovery panel shown when the camera plugin reports
  /// an error — permission denial or otherwise — instead of the plugin's
  /// default error surface.
  Widget _buildRecoveryPanel(ThemeData theme) {
    final colors = theme.colorScheme;
    final denied =
        _cameraError?.errorCode == MobileScannerErrorCode.permissionDenied;
    final title = denied ? 'Camera access is off' : 'Camera unavailable';
    final body = denied
        ? 'To scan barcodes, allow camera access for Hustl in Settings. You can also type the barcode instead.'
        : 'Couldn’t access the camera. You can type the barcode instead.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(AppSpacing.x3),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSpacing.x6,
                height: AppSpacing.x6,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              if (denied)
                Semantics(
                  button: true,
                  label: 'Open settings',
                  child: FilledButton(
                    onPressed: _openSettings,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Open settings'),
                  ),
                ),
              if (denied) const SizedBox(height: AppSpacing.x1),
              Semantics(
                button: true,
                label: 'Enter code manually',
                child: TextButton(
                  onPressed: () => context.pop(const BarcodeScanManualEntry()),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Enter code manually'),
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Semantics(
                button: true,
                label: 'Close',
                child: TextButton(
                  onPressed: () => context.pop(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_cameraError != null) {
      return Dialog.fullscreen(
        child: Stack(
          children: [_buildRecoveryPanel(theme), _buildCloseButton(context)],
        ),
      );
    }

    final preview =
        widget.previewBuilder?.call(_onDetect) ??
        MobileScanner(
          controller: _controller,
          fit: BoxFit.cover,
          onDetect: _onDetect,
          errorBuilder: (context, error) {
            if (_cameraError == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _cameraError != null) return;
                _inactivityTimer?.cancel();
                setState(() => _cameraError = error);
              });
            }
            return const SizedBox.shrink();
          },
        );
    return Dialog.fullscreen(
      child: Stack(
        fit: StackFit.expand,
        children: [
          preview,
          const _ScannerCrosshair(),
          if (_showSuccessFlash) const _SuccessFlash(),
          _buildCloseButton(context),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x2,
                AppSpacing.x3,
                AppSpacing.x3,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    theme.colorScheme.scrim.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: _timedOut
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _timedOutMessage,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.brandCloudWhite,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Semantics(
                          button: true,
                          label: 'Keep scanning',
                          child: FilledButton(
                            onPressed: () {
                              setState(() => _timedOut = false);
                              _startInactivityTimer();
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text('Keep scanning'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Semantics(
                          button: true,
                          label: 'Enter code manually',
                          child: TextButton(
                            onPressed: () =>
                                context.pop(const BarcodeScanManualEntry()),
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: AppColors.brandCloudWhite,
                            ),
                            child: const Text('Enter code manually'),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Align the barcode within the frame',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.brandCloudWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Center viewfinder frame that guides one-handed aim. A rounded rectangle with
/// a thin '+' reticle in the middle.
class _ScannerCrosshair extends StatelessWidget {
  const _ScannerCrosshair();

  @override
  Widget build(BuildContext context) {
    final frame = AppColors.brandCloudWhite.withValues(alpha: 0.85);
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 240,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: frame, width: 2),
                  borderRadius: BorderRadius.circular(AppSpacing.x2),
                ),
              ),
              SizedBox(
                width: AppSpacing.x3,
                child: Divider(color: frame, thickness: 1.5, height: 0),
              ),
              SizedBox(
                height: AppSpacing.x3,
                child: VerticalDivider(color: frame, thickness: 1.5, width: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brief full-screen highlight shown the instant a barcode is detected.
///
/// Mounted only on a hit (and torn down ~160ms later when the dialog pops), it
/// fades from transparent to its tinted peak so the cue actually flashes. The
/// old `AnimatedOpacity(opacity: 1)` never animated because the value was
/// constant from first build; a [TweenAnimationBuilder] self-drives the fade
/// the moment it appears.
class _SuccessFlash extends StatelessWidget {
  const _SuccessFlash();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.fast,
        curve: AppMotion.enterCurve,
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: ColoredBox(
          color: AppColors.accentEmeraldGreen.withValues(alpha: 0.35),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
