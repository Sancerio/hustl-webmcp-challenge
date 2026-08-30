import 'package:equatable/equatable.dart';

class WorkoutTemplate extends Equatable {
  final String id;
  final String name;
  final String description;
  final List<dynamic>
  exercises; // Using dynamic for simplicity, would be TemplateExercise in a full implementation
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.exercises,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    exercises,
    createdAt,
    updatedAt,
  ];

  WorkoutTemplate copyWith({
    String? id,
    String? name,
    String? description,
    List<dynamic>? exercises,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkoutTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      exercises: exercises ?? this.exercises,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Factory to create from JSON
  factory WorkoutTemplate.fromJson(Map<String, dynamic> json) {
    return WorkoutTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      exercises: (json['exercises'] as List<dynamic>?) ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'exercises': exercises,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
