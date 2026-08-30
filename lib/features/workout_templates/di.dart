import 'package:get_it/get_it.dart';
import 'domain/repositories/template_repository.dart';
// import 'data/repositories/mock_template_repository.dart';
import 'data/repositories/local_template_repository.dart';

void setupWorkoutTemplatesDependencies(GetIt getIt) {
  // Register repositories
  if (!getIt.isRegistered<TemplateRepository>()) {
    getIt.registerLazySingleton<TemplateRepository>(
      () => LocalTemplateRepository(),
    );
  }

  // Register services if needed

  // Register blocs if needed
}
