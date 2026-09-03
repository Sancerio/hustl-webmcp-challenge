import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/repositories/health_metrics_repository.dart';

abstract class HealthPermissionsEvent extends Equatable {
  const HealthPermissionsEvent();

  @override
  List<Object?> get props => [];
}

class HealthPermissionsStatusRequested extends HealthPermissionsEvent {
  const HealthPermissionsStatusRequested({this.silent = false});

  /// When true, skip the Loading emit: the UI keeps showing the current
  /// state while the status is re-checked in the background (used on app
  /// resume so a rendered dashboard doesn't flash to a skeleton).
  final bool silent;

  @override
  List<Object?> get props => [silent];
}

class HealthPermissionsGrantRequested extends HealthPermissionsEvent {}

class HealthPermissionsDenialCleared extends HealthPermissionsEvent {}

abstract class HealthPermissionsState extends Equatable {
  const HealthPermissionsState();

  @override
  List<Object?> get props => [];
}

class HealthPermissionsInitial extends HealthPermissionsState {}

class HealthPermissionsLoading extends HealthPermissionsState {}

class HealthPermissionsGranted extends HealthPermissionsState {}

class HealthPermissionsDenied extends HealthPermissionsState {
  const HealthPermissionsDenied({this.permanentlyDenied = false});

  final bool permanentlyDenied;

  @override
  List<Object?> get props => [permanentlyDenied];
}

class HealthPermissionsUnavailable extends HealthPermissionsState {}

class HealthPermissionsFailure extends HealthPermissionsState {
  const HealthPermissionsFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class HealthPermissionsBloc
    extends Bloc<HealthPermissionsEvent, HealthPermissionsState> {
  HealthPermissionsBloc(this._repository) : super(HealthPermissionsInitial()) {
    on<HealthPermissionsStatusRequested>(_onStatusRequested);
    on<HealthPermissionsGrantRequested>(_onGrantRequested);
    on<HealthPermissionsDenialCleared>(_onDenialCleared);
  }

  final HealthMetricsRepository _repository;

  Future<void> _onStatusRequested(
    HealthPermissionsStatusRequested event,
    Emitter<HealthPermissionsState> emit,
  ) async {
    if (!event.silent) {
      emit(HealthPermissionsLoading());
    }
    try {
      final status = await _repository.getPermissionsStatus();
      emit(_mapStatusToState(status));
    } catch (error) {
      emit(
        const HealthPermissionsFailure(
          'Unable to determine health permissions',
        ),
      );
    }
  }

  Future<void> _onGrantRequested(
    HealthPermissionsGrantRequested event,
    Emitter<HealthPermissionsState> emit,
  ) async {
    emit(HealthPermissionsLoading());
    try {
      final status = await _repository.requestPermissions();
      emit(_mapStatusToState(status));
    } catch (error) {
      emit(const HealthPermissionsFailure('Unable to request permissions'));
    }
  }

  Future<void> _onDenialCleared(
    HealthPermissionsDenialCleared event,
    Emitter<HealthPermissionsState> emit,
  ) async {
    await _repository.resetPermissionDenialFlag();
    add(const HealthPermissionsStatusRequested());
  }

  HealthPermissionsState _mapStatusToState(HealthPermissionsStatus status) {
    if (!status.isServiceAvailable) {
      return HealthPermissionsUnavailable();
    }
    if (status.hasPermissions) {
      return HealthPermissionsGranted();
    }
    return HealthPermissionsDenied(permanentlyDenied: status.deniedPermanently);
  }
}
