import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/bootstrap/hustl_app_bootstrapper.dart';

void main() {
  test('challenge evaluator skips every post-app integration task', () {
    expect(shouldStartPostAppTasks(challengeMode: true), isFalse);
  });

  test('normal product keeps post-app integration tasks enabled', () {
    expect(shouldStartPostAppTasks(challengeMode: false), isTrue);
  });
}
