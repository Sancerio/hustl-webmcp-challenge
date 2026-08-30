import 'package:equatable/equatable.dart';

sealed class FoodSearchEvent extends Equatable {
  const FoodSearchEvent();

  @override
  List<Object?> get props => [];
}

class FoodQueryChanged extends FoodSearchEvent {
  const FoodQueryChanged(this.query);
  final String query;

  @override
  List<Object?> get props => [query];
}
