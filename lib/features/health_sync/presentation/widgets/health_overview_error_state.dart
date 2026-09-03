import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/screen_empty_state.dart';
import '../bloc/health_overview_bloc.dart';

class HealthOverviewErrorState extends StatelessWidget {
  const HealthOverviewErrorState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    // Kind error treatment: a soft tinted holder + a plain-language headline,
    // with the technical cause demoted to the supportive line, and a single
    // blue "Try again" that re-runs the refresh event.
    return ScreenEmptyState(
      icon: Icons.favorite_outline,
      title: "We couldn't load your health data",
      message: message ?? 'Something interrupted the sync. Give it another go.',
      actionLabel: 'Try again',
      onAction: () => context.read<HealthOverviewBloc>().add(
        const HealthOverviewRefreshed(),
      ),
    );
  }
}
