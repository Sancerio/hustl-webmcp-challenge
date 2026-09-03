import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_log/domain/utils/muscle_group_mapper.dart';
import '../../data/services/template_sync_service.dart';
import '../../domain/models/workout_template.dart';
import '../../domain/repositories/template_repository.dart';
import '../widgets/template_region.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import '../widgets/template_card.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({
    super.key,
    @visibleForTesting this.reflectDetailRouteInBrowser,
  });

  /// Overrides the web-only location transfer in widget tests.
  ///
  /// Production callers leave this unset so Flutter web uses route-replacing
  /// navigation while native platforms retain their pushed detail stack.
  final bool? reflectDetailRouteInBrowser;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final _templateRepository = GetIt.instance<TemplateRepository>();
  TemplateSyncService? get _syncService =>
      GetIt.I.isRegistered<TemplateSyncService>()
      ? GetIt.I<TemplateSyncService>()
      : null;
  List<WorkoutTemplate> _templates = [];

  /// Most-trained muscle group per template id, used to tint the leading holder.
  /// Resolved from each template's exercises; empty until loaded.
  Map<String, TemplateRegion> _regionByTemplateId = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates(syncRemote: true);
  }

  Future<void> _loadTemplates({bool syncRemote = false}) async {
    setState(() => _loading = true);
    try {
      if (syncRemote && _syncService != null) {
        try {
          await _syncService!.syncNow();
        } catch (_) {
          // Fall back to local state below.
        }
      }
      final local = await _templateRepository.getWorkoutTemplates();
      if (!mounted) return;
      setState(() {
        _templates = local;
        _loading = false;
      });
      // Region tints are best-effort decoration — resolve them off the critical
      // path so a slow or failing exercise catalog never holds back the user's
      // already-loaded templates. The holders show the neutral tint until ready.
      unawaited(_loadRegions(local));
    } catch (e, s) {
      dev.log(
        'Failed to load templates',
        name: 'TemplatesScreen',
        error: e,
        stackTrace: s,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      HustlSnack.show(
        context,
        'We couldn\'t load your templates. Pull to refresh or try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  /// Resolves region tints in the background and folds them in once ready, so
  /// the template list never waits on the (possibly networked) exercise catalog.
  /// Always replaces the map — including with an empty one — so tints fall back
  /// to neutral when a reload no longer resolves any regions.
  Future<void> _loadRegions(List<WorkoutTemplate> templates) async {
    final regions = await _resolveTemplateRegions(templates);
    if (!mounted) return;
    setState(() => _regionByTemplateId = regions);
  }

  /// Resolves each template's most-trained muscle group from its exercises so the
  /// leading holder can be tinted. Best-effort: matches each `exerciseId`
  /// (stored as the exercise name) against the catalog, folds the muscles into
  /// figure groups, then picks the most-trained muscle group. Returns an empty map (→
  /// neutral tint) if the exercise catalog isn't available or on any error.
  Future<Map<String, TemplateRegion>> _resolveTemplateRegions(
    List<WorkoutTemplate> templates,
  ) async {
    if (!GetIt.I.isRegistered<ExerciseRepository>()) return const {};
    try {
      final all = await GetIt.I<ExerciseRepository>().getAllExercises();
      final musclesByName = <String, List<String>>{
        for (final e in all) e.name.trim().toLowerCase(): e.muscles,
      };
      final result = <String, TemplateRegion>{};
      for (final t in templates) {
        final labels = <String>[];
        for (final e in t.exercises) {
          final name = (e['exerciseId'] as String?)?.trim().toLowerCase();
          if (name == null || name.isEmpty) continue;
          final muscles = musclesByName[name];
          if (muscles != null) labels.addAll(muscles);
        }
        final region = dominantTemplateRegion(figureMuscleGroups(labels));
        if (region != null) result[t.id] = region;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _openTemplate(WorkoutTemplate t, {bool edit = false}) async {
    final location = '/templates/${t.id}';
    final extra = {'startInEditMode': edit};
    if (widget.reflectDetailRouteInBrowser ?? kIsWeb) {
      // GoRouter intentionally leaves imperative pushes out of the browser URL
      // by default. WebMCP ownership is route-derived, so transfer the visible
      // detail to its canonical browser location instead of leaving /templates
      // in the address bar while a different template owns the screen.
      context.go(location, extra: extra);
      return;
    }
    await context.push(location, extra: extra);
    if (!mounted) return;
    await _loadTemplates();
  }

  Future<void> _deleteTemplate(WorkoutTemplate t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Are you sure you want to delete "${t.name}"?'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _templateRepository.deleteWorkoutTemplate(t.id);
      try {
        await _syncService?.syncNow();
      } catch (_) {}
      await _loadTemplates();
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Template deleted.',
        variant: HustlSnackVariant.success,
      );
    } catch (e, s) {
      dev.log(
        'Failed to delete template',
        name: 'TemplatesScreen',
        error: e,
        stackTrace: s,
      );
      if (!mounted) return;
      HustlSnack.show(
        context,
        'We couldn\'t delete that template. Please try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  void _startFromTemplate(WorkoutTemplate t) {
    final extra = {
      'initialName': t.name,
      // Pass the template's stored prescription sets with provenance so the
      // active workout can keep "Previous" tied to actual session history.
      'initialExercises': t.exercises
          .map(
            (e) => {
              'name': e['exerciseId'] as String? ?? '',
              'sets': (e['sets'] as int?) ?? 1,
              'rest': e['restTimerSeconds'] as int?,
              'previousSets': e['previousSets'] as List<dynamic>?,
              'previousSetsAreTemplateTargets': true,
              // Provenance: template prescription targets are separate from
              // true previous-session history.
              'targetsArePlaceholder': e['targetsArePlaceholder'] == true,
            },
          )
          .toList(),
    };
    context.go('/workout_session', extra: workoutRouteExtra(context, extra));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Templates'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      child: _loading
          ? const HustlInlineSkeleton()
          : _templates.isEmpty
          ? ScreenEmptyState(
              icon: Icons.fitness_center,
              assetIcon: 'assets/icons/empty_workout.svg',
              title: 'Build your first routine',
              message:
                  'Save a workout as a template and it lands here, ready to '
                  'start with one tap. Begin a session, then save it from the '
                  'summary screen.',
              actionLabel: 'Start a workout',
              onAction: () => context.go('/'),
            )
          : RefreshIndicator(
              onRefresh: () => _loadTemplates(syncRemote: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x2,
                  AppSpacing.x2,
                  AppSpacing.x2,
                  AppSpacing.x4,
                ),
                children: [
                  StaggeredEntrance(
                    animationKey: 'templates_list',
                    children: [
                      SectionList(
                        card: true,
                        children: [
                          for (final t in _templates)
                            TemplateCard(
                              template: t,
                              region: _regionByTemplateId[t.id],
                              onTap: () => _openTemplate(t),
                              onStart: () => _startFromTemplate(t),
                              onEdit: () => _openTemplate(t, edit: true),
                              onDelete: () => _deleteTemplate(t),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
