import 'package:flutter/material.dart';
import '../widgets/exercise_list_screen_base.dart';
import '../widgets/custom_exercise_form.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final ValueNotifier<int> _refreshSignal = ValueNotifier<int>(0);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _refreshSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      scaffoldKey: _scaffoldKey,
      child: ExerciseListScreenBase(
        appBarTitle: 'Exercises',
        showMenuButton: true,
        menuScaffoldKey: _scaffoldKey,
        allowFilters: true,
        allowSharedExercises: true,
        refreshSignal: _refreshSignal,
        appBarTrailing: IconButton(
          icon: HustlIcon(
            asset: 'assets/icons/ic_add.svg',
            size: 24,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          tooltip: 'Create Custom',
          onPressed: () async {
            final created = await showCustomExerciseForm(context);
            if (!mounted || created == null) return;
            _refreshSignal.value++;
            // Use the State's own context so the mounted guard above applies.
            HustlSnack.show(
              this.context,
              'Custom exercise created',
              variant: HustlSnackVariant.success,
              duration: const Duration(seconds: 2),
            );
          },
        ),
        onExerciseTap: (context, exercise) {
          final slug = exercise.canonicalKey;
          if (slug == null || slug.isEmpty) {
            context.push('/exercise_detail', extra: exercise);
            return;
          }
          context.push('/exercise_library/$slug');
        },
      ),
    );
  }
}
