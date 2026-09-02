import 'package:flutter/widgets.dart';

import '../model/evaluator_state.dart';

class EvaluatorScope extends InheritedNotifier<EvaluatorState> {
  const EvaluatorScope({
    super.key,
    required EvaluatorState state,
    required super.child,
  }) : super(notifier: state);

  static EvaluatorState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EvaluatorScope>()!.notifier!;
}
