import 'package:flutter/material.dart';

class SetRowStateLogic {
  const SetRowStateLogic._();

  static bool isWeightExplicit({
    required bool isDurationOnly,
    required bool isCompleted,
    required double weight,
    required bool wasConfirmed,
  }) {
    return isDurationOnly || isCompleted || weight.abs() > 0 || wasConfirmed;
  }

  static bool isRepsExplicit({
    required bool isCompleted,
    required int reps,
    required bool wasConfirmed,
  }) {
    return isCompleted || reps > 0 || wasConfirmed;
  }

  static void syncNumericController<T extends num>({
    required TextEditingController controller,
    required FocusNode focusNode,
    required T newValue,
    required T? fallbackValue,
    required bool isDurationOnly,
    required bool isConfirmed,
  }) {
    if (focusNode.hasFocus) return;

    final currentText = controller.text;
    final currentNum = num.tryParse(currentText);
    if (currentNum != null && currentNum == newValue) return;

    if (!isDurationOnly &&
        newValue == 0 &&
        (fallbackValue == null || fallbackValue == 0) &&
        !isConfirmed) {
      controller.clear();
      return;
    }

    if (newValue.abs() > 0 || isConfirmed) {
      controller.text = newValue.toString();
      return;
    }

    if (fallbackValue != null && fallbackValue.abs() > 0) {
      controller.text = fallbackValue.toString();
      return;
    }

    controller.clear();
  }

  static int? resolveCardioDraftSeconds({
    required int currentSecs,
    required int newValue,
    required int? fallbackValue,
    required bool isConfirmed,
  }) {
    if (currentSecs == newValue) return currentSecs;
    if (newValue > 0 || isConfirmed) return newValue;
    return fallbackValue;
  }
}
