import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/archived_task.dart';
import '../models/list.dart';
import '../models/repeat_interval.dart';
import '../models/task.dart';

/// CRUD + realtime streams for Firestore-backed (shared) lists.
///
/// Schema:
/// ```
/// users/{uid}                          { email, displayName, updatedAt }
/// lists/{listId}                       { ownerUid, collaboratorUids[], name,
///                                        color, iconEmoji, iconCodePoint,
///                                        themeOverride, parentId, sortOrder,
///                                        updatedAt }
///   tasks/{taskId}                     { text, reminderDateTime, repeat,
///                                        updatedAt }
///   archive/{archiveId}                { text, archivedAtTimestamp,
///                                        originId, originNameSnapshot,
///                                        originColorSnapshot }
/// invites/{token}                      { listId, inviterUid, email,
///                                        createdAt, status }
/// ```
///
/// Every method gracefully no-ops when Firebase isn't initialized so this
/// class is safe to instantiate on every machine — including ones that
/// haven't run `flutterfire configure` yet.
class FirestoreListService {
  static FirestoreListService? _instance;
  factory FirestoreListService() => _instance ??= FirestoreListService._();
  FirestoreListService._();

  bool get _ready => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // --- List metadata -------------------------------------------------------

  /// Streams the live list document. Emits null if the list is deleted or
  /// inaccessible (security rules denied).
  Stream<TaskList?> streamList(String listId) {
    if (!_ready) return Stream.value(null);
    return _db
        .collection('lists')
        .doc(listId)
        .snapshots()
        .map((snap) => snap.exists ? _decodeList(listId, snap.data()!) : null)
        .handleError((e) {
      debugPrint('FirestoreListService.streamList($listId) error: $e');
    });
  }

  /// One-shot fetch — used by the migrator to verify a write before
  /// deleting the source.
  Future<TaskList?> getList(String listId) async {
    if (!_ready) return null;
    try {
      final snap = await _db.collection('lists').doc(listId).get();
      return snap.exists ? _decodeList(listId, snap.data()!) : null;
    } catch (e) {
      debugPrint('FirestoreListService.getList($listId) failed: $e');
      return null;
    }
  }

  /// Streams every Firestore list the current user can see (owned or
  /// collaborated). Used by the home screen to surface shared lists alongside
  /// local ones in Phase 4.
  Stream<List<TaskList>> streamMyLists(String uid) {
    if (!_ready) return Stream.value(const []);
    return _db
        .collection('lists')
        .where(Filter.or(
          Filter('ownerUid', isEqualTo: uid),
          Filter('collaboratorUids', arrayContains: uid),
        ))
        .snapshots()
        .map((qs) =>
            qs.docs.map((d) => _decodeList(d.id, d.data())).toList())
        .handleError((e) {
      debugPrint('FirestoreListService.streamMyLists error: $e');
    });
  }

  Future<void> upsertList(TaskList list) async {
    if (!_ready) return;
    try {
      await _db.collection('lists').doc(list.id).set({
        'ownerUid': list.ownerUid,
        'collaboratorUids': list.collaboratorUids,
        'name': list.name,
        'color': list.color,
        'iconEmoji': list.iconEmoji,
        'iconCodePoint': list.iconCodePoint,
        'parentId': list.parentId,
        'sortOrder': list.sortOrder,
        'themeOverride': list.themeOverride?.toJson(),
        'updatedAt': list.updatedAt,
        'createdAtTimestamp': list.createdAtTimestamp,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('FirestoreListService.upsertList failed: $e');
      rethrow;
    }
  }

  Future<void> deleteList(String listId) async {
    if (!_ready) return;
    try {
      // Firestore has no recursive delete client-side; clear subcollections
      // first, then the doc. Limit batches to 400 ops (well under 500 cap).
      await _wipeSubcollection('lists/$listId/tasks');
      await _wipeSubcollection('lists/$listId/archive');
      await _db.collection('lists').doc(listId).delete();
    } catch (e) {
      debugPrint('FirestoreListService.deleteList failed: $e');
    }
  }

  Future<void> _wipeSubcollection(String path) async {
    while (true) {
      final snap = await _db.collection(path).limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) return;
    }
  }

  // --- Tasks ---------------------------------------------------------------

  Stream<List<Task>> streamTasks(String listId) {
    if (!_ready) return Stream.value(const []);
    return _db
        .collection('lists/$listId/tasks')
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map((d) => _decodeTask(d.id, d.data())).toList())
        .handleError((e) {
      debugPrint('FirestoreListService.streamTasks($listId) error: $e');
    });
  }

  Future<void> addTask(String listId, Task task) async {
    if (!_ready) return;
    try {
      await _db.collection('lists/$listId/tasks').doc(task.id).set({
        'text': task.text,
        'reminderDateTime': task.reminderDateTime?.millisecondsSinceEpoch,
        'repeat': task.repeat?.name,
        'updatedAt': task.updatedAt,
        'createdAtMs': task.updatedAt,
      });
    } catch (e) {
      debugPrint('FirestoreListService.addTask failed: $e');
    }
  }

  Future<void> updateTask(String listId, Task task) async {
    if (!_ready) return;
    try {
      await _db.collection('lists/$listId/tasks').doc(task.id).set({
        'text': task.text,
        'reminderDateTime': task.reminderDateTime?.millisecondsSinceEpoch,
        'repeat': task.repeat?.name,
        'updatedAt': task.updatedAt,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('FirestoreListService.updateTask failed: $e');
    }
  }

  Future<void> removeTask(String listId, String taskId) async {
    if (!_ready) return;
    try {
      await _db.collection('lists/$listId/tasks').doc(taskId).delete();
    } catch (e) {
      debugPrint('FirestoreListService.removeTask failed: $e');
    }
  }

  // --- Archive -------------------------------------------------------------

  Stream<List<ArchivedTask>> streamArchive(String listId) {
    if (!_ready) return Stream.value(const []);
    return _db
        .collection('lists/$listId/archive')
        .orderBy('archivedAtTimestamp', descending: true)
        .snapshots()
        .map((qs) =>
            qs.docs.map((d) => _decodeArchive(d.id, d.data())).toList())
        .handleError((e) {
      debugPrint('FirestoreListService.streamArchive($listId) error: $e');
    });
  }

  Future<void> addArchive(String listId, ArchivedTask entry) async {
    if (!_ready) return;
    try {
      await _db.collection('lists/$listId/archive').doc(entry.id).set({
        'text': entry.text,
        'archivedAtTimestamp': entry.archivedAtTimestamp,
        'originId': entry.originId,
        'originNameSnapshot': entry.originNameSnapshot,
        'originColorSnapshot': entry.originColorSnapshot,
      });
    } catch (e) {
      debugPrint('FirestoreListService.addArchive failed: $e');
    }
  }

  Future<void> removeArchive(String listId, String archiveId) async {
    if (!_ready) return;
    try {
      await _db.collection('lists/$listId/archive').doc(archiveId).delete();
    } catch (e) {
      debugPrint('FirestoreListService.removeArchive failed: $e');
    }
  }

  Future<void> clearArchive(String listId) async {
    if (!_ready) return;
    await _wipeSubcollection('lists/$listId/archive');
  }

  // --- Decoders ------------------------------------------------------------

  TaskList _decodeList(String id, Map<String, dynamic> data) {
    final collabRaw = data['collaboratorUids'];
    final collab = collabRaw is List
        ? collabRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    final created = (data['createdAtTimestamp'] as int?) ??
        (data['updatedAt'] as int?) ??
        DateTime.now().millisecondsSinceEpoch;
    return TaskList(
      id: id,
      name: (data['name'] as String?) ?? 'Untitled',
      createdAtTimestamp: created,
      parentId: data['parentId'] as String?,
      color: (data['color'] as num?)?.toInt(),
      iconEmoji: data['iconEmoji'] as String?,
      iconCodePoint: data['iconCodePoint'] as String?,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      updatedAt: (data['updatedAt'] as num?)?.toInt() ?? created,
      storage: ListStorage.firestore,
      ownerUid: data['ownerUid'] as String?,
      collaboratorUids: collab,
    );
  }

  Task _decodeTask(String id, Map<String, dynamic> data) {
    final reminderMs = data['reminderDateTime'];
    return Task(
      id: id,
      text: (data['text'] as String?) ?? '',
      reminderDateTime: reminderMs is int
          ? DateTime.fromMillisecondsSinceEpoch(reminderMs)
          : null,
      repeat: RepeatInterval.fromName(data['repeat'] as String?),
      updatedAt: (data['updatedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  ArchivedTask _decodeArchive(String id, Map<String, dynamic> data) {
    return ArchivedTask(
      id: id,
      text: (data['text'] as String?) ?? '',
      archivedAtTimestamp: (data['archivedAtTimestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      originId: (data['originId'] as String?) ?? 'unknown',
      originNameSnapshot:
          (data['originNameSnapshot'] as String?) ?? 'Unknown',
      originColorSnapshot: (data['originColorSnapshot'] as num?)?.toInt(),
    );
  }
}
