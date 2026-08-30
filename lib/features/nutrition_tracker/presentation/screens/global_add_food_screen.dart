import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/navigation/app_router.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';

import '../../domain/models/food_log_entry.dart';
import '../../domain/repositories/food_log_repository.dart';
import '../diary_refresh_signal.dart';
import '../widgets/add_food_sheet.dart';

/// Host for the global "/add-food" entry point. Reachable in one tap from the
/// shell (and the nutrition tab), this screen has no chrome of its own: it
/// immediately presents [AddFoodSheet] for today and persists anything the user
/// logs straight through the [FoodLogRepository], so a diary the user later
/// opens picks the new entries up on its next load.
///
/// Dismissing the sheet (with or without a log) pops back to wherever the user
/// came from. This keeps the add-food flow a true overlay — no extra tab, no
/// lingering blank screen.
class GlobalAddFoodScreen extends StatefulWidget {
  const GlobalAddFoodScreen({super.key});

  @override
  State<GlobalAddFoodScreen> createState() => _GlobalAddFoodScreenState();
}

class _GlobalAddFoodScreenState extends State<GlobalAddFoodScreen> {
  bool _presented = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _present());
  }

  Future<void> _present() async {
    if (_presented) return;
    _presented = true;

    final router = GoRouter.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) => AddFoodSheet(
        // No date argument from this entry point: default to today.
        date: DateTime.now(),
        onAdd: _persist,
        // The quick action is a fire-and-return overlay: each pick logs
        // immediately and pops back, so it opts out of the staging plate.
        enablePlate: false,
      ),
    );

    // The sheet is gone; this host has nothing left to show, so leave.
    if (router.canPop()) router.pop();
  }

  /// Persists the logged entries. The sheet and this host both tear down the
  /// instant the user commits — so a save failure can't surface through the
  /// local (now-unmounted) context. We report errors out-of-band through the
  /// root ScaffoldMessenger (via the global navigatorKey), which outlives this
  /// screen, so a dropped save is always announced rather than silently lost.
  ///
  /// The persist is deliberately NOT awaited before popping: the happy path
  /// stays snappy and the user returns immediately, while a failure still shows
  /// a snack on whatever screen they landed on.
  Future<void> _persist(List<FoodLogEntry> entries) async {
    if (entries.isEmpty) return;
    final repo = GetIt.instance<FoodLogRepository>();
    try {
      await repo.addEntries(entries);
      // The live diary (kept alive in the shell's IndexedStack) owns its own
      // DiaryBloc and only reloads on its own events, so a food logged here
      // would otherwise be invisible until a manual refresh. Ping the shared
      // refresh signal so any mounted diary reloads its current day and picks
      // up the new entry.
      final getIt = GetIt.instance;
      if (getIt.isRegistered<DiaryRefreshSignal>()) {
        getIt<DiaryRefreshSignal>().ping();
      }
    } catch (_) {
      // Route-independent surface: the global navigator's context resolves the
      // root ScaffoldMessenger, which outlives this popped host. This is a fresh
      // global lookup (not a stale captured context), so it's safe across the
      // await despite the lint — matching the navigatorKey pattern used by
      // NotificationService.
      final messengerContext = navigatorKey.currentContext;
      if (messengerContext == null) return;
      HustlSnack.show(
        // ignore: use_build_context_synchronously
        messengerContext,
        'Couldn’t save that food. Please try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // A bare scaffold under the modal sheet — never the focus, just a backdrop
    // while the sheet is up and for the single frame before we pop.
    return const Scaffold(body: SizedBox.shrink());
  }
}
