import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/food_repository.dart';
import 'food_search_event.dart';
import 'food_search_state.dart';

class FoodSearchBloc extends Bloc<FoodSearchEvent, FoodSearchState> {
  FoodSearchBloc(this._foodRepository) : super(const FoodSearchState()) {
    on<FoodQueryChanged>(_onQueryChanged);
  }

  final FoodRepository _foodRepository;

  Future<void> _onQueryChanged(
    FoodQueryChanged event,
    Emitter<FoodSearchState> emit,
  ) async {
    final q = event.query.trim();
    // Clearing the field resets to the empty state so stale results, errors, or
    // the stale-cache banner from a previous search don't linger under a blank
    // query.
    if (q.isEmpty) {
      emit(const FoodSearchState());
      return;
    }
    emit(
      state.copyWith(
        query: q,
        isLoading: true,
        errorMessage: null,
        isStale: false,
        staleAgeMs: null,
      ),
    );
    try {
      final result = await _foodRepository.searchFoodsResult(q);
      emit(
        state.copyWith(
          isLoading: false,
          results: result.foods,
          isStale: result.isStale,
          staleAgeMs: result.staleAgeMs,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }
}
