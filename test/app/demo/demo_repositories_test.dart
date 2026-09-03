import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:hustl_app/app/demo/demo_auth_repository.dart';
import 'package:hustl_app/app/demo/demo_connections_repository.dart';
import 'package:hustl_app/app/demo/demo_dependencies.dart';
import 'package:hustl_app/app/demo/demo_food_log_repository.dart';
import 'package:hustl_app/app/demo/demo_food_repository.dart';
import 'package:hustl_app/app/demo/demo_health_metrics_repository.dart';
import 'package:hustl_app/app/demo/demo_coaching_trends_api.dart';
import 'package:hustl_app/app/demo/demo_meal_scan_repository.dart';
import 'package:hustl_app/app/demo/demo_nutrition_targets_repository.dart';
import 'package:hustl_app/app/demo/demo_persona.dart';
import 'package:hustl_app/app/demo/demo_template_repository.dart';
import 'package:hustl_app/app/demo/demo_workout_repository.dart';
import 'package:hustl_app/app/demo/demo_workout_history_web_mcp_service.dart';
import 'package:hustl_app/app/demo/demo_workout_seed.dart';

import 'package:hustl_app/app/demo/demo_proposals_repository.dart';
import 'package:hustl_app/app/demo/demo_state.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_revision_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/template_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/food_log_revision_proposal_repository.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/connections/domain/repositories/connections_repository.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';
import 'package:hustl_app/core/webmcp/coaching_trends_api.dart';
import 'package:hustl_app/core/webmcp/coaching_trends_web_mcp_service.dart';
import 'package:hustl_app/core/webmcp/workout_history_web_mcp_service.dart';

void main() {
  // A fixed anchor makes every assertion fully deterministic.
  final anchor = DateTime(2026, 6, 12);

  group('DemoWorkoutRepository', () {
    late DemoWorkoutRepository repo;

    setUp(() => repo = DemoWorkoutRepository(anchor: anchor));

    test('seeds exactly 48 completed sessions (12 weeks x 4/week)', () async {
      expect(DemoWorkoutSeed.sessionCount, 48);
      final sessions = await repo.getWorkoutSessions();
      expect(sessions.length, 48);
      expect(sessions.every((s) => s.isCompleted), isTrue);
    });

    test('sessions are newest-first', () async {
      final sessions = await repo.getWorkoutSessions();
      for (var i = 1; i < sessions.length; i++) {
        expect(
          sessions[i].startTime.isAfter(sessions[i - 1].startTime),
          isFalse,
        );
      }
    });

    test('rotation cycles push/pull/legs/upper', () async {
      final sessions = await repo.getWorkoutSessions();
      final names = sessions.map((s) => s.name).toSet();
      expect(
        names,
        containsAll(<String>{
          'Chest Power',
          'Pull Power',
          'Leg Power',
          'Push Power',
        }),
      );
    });

    test('exactly 3 PR sets live in the most recent session', () async {
      final sessions = await repo.getWorkoutSessions();
      final latest = sessions.first;
      final prCount = latest.exercises
          .expand((e) => e.sets)
          .where((s) => s.isPr)
          .length;
      expect(prCount, 3);

      // No other session carries PR flags.
      final otherPrs = sessions
          .skip(1)
          .expand((s) => s.exercises)
          .expand((e) => e.sets)
          .where((s) => s.isPr)
          .length;
      expect(otherPrs, 0);
    });

    test('progressive overload: newest bench is heavier than oldest', () async {
      final sessions = await repo.getWorkoutSessions();
      double benchWeight(Iterable sessionsList) {
        for (final s in sessionsList) {
          for (final e in s.exercises) {
            if (e.exercise.slug == 'barbell-bench-press') {
              return e.sets.first.weight as double;
            }
          }
        }
        return 0;
      }

      final newest = benchWeight(sessions);
      final oldest = benchWeight(sessions.reversed);
      expect(newest, greaterThan(oldest));
    });

    test('limit and date filters work', () async {
      final limited = await repo.getWorkoutSessions(limit: 5);
      expect(limited.length, 5);

      final recent = await repo.getWorkoutSessions(
        startDate: anchor.subtract(const Duration(days: 7)),
      );
      expect(recent.length, inInclusiveRange(1, 8));
    });

    test('PR lookup returns the heaviest seeded set', () async {
      final pr = await repo.getExercisePr(
        'Barbell Bench Press',
        exerciseSlug: 'barbell-bench-press',
      );
      expect(pr, isNotNull);
      expect(pr!.weight, greaterThan(0));
    });
  });

  group('Body score (computed from seeded sessions)', () {
    test('reads ~82 balance with hamstrings lagging quads', () async {
      final repo = DemoWorkoutRepository(anchor: anchor);
      final sessions = await repo.getWorkoutSessions();
      final service = BodyScoreService();
      final summary = service.summarize(
        sessions,
        window: const Duration(days: 28),
        anchor: anchor,
      );
      expect(summary, isNotNull);

      // Balance lands in the spec's "~82" neighbourhood.
      expect(summary!.balanceScore, inInclusiveRange(78.0, 88.0));

      // Hamstrings score is meaningfully below quads (lagging).
      final hamstrings = summary.regionScores[MuscleGroup.hamstrings] ?? 0;
      final quads = summary.regionScores[MuscleGroup.quads] ?? 0;
      expect(hamstrings, greaterThan(0));
      expect(hamstrings, lessThan(quads));
      expect(summary.isRegionUnderTarget(MuscleGroup.hamstrings), isTrue);
    });
  });

  group('DemoTemplateRepository', () {
    test(
      'seeds the persona templates including the favorite push day',
      () async {
        final repo = DemoTemplateRepository(anchor: anchor);
        final templates = await repo.getWorkoutTemplates();
        expect(templates, isNotEmpty);
        final names = templates.map((t) => t.name).toList();
        expect(names, contains('Chest Power'));
        final push = templates.firstWhere((t) => t.name == 'Chest Power');
        expect(push.exercises.length, 5);
      },
    );
  });

  group('DemoFoodLogRepository', () {
    test('today has exactly 4 meals summing to 1430/118/142/48', () async {
      final repo = DemoFoodLogRepository(anchor: anchor);
      final entries = await repo.getLogsForDate(anchor);
      expect(entries.length, 4);

      double sum(double Function(dynamic) f) =>
          entries.fold<double>(0, (acc, e) => acc + f(e));
      expect(sum((e) => e.calories), 1430);
      expect(sum((e) => e.proteinGrams), 118);
      expect(sum((e) => e.carbsGrams), 142);
      expect(sum((e) => e.fatGrams), 48);

      // Four distinct hours so the diary timeline renders four groups.
      final hours = entries.map((e) => e.loggedAt.hour).toSet();
      expect(hours.length, 4);
    });

    test('other days are empty', () async {
      final repo = DemoFoodLogRepository(anchor: anchor);
      final yesterday = await repo.getLogsForDate(
        anchor.subtract(const Duration(days: 1)),
      );
      expect(yesterday, isEmpty);
    });
  });

  group('DemoFoodRepository', () {
    test('search and favorites return seeded foods', () async {
      final repo = DemoFoodRepository();
      final results = await repo.searchFoods('chicken');
      expect(results, isNotEmpty);
      final favorites = await repo.listFavorites();
      expect(favorites, isNotEmpty);
      final barcode = await repo.lookupBarcode('0123456789012');
      expect(barcode, isNotNull);
    });
  });

  group('DemoNutritionTargetsRepository', () {
    late DemoNutritionTargetsRepository repo;
    setUp(() => repo = DemoNutritionTargetsRepository(anchor: anchor));

    test('current plan exposes 2200/160/220/70 targets', () async {
      final plan = await repo.getCurrentPlan(anchor);
      expect(plan, isNotNull);
      expect(plan!.caloriesTarget, 2200);
      expect(plan.proteinTarget, 160);
      expect(plan.carbsTarget, 220);
      expect(plan.fatTarget, 70);
      expect(plan.goal, 'lose');
      expect(plan.mode, 'auto');
    });

    test('weight trend spans 90 days, 84.2 -> ~81.6', () async {
      final trend = await repo.getWeightTrend(
        anchor.subtract(const Duration(days: 90)),
        anchor,
      );
      final trendLine = trend['trend'] as List;
      expect(trendLine.length, DemoNutritionTargetsRepository.weightSeriesDays);

      final firstTrend = (trendLine.first as Map)['trendKg'] as num;
      final lastTrend = (trendLine.last as Map)['trendKg'] as num;
      expect(firstTrend.toDouble(), closeTo(DemoPersona.weightStartKg, 0.01));
      expect(lastTrend.toDouble(), closeTo(DemoPersona.weightEndKg, 0.01));

      // Scatter points exist and carry a date + weight.
      final scale = trend['scale'] as List;
      expect(scale, isNotEmpty);
      final point = scale.first as Map;
      expect(point['date'], isA<String>());
      expect(point['weightKg'], isA<num>());
      expect(trend['goalType'], 'lose');
    });

    test('weight trend is deterministic for a fixed anchor', () async {
      final a = await repo.getWeightTrend(anchor, anchor);
      final b = await DemoNutritionTargetsRepository(
        anchor: anchor,
      ).getWeightTrend(anchor, anchor);
      expect(a['trend'].toString(), b['trend'].toString());
      expect(a['scale'].toString(), b['scale'].toString());
    });

    test(
      'insights / adherence / check-in expose the parsed map shapes',
      () async {
        final insights = await repo.getInsights(
          anchor.subtract(const Duration(days: 30)),
          anchor,
        );
        expect(insights['averages'], isA<Map>());
        expect(insights['energyBalance'], isA<Map>());
        expect((insights['energyBalance'] as Map)['days'], isA<List>());
        expect(insights['weight'], isA<Map>());

        final adherence = await repo.getWeeklyAdherence(anchor);
        expect(adherence['weeklyScore'], isA<num>());
        expect((adherence['days'] as List).length, 7);

        final checkIn = await repo.getWeeklyCheckIn(anchor);
        expect(checkIn['deltas'], isA<Map>());
        expect(checkIn['why'], isA<Map>());
        expect(checkIn['coverage'], isA<Map>());
      },
    );
  });

  group('DemoProposalsRepository', () {
    late DemoProposalsRepository repo;
    late DemoState state;
    late DemoFoodLogRepository foodLogRepository;
    late DemoNutritionTargetsRepository nutritionTargetsRepository;
    late DemoTemplateRepository templateRepository;
    late DemoConnectionsRepository connectionsRepository;

    setUp(() {
      state = DemoState();
      foodLogRepository = DemoFoodLogRepository(anchor: anchor);
      nutritionTargetsRepository = DemoNutritionTargetsRepository(
        anchor: anchor,
      );
      templateRepository = DemoTemplateRepository(anchor: anchor);
      connectionsRepository = DemoConnectionsRepository(
        anchor: anchor,
        state: state,
      );
      repo = DemoProposalsRepository(
        anchor: anchor,
        state: state,
        foodLogRepository: foodLogRepository,
        nutritionTargetsRepository: nutritionTargetsRepository,
        templateRepository: templateRepository,
      );
    });

    const apple = FoodLogProposalInput(
      date: '2026-06-12',
      note: 'Demo apple',
      items: [
        FoodLogProposalItem(
          foodName: 'Apple',
          servingGrams: 100,
          calories: 52,
          proteinGrams: 0.3,
          carbsGrams: 14,
          fatGrams: 0.2,
          fiberGrams: 2.4,
          sugarGrams: 10.4,
          sodiumMg: 1,
        ),
      ],
    );

    test('seeds a pending Claude nutrition-target proposal', () async {
      final pending = await repo.listPending();
      expect(pending, isNotEmpty);
      final nutrition = pending.firstWhere(
        (p) => p.kind == ProposalKind.nutritionTargets,
      );
      expect(nutrition.id, DemoProposalsRepository.nutritionId);
      expect(nutrition.isPending, isTrue);
      expect(nutrition.summary, contains('Claude'));

      final detail = await repo.getProposal(nutrition.id);
      final n = detail.proposedNutrition;
      expect(n, isNotNull);
      // Raise protein 160 -> 180 g and calories 2200 -> 2350 kcal.
      expect(n!.proteinTarget, 180);
      expect(n.caloriesTarget, 2350);
      expect(detail.description, contains('Claude'));
      expect((n.rationale ?? '').trim(), isNotEmpty);
    });

    test('also seeds a Codex template tweak for a fuller inbox', () async {
      final pending = await repo.listPending();
      final edit = pending.firstWhere(
        (p) => p.kind == ProposalKind.templateEdit,
      );
      expect(edit.summary, contains('Codex'));
      // Newest-first: the nutrition proposal (today) precedes the edit (yesterday).
      expect(pending.first.kind, ProposalKind.nutritionTargets);
    });

    test(
      'can start with an empty inbox for live challenge collaboration',
      () async {
        final emptyRepo = DemoProposalsRepository(
          anchor: anchor,
          seedInitialProposals: false,
        );

        expect(await emptyRepo.listPending(), isEmpty);
        final result = await emptyRepo.proposeNutritionTargets(
          const NutritionProposalInput(
            caloriesTarget: 2100,
            proteinTarget: 170,
            carbsTarget: 205,
            fatTarget: 67,
            rationale:
                'Translate the athlete conversation into reviewable targets.',
          ),
        );

        expect(result.status, 'pending');
        expect(await emptyRepo.listPending(), hasLength(1));
      },
    );

    test(
      'conversation translation applies two and dismisses three proposals',
      () async {
        final targets = DemoNutritionTargetsRepository(anchor: anchor);
        final templates = DemoTemplateRepository(anchor: anchor);
        final emptyRepo = DemoProposalsRepository(
          anchor: anchor,
          seedInitialProposals: false,
          nutritionTargetsRepository: targets,
          templateRepository: templates,
        );
        final baselineTargets = await targets.getCurrentPlan(anchor);
        final baselineTemplates = await templates.getWorkoutTemplates();

        final nutrition = await emptyRepo.proposeNutritionTargets(
          const NutritionProposalInput(
            caloriesTarget: 2100,
            proteinTarget: 175,
            carbsTarget: 204,
            fatTarget: 65,
            rationale:
                'Support a gradual cut while preserving strength and recovery.',
          ),
        );
        const plans = <TemplateProposalPlan>[
          TemplateProposalPlan(
            name: 'Upper A',
            exercises: [
              TemplateProposalExercise(
                exerciseId: 'Barbell Bench Press',
                slug: 'barbell-bench-press',
                sets: 3,
                repsTarget: 5,
                restTimerSeconds: 180,
                rpeTarget: 8,
              ),
              TemplateProposalExercise(
                exerciseId: 'Barbell Row',
                slug: 'barbell-row',
                sets: 3,
                repsTarget: 6,
                restTimerSeconds: 150,
                rpeTarget: 8,
              ),
            ],
          ),
          TemplateProposalPlan(
            name: 'Lower A',
            exercises: [
              TemplateProposalExercise(
                exerciseId: 'Barbell Back Squat',
                slug: 'barbell-back-squat',
                sets: 3,
                repsTarget: 5,
                restTimerSeconds: 180,
                rpeTarget: 8,
              ),
              TemplateProposalExercise(
                exerciseId: 'Romanian Deadlift',
                slug: 'romanian-deadlift',
                sets: 3,
                repsTarget: 8,
                restTimerSeconds: 150,
                rpeTarget: 7,
              ),
            ],
          ),
          TemplateProposalPlan(
            name: 'Upper B',
            exercises: [
              TemplateProposalExercise(
                exerciseId: 'Overhead Press',
                slug: 'overhead-press',
                sets: 3,
                repsTarget: 6,
                restTimerSeconds: 150,
                rpeTarget: 8,
              ),
              TemplateProposalExercise(
                exerciseId: 'Weighted Pull-up',
                slug: 'weighted-pull-up',
                sets: 3,
                repsTarget: 6,
                restTimerSeconds: 150,
                rpeTarget: 8,
              ),
            ],
          ),
          TemplateProposalPlan(
            name: 'Lower B',
            exercises: [
              TemplateProposalExercise(
                exerciseId: 'Barbell Deadlift',
                slug: 'barbell-deadlift',
                sets: 3,
                repsTarget: 4,
                restTimerSeconds: 210,
                rpeTarget: 8,
              ),
              TemplateProposalExercise(
                exerciseId: 'Bulgarian Split Squat',
                slug: 'bulgarian-split-squat',
                sets: 3,
                repsTarget: 8,
                restTimerSeconds: 120,
                rpeTarget: 7,
              ),
            ],
          ),
        ];
        final templateProposals = <TemplateProposalResult>[];
        for (final plan in plans) {
          templateProposals.add(await emptyRepo.proposeTemplate(plan));
        }

        expect(await emptyRepo.listPending(), hasLength(5));
        expect(await targets.getCurrentPlan(anchor), baselineTargets);
        expect(await templates.getWorkoutTemplates(), baselineTemplates);

        await emptyRepo.approve(
          nutrition.proposalId,
          idempotencyKey: 'approve-nutrition',
        );
        await emptyRepo.approve(
          templateProposals.first.proposalId,
          idempotencyKey: 'approve-${templateProposals.first.proposalId}',
        );
        for (final proposal in templateProposals.skip(1)) {
          await emptyRepo.reject(
            proposal.proposalId,
            reason: 'Athlete chose a smaller initial change.',
          );
        }

        final appliedTargets = await targets.getCurrentPlan(anchor);
        final appliedTemplates = await templates.getWorkoutTemplates();
        expect(appliedTargets?.caloriesTarget, 2100);
        expect(appliedTargets?.proteinTarget, 175);
        expect(appliedTargets?.carbsTarget, 204);
        expect(appliedTargets?.fatTarget, 65);
        expect(
          appliedTemplates.map((template) => template.name),
          contains(plans.first.name),
        );
        expect(
          appliedTemplates.map((template) => template.name),
          isNot(containsAll(plans.skip(1).map((plan) => plan.name))),
        );
        expect(appliedTemplates, hasLength(baselineTemplates.length + 1));
        expect(await emptyRepo.listPending(), isEmpty);

        final applied = await emptyRepo.listDecided(
          statuses: const ['applied'],
        );
        final rejected = await emptyRepo.listDecided(
          statuses: const ['rejected'],
        );
        expect(applied, hasLength(2));
        expect(rejected, hasLength(3));

        // A terminal decision cannot be replayed to mutate state a second time.
        await expectLater(
          emptyRepo.approve(
            templateProposals[1].proposalId,
            idempotencyKey: 'late-approve-rejected',
          ),
          throwsA(anything),
        );
        expect(await templates.getWorkoutTemplates(), appliedTemplates);
      },
    );

    test('approving drops the proposal from the pending set', () async {
      await repo.approve(
        DemoProposalsRepository.nutritionId,
        idempotencyKey: 'k',
      );
      final pending = await repo.listPending();
      expect(
        pending.any((p) => p.id == DemoProposalsRepository.nutritionId),
        isFalse,
      );
    });

    test(
      'history lists decided proposals with default and custom filters',
      () async {
        await repo.approve(
          DemoProposalsRepository.nutritionId,
          idempotencyKey: 'k',
        );

        final defaultHistory = await repo.listDecided();
        expect(
          defaultHistory.map((proposal) => proposal.id),
          contains(DemoProposalsRepository.nutritionId),
        );
        expect(await repo.listDecided(statuses: const ['rejected']), isEmpty);
      },
    );

    test('food auto-log OFF stays pending and does not touch diary', () async {
      final before = await foodLogRepository.getLogsForDate(anchor);
      final result = await repo.proposeFoodLog(apple);

      expect(result.status, 'pending');
      expect(result.requiresHumanReview, isTrue);
      expect(await foodLogRepository.getLogsForDate(anchor), before);
    });

    test('food auto-log ON applies once and Undo restores baseline', () async {
      final before = await foodLogRepository.getLogsForDate(anchor);
      await connectionsRepository.setWebMcpFoodAutoLog(true);

      final first = await repo.proposeFoodLog(apple);
      final afterFirst = await foodLogRepository.getLogsForDate(anchor);
      final replay = await repo.proposeFoodLog(apple);
      final afterReplay = await foodLogRepository.getLogsForDate(anchor);

      expect(first.status, 'applied');
      expect(first.proposal.summary.isFirstPartyWebAutoLog, isTrue);
      expect(replay.status, 'applied');
      expect(replay.proposalId, first.proposalId);
      expect(afterFirst.length, before.length + 1);
      expect(afterReplay, afterFirst);
      expect((await repo.listAutoAppliedLogs()).single.id, first.proposalId);

      await repo.revert(first.proposalId);
      expect(await foodLogRepository.getLogsForDate(anchor), before);
      await repo.revert(first.proposalId);
      expect(await foodLogRepository.getLogsForDate(anchor), before);
      expect(await repo.listAutoAppliedLogs(), isEmpty);
    });

    test('reviewed food log applies exactly once and can be undone', () async {
      final before = await foodLogRepository.getLogsForDate(anchor);
      final proposal = await repo.proposeFoodLog(apple);

      await Future.wait([
        repo.approve(proposal.proposalId, idempotencyKey: 'food-apply'),
        repo.approve(proposal.proposalId, idempotencyKey: 'food-apply-retry'),
      ]);
      final applied = await foodLogRepository.getLogsForDate(anchor);
      await repo.approve(proposal.proposalId, idempotencyKey: 'food-replay');

      expect(applied.length, before.length + 1);
      expect(await foodLogRepository.getLogsForDate(anchor), applied);
      await repo.revert(proposal.proposalId);
      expect(await foodLogRepository.getLogsForDate(anchor), before);
    });

    test(
      'two reviewed food logs keep distinct entry ids and independent Undo',
      () async {
        final before = await foodLogRepository.getLogsForDate(anchor);
        final first = await repo.proposeFoodLog(apple);
        const banana = FoodLogProposalInput(
          date: '2026-06-12',
          note: 'Demo banana',
          items: [
            FoodLogProposalItem(
              foodName: 'Banana',
              servingGrams: 118,
              calories: 105,
              proteinGrams: 1.3,
              carbsGrams: 27,
              fatGrams: 0.4,
            ),
          ],
        );
        final second = await repo.proposeFoodLog(banana);

        await repo.approve(first.proposalId, idempotencyKey: 'first-food');
        await repo.approve(second.proposalId, idempotencyKey: 'second-food');

        final firstDetail = await repo.getProposal(first.proposalId);
        final secondDetail = await repo.getProposal(second.proposalId);
        final firstIds = firstDetail.appliedResult!['foodLogEntryIds'] as List;
        final secondIds =
            secondDetail.appliedResult!['foodLogEntryIds'] as List;
        expect(firstIds.single, isNot(secondIds.single));
        expect(
          await foodLogRepository.getLogsForDate(anchor),
          hasLength(before.length + 2),
        );

        await repo.revert(first.proposalId);
        final afterFirstUndo = await foodLogRepository.getLogsForDate(anchor);
        expect(afterFirstUndo, hasLength(before.length + 1));
        expect(
          afterFirstUndo.any((entry) => entry.foodName == 'Apple'),
          isFalse,
        );
        expect(
          afterFirstUndo.any((entry) => entry.foodName == 'Banana'),
          isTrue,
        );

        await repo.revert(second.proposalId);
        expect(await foodLogRepository.getLogsForDate(anchor), before);
      },
    );

    test('nutrition approval mutates the shared target repository', () async {
      const input = NutritionProposalInput(
        caloriesTarget: 2400,
        proteinTarget: 175,
        carbsTarget: 255,
        fatTarget: 68,
        rationale: 'Fuel the next block.',
      );
      final proposal = await repo.proposeNutritionTargets(input);
      await repo.approve(
        proposal.proposalId,
        idempotencyKey: 'nutrition-apply',
      );

      final plan = await nutritionTargetsRepository.getCurrentPlan(anchor);
      expect(plan?.caloriesTarget, 2400);
      expect(plan?.proteinTarget, 175);
      expect(plan?.carbsTarget, 255);
      expect(plan?.fatTarget, 68);
    });

    test(
      'template create approval writes once and replay is idempotent',
      () async {
        const plan = TemplateProposalPlan(
          name: 'Demo full body',
          description: 'A compact evaluator plan.',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Goblet Squat',
              slug: 'goblet-squat',
              sets: 3,
              repsTarget: 10,
              restTimerSeconds: 90,
              weightTarget: 24,
              rpeTarget: 7,
            ),
          ],
        );
        final before = await templateRepository.getWorkoutTemplates();
        final proposal = await repo.proposeTemplate(plan);
        final duplicate = await repo.proposeTemplate(plan);
        expect(duplicate.status, 'duplicate');
        expect(duplicate.proposalId, proposal.proposalId);

        final result = await repo.approve(
          proposal.proposalId,
          idempotencyKey: 'template-create',
        );
        await repo.approve(
          proposal.proposalId,
          idempotencyKey: 'template-create-replay',
        );
        final after = await templateRepository.getWorkoutTemplates();
        expect(after.length, before.length + 1);
        expect(
          await templateRepository.getWorkoutTemplate(result.templateId!),
          isNotNull,
        );
      },
    );

    test(
      'template edit applies the reviewed replacement exactly once',
      () async {
        final before = await templateRepository.getWorkoutTemplate(
          'demo-template-push',
        );
        const plan = TemplateProposalPlan(
          name: 'Chest Power revised',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              slug: 'barbell-bench-press',
              sets: 3,
              repsTarget: 6,
              restTimerSeconds: 180,
              weightTarget: 90,
              rpeTarget: 8,
            ),
          ],
        );
        final proposal = await repo.proposeTemplateEdit(
          before!.id,
          before.updatedAt,
          plan,
        );
        await repo.approve(
          proposal.proposalId,
          idempotencyKey: 'template-edit',
        );
        final after = await templateRepository.getWorkoutTemplate(before.id);

        expect(after?.name, 'Chest Power revised');
        expect(after?.exercises.length, 1);
        expect(after?.updatedAt, isNot(before.updatedAt));
      },
    );

    test(
      'template edit accepts and replays an ISO UTC version token',
      () async {
        final before = await templateRepository.getWorkoutTemplate(
          'demo-template-push',
        );
        final roundTrippedVersion = DateTime.parse(
          before!.updatedAt.toUtc().toIso8601String(),
        );
        const plan = TemplateProposalPlan(
          name: 'Chest Power recovery day',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              sets: 3,
              restTimerSeconds: 180,
            ),
          ],
        );

        final proposal = await repo.proposeTemplateEdit(
          before.id,
          roundTrippedVersion,
          plan,
        );
        final replay = await repo.proposeTemplateEdit(
          before.id,
          before.updatedAt,
          plan,
        );

        expect(proposal.status, 'pending');
        expect(replay.status, 'duplicate');
        expect(replay.proposalId, proposal.proposalId);
        expect(await templateRepository.getWorkoutTemplate(before.id), before);
      },
    );

    test(
      'concurrent identical template edits resolve to one pending proposal',
      () async {
        final before = await templateRepository.getWorkoutTemplate(
          'demo-template-push',
        );
        const plan = TemplateProposalPlan(
          name: 'Chest Power concurrent replay',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              sets: 3,
              restTimerSeconds: 180,
            ),
          ],
        );

        final results = await Future.wait([
          repo.proposeTemplateEdit(before!.id, before.updatedAt, plan),
          repo.proposeTemplateEdit(before.id, before.updatedAt, plan),
        ]);

        expect(
          results.map((result) => result.proposalId).toSet(),
          hasLength(1),
        );
        expect(
          results.map((result) => result.status),
          containsAll(<String>['pending', 'duplicate']),
        );
      },
    );

    test(
      'template approval rejects a sibling proposal after its base changes',
      () async {
        final before = await templateRepository.getWorkoutTemplate(
          'demo-template-push',
        );
        const firstPlan = TemplateProposalPlan(
          name: 'Chest Power lighter',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              sets: 3,
              restTimerSeconds: 180,
            ),
          ],
        );
        const stalePlan = TemplateProposalPlan(
          name: 'Chest Power stale overwrite',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              sets: 5,
              restTimerSeconds: 180,
            ),
          ],
        );
        final first = await repo.proposeTemplateEdit(
          before!.id,
          before.updatedAt,
          firstPlan,
        );
        final stale = await repo.proposeTemplateEdit(
          before.id,
          before.updatedAt,
          stalePlan,
        );

        await repo.approve(first.proposalId, idempotencyKey: 'first-template');
        await expectLater(
          repo.approve(stale.proposalId, idempotencyKey: 'stale-template'),
          throwsA(isA<TemplateProposalConflict>()),
        );

        final after = await templateRepository.getWorkoutTemplate(before.id);
        expect(after?.name, firstPlan.name);
        expect(after?.exercises.single['sets'], 3);
        expect((await repo.getProposal(stale.proposalId)).isPending, isTrue);
      },
    );

    test(
      'concurrent sibling template approvals apply one and conflict one',
      () async {
        final before = await templateRepository.getWorkoutTemplate(
          'demo-template-push',
        );
        const firstPlan = TemplateProposalPlan(
          name: 'Chest Power concurrent first',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              sets: 3,
              restTimerSeconds: 180,
            ),
          ],
        );
        const secondPlan = TemplateProposalPlan(
          name: 'Chest Power concurrent second',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              sets: 5,
              restTimerSeconds: 180,
            ),
          ],
        );
        final first = await repo.proposeTemplateEdit(
          before!.id,
          before.updatedAt,
          firstPlan,
        );
        final second = await repo.proposeTemplateEdit(
          before.id,
          before.updatedAt,
          secondPlan,
        );

        Future<Object> capture(Future<ApproveResult> operation) async {
          try {
            return await operation;
          } catch (error) {
            return error;
          }
        }

        final outcomes = await Future.wait([
          capture(
            repo.approve(first.proposalId, idempotencyKey: 'concurrent-first'),
          ),
          capture(
            repo.approve(
              second.proposalId,
              idempotencyKey: 'concurrent-second',
            ),
          ),
        ]);

        expect(outcomes.whereType<ApproveResult>(), hasLength(1));
        expect(outcomes.whereType<TemplateProposalConflict>(), hasLength(1));
        final details = await Future.wait([
          repo.getProposal(first.proposalId),
          repo.getProposal(second.proposalId),
        ]);
        expect(
          details.where((detail) => detail.summary.isApplied),
          hasLength(1),
        );
        expect(details.where((detail) => detail.isPending), hasLength(1));
        final applied = details.singleWhere(
          (detail) => detail.summary.isApplied,
        );
        final after = await templateRepository.getWorkoutTemplate(before.id);
        expect(after?.name, applied.templateName);
      },
    );

    test(
      'food edit and delete approvals both restore exact rows on Undo',
      () async {
        final baseline = (await foodLogRepository.getLogsForDate(anchor)).first;
        final edit = await repo.proposeFoodLogEdit(
          FoodLogEditProposalInput(
            targetEntryId: baseline.id,
            changes: const FoodLogRevisionChanges(
              foodName: 'Greek yogurt bowl',
              calories: 390,
              sodiumMg: 125,
            ),
          ),
        );
        await repo.approve(edit.proposalId, idempotencyKey: 'food-edit');
        expect(foodLogRepository.findEntry(baseline.id)?.calories, 390);
        expect(
          foodLogRepository.findEntry(baseline.id)?.foodName,
          'Greek yogurt bowl',
        );
        await repo.revert(edit.proposalId);
        expect(foodLogRepository.findEntry(baseline.id), baseline);

        final deletion = await repo.proposeFoodLogDelete(
          FoodLogDeleteProposalInput(targetEntryId: baseline.id),
        );
        await repo.approve(deletion.proposalId, idempotencyKey: 'food-delete');
        expect(foodLogRepository.findEntry(baseline.id), isNull);
        await repo.revert(deletion.proposalId);
        expect(foodLogRepository.findEntry(baseline.id), baseline);
      },
    );
  });

  group('DemoAuthRepository', () {
    test('is instantly authenticated as the Alex persona', () async {
      final repo = DemoAuthRepository();
      final user = await repo.getCurrentUser();
      expect(user, isNotNull);
      expect(user!.id, DemoPersona.userId);
      expect(user.provider, AuthProvider.google);
      expect(user.displayName, 'Alex');
    });

    test('sign out clears the user', () async {
      final repo = DemoAuthRepository();
      await repo.signOut();
      expect(await repo.getCurrentUser(), isNull);
    });
  });

  group('DemoHealthMetricsRepository', () {
    test('loads a populated snapshot with sleep, steps and weight', () async {
      const repo = DemoHealthMetricsRepository();
      final permissions = await repo.getPermissionsStatus();
      expect(permissions.hasPermissions, isTrue);

      final snapshot = await repo.loadSnapshot(
        start: anchor.subtract(const Duration(days: 29)),
        end: anchor,
      );
      expect(snapshot.dailySummaries, isNotEmpty);
      expect(snapshot.recoverySnapshots, isNotEmpty);

      // Steps samples were injected.
      final steps = snapshot.metrics
          .where((m) => m.type == HealthMetricType.steps)
          .toList();
      expect(steps, isNotEmpty);

      // Weight samples reflect Alex's track (start higher than end-ish).
      final weights = snapshot.metrics
          .where((m) => m.type == HealthMetricType.weight)
          .toList();
      expect(weights, isNotEmpty);

      // Latest recovery snapshot is pinned to 7h12m of sleep.
      final latest = snapshot.recoverySnapshots.last;
      expect(
        latest.sleepDurationMinutes,
        DemoHealthMetricsRepository.sleepMinutes,
      );
      expect(latest.readinessScore, 74);
      expect(latest.anomalyFlags, isEmpty);
    });

    test('challenge seed has poor sleep and reduced readiness only', () async {
      const repo = DemoHealthMetricsRepository(poorRecovery: true);
      final snapshot = await repo.loadSnapshot(
        start: anchor.subtract(const Duration(days: 29)),
        end: anchor,
      );

      final latest = snapshot.recoverySnapshots.last;
      expect(
        latest.sleepDurationMinutes,
        DemoHealthMetricsRepository.challengeSleepMinutes,
      );
      expect(
        latest.readinessScore,
        DemoHealthMetricsRepository.challengeReadiness,
      );
      expect(latest.flowBand, RecoveryFlowBand.recharge);
      expect(latest.anomalyFlags, ['sleep_below_baseline']);
    });
  });

  group('offline WebMCP demo adapters', () {
    test(
      'history is bounded, paginated, and strips raw workout detail',
      () async {
        final service = DemoWorkoutHistoryWebMcpService(
          repository: DemoWorkoutRepository(anchor: anchor),
          anchor: anchor,
        );

        final first = await service.loadWorkoutHistory(limit: 99);
        expect(first['workoutCount'], 20);
        expect(first['hasMore'], isTrue);
        expect(first['nextCursor'], 'demo:20');
        final workouts = first['workouts']! as List<Object?>;
        expect(workouts, hasLength(20));
        expect(
          (workouts.first! as Map<String, Object?>).keys,
          unorderedEquals([
            'id',
            'name',
            'startAt',
            'endAt',
            'durationSeconds',
            'status',
          ]),
        );
        expect(first.toString(), isNot(contains('-set')));
        expect(first.toString(), isNot(contains('exercises')));

        final finalPage = await service.loadWorkoutHistory(
          limit: 20,
          cursor: 'demo:40',
        );
        expect(finalPage['workoutCount'], 8);
        expect(finalPage['hasMore'], isFalse);
        expect(finalPage['nextCursor'], isNull);
      },
    );

    test('exercise history is deterministic and aggregate-only', () async {
      final service = DemoWorkoutHistoryWebMcpService(
        repository: DemoWorkoutRepository(anchor: anchor),
        anchor: anchor,
      );

      final first = await service.loadExerciseHistory(limit: 5, sinceDays: 365);
      final second = await service.loadExerciseHistory(
        limit: 5,
        sinceDays: 365,
      );

      expect(first, second);
      expect(first['exerciseCount'], 5);
      expect(first['range'], {'sinceDays': 365, 'since': '2025-06-13'});
      expect(first.toString(), isNot(contains('demo-session-')));
      expect(first.toString(), isNot(contains('-set')));
      final exercises = first['exercises']! as List<Object?>;
      final firstExercise = exercises.first! as Map<String, Object?>;
      expect(firstExercise['frequency'], greaterThan(0));
      expect(firstExercise['typicalSets'], greaterThan(0));
      expect(firstExercise.keys, isNot(contains('id')));
      expect(firstExercise.keys, isNot(contains('notes')));
    });

    test('coaching trends are deterministic bounded aggregates', () async {
      const api = DemoCoachingTrendsApi();
      final service = CoachingTrendsWebMcpService(
        api: api,
        localContext: () => (endDate: '2026-06-12', utcOffsetMinutes: 480),
      );

      final result = await service.load(windowDays: 30);

      expect(result['range'], {
        'windowDays': 30,
        'start': '2026-05-14',
        'end': '2026-06-12',
        'previousStart': '2026-04-14',
        'previousEnd': '2026-05-13',
      });
      final recovery = result['recovery']! as Map<String, Object?>;
      final current = recovery['current']! as Map<String, Object?>;
      expect(current['averageSleepHours'], 6.3);
      expect(current['averageHrvMs'], 49.0);
      expect(result.toString(), isNot(contains('accountId')));
      expect(result.toString(), isNot(contains('daily')));
    });
  });

  group('DemoMealScanRepository', () {
    test('returns a deterministic offline scan result', () async {
      const repo = DemoMealScanRepository();
      final result = await repo.scanMealPhoto(
        imageBytes: Uint8List(0),
        mimeType: 'image/jpeg',
      );
      expect(result.items, isNotEmpty);
      expect(result.totals.caloriesKcal, isNotNull);
    });
  });

  group('registerDemoDependencies', () {
    test('overrides the repositories in a GetIt container', () async {
      final getIt = GetIt.asNewInstance();
      // Pre-register a real-ish placeholder to prove the demo overrides it.
      getIt.registerLazySingleton<AuthRepository>(DemoAuthRepository.new);
      registerDemoDependencies(getIt, anchor: anchor, challengeMode: true);

      expect(getIt<AuthRepository>(), isA<DemoAuthRepository>());
      expect(getIt<WorkoutRepository>(), isA<DemoWorkoutRepository>());
      expect(
        getIt<WorkoutHistoryWebMcpReader>(),
        isA<DemoWorkoutHistoryWebMcpService>(),
      );
      expect(getIt<CoachingTrendsApi>(), isA<DemoCoachingTrendsApi>());
      expect(getIt<TemplateRepository>(), isA<DemoTemplateRepository>());
      expect(getIt<FoodLogRepository>(), isA<DemoFoodLogRepository>());
      expect(getIt<FoodRepository>(), isA<DemoFoodRepository>());
      expect(
        getIt<NutritionTargetsRepository>(),
        isA<DemoNutritionTargetsRepository>(),
      );
      expect(
        getIt<HealthMetricsRepository>(),
        isA<DemoHealthMetricsRepository>(),
      );
      expect(getIt<ProposalsRepository>(), isA<DemoProposalsRepository>());
      expect(await getIt<ProposalsRepository>().listPending(), isEmpty);

      // Reassignment flag is restored to its prior value.
      expect(getIt.allowReassignment, isFalse);

      await getIt.reset();
    });

    test(
      'challenge graph locks auto-log and keeps all proposal entry points pending',
      () async {
        final getIt = GetIt.asNewInstance();
        addTearDown(getIt.reset);
        registerDemoDependencies(getIt, anchor: anchor, challengeMode: true);

        final connections = getIt<ConnectionsRepository>();
        final proposals = getIt<ProposalsRepository>();
        final foodRevisions = proposals as FoodLogRevisionProposalRepository;
        final foodLogs = getIt<FoodLogRepository>();
        final nutritionTargets = getIt<NutritionTargetsRepository>();
        final templates = getIt<TemplateRepository>();
        final baselineDiary = await foodLogs.getLogsForDate(anchor);
        final baselineNutrition = await nutritionTargets.getCurrentPlan(anchor);
        final baselineTemplates = await templates.getWorkoutTemplates();
        final targetFood = baselineDiary.first;
        final targetTemplate = await templates.getWorkoutTemplate(
          'demo-template-push',
        );
        expect(targetTemplate, isNotNull);

        // Simulate a stale settings write reaching the in-memory repository.
        // The session capability, not the caller, remains authoritative.
        expect(await connections.setWebMcpFoodAutoLog(true), isFalse);
        expect(await connections.getWebMcpFoodAutoLog(), isFalse);

        final nutrition = await proposals.proposeNutritionTargets(
          const NutritionProposalInput(
            caloriesTarget: 2100,
            proteinTarget: 170,
            carbsTarget: 205,
            fatTarget: 67,
            rationale: 'Keep the evaluator change reviewable.',
          ),
        );
        final food = await proposals.proposeFoodLog(
          const FoodLogProposalInput(
            date: '2026-06-12',
            note: 'Challenge proposal',
            items: [
              FoodLogProposalItem(
                foodName: 'Apple',
                servingGrams: 100,
                calories: 52,
                proteinGrams: 0.3,
                carbsGrams: 14,
                fatGrams: 0.2,
              ),
            ],
          ),
        );
        final foodEdit = await foodRevisions.proposeFoodLogEdit(
          FoodLogEditProposalInput(
            targetEntryId: targetFood.id,
            changes: const FoodLogRevisionChanges(calories: 390),
          ),
        );
        final foodDelete = await foodRevisions.proposeFoodLogDelete(
          FoodLogDeleteProposalInput(targetEntryId: targetFood.id),
        );
        const createPlan = TemplateProposalPlan(
          name: 'Challenge full body',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Goblet Squat',
              slug: 'goblet-squat',
              sets: 3,
              repsTarget: 10,
              restTimerSeconds: 90,
            ),
          ],
        );
        final templateCreate = await proposals.proposeTemplate(createPlan);
        const editPlan = TemplateProposalPlan(
          name: 'Chest Power challenge revision',
          exercises: [
            TemplateProposalExercise(
              exerciseId: 'Barbell Bench Press',
              slug: 'barbell-bench-press',
              sets: 3,
              repsTarget: 6,
              restTimerSeconds: 180,
            ),
          ],
        );
        final templateEdit = await proposals.proposeTemplateEdit(
          targetTemplate!.id,
          targetTemplate.updatedAt,
          editPlan,
        );

        expect([
          nutrition.status,
          food.status,
          foodEdit.status,
          foodDelete.status,
          templateCreate.status,
          templateEdit.status,
        ], everyElement('pending'));
        final pending = await proposals.listPending();
        expect(pending, hasLength(6));
        expect(
          pending.map((proposal) => proposal.kind),
          containsAll(<ProposalKind>{
            ProposalKind.nutritionTargets,
            ProposalKind.foodLog,
            ProposalKind.foodLogEdit,
            ProposalKind.foodLogDelete,
            ProposalKind.templateCreate,
            ProposalKind.templateEdit,
          }),
        );
        expect(await proposals.listDecided(), isEmpty);
        expect(await proposals.listAutoAppliedLogs(), isEmpty);
        expect(await foodLogs.getLogsForDate(anchor), baselineDiary);
        expect(
          await nutritionTargets.getCurrentPlan(anchor),
          baselineNutrition,
        );
        expect(await templates.getWorkoutTemplates(), baselineTemplates);
      },
    );

    test('ordinary demo retains the illustrative seeded inbox', () async {
      final getIt = GetIt.asNewInstance();

      registerDemoDependencies(getIt, anchor: anchor);

      expect(await getIt<ProposalsRepository>().listPending(), hasLength(2));
      await getIt.reset();
    });

    test('ordinary demo retains opt-in food auto-log behavior', () async {
      final getIt = GetIt.asNewInstance();
      addTearDown(getIt.reset);
      registerDemoDependencies(getIt, anchor: anchor);
      final connections = getIt<ConnectionsRepository>();
      final proposals = getIt<ProposalsRepository>();
      final foodLogs = getIt<FoodLogRepository>();
      final baselineDiary = await foodLogs.getLogsForDate(anchor);

      expect(await connections.setWebMcpFoodAutoLog(true), isTrue);
      final result = await proposals.proposeFoodLog(
        const FoodLogProposalInput(
          date: '2026-06-12',
          note: 'Ordinary demo auto-log',
          items: [
            FoodLogProposalItem(
              foodName: 'Apple',
              servingGrams: 100,
              calories: 52,
              proteinGrams: 0.3,
              carbsGrams: 14,
              fatGrams: 0.2,
            ),
          ],
        ),
      );

      expect(result.status, 'applied');
      expect(result.proposal.summary.isFirstPartyWebAutoLog, isTrue);
      expect(
        await foodLogs.getLogsForDate(anchor),
        hasLength(baselineDiary.length + 1),
      );
    });
  });
}
