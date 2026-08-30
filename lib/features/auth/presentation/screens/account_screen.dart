import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';
import 'package:hustl_app/core/widgets/sync_prompt_card.dart';
import 'package:hustl_app/features/ai_proposals/presentation/widgets/proposal_count_chip.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_events_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/learn/domain/learn_articles.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_log_card.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/workout_events_service.dart';

import '../../domain/entities/auth_user.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/account_delete_section.dart';
import '../widgets/account_sheet.dart';

// ---------------------------------------------------------------------------
// Serializable DTO used by compute() — contains only primitive values so it
// can be sent across Dart isolate boundaries without issue.
// ---------------------------------------------------------------------------

class _SessionSetDto {
  const _SessionSetDto({
    required this.isCompleted,
    required this.weight,
    required this.reps,
  });
  final bool isCompleted;
  final double weight;
  final int reps;
}

class _SessionExerciseDto {
  const _SessionExerciseDto({
    required this.key,
    required this.isAssisted,
    required this.sets,
  });
  final String key;
  final bool isAssisted;
  final List<_SessionSetDto> sets;
}

class _SessionDto {
  const _SessionDto({
    required this.startTimeMs,
    required this.hasEndTime,
    required this.exercises,
  });
  final int startTimeMs;
  final bool hasEndTime;
  final List<_SessionExerciseDto> exercises;
}

class _AccountStatsInput {
  const _AccountStatsInput({
    required this.sessions,
    required this.weeklyGoal,
    required this.nowMs,
  });
  final List<_SessionDto> sessions;
  final int weeklyGoal;
  final int nowMs;
}

class _AccountStatsResult {
  const _AccountStatsResult({
    required this.sessionCount,
    required this.prCount,
    required this.goalWeeks,
  });
  final int sessionCount;
  final int prCount;
  final int goalWeeks;
}

// Top-level so it can be passed to compute().
_AccountStatsResult _computeAccountStats(_AccountStatsInput input) {
  final now = DateTime.fromMillisecondsSinceEpoch(input.nowMs);

  int sessionCount = 0;
  int prCount = 0;
  final Map<String, int> countByWeek = {};
  final Map<String, double> bestWeightByExercise = {};
  final Map<String, int> bestRepsAtWeightByExercise = {};

  for (final session in input.sessions) {
    if (session.hasEndTime) sessionCount++;

    for (final ex in session.exercises) {
      double bestWeight =
          bestWeightByExercise[ex.key] ?? double.negativeInfinity;
      int bestRepsAtWeight = bestRepsAtWeightByExercise[ex.key] ?? -1;
      for (final set in ex.sets) {
        if (!set.isCompleted) continue;
        if (ex.isAssisted && set.weight >= 0) continue;
        if (set.weight > bestWeight ||
            (set.weight == bestWeight && set.reps > bestRepsAtWeight)) {
          prCount++;
          bestWeight = set.weight;
          bestRepsAtWeight = set.reps;
        }
      }
      bestWeightByExercise[ex.key] = bestWeight;
      bestRepsAtWeightByExercise[ex.key] = bestRepsAtWeight;
    }

    final weekKey = _isoWeekKey(
      DateTime.fromMillisecondsSinceEpoch(session.startTimeMs),
    );
    countByWeek.update(weekKey, (v) => v + 1, ifAbsent: () => 1);
  }

  final currentWeekKey = _isoWeekKey(now);
  final sortedCountWeeks = countByWeek.keys.toList()
    ..sort((a, b) => _weekStartMs(a).compareTo(_weekStartMs(b)));
  int goalWeeks = 0;
  for (int i = sortedCountWeeks.length - 1; i >= 0; i--) {
    final k = sortedCountWeeks[i];
    final count = countByWeek[k] ?? 0;
    if (count >= input.weeklyGoal) {
      goalWeeks++;
      continue;
    }
    if (k == currentWeekKey) {
      final weekStartMs = _weekStartMs(k);
      final weekEndMs = weekStartMs + const Duration(days: 7).inMilliseconds;
      if (now.millisecondsSinceEpoch < weekEndMs) {
        continue;
      }
    }
    break;
  }

  return _AccountStatsResult(
    sessionCount: sessionCount,
    prCount: prCount,
    goalWeeks: goalWeeks,
  );
}

// Helper: ISO week key string for a DateTime — must be top-level for compute.
String _isoWeekKey(DateTime date) {
  final week = _isoWeekNumber(date);
  return '${date.year}-W${week.toString().padLeft(2, '0')}';
}

int _isoWeekNumber(DateTime date) {
  final jan4 = DateTime(date.year, 1, 4);
  final start = jan4.subtract(Duration(days: jan4.weekday - DateTime.monday));
  return ((date.difference(start).inDays) / 7).floor() + 1;
}

// Returns the Unix-millisecond timestamp of Monday for a week key 'YYYY-WWW'.
int _weekStartMs(String key) {
  final parts = key.split('-W');
  if (parts.length != 2) return 0;
  final year = int.tryParse(parts[0]);
  final week = int.tryParse(parts[1]);
  if (year == null || week == null) return 0;
  final jan4 = DateTime(year, 1, 4);
  final startOfWeek1 = jan4.subtract(
    Duration(days: jan4.weekday - DateTime.monday),
  );
  return startOfWeek1
      .add(Duration(days: (week - 1) * 7))
      .millisecondsSinceEpoch;
}

// ---------------------------------------------------------------------------

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.now});

  /// Optional override for the "current" time, primarily for tests.
  final DateTime? now;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final DateTime _referenceNow;
  bool _isStatsLoading = true;
  int _sessionCount = 0;
  int _prCount = 0;
  int _goalStreakWeeks = 0;
  AuthUser? _cachedUser;
  bool _prFlagRecomputeInFlight = false;
  // Set true while an account deletion is in flight so the auth listener can
  // distinguish a delete-driven sign-out (reset to home) from a plain sign-out.
  bool _deletionInProgress = false;
  StreamSubscription<WorkoutChange>? _workoutEventsSub;
  Timer? _statsRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _referenceNow = widget.now ?? DateTime.now();
    _loadStats();
    // The legacy PR-flag migration is O(all sessions) + a full ~1.6MB persist.
    // On web there are no isolates, so it runs inline on the single UI thread;
    // schedule it AFTER the first frame so the Account screen paints (skeleton →
    // content) before any heavy work begins. The migration itself yields between
    // chunks (see LocalWorkoutRepository.recomputeAllPrFlags), so even once it
    // starts it never blocks a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeRecomputeLegacyPrFlags();
    });
    _workoutEventsSub = GetIt.instance.isRegistered<WorkoutEventsService>()
        ? GetIt.instance<WorkoutEventsService>().stream.listen((change) {
            if (!mounted) return;
            if (change.kind == WorkoutChangeKind.created) return;
            _statsRefreshDebounce?.cancel();
            _statsRefreshDebounce = Timer(AppMotion.slow, _loadStats);
          })
        : null;
  }

  @override
  void dispose() {
    _workoutEventsSub?.cancel();
    _statsRefreshDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final repo = GetIt.instance<WorkoutRepository>();
      final prefs = GetIt.instance<PreferencesService>();
      // NOTE: the legacy PR-flag migration is NOT awaited here — it is scheduled
      // post-frame in initState. Stats load on their own so the screen paints
      // fast; the migration only rewrites the stored `isPr` flags, which does not
      // change the stat NUMBERS this screen displays (computed independently in
      // _computeAccountStats from the sets' weight/reps, not from isPr).
      final List<WorkoutSession> sessions = await repo.getWorkoutSessions();
      final weeklyGoal = await prefs.getWeeklyWorkoutGoal();

      // Build a serializable DTO so the O(sessions × exercises × sets) scan
      // runs on a background isolate (spec §6 "Heavy aggregation goes through
      // compute()").
      final sortedSessions = List<WorkoutSession>.from(sessions)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final dtos = sortedSessions
          .map(
            (s) => _SessionDto(
              startTimeMs: s.startTime.millisecondsSinceEpoch,
              hasEndTime: s.endTime != null,
              exercises: s.exercises
                  .map(
                    (ex) => _SessionExerciseDto(
                      key: _exerciseKey(ex.exercise),
                      isAssisted: ex.exercise.kind == ExerciseKind.assisted,
                      sets: ex.sets
                          .map(
                            (set) => _SessionSetDto(
                              isCompleted: set.isCompleted,
                              weight: set.weight,
                              reps: set.reps,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false);

      final result = await compute(
        _computeAccountStats,
        _AccountStatsInput(
          sessions: dtos,
          weeklyGoal: weeklyGoal,
          nowMs: _referenceNow.millisecondsSinceEpoch,
        ),
      );

      if (!mounted) return;
      setState(() {
        _sessionCount = result.sessionCount;
        _prCount = result.prCount;
        _goalStreakWeeks = result.goalWeeks;
        _isStatsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isStatsLoading = false;
      });
    }
  }

  /// One-time legacy migration that rewrites stored `isPr` flags. Pref-gated so
  /// it runs at most once per device, scheduled post-frame, and chunked inside
  /// the repository so it never blocks a frame on web. Best-effort: failures are
  /// swallowed and simply leave the pref unset for a later retry.
  Future<void> _maybeRecomputeLegacyPrFlags() async {
    if (_prFlagRecomputeInFlight) return;
    final repo = GetIt.instance<WorkoutRepository>();
    final prefs = GetIt.instance<PreferencesService>();
    final didRecompute = await prefs.getPrFlagsRecomputedV1();
    if (didRecompute) return;
    _prFlagRecomputeInFlight = true;
    try {
      await repo.recomputeAllPrFlags();
      await prefs.setPrFlagsRecomputedV1(true);
    } catch (_) {
      // Best effort: don't block the UI on legacy migration.
    } finally {
      _prFlagRecomputeInFlight = false;
    }
  }

  String _exerciseKey(Exercise exercise) {
    final canonical = exercise.canonicalKey;
    if (canonical != null && canonical.isNotEmpty) {
      return canonical;
    }
    final name = exercise.name.trim().toLowerCase();
    return name.isNotEmpty ? name : exercise.name;
  }

  Widget _buildHeader(
    BuildContext context, {
    String? name,
    String? email,
    String? photoUrl,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            backgroundColor: colors.surfaceContainerHighest,
            child: photoUrl == null
                ? Icon(Icons.person, color: colors.onSurfaceVariant)
                : null,
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name ?? 'Guest', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  email ?? 'Not signed in',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    if (_isStatsLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AccountSectionHeader('This week'),
          SectionList(
            card: true,
            children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.x1),
                  child: AppSkeleton(height: 20),
                ),
            ],
          ),
        ],
      );
    }

    // No completed sessions yet — instead of a bare gap (or stark zeros),
    // show a warm first-run card that invites the very first workout.
    if (_sessionCount == 0) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountSectionHeader('This week'),
          _FirstWorkoutStatsCard(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AccountSectionHeader('This week'),
        SectionList(
          card: true,
          children: [
            _StatRow(
              label: 'Workouts',
              value: NumberFormatUtil.formatInt(_sessionCount),
            ),
            _StatRow(
              label: 'Personal records',
              value: NumberFormatUtil.formatInt(_prCount),
            ),
            _StatRow(
              label: 'Goal weeks',
              value: _goalStreakWeeks == 0 ? '—' : '$_goalStreakWeeks wk',
            ),
          ],
        ),
      ],
    );
  }

  /// The Progress and Settings entries grouped into a single premium card —
  /// the Account screen is the home for settings (the menu button comment has
  /// always promised "Settings lives inside Account"); this card is the only
  /// entry point to the Settings route, which is otherwise unreachable.
  Widget _buildNavCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AccountSectionHeader('More'),
        SectionList(
          card: true,
          children: [
            _AccountNavRow(
              icon: Icons.trending_up,
              title: 'Progress',
              subtitle: 'Volume charts, PRs, and training history',
              // Progress is a TAB branch — switch the shell branch (go), don't
              // push it over the shell (which would strand a back button and
              // leave the bottom nav on Account).
              onTap: () => context.go('/progress'),
            ),
            _AccountNavRow(
              icon: Icons.favorite_outline,
              title: 'How recovery works',
              subtitle:
                  learnArticleBySlug(recoveryAndReadinessSlug)?.summary ?? '',
              onTap: () => context.push('/learn/$recoveryAndReadinessSlug'),
            ),
            _AccountNavRow(
              icon: Icons.auto_awesome_outlined,
              title: 'AI proposals',
              subtitle: 'Review changes your AI suggested',
              trailing: _proposalCountChip(),
              onTap: () => context.push('/proposals'),
            ),
            _AccountNavRow(
              icon: Icons.hub_outlined,
              title: 'Connected AI apps',
              subtitle: 'Manage Claude, Codex, ChatGPT access',
              onTap: () => context.push('/connections'),
            ),
            _AccountNavRow(
              icon: Icons.tune,
              title: 'App settings',
              subtitle: 'Units, sync, notifications, and sign-out',
              onTap: () => context.push('/settings'),
            ),
          ],
        ),
      ],
    );
  }

  /// A live pending-proposal count chip, hidden when zero. Bound to the shared
  /// [ProposalEventsService] notifier so it tracks polls/approvals.
  Widget? _proposalCountChip() {
    if (!GetIt.instance.isRegistered<ProposalEventsService>()) return null;
    final events = GetIt.instance<ProposalEventsService>();
    return ValueListenableBuilder<int>(
      valueListenable: events.pendingCount,
      builder: (context, count, _) => count <= 0
          ? const SizedBox.shrink()
          : ProposalCountChip(count: count),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Account'),
        centerTitle: true,
      ),
      child: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            _cachedUser = state.user;
          } else if (state is AuthUnauthenticated) {
            _cachedUser = null;
            // A successful deletion ends in the unauthenticated state; reset the
            // stack to home so the user lands on a clean signed-out app.
            if (_deletionInProgress) {
              _deletionInProgress = false;
              context.go('/');
            }
          } else if (state is AuthFailure) {
            final wasDeletingAccount = _deletionInProgress;
            // Deletion failed — clear the flag so a later sign-out isn't
            // mistaken for a delete.
            _deletionInProgress = false;
            if (wasDeletingAccount) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Couldn't delete account. ${state.message}"),
                ),
              );
            }
          }
        },
        builder: (context, state) {
          final cachedUser = _cachedUser;
          if ((state is AuthLoading || state is AuthHydrating) &&
              cachedUser == null) {
            return _buildLoadingBody(context);
          }
          if (state is AuthAuthenticated || cachedUser != null) {
            final user = state is AuthAuthenticated ? state.user : cachedUser!;
            return _buildAuthenticatedBody(context, user);
          }
          return _buildUnauthenticatedBody(context);
        },
      ),
    );
  }
}

// Spacing convenience — 12pt between stat cards.
const _kStatCardGap = SizedBox(width: 12.0);

extension on _AccountScreenState {
  Widget _buildAuthenticatedBody(BuildContext context, AuthUser user) {
    final header = _buildHeader(
      context,
      name: user.displayName,
      email: user.email,
      photoUrl: user.photoUrl,
    );

    // Left: identity + this-week stats. Right: weight logging + navigation.
    final leftBlocks = <Widget>[
      header,
      const SizedBox(height: AppSpacing.x2),
      _buildStatsRow(context),
    ];
    final deleteSection = AccountDeleteSection(
      onConfirmed: () => _deletionInProgress = true,
    );
    final rightBlocks = <Widget>[
      WeightLogCard(isSignedIn: true, now: _referenceNow),
      const SizedBox(height: AppSpacing.x3),
      _buildNavCard(context),
      deleteSection,
    ];

    return _buildScrollBody(
      context,
      narrowChildren: [
        header,
        const SizedBox(height: AppSpacing.x2),
        _buildStatsRow(context),
        const SizedBox(height: AppSpacing.x2),
        WeightLogCard(isSignedIn: true, now: _referenceNow),
        const SizedBox(height: AppSpacing.x3),
        _buildNavCard(context),
        deleteSection,
        const SizedBox(height: AppSpacing.x2),
      ],
      leftBlocks: leftBlocks,
      rightBlocks: rightBlocks,
    );
  }

  Widget _buildUnauthenticatedBody(BuildContext context) {
    // One sign-in surface, not two. The old layout stacked a "Sign in to sync"
    // card directly on top of a "Sign in to log weigh-ins" card — two identical
    // primary buttons competing. Weigh-ins, backup, and cross-device sync all
    // unlock with the same account, so they belong to a single prompt with one
    // primary CTA. (The full weight card returns once signed in.)
    final syncCard = SyncPromptCard(
      title: 'Sign in to save your progress',
      subtitle:
          'Back up your workouts and weigh-ins, and pick up on any device.',
      ctaLabel: 'Sign in',
      onCtaPressed: () => showLoginSheet(context),
      showBenefits: true,
    );

    // Left: sign-in prompt. Right: this-week stats + nav.
    final leftBlocks = <Widget>[
      _buildHeader(context),
      const SizedBox(height: AppSpacing.x2),
      syncCard,
    ];
    final rightBlocks = <Widget>[
      _buildStatsRow(context),
      const SizedBox(height: AppSpacing.x3),
      _buildNavCard(context),
    ];

    return _buildScrollBody(
      context,
      narrowChildren: [
        _buildHeader(context),
        const SizedBox(height: AppSpacing.x2),
        syncCard,
        const SizedBox(height: AppSpacing.x2),
        _buildStatsRow(context),
        const SizedBox(height: AppSpacing.x3),
        _buildNavCard(context),
        const SizedBox(height: AppSpacing.x2),
      ],
      leftBlocks: leftBlocks,
      rightBlocks: rightBlocks,
    );
  }

  /// One scroll view for both layouts. Below the wide breakpoint the body is
  /// the original single column (byte-for-byte). At and above it, the major
  /// blocks reflow into two side-by-side columns within the same scroll.
  Widget _buildScrollBody(
    BuildContext context, {
    required List<Widget> narrowChildren,
    required List<Widget> leftBlocks,
    required List<Widget> rightBlocks,
  }) {
    final isWide =
        MediaQuery.sizeOf(context).width >= ResponsiveCenter.wideBreakpoint;

    if (!isWide) {
      return SingleChildScrollView(
        padding: AppSpacing.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: narrowChildren,
        ),
      );
    }

    return SingleChildScrollView(
      padding: AppSpacing.screen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: leftBlocks,
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rightBlocks,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBody(BuildContext context) {
    return SingleChildScrollView(
      padding: AppSpacing.screen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton
          const AppSkeleton(height: 110),
          const SizedBox(height: AppSpacing.x2),
          // Stats row skeleton
          Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                const Expanded(child: AppSkeleton(height: 84)),
                if (i < 2) _kStatCardGap,
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          const AppSkeleton(height: 72),
          const SizedBox(height: AppSpacing.x2),
        ],
      ),
    );
  }
}

/// Section header for the account screen. The body already insets by
/// `AppSpacing.screen`, so this drops [SectionHeader]'s horizontal padding to
/// keep rows aligned to the screen edge.
class _AccountSectionHeader extends StatelessWidget {
  const _AccountSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title,
      padding: const EdgeInsets.only(top: AppSpacing.x3, bottom: AppSpacing.x1),
    );
  }
}

/// First-run stand-in for the "This week" stats card. A brand-new account has
/// no completed sessions, so rather than three gray dashes (or an empty gap)
/// this card offers a soft blue-tinted glyph, an encouraging line, and a single
/// blue CTA toward the first workout — the Wave I welcome voice.
class _FirstWorkoutStatsCard extends StatelessWidget {
  const _FirstWorkoutStatsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SectionList(
      card: true,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.10),
                  ),
                  child: Icon(
                    Icons.bolt_outlined,
                    size: 24,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your first workout starts the story',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Log a session and your workouts, records, and goal '
                        'weeks show up here.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            // Tonal, not filled: on the guest screen the sole filled-blue CTA is
            // "Sign in" — this stays a clear but secondary nudge so the two
            // don't compete. For a signed-in first-run it reads the same.
            FilledButton.tonalIcon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Start a workout'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A flat aligned stat row: label left (15/w500), value right (15/w600
/// tabular). The §12.1 list voice.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            Text(value, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

/// A navigation row inside the grouped "More" card: quiet icon, 15px title, a
/// caption, and a trailing chevron. Rows read as premium objects inside the
/// surrounding [SectionList] card, not bare ledger lines.
class _AccountNavRow extends StatelessWidget {
  const _AccountNavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Optional widget shown just before the chevron (e.g. a count chip).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      container: true,
      button: true,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
            child: Row(
              children: [
                Icon(icon, size: 22, color: colors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  trailing!,
                  const SizedBox(width: AppSpacing.x1),
                ],
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
