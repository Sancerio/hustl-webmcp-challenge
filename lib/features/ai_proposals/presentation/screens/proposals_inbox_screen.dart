import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/navigation/route_observer.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../../nutrition_tracker/presentation/widgets/segmented_pill_selector.dart';
import '../bloc/proposal_history_cubit.dart';
import '../bloc/proposals_bloc.dart';
import '../bloc/proposals_event.dart';
import '../bloc/proposals_state.dart';
import '../widgets/proposal_history_list.dart';
import '../widgets/proposal_inbox_row.dart';

/// The pending-proposal inbox, with a state-only `Pending · History` tab.
/// Pushes over the shell at `/proposals` — history is NOT a separate route.
class ProposalsInboxScreen extends StatelessWidget {
  const ProposalsInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ProposalsBloc>(
          create: (_) =>
              GetIt.instance<ProposalsBloc>()..add(const LoadProposals()),
        ),
        BlocProvider<ProposalHistoryCubit>(
          create: (_) => GetIt.instance<ProposalHistoryCubit>(),
        ),
      ],
      child: const _ProposalsInboxView(),
    );
  }
}

enum _ProposalsTab { pending, history }

class _ProposalsInboxView extends StatefulWidget {
  const _ProposalsInboxView();

  @override
  State<_ProposalsInboxView> createState() => _ProposalsInboxViewState();
}

class _ProposalsInboxViewState extends State<_ProposalsInboxView>
    with RouteAware {
  _ProposalsTab _tab = _ProposalsTab.pending;
  bool _historyLoaded = false;

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
    try {
      routeObserver.unsubscribe(this);
    } catch (_) {}
    super.dispose();
  }

  /// Returning from the pushed approval screen — that screen runs its own bloc,
  /// so refresh here to drop any row the user just approved/rejected.
  @override
  void didPopNext() {
    if (!mounted) return;
    context.read<ProposalsBloc>().add(const RefreshProposals());
    if (_historyLoaded) {
      context.read<ProposalHistoryCubit>().refresh();
    }
  }

  void _selectTab(_ProposalsTab tab) {
    setState(() => _tab = tab);
    if (tab == _ProposalsTab.history && !_historyLoaded) {
      _historyLoaded = true;
      context.read<ProposalHistoryCubit>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // The pending count is this screen's most useful glance ("do I have
    // anything to review?"). Rebuilds only when the count changes.
    final pendingCount = context.select<ProposalsBloc, int?>(
      (b) => b.state is ProposalsLoaded
          ? (b.state as ProposalsLoaded).items.length
          : null,
    );
    final pendingLabel = (pendingCount != null && pendingCount > 0)
        ? 'Pending · $pendingCount'
        : 'Pending';
    return MainScaffold(
      appBar: AppBar(title: const Text('AI activity')),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x2,
              AppSpacing.x2,
              AppSpacing.x2,
              AppSpacing.x1,
            ),
            child: SegmentedPillSelector<_ProposalsTab>(
              options: const [_ProposalsTab.pending, _ProposalsTab.history],
              selected: _tab,
              onSelect: _selectTab,
              labels: {
                _ProposalsTab.pending: pendingLabel,
                _ProposalsTab.history: 'History',
              },
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : AppMotion.medium,
              switchInCurve: AppMotion.enterCurve,
              switchOutCurve: AppMotion.exitCurve,
              transitionBuilder: appFadeSlideTransition,
              child: _tab == _ProposalsTab.pending
                  ? const _PendingTab(key: ValueKey('pending'))
                  : const ProposalHistoryList(key: ValueKey('history')),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingTab extends StatelessWidget {
  const _PendingTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProposalsBloc, ProposalsState>(
      builder: (context, state) {
        if (state is ProposalsLoading || state is ProposalsInitial) {
          return const HustlInlineSkeleton();
        }
        if (state is ProposalsFailure) {
          return ScreenEmptyState(
            icon: Icons.cloud_off_rounded,
            title: "We couldn't load proposals",
            message: state.message,
            actionLabel: 'Try again',
            onAction: () =>
                context.read<ProposalsBloc>().add(const LoadProposals()),
          );
        }
        final loaded = state as ProposalsLoaded;
        if (loaded.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async =>
                context.read<ProposalsBloc>().add(const RefreshProposals()),
            child: ListView(
              children: const [
                SizedBox(height: 80),
                ScreenEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No proposals to review',
                  message:
                      'When your connected AI suggests a workout-template '
                      'or nutrition-target change, it shows up here for you '
                      'to approve.',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              context.read<ProposalsBloc>().add(const RefreshProposals()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              SectionList(
                card: true,
                children: [
                  for (final p in loaded.items)
                    ProposalInboxRow(
                      proposal: p,
                      isStale: loaded.staleIds.contains(p.id),
                      isBusy: loaded.inFlightIds.contains(p.id),
                      onTap: () => context.push('/proposals/${p.id}'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
