import 'package:equatable/equatable.dart';

import '../../domain/models/food_log_entry.dart';

sealed class DiaryEvent extends Equatable {
  const DiaryEvent();

  @override
  List<Object?> get props => [];
}

class LoadDiary extends DiaryEvent {
  const LoadDiary(this.date);
  final DateTime date;

  @override
  List<Object?> get props => [date];
}

class AddDiaryEntries extends DiaryEvent {
  const AddDiaryEntries(this.entries);
  final List<FoodLogEntry> entries;

  @override
  List<Object?> get props => [entries];
}

class DeleteDiaryEntry extends DiaryEvent {
  const DeleteDiaryEntry(this.entryId);
  final String entryId;

  @override
  List<Object?> get props => [entryId];
}

class UpdateDiaryEntry extends DiaryEvent {
  const UpdateDiaryEntry(this.entryId, this.patch);
  final String entryId;
  final Map<String, dynamic> patch;

  @override
  List<Object?> get props => [entryId, patch];
}
