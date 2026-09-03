import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models/food_log_entry.dart';
import '../../domain/repositories/food_log_repository.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import 'diary_event.dart';
import 'diary_state.dart';

class DiaryBloc extends Bloc<DiaryEvent, DiaryState> {
  DiaryBloc(
    this._logsRepository,
    this._targetsRepository, {
    DateTime? initialDate,
  }) : super(DiaryState(date: initialDate ?? DateTime.now())) {
    on<LoadDiary>(_onLoadDiary);
    on<AddDiaryEntries>(_onAddEntries);
    on<DeleteDiaryEntry>(_onDeleteEntry);
    on<UpdateDiaryEntry>(_onUpdateEntry);
  }

  final FoodLogRepository _logsRepository;
  final NutritionTargetsRepository _targetsRepository;

  DateTime _parseLocalDate(String raw) {
    final s = raw.trim();
    if (s.length == 10 && s[4] == '-' && s[7] == '-') {
      final parts = s.split('-');
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    return DateTime.parse(s);
  }

  Future<void> _onLoadDiary(LoadDiary event, Emitter<DiaryState> emit) async {
    emit(
      state.copyWith(
        date: event.date,
        isLoading: true,
        errorMessage: null,
        clearDayWeightKg: true,
        clearLatestWeightKg: true,
        clearLatestWeightDate: true,
      ),
    );
    try {
      final entries = await _logsRepository.getLogsForDate(event.date);
      final targets = await _targetsRepository.getCurrentPlan(event.date);

      double? dayWeightKg;
      double? latestWeightKg;
      DateTime? latestWeightDate;
      try {
        final end = DateTime(event.date.year, event.date.month, event.date.day);
        final start = end.subtract(const Duration(days: 30));
        final trend = await _targetsRepository.getWeightTrend(start, end);
        final scale = (trend['scale'] as List?) ?? const [];
        if (scale.isNotEmpty) {
          final dayKey = end.toIso8601String().substring(0, 10);
          for (final point in scale) {
            if (point is! Map) continue;
            final dateRaw = point['date']?.toString();
            final kg = (point['weightKg'] as num?)?.toDouble();
            if (dateRaw == null || kg == null || kg <= 0) continue;
            latestWeightKg = kg;
            latestWeightDate = _parseLocalDate(dateRaw);
            if (dateRaw == dayKey) dayWeightKg = kg;
          }
        }
      } catch (_) {
        // Best-effort only; diary should render for guests/offline.
      }

      final totals = entries.fold<Map<String, double>>(
        {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
        (acc, e) {
          acc['calories'] = (acc['calories'] ?? 0) + e.calories;
          acc['protein'] = (acc['protein'] ?? 0) + e.proteinGrams;
          acc['carbs'] = (acc['carbs'] ?? 0) + e.carbsGrams;
          acc['fat'] = (acc['fat'] ?? 0) + e.fatGrams;
          return acc;
        },
      );

      emit(
        state.copyWith(
          isLoading: false,
          hasLoaded: true,
          entries: entries,
          targets: targets,
          totalCalories: totals['calories'],
          totalProtein: totals['protein'],
          totalCarbs: totals['carbs'],
          totalFat: totals['fat'],
          dayWeightKg: dayWeightKg,
          latestWeightKg: latestWeightKg,
          latestWeightDate: latestWeightDate,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onAddEntries(
    AddDiaryEntries event,
    Emitter<DiaryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      await _logsRepository.addEntries(event.entries);
      add(LoadDiary(state.date));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onDeleteEntry(
    DeleteDiaryEntry event,
    Emitter<DiaryState> emit,
  ) async {
    final previousEntries = state.entries;
    final index = previousEntries.indexWhere((e) => e.id == event.entryId);
    if (index == -1) return;

    final nextEntries = List<FoodLogEntry>.from(previousEntries)
      ..removeAt(index);
    final totals = nextEntries.fold<Map<String, double>>(
      {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
      (acc, e) {
        acc['calories'] = (acc['calories'] ?? 0) + e.calories;
        acc['protein'] = (acc['protein'] ?? 0) + e.proteinGrams;
        acc['carbs'] = (acc['carbs'] ?? 0) + e.carbsGrams;
        acc['fat'] = (acc['fat'] ?? 0) + e.fatGrams;
        return acc;
      },
    );

    emit(
      state.copyWith(
        isLoading: false,
        entries: nextEntries,
        totalCalories: totals['calories'],
        totalProtein: totals['protein'],
        totalCarbs: totals['carbs'],
        totalFat: totals['fat'],
      ),
    );
    try {
      await _logsRepository.deleteEntry(event.entryId);
    } catch (e) {
      final previousTotals = previousEntries.fold<Map<String, double>>(
        {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
        (acc, entry) {
          acc['calories'] = (acc['calories'] ?? 0) + entry.calories;
          acc['protein'] = (acc['protein'] ?? 0) + entry.proteinGrams;
          acc['carbs'] = (acc['carbs'] ?? 0) + entry.carbsGrams;
          acc['fat'] = (acc['fat'] ?? 0) + entry.fatGrams;
          return acc;
        },
      );
      emit(
        state.copyWith(
          isLoading: false,
          entries: previousEntries,
          totalCalories: previousTotals['calories'],
          totalProtein: previousTotals['protein'],
          totalCarbs: previousTotals['carbs'],
          totalFat: previousTotals['fat'],
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onUpdateEntry(
    UpdateDiaryEntry event,
    Emitter<DiaryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      await _logsRepository.updateEntry(event.entryId, event.patch);
      add(LoadDiary(state.date));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }
}
