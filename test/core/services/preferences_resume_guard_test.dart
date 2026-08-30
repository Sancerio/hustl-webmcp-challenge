import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upload offset clamps negatives to zero and clears correctly', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    await prefs.setWorkoutsUploadOffset(-10);
    expect(await prefs.getWorkoutsUploadOffset(), 0);

    await prefs.setWorkoutsUploadOffset(5);
    expect(await prefs.getWorkoutsUploadOffset(), 5);

    await prefs.setWorkoutsUploadSignature('sig');
    await prefs.clearWorkoutsUploadProgress();
    expect(await prefs.getWorkoutsUploadSignature(), isNull);
    expect(await prefs.getWorkoutsUploadOffset(), 0);
  });
}
