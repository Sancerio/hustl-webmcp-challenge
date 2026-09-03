part of 'health_overview_bloc.dart';

abstract class HealthOverviewEvent extends Equatable {
  const HealthOverviewEvent();

  @override
  List<Object?> get props => [];
}

class HealthOverviewStarted extends HealthOverviewEvent {
  const HealthOverviewStarted({this.forceRefresh = false});

  final bool forceRefresh;

  @override
  List<Object?> get props => [forceRefresh];
}

class HealthOverviewRefreshed extends HealthOverviewEvent {
  const HealthOverviewRefreshed();
}

class HealthOverviewDateRangeChanged extends HealthOverviewEvent {
  const HealthOverviewDateRangeChanged({
    required this.start,
    required this.end,
    this.forceRefresh = false,
  });

  final DateTime start;
  final DateTime end;
  final bool forceRefresh;

  @override
  List<Object?> get props => [start, end, forceRefresh];
}
