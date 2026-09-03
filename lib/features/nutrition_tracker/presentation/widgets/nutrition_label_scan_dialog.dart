import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/services/nutrition_label_ocr_service.dart';
import '../../domain/models/food.dart';
import '../../domain/models/food_log_entry.dart';
import '../../domain/repositories/food_repository.dart';
import '../../domain/services/nutrition_label_parser.dart';

class NutritionLabelScanDialog extends StatefulWidget {
  const NutritionLabelScanDialog({
    super.key,
    required this.date,
    this.defaultLoggedAt,
  });

  final DateTime date;
  final DateTime? defaultLoggedAt;

  @override
  State<NutritionLabelScanDialog> createState() =>
      _NutritionLabelScanDialogState();
}

class _NutritionLabelScanDialogState extends State<NutritionLabelScanDialog> {
  final _imagePicker = ImagePicker();
  final _ocr = NutritionLabelOcrService();

  Uint8List? _imageBytes;
  NutritionLabelParseResult? _parsed;
  bool _isBusy = false;

  final _nameController = TextEditingController();
  final _amountGramsController = TextEditingController();
  final _servingsController = TextEditingController();
  final _servingGramsController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();

  bool _valuesPer100g = false;
  bool _saveAsCustomFood = true;

  @override
  void dispose() {
    _nameController.dispose();
    _amountGramsController.dispose();
    _servingsController.dispose();
    _servingGramsController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _ocr.dispose();
    super.dispose();
  }

  String _formatNumber(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.01) return rounded.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  void _seedControllersFromParseResult(NutritionLabelParseResult result) {
    _valuesPer100g = result.valuesPer100g;
    _nameController.text = (result.productName ?? 'Label scan').trim();
    _servingGramsController.text = result.servingSizeGrams == null
        ? ''
        : result.servingSizeGrams!.toStringAsFixed(0);
    _caloriesController.text = result.caloriesKcal == null
        ? ''
        : result.caloriesKcal!.toStringAsFixed(0);
    _proteinController.text = result.proteinGrams == null
        ? ''
        : result.proteinGrams!.toStringAsFixed(0);
    _carbsController.text = result.carbsGrams == null
        ? ''
        : result.carbsGrams!.toStringAsFixed(0);
    _fatController.text = result.fatGrams == null
        ? ''
        : result.fatGrams!.toStringAsFixed(0);

    final defaultAmount = result.valuesPer100g
        ? 100
        : (result.servingSizeGrams?.round() ?? 0);
    _amountGramsController.text = defaultAmount > 0 ? '$defaultAmount' : '';
    _servingsController.text =
        !_valuesPer100g && result.servingSizeGrams != null ? '1' : '';
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isBusy) return;
    if (kIsWeb) {
      HustlSnack.show(
        context,
        'Label scan isn\'t available on web yet.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _parsed = null;
    });

    try {
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (!mounted) return;
      if (file == null) {
        setState(() => _isBusy = false);
        return;
      }

      final bytes = await file.readAsBytes();
      final rawText = await _ocr.recognizeTextFromPath(file.path);
      final parsed = parseNutritionLabelText(rawText);

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _parsed = parsed;
        _isBusy = false;
      });
      _seedControllersFromParseResult(parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      HustlSnack.show(
        context,
        'Couldn’t read the label. Try a clearer photo with the full '
        'nutrition label visible.',
        variant: HustlSnackVariant.warning,
      );
    }
  }

  double? _tryParsePositive(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    return value;
  }

  void _syncAmountFromServings() {
    if (_valuesPer100g) return;
    final servingSizeGrams = _tryParsePositive(_servingGramsController);
    final servings = _tryParsePositive(_servingsController);
    if (servingSizeGrams == null || servings == null) return;
    _amountGramsController.text = _formatNumber(servingSizeGrams * servings);
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim().isEmpty
        ? 'Label scan'
        : _nameController.text.trim();
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

    final amountGrams = _tryParsePositive(_amountGramsController);
    if (amountGrams == null) {
      HustlSnack.show(
        context,
        'Enter an amount (g) to log.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }

    final caloriesBasis = _tryParsePositive(_caloriesController) ?? 0;
    final proteinBasis = _tryParsePositive(_proteinController) ?? 0;
    final carbsBasis = _tryParsePositive(_carbsController) ?? 0;
    final fatBasis = _tryParsePositive(_fatController) ?? 0;

    final servingSizeGrams = _valuesPer100g
        ? null
        : _tryParsePositive(_servingGramsController);
    final basisGrams = _valuesPer100g ? 100.0 : servingSizeGrams;

    double? caloriesPer100g;
    double? proteinPer100g;
    double? carbsPer100g;
    double? fatPer100g;

    final shouldComputePer100g =
        _saveAsCustomFood && basisGrams != null && basisGrams > 0;
    if (shouldComputePer100g) {
      final basis = basisGrams;
      caloriesPer100g = caloriesBasis / basis * 100;
      proteinPer100g = proteinBasis / basis * 100;
      carbsPer100g = carbsBasis / basis * 100;
      fatPer100g = fatBasis / basis * 100;
    }

    final canCreateCustomFood =
        caloriesPer100g != null &&
        proteinPer100g != null &&
        carbsPer100g != null &&
        fatPer100g != null;

    final totalCalories =
        (canCreateCustomFood
                ? caloriesPer100g * (amountGrams / 100)
                : (basisGrams == null || basisGrams <= 0)
                ? caloriesBasis
                : caloriesBasis * (amountGrams / basisGrams))
            .clamp(0, double.infinity)
            .toDouble();
    final totalProtein =
        (canCreateCustomFood
                ? proteinPer100g * (amountGrams / 100)
                : (basisGrams == null || basisGrams <= 0)
                ? proteinBasis
                : proteinBasis * (amountGrams / basisGrams))
            .clamp(0, double.infinity)
            .toDouble();
    final totalCarbs =
        (canCreateCustomFood
                ? carbsPer100g * (amountGrams / 100)
                : (basisGrams == null || basisGrams <= 0)
                ? carbsBasis
                : carbsBasis * (amountGrams / basisGrams))
            .clamp(0, double.infinity)
            .toDouble();
    final totalFat =
        (canCreateCustomFood
                ? fatPer100g * (amountGrams / 100)
                : (basisGrams == null || basisGrams <= 0)
                ? fatBasis
                : fatBasis * (amountGrams / basisGrams))
            .clamp(0, double.infinity)
            .toDouble();

    if (_isBusy) return;

    if (!canCreateCustomFood) {
      context.pop(
        FoodLogEntry(
          id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
          date: widget.date,
          loggedAt: loggedAt,
          servingGrams: amountGrams,
          calories: totalCalories,
          proteinGrams: totalProtein,
          carbsGrams: totalCarbs,
          fatGrams: totalFat,
          foodName: name,
          source: 'label_scan',
        ),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      final repo = GetIt.instance<FoodRepository>();
      final created = await repo.createCustomFood(
        Food(
          id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          source: 'custom',
          servingSizeGrams: servingSizeGrams ?? 100,
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: proteinPer100g,
          carbsPer100g: carbsPer100g,
          fatPer100g: fatPer100g,
          completeness: 1,
        ),
      );

      if (!mounted) return;
      setState(() => _isBusy = false);
      context.pop(
        FoodLogEntry(
          id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
          date: widget.date,
          loggedAt: loggedAt,
          servingGrams: amountGrams,
          calories: (created.caloriesPer100g ?? 0) * (amountGrams / 100),
          proteinGrams: (created.proteinPer100g ?? 0) * (amountGrams / 100),
          carbsGrams: (created.carbsPer100g ?? 0) * (amountGrams / 100),
          fatGrams: (created.fatPer100g ?? 0) * (amountGrams / 100),
          food: created,
          foodName: created.name,
          source: 'label_scan',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      HustlSnack.show(
        context,
        'Couldn’t save that food. Logging it as a manual entry.',
        variant: HustlSnackVariant.warning,
      );
      context.pop(
        FoodLogEntry(
          id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
          date: widget.date,
          loggedAt: loggedAt,
          servingGrams: amountGrams,
          calories: totalCalories,
          proteinGrams: totalProtein,
          carbsGrams: totalCarbs,
          fatGrams: totalFat,
          foodName: name,
          source: 'label_scan',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan label'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _isBusy ? null : () => context.pop(),
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
        body: SafeArea(
          child: _isBusy
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Take a clear photo of the Nutrition Facts panel. We’ll extract calories + macros, and you can adjust anything before logging.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Take photo'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose photo'),
                      ),
                      if (_parsed != null) ...[
                        const SizedBox(height: 20),
                        if (_imageBytes != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.cover,
                              height: 220,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Food name',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _valuesPer100g,
                          onChanged: (v) {
                            setState(() {
                              _valuesPer100g = v;
                              if (v) _servingGramsController.text = '';
                              if (v) _servingsController.text = '';
                              if (_amountGramsController.text.trim().isEmpty) {
                                _amountGramsController.text = v ? '100' : '';
                              }
                              if (!v &&
                                  _servingsController.text.trim().isEmpty &&
                                  _tryParsePositive(_servingGramsController) !=
                                      null) {
                                _servingsController.text = '1';
                                _syncAmountFromServings();
                              }
                            });
                          },
                          title: const Text('Values are per 100g'),
                          subtitle: const Text(
                            'Turn on if the label shows “per 100g”',
                          ),
                        ),
                        if (!_valuesPer100g) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _servingGramsController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Serving size (g)',
                            ),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) {
                              if (_servingsController.text.trim().isEmpty &&
                                  _amountGramsController.text.trim().isEmpty &&
                                  _tryParsePositive(_servingGramsController) !=
                                      null) {
                                _servingsController.text = '1';
                              }
                              _syncAmountFromServings();
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_valuesPer100g)
                          TextField(
                            controller: _amountGramsController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount to log (g)',
                            ),
                            textInputAction: TextInputAction.next,
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _servingsController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Servings',
                                    hintText: '1',
                                    helperText:
                                        _tryParsePositive(
                                              _servingGramsController,
                                            ) ==
                                            null
                                        ? 'Enter serving size to enable'
                                        : null,
                                  ),
                                  enabled:
                                      _tryParsePositive(
                                        _servingGramsController,
                                      ) !=
                                      null,
                                  textInputAction: TextInputAction.next,
                                  onChanged: (_) => _syncAmountFromServings(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _amountGramsController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Amount to log (g)',
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _caloriesController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: _valuesPer100g
                                      ? 'Calories (per 100g)'
                                      : 'Calories (per serving)',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _proteinController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: _valuesPer100g
                                      ? 'Protein (g/100g)'
                                      : 'Protein (g/serving)',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _carbsController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: _valuesPer100g
                                      ? 'Carbs (g/100g)'
                                      : 'Carbs (g/serving)',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _fatController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: _valuesPer100g
                                      ? 'Fat (g/100g)'
                                      : 'Fat (g/serving)',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _saveAsCustomFood,
                          onChanged: (v) =>
                              setState(() => _saveAsCustomFood = v),
                          title: const Text('Save as custom food'),
                          subtitle: const Text(
                            'Lets you adjust grams later without retyping',
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _submit,
                          child: const Text('Add to plate'),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
