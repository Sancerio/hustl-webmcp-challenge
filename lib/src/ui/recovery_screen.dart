import 'package:flutter/material.dart';

import 'charts.dart';
import 'design.dart';

class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Row(
        children: [
          Expanded(
            child: PageHeading(
              title: 'Biology',
              subtitle: 'The signals shaping today, grounded in your baseline.',
            ),
          ),
          StatusDot(color: hustleEmerald),
          SizedBox(width: 8),
          Text('Live health sync'),
        ],
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          const conditions = Column(
            children: [
              _ConditionsCard(),
              SizedBox(height: 14),
              _InstrumentsCard(),
            ],
          );
          const trends = Column(
            children: [_BodyWeightCard(), SizedBox(height: 14), _InsightCard()],
          );
          if (constraints.maxWidth < 760) {
            return const Column(
              children: [conditions, SizedBox(height: 14), trends],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: conditions),
              SizedBox(width: 14),
              Expanded(flex: 5, child: trends),
            ],
          );
        },
      ),
    ],
  );
}

class _ConditionsCard extends StatelessWidget {
  const _ConditionsCard();

  @override
  Widget build(BuildContext context) => HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TODAY CONDITIONS',
          style: TextStyle(color: hustleMuted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RingMetric(
              value: .42,
              center: '42',
              caption: 'readiness',
              color: hustleAmber,
              size: 118,
            ),
            SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recharge.',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Sleep and HRV are below baseline. Reduce volume, keep the important work.',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: const LinearProgressIndicator(
            value: .74,
            minHeight: 7,
            color: hustleAmber,
          ),
        ),
        const SizedBox(height: 8),
        const Text('High-confidence baseline · 21 days of data'),
      ],
    ),
  );
}

class _InstrumentsCard extends StatelessWidget {
  const _InstrumentsCard();

  @override
  Widget build(BuildContext context) => const HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HustlSectionTitle('Instruments'),
        _Signal(
          label: 'Sleep',
          value: '5h 18m',
          baseline: '7h 12m',
          icon: Icons.bedtime_outlined,
        ),
        Divider(),
        _Signal(
          label: 'HRV',
          value: '47 ms',
          baseline: '57 ms',
          icon: Icons.monitor_heart_outlined,
        ),
        Divider(),
        _Signal(
          label: 'Resting HR',
          value: '61 bpm',
          baseline: '54 bpm',
          icon: Icons.favorite_outline_rounded,
        ),
      ],
    ),
  );
}

class _Signal extends StatelessWidget {
  const _Signal({
    required this.label,
    required this.value,
    required this.baseline,
    required this.icon,
  });
  final String label;
  final String value;
  final String baseline;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Icon(icon, color: hustleBlue, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              'baseline $baseline',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    ),
  );
}

class _BodyWeightCard extends StatelessWidget {
  const _BodyWeightCard();

  @override
  Widget build(BuildContext context) => const HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HustlSectionTitle('Body weight'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '78.4',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 5),
            Padding(padding: EdgeInsets.only(bottom: 4), child: Text('kg')),
            Spacer(),
            Text('−0.3 kg', style: TextStyle(color: hustleEmerald)),
          ],
        ),
        SizedBox(height: 18),
        Sparkline(
          values: [79.1, 78.9, 79.0, 78.7, 78.8, 78.6, 78.4],
          color: hustleLavender,
          height: 92,
        ),
        SizedBox(height: 8),
        Text('7-day trend'),
      ],
    ),
  );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard();

  @override
  Widget build(BuildContext context) => const HustlPanel(
    borderColor: Color(0xFF2D4C45),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusDot(color: hustleEmerald),
            SizedBox(width: 8),
            Text(
              'INSIGHT',
              style: TextStyle(color: hustleEmerald, fontSize: 12),
            ),
          ],
        ),
        SizedBox(height: 12),
        Text(
          'Your strength is holding while weight trends down.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text('Keep today controlled and protect Wednesday football recovery.'),
      ],
    ),
  );
}
