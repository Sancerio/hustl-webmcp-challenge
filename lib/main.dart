import 'package:flutter/material.dart';

import 'app/public_app.dart';
import 'app/public_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupPublicDependencies();
  runApp(const PublicHustlApp());
}
