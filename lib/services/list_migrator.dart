import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/list.dart';
import '../providers/auth_notifier.dart';
import '../providers/settings_notifier.dart';
import 'drive_sync_service.dart';
import 'firestore_list_service.dart';

/// Moves a list's data between Drive and Firestore when it's shared / unshared.
///
/// Each migration is write-target-first / verify / flip-flag / delete-source.
/// A failure mid-flight leaves the list in BOTH stores rather than losing
/// data — duplication is recoverable, deletion isn't.
///
/// Migrations no-op cleanly if Firebase isn't initialized; the UI gates the
/// "Share" entry on auth + Firebase availability anyway.
class ListMigrator {
  final SettingsNotifier _settings;
  final AuthNotifier _auth;
  final DriveSyncService _drive;
  final FirestoreListService _firestore;

  ListMigrator(this._settings, this._auth, this._drive)
      : _firestore = FirestoreListService();

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  /// Promotes a local/Drive-backed list to Firestore so it can be shared.
  /// Returns true on success; the list ends up with `storage = firestore`,
  /// `ownerUid = currentUser`, no collaborators yet.
  Future<bool> migrateDriveToFirestore(String listId) async {
    if (!_firebaseReady) return false;
    final uid = _auth.firebaseUid;
    if (uid == null) return false;
    final list = _settings.taskListById(listId);
    if (list == null) return false;
    if (list.storage == ListStorage.firestore) return true;

    await _settings.loadListIfNeeded(listId);
    final tasks = _settings.tasksFor(listId);
    final archive = _settings.archiveFor(listId);

    try {
      // Stage 1: write the list document with the new owner.
      final hydrated = list.copyWith(
        storage: ListStorage.firestore,
        ownerUid: uid,
        collaboratorUids: const <String>[],
      );
      await _firestore.upsertList(hydrated);

      // Stage 2: write tasks + archive subcollections.
      for (final t in tasks) {
        await _firestore.addTask(listId, t);
      }
      for (final a in archive) {
        await _firestore.addArchive(listId, a);
      }

      // Stage 3: verify by reading back.
      final readback = await _firestore.getList(listId);
      if (readback == null) {
        debugPrint('ListMigrator: read-back failed for $listId; aborting');
        return false;
      }

      // Stage 4: flip local list flag + drop the Drive copy.
      await _settings.updateTaskList(hydrated);
      await _drive.deleteContainer(listId);
      return true;
    } catch (e) {
      debugPrint('ListMigrator.migrateDriveToFirestore($listId) failed: $e');
      return false;
    }
  }

  /// Demotes a Firestore list back to Drive — used when the owner unshares
  /// (kicks all collaborators + flips storage). Caller must ensure no other
  /// collaborators are present before calling, otherwise their access goes
  /// away silently.
  Future<bool> migrateFirestoreToDrive(String listId) async {
    if (!_firebaseReady) return false;
    final list = _settings.taskListById(listId);
    if (list == null) return false;
    if (list.storage != ListStorage.firestore) return true;

    try {
      // Local cache is the source of truth at this point — Phase 3.B will
      // populate it from Firestore streams while the list is shared.
      final demoted = list.copyWith(
        storage: ListStorage.local,
        ownerUid: null,
        collaboratorUids: const <String>[],
      );

      // Drive push happens automatically once the local flag flips and the
      // sync orchestrator picks up the dirty event, so nothing to do here
      // except update the local row.
      await _settings.updateTaskList(demoted);

      // Tear down the remote copy.
      await _firestore.deleteList(listId);
      return true;
    } catch (e) {
      debugPrint('ListMigrator.migrateFirestoreToDrive($listId) failed: $e');
      return false;
    }
  }
}
