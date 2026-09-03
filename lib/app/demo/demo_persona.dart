import '../../features/auth/domain/entities/auth_user.dart';

/// Static identity + headline numbers for the demo persona "Alex".
///
/// Every value here is a fixed constant so demo screens are reproducible for
/// screenshots and visual-regression shots (spec §10).
class DemoPersona {
  const DemoPersona._();

  static const String userId = 'demo-alex';
  static const String displayName = 'Alex';
  static const String email = 'alex@demo.hustl.app';
  static const String? photoUrl = null;

  /// Height used to derive BMI in health summaries.
  static const double heightCm = 180.0;

  /// 90-day body-weight journey (kg). Start/end are pinned by the spec.
  static const double weightStartKg = 84.2;
  static const double weightEndKg = 81.6;

  /// Authenticated user returned instantly by the demo auth repository.
  static const AuthUser user = AuthUser(
    id: userId,
    provider: AuthProvider.google,
    displayName: displayName,
    email: email,
    photoUrl: photoUrl,
  );
}
