import 'package:flutter/material.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/utils/time_format_util.dart';

import '../../domain/models/workout_set.dart';
import '../../domain/utils/effort_scale.dart';
import 'set_row_state_logic.dart';

part 'set_row_controller_commit.dart';
part 'set_row_controller_input.dart';
part 'set_row_controller_set_ops.dart';
part 'set_row_controller_sync.dart';

enum SetRowPersistKind { updated, completed }

class SetRowPersistEvent {
  final SetRowPersistKind kind;
  final WorkoutSet set;

  const SetRowPersistEvent._(this.kind, this.set);

  const SetRowPersistEvent.updated(WorkoutSet set)
    : this._(SetRowPersistKind.updated, set);

  const SetRowPersistEvent.completed(WorkoutSet set)
    : this._(SetRowPersistKind.completed, set);
}

class SetRowController extends ChangeNotifier {
  SetRowController({
    required WorkoutSet set,
    required ExerciseKind exerciseKind,
    required ExerciseLoggingMode loggingMode,
    WorkoutSet? previousSet,
  }) : _set = set,
       _previousSet = previousSet,
       _exerciseKind = exerciseKind,
       _loggingMode = loggingMode {
    _initializeControllers();
  }

  final TextEditingController weightController = TextEditingController();
  final TextEditingController repsController = TextEditingController();
  final FocusNode weightFocusNode = FocusNode();
  final FocusNode repsFocusNode = FocusNode();

  WorkoutSet _set;
  WorkoutSet? _previousSet;
  ExerciseKind _exerciseKind;
  ExerciseLoggingMode _loggingMode;

  bool _weightConfirmed = false;
  bool _repsConfirmed = false;
  bool _isEditingWeight = false;
  bool _isEditingReps = false;
  bool _durationDraftEdited = false;
  bool _suppressWeightBlurOnce = false;
  bool _suppressRepsBlurOnce = false;
  int? _cardioDraftSeconds;
  bool _isDisposed = false;

  WorkoutSet get set => _set;
  WorkoutSet? get previousSet => _previousSet;
  ExerciseKind get exerciseKind => _exerciseKind;
  ExerciseLoggingMode get loggingMode => _loggingMode;

  bool get isDistanceDuration =>
      _loggingMode == ExerciseLoggingMode.distanceDuration;
  bool get isDurationOnly => _loggingMode == ExerciseLoggingMode.durationOnly;
  bool get usesDurationField => isDistanceDuration || isDurationOnly;

  bool get isCompleted => _set.isCompleted;
  bool get isPr => _set.isPr;
  SetType get setType => _set.setType;
  int? get cardioDraftSeconds => _cardioDraftSeconds;

  /// Optional per-set Rate of Perceived Exertion (1-10), null when unset.
  int? get rpe => _set.rpe;

  bool get isWeightPrefilled {
    final prev = _previousSet;
    if (prev == null) return false;
    return (double.tryParse(weightController.text) ?? -1) == prev.weight &&
        !_weightConfirmed &&
        !isCompleted;
  }

  bool get isWeightPlaceholder {
    if (isDurationOnly || isCompleted) return false;
    if (_weightConfirmed) return false;
    final prevWeight = _previousSet?.weight ?? 0.0;
    if (prevWeight.abs() > 0) return false;
    final text = weightController.text.trim();
    return text.isEmpty || text == '0' || text == '0.0' || text == '0.00';
  }

  bool get isRepsPlaceholder {
    if (usesDurationField || isCompleted) return false;
    if (_repsConfirmed) return false;
    final prevReps = _previousSet?.reps ?? 0;
    if (prevReps > 0) return false;
    final text = repsController.text.trim();
    return text.isEmpty || text == '0';
  }

  bool get isRepsPrefilled {
    final prev = _previousSet;
    if (prev == null || isCompleted) return false;

    if (usesDurationField) {
      return !_durationDraftEdited &&
          (_cardioDraftSeconds ?? -1) == prev.reps &&
          !_repsConfirmed;
    }

    return repsController.text == prev.reps.toString() && !_repsConfirmed;
  }

  void _notify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    weightController.dispose();
    repsController.dispose();
    weightFocusNode.dispose();
    repsFocusNode.dispose();
    super.dispose();
  }
}
