import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/nutrition_tracker/data/datasources/hustl_backend_nutrition_api.dart';
import 'package:hustl_app/features/nutrition_tracker/data/repositories/nutrition_targets_repository_impl.dart';

/// Fake API that returns a canned targets payload (the same `data` envelope the
/// backend handler responds with) so the repository's plan-building logic can be
/// exercised in isolation. `patchTargets` mirrors the real PATCH response, which
/// (after the prefill fix) carries the persisted `profile` alongside the plan.
class _FakeApi extends HustlBackendNutritionApi {
  _FakeApi({
    this.patchResponse = const {},
    this.targetsResponse = const {},
    this.targetsThrows = false,
  }) : super(tokens: TokenStorage());

  final Map<String, dynamic> patchResponse;
  final Map<String, dynamic> targetsResponse;
  final bool targetsThrows;
  bool? requestedReadOnly;

  @override
  Future<Map<String, dynamic>> getTargets(
    DateTime date, {
    bool readOnly = false,
  }) async {
    requestedReadOnly = readOnly;
    if (targetsThrows) {
      throw HustlBackendNutritionApiException(
        statusCode: 503,
        code: 'targets_failed',
        message: 'Couldn’t load targets. Please try again.',
      );
    }
    return targetsResponse;
  }

  @override
  Future<Map<String, dynamic>> patchTargets(
    String weekStart,
    Map<String, dynamic> patch,
  ) async {
    return patchResponse;
  }
}

void main() {
  group('NutritionTargetsRepositoryImpl.updatePlan', () {
    // Regression: PATCH (auto/manual toggle, manual-editor save) used to drop the
    // profile, so `updatePlan` rebuilt the in-memory plan with a null profile and
    // the next goal-sheet open lost the saved age/sex/height/weight/activity
    // prefill until a full GET refresh. The PATCH response carries the profile and
    // the repository must thread it through onto the rebuilt plan.
    test('carries the PATCH-returned profile onto the rebuilt plan', () async {
      final api = _FakeApi(
        patchResponse: {
          'plan': {
            'week_start': '2026-06-15',
            'mode': 'manual',
            'goal': 'lose',
            'calories_target': 2000,
            'protein_grams_target': 160,
            'carbs_grams_target': 200,
            'fat_grams_target': 60,
          },
          'needsSetup': false,
          'profile': {
            'ageYears': 34,
            'heightCm': 178,
            'weightKg': 81.5,
            'gender': 'female',
            'activityLevel': 'active',
          },
        },
      );
      final repo = NutritionTargetsRepositoryImpl(api: api);

      final plan = await repo.updatePlan(DateTime.parse('2026-06-15'), {
        'mode': 'manual',
        'caloriesTarget': 2000,
      });

      expect(plan, isNotNull);
      expect(plan!.needsSetup, isFalse);
      expect(plan.profile, isNotNull);
      expect(plan.profile!.ageYears, 34);
      expect(plan.profile!.heightCm, 178);
      expect(plan.profile!.weightKg, 81.5);
      expect(plan.profile!.gender, 'female');
      expect(plan.profile!.activityLevel, 'active');
    });

    // When the PATCH response omits `profile` (e.g. nothing saved yet), the
    // repository injects the null sibling so `fromMap` yields an empty profile —
    // matching the GET/recalc "null-filled profile when nothing saved" shape
    // rather than fabricating values.
    test('yields an empty profile when the PATCH response omits it', () async {
      final api = _FakeApi(
        patchResponse: {
          'plan': {
            'week_start': '2026-06-15',
            'mode': 'auto',
            'goal': 'maintain',
            'calories_target': 2100,
            'protein_grams_target': 150,
            'carbs_grams_target': 210,
            'fat_grams_target': 65,
          },
          'needsSetup': true,
        },
      );
      final repo = NutritionTargetsRepositoryImpl(api: api);

      final plan = await repo.updatePlan(DateTime.parse('2026-06-15'), {
        'mode': 'auto',
      });

      expect(plan, isNotNull);
      expect(plan!.profile, isNotNull);
      expect(plan.profile!.isEmpty, isTrue);
    });
  });

  group('NutritionTargetsRepositoryImpl.getCurrentPlanReadOnly', () {
    test('uses the backend read-only endpoint mode', () async {
      final api = _FakeApi(targetsResponse: const {'plan': null});
      final repo = NutritionTargetsRepositoryImpl(api: api);

      expect(await repo.getCurrentPlanReadOnly(DateTime(2026, 8, 26)), isNull);
      expect(api.requestedReadOnly, isTrue);
    });

    test('propagates backend failures instead of reporting no setup', () {
      final repo = NutritionTargetsRepositoryImpl(
        api: _FakeApi(targetsThrows: true),
      );

      expect(
        () => repo.getCurrentPlanReadOnly(DateTime(2026, 8, 26)),
        throwsA(isA<HustlBackendNutritionApiException>()),
      );
    });
  });
}
