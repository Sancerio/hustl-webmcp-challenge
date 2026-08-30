import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/navigation/app_router.dart';

void main() {
  test('challenge builds own the evaluator route', () {
    expect(demoRouteRedirectTarget(challengeMode: true), isNull);
  });

  test('normal builds redirect the evaluator route home', () {
    expect(demoRouteRedirectTarget(challengeMode: false), '/');
  });
}
