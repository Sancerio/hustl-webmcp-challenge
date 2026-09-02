import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'charts.dart';
import 'design.dart';
import 'evaluator_scope.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    return ListView(
      children: [
        const PageHeading(
          title: 'Train',
          subtitle: 'Your week, recovery, and next session in one place.',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final primary = Column(
              children: const [
                _WeeklyActivity(),
                SizedBox(height: 14),
                _ReadinessStrip(),
                SizedBox(height: 14),
                _RepeatWorkout(),
              ],
            );
            final secondary = Column(
              children: [
                const _CoachRecommendation(),
                const SizedBox(height: 14),
                const _TemplatePreview(),
                const SizedBox(height: 14),
                _VolumeTrend(proteinTarget: state.nutritionTargets.protein),
              ],
            );
            if (constraints.maxWidth < 760) {
              return Column(
                children: [primary, const SizedBox(height: 14), secondary],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: primary),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: secondary),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => context.go('/templates'),
            icon: const Icon(Icons.view_list_rounded),
            label: const Text('Browse templates'),
          ),
        ),
      ],
    );
  }
}

class _WeeklyActivity extends StatelessWidget {
  const _WeeklyActivity();

  @override
  Widget build(BuildContext context) => HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HustlSectionTitle('Weekly activity'),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              const RingMetric(value: 1, center: '4', caption: 'of 4'),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '52.3k kg',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text('Training volume this week'),
                    const SizedBox(height: 18),
                    if (constraints.maxWidth > 360) const WeekBars(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReadinessStrip extends StatelessWidget {
  const _ReadinessStrip();

  @override
  Widget build(BuildContext context) => const HustlPanel(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        Icon(Icons.favorite_rounded, color: hustleAmber, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Readiness',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text('Recharge', style: TextStyle(color: hustleAmber)),
        SizedBox(width: 12),
        Text('42', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _RepeatWorkout extends StatelessWidget {
  const _RepeatWorkout();

  @override
  Widget build(BuildContext context) => HustlPanel(
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF21243B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.replay_rounded, color: hustleLavender),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Repeat Lower strength',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text('6 exercises · about 60 min'),
            ],
          ),
        ),
        FilledButton(
          onPressed: () => context.go('/templates/template-strength-a'),
          child: const Text('View plan'),
        ),
      ],
    ),
  );
}

class _CoachRecommendation extends StatelessWidget {
  const _CoachRecommendation();

  @override
  Widget build(BuildContext context) => HustlPanel(
    borderColor: Color(0xFF665027),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusDot(color: hustleAmber),
            SizedBox(width: 8),
            Text('COACH', style: TextStyle(color: hustleAmber, fontSize: 12)),
          ],
        ),
        SizedBox(height: 14),
        Text(
          'Preserve strength. Trim fatigue.',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          'Use a lower-volume upper session today. Sleep and HRV are below baseline.',
        ),
      ],
    ),
  );
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview();

  @override
  Widget build(BuildContext context) => const HustlPanel(
    child: Row(
      children: [
        Icon(Icons.view_list_rounded, color: hustleBlue),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Templates', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 3),
              Text('Strength foundation · 3 days'),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: hustleMuted),
      ],
    ),
  );
}

class _VolumeTrend extends StatelessWidget {
  const _VolumeTrend({required this.proteinTarget});
  final double proteinTarget;

  @override
  Widget build(BuildContext context) => HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HustlSectionTitle('Volume trend'),
        const Sparkline(values: [32, 38, 35, 44, 47, 49, 52.3]),
        const SizedBox(height: 8),
        Text('Protein target ${proteinTarget.round()} g · recovery-aware'),
      ],
    ),
  );
}
