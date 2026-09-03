import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:url_launcher/url_launcher.dart';

class FoodScanCameraDialog extends StatefulWidget {
  const FoodScanCameraDialog({super.key});

  @override
  State<FoodScanCameraDialog> createState() => _FoodScanCameraDialogState();
}

class _FoodScanCameraDialogState extends State<FoodScanCameraDialog> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  Future<void>? _initFuture;

  bool _isBusy = false;
  bool _torchOn = false;
  int _cameraIndex = 0;
  String? _errorMessage;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  bool _isPermissionDenied(Object error) {
    if (error is CameraException) {
      final code = error.code;
      return code == 'CameraAccessDenied' ||
          code == 'CameraAccessDeniedWithoutPrompt' ||
          code == 'AudioAccessDenied' ||
          code == 'AudioAccessDeniedWithoutPrompt';
    }
    return false;
  }

  String _friendlyErrorMessage(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) return 'Couldn’t access the camera. Please try again.';
    return text.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  /// Records an error from camera setup, flagging permission denials so the
  /// preview can show a legible recovery panel instead of low-contrast text.
  void _setError(Object error) {
    if (!mounted) return;
    setState(() {
      _permissionDenied = _isPermissionDenied(error);
      _errorMessage = _permissionDenied ? null : _friendlyErrorMessage(error);
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

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _errorMessage = 'No camera available on this device.');
        return;
      }

      final backIndex = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      final initialIndex = backIndex >= 0 ? backIndex : 0;

      setState(() => _cameras = cameras);
      await _setCamera(initialIndex);
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> _setCamera(int index) async {
    if (index < 0 || index >= _cameras.length) return;
    setState(() {
      _cameraIndex = index;
      _errorMessage = null;
      _permissionDenied = false;
      _torchOn = false;
    });

    final previous = _controller;
    _controller = null;
    if (previous != null) {
      await previous.dispose();
    }

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    final initFuture = controller.initialize();
    setState(() {
      _controller = controller;
      _initFuture = initFuture;
    });

    try {
      await initFuture;
      await controller.setFlashMode(FlashMode.off);
    } catch (e) {
      await controller.dispose();
      _setError(e);
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    final initFuture = _initFuture;
    if (controller == null || initFuture == null || _isBusy) return;
    setState(() => _isBusy = true);

    try {
      await initFuture;
      final next = _torchOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(next);
      if (!mounted) return;
      setState(() {
        _torchOn = !_torchOn;
        _isBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _errorMessage = _friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isBusy) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    await _setCamera(next);
  }

  Future<void> _capture() async {
    final controller = _controller;
    final initFuture = _initFuture;
    if (controller == null || initFuture == null || _isBusy) return;
    setState(() => _isBusy = true);

    try {
      await initFuture;
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      context.pop<Uint8List>(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _errorMessage = _friendlyErrorMessage(e);
      });
    }
  }

  /// A contained, legible recovery panel — used for both permission denials and
  /// generic camera errors so messaging never reads as low-contrast text on the
  /// dark preview background.
  Widget _buildRecoveryPanel(ThemeData theme) {
    final colors = theme.colorScheme;
    final title = _permissionDenied
        ? 'Camera access is off'
        : 'Camera unavailable';
    final body = _permissionDenied
        ? 'To scan meals, allow camera access for Hustl in Settings. You can still add food by hand any time.'
        : (_errorMessage ?? 'Couldn’t access the camera. Please try again.');

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
                child: Icon(Icons.photo_camera_outlined, color: colors.primary),
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
              if (_permissionDenied)
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
              if (_permissionDenied) const SizedBox(height: AppSpacing.x1),
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

  Widget _buildPreview(ThemeData theme) {
    final controller = _controller;
    final initFuture = _initFuture;

    if (_permissionDenied || _errorMessage != null) {
      return _buildRecoveryPanel(theme);
    }

    if (controller == null || initFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        final previewSize = controller.value.previewSize;
        if (previewSize == null) {
          return Center(child: CameraPreview(controller));
        }

        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final child = SizedBox(
          width: isPortrait ? previewSize.height : previewSize.width,
          height: isPortrait ? previewSize.width : previewSize.height,
          child: CameraPreview(controller),
        );

        return ClipRect(
          clipBehavior: Clip.hardEdge,
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final canSwitch = _cameras.length >= 2;
    final hasError = _permissionDenied || _errorMessage != null;

    return Dialog.fullscreen(
      child: Stack(
        children: [
          Positioned.fill(child: _buildPreview(theme)),
          Positioned(
            top: topInset + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close),
              color: AppColors.brandCloudWhite,
              onPressed: _isBusy ? null : () => context.pop(),
              tooltip: 'Close',
            ),
          ),
          Positioned(
            top: topInset + 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: hasError ? null : _toggleTorch,
                  icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                  color: AppColors.brandCloudWhite,
                  tooltip: _torchOn ? 'Torch on' : 'Torch off',
                ),
                IconButton(
                  onPressed: hasError || !canSwitch ? null : _switchCamera,
                  icon: const Icon(Icons.cameraswitch),
                  color: AppColors.brandCloudWhite,
                  tooltip: 'Switch camera',
                ),
              ],
            ),
          ),
          if (!hasError)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      theme.colorScheme.scrim.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tips: full plate · top-down · good light · hold steady',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.brandCloudWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _capture,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.brandCloudWhite,
                            width: 4,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.brandCloudWhite.withValues(
                                alpha: 0.9,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isBusy) ...[
                      const SizedBox(height: 12),
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
