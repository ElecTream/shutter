import 'package:uuid/uuid.dart';
import 'repeat_interval.dart';

// Represents a single to-do item. Containership (root / list UUID) is implicit
// via the SharedPreferences key the task is stored under; there is no listId.
class Task {
  final String id;
  final String text;
  final DateTime? reminderDateTime;
  final RepeatInterval? repeat; // null = one-shot reminder.

  Task({
    required this.id,
    required this.text,
    this.reminderDateTime,
    this.repeat,
  });

  factory Task.createNew({required String text}) {
    return Task(id: const Uuid().v4(), text: text);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'reminderDateTime': reminderDateTime?.millisecondsSinceEpoch,
        'repeat': repeat?.name,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        text: json['text'] as String,
        reminderDateTime: json['reminderDateTime'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['reminderDateTime'] as int)
            : null,
        repeat: RepeatInterval.fromName(json['repeat'] as String?),
      );

  // NOTE: reminderDateTime and repeat are intentionally used-as-passed (not
  // ??-defaulted), so callers can clear them by passing null. This matches the
  // existing contract for reminderDateTime; callers that want to preserve
  // either value must pass it explicitly.
  Task copyWith({
    String? text,
    DateTime? reminderDateTime,
    RepeatInterval? repeat,
  }) {
    return Task(
      id: id,
      text: text ?? this.text,
      reminderDateTime: reminderDateTime,
      repeat: repeat,
    );
  }
}
