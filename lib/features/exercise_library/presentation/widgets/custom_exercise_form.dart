import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/exercise.dart';
import '../../domain/repositories/exercise_repository.dart';
import '../../domain/services/exercise_library_filters.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../core/services/token_storage.dart';

Future<Exercise?> showCustomExerciseForm(
  BuildContext context, {
  Exercise? initial,
}) {
  return showModalBottomSheet<Exercise?>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, controller) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _CustomExerciseFormBody(
            initial: initial,
            scrollController: controller,
          ),
        ),
      ),
    ),
  );
}

class _CustomExerciseFormBody extends StatefulWidget {
  final Exercise? initial;
  final ScrollController? scrollController;
  const _CustomExerciseFormBody({this.initial, this.scrollController});

  @override
  State<_CustomExerciseFormBody> createState() =>
      _CustomExerciseFormBodyState();
}

class _CustomExerciseFormBodyState extends State<_CustomExerciseFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  bool _saving = false;
  final List<String> _muscles = <String>[];
  ExerciseLoggingMode _loggingMode = ExerciseLoggingMode.weightReps;
  ExerciseVisibility _visibility = ExerciseVisibility.private;
  bool _canShare = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCanShare();
    final initial = widget.initial;
    if (initial != null) {
      _nameCtrl.text = initial.name;
      if (initial.description != null) {
        _descriptionCtrl.text = initial.description!;
      }
      _muscles
        ..clear()
        ..addAll(initial.muscles);
      _loggingMode = initial.loggingMode;
      _visibility = initial.visibility == ExerciseVisibility.catalog
          ? ExerciseVisibility.private
          : initial.visibility;
    }
  }

  Future<void> _loadCanShare() async {
    try {
      if (!GetIt.I.isRegistered<TokenStorage>()) return;
      final token = await GetIt.I<TokenStorage>().getAccessToken();
      if (!mounted) return;
      setState(() => _canShare = token != null && token.isNotEmpty);
    } catch (_) {
      if (!mounted) return;
      setState(() => _canShare = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 8,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing
                            ? 'Edit Custom Exercise'
                            : 'Create Custom Exercise',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Saved to My Exercises',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: _saving
                      ? null
                      : () {
                          if (context.canPop()) context.pop();
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                  controller: widget.scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    _SectionCard(
                      title: 'Basics',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _nameCtrl,
                            enabled: !_saving,
                            autofocus: !isEditing,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                              hintText: 'e.g., Barbell Squat',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          _buildLoggingModeField(context),
                        ],
                      ),
                    ),
                    _SectionCard(
                      title: 'Sharing',
                      child: _buildVisibilitySection(context),
                    ),
                    _SectionCard(
                      title: 'Target Muscles',
                      child: _buildMusclePickerSection(context),
                    ),
                    _SectionCard(
                      title: 'Notes',
                      child: TextFormField(
                        controller: _descriptionCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Setup cues, variations, or anything else…',
                        ),
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            ValueListenableBuilder(
              valueListenable: _nameCtrl,
              builder: (context, _, __) {
                final canSave = !_saving && _nameCtrl.text.trim().isNotEmpty;
                return FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  onPressed: canSave ? _onSave : null,
                  label: Text(isEditing ? 'Save changes' : 'Save'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = GetIt.I.isRegistered<ExerciseRepository>()
          ? GetIt.I<ExerciseRepository>()
          : null;
      const uuid = Uuid();
      final name = _nameCtrl.text.trim();
      final muscles = _muscles.isEmpty
          ? const ['Custom']
          : List<String>.from(_muscles);
      final isEditing = widget.initial != null;
      final vis = _canShare
          ? _visibility
          : (isEditing
                ? (widget.initial!.visibility == ExerciseVisibility.catalog
                      ? ExerciseVisibility.private
                      : widget.initial!.visibility)
                : ExerciseVisibility.private);
      // For legacy customs without id, delete the pre-edit entry by name and assign a new id
      if (repo != null &&
          isEditing &&
          (widget.initial!.id == null || widget.initial!.id!.isEmpty)) {
        await repo.removeCustomExercise(widget.initial!);
      }
      final assignedId = isEditing
          ? (widget.initial!.id ?? uuid.v4())
          : uuid.v4();
      final exercise = Exercise(
        id: assignedId,
        slug: isEditing ? widget.initial!.slug : null,
        name: name,
        muscles: muscles,
        imageUrl: isEditing ? widget.initial!.imageUrl : null,
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        equipment: isEditing ? widget.initial!.equipment : const [],
        difficulty: isEditing ? widget.initial!.difficulty : null,
        videoUrl: isEditing ? widget.initial!.videoUrl : null,
        tags: isEditing ? widget.initial!.tags : const [],
        isFavorite: isEditing ? widget.initial!.isFavorite : false,
        kind: isEditing ? widget.initial!.kind : ExerciseKind.strength,
        loggingMode: _loggingMode,
        visibility: vis,
      );
      final saved = repo != null
          ? await repo.addCustomExercise(exercise)
          : exercise;
      if (!mounted) return;
      context.pop<Exercise?>(saved);
    } catch (e, s) {
      dev.log(
        'Failed to save custom exercise',
        name: 'CustomExerciseForm',
        error: e,
        stackTrace: s,
      );
      if (mounted) {
        HustlSnack.show(
          context,
          'We couldn\'t save this exercise. Please try again.',
          variant: HustlSnackVariant.error,
        );
      }
      // Do NOT pop: keep the sheet open so the user can retry without
      // re-entering everything.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildVisibilitySection(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _canShare && !_saving;
    final effective = _visibility == ExerciseVisibility.public
        ? ExerciseVisibility.public
        : ExerciseVisibility.private;
    final helper = !_canShare
        ? 'Sign in to share exercises.'
        : (effective == ExerciseVisibility.public
              ? 'Visible to signed-in users in Shared Exercises.'
              : 'Only you can see it.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ExerciseVisibility>(
          segments: const [
            ButtonSegment(
              value: ExerciseVisibility.private,
              label: Text('Private'),
              icon: Icon(Icons.lock_outline),
            ),
            ButtonSegment(
              value: ExerciseVisibility.public,
              label: Text('Public'),
              icon: Icon(Icons.public),
            ),
          ],
          selected: {effective},
          showSelectedIcon: false,
          onSelectionChanged: enabled
              ? (selection) {
                  final next = selection.first;
                  setState(() => _visibility = next);
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLoggingModeField(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ExerciseLoggingMode>(
          initialValue: _loggingMode,
          onChanged: _saving
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() => _loggingMode = v);
                },
          items: const [
            DropdownMenuItem(
              value: ExerciseLoggingMode.weightReps,
              child: Text('Weight × Reps'),
            ),
            DropdownMenuItem(
              value: ExerciseLoggingMode.distanceDuration,
              child: Text('Distance × Duration'),
            ),
            DropdownMenuItem(
              value: ExerciseLoggingMode.durationOnly,
              child: Text('Duration Only'),
            ),
          ],
          decoration: const InputDecoration(
            labelText: 'Logging mode',
            hintText: 'Select how sets are logged',
          ),
        ),
        const SizedBox(height: 6),
        Text(switch (_loggingMode) {
          ExerciseLoggingMode.weightReps => 'Logs: kg × reps (default)',
          ExerciseLoggingMode.distanceDuration => 'Logs: km × time',
          ExerciseLoggingMode.durationOnly => 'Logs: time only',
        }, style: theme.textTheme.bodySmall),
      ],
    );
  }

  // UI: Muscles chip picker section
  Widget _buildMusclePickerSection(BuildContext context) {
    final theme = Theme.of(context);
    final hasMuscles = _muscles.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_muscles.isEmpty)
          Text(
            'Optional — add one or more muscles',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (_muscles.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _muscles
                .map(
                  (m) => Chip(
                    label: Text(m),
                    onDeleted: _saving
                        ? null
                        : () => setState(() => _muscles.remove(m)),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: Icon(hasMuscles ? Icons.tune : Icons.add),
            label: Text(hasMuscles ? 'Edit muscles' : 'Add muscles'),
            onPressed: _saving
                ? null
                : () async {
                    final picked = await _openMusclePicker(
                      context,
                      selected: _muscles,
                      options: exerciseLibraryMuscleGroupOptions,
                    );
                    if (picked != null) {
                      setState(() {
                        _muscles
                          ..clear()
                          ..addAll(picked);
                      });
                    }
                  },
          ),
        ),
      ],
    );
  }

  Future<List<String>?> _openMusclePicker(
    BuildContext context, {
    required List<String> selected,
    required List<String> options,
  }) async {
    final Set<String> temp = {...selected};
    final controller = TextEditingController();
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (ctx, scroll) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pick Muscles',
                            style: Theme.of(ctx).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed: () {
                            if (ctx.canPop()) ctx.pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scroll,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: options.map((opt) {
                            final isSel = temp.contains(opt);
                            return FilterChip(
                              label: Text(opt),
                              selected: isSel,
                              onSelected: (s) {
                                if (s) {
                                  temp.add(opt);
                                } else {
                                  temp.remove(opt);
                                }
                                // Force rebuild
                                (ctx as Element).markNeedsBuild();
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              labelText: 'Add custom muscle',
                            ),
                            onSubmitted: (v) {
                              final val = v.trim();
                              if (val.isNotEmpty) {
                                temp.add(_titleCase(val));
                                controller.clear();
                                (ctx as Element).markNeedsBuild();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            final val = controller.text.trim();
                            if (val.isNotEmpty) {
                              temp.add(_titleCase(val));
                              controller.clear();
                              (ctx as Element).markNeedsBuild();
                            }
                          },
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        ctx.pop<List<String>>(temp.toList()..sort());
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          final lower = w.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
