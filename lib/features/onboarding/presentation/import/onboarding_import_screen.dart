import 'dart:convert' show utf8;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/di/service_locator.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

import '../../../settings/presentation/screens/strong_import_help.dart';
import '../../../workout_logging/domain/services/strong_csv_import_service.dart';
import '../../domain/import_summary.dart';
import '../intro/onboarding_intro_art.dart';

/// Onboarding switcher entry — "Coming from Strong?". Picks the export, parses it
/// with the real [StrongCsvImportService], and hands a real [ImportSummary] to
/// the preview. Parse problems land on a friendly, recoverable error (retry /
/// help), never a dead-end.
class OnboardingImportScreen extends StatefulWidget {
  const OnboardingImportScreen({super.key});

  @override
  State<OnboardingImportScreen> createState() => _OnboardingImportScreenState();
}

class _OnboardingImportScreenState extends State<OnboardingImportScreen> {
  static const _genericError =
      "We couldn't read that file. Make sure it's the strong.csv you exported, "
      'then try again.';
  static const _notStrongError =
      "That doesn't look like a Strong export. Open Strong, export your data as "
      'CSV, and pick that file.';
  static const _emptyError =
      "We couldn't find any workouts in that file. Pick the strong.csv with your "
      'training history.';

  bool _busy = false;
  String? _error;

  Future<void> _pickAndParse() async {
    Haptics.selection();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = result.files.first.bytes;
      if (bytes == null) {
        if (mounted) setState(() => _failWith(_genericError));
        return;
      }

      // Decode as UTF-8 (Strong exports are UTF-8) so accented exercise names and
      // any BOM/multi-byte chars survive; allowMalformed keeps a stray byte from
      // dead-ending the whole import.
      final parsed = await getIt<StrongCsvImportService>().parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      final summary = ImportSummary.fromSessions(parsed.sessions);
      final missingColumns = parsed.warnings.any(
        (w) => w.contains('Missing required columns'),
      );
      if (!mounted) return;

      if (missingColumns) {
        setState(() => _failWith(_notStrongError));
        return;
      }
      if (summary.isEmpty) {
        setState(() => _failWith(_emptyError));
        return;
      }

      setState(() => _busy = false);
      Haptics.confirm();
      context.push(
        '/onboarding/import/preview',
        extra: {'sessions': parsed.sessions, 'summary': summary},
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _failWith(_genericError));
    }
  }

  void _failWith(String message) {
    _busy = false;
    _error = message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(backgroundColor: colors.surface, elevation: 0),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            0,
            AppSpacing.x3,
            AppSpacing.x3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: LogoMark(size: 48, radius: 14)),
              const SizedBox(height: AppSpacing.x3),
              Text(
                'Coming from Strong?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.x1 + 4),
              Text(
                'Bring your whole training history with you. Export your data '
                'from Strong as a CSV, then pick it here — every workout, set, '
                'and PR comes along.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              if (_error != null) ...[
                _ErrorCard(message: _error!),
                const SizedBox(height: AppSpacing.x2),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _pickAndParse,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 20),
                label: Text(
                  _busy ? 'Reading your file…' : 'Choose your strong.csv',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.pillRadius,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Haptics.selection();
                    showStrongImportHelp(context);
                  },
                  icon: const Icon(Icons.help_outline_rounded, size: 18),
                  label: const Text('How to export from Strong'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primary,
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.6),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: AppColors.accentWarningAmber,
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
