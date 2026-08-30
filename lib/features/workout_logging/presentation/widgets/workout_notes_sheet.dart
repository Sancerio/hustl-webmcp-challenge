import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';

class WorkoutNotesSheet extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onSave;
  final VoidCallback onClose;

  const WorkoutNotesSheet({
    super.key,
    required this.initialText,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<WorkoutNotesSheet> createState() => _WorkoutNotesSheetState();
}

class _WorkoutNotesSheetState extends State<WorkoutNotesSheet> {
  late final TextEditingController _controller;
  late String _original;
  final _suggestions = const [
    'Felt strong today',
    'Form focus set',
    'Shorter rest helped',
    'Try heavier next time',
  ];

  @override
  void initState() {
    super.initState();
    _original = widget.initialText;
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _changed => _controller.text != _original;

  void _insertSuggestion(String suggestion) {
    Haptics.selection();
    final text = _controller.text;
    _controller.text = text.isEmpty ? suggestion : '$text\n$suggestion';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final charCount = _controller.text.trim().length;
    final hasText = _controller.text.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.x3,
          right: AppSpacing.x3,
          top: AppSpacing.x1 + 2,
          bottom: mediaQuery.viewInsets.bottom + AppSpacing.x2,
        ),
        child: ResponsiveCenter(
          maxContentWidth: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: AppRadius.pillRadius,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              // --- Header: icon chip + title + helper, close affordance ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: AppRadius.controlRadius,
                    ),
                    child: Icon(
                      Icons.edit_note_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1 + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workout notes',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Capture how it went — optional.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x2),
              // --- Notes field: on-theme fill, crisp focus state ---
              TextField(
                controller: _controller,
                maxLines: null,
                minLines: 5,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyMedium,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Add any notes for this workout…',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2,
                    vertical: AppSpacing.x1 + 4,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: AppRadius.cardRadius,
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.cardRadius,
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.cardRadius,
                    borderSide: BorderSide(color: colors.primary, width: 1.5),
                  ),
                  suffixIcon: hasText
                      ? IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                          icon: Icon(
                            Icons.clear_rounded,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.x1 + 4),
              // --- Quick-add suggestions as polished chips ---
              Text(
                'Quick add',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.x1),
              Wrap(
                spacing: AppSpacing.x1,
                runSpacing: AppSpacing.x1,
                children: [
                  for (final suggestion in _suggestions)
                    _SuggestionChip(
                      label: suggestion,
                      onTap: () => _insertSuggestion(suggestion),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.x1 + 4),
              // --- Save-state affordance: char count + up-to-date status ---
              Row(
                children: [
                  Text(
                    charCount == 1 ? '1 char' : '$charCount chars',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: _changed
                        ? Row(
                            key: const ValueKey('notes-unsaved'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Unsaved changes',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            key: const ValueKey('notes-saved'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Up to date',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x2),
              // --- Primary CTA ---
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('notesSaveButton'),
                  onPressed: _changed
                      ? () {
                          Haptics.confirm();
                          widget.onSave(_controller.text);
                        }
                      : null,
                  child: const Text('Save notes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A polished, tappable quick-add chip. Inserts its label into the notes field
/// on tap — a focused affordance, not a selectable filter chip.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x1 + 4,
            vertical: AppSpacing.x1 - 2,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: AppRadius.pillRadius,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: colors.primary),
              const SizedBox(width: 4),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
