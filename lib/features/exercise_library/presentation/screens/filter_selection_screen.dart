import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import '../../domain/services/exercise_library_filters.dart';

const String customExerciseFilterLabel = 'My custom exercises';
const String sharedExerciseFilterLabel = 'Shared exercises';

class FilterSelectionScreen extends StatefulWidget {
  final List<String> initialFilters;
  final List<String> sourceOptions;

  const FilterSelectionScreen({
    super.key,
    this.initialFilters = const [],
    this.sourceOptions = const [customExerciseFilterLabel],
  });

  @override
  State<FilterSelectionScreen> createState() => _FilterSelectionScreenState();
}

class _FilterSelectionScreenState extends State<FilterSelectionScreen> {
  // State for selected filters
  late Set<String> _selectedMuscleGroups;
  late Set<String> _selectedEquipment;
  late Set<String> _selectedDifficulties;
  late Set<String> _selectedTypes;
  late Set<String> _selectedSources;

  @override
  void initState() {
    super.initState();
    _selectedMuscleGroups = widget.initialFilters
        .where((f) => exerciseLibraryMuscleGroupOptions.contains(f))
        .toSet();
    _selectedEquipment = widget.initialFilters
        .where((f) => exerciseLibraryEquipmentOptions.contains(f))
        .toSet();
    _selectedDifficulties = widget.initialFilters
        .where((f) => exerciseLibraryDifficultyOptions.contains(f))
        .toSet();
    _selectedTypes = widget.initialFilters
        .where((f) => exerciseLibraryTypeOptions.contains(f))
        .toSet();
    _selectedSources = widget.initialFilters
        .where((f) => widget.sourceOptions.contains(f))
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filters'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(), // Close without applying
        ),
        actions: [
          TextButton(
            onPressed: () {
              final allSelected = <String>{
                ..._selectedMuscleGroups,
                ..._selectedEquipment,
                ..._selectedDifficulties,
                ..._selectedTypes,
                ..._selectedSources,
              };
              debugPrint('Applying Filters: $allSelected');
              context.pop(allSelected);
            },
            // Use theme color for consistency
            style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
            child: const Text('Apply'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Width capping/centering is handled by the caller's responsive wrap so
      // the AppBar is capped too; keep only the content padding here.
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: <Widget>[
            _buildFilterSection(
              title: 'Muscle group',
              options: exerciseLibraryMuscleGroupOptions,
              selected: _selectedMuscleGroups,
            ),
            _buildFilterSection(
              title: 'Equipment',
              options: exerciseLibraryEquipmentOptions,
              selected: _selectedEquipment,
            ),
            _buildFilterSection(
              title: 'Difficulty',
              options: exerciseLibraryDifficultyOptions,
              selected: _selectedDifficulties,
            ),
            _buildFilterSection(
              title: 'Type',
              options: exerciseLibraryTypeOptions,
              selected: _selectedTypes,
            ),
            _buildFilterSection(
              title: 'Source',
              options: widget.sourceOptions,
              selected: _selectedSources,
              singleSelect: true,
            ),
          ],
        ),
      ),
    );
  }

  // §12.1: flat 12px text chips — selected = blue 10% tint + blue w600 text,
  // unselected = subtle surface fill + muted text. No green tint, no border.
  Widget _buildFilterSection({
    required String title,
    required List<String> options,
    required Set<String> selected,
    bool singleSelect = false,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentElectricBlue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final bool isSelected = selected.contains(option);
              void toggle() {
                setState(() {
                  if (isSelected) {
                    selected.remove(option);
                  } else if (singleSelect) {
                    selected
                      ..clear()
                      ..add(option);
                  } else {
                    selected.add(option);
                  }
                });
              }

              return Semantics(
                button: true,
                selected: isSelected,
                label: option,
                child: InkWell(
                  onTap: toggle,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accent.withValues(alpha: 0.10)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        color: isSelected
                            ? accent
                            : colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 16 / 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
