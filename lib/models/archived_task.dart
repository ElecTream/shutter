import 'package:uuid/uuid.dart';

// Represents a task that has been completed and archived.
// Carries an origin snapshot so the global archive view can render provenance
// even after the origin list has been deleted.
class ArchivedTask {
  final String id;
  final String text;
  final int archivedAtTimestamp;
  final String originId; // "root" or a list UUID.
  final String originNameSnapshot;
  final int? originColorSnapshot;

  ArchivedTask({
    required this.id,
    required this.text,
    required this.archivedAtTimestamp,
    required this.originId,
    required this.originNameSnapshot,
    this.originColorSnapshot,
  });

  factory ArchivedTask.createNew({
    required String text,
    required String originId,
    required String originNameSnapshot,
    int? originColorSnapshot,
  }) {
    return ArchivedTask(
      id: const Uuid().v4(),
      text: text,
      archivedAtTimestamp: DateTime.now().millisecondsSinceEpoch,
      originId: originId,
      originNameSnapshot: originNameSnapshot,
      originColorSnapshot: originColorSnapshot,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'archivedAtTimestamp': archivedAtTimestamp,
        'originId': originId,
        'originNameSnapshot': originNameSnapshot,
        'originColorSnapshot': originColorSnapshot,
      };

  factory ArchivedTask.fromJson(Map<String, dynamic> json) => ArchivedTask(
        id: (json['id'] as String?) ?? const Uuid().v4(),
        text: json['text'] as String,
        archivedAtTimestamp: json['archivedAtTimestamp'] as int,
        originId: (json['originId'] as String?) ?? 'unknown',
        originNameSnapshot: (json['originNameSnapshot'] as String?) ?? 'Unknown',
        originColorSnapshot: json['originColorSnapshot'] as int?,
      );
}
