import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/coach_card.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/hustl_icon.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../workout_logging/presentation/widgets/onboarding_permission_primer.dart';
import '../../domain/models/nutrition_target_plan.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import '../../domain/services/nutrition_checkin_reminder.dart';
import '../nutrition_view_cache.dart';
import '../widgets/goal_setup_dialog.dart';
import '../widgets/nutrition_coach.dart';
import '../widgets/strategy_cards.dart';
import '../widgets/strategy_controls_card.dart';
import '../widgets/strategy_data_quality_card.dart';
import '../widgets/targets_editor_sheet.dart';
import '../widgets/weekly_checkin_sheet.dart';

class StrategyScreen extends StatefulWidget {
  const StrategyScreen({super.key});

  @override
  State<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends State<StrategyScreen> {
  late Future<NutritionTargetPlan?> _futurePlan;
  late Future<Map<String, dynamic>> _checkInFuture;
  final _repo = GetIt.instance<NutritionTargetsRepository>();
  final _reminder = NutritionCheckInReminder();
  // Last-loaded plan (cross-visit) — shown instantly on a revisit.
  NutritionTargetPlan? _cachedPlan;
  // Guards the one-time check-in notification primer so it shows at most once
  // per screen mount (the persisted flag below makes it once per install).
  bool _primerHandled = false;
  // Opt-in behavioral-momentum coach tips (item 4). Off by default; surfaced as
  // a toggle in the controls card.
  bool _momentumEnabled = false;
  // Opt-in "Coach explains my numbers" LLM narrative (item 6). Off by default and
  // independent of momentum; surfaced as its own toggle in the controls card.
  bool _coachExplainsEnabled = false;

  /// Fetches the current plan, populating [_cachedPlan] from the cross-visit
  /// cache first so a revisit paints instantly instead of flashing the skeleton.
  Future<NutritionTargetPlan?> _loadPlan() {
    _cachedPlan = NutritionViewCache.instance.get<NutritionTargetPlan>(
      'strategy:plan',
    );
    return _repo.getCurrentPlan(DateTime.now()).then((value) {
      if (value != null) {
        NutritionViewCache.instance.set('strategy:plan', value);
      }
      return value;
    });
  }

  @override
  void initState() {
    super.initState();
    _futurePlan = _loadPlan()..then(_onPlanResolved);
    _checkInFuture = _repo.getWeeklyCheckIn(DateTime.now());
    _loadMomentumPref();
  }

  Future<void> _loadMomentumPref() async {
    final prefs = PreferencesService();
    final momentum = await prefs.getBehavioralMomentumEnabled();
    final coachExplains = await prefs.getCoachExplainsEnabled();
    if (!mounted) return;
    if (momentum == _momentumEnabled &&
        coachExplains == _coachExplainsEnabled) {
      return;
    }
    setState(() {
      _momentumEnabled = momentum;
      _coachExplainsEnabled = coachExplains;
    });
  }

  Future<void> _toggleMomentum(bool enabled) async {
    Haptics.selection();
    setState(() => _momentumEnabled = enabled);
    await PreferencesService().setBehavioralMomentumEnabled(enabled);
  }

  Future<void> _toggleCoachExplains(bool enabled) async {
    Haptics.selection();
    setState(() => _coachExplainsEnabled = enabled);
    await PreferencesService().setCoachExplainsEnabled(enabled);
  }

  Future<void> _refresh() async {
    setState(() {
      _futurePlan = _loadPlan()..then(_onPlanResolved);
      _checkInFuture = _repo.getWeeklyCheckIn(DateTime.now());
    });
  }

  /// Once a *real* plan is in hand, offer the one-time reminder primer and keep
  /// the OS schedule in sync with the current mode/lock state. No-ops during
  /// first-run setup (a zeroed plan has no check-in to remind about).
  Future<void> _onPlanResolved(NutritionTargetPlan? plan) async {
    if (!mounted || plan == null || plan.needsSetup) return;
    await _maybePrimeCheckInReminder(plan);
    if (!mounted) return;
    await _reminder.sync(plan);
  }

  /// Shows the in-context rationale before the OS notification prompt, exactly
  /// once per install. "Turn on" opts in (the [_reminder] sync that follows arms
  /// it); "Not now" leaves it off and discoverable later in Settings.
  Future<void> _maybePrimeCheckInReminder(NutritionTargetPlan plan) async {
    if (_primerHandled) return;
    _primerHandled = true;
    final prefs = PreferencesService();
    if (await prefs.getSeenNutritionNotificationPrimer()) return;
    if (!mounted) return;
    final allow = await OnboardingPermissionPrimer.show(
      context,
      assetIcon: 'assets/icons/ic_calendar.svg',
      title: 'Weekly check-in reminder',
      message:
          'Get one gentle nudge a week to review your trend and fresh targets. '
          'No streaks, no nagging — turn it off anytime in Settings.',
      allowLabel: 'Turn on',
      notNowLabel: 'Not now',
    );
    // Only consume the primer on an explicit choice (Turn on / Not now). An
    // accidental dismissal (barrier tap/swipe) must not permanently mark it seen.
    if (allow != PermissionPrimerChoice.dismissed) {
      await prefs.setSeenNutritionNotificationPrimer(true);
    }
    if (allow == PermissionPrimerChoice.allow) {
      await prefs.setNutritionCheckInReminderEnabled(true);
    }
  }

  Future<void> _toggleMode(NutritionTargetPlan plan, bool isAuto) async {
    final updated = await _repo.updatePlan(plan.weekStart, {
      'mode': isAuto ? 'auto' : 'manual',
    });
    setState(() {
      _futurePlan = Future.value(updated)..then(_onPlanResolved);
      _checkInFuture = _repo.getWeeklyCheckIn(DateTime.now());
    });
  }

  Future<void> _openGoalSetup(NutritionTargetPlan plan) async {
    final result = await showGoalSetupDialog(
      context,
      initialGoal: plan.goal,
      initialRatePerWeek: plan.ratePerWeek,
      initialProfile: plan.profile,
      requireProfile: plan.needsSetup,
    );
    if (result == null) return;
    final newPlan = await _repo.recalculatePlan(
      DateTime.now(),
      mode: plan.mode,
      goal: result['goal'] as String?,
      ratePerWeek: result['rate'] as double?,
      profile: (result['profile'] as Map?)?.cast<String, dynamic>(),
    );
    setState(() {
      _futurePlan = Future.value(newPlan)..then(_onPlanResolved);
      _checkInFuture = _repo.getWeeklyCheckIn(DateTime.now());
    });
  }

  Future<void> _openTargetsEditor(NutritionTargetPlan plan) async {
    final patch = await showTargetsEditorSheet(context, plan);
    if (patch == null) return;
    final updated = await _repo.updatePlan(plan.weekStart, patch);
    setState(() {
      _futurePlan = Future.value(updated)..then(_onPlanResolved);
      _checkInFuture = _repo.getWeeklyCheckIn(DateTime.now());
    });
  }

  Future<void> _openCheckIn(
    NutritionTargetPlan plan,
    Map<String, dynamic> payload,
  ) async {
    if (!mounted) return;
    var working = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setInnerState) {
          final router = GoRouter.of(context);
          return WeeklyCheckInSheet(
            plan: plan,
            payload: payload,
            isWorking: working,
            onApply: () async {
              setInnerState(() => working = true);
              try {
                await _repo.applyWeeklyCheckIn(DateTime.now());
                if (!mounted) return;
                if (router.canPop()) router.pop();
                await _refresh();
              } catch (e) {
                setInnerState(() => working = false);
                if (!sheetContext.mounted) return;
                HustlSnack.show(
                  sheetContext,
                  'Couldn\'t apply your check-in. Please try again.',
                  variant: HustlSnackVariant.error,
                );
              }
            },
            onSkip: () async {
              setInnerState(() => working = true);
              try {
                await _repo.skipWeeklyCheckIn(DateTime.now());
                if (!mounted) return;
                if (router.canPop()) router.pop();
                await _refresh();
              } catch (e) {
                setInnerState(() => working = false);
                if (!sheetContext.mounted) return;
                HustlSnack.show(
                  sheetContext,
                  'Couldn\'t skip your check-in. Please try again.',
                  variant: HustlSnackVariant.error,
                );
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _setLockUntil(NutritionTargetPlan plan) async {
    final now = DateTime.now();
    final initial = plan.lockedUntil?.isAfter(now) == true
        ? plan.lockedUntil!
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final updated = await _repo.updatePlan(plan.weekStart, {
      'lockUntil': picked.toIso8601String(),
    });
    setState(() {
      _futurePlan = Future.value(updated)..then(_onPlanResolved);
      _checkInFuture = _repo.getWeeklyCheckIn(DateTime.now());
    });
  }

  Future<void> _clearLock(NutritionTargetPlan plan) async {
    final updated = await _repo.updatePlan(plan.weekStart, {'lockUntil': null});
    setState(() {
      _futurePlan = Future.value(updated)..then(_onPlanResolved);
      _checkInFuture = _repo.getWeeklyCheckIn(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Strategy'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      child: FutureBuilder<NutritionTargetPlan?>(
        future: _futurePlan,
        builder: (context, snapshot) {
          // SWR: paint the last-cached plan instantly; skeleton only on a true
          // first load.
          final plan = snapshot.data ?? _cachedPlan;
          if (plan == null) {
            return AppSkeleton.lines(semanticsLabel: 'Loading strategy');
          }
          // First run: no plan has been set up yet, so the hero/macros/coaching
          // cards would all render as gray zeros (0 kcal, 0 g, 0/7). Greet the
          // new user with an inviting prompt and one blue CTA into goal setup
          // instead of a lifeless zeroed-out program.
          if (plan.needsSetup) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: AppSpacing.x4),
                  _StrategyFirstRunPrompt(
                    onSetGoal: () => _openGoalSetup(plan),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FutureBuilder<Map<String, dynamic>>(
                  future: _checkInFuture,
                  builder: (context, checkSnap) {
                    final payload = (checkSnap.data as Map?)
                        ?.cast<String, dynamic>();
                    final available = payload?['available'] == true;
                    final coverage = (payload?['coverage'] as Map?)
                        ?.cast<String, dynamic>();
                    final why = (payload?['why'] as Map?)
                        ?.cast<String, dynamic>();
                    final tdeeKcal = (why?['tdeeKcal'] as num?)?.toDouble();
                    final coachInsight = nutritionCoachInsight(
                      plan: plan,
                      checkIn: payload,
                      onReviewCheckIn: available && payload != null
                          ? () => _openCheckIn(plan, payload)
                          : null,
                    );
                    return Column(
                      children: [
                        // Coach leads — the single guidance + "Review check-in"
                        // surface, above the data.
                        if (coachInsight != null) ...[
                          CoachCard(insight: coachInsight),
                          const SizedBox(height: AppSpacing.x3),
                        ],
                        StrategyHeroCard(plan: plan, tdeeKcal: tdeeKcal),
                        const SizedBox(height: AppSpacing.x3),
                        StrategyMacrosGridCard(plan: plan),
                        const SizedBox(height: AppSpacing.x3),
                        StrategyDataQualityRingsCard(coverage: coverage),
                        const SizedBox(height: AppSpacing.x3),
                        StrategyControlsCard(
                          plan: plan,
                          onToggleMode: (v) => _toggleMode(plan, v),
                          onSetLock: () => _setLockUntil(plan),
                          onClearLock: () => _clearLock(plan),
                          onEditTargets: () => _openTargetsEditor(plan),
                          onSetGoal: () => _openGoalSetup(plan),
                          momentumEnabled: _momentumEnabled,
                          onToggleMomentum: _toggleMomentum,
                          coachExplainsEnabled: _coachExplainsEnabled,
                          onToggleCoachExplains: _toggleCoachExplains,
                        ),
                        const SizedBox(height: AppSpacing.x2),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The strategy first-run welcome (Wave I — Apple Fitness+ x Whoop): shown when
/// no plan has been set up yet, before any goal exists. A soft elevated card
/// with a blue-tinted icon holder, a confident sentence-case headline, one warm
/// supportive line, and a blue [FilledButton] that opens goal setup. A brand-new
/// user lands on an invitation, not a zeroed-out program. The entrance fade/rise
/// is skipped under reduce-motion.
class _StrategyFirstRunPrompt extends StatelessWidget {
  const _StrategyFirstRunPrompt({required this.onSetGoal});

  final VoidCallback onSetGoal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x3,
        AppSpacing.x4,
        AppSpacing.x3,
        AppSpacing.x3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: HustlIcon(
                asset: 'assets/icons/ic_target.svg',
                size: 30,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2 + 4),
          Text(
            'Set your nutrition goal',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x1 + 2),
          Text(
            'Tell us whether you want to lose, maintain, or gain, and we\'ll '
            'build daily calorie and macro targets that adapt as you log.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Haptics.selection();
                onSetGoal();
              },
              child: const Text('Set my goal'),
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) return card;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: card,
    );
  }
}
