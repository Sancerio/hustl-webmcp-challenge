import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/exercise.dart';

/// Provides a seed list of exercises bundled with the app for first run/offline.
abstract class ExerciseSeedDataSource {
  Future<List<Exercise>> loadSeed();
}

class AssetExerciseSeedDataSource implements ExerciseSeedDataSource {
  final String assetPath;

  const AssetExerciseSeedDataSource({
    this.assetPath = 'assets/data/exercises_seed.json',
  });

  @override
  Future<List<Exercise>> loadSeed() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final List<dynamic> data = jsonDecode(raw) as List<dynamic>;
      return data
          .map((e) => Exercise.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (_) {
      return const <Exercise>[];
    }
  }
}
