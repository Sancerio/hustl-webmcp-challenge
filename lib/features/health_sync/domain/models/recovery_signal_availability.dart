import 'package:equatable/equatable.dart';

/// The four core recovery signals the readiness model leans on. Availability is
/// derived from whether the signal *actually returns data* — never from a
/// permission boolean, since iOS does not confirm read denial and a "granted"
/// connection can still mean zero data.
enum RecoverySignal { hrv, restingHeartRate, sleep, respiratoryRate }

extension RecoverySignalDisplay on RecoverySignal {
  /// Kind, non-technical label for a targeted re-grant prompt.
  String get displayLabel {
    switch (this) {
      case RecoverySignal.hrv:
        return 'heart rate variability';
      case RecoverySignal.restingHeartRate:
        return 'resting heart rate';
      case RecoverySignal.sleep:
        return 'sleep';
      case RecoverySignal.respiratoryRate:
        return 'breathing rate';
    }
  }
}

/// Whether the underlying provider (Health Connect on Android) is reachable at
/// all. iOS is treated as [available] because HealthKit is built in; the real
/// gap on iOS is per-signal data, captured by [RecoverySignalAvailability].
enum HealthProviderAvailability {
  /// Provider is installed and ready (iOS HealthKit, or Android Health Connect
  /// present and up to date).
  available,

  /// Android only: Health Connect is missing entirely and can be routed to an
  /// install action.
  needsInstall,

  /// Android only: Health Connect is installed but its provider component is out
  /// of date and must be updated before it can supply data. Routes to the same
  /// Play listing as [needsInstall] but with update-oriented copy.
  needsUpdate,

  /// The platform cannot supply health data at all (e.g. web, unsupported OS).
  unsupported,
}

/// Per-signal availability derived from whether each recovery signal is
/// actually flowing, plus the provider reachability. Fully additive: with no
/// recovery data every field reads as "no signals yet" and surfaces behave
/// exactly as today.
class RecoverySignalAvailability extends Equatable {
  const RecoverySignalAvailability({
    this.providerAvailability = HealthProviderAvailability.available,
    this.hrv = false,
    this.restingHeartRate = false,
    this.sleep = false,
    this.respiratoryRate = false,
  });

  /// Empty default: nothing flowing yet, provider assumed reachable. Surfaces
  /// gate on [hasAnySignal] / [missingSignals] so this reads as "today".
  static const RecoverySignalAvailability empty = RecoverySignalAvailability();

  final HealthProviderAvailability providerAvailability;
  final bool hrv;
  final bool restingHeartRate;
  final bool sleep;
  final bool respiratoryRate;

  bool isAvailable(RecoverySignal signal) {
    switch (signal) {
      case RecoverySignal.hrv:
        return hrv;
      case RecoverySignal.restingHeartRate:
        return restingHeartRate;
      case RecoverySignal.sleep:
        return sleep;
      case RecoverySignal.respiratoryRate:
        return respiratoryRate;
    }
  }

  /// True when at least one core recovery signal is flowing.
  bool get hasAnySignal => hrv || restingHeartRate || sleep || respiratoryRate;

  /// True when every core recovery signal is flowing.
  bool get hasAllSignals => hrv && restingHeartRate && sleep && respiratoryRate;

  /// The signals that are not currently flowing — what a targeted re-grant
  /// prompt should ask the user to turn on. Respiratory rate is treated as a
  /// bonus signal and only listed once the core three are present, so an
  /// early-stage user is not nagged about a signal their watch may never write.
  List<RecoverySignal> get missingSignals {
    final core = <RecoverySignal>[
      if (!hrv) RecoverySignal.hrv,
      if (!restingHeartRate) RecoverySignal.restingHeartRate,
      if (!sleep) RecoverySignal.sleep,
    ];
    if (core.isEmpty && !respiratoryRate) {
      return const [RecoverySignal.respiratoryRate];
    }
    return core;
  }

  RecoverySignalAvailability copyWith({
    HealthProviderAvailability? providerAvailability,
    bool? hrv,
    bool? restingHeartRate,
    bool? sleep,
    bool? respiratoryRate,
  }) {
    return RecoverySignalAvailability(
      providerAvailability: providerAvailability ?? this.providerAvailability,
      hrv: hrv ?? this.hrv,
      restingHeartRate: restingHeartRate ?? this.restingHeartRate,
      sleep: sleep ?? this.sleep,
      respiratoryRate: respiratoryRate ?? this.respiratoryRate,
    );
  }

  @override
  List<Object?> get props => [
    providerAvailability,
    hrv,
    restingHeartRate,
    sleep,
    respiratoryRate,
  ];
}
