import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/navigation/route_observer.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/haptics.dart' show Haptics;
import 'package:hustl_app/core/config/api_config.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/features/auth/presentation/widgets/account_sheet.dart'
    show showLoginSheet;
import 'package:hustl_app/core/widgets/responsive_center.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import '../../../workout_log/presentation/widgets/history/staggered_card_entrance.dart';
import '../../../../core/services/preferences_service.dart';
import '../widgets/active_filters_display.dart';
import '../screens/filter_selection_screen.dart';
import '../../domain/services/exercise_library_filters.dart';
import '../../domain/models/exercise.dart';
import '../../domain/repositories/exercise_repository.dart';
import '../../data/datasources/hustl_backend_exercise_api.dart';
import '../../data/datasources/exercise_cache_local_datasource.dart';
import '../../../../core/utils/fuzzy_search_util.dart';
import 'exercise_card.dart' as card_widget;
import '../../../workout_logging/domain/repositories/workout_repository.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/models/workout_exercise.dart';

class _SteerImageInput {
  final String? url;
  final String? dataUrl;
  const _SteerImageInput({this.url, this.dataUrl});
}

class ExerciseListScreenBase extends StatefulWidget {
  final String appBarTitle;
  final void Function(BuildContext context, Exercise exercise) onExerciseTap;
  final bool allowFilters;
  final bool allowSharedExercises;
  final Widget? appBarTrailing;
  final ValueNotifier<int>? refreshSignal;
  final bool showMenuButton;
  final GlobalKey<ScaffoldState>? menuScaffoldKey;

  /// When true, the screen offers a multi-select mode: a toggle in the app bar
  /// lets the lifter pick 2+ exercises and confirm them as a single superset
  /// group via [onMultiSelectConfirm]. Single-tap add stays unchanged.
  final bool allowMultiSelect;

  /// Called with the chosen exercises (in selection order) when the lifter
  /// confirms a multi-select "Superset" action. Only used when
  /// [allowMultiSelect] is true.
  final void Function(BuildContext context, List<Exercise> exercises)?
  onMultiSelectConfirm;

  const ExerciseListScreenBase({
    super.key,
    required this.appBarTitle,
    required this.onExerciseTap,
    this.allowFilters = true,
    this.allowSharedExercises = false,
    this.appBarTrailing,
    this.refreshSignal,
    this.showMenuButton = false,
    this.menuScaffoldKey,
    this.allowMultiSelect = false,
    this.onMultiSelectConfirm,
  });

  @override
  State<ExerciseListScreenBase> createState() => _ExerciseListScreenBaseState();
}

class _ExerciseListScreenBaseState extends State<ExerciseListScreenBase>
    with RouteAware {
  late final ExerciseRepository _exerciseRepository;
  late final WorkoutRepository _workoutRepository;
  late final PreferencesService _prefs;
  List<Exercise> _exercises = [];
  List<Exercise> _filteredExercises = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  final Set<String> _generating = <String>{};
  final Map<String, DateTime?> _lastPerformed = {};
  final Map<String, int> _workoutCounts = {};

  List<String> _activeFilters = [];
  String _searchQuery = '';
  bool _onlyFavorites = false;
  bool _debugMode = false;
  bool _compactList = true;

  // Multi-select (superset) state. Selection is an ordered list of identity
  // keys so the created group keeps the tap order.
  bool _multiSelectMode = false;
  final List<String> _selectedKeys = [];
  // Tracks which exercise keys have had their list entrance animation played
  // so the stagger runs only once per screen build (same pattern as history).
  final Set<String> _staggeredExerciseKeys = {};

  final TextEditingController _searchController = TextEditingController();

  bool get _isSharedMode =>
      widget.allowSharedExercises &&
      _activeFilters.contains(sharedExerciseFilterLabel);

  @override
  void initState() {
    super.initState();
    _exerciseRepository = GetIt.instance<ExerciseRepository>();
    _workoutRepository = GetIt.instance<WorkoutRepository>();
    _prefs = GetIt.I.isRegistered<PreferencesService>()
        ? GetIt.I<PreferencesService>()
        : PreferencesService();
    _reloadForActiveSource();
    _loadDebugMode();
    _loadViewMode();
    widget.refreshSignal?.addListener(_onExternalRefresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modal = ModalRoute.of(context);
    if (modal is PageRoute) {
      routeObserver.subscribe(this, modal);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    try {
      widget.refreshSignal?.removeListener(_onExternalRefresh);
    } catch (_) {}
    try {
      final modal = ModalRoute.of(context);
      if (modal is PageRoute) routeObserver.unsubscribe(this);
    } catch (_) {}
    super.dispose();
  }

  void _onExternalRefresh() {
    _reloadForActiveSource();
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    _reloadForActiveSource();
  }

  Future<List<WorkoutSession>> _safeWorkoutSessions() async {
    try {
      return await _workoutRepository.getWorkoutSessions();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _reloadForActiveSource() async {
    if (_isSharedMode) {
      await _loadSharedExercises();
      return;
    }
    await _loadExercises();
  }

  Future<void> _applyLoadedExercises(List<Exercise> exercises) async {
    final sessions = await _safeWorkoutSessions();
    final usage = _buildUsageStats(sessions);
    _lastPerformed
      ..clear()
      ..addEntries(
        exercises.map((exercise) {
          final key = _identityKeyForExercise(exercise);
          return MapEntry(key, usage.lastPerformed[key]);
        }),
      );
    _workoutCounts
      ..clear()
      ..addEntries(
        exercises.map((exercise) {
          final key = _identityKeyForExercise(exercise);
          return MapEntry(key, usage.counts[key] ?? 0);
        }),
      );
    _sortExercises(exercises);
    if (!mounted) return;
    setState(() {
      _exercises = exercises;
      _isLoading = false;
      _loadFailed = false;
    });
    _applyFilters();
  }

  Future<void> _loadExercises() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final exercises = await _exerciseRepository.getAllExercises();
      await _applyLoadedExercises(exercises);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
      debugPrint('Error loading exercises: $e');
      _showSnack(
        'We couldn\'t load your exercises. Check your connection and try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  Future<void> _loadSharedExercises() async {
    setState(() => _isLoading = true);
    try {
      final exercises = await _exerciseRepository.getSharedExercises();
      await _applyLoadedExercises(exercises);
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading shared exercises: $e');
      final msg = e.toString();
      if (msg.contains('Not authenticated')) {
        _showSignInToShareSnack();
      } else {
        _showSnack(
          'Couldn\'t load shared exercises',
          variant: HustlSnackVariant.error,
        );
      }
    }
  }

  Future<void> _refreshFromBackend() async {
    if (_isSharedMode) {
      try {
        final shared = await _exerciseRepository.getSharedExercises();
        await _applyLoadedExercises(shared);
      } catch (e) {
        debugPrint('Manual shared refresh failed: $e');
        final msg = e.toString();
        if (msg.contains('Not authenticated')) {
          _showSignInToShareSnack();
        } else {
          _showSnack(
            'Couldn\'t refresh shared exercises',
            variant: HustlSnackVariant.error,
          );
        }
      }
      return;
    }

    try {
      final backend = GetIt.I<HustlBackendExerciseApi>();
      final cache = GetIt.I<ExerciseCacheDataSource>();
      final fresh = await backend.listExercises(limit: 1000);
      final filteredFresh = fresh
          .where(
            (e) =>
                e.name.trim().isNotEmpty &&
                e.muscles.any((m) => m.trim().isNotEmpty),
          )
          .toList(growable: false);
      if (filteredFresh.isNotEmpty) {
        await cache.saveAll(filteredFresh);
      }
      final custom = await _exerciseRepository.getCustomExercises();
      final merged = _mergeCustom(filteredFresh, custom);
      final sessions = await _safeWorkoutSessions();
      final usage = _buildUsageStats(sessions);
      _lastPerformed
        ..clear()
        ..addEntries(
          merged.map((exercise) {
            final key = _identityKeyForExercise(exercise);
            return MapEntry(key, usage.lastPerformed[key]);
          }),
        );
      _workoutCounts
        ..clear()
        ..addEntries(
          merged.map((exercise) {
            final key = _identityKeyForExercise(exercise);
            return MapEntry(key, usage.counts[key] ?? 0);
          }),
        );
      _sortExercises(merged);
      if (!mounted) return;
      setState(() {
        _exercises = merged;
        _applyFilters();
      });
    } catch (e) {
      debugPrint('Manual refresh failed: $e');
      _showSnack(
        'Couldn\'t refresh exercises',
        variant: HustlSnackVariant.error,
      );
    }
  }

  void _sortExercises(List<Exercise> list) {
    list.sort((a, b) {
      final da = _lastPerformed[_identityKeyForExercise(a)];
      final db = _lastPerformed[_identityKeyForExercise(b)];
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.muscles.first.compareTo(b.muscles.first);
    });
  }

  List<Exercise> _mergeCustom(List<Exercise> base, List<Exercise> custom) {
    if (custom.isEmpty) return base;
    final Set<String> seen = {};
    final List<Exercise> merged = [];
    for (final e in custom) {
      merged.add(e);
      seen.add(e.name.toLowerCase());
    }
    for (final e in base) {
      if (seen.contains(e.name.toLowerCase())) continue;
      merged.add(e);
    }
    return merged;
  }

  bool _isCustomExercise(Exercise exercise) {
    return exercise.visibility != ExerciseVisibility.catalog;
  }

  Future<void> _loadDebugMode() async {
    try {
      final enabled = await _prefs.getDebugMode();
      if (mounted) setState(() => _debugMode = enabled);
    } catch (_) {}
  }

  Future<void> _loadViewMode() async {
    try {
      final compact = await _prefs.getExerciseListCompact();
      if (!mounted) return;
      setState(() => _compactList = compact);
    } catch (_) {}
  }

  Future<void> _toggleViewMode() async {
    final next = !_compactList;
    setState(() => _compactList = next);
    try {
      await _prefs.setExerciseListCompact(next);
    } catch (_) {}
  }

  Future<void> _toggleFavorites() async {
    Haptics.selection();
    setState(() {
      _onlyFavorites = !_onlyFavorites;
      _applyFilters();
    });
  }

  static const int _maxSteerImageBytes = 5 * 1000 * 1000;

  Future<_SteerImageInput?> _showRegenerateImageDialog() async {
    final urlCtrl = TextEditingController();
    String? pickedName;
    String? pickedDataUrl;

    try {
      return await showDialog<_SteerImageInput>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              Future<void> pickImage() async {
                try {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    withData: true,
                  );
                  if (result == null || result.files.isEmpty) return;
                  final file = result.files.first;
                  final bytes = file.bytes;
                  if (bytes == null || bytes.isEmpty) {
                    _showSnack(
                      'Couldn\'t read that image',
                      variant: HustlSnackVariant.warning,
                    );
                    return;
                  }
                  if (bytes.length > _maxSteerImageBytes) {
                    _showSnack(
                      'That steering image is too large (over 5MB)',
                      variant: HustlSnackVariant.warning,
                    );
                    return;
                  }
                  final ext = (file.extension ?? '').toLowerCase();
                  final mime = switch (ext) {
                    'png' => 'image/png',
                    'jpg' => 'image/jpeg',
                    'jpeg' => 'image/jpeg',
                    'webp' => 'image/webp',
                    _ => 'image/png',
                  };
                  final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
                  setState(() {
                    pickedName = file.name;
                    pickedDataUrl = dataUrl;
                    urlCtrl.text = '';
                  });
                } catch (e) {
                  debugPrint('Failed to pick steering image: $e');
                  _showSnack(
                    'Couldn\'t pick that image',
                    variant: HustlSnackVariant.error,
                  );
                }
              }

              void clearPicked() {
                setState(() {
                  pickedName = null;
                  pickedDataUrl = null;
                });
              }

              return AlertDialog(
                title: const Text('Regenerate image (debug)'),
                content: SizedBox(
                  width: math.min(420.0, MediaQuery.sizeOf(context).width - 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Optionally add a steering image (STYLE_BASE_IMAGE is still applied).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlCtrl,
                        decoration: InputDecoration(
                          labelText: 'Steering image URL (optional)',
                          hintText: 'https://…',
                          suffixIcon: urlCtrl.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () => setState(urlCtrl.clear),
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Clear URL',
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: pickImage,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Choose image'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pickedName ?? 'No file selected',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (pickedDataUrl != null)
                            IconButton(
                              onPressed: clearPicked,
                              icon: const Icon(Icons.close),
                              tooltip: 'Clear image',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => context.pop<_SteerImageInput?>(null),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final url = urlCtrl.text.trim();
                      context.pop(
                        _SteerImageInput(
                          dataUrl: pickedDataUrl,
                          url: pickedDataUrl != null
                              ? null
                              : (url.isEmpty ? null : url),
                        ),
                      );
                    },
                    child: const Text('Generate'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      urlCtrl.dispose();
    }
  }

  Future<void> _onRegenerateImagePressed(Exercise exercise) async {
    final input = await _showRegenerateImageDialog();
    if (!mounted || input == null) return;
    await _regenerateThumbnail(
      exercise,
      steerImageUrl: input.url,
      steerImageDataUrl: input.dataUrl,
    );
  }

  Future<void> _regenerateThumbnail(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async {
    final key = _exerciseKey(exercise);
    setState(() => _generating.add(key));
    try {
      final url = await _exerciseRepository.regenerateThumbnailDebug(
        exercise,
        steerImageUrl: steerImageUrl,
        steerImageDataUrl: steerImageDataUrl,
      );
      if (url == null) return;
      setState(() {
        _exercises = _exercises
            .map((e) => e.name == exercise.name ? e.copyWith(imageUrl: url) : e)
            .toList();
        _filteredExercises = _filteredExercises
            .map((e) => e.name == exercise.name ? e.copyWith(imageUrl: url) : e)
            .toList();
      });
      _showSnack('Image regenerated', variant: HustlSnackVariant.success);
    } catch (e) {
      debugPrint('Failed to regenerate thumbnail: $e');
      final msg = e.toString();
      if (msg.contains('429')) {
        _showSnack(
          'Rate limited. Try again shortly.',
          variant: HustlSnackVariant.warning,
        );
      } else if (msg.contains('no_base_image')) {
        _showSnack(
          'No base image configured. Set STYLE_BASE_IMAGE.',
          variant: HustlSnackVariant.error,
        );
      } else if (msg.contains('invalid_base_image_url')) {
        _showSnack(
          'Invalid STYLE_BASE_IMAGE URL.',
          variant: HustlSnackVariant.error,
        );
      } else if (msg.contains('invalid_steer_image_url')) {
        _showSnack(
          'Invalid steering image URL.',
          variant: HustlSnackVariant.error,
        );
      } else if (msg.contains('invalid_steer_image')) {
        _showSnack('Invalid steering image.', variant: HustlSnackVariant.error);
      } else {
        _showSnack(
          'Couldn\'t regenerate the image',
          variant: HustlSnackVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _generating.remove(key));
    }
  }

  String _identityKeyForExercise(Exercise e) {
    final canonical = e.canonicalKey;
    if (canonical != null && canonical.isNotEmpty) return canonical;
    final id = e.id;
    if (id != null && id.trim().isNotEmpty) return id.trim().toLowerCase();
    final normalized = e.name.trim().toLowerCase();
    return normalized.isNotEmpty ? normalized : e.name;
  }

  String? _identityKeyForWorkoutExercise(WorkoutExercise e) {
    final canonical = Exercise.canonicalKeyFrom(
      name: e.exercise.name,
      slug: e.exercise.slug,
    );
    if (canonical != null && canonical.isNotEmpty) return canonical;
    final normalized = e.exercise.name.trim().toLowerCase();
    return normalized.isNotEmpty ? normalized : null;
  }

  _UsageStats _buildUsageStats(List<WorkoutSession> sessions) {
    final counts = <String, int>{};
    final lastPerformed = <String, DateTime>{};
    final ordered = sessions.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    for (final session in ordered) {
      for (final workoutExercise in session.exercises) {
        final key = _identityKeyForWorkoutExercise(workoutExercise);
        if (key == null) continue;
        final hasCompletedSet = workoutExercise.sets.any((s) => s.isCompleted);
        if (!hasCompletedSet) continue;
        counts.update(key, (value) => value + 1, ifAbsent: () => 1);
        lastPerformed.putIfAbsent(key, () => session.startTime);
      }
    }
    return _UsageStats(counts, lastPerformed);
  }

  DateTime? _lastPerformedFor(Exercise exercise) =>
      _lastPerformed[_identityKeyForExercise(exercise)];

  int _workoutCountFor(Exercise exercise) =>
      _workoutCounts[_identityKeyForExercise(exercise)] ?? 0;

  String _exerciseKey(Exercise e) => (e.id?.isNotEmpty == true
      ? e.id!
      : (e.slug?.isNotEmpty == true ? e.slug! : e.name));

  void _handleExerciseTap(Exercise exercise) {
    if (_multiSelectMode) {
      _toggleSelection(exercise);
      return;
    }
    if (_isSharedMode) {
      context.push('/exercise_detail', extra: exercise);
      return;
    }
    widget.onExerciseTap(context, exercise);
  }

  void _toggleMultiSelectMode() {
    Haptics.selection();
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) _selectedKeys.clear();
    });
  }

  void _toggleSelection(Exercise exercise) {
    final key = _identityKeyForExercise(exercise);
    Haptics.selection();
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  bool _isSelected(Exercise exercise) =>
      _selectedKeys.contains(_identityKeyForExercise(exercise));

  void _confirmMultiSelect() {
    final confirm = widget.onMultiSelectConfirm;
    if (confirm == null || _selectedKeys.length < 2) return;
    // Resolve keys back to exercises in selection order.
    final byKey = <String, Exercise>{};
    for (final e in _exercises) {
      byKey.putIfAbsent(_identityKeyForExercise(e), () => e);
    }
    final chosen = <Exercise>[];
    for (final key in _selectedKeys) {
      final e = byKey[key];
      if (e != null) chosen.add(e);
    }
    if (chosen.length < 2) return;
    confirm(context, chosen);
  }

  Widget _buildAvatar(String? imageUrl, String name, ColorScheme scheme) {
    final borderRadius = BorderRadius.circular(AppRadius.control - 2);
    Widget child;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('assets/')) {
        child = Image.asset(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) =>
              _avatarPlaceholder(name, scheme),
        );
      } else {
        child = CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) =>
              _avatarPlaceholder(name, scheme),
          placeholder: (context, url) =>
              Container(color: scheme.surfaceContainerHighest),
        );
      }
    } else {
      child = _avatarPlaceholder(name, scheme);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: 52, height: 52, child: child),
    );
  }

  Widget _avatarPlaceholder(String name, ColorScheme scheme) {
    final bg = _colorForName(name, scheme);
    final fg = _foregroundFor(bg);
    return Container(
      color: scheme.surface,
      alignment: Alignment.center,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.control - 4),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          _initialsFor(name),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _initialsFor(String name) {
    final cleaned = name
        .replaceAll(RegExp(r"[()\[\]{}]"), ' ')
        .replaceAll(RegExp(r"\s+"), ' ')
        .trim();
    if (cleaned.isEmpty) return '#';
    final parts = cleaned.split(' ');
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2)
          ? p.substring(0, 2).toUpperCase()
          : p.substring(0, 1).toUpperCase();
    }
    final first = parts[0];
    final second = parts[1];
    final i1 = first.isNotEmpty ? first[0] : '';
    final i2 = second.isNotEmpty ? second[0] : '';
    final res = (i1 + i2).toUpperCase();
    return res.isNotEmpty ? res : '#';
  }

  Color _colorForName(String name, ColorScheme scheme) {
    final palette = <Color>[
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surfaceContainerHighest,
    ];
    final idx = name.toLowerCase().hashCode.abs() % palette.length;
    return palette[idx];
  }

  Color _foregroundFor(Color bg) {
    final brightness = ThemeData.estimateBrightnessForColor(bg);
    return brightness == Brightness.dark
        ? AppColors.brandCloudWhite
        : AppColors.brandCarbonBlack.withValues(alpha: 0.87);
  }

  void _showSnack(
    String message, {
    HustlSnackVariant variant = HustlSnackVariant.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    HustlSnack.show(
      context,
      message,
      variant: variant,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: const Duration(seconds: 2),
    );
  }

  // A sign-in nudge with a one-tap path — never name sign-in without offering
  // a way to do it (the dead-end pattern fixed across the app).
  void _showSignInToShareSnack() {
    _showSnack(
      'Sign in to browse shared exercises',
      variant: HustlSnackVariant.warning,
      actionLabel: 'Sign in',
      onAction: () => showLoginSheet(context),
    );
  }

  void _removeFilter(String filterToRemove) {
    final wasShared = _isSharedMode;
    setState(() {
      _activeFilters = _activeFilters
          .where((f) => f != filterToRemove)
          .toList();
    });
    if (wasShared != _isSharedMode) {
      unawaited(_reloadForActiveSource());
      return;
    }
    _applyFilters();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final Set<String> favoriteNames = _prefs.getFavoriteExercises();
    List<Exercise> result = List<Exercise>.from(_exercises);
    if (_searchQuery.isNotEmpty) {
      final List<Map<String, dynamic>> exercisesWithScores = _exercises.map((
        exercise,
      ) {
        final score = FuzzySearchUtil.calculateFuzzyScore<Exercise>(
          exercise,
          _searchQuery,
          (item) => [item.name, item.muscles.join(' ')],
        );
        return {'exercise': exercise, 'score': score};
      }).toList();
      final matches = exercisesWithScores
          .where((item) => item['score'] > 0)
          .toList();
      matches.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
      result = matches.map((match) => match['exercise'] as Exercise).toList();
    }
    if (widget.allowFilters && _activeFilters.isNotEmpty) {
      result = result.where((exercise) {
        return _activeFilters.every((filter) {
          if (filter == customExerciseFilterLabel) {
            return _isCustomExercise(exercise);
          }
          if (filter == sharedExerciseFilterLabel) {
            return true;
          }
          return matchesExerciseLibraryFilter(exercise, filter);
        });
      }).toList();
    }
    if (_onlyFavorites) {
      result = result
          .where((exercise) => favoriteNames.contains(exercise.name))
          .toList();
    }
    if (_searchQuery.isEmpty) {
      _sortExercises(result);
    }
    setState(() => _filteredExercises = result);
  }

  // --- Search bar widget (sliver-header style) ---
  Widget _buildSearchHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x1,
        AppSpacing.x2,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search + favorites + filter row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Search exercises…',
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: colors.onSurfaceVariant,
                      size: 22,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    // §12.4: quiet search — subtle fill, small control radius,
                    // no resting border. The theme supplies the focus accent.
                    fillColor: colors.surfaceContainerHighest,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: BorderSide(color: colors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              // Favorites toggle — always visible in the header
              _FavoriteToggleButton(
                active: _onlyFavorites,
                onTap: _toggleFavorites,
              ),
              if (widget.allowFilters) ...[
                const SizedBox(width: 4),
                _FilterIconButton(
                  activeCount: _activeFilters.length,
                  onTap: _openFilterSheet,
                ),
              ],
            ],
          ),
          // Active filter chips row — shown inline below search when filters active
          if (widget.allowFilters && _activeFilters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ActiveFiltersDisplay(
                activeFilters: _activeFilters,
                onFilterRemoved: _removeFilter,
              ),
            ),
          const SizedBox(height: AppSpacing.x1),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, controller) => ResponsiveCenter(
          maxContentWidth: 600,
          child: FilterSelectionScreen(
            initialFilters: _activeFilters,
            sourceOptions: widget.allowSharedExercises
                ? const [customExerciseFilterLabel, sharedExerciseFilterLabel]
                : const [customExerciseFilterLabel],
          ),
        ),
      ),
    );
    if (result != null) {
      final wasShared = _isSharedMode;
      setState(() => _activeFilters = result.toList());
      if (wasShared != _isSharedMode) {
        unawaited(_reloadForActiveSource());
      } else {
        _applyFilters();
      }
    }
  }

  /// Applies a staggered entrance to the first [AppMotion.staggerMaxItems]
  /// items in the list, once per screen build. Reduce-motion respected.
  Widget _maybeStagger(int index, String exerciseKey, Widget child) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion ||
        index >= 8 || // stagger budget
        _staggeredExerciseKeys.contains(exerciseKey)) {
      return child;
    }
    _staggeredExerciseKeys.add(exerciseKey);
    return StaggeredCardEntrance(index: index, child: child);
  }

  /// A single compact exercise row (avatar · name/meta · count chip). Shared by
  /// the single-column list (below 900) and the two-column wide grid (>= 900)
  /// so both layouts render the identical tile, tap target, and stagger.
  Widget _buildCompactExerciseRow(BuildContext context, int index) {
    final exercise = _filteredExercises[index];
    final last = _lastPerformedFor(exercise);
    final heroTag = 'exercise_image_${exercise.name}';
    final exerciseKey = _exerciseKey(exercise);
    final colors = Theme.of(context).colorScheme;
    final selected = _multiSelectMode && _isSelected(exercise);
    final item = InkWell(
      onTap: () {
        if (!_multiSelectMode) Haptics.selection();
        _handleExerciseTap(exercise);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.x1,
          horizontal: 6,
        ),
        child: Row(
          children: [
            if (_multiSelectMode) ...[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected ? colors.primary : colors.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.x1),
            ],
            Hero(
              tag: heroTag,
              child: _buildAvatar(
                exercise.imageUrl,
                exercise.name,
                Theme.of(context).colorScheme,
              ),
            ),
            const SizedBox(width: AppSpacing.x1 + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // §12.4: row name = 15/w500 (bodyLarge).
                  Text(
                    exercise.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  // Muted 12px meta.
                  Text(
                    exercise.muscles.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (last != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Last: ${DateFormat.yMMMd().format(last.toLocal())}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            // Workout count with tooltip so the number has context
            Tooltip(
              message: 'Times performed',
              child: AppChip(
                label: _workoutCountFor(exercise).toString(),
                variant: AppChipVariant.data,
              ),
            ),
          ],
        ),
      ),
    );
    return _maybeStagger(index, exerciseKey, item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // On the Library tab root the title is left-aligned and the account
        // avatar lives in actions (top-right); on a pushed selection screen the
        // title stays centred with a back button in leading.
        centerTitle: !widget.showMenuButton,
        automaticallyImplyLeading: false,
        leading: widget.showMenuButton
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
        title: Text(
          _multiSelectMode ? 'Select for superset' : widget.appBarTitle,
        ),
        actions: [
          if (widget.allowMultiSelect)
            IconButton(
              key: const ValueKey('multiSelectToggle'),
              tooltip: _multiSelectMode
                  ? 'Cancel superset selection'
                  : 'Group as superset',
              icon: Icon(_multiSelectMode ? Icons.close : Icons.link),
              onPressed: _toggleMultiSelectMode,
            ),
          if (!_multiSelectMode && widget.appBarTrailing != null)
            widget.appBarTrailing!,
          // View mode toggle (compact-only matters; hidden during multi-select)
          if (!_multiSelectMode)
            IconButton(
              tooltip: _compactList
                  ? 'Switch to grid view'
                  : 'Switch to list view',
              icon: Icon(_compactList ? Icons.grid_view : Icons.view_list),
              onPressed: _toggleViewMode,
            ),
          // On the tab root the account avatar is the trailing-most action
          // (top-right), matching every other tab root.
          if (widget.showMenuButton)
            HustlMenuButton(scaffoldKey: widget.menuScaffoldKey),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: _multiSelectMode
          ? _SupersetConfirmBar(
              count: _selectedKeys.length,
              onConfirm: _selectedKeys.length >= 2 ? _confirmMultiSelect : null,
            )
          : null,
      // Constrain the list body so exercises don't stretch edge-to-edge on
      // tablet portrait (~720) or sprawl on desktop (1200), matching the
      // MainScaffold-based screens.
      body: ResponsiveCenter(
        maxContentWidth: 720,
        wideMaxWidth: 1200,
        child: Column(
          children: [
            // Search bar moved to TOP per spec
            _buildSearchHeader(context),
            Expanded(child: _buildBodyContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent() {
    if (_isLoading) {
      return _ExerciseListSkeleton();
    }

    if (_loadFailed && _exercises.isEmpty) {
      return ScreenEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'We couldn\'t load your exercises',
        message:
            'Something went wrong reaching your exercise library. Check your '
            'connection and try again.',
        actionLabel: 'Try again',
        onAction: _loadExercises,
      );
    }

    if (_filteredExercises.isEmpty) {
      // Inviting first-run / empty paths, never a bare "0":
      //   1. Favorites-only on, nothing starred — point to the star.
      //   2. A search with no matches — offer to clear it.
      //   3. Filters active with no matches — offer to clear them.
      //   4. A genuinely empty catalog — reassure it's on its way, offer refresh.
      if (_onlyFavorites) {
        return ScreenEmptyState(
          icon: Icons.star_border,
          title: 'No favorites yet',
          message:
              'Tap the star on any exercise and it lands here for quick access.',
          actionLabel: 'Browse all exercises',
          onAction: () {
            setState(() {
              _onlyFavorites = false;
              _applyFilters();
            });
          },
        );
      }
      if (_searchQuery.isNotEmpty) {
        return ScreenEmptyState(
          icon: Icons.search_off,
          title: 'No matches for “$_searchQuery”',
          message:
              'Try a different keyword, or clear the search to see them all.',
          actionLabel: 'Clear search',
          onAction: () {
            _searchController.clear();
            _onSearchChanged('');
          },
        );
      }
      if (widget.allowFilters && _activeFilters.isNotEmpty) {
        return ScreenEmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'No exercises match these filters',
          message:
              'Loosen a filter to bring more of the catalog back into view.',
          actionLabel: 'Clear filters',
          onAction: () {
            setState(() => _activeFilters = []);
            unawaited(_reloadForActiveSource());
          },
        );
      }
      return ScreenEmptyState(
        icon: Icons.fitness_center,
        title: _isSharedMode
            ? 'No shared exercises yet'
            : 'Your exercise library is on its way',
        message: _isSharedMode
            ? 'Shared exercises from the community will show up here once they sync.'
            : 'Hundreds of movements load the moment you’re online — check back in a moment.',
        actionLabel: 'Refresh',
        onAction: _refreshFromBackend,
      );
    }

    if (_compactList) {
      // Wide (>= 900): a single column of full-width rows sprawls inside the
      // ~1200 shell. Re-flow the SAME compact rows into a two-column grid so the
      // library fills the width like Apple Fitness's catalog on iPad. Below 900
      // the layout stays byte-for-byte the single-column separated list.
      final width = MediaQuery.sizeOf(context).width;
      if (width >= ResponsiveCenter.wideBreakpoint) {
        return RefreshIndicator(
          onRefresh: _refreshFromBackend,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x1,
              AppSpacing.x1,
              AppSpacing.x1,
              84,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.x1,
              crossAxisSpacing: AppSpacing.x2,
              // Avatar (52) + 8/8 vertical padding sets the row floor; the 1–3
              // text lines stay within it, so a fixed extent keeps both 2-line
              // and 3-line rows clip-free with a little headroom.
              mainAxisExtent: 76,
            ),
            itemCount: _filteredExercises.length,
            itemBuilder: (context, index) =>
                _buildCompactExerciseRow(context, index),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _refreshFromBackend,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x1,
            AppSpacing.x1,
            AppSpacing.x1,
            84,
          ),
          itemCount: _filteredExercises.length,
          separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5),
          itemBuilder: (context, index) =>
              _buildCompactExerciseRow(context, index),
        ),
      );
    }

    // Grid (card) mode
    return LayoutBuilder(
      builder: (context, constraints) {
        const double horizontalPadding = 12;
        const double crossAxisSpacing = 12;
        final double w = constraints.maxWidth;
        final int crossAxisCount;
        if (w >= 1500) {
          crossAxisCount = 6;
        } else if (w >= 1200) {
          crossAxisCount = 5;
        } else if (w >= 900) {
          crossAxisCount = 4;
        } else if (w >= 600) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 2;
        }
        final double tileWidth =
            (w -
                (horizontalPadding * 2) -
                (crossAxisSpacing * (crossAxisCount - 1))) /
            crossAxisCount;
        final double tileHeight = tileWidth + 104;

        return RefreshIndicator(
          onRefresh: _refreshFromBackend,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: crossAxisSpacing,
              crossAxisSpacing: crossAxisSpacing,
              mainAxisExtent: tileHeight,
            ),
            itemCount: _filteredExercises.length,
            itemBuilder: (context, index) {
              final exercise = _filteredExercises[index];
              final isGenerating = _generating.contains(_exerciseKey(exercise));
              final heroTag = 'exercise_image_${exercise.name}';
              return card_widget.ExerciseCard(
                exerciseName: exercise.name,
                muscleGroup: exercise.muscles.join(', '),
                lastPerformed: _lastPerformedFor(exercise),
                imageUrl: exercise.imageUrl,
                heroTag: heroTag,
                onTap: () {
                  Haptics.selection();
                  _handleExerciseTap(exercise);
                },
                showRefresh:
                    _debugMode && ApiConfig.debugExerciseGenerationEnabled,
                isLoading: isGenerating,
                onRefresh: () => _onRegenerateImagePressed(exercise),
              );
            },
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder for the exercise list while loading.
class _ExerciseListSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x1,
        AppSpacing.x1,
        AppSpacing.x1,
        84,
      ),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.x1,
            horizontal: 6,
          ),
          child: Row(
            children: [
              AppSkeleton(
                width: 52,
                height: 52,
                borderRadius: BorderRadius.circular(AppRadius.control - 2),
              ),
              const SizedBox(width: AppSpacing.x1 + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(
                      width: double.infinity,
                      height: 14,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    const SizedBox(height: 6),
                    AppSkeleton(
                      width: 120,
                      height: 12,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Favorites toggle icon-button shown in the search header.
class _FavoriteToggleButton extends StatelessWidget {
  const _FavoriteToggleButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: active ? 'Show all exercises' : 'Favorites only',
      child: Material(
        color: active
            ? AppColors.accentWarningAmber.withValues(alpha: 0.14)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              active ? Icons.star : Icons.star_border,
              size: 22,
              color: active
                  ? AppColors.accentWarningAmber
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter icon-button with optional active-count badge.
class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Filter exercises',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: activeCount > 0
                ? colors.primary.withValues(alpha: 0.12)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.filter_list,
                  size: 22,
                  color: activeCount > 0
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (activeCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  activeCount.toString(),
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UsageStats {
  final Map<String, int> counts;
  final Map<String, DateTime> lastPerformed;

  const _UsageStats(this.counts, this.lastPerformed);
}

/// Sticky bottom bar shown in multi-select mode: a single "Superset" action
/// that groups the chosen exercises. Disabled until 2+ are selected.
class _SupersetConfirmBar extends StatelessWidget {
  const _SupersetConfirmBar({required this.count, required this.onConfirm});

  final int count;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x1,
          AppSpacing.x2,
          AppSpacing.x1,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                count < 2
                    ? 'Select 2 or more exercises'
                    : '$count exercises selected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            FilledButton.icon(
              key: const ValueKey('supersetConfirmButton'),
              onPressed: onConfirm,
              icon: const Icon(Icons.link, size: 18),
              label: Text(count >= 2 ? 'Superset ($count)' : 'Superset'),
            ),
          ],
        ),
      ),
    );
  }
}
