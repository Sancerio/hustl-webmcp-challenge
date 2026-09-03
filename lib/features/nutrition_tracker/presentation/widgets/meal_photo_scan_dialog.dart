import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/onboarding_permission_primer.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/models/food_log_entry.dart';
import '../../domain/models/meal_scan_result.dart';
import '../../domain/repositories/meal_scan_repository.dart';
import '../../domain/services/meal_scan_plate_mapper.dart';
import 'ai_capture_consent_sheet.dart';
import 'food_scan_camera_dialog.dart';
import 'meal_describe_field.dart';
import 'meal_photo_scan_loading_view.dart';
import 'meal_scan_plate_draft.dart';
import 'meal_scan_target_compare.dart';

enum MealPhotoScanAction { logMeal, addToPlate }

class MealPhotoScanResult {
  const MealPhotoScanResult({
    required this.totalEntry,
    required this.plateEntries,
    required this.action,
  });

  final FoodLogEntry totalEntry;
  final List<FoodLogEntry> plateEntries;
  final MealPhotoScanAction action;
}

class MealPhotoScanDialog extends StatefulWidget {
  const MealPhotoScanDialog({
    super.key,
    required this.date,
    required this.primaryAction,
    required this.autoStartCamera,
    this.startInDescribe = false,
    this.defaultLoggedAt,
    this.dayTargetCalories,
    this.dayConsumedCalories,
  });

  final DateTime date;
  final MealPhotoScanAction primaryAction;
  final bool autoStartCamera;

  /// The day's calorie target and the calories already logged before this meal.
  /// When [dayTargetCalories] is set (> 0), the scan result shows a live
  /// target-vs-consumed comparison. Both null on entry points without a loaded
  /// diary (the global scan shortcut), where the comparison is simply omitted.
  final double? dayTargetCalories;
  final double? dayConsumedCalories;

  /// Opens straight into the "describe a meal" text entry instead of the photo
  /// buttons, so the add-food Describe chip can reach the NL flow in one tap.
  /// Mutually exclusive with [autoStartCamera] (describe wins if both are set).
  final bool startInDescribe;
  final DateTime? defaultLoggedAt;

  @override
  State<MealPhotoScanDialog> createState() => _MealPhotoScanDialogState();
}

class _MealPhotoScanDialogState extends State<MealPhotoScanDialog> {
  final _imagePicker = ImagePicker();

  Uint8List? _imageBytes;
  MealScanResult? _scan;
  String? _scanErrorMessage;
  bool _isBusy = false;
  bool _showManualEntryWhileScanning = false;
  bool _hasManualEdits = false;
  // Tracks manual edits to the MACRO fields only (not the meal name). The plate
  // -> totals sync is suppressed only once the user has typed their own macros,
  // so renaming the meal doesn't freeze "Log total only" on stale totals.
  bool _hasManualMacroEdits = false;
  bool _suppressEditTracking = false;

  /// Synchronous re-entrancy guard. Set at the very top of the photo/describe
  /// handlers before any await, so a double-tap can't stack two consent sheets
  /// or two AI calls during the window before [_isBusy] flips.
  bool _aiRequestInFlight = false;

  /// Working copy of the scanned items, kept in sync with the editable plate
  /// draft. The commit action builds plate entries from this list.
  List<MealScanItem> _editedItems = const [];

  /// Whether the describe-a-meal text entry is shown instead of the photo
  /// buttons. Seeded from [MealPhotoScanDialog.startInDescribe] so the Describe
  /// chip opens straight into the text flow; otherwise defaults to photo capture.
  late bool _showDescribeEntry = widget.startInDescribe;

  Timer? _hintTimer;
  Timer? _elapsedTimer;
  DateTime? _busyStartedAt;
  int _hintIndex = 0;
  int _busySeconds = 0;

  static const _loadingHints = <String>[
    'Estimating calories & macros',
    'Breaking into items',
    'Almost done',
  ];

  final _mealNameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();

  /// Optional free-text hint (cuisine, restaurant, notes) passed to the AI as
  /// `notes` to improve accuracy. Never required.
  final _detailController = TextEditingController();

  /// Anchors the editable items section so the target-compare "Adjust portion"
  /// affordance can scroll the existing per-item editor into view.
  final _itemsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _mealNameController.addListener(() {
      if (_suppressEditTracking) return;
      _hasManualEdits = true;
    });
    for (final controller in [
      _caloriesController,
      _proteinController,
      _carbsController,
      _fatController,
    ]) {
      controller.addListener(() {
        if (_suppressEditTracking) return;
        _hasManualEdits = true;
        _hasManualMacroEdits = true;
      });
    }
    if (widget.autoStartCamera && !widget.startInDescribe) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Open the camera straight away, but if the user backs out, land them
        // in the dialog (photo / library / describe a meal) rather than
        // dismissing — otherwise auto-start would hide those alternatives.
        _pickImage(ImageSource.camera, dismissOnCancel: false);
      });
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _elapsedTimer?.cancel();
    _mealNameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  void _startBusyUi() {
    _hintTimer?.cancel();
    _elapsedTimer?.cancel();

    _busyStartedAt = DateTime.now();
    _busySeconds = 0;
    _hintIndex = 0;

    _hintTimer = Timer.periodic(const Duration(milliseconds: 1700), (_) {
      if (!mounted || !_isBusy) return;
      setState(() {
        _hintIndex = (_hintIndex + 1) % _loadingHints.length;
      });
    });
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _busyStartedAt;
      if (!mounted || !_isBusy || start == null) return;
      setState(() {
        _busySeconds = DateTime.now().difference(start).inSeconds;
      });
    });
  }

  void _stopBusyUi() {
    _hintTimer?.cancel();
    _hintTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _busyStartedAt = null;
    _busySeconds = 0;
    _hintIndex = 0;
  }

  String _guessMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  double? _tryParseNonNegative(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null || value < 0) return null;
    return value;
  }

  void _seedControllers(MealScanResult result) {
    _suppressEditTracking = true;
    _mealNameController.text = result.mealName.trim().isEmpty
        ? 'Meal'
        : result.mealName.trim();
    _caloriesController.text = result.totals.caloriesKcal == null
        ? ''
        : result.totals.caloriesKcal!.toStringAsFixed(0);
    _proteinController.text = result.totals.proteinGrams == null
        ? ''
        : result.totals.proteinGrams!.toStringAsFixed(0);
    _carbsController.text = result.totals.carbsGrams == null
        ? ''
        : result.totals.carbsGrams!.toStringAsFixed(0);
    _fatController.text = result.totals.fatGrams == null
        ? ''
        : result.totals.fatGrams!.toStringAsFixed(0);
    _suppressEditTracking = false;
  }

  void _maybeSeedControllers(MealScanResult result) {
    if (_hasManualEdits) return;
    final hasText =
        _mealNameController.text.trim().isNotEmpty ||
        _caloriesController.text.trim().isNotEmpty ||
        _proteinController.text.trim().isNotEmpty ||
        _carbsController.text.trim().isNotEmpty ||
        _fatController.text.trim().isNotEmpty;
    if (hasText) return;
    _seedControllers(result);
  }

  void _clearControllers() {
    _suppressEditTracking = true;
    _mealNameController.clear();
    _caloriesController.clear();
    _proteinController.clear();
    _carbsController.clear();
    _fatController.clear();
    _suppressEditTracking = false;
  }

  /// Re-seeds the top macro fields from the live plate draft so "Log total
  /// only" never logs stale totals that disagree with the reviewed plate. Skips
  /// when the user has typed their own totals; the writes are wrapped so they
  /// don't trip the manual-edit flag.
  void _syncTotalsFromEditedItems() {
    if (_hasManualMacroEdits) return;
    double sum(double? Function(MealScanItem) pick) =>
        _editedItems.fold(0, (acc, item) => acc + (pick(item) ?? 0));
    final kcal = sum((i) => i.caloriesKcal);
    final protein = sum((i) => i.proteinGrams);
    final carbs = sum((i) => i.carbsGrams);
    final fat = sum((i) => i.fatGrams);
    _suppressEditTracking = true;
    _caloriesController.text = kcal.toStringAsFixed(0);
    _proteinController.text = protein.toStringAsFixed(0);
    _carbsController.text = carbs.toStringAsFixed(0);
    _fatController.text = fat.toStringAsFixed(0);
    _suppressEditTracking = false;
  }

  String _friendlyScanErrorMessage(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) return 'Couldn’t scan that meal photo. Please try again.';
    // A raw transport failure — e.g. the app was backgrounded mid-upload and
    // the socket was torn down — reads as "ClientException: Bad file
    // descriptor, uri=…". Never surface that to the user.
    if (text.startsWith('ClientException') ||
        text.contains('Bad file descriptor') ||
        text.contains('SocketException')) {
      return 'Couldn’t reach Hustl — check your connection and try again.';
    }
    // Avoid leaking raw exception prefixes into the UI.
    return text.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  Future<void> _pickImage(
    ImageSource source, {
    required bool dismissOnCancel,
  }) async {
    if (_isBusy) return;
    // Synchronous re-entrancy guard before any await — blocks a double-tap from
    // stacking two consent sheets / two AI calls in the pre-_isBusy window.
    if (_aiRequestInFlight) return;
    _aiRequestInFlight = true;
    try {
      // Gate every AI capture behind one-time consent before touching the
      // camera or gallery. Declining aborts quietly.
      final consented = await ensureAiCaptureConsent(context);
      if (!mounted) return;
      if (!consented) {
        if (dismissOnCancel) context.pop();
        return;
      }

      Uint8List? bytes;
      if (source == ImageSource.camera && !kIsWeb) {
        // Explain why we need the camera before the OS prompt appears, so the
        // request never arrives cold — but only ONCE. After the primer has been
        // shown it's remembered, so later scans go straight to the camera
        // instead of re-prompting on every capture.
        final prefs = GetIt.instance<PreferencesService>();
        final seenPrimer = await prefs.getSeenMealScanCameraPrimer();
        if (!mounted) return;
        if (!seenPrimer) {
          final allowed = await OnboardingPermissionPrimer.show(
            context,
            assetIcon: 'assets/icons/ic_flame.svg',
            title: 'Scan your meal',
            message:
                'Snap a photo to log food instantly — we’ll need camera access.',
            allowLabel: 'Continue',
          );
          // Only consume the primer on an explicit choice; an accidental
          // dismissal must leave it unseen so it shows again next time.
          if (allowed != PermissionPrimerChoice.dismissed) {
            await prefs.setSeenMealScanCameraPrimer(true);
          }
          if (!mounted) return;
          if (allowed != PermissionPrimerChoice.allow) {
            if (dismissOnCancel) context.pop();
            return;
          }
        }
        bytes = await showDialog<Uint8List>(
          context: context,
          builder: (context) => const FoodScanCameraDialog(),
        );
      } else {
        final file = await _imagePicker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1400,
        );
        if (!mounted) return;
        if (file != null) {
          bytes = await file.readAsBytes();
        }
      }

      if (!mounted) return;
      if (bytes == null) {
        if (dismissOnCancel) context.pop();
        return;
      }

      final mimeType = _guessMimeType(bytes);

      setState(() {
        _imageBytes = bytes;
        _isBusy = true;
        _showManualEntryWhileScanning = false;
        _hasManualEdits = false;
        _hasManualMacroEdits = false;
        _scan = null;
        _scanErrorMessage = null;
      });
      _clearControllers();
      _startBusyUi();

      final detail = _detailController.text.trim();
      final repo = GetIt.instance<MealScanRepository>();
      final result = await repo.scanMealPhoto(
        imageBytes: bytes,
        mimeType: mimeType,
        notes: detail.isEmpty ? null : detail,
      );

      if (!mounted) return;
      _applyScanResult(result);
    } catch (e) {
      if (!mounted) return;
      _applyScanError(e);
    } finally {
      _aiRequestInFlight = false;
    }
  }

  /// Describe-a-meal path: estimate macros from typed/dictated text. Shares the
  /// same consent gate, busy/error UI, and result handling as the photo scan.
  Future<void> _describeMeal(String text) async {
    if (_isBusy) return;
    final description = text.trim();
    if (description.isEmpty) return;
    // Synchronous re-entrancy guard before any await — see [_pickImage].
    if (_aiRequestInFlight) return;
    _aiRequestInFlight = true;
    try {
      final consented = await ensureAiCaptureConsent(context);
      if (!mounted) return;
      if (!consented) return;

      setState(() {
        _imageBytes = null;
        _isBusy = true;
        _showManualEntryWhileScanning = false;
        _hasManualEdits = false;
        _hasManualMacroEdits = false;
        _scan = null;
        _editedItems = const [];
        _scanErrorMessage = null;
      });
      _clearControllers();
      _startBusyUi();

      final detail = _detailController.text.trim();
      final repo = GetIt.instance<MealScanRepository>();
      final result = await repo.describeMeal(
        text: description,
        notes: detail.isEmpty ? null : detail,
      );

      if (!mounted) return;
      _applyScanResult(result);
    } catch (e) {
      if (!mounted) return;
      _applyScanError(e);
    } finally {
      _aiRequestInFlight = false;
    }
  }

  void _applyScanResult(MealScanResult result) {
    setState(() {
      _scan = result;
      _editedItems = List<MealScanItem>.from(result.items);
      _isBusy = false;
      _showManualEntryWhileScanning = false;
      _scanErrorMessage = null;
    });
    _stopBusyUi();
    _maybeSeedControllers(result);
  }

  void _applyScanError(Object error) {
    setState(() {
      _isBusy = false;
      _scan = null;
      _editedItems = const [];
      _scanErrorMessage = _friendlyScanErrorMessage(error);
      _showManualEntryWhileScanning = true;
    });
    _stopBusyUi();
  }

  MealPhotoScanResult? _buildResult(MealPhotoScanAction action) {
    final seed = widget.defaultLoggedAt?.toLocal();
    final now = seed ?? DateTime.now();
    final loggedAt = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      now.hour,
      now.minute,
      now.second,
    );
    final mealName = _mealNameController.text.trim().isEmpty
        ? 'Meal'
        : _mealNameController.text.trim();
    final calories = _tryParseNonNegative(_caloriesController) ?? 0;
    final protein = _tryParseNonNegative(_proteinController) ?? 0;
    final carbs = _tryParseNonNegative(_carbsController) ?? 0;
    final fat = _tryParseNonNegative(_fatController) ?? 0;

    final totalEntry = FoodLogEntry(
      id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
      date: widget.date,
      loggedAt: loggedAt,
      servingGrams: 1,
      calories: calories,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
      foodName: mealName,
      source: 'meal_scan',
    );

    final scan = _scan;
    // Build the plate from the user's edited items (grams tweaks, removals),
    // not the original AI result.
    final scanEntries = scan == null
        ? const <FoodLogEntry>[]
        : mealScanResultToPlateEntries(
            scan: MealScanResult(
              mealName: scan.mealName,
              totals: scan.totals,
              items: _editedItems,
              confidence: scan.confidence,
              assumptions: scan.assumptions,
              warnings: scan.warnings,
              debug: scan.debug,
            ),
            date: widget.date,
            loggedAt: loggedAt,
          );
    final plateEntries = scanEntries.isNotEmpty
        ? scanEntries
        : <FoodLogEntry>[totalEntry];

    final totalHasMacros = calories > 0 || protein > 0 || carbs > 0 || fat > 0;

    if (action == MealPhotoScanAction.logMeal && !totalHasMacros) {
      HustlSnack.show(
        context,
        'Enter at least calories or macros to log this meal.',
        variant: HustlSnackVariant.warning,
      );
      return null;
    }

    if (action == MealPhotoScanAction.addToPlate &&
        scanEntries.isEmpty &&
        !totalHasMacros) {
      HustlSnack.show(
        context,
        'Enter at least calories or macros to add this meal.',
        variant: HustlSnackVariant.warning,
      );
      return null;
    }

    return MealPhotoScanResult(
      totalEntry: totalEntry,
      plateEntries: plateEntries,
      action: action,
    );
  }

  /// Brings the existing editable items list into view — the "Adjust portion"
  /// correction reuses the plate editor rather than inventing a new flow.
  void _scrollToItems() {
    final ctx = _itemsSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppMotion.sheet,
      curve: AppMotion.enterCurve,
      alignment: 0.1,
    );
  }

  String _confidenceLabel(double value) {
    if (value >= 0.75) return 'High confidence';
    if (value >= 0.5) return 'Medium confidence';
    if (value >= 0.25) return 'Low confidence';
    return 'Very low confidence';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = _scan;

    // The editable form (meal name, macros, plate draft, commit buttons) shows
    // once a photo is being reviewed, or once a describe-path estimate/error is
    // ready while no image is attached.
    final hasResultOrError = scan != null || _scanErrorMessage != null;
    final showEditableForm =
        (_imageBytes != null && (!_isBusy || _showManualEntryWhileScanning)) ||
        (_imageBytes == null &&
            ((!_isBusy && hasResultOrError) || _showManualEntryWhileScanning));

    String labelForAction(MealPhotoScanAction action) {
      switch (action) {
        case MealPhotoScanAction.addToPlate:
          return 'Review plate';
        case MealPhotoScanAction.logMeal:
          return 'Log total only';
      }
    }

    final primaryAction = widget.primaryAction;
    final secondaryAction = widget.primaryAction == MealPhotoScanAction.logMeal
        ? MealPhotoScanAction.addToPlate
        : MealPhotoScanAction.logMeal;
    final primaryLabel = labelForAction(primaryAction);
    final secondaryLabel = labelForAction(secondaryAction);

    final dialog = Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
          title: const Text('Food Scan'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x2,
              AppSpacing.x2,
              AppSpacing.x2,
              AppSpacing.x3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showDescribeEntry) ...[
                  MealDescribeField(
                    enabled: !_isBusy,
                    onEstimate: _describeMeal,
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  TextButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () => setState(() => _showDescribeEntry = false),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Use a photo instead'),
                  ),
                ] else ...[
                  // Hero capture card — the card itself is the primary tap
                  // target (single elevation; no FilledButton-on-card double
                  // cue). The blue icon/label use colorScheme.primary, the
                  // app-icon brand blue.
                  _HeroCaptureCard(
                    enabled: !_isBusy,
                    onTap: () =>
                        _pickImage(ImageSource.camera, dismissOnCancel: false),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  // Secondary actions — gallery + describe, demoted to a
                  // two-up row so both alternatives stay visible without
                  // competing with the hero.
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => _pickImage(
                                  ImageSource.gallery,
                                  dismissOnCancel: false,
                                ),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Choose photo'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => setState(() => _showDescribeEntry = true),
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('Describe a meal'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.x3),
                TextField(
                  controller: _detailController,
                  enabled: !_isBusy,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Add detail (optional)',
                    hintText:
                        'Cuisine, restaurant, or notes to improve accuracy',
                  ),
                ),
                if (_isBusy && _imageBytes == null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  MealPhotoScanLoadingView(
                    imageBytes: null,
                    hintText: _loadingHints[_hintIndex],
                    isTakingLong: _busySeconds >= 8,
                    onCancel: () => context.pop(),
                    onLogManuallyInstead:
                        _busySeconds >= 8 && !_showManualEntryWhileScanning
                        ? () {
                            setState(() {
                              _showManualEntryWhileScanning = true;
                            });
                          }
                        : null,
                    showItemsSkeleton: !_showManualEntryWhileScanning,
                  ),
                ],
                if (_imageBytes != null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  if (_isBusy)
                    MealPhotoScanLoadingView(
                      imageBytes: _imageBytes!,
                      hintText: _loadingHints[_hintIndex],
                      isTakingLong: _busySeconds >= 8,
                      onCancel: () => context.pop(),
                      onLogManuallyInstead:
                          _busySeconds >= 8 && !_showManualEntryWhileScanning
                          ? () {
                              setState(() {
                                _showManualEntryWhileScanning = true;
                              });
                            }
                          : null,
                      showItemsSkeleton: !_showManualEntryWhileScanning,
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _imageBytes!,
                        fit: BoxFit.cover,
                        height: 220,
                      ),
                    ),
                ],
                if (showEditableForm) ...[
                  const SizedBox(height: AppSpacing.x2),
                  if (_scanErrorMessage != null) ...[
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.errorContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: theme.colorScheme.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _scanErrorMessage!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1 + 4),
                    Text(
                      'You can still log this meal by entering calories/macros below.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1 + 4),
                  ],
                  TextField(
                    controller: _mealNameController,
                    decoration: const InputDecoration(labelText: 'Meal name'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    scan != null ? 'Estimated macros' : 'Calories & macros',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _caloriesController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Calories (kcal)',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1 + 4),
                      Expanded(
                        child: TextField(
                          controller: _proteinController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Protein (g)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x1 + 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _carbsController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Carbs (g)',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1 + 4),
                      Expanded(
                        child: TextField(
                          controller: _fatController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Fat (g)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (scan != null) ...[
                    if (widget.dayTargetCalories != null &&
                        widget.dayTargetCalories! > 0) ...[
                      const SizedBox(height: AppSpacing.x2),
                      MealScanTargetCompare(
                        targetCalories: widget.dayTargetCalories!,
                        consumedBeforeCalories: widget.dayConsumedCalories ?? 0,
                        mealCalories:
                            double.tryParse(
                              _caloriesController.text.trim().replaceAll(
                                ',',
                                '.',
                              ),
                            ) ??
                            0,
                        onAdjustPortion: scan.items.isNotEmpty
                            ? _scrollToItems
                            : null,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.x1 + 4),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _confidenceLabel(scan.confidence),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: scan.confidence.clamp(0, 1),
                                  minHeight: 6,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.x1 + 4),
                        Text(
                          '${(scan.confidence * 100).round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (scan.items.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x1 + 4),
                      Text(
                        'Items',
                        key: _itemsSectionKey,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Edit grams or remove items — the total updates as you go.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      MealScanPlateDraft(
                        key: ValueKey(identityHashCode(scan)),
                        items: scan.items,
                        onChanged: (items) {
                          _editedItems = items;
                          _syncTotalsFromEditedItems();
                        },
                      ),
                    ],
                    if (scan.assumptions.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        'Assumptions: ${scan.assumptions.join(' • ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.x2),
                  FilledButton(
                    onPressed: () {
                      final out = _buildResult(primaryAction);
                      if (out == null) return;
                      context.pop(out);
                    },
                    child: Text(primaryLabel),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  OutlinedButton(
                    onPressed: () {
                      final out = _buildResult(secondaryAction);
                      if (out == null) return;
                      context.pop(out);
                    },
                    child: Text(secondaryLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // A full-screen Dialog isn't a pushed route, so it has no iOS interactive
    // back-swipe. Add a left-edge swipe-to-dismiss so the scan screen can be
    // dismissed with the edge gesture like every other full-screen screen.
    return Stack(
      children: [
        dialog,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 250 && context.mounted) {
                context.pop();
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Elevated, tappable hero for the dominant camera-capture path. The card is
/// the tap target (single elevation), with a brand-blue icon/label and a press
/// scale + shadow lift. Goes non-interactive while a scan is in flight.
class _HeroCaptureCard extends StatefulWidget {
  const _HeroCaptureCard({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_HeroCaptureCard> createState() => _HeroCaptureCardState();
}

class _HeroCaptureCardState extends State<_HeroCaptureCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _pressed = false)
          : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: AppMotion.fast,
        curve: AppMotion.enterCurve,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.enterCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              _pressed
                  ? AppShadows.medium(context)
                  : AppShadows.subtle(context),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_camera_outlined, size: 56, color: cs.primary),
              const SizedBox(height: AppSpacing.x2),
              Text(
                'Take a photo',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Frame your meal — we’ll estimate calories + macros',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
