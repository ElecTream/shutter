import 'package:uuid/uuid.dart';

// Represents a single to-do item.
class Task {
  final String id;
  final String text;

  Task({required this.id, required this.text});

  // A special constructor to create a new task with a unique ID.
  factory Task.createNew({required String text}) {
    return Task(id: const Uuid().v4(), text: text);
  }

  // Converts the Task object to a JSON map for saving.
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
      };

  // Creates a Task object from a JSON map when loading.
  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        text: json['text'],
      );
}
