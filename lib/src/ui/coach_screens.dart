import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/models.dart';
import 'design.dart';
import 'evaluator_scope.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    final pending = state.pending;
    final recent = state.recent;
    return ListView(
      children: [
        PageHeading(
          title: 'Coach',
          subtitle: pending.isEmpty
              ? 'No proposals are waiting. AI suggestions appear here for your decision.'
              : '${pending.length} proposal${pending.length == 1 ? '' : 's'} waiting for your review.',
        ),
        if (pending.isEmpty && recent.isEmpty)
          const SurfaceCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 38, color: muted),
                  SizedBox(height: 12),
                  Text('Your review queue is clear.'),
                ],
              ),
            ),
          ),
        for (final proposal in pending) ...[
          _ProposalRow(proposal: proposal),
          const SizedBox(height: 12),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Recent decisions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final proposal in recent) ...[
            _ProposalRow(proposal: proposal),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _ProposalRow extends StatelessWidget {
  const _ProposalRow({required this.proposal});

  final CoachProposal proposal;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(8),
    child: ListTile(
      onTap: () => context.go('/proposals/${proposal.id}'),
      leading: CircleAvatar(child: Icon(_icon(proposal.kind))),
      title: Text(proposal.title),
      subtitle: Text(_status(proposal.status)),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );

  IconData _icon(ProposalKind kind) => switch (kind) {
    ProposalKind.nutritionTargets => Icons.tune_rounded,
    ProposalKind.foodLog => Icons.restaurant_rounded,
    ProposalKind.foodLogEdit => Icons.edit_outlined,
    ProposalKind.foodLogDelete => Icons.delete_outline_rounded,
    ProposalKind.templateCreate => Icons.view_list_rounded,
    ProposalKind.templateEdit => Icons.edit_outlined,
  };

  String _status(ProposalStatus status) => switch (status) {
    ProposalStatus.pending => 'Pending · needs your review',
    ProposalStatus.applied => 'Applied',
    ProposalStatus.rejected => 'Dismissed',
    ProposalStatus.conflicted => 'No longer current',
  };
}

class ProposalDetailScreen extends StatelessWidget {
  const ProposalDetailScreen({super.key, required this.proposalId});

  final String proposalId;

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    final proposal = state.proposalById(proposalId);
    if (proposal == null) return const _NotFound(label: 'Proposal not found');
    final pending = proposal.status == ProposalStatus.pending;
    return ListView(
      children: [
        TextButton.icon(
          onPressed: () => context.go('/proposals'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to Coach'),
        ),
        const SizedBox(height: 12),
        PageHeading(
          title: proposal.title,
          subtitle: pending
              ? 'Review the exact proposed change. Nothing is live yet.'
              : 'This decision is terminal and no longer actionable.',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Proposed diff',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _ProposalDiff(proposal: proposal),
            ],
          ),
        ),
        if (pending) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => state.apply(proposal.id),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Apply'),
              ),
              OutlinedButton.icon(
                onPressed: () => state.dismiss(proposal.id),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProposalDiff extends StatelessWidget {
  const _ProposalDiff({required this.proposal});

  final CoachProposal proposal;

  @override
  Widget build(BuildContext context) => switch (proposal.kind) {
    ProposalKind.nutritionTargets => _NutritionTargetDiff(
      payload: proposal.payload,
    ),
    ProposalKind.foodLog => _FoodLogDiff(payload: proposal.payload),
    ProposalKind.foodLogEdit => _FoodEditDiff(payload: proposal.payload),
    ProposalKind.foodLogDelete => _FoodDeleteDiff(payload: proposal.payload),
    ProposalKind.templateCreate ||
    ProposalKind.templateEdit => _TemplateDiff(payload: proposal.payload),
  };
}

class _NutritionTargetDiff extends StatelessWidget {
  const _NutritionTargetDiff({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final live = EvaluatorScope.of(context).nutritionTargets;
    final before = payload['baseTargets'] is Map
        ? Map<String, Object?>.from(payload['baseTargets']! as Map)
        : live.toJson();
    return Column(
      children: [
        _ChangeRow(
          label: 'Calories',
          before: '${_displayNumber(before['calories'])} kcal',
          after: '${_displayNumber(payload['caloriesTarget'])} kcal',
        ),
        _ChangeRow(
          label: 'Protein',
          before: '${_displayNumber(before['proteinGrams'])} g',
          after: '${_displayNumber(payload['proteinTarget'])} g',
        ),
        _ChangeRow(
          label: 'Carbs',
          before: '${_displayNumber(before['carbsGrams'])} g',
          after: '${_displayNumber(payload['carbsTarget'])} g',
        ),
        _ChangeRow(
          label: 'Fat',
          before: '${_displayNumber(before['fatGrams'])} g',
          after: '${_displayNumber(payload['fatTarget'])} g',
          showDivider: false,
        ),
        if (payload['rationale'] case final String rationale) ...[
          const SizedBox(height: 18),
          _Note(label: 'Coach rationale', text: rationale),
        ],
      ],
    );
  }
}

class _FoodLogDiff extends StatelessWidget {
  const _FoodLogDiff({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final items = (payload['items']! as List).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine(
          icon: Icons.calendar_today_outlined,
          label: 'Log date',
          value: '${payload['date']}',
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < items.length; index++) ...[
          _FoodItemCard(item: items[index].cast<String, Object?>()),
          if (index != items.length - 1) const SizedBox(height: 10),
        ],
        if (payload['note'] case final String note) ...[
          const SizedBox(height: 16),
          _Note(label: 'Note', text: note),
        ],
      ],
    );
  }
}

class _FoodEditDiff extends StatelessWidget {
  const _FoodEditDiff({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    final targetId = payload['targetEntryId']! as String;
    final entry = state.foodEntries
        .where((candidate) => candidate.id == targetId)
        .firstOrNull;
    final changes = (payload['changes']! as Map).cast<String, Object?>();
    final before = payload['targetEntrySnapshot'] is Map
        ? Map<String, Object?>.from(payload['targetEntrySnapshot']! as Map)
        : entry?.toJson() ?? const <String, Object?>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine(
          icon: Icons.restaurant_outlined,
          label: 'Meal',
          value: before['foodName'] as String? ?? 'Selected diary entry',
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < changes.length; index++)
          _ChangeRow(
            label: _fieldLabel(changes.keys.elementAt(index)),
            before: _fieldValue(
              changes.keys.elementAt(index),
              before[changes.keys.elementAt(index)],
            ),
            after: _fieldValue(
              changes.keys.elementAt(index),
              changes.values.elementAt(index),
            ),
            showDivider: index != changes.length - 1,
          ),
      ],
    );
  }
}

class _FoodDeleteDiff extends StatelessWidget {
  const _FoodDeleteDiff({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final targetId = payload['targetEntryId']! as String;
    final liveEntry = EvaluatorScope.of(
      context,
    ).foodEntries.where((candidate) => candidate.id == targetId).firstOrNull;
    final snapshot = payload['targetEntrySnapshot'] is Map
        ? Map<String, Object?>.from(payload['targetEntrySnapshot']! as Map)
        : liveEntry?.toJson();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3B8B3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFA8322A),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Entry scheduled for removal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (snapshot == null) ...[
            const SizedBox(height: 8),
            const Text('Remove this entry from the diary.'),
          ] else ...[
            if (snapshot['date'] case final String date) ...[
              const SizedBox(height: 14),
              _SummaryLine(
                icon: Icons.calendar_today_outlined,
                label: 'Log date',
                value: date,
              ),
            ],
            if (snapshot['consumedAt'] case final String consumedAt) ...[
              const SizedBox(height: 10),
              _SummaryLine(
                icon: Icons.schedule_rounded,
                label: 'Consumed at',
                value: consumedAt,
              ),
            ],
            const SizedBox(height: 14),
            _FoodItemCard(item: snapshot),
            if (snapshot['note'] case final String note) ...[
              const SizedBox(height: 14),
              _Note(label: 'Note', text: note),
            ],
          ],
        ],
      ),
    );
  }
}

class _TemplateDiff extends StatelessWidget {
  const _TemplateDiff({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final plan = (payload['plan']! as Map).cast<String, Object?>();
    final exercises = (plan['exercises']! as List).cast<Map>();
    final fixtures = EvaluatorScope.of(context).exercises;
    String nameFor(String id) =>
        fixtures
            .where((exercise) => exercise.id == id)
            .map((exercise) => exercise.name)
            .firstOrNull ??
        id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine(
          icon: Icons.view_list_outlined,
          label: 'Template',
          value: '${plan['name']}',
        ),
        if (plan['description'] case final String description) ...[
          const SizedBox(height: 14),
          _Note(label: 'Purpose', text: description),
        ],
        const SizedBox(height: 18),
        Text(
          '${exercises.length} exercise${exercises.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < exercises.length; index++) ...[
          Builder(
            builder: (context) {
              final exercise = exercises[index].cast<String, Object?>();
              return _ExercisePlanRow(
                name: nameFor(exercise['exerciseId']! as String),
                exercise: exercise,
              );
            },
          ),
          if (index != exercises.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _FoodItemCard extends StatelessWidget {
  const _FoodItemCard({required this.item});

  final Map<String, Object?> item;

  @override
  Widget build(BuildContext context) {
    final optionalDetails = <(String, String)>[
      if (item['fiberGrams'] case final num value)
        ('Fibre', '${_displayNumber(value)} g'),
      if (item['sugarGrams'] case final num value)
        ('Sugar', '${_displayNumber(value)} g'),
      if (item['sodiumMg'] case final num value)
        ('Sodium', '${_displayNumber(value)} mg'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(child: Icon(Icons.restaurant_rounded, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['foodName']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Serving: ${_displayNumber(item['servingGrams'])} g · Calories: ${_displayNumber(item['calories'])} kcal',
                ),
                const SizedBox(height: 3),
                Text(
                  'Protein: ${_displayNumber(item['proteinGrams'])} g · Carbs: ${_displayNumber(item['carbsGrams'])} g · Fat: ${_displayNumber(item['fatGrams'])} g',
                ),
                for (final detail in optionalDetails) ...[
                  const SizedBox(height: 3),
                  Text('${detail.$1}: ${detail.$2}'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExercisePlanRow extends StatelessWidget {
  const _ExercisePlanRow({required this.name, required this.exercise});

  final String name;
  final Map<String, Object?> exercise;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: canvas,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.fitness_center_rounded, color: blue, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                '${exercise['sets']} sets · ${exercise['repsTarget'] ?? '—'} reps · RPE ${exercise['rpeTarget'] ?? '—'} · ${exercise['restTimerSeconds']}s rest',
              ),
              if (exercise['slug'] case final String slug) ...[
                const SizedBox(height: 3),
                Text('Slug: $slug'),
              ],
              if (exercise['weightTarget'] case final num weight) ...[
                const SizedBox(height: 3),
                Text('Target weight: ${_displayNumber(weight)} kg'),
              ],
              if (exercise['notes'] case final String notes) ...[
                const SizedBox(height: 3),
                Text('Notes: $notes'),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.label,
    required this.before,
    required this.after,
    this.showDivider = true,
  });

  final String label;
  final String before;
  final String after;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const beforeStyle = TextStyle(color: muted);
            const afterStyle = TextStyle(
              color: blue,
              fontWeight: FontWeight.w700,
            );
            const arrow = Padding(
              padding: EdgeInsets.fromLTRB(10, 2, 10, 0),
              child: Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
            );

            if (constraints.maxWidth < 400) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(before, style: beforeStyle)),
                      arrow,
                      Expanded(
                        child: Text(
                          after,
                          textAlign: TextAlign.end,
                          style: afterStyle,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: Text(label)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    before,
                    textAlign: TextAlign.end,
                    style: beforeStyle,
                  ),
                ),
                arrow,
                Expanded(
                  flex: 3,
                  child: Text(
                    after,
                    textAlign: TextAlign.start,
                    style: afterStyle,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      if (showDivider) const Divider(height: 1),
    ],
  );
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final labelText = Text('$label: ', style: const TextStyle(color: muted));
      final valueText = Text(
        value,
        style: Theme.of(context).textTheme.titleMedium,
      );
      if (constraints.maxWidth < 400) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: blue, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 2), valueText],
              ),
            ),
          ],
        );
      }
      return Row(
        children: [
          Icon(icon, color: blue, size: 20),
          const SizedBox(width: 10),
          labelText,
          Expanded(child: valueText),
        ],
      );
    },
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: canvas,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(text),
      ],
    ),
  );
}

String _displayNumber(Object? value) {
  if (value is num && value == value.roundToDouble()) {
    return value.toInt().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
  return '$value';
}

String _fieldLabel(String key) => switch (key) {
  'foodName' => 'Food name',
  'servingGrams' => 'Serving',
  'calories' => 'Calories',
  'proteinGrams' => 'Protein',
  'carbsGrams' => 'Carbs',
  'fatGrams' => 'Fat',
  'fiberGrams' => 'Fibre',
  'sugarGrams' => 'Sugar',
  'sodiumMg' => 'Sodium',
  _ => key,
};

String _fieldValue(String key, Object? value) {
  final suffix = switch (key) {
    'servingGrams' ||
    'proteinGrams' ||
    'carbsGrams' ||
    'fatGrams' ||
    'fiberGrams' ||
    'sugarGrams' => ' g',
    'calories' => ' kcal',
    'sodiumMg' => ' mg',
    _ => '',
  };
  return '${_displayNumber(value)}$suffix';
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(child: Text(label));
}
