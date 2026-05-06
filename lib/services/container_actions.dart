import '../models/archived_task.dart';
import '../models/list.dart';
import '../models/task.dart';
import '../providers/settings_notifier.dart';
import 'firestore_list_service.dart';

/// Dispatcher for per-list mutations. Hides whether a list is Firestore-backed
/// (shared) or local/Drive-backed (personal) from the screens that drive the
/// UI. The screen passes the live `TaskList` and the action; this class picks
/// the right backend.
///
/// Firestore-backed mutations skip the local-cache code path entirely —
/// reads come from snapshot streams, so writing both would race with the
/// stream's authoritative view. Local/Drive mutations continue to flow
/// through SettingsNotifier so the existing offline + Drive sync behavior
/// is preserved.
class ContainerActions {
  ContainerActions(this._settings) : _firestore = FirestoreListService();
  final SettingsNotifier _settings;
  final FirestoreListService _firestore;

  bool _isFirestore(TaskList list) =>
      list.storage == ListStorage.firestore;

  Future<void> addTask(TaskList list, Task task) async {
    if (_isFirestore(list)) {
      await _firestore.addTask(list.id, task);
    } else {
      await _settings.addListTask(list.id, task);
    }
  }

  Future<void> updateTask(TaskList list, Task task) async {
    if (_isFirestore(list)) {
      await _firestore.updateTask(list.id, task);
    } else {
      await _settings.updateListTask(list.id, task);
    }
  }

  Future<void> removeTask(TaskList list, String taskId) async {
    if (_isFirestore(list)) {
      await _firestore.removeTask(list.id, taskId);
    } else {
      await _settings.removeListTask(list.id, taskId);
    }
  }

  Future<void> reorderTasks(TaskList list, int oldIndex, int newIndex) async {
    if (_isFirestore(list)) {
      // Firestore tasks aren't ordered yet — schema lacks a sortOrder field.
      // Phase 3.C can add one if drag-reorder on shared lists becomes a
      // requirement. For now reorder is a no-op on shared lists.
      return;
    }
    await _settings.reorderListTasks(list.id, oldIndex, newIndex);
  }

  /// Archives [task] without removing the active row — same contract as
  /// [SettingsNotifier.archiveListSnapshot]. Caller pairs with [removeTask]
  /// after the strike-through animation ends.
  Future<void> archiveSnapshot(TaskList list, Task task) async {
    if (_isFirestore(list)) {
      final entry = ArchivedTask.createNew(
        text: task.text,
        originId: list.id,
        originNameSnapshot: list.name,
        originColorSnapshot: list.color,
      );
      await _firestore.addArchive(list.id, entry);
    } else {
      await _settings.archiveListSnapshot(list, task);
    }
  }

  Future<void> restoreArchived(TaskList list, ArchivedTask entry) async {
    if (_isFirestore(list)) {
      // Reanimate as a new task; drop the archive row.
      final restored = Task.createNew(text: entry.text);
      await _firestore.addTask(list.id, restored);
      await _firestore.removeArchive(list.id, entry.id);
    } else {
      await _settings.restoreListArchivedTask(list.id, entry);
    }
  }

  Future<void> clearArchive(TaskList list) async {
    if (_isFirestore(list)) {
      await _firestore.clearArchive(list.id);
    } else {
      await _settings.clearListArchive(list.id);
    }
  }
}
