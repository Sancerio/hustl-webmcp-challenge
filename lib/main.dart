import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/app.dart';
import 'src/model/evaluator_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final state = EvaluatorState();
  await state.loadFixtures();
  runApp(EvaluatorApp(state: state));
}
