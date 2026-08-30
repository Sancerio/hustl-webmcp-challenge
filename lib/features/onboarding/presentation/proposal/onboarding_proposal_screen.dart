import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/starter_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_bloc.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_event.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_state.dart';
import 'package:hustl_app/features/onboarding/domain/onboarding_telemetry.dart';

import 'onboarding_proposal_views.dart';
import 'starter_proposal_card.dart';

/// The onboarding "AI magic moment": consent → draft a first-party starter
/// proposal from the user's own logs → render it (with "Why this?" lineage and
/// the improving-estimate honesty) → approve it through the EXISTING
/// [ProposalsBloc] pipeline (no fork). Every branch (not-enough-data, error,
/// approve failure) offers a retry or a graceful exit, so it never dead-ends.
class OnboardingProposalScreen extends StatelessWidget {
  const OnboardingProposalScreen({
    super.key,
    this.repository,
    this.preferences,
    this.bloc,
  });

  /// Injectable for tests; default to the GetIt-registered instances.
  final ProposalsRepository? repository;
  final PreferencesService? preferences;
  final ProposalsBloc? bloc;

  @override
  Widget build(BuildContext context) {
    final view = _OnboardingProposalView(
      repository: repository,
      preferences: preferences,
    );
    final injected = bloc;
    if (injected != null) {
      return BlocProvider<ProposalsBloc>.value(value: injected, child: view);
    }
    return BlocProvider<ProposalsBloc>(
      create: (_) => GetIt.instance<ProposalsBloc>(),
      child: view,
    );
  }
}

enum _Stage { consent, generating, ready, notEnough, error, success }

class _OnboardingProposalView extends StatefulWidget {
  const _OnboardingProposalView({this.repository, this.preferences});

  final ProposalsRepository? repository;
  final PreferencesService? preferences;

  @override
  State<_OnboardingProposalView> createState() =>
      _OnboardingProposalViewState();
}

class _OnboardingProposalViewState extends State<_OnboardingProposalView> {
  late final ProposalsRepository _repository =
      widget.repository ?? GetIt.instance<ProposalsRepository>();
  late final PreferencesService _prefs =
      widget.preferences ?? GetIt.instance<PreferencesService>();

  late _Stage _stage;
  ProposalDetail? _detail;
  StarterProposalNotEnoughData? _notEnough;
  StarterProposalError? _error;

  // A stable idempotency key per approve attempt, reused on retry.
  String? _idempotencyKey;
  bool _approveDispatched = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Consent is REQUIRED before any draft is generated. Skip the gate only when
    // the user has already consented in a prior visit.
    if (_prefs.onboardingProposalConsent) {
      _stage = _Stage.generating;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _generate();
      });
    } else {
      _stage = _Stage.consent;
    }
  }

  Future<void> _acceptConsent() async {
    try {
      await _prefs.setOnboardingProposalConsent(true);
    } catch (_) {}
    if (!mounted) return;
    await _generate();
  }

  Future<void> _generate() async {
    setState(() => _stage = _Stage.generating);
    final result = await _repository.generateStarter();
    if (!mounted) return;
    switch (result) {
      case StarterProposalSucceeded(:final proposal):
        _detail = proposal;
        OnboardingTelemetry.instance.proposalShown();
        // Mark seen once a real proposal is shown so the once-only trigger never
        // re-prompts. Best-effort.
        try {
          await _prefs.setOnboardingProposalSeen(true);
        } catch (_) {}
        if (!mounted) return;
        setState(() => _stage = _Stage.ready);
      case StarterProposalNotEnoughData():
        _notEnough = result;
        setState(() => _stage = _Stage.notEnough);
      case StarterProposalError():
        _error = result;
        setState(() => _stage = _Stage.error);
    }
  }

  void _approve() {
    final detail = _detail;
    if (detail == null) return;
    _idempotencyKey ??= '${detail.id}-${DateTime.now().millisecondsSinceEpoch}';
    _approveDispatched = true;
    setState(() => _busy = true);
    // Dispatch the EXISTING approve event — the bloc handler runs the count
    // push, template sync / diary refresh, and the approved-counter bump.
    context.read<ProposalsBloc>().add(
      ApproveProposal(detail.id, idempotencyKey: _idempotencyKey!),
    );
  }

  Future<void> _exit() async {
    final router = GoRouter.of(context);
    try {
      await _prefs.setOnboardingProposalSeen(true);
    } catch (_) {}
    if (!mounted) return;
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  void _onBlocState(BuildContext context, ProposalsState state) {
    if (!_approveDispatched) return;
    if (state is ProposalsLoaded) {
      if (state.inFlightIds.contains(_detail?.id)) return;
      _approveDispatched = false;
      OnboardingTelemetry.instance.proposalApproved();
      setState(() {
        _busy = false;
        _stage = _Stage.success;
      });
    } else if (state is ProposalsFailure) {
      _approveDispatched = false;
      setState(() => _busy = false);
      HustlSnack.show(context, state.message, variant: HustlSnackVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProposalsBloc, ProposalsState>(
      listener: _onBlocState,
      child: Scaffold(
        appBar: AppBar(title: const Text('Your coach')),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_stage) {
      case _Stage.consent:
        return ProposalConsentGate(onAccept: _acceptConsent, onDecline: _exit);
      case _Stage.generating:
        return const ProposalStatusView(
          icon: Icons.auto_awesome_rounded,
          title: 'Drafting your plan',
          message: 'Reading your logs to draft a starter plan…',
          busy: true,
        );
      case _Stage.ready:
        return _readyView(context);
      case _Stage.notEnough:
        return ProposalStatusView(
          icon: Icons.eco_outlined,
          title: 'Your coach is still learning',
          message:
              _notEnough?.humanMessage ??
              'Keep logging your workouts — your coach needs a little more to '
                  'draft a plan worth approving.',
          primaryLabel: 'Keep logging',
          onPrimary: _exit,
        );
      case _Stage.error:
        return ProposalStatusView(
          icon: Icons.cloud_off_rounded,
          title: "That didn't go through",
          message: _error?.message ?? "We couldn't draft your plan just now.",
          primaryLabel: 'Try again',
          onPrimary: _generate,
          secondaryLabel: 'Not now',
          onSecondary: _exit,
        );
      case _Stage.success:
        return ProposalStatusView(
          icon: Icons.check_circle_rounded,
          title: 'Your plan is set',
          message:
              'Your coach will keep sharpening it every time you log. You can '
              'review proposals anytime.',
          primaryLabel: 'Done',
          onPrimary: _exit,
        );
    }
  }

  Widget _readyView(BuildContext context) {
    final detail = _detail!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.x3),
      children: [
        const ProposalHero(
          title: 'Your coach has a proposal',
          subtitle:
              'A starter plan drafted from your own logs. Nothing changes '
              'until you approve.',
        ),
        const SizedBox(height: AppSpacing.x3),
        StarterProposalCard(
          proposal: detail,
          lineageText: 'Based on the sessions and goals you’ve logged',
        ),
        const SizedBox(height: AppSpacing.x2),
        ProposalWhyThis(proposal: detail),
        const SizedBox(height: AppSpacing.x2),
        const ProposalImprovingEstimateNote(),
        const SizedBox(height: AppSpacing.x3),
        FilledButton.icon(
          onPressed: _busy ? null : _approve,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Approve'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.controlRadius,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        TextButton(
          onPressed: _busy ? null : _exit,
          child: const Text('Not now'),
        ),
      ],
    );
  }
}
