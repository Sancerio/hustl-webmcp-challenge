import 'package:flutter/foundation.dart';

/// Keeps browser tools unavailable while auth/account migration is unresolved.
class WebMcpAccessGate {
  WebMcpAccessGate();

  final ValueNotifier<bool> ready = ValueNotifier(false);
  int _generation = 0;

  int get generation => _generation;

  void setReady(bool value) {
    if (ready.value != value) ready.value = value;
  }

  /// Closes access and invalidates every earlier asynchronous open attempt.
  int closeForTransition() {
    _generation += 1;
    setReady(false);
    return _generation;
  }

  /// Opens only if no newer auth transition has started in the meantime.
  void openIfCurrent(int generation) {
    if (generation == _generation) setReady(true);
  }

  bool isReadyFor(int generation) => ready.value && generation == _generation;
}
