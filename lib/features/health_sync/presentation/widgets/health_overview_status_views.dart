import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/screen_empty_state.dart';
import '../bloc/health_permissions_bloc.dart';

class HealthOverviewUnavailableView extends StatelessWidget {
  const HealthOverviewUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    // Informational, not alarmist: a neutral/primary-tinted holder rather than
    // error red — this is just a capability note for the current device.
    return const ScreenEmptyState(
      icon: Icons.health_and_safety_outlined,
      title: 'Health data needs a supported device',
      message:
          'Apple Health is iOS only and Health Connect is Android only. Open '
          'Hustl on one of those to sync your body metrics.',
    );
  }
}

class HealthPermissionsFailureView extends StatelessWidget {
  const HealthPermissionsFailureView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // Kind error treatment with the technical cause demoted to the supportive
    // line and a single blue "Try again" that re-checks permission status.
    return ScreenEmptyState(
      icon: Icons.health_and_safety_outlined,
      title: "We couldn't check health permissions",
      message: message,
      actionLabel: 'Try again',
      onAction: () => context.read<HealthPermissionsBloc>().add(
        const HealthPermissionsStatusRequested(),
      ),
    );
  }
}
