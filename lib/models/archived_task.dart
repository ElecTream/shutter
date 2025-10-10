import 'dart:convert';

// Represents a task that has been completed and archived.
class ArchivedTask {
  final String text;
  final int archivedAtTimestamp; // When the task was archived.

  ArchivedTask({required this.text, required this.archivedAtTimestamp});

  // Converts the ArchivedTask object to a JSON map.
  Map<String, dynamic> toJson() => {
        'text': text,
        'archivedAtTimestamp': archivedAtTimestamp,
      };

  // Creates an ArchivedTask object from a JSON map.
  factory ArchivedTask.fromJson(Map<String, dynamic> json) => ArchivedTask(
        text: json['text'],
        archivedAtTimestamp: json['archivedAtTimestamp'],
      );
}
