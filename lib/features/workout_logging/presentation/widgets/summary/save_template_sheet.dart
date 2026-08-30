import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import '../../../../workout_templates/domain/models/workout_template.dart';

/// Result of the save-template sheet. When [template] is null the user chose to
/// create a new template named [name]; otherwise they chose to update it.
class SaveTemplateChoice {
  const SaveTemplateChoice({required this.name, this.template});

  final String name;
  final WorkoutTemplate? template;
}

/// Bottom sheet for saving the finished workout as a template (create new or
/// update existing). Extracted from the summary screen to keep that file small.
Future<SaveTemplateChoice?> showSaveTemplateSheet(
  BuildContext context, {
  required String defaultName,
  required List<WorkoutTemplate> existingTemplates,
}) {
  return showModalBottomSheet<SaveTemplateChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _SaveTemplateSheet(
        defaultName: defaultName,
        existingTemplates: existingTemplates,
      ),
    ),
  );
}

class _SaveTemplateSheet extends StatefulWidget {
  const _SaveTemplateSheet({
    required this.defaultName,
    required this.existingTemplates,
  });

  final String defaultName;
  final List<WorkoutTemplate> existingTemplates;

  @override
  State<_SaveTemplateSheet> createState() => _SaveTemplateSheetState();
}

class _SaveTemplateSheetState extends State<_SaveTemplateSheet> {
  late String _name = widget.defaultName;
  WorkoutTemplate? _selected;

  bool get _creatingNew => _selected == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasExisting = widget.existingTemplates.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Save workout', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.x2),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: true, label: Text('Create new')),
                ButtonSegment(
                  value: false,
                  label: const Text('Update'),
                  enabled: hasExisting,
                ),
              ],
              selected: {_creatingNew},
              onSelectionChanged: (selection) {
                setState(() {
                  if (selection.first) {
                    _selected = null;
                  } else if (hasExisting) {
                    _selected = widget.existingTemplates.first;
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.x2),
            if (_creatingNew)
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(
                  labelText: 'Template name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _name = value,
              )
            else
              DropdownButtonFormField<WorkoutTemplate>(
                initialValue: _selected,
                decoration: const InputDecoration(
                  labelText: 'Select template',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in widget.existingTemplates)
                    DropdownMenuItem(value: t, child: Text(t.name)),
                ],
                onChanged: (t) => setState(() => _selected = t),
              ),
            const SizedBox(height: AppSpacing.x3),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (_creatingNew && _name.trim().isEmpty) return;
                  context.pop(
                    SaveTemplateChoice(name: _name.trim(), template: _selected),
                  );
                },
                child: Text(_creatingNew ? 'Save template' : 'Update template'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
