import 'package:flutter/material.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import '../nutrition_view_cache.dart';
import '../widgets/insights_cards.dart';
import '../widgets/refresh_line_overlay.dart';

class NutritionInsightsScreen extends StatefulWidget {
  const NutritionInsightsScreen({super.key});

  @override
  State<NutritionInsightsScreen> createState() =>
      _NutritionInsightsScreenState();
}

class _NutritionInsightsScreenState extends State<NutritionInsightsScreen> {
  final _repo = GetIt.instance<NutritionTargetsRepository>();

  // Cache futures keyed on inputs to avoid unbounded rebuilds.
  final _end = DateTime.now();
  int _rangeDays = 14;
  bool _energyCompareToExpenditure = false;
  // Opt-in behavioral-momentum coach tips (item 4). Read once on mount; the
  // insights fetch only requests the momentum rec when this is true, so the
  // coach is never noisy by default.
  bool _momentumOptIn = false;
  // Opt-in "Coach explains my numbers" narrative (item 6). Read once on mount;
  // the narrative is fetched LAZILY (only when the user expands the explanation)
  // and only when this is true, so it stays entirely off the insights load path.
  bool _coachExplainsOptIn = false;

  // Keyed caches — replaced only when the key changes.
  late Future<Map<String, dynamic>> _future;
  late Future<Map<String, dynamic>> _adherenceFuture;
  // Track the key that was used to build the cached future. The momentum flag is
  // part of the key so toggling the pref re-fetches with the right gate.
  int? _cachedRangeDays;
  bool? _cachedMomentumOptIn;
  String? _cachedAdherenceWeek;
  // Last-loaded insights for this range (cross-visit, via NutritionViewCache) —
  // shown instantly so a revisit doesn't flash the skeleton.
  Map<String, dynamic>? _cachedInsights;

  @override
  void initState() {
    super.initState();
    _ensureFutures();
    _loadMomentumPref();
  }

  /// Reads the opt-in prefs and, if the momentum gate differs from what the
  /// current future used, rebuilds the insights fetch. The coach-explains pref
  /// only flips a flag — it never re-fetches insights (the narrative is lazy).
  Future<void> _loadMomentumPref() async {
    final prefs = PreferencesService();
    final enabled = await prefs.getBehavioralMomentumEnabled();
    final coachExplains = await prefs.getCoachExplainsEnabled();
    if (!mounted) return;
    if (enabled == _momentumOptIn && coachExplains == _coachExplainsOptIn) return;
    setState(() {
      _coachExplainsOptIn = coachExplains;
      if (enabled != _momentumOptIn) {
        _momentumOptIn = enabled;
        _ensureFutures();
      }
    });
  }

  /// Only replaces a future when its inputs have changed.
  void _ensureFutures() {
    final needsInsights =
        _cachedRangeDays != _rangeDays ||
        _cachedMomentumOptIn != _momentumOptIn;
    if (needsInsights) {
      _cachedRangeDays = _rangeDays;
      _cachedMomentumOptIn = _momentumOptIn;
      final start = _end.subtract(Duration(days: _rangeDays - 1));
      final key = 'insights:$_rangeDays:m$_momentumOptIn';
      _cachedInsights = NutritionViewCache.instance.get<Map<String, dynamic>>(
        key,
      );
      _future = _repo
          .getInsights(start, _end, momentumOptIn: _momentumOptIn)
          .then((value) {
            NutritionViewCache.instance.set(key, value);
            return value;
          });
    }

    // Adherence is keyed on the current ISO week start.
    final weekStart = _end.subtract(Duration(days: (_end.weekday + 6) % 7));
    final weekKey = weekStart.toIso8601String().substring(0, 10);
    if (_cachedAdherenceWeek != weekKey) {
      _cachedAdherenceWeek = weekKey;
      _adherenceFuture = _repo.getWeeklyAdherence(weekStart);
    }
  }

  /// Lazily fetches the optional coach narrative for the CURRENT range. Called
  /// only when the user expands the explanation and only when opted in. Returns
  /// null on flag-off / gate-fail / any error, so the cards stand alone.
  Future<String?> _fetchNarrative() {
    final start = _end.subtract(Duration(days: _rangeDays - 1));
    return _repo.getCoachExplains(
      start,
      _end,
      momentumOptIn: _momentumOptIn,
    );
  }

  void _setRange(int days) {
    if (_rangeDays == days) return;
    Haptics.selection();
    setState(() {
      _rangeDays = days;
      _ensureFutures();
    });
  }

  /// True when nothing has been logged in the range: average calories are zero
  /// and no energy-balance day carries any intake. In that case every card
  /// would render as a gray zero, so we show an inviting first-run prompt.
  bool _hasNoData(Map averages, Map? energyBalance) {
    final avgCalories = (averages['calories'] as num?)?.toDouble() ?? 0;
    if (avgCalories > 0) return false;
    final days = (energyBalance?['days'] as List?) ?? const [];
    for (final raw in days) {
      if (raw is! Map) continue;
      final intake = (raw['intakeCalories'] as num?)?.toDouble() ?? 0;
      if (intake > 0) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Insights'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          // SWR: paint the last-cached insights instantly; only show the
          // skeleton on a true first load. The thin line signals revalidation.
          final data = snapshot.data ?? _cachedInsights;
          if (data == null) {
            return AppSkeleton.lines(semanticsLabel: 'Loading insights');
          }
          final refreshing =
              snapshot.connectionState == ConnectionState.waiting;
          final averages = data['averages'] as Map? ?? {};
          final energyBalance = data['energyBalance'] as Map?;

          // First run: nothing has been logged yet, so every metric would be a
          // bare gray zero. Greet the new user with an inviting prompt toward
          // their first food log instead of a screen full of empty zeros.
          final Widget body = _hasNoData(averages, energyBalance)
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    InsightsRangeSelectorCard(
                      selectedDays: _rangeDays,
                      onSelect: _setRange,
                    ),
                    const SizedBox(height: 48),
                    ScreenEmptyState(
                      icon: Icons.insights_outlined,
                      assetIcon: 'assets/icons/empty_chart.svg',
                      title: 'Your insights start with one log',
                      message:
                          'Log a few meals and we\'ll show your calorie and '
                          'macro trends, energy balance, and weekly adherence '
                          'here.',
                      actionLabel: 'Log your first food',
                      onAction: () => context.go('/nutrition'),
                    ),
                  ],
                )
              : _buildHub(energyBalance, averages, data);
          return RefreshLineOverlay(refreshing: refreshing, child: body);
        },
      ),
    );
  }

  /// Days within the range that have any logged intake — backs the data-quality
  /// meter and is read straight off the energy-balance series.
  int _loggedDays(List ebDays) => ebDays
      .whereType<Map>()
      .where((d) => ((d['intakeCalories'] as num?)?.toDouble() ?? 0) > 0)
      .length;

  Widget _buildHub(
    Map? energyBalance,
    Map averages,
    Map<String, dynamic> data,
  ) {
    final ebDays =
        (energyBalance is Map ? (energyBalance['days'] as List?) : null) ??
        const [];
    final recs = (data['recommendations'] as List?) ?? const [];
    // Prefer the backend's data-completeness summary; fall back to a client-side
    // recompute off the energy series so older responses still render honestly.
    final dc = data['dataCompleteness'] as Map?;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        InsightsRangeSelectorCard(
          selectedDays: _rangeDays,
          onSelect: _setRange,
        ),
        const SizedBox(height: 24),
        // Actionable coach recommendations lead the hub — they carry the energy
        // verdict (R1) and deep-link into real nutrition surfaces.
        InsightsCoachRecommendations(
          recommendations: recs,
          momentumOptIn: _momentumOptIn,
          // Item 6: only offer the lazy "Explain my numbers" affordance when the
          // user has opted in. The fetcher hits the SEPARATE lazy endpoint, so
          // the insights load path never pays for the narrative.
          coachExplainsOptIn: _coachExplainsOptIn,
          fetchNarrative: _coachExplainsOptIn ? _fetchNarrative : null,
        ),
        if (recs.isNotEmpty) const SizedBox(height: 24),
        if (energyBalance is Map) ...[
          InsightsEnergyBalanceCard(
            energyBalance: Map<String, dynamic>.from(energyBalance),
            compareToExpenditure: _energyCompareToExpenditure,
            onToggleCompare: (v) =>
                setState(() => _energyCompareToExpenditure = v),
          ),
          const SizedBox(height: 24),
        ],
        InsightsAveragesCard(rangeDays: _rangeDays, averages: averages),
        const SizedBox(height: 24),
        if (ebDays.isNotEmpty) ...[
          DataQualityCard(
            loggedDays:
                (dc?['daysLogged'] as num?)?.toInt() ?? _loggedDays(ebDays),
            totalDays: (dc?['daysInRange'] as num?)?.toInt() ?? ebDays.length,
          ),
          const SizedBox(height: 24),
        ],
        if (data['weight'] is Map) ...[
          InsightsWeightChangeCard(data: data['weight'] as Map),
          const SizedBox(height: 16),
        ],
        AdherenceCardSlot(future: _adherenceFuture),
        const SizedBox(height: 8),
        const _NextActionsSection(),
      ],
    );
  }
}

/// §12.3: flat section — UPPERCASE header + divider rows with a chevron,
/// no icon blocks, no big filled buttons.
class _NextActionsSection extends StatelessWidget {
  const _NextActionsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Next best actions'),
        SectionList(
          card: true,
          children: [
            _ActionRow(
              label: 'Adjust targets',
              onTap: () => context.push('/nutrition/strategy'),
            ),
            _ActionRow(
              label: 'View weight',
              onTap: () => context.push('/nutrition/weight'),
            ),
            _ActionRow(
              label: 'View expenditure',
              onTap: () => context.push('/nutrition/expenditure'),
            ),
            _ActionRow(
              label: 'Go to diary',
              onTap: () => context.go('/nutrition'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
