import 'package:flutter/material.dart';

import 'design.dart';

class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const PageHeading(
        title: 'Recover',
        subtitle: 'A bounded, non-medical view of the signals shaping today.',
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xFFFFE9C7),
                  child: Text(
                    '42',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text('Recharge today\nHigh-confidence baseline'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const _Signal(
              label: 'Sleep',
              value: '5h 18m',
              baseline: '7h 12m baseline',
            ),
            const _Signal(
              label: 'HRV',
              value: '47 ms',
              baseline: '57 ms baseline',
            ),
            const _Signal(
              label: 'Resting HR',
              value: '61 bpm',
              baseline: '54 bpm baseline',
            ),
          ],
        ),
      ),
    ],
  );
}

class _Signal extends StatelessWidget {
  const _Signal({
    required this.label,
    required this.value,
    required this.baseline,
  });

  final String label;
  final String value;
  final String baseline;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value),
            Text(baseline, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    ),
  );
}
