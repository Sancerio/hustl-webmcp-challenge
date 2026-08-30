import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/web/platform_redirect.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/widgets/responsive_center.dart';
import '../../../nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../../../nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import '../../../nutrition_tracker/domain/services/food_log_csv_export_service.dart';
import '../../../nutrition_tracker/domain/services/food_log_history_loader.dart';
import '../../../nutrition_tracker/domain/services/weight_history_csv_export_service.dart';
import '../../../onboarding/domain/workout_import_runner.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/repositories/workout_repository.dart';
import '../../../workout_logging/domain/services/strong_csv_import_service.dart';
import 'strong_import_help.dart';

/// Import / export workout data (Strong CSV) — a pushed sub-screen so the
/// file-picker, preview, progress and share flows are a normal screen with a
/// back affordance instead of a stack of dialogs inside Settings.
class DataImportExportScreen extends StatefulWidget {
  const DataImportExportScreen({super.key});

  /// Test seam: when set, the nutrition/weight CSV exports are routed here
  /// instead of the platform share sheet / web download, so widget tests can
  /// assert on the produced file without platform channels.
  @visibleForTesting
  static Future<void> Function({
    required String fileName,
    required String csvText,
  })?
  debugCsvShareOverride;

  @override
  State<DataImportExportScreen> createState() => _DataImportExportScreenState();
}

class _DataImportExportScreenState extends State<DataImportExportScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const HustlMenuButton(),
        title: const Text('Import / export data'),
      ),
      body: ResponsiveCenter(
        maxContentWidth: 720,
        wideMaxWidth: 1200,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.x2),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: const Text('Import from Strong'),
                    subtitle: const Text('CSV export from Strong app'),
                    onTap: _onImportFromStrong,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('Export workouts (CSV)'),
                    subtitle: const Text('Strong-compatible export'),
                    onTap: _onExportWorkoutsCsv,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('Export nutrition (CSV)'),
                    subtitle: const Text('Your full food log history'),
                    onTap: _onExportNutritionCsv,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('Export weight history (CSV)'),
                    subtitle: const Text('Scale and trend weight, in kg'),
                    onTap: _onExportWeightCsv,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('How to export from Strong'),
                    subtitle: const Text(
                      'Step-by-step export and import guide',
                    ),
                    onTap: () => showStrongImportHelp(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onImportFromStrong() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      // Decode as UTF-8 so non-ASCII exercise/workout names survive (raw code
      // units would mojibake them and break name-based dedupe/catalog matching).
      final text = utf8.decode(bytes, allowMalformed: true);

      final importer = GetIt.instance<StrongCsvImportService>();
      final parsed = await importer.parse(text);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('Import Preview'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (parsed.warnings.isNotEmpty) ...[
                    Text(
                      'Warnings (${parsed.warnings.length}):',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 80,
                      child: SingleChildScrollView(
                        child: Text(
                          parsed.warnings.join('\n'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const Divider(),
                  ],
                  Text('${parsed.sessions.length} sessions found'),
                  const SizedBox(height: AppSpacing.x1),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      itemCount: parsed.sessions.length,
                      itemBuilder: (_, i) {
                        final s = parsed.sessions[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.name),
                          subtitle: Text(
                            '${DateFormat('yyyy-MM-dd').format(s.startTime)} • ${s.exercises.length} exercises',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => context.pop(true),
                child: const Text('Import'),
              ),
            ],
          );
        },
      ).then((confirmed) async {
        if (confirmed == true) {
          await _importSessionsWithProgress(parsed.sessions);
        }
      });
    } catch (e) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn\'t import your Strong data: $e',
        variant: HustlSnackVariant.error,
      );
    }
  }

  Future<void> _onExportWorkoutsCsv() async {
    // iOS requires an anchor rect for the share popover (it's mandatory on iPad,
    // and omitting it throws PlatformException(sharePositionOrigin ...)). Capture
    // the screen's rect BEFORE any await so we never touch a stale context.
    final renderBox = context.findRenderObject() as RenderBox?;
    final mediaSize = MediaQuery.of(context).size;
    final shareOrigin = (renderBox != null && renderBox.hasSize)
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : Rect.fromLTWH(0, 0, mediaSize.width, mediaSize.height / 2);
    try {
      final repo = GetIt.instance<WorkoutRepository>();
      final exporter = GetIt.instance<StrongCsvExportService>();

      final sessions = await repo.getWorkoutSessions();
      final csvText = exporter.buildCsv(sessions);
      final fileName = exporter.fileName();

      if (kIsWeb) {
        webDownloadTextFile(
          fileName: fileName,
          contents: csvText,
          mimeType: 'text/csv',
        );
      } else {
        final bytes = Uint8List.fromList(utf8.encode(csvText));
        final file = XFile.fromData(
          bytes,
          mimeType: 'text/csv',
          name: fileName,
        );
        await Share.shareXFiles(
          [file],
          subject: fileName,
          sharePositionOrigin: shareOrigin,
        );
      }

      if (!mounted) return;
      HustlSnack.show(
        context,
        'Export ready',
        variant: HustlSnackVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn\'t export your workouts: $e',
        variant: HustlSnackVariant.error,
      );
    }
  }

  Future<void> _onExportNutritionCsv() async {
    // Same iPad share-popover anchor rule as the workout export: capture the
    // rect BEFORE any await so we never touch a stale context.
    final shareOrigin = _shareOriginRect();
    try {
      final loader = FoodLogHistoryLoader(
        repository: GetIt.instance<FoodLogRepository>(),
      );
      const exporter = FoodLogCsvExportService();

      // History can span years, so it's fetched in bounded windows (the
      // backend caps one request at 366 days) behind a progress dialog.
      final entries = await _runWithExportProgress(
        title: 'Preparing nutrition export',
        task: (onProgress) => loader.loadAll(onWindowFetched: onProgress),
      );

      await _shareCsv(
        fileName: exporter.fileName(),
        csvText: exporter.buildCsv(entries),
        shareOrigin: shareOrigin,
      );

      if (!mounted) return;
      HustlSnack.show(
        context,
        'Export ready',
        variant: HustlSnackVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn\'t export your nutrition history: $e',
        variant: HustlSnackVariant.error,
      );
    }
  }

  Future<void> _onExportWeightCsv() async {
    final shareOrigin = _shareOriginRect();
    try {
      final repo = GetIt.instance<NutritionTargetsRepository>();
      const exporter = WeightHistoryCsvExportService();

      // Single ranged read covering the weight screen's "All" range (10y).
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day - 3650);
      final payload = await repo.getWeightTrend(start, now);

      await _shareCsv(
        fileName: exporter.fileName(),
        csvText: exporter.buildCsv(payload),
        shareOrigin: shareOrigin,
      );

      if (!mounted) return;
      HustlSnack.show(
        context,
        'Export ready',
        variant: HustlSnackVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn\'t export your weight history: $e',
        variant: HustlSnackVariant.error,
      );
    }
  }

  /// The iPad share-popover anchor (mandatory there; omitting it throws
  /// PlatformException) — same computation the workout export uses inline.
  Rect _shareOriginRect() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final mediaSize = MediaQuery.of(context).size;
    return (renderBox != null && renderBox.hasSize)
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : Rect.fromLTWH(0, 0, mediaSize.width, mediaSize.height / 2);
  }

  /// Runs [task] behind a non-dismissible progress dialog. The task receives
  /// an `onProgress(step)` callback that refreshes the dialog's step counter.
  Future<T> _runWithExportProgress<T>({
    required String title,
    required Future<T> Function(void Function(int step) onProgress) task,
  }) async {
    var step = 0;
    StateSetter? setDialogState;
    // ignore: unawaited_futures
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          setDialogState = setState;
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    step == 0
                        ? 'Fetching history…'
                        : 'Fetched $step period${step == 1 ? '' : 's'}',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    try {
      return await task((done) {
        step = done;
        setDialogState?.call(() {});
      });
    } finally {
      if (mounted) context.pop();
    }
  }

  /// Saves/shares a built CSV with the exact flow the workout export uses
  /// (web download on web, share sheet elsewhere). Routed through the
  /// [DataImportExportScreen.debugCsvShareOverride] seam in widget tests.
  Future<void> _shareCsv({
    required String fileName,
    required String csvText,
    required Rect shareOrigin,
  }) async {
    final override = DataImportExportScreen.debugCsvShareOverride;
    if (override != null) {
      await override(fileName: fileName, csvText: csvText);
      return;
    }
    if (kIsWeb) {
      webDownloadTextFile(
        fileName: fileName,
        contents: csvText,
        mimeType: 'text/csv',
      );
    } else {
      final bytes = Uint8List.fromList(utf8.encode(csvText));
      final file = XFile.fromData(bytes, mimeType: 'text/csv', name: fileName);
      await Share.shareXFiles(
        [file],
        subject: fileName,
        sharePositionOrigin: shareOrigin,
      );
    }
  }

  Future<void> _importSessionsWithProgress(
    List<WorkoutSession> sessions,
  ) async {
    if (!mounted || sessions.isEmpty) return;
    final runner = WorkoutImportRunner(
      repository: GetIt.instance<WorkoutRepository>(),
    );
    final total = sessions.length;
    int processed = 0;

    StateSetter? setDialogState;
    // ignore: unawaited_futures
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          setDialogState = setState;
          final progress = total == 0
              ? null
              : (processed / total).clamp(0.0, 1.0);
          return AlertDialog(
            title: const Text('Importing Strong data'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text('Processed $processed of $total'),
                ],
              ),
            ),
          );
        },
      ),
    );

    // The write loop + (name + start time) merge-on-collision dedup live in
    // WorkoutImportRunner; this screen only owns the progress dialog + snack.
    final outcome = await runner.run(
      sessions,
      onProgress: (done, _) {
        processed = done;
        if (done == total || done % 5 == 0) {
          setDialogState?.call(() {});
        }
      },
    );

    if (mounted) {
      context.pop();
      final msg = outcome.replaced > 0
          ? 'Imported ${outcome.imported}, replaced ${outcome.replaced} existing'
          : 'Imported ${outcome.imported} '
                'session${outcome.imported == 1 ? '' : 's'}';
      HustlSnack.show(context, msg, variant: HustlSnackVariant.success);
    }
  }
}
