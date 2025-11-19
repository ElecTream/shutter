import 'package:uuid/uuid.dart';

// Represents a single to-do item.
class Task {
  final String id;
  final String text;
  final DateTime? reminderDateTime;

  Task({
    required this.id,
    required this.text,
    this.reminderDateTime,
  });

  // A special constructor to create a new task with a unique ID.
  factory Task.createNew({required String text}) {
    return Task(id: const Uuid().v4(), text: text);
  }

  // Converts the Task object to a JSON map for saving.
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'reminderDateTime': reminderDateTime?.millisecondsSinceEpoch,
      };

  // Creates a Task object from a JSON map when loading.
  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        text: json['text'],
        reminderDateTime: json['reminderDateTime'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['reminderDateTime'])
            : null,
      );

  // Creates a copy of the task with some updated fields.
  Task copyWith({String? text, DateTime? reminderDateTime}) {
    return Task(
      id: id,
      text: text ?? this.text,
      // Note: A null value is intentionally allowed to clear the reminder.
      reminderDateTime: reminderDateTime,
    );
  }
}