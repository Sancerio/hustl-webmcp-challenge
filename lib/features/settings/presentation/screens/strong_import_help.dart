import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';

/// The "How to export from Strong" step-by-step guide, shown as a bottom sheet.
/// Pure UI (no I/O) — extracted from settings_screen to keep that file smaller.
void showStrongImportHelp(BuildContext context) {
  final theme = Theme.of(context);
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) {
      Widget step(int n, IconData icon, String text) {
        return ListTile(
          dense: false,
          leading: Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Text('$n', style: theme.textTheme.labelLarge),
              ),
              Positioned(
                right: -6,
                bottom: -6,
                child: Icon(icon, size: 14, color: theme.colorScheme.secondary),
              ),
            ],
          ),
          title: Text(text),
        );
      }

      Widget section({
        required IconData icon,
        required String title,
        required List<Widget> children,
      }) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: Icon(icon),
                  title: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ...children,
              ],
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          0,
          AppSpacing.x2,
          AppSpacing.x3,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Icon(
                      Icons.file_upload_outlined,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Import from Strong',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              section(
                icon: Icons.ios_share_outlined,
                title: 'Export from Strong',
                children: [
                  step(
                    1,
                    Icons.settings_outlined,
                    'Open Strong → Profile → Settings',
                  ),
                  step(2, Icons.file_upload_outlined, 'Tap Data / Export Data'),
                  step(
                    3,
                    Icons.save_alt_outlined,
                    'Choose CSV export and save/share the file',
                  ),
                  step(
                    4,
                    Icons.folder_zip_outlined,
                    'If you get a ZIP, unzip and locate strong.csv',
                  ),
                ],
              ),
              section(
                icon: Icons.file_download_done_outlined,
                title: 'Import into Hustl',
                children: [
                  step(
                    1,
                    Icons.settings_suggest_outlined,
                    'In Hustl: Account → Settings',
                  ),
                  step(
                    2,
                    Icons.file_open_outlined,
                    'Tap Import from Strong under Data & Import',
                  ),
                  step(
                    3,
                    Icons.description_outlined,
                    'Pick your strong.csv and review the preview',
                  ),
                  step(4, Icons.check_circle_outline, 'Tap Import to finish'),
                ],
              ),
              section(
                icon: Icons.info_outline,
                title: 'Notes',
                children: const [
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.copy_all_outlined),
                    title: Text(
                      'Duplicate sessions (same name + start time) are replaced',
                    ),
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.rule_folder_outlined),
                    title: Text(
                      'Unmatched exercises are mapped to closest names; review warnings',
                    ),
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.folder_open_outlined),
                    title: Text(
                      'If you have a ZIP, unzip first and select strong.csv',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => context.pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
