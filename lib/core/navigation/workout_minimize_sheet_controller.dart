import 'package:flutter/widgets.dart';

/// Handle exposed by the active-workout route transition to its screen.
///
/// The transition owns the animation; the screen only supplies input from its
/// collapse control and drag handle. Keeping navigation motion outside the
/// workout screen prevents its logging state from rebuilding on every frame.
class WorkoutMinimizeSheetController {
  const WorkoutMinimizeSheetController({
    required bool Function(BuildContext context) canDrag,
    required void Function(BuildContext context, double deltaFraction) dragBy,
    required Future<void> Function(BuildContext context, double velocity)
    release,
    required Future<void> Function(BuildContext context) cancel,
    required Future<void> Function(BuildContext context) minimize,
  }) : _canDrag = canDrag,
       _dragBy = dragBy,
       _release = release,
       _cancel = cancel,
       _minimize = minimize;

  final bool Function(BuildContext context) _canDrag;
  final void Function(BuildContext context, double deltaFraction) _dragBy;
  final Future<void> Function(BuildContext context, double velocity) _release;
  final Future<void> Function(BuildContext context) _cancel;
  final Future<void> Function(BuildContext context) _minimize;

  bool canDrag(BuildContext context) => _canDrag(context);

  void dragBy(BuildContext context, double deltaFraction) =>
      _dragBy(context, deltaFraction);

  Future<void> release(BuildContext context, double velocity) =>
      _release(context, velocity);

  Future<void> cancel(BuildContext context) => _cancel(context);

  Future<void> minimize(BuildContext context) => _minimize(context);
}

class WorkoutMinimizeSheetScope extends InheritedWidget {
  const WorkoutMinimizeSheetScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final WorkoutMinimizeSheetController controller;

  static WorkoutMinimizeSheetController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkoutMinimizeSheetScope>()
          ?.controller;

  @override
  bool updateShouldNotify(WorkoutMinimizeSheetScope oldWidget) =>
      oldWidget.controller != controller;
}
