import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/archived_task.dart';
import '../models/list.dart';
import '../models/task.dart';
import '../providers/auth_notifier.dart';
import '../providers/settings_notifier.dart';
import 'auth_service.dart';
import 'drive_sync_service.dart';
import 'firestore_list_service.dart';

/// Coordinates Drive sync for personal lists.
///
/// - On sign-in, ensures the Drive folder exists then runs a full reconcile
///   (push pending dirty, then pull manifest + every container).
/// - On every mutation, debounces by 2s and pushes only the touched
///   containers (`root`, list UUIDs, or the manifest).
/// - "Sync now" and app resume call [syncNow], which pushes any pending
///   dirty work then pulls remote state. Per-list LWW on the manifest;
///   container-level LWW (file `updatedAt` vs local max record `updatedAt`)
///   on tasks/archive.
/// - On sign-out, drops the cached folder id and stops syncing; local data
///   is untouched.
class SyncOrchestrator {
  final SettingsNotifier _settings;
  final AuthNotifier _auth;
  final DriveSyncService _drive;

  StreamSubscription<String>? _dirtySub;
  StreamSubscription<List<TaskList>>? _firestoreListsSub;
  String? _firestoreListsUid;
  final FirestoreListService _firestore;
  final Set<String> _pendingDirty = <String>{};
  Timer? _debounceTimer;
  bool _running = false;
  bool _initialReconcileDone = false;

  SyncOrchestrator(this._settings, this._auth)
      : _drive = DriveSyncService(AuthService()),
        _firestore = FirestoreListService() {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  // --- Public API ----------------------------------------------------------

  /// Push then pull — full reconcile. Wired to the "Sync now" button in
  /// Settings, the initial sign-in path, and app-resume.
  ///
  /// Push first so any local edits queued for sync are uploaded before we
  /// adopt remote state. Then pull manifest + every container, applying
  /// per-list LWW on metadata and per-container LWW on tasks/archive.
  Future<void> syncNow() async {
    if (!_auth.signedIn) return;
    if (_running) return;

    // Stage 1: push every container the orchestrator knows about. This is a
    // superset of the dirty set so concurrent edits during the run don't get
    // skipped — we'd rather push redundantly than miss a change.
    _pendingDirty
      ..add(kManifestDirtyKey)
      ..add('root');
    for (final l in _settings.taskLists) {
      _pendingDirty.add(l.id);
    }
    await _flush();

    // Stage 2: pull and merge.
    await _pullAndMerge();
  }

  void dispose() {
    _detachDirty();
    _detachFirestoreLists();
    _auth.removeListener(_onAuthChanged);
  }

  // --- Lifecycle -----------------------------------------------------------

  void _onAuthChanged() {
    if (_auth.signedIn) {
      _attachDirty();
      _attachFirestoreLists();
      // Don't await — the orchestrator lives outside the widget tree and the
      // initial reconcile shouldn't block sign-in.
      unawaited(_scheduleInitialSync());
    } else {
      _detachDirty();
      _detachFirestoreLists();
      _drive.resetCache();
      _pendingDirty.clear();
      _initialReconcileDone = false;
    }
  }

  /// Subscribes to the lists the current user owns or collaborates on. Each
  /// snapshot replaces the firestore-backed slice of the local manifest so
  /// shared lists appear/disappear on the home screen as memberships change.
  /// FirebaseAuth credential exchange is async; the auth listener fires
  /// repeatedly while sign-in completes — re-attaching with the same uid
  /// is a no-op.
  void _attachFirestoreLists() {
    final uid = _auth.firebaseUid;
    if (uid == null) return;
    if (_firestoreListsSub != null && _firestoreListsUid == uid) return;
    _detachFirestoreLists();
    _firestoreListsUid = uid;
    _firestoreListsSub = _firestore.streamMyLists(uid).listen((lists) {
      _settings.beginRemoteApply();
      try {
        _settings.applyRemoteFirestoreLists(lists);
      } finally {
        _settings.endRemoteApply();
      }
    });
  }

  void _detachFirestoreLists() {
    _firestoreListsSub?.cancel();
    _firestoreListsSub = null;
    _firestoreListsUid = null;
  }

  void _attachDirty() {
    _dirtySub ??= _settings.dirtyContainers.listen((id) {
      _pendingDirty.add(id);
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), _flush);
    });
  }

  void _detachDirty() {
    _dirtySub?.cancel();
    _dirtySub = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  Future<void> _scheduleInitialSync() async {
    if (_initialReconcileDone) return;
    _initialReconcileDone = true;
    final folderId = await _drive.bootstrapFolder();
    if (folderId == null) return;
    // syncNow handles both branches: pulls a fresh manifest (no-op if the
    // remote is empty) and pushes whatever local has on top.
    await syncNow();
  }

  // --- Push pipeline -------------------------------------------------------

  Future<void> _flush() async {
    if (!_auth.signedIn) return;
    if (_pendingDirty.isEmpty) return;
    if (_running) {
      // A pull or earlier flush is in flight — reschedule so the dirty work
      // isn't lost. The next tick will see _running cleared and proceed.
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), _flush);
      return;
    }
    _running = true;
    try {
      final dirty = _pendingDirty.toSet();
      _pendingDirty.clear();
      for (final id in dirty) {
        if (id == kManifestDirtyKey) {
          await _pushManifest();
        } else {
          await _pushContainer(id);
        }
      }
    } catch (e) {
      debugPrint('SyncOrchestrator._flush failed: $e');
    } finally {
      _running = false;
      // If new dirty entries arrived during the flush, schedule another.
      if (_pendingDirty.isNotEmpty && _auth.signedIn) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 2), _flush);
      }
    }
  }

  Future<void> _pushManifest() async {
    final lists =
        _settings.taskLists.map((l) => l.toJson()).toList(growable: false);
    final manifest = <String, dynamic>{
      'schema': 1,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'lists': lists,
    };
    await _drive.pushManifest(manifest);
  }

  // --- Pull pipeline -------------------------------------------------------

  /// Pulls the remote manifest + every remote container and applies them
  /// to local state under [SettingsNotifier.beginRemoteApply] so the writes
  /// don't echo back as dirty events.
  ///
  /// Per-list LWW on the manifest; container body replaces local only when
  /// the file's `updatedAt` exceeds the local max record `updatedAt`.
  Future<void> _pullAndMerge() async {
    if (_running) return;
    _running = true;
    _settings.beginRemoteApply();
    try {
      final manifest = await _drive.pullManifest();
      if (manifest == null) return;

      // Manifest merge.
      final remoteListsRaw = (manifest['lists'] as List?) ?? const [];
      final remoteLists = <TaskList>[];
      for (final m in remoteListsRaw) {
        if (m is! Map) continue;
        try {
          remoteLists.add(TaskList.fromJson(Map<String, dynamic>.from(m)));
        } catch (e) {
          debugPrint('SyncOrchestrator manifest entry decode failed: $e');
        }
      }
      await _settings.applyRemoteManifest(remoteLists);

      // Container merge — root + every list now in the manifest. Skip
      // Firestore-backed lists; their data lives entirely on Firestore.
      final ids = <String>['root', ...remoteLists.map((l) => l.id)];
      for (final id in ids) {
        if (id != 'root') {
          final list = _settings.taskListById(id);
          if (list != null && list.storage == ListStorage.firestore) {
            continue;
          }
        }
        await _pullContainer(id);
      }
    } catch (e) {
      debugPrint('SyncOrchestrator._pullAndMerge failed: $e');
    } finally {
      _settings.endRemoteApply();
      _running = false;
    }
  }

  Future<void> _pullContainer(String id) async {
    final body = await _drive.pullContainer(id);
    if (body == null) return;
    final remoteUpdatedAt = (body['updatedAt'] as int?) ?? 0;
    final localUpdatedAt = _settings.localContainerUpdatedAt(id);
    if (remoteUpdatedAt <= localUpdatedAt) return;

    final tasks = <Task>[];
    for (final raw in (body['tasks'] as List?) ?? const []) {
      if (raw is! Map) continue;
      try {
        tasks.add(Task.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {}
    }
    final archive = <ArchivedTask>[];
    for (final raw in (body['archive'] as List?) ?? const []) {
      if (raw is! Map) continue;
      try {
        archive.add(ArchivedTask.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {}
    }
    await _settings.applyRemoteContainer(id, tasks: tasks, archive: archive);
  }

  Future<void> _pushContainer(String id) async {
    if (id == 'root') {
      final body = <String, dynamic>{
        'schema': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'tasks':
            _settings.rootTasks.map((t) => t.toJson()).toList(growable: false),
        'archive':
            _settings.rootArchive.map((a) => a.toJson()).toList(growable: false),
      };
      await _drive.pushContainer('root', body);
      return;
    }
    if (!_settings.listExists(id)) {
      // List was deleted locally — nuke the remote copy if present.
      await _drive.deleteContainer(id);
      return;
    }
    // Firestore-backed lists live entirely on Firestore; their Drive copy was
    // removed by the migrator on share. Skip pushing so we don't recreate it.
    final list = _settings.taskListById(id);
    if (list != null && list.storage == ListStorage.firestore) return;
    await _settings.loadListIfNeeded(id);
    final body = <String, dynamic>{
      'schema': 1,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'tasks': _settings
          .tasksFor(id)
          .map((t) => t.toJson())
          .toList(growable: false),
      'archive': _settings
          .archiveFor(id)
          .map((a) => a.toJson())
          .toList(growable: false),
    };
    await _drive.pushContainer(id, body);
  }
}
