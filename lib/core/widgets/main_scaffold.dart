import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/meal_photo_scan_dialog.dart';

/// Per-screen scaffold. Navigation chrome (bottom nav bar, active-workout
/// banner, desktop rail) is owned ONCE by the app shell, so this widget only
/// provides the app bar, body, and optional FAB.
///
/// On wide screens the content is centred at a comfortable max width to match
/// the shell layout for routes that push over it.
class MainScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final Widget? drawer;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const MainScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.drawer,
    this.scaffoldKey,
  });

  static BuildContext _resolveRootContext(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final rootContext = router?.routerDelegate.navigatorKey.currentContext;
    return rootContext ?? context;
  }

  static String _loggedSnackMessage(List<FoodLogEntry> entries) {
    if (entries.length <= 1) return 'Logged meal';
    return 'Logged ${entries.length} foods';
  }

  static Future<void> _logEntries(
    BuildContext context,
    List<FoodLogEntry> entries, {
    bool showViewAction = true,
    bool navigateToDiaryOnSuccess = false,
  }) async {
    final rootContext = _resolveRootContext(context);
    final messenger = ScaffoldMessenger.maybeOf(rootContext);
    final router = GoRouter.maybeOf(rootContext);
    final repo = GetIt.instance<FoodLogRepository>();

    try {
      final saved = await repo.addEntries(entries);
      if (!rootContext.mounted) return;
      if (navigateToDiaryOnSuccess) {
        router?.go('/nutrition');
      }

      final showView = showViewAction && router != null;
      if (messenger != null) {
        HustlSnack.show(
          rootContext,
          _loggedSnackMessage(saved.isNotEmpty ? saved : entries),
          variant: HustlSnackVariant.success,
          // Nutrition is a TAB branch — switch the branch (go) like the
          // sibling navigateToDiaryOnSuccess path, not push.
          actionLabel: showView ? 'View' : null,
          onAction: showView ? () => router.go('/nutrition') : null,
        );
      }
    } catch (e) {
      if (!rootContext.mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (messenger != null) {
        HustlSnack.show(
          rootContext,
          message.trim().isEmpty
              ? 'Couldn’t log meal. Please try again.'
              : message,
          variant: HustlSnackVariant.warning,
        );
      }
    }
  }

  static Future<void> openGlobalMealScan(BuildContext context) async {
    final rootContext = _resolveRootContext(context);
    final now = DateTime.now();
    final result = await showDialog<MealPhotoScanResult>(
      context: rootContext,
      builder: (context) => MealPhotoScanDialog(
        date: now,
        primaryAction: MealPhotoScanAction.addToPlate,
        autoStartCamera: true,
      ),
    );
    if (!rootContext.mounted || result == null) return;

    // The scan dialog already lets the user review/edit before returning, so log
    // straight through — no staging tray. Prefer the per-item breakdown; fall
    // back to the single combined meal entry when there's no breakdown.
    final entries =
        result.action == MealPhotoScanAction.addToPlate &&
            result.plateEntries.isNotEmpty
        ? result.plateEntries
        : [result.totalEntry];
    await _logEntries(
      rootContext,
      entries,
      showViewAction: false,
      navigateToDiaryOnSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: appBar,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      backgroundColor: backgroundColor,
      // Constrain the body — never the app bar — so content stops stretching
      // edge-to-edge on tablet/desktop: a comfortable reading width on tablet
      // portrait (~720), a wider column on landscape tablet / desktop (1200).
      body: ResponsiveCenter(
        maxContentWidth: 720,
        wideMaxWidth: 1200,
        child: child,
      ),
    );
  }
}
