import 'package:uuid/uuid.dart';

// Represents a named list of tasks (a 'Notebook' in the app).
class TaskList {
  final String id;
  String name;
  final int createdAtTimestamp;

  TaskList({
    required this.id,
    required this.name,
    required this.createdAtTimestamp,
  });

  // Factory constructor for creating a brand new list
  factory TaskList.createNew({required String name}) {
    return TaskList(
      id: const Uuid().v4(),
      name: name,
      createdAtTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Converts the TaskList object to a JSON map for saving.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAtTimestamp': createdAtTimestamp,
      };

  // Creates a TaskList object from a JSON map when loading.
  factory TaskList.fromJson(Map<String, dynamic> json) => TaskList(
        id: json['id'],
        name: json['name'],
        createdAtTimestamp: json['createdAtTimestamp'],
      );

  // Creates a copy of the list with updated fields.
  TaskList copyWith({String? name}) {
    return TaskList(
      id: id,
      name: name ?? this.name,
      createdAtTimestamp: createdAtTimestamp,
    );
  }
}