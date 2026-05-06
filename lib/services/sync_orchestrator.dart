import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/auth_notifier.dart';
import '../providers/settings_notifier.dart';
import 'auth_service.dart';
import 'drive_sync_service.dart';

/// Coordinates Drive backups for personal lists.
///
/// Phase 2 contract — push-only backup:
/// - On sign-in, ensures the Drive folder exists and runs an initial bulk
///   push so the user's local state is mirrored remotely.
/// - On every mutation, debounces by 2s and pushes only the touched
///   containers (`root`, list UUIDs, or the manifest).
/// - On sign-out, drops the cached folder id and stops syncing; local data
///   is untouched.
///
/// Phase 2.1 will add the pull-side merge (per-list updatedAt LWW). For now
/// the orchestrator is a one-way mirror — adequate for backup but not for
/// multi-device sync.
class SyncOrchestrator {
  final SettingsNotifier _settings;
  final AuthNotifier _auth;
  final DriveSyncService _drive;

  StreamSubscription<String>? _dirtySub;
  final Set<String> _pendingDirty = <String>{};
  Timer? _debounceTimer;
  bool _running = false;
  bool _initialReconcileDone = false;

  SyncOrchestrator(this._settings, this._auth)
      : _drive = DriveSyncService(AuthService()) {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  // --- Public API ----------------------------------------------------------

  /// Forces a full push regardless of dirty tracking. Wired to the
  /// "Sync now" button in Settings; also used as the bulk-upload path on
  /// first sign-in.
  Future<void> syncNow() async {
    if (!_auth.signedIn) return;
    _pendingDirty
      ..add(kManifestDirtyKey)
      ..add('root');
    for (final l in _settings.taskLists) {
      _pendingDirty.add(l.id);
    }
    await _flush();
  }

  void dispose() {
    _detachDirty();
    _auth.removeListener(_onAuthChanged);
  }

  // --- Lifecycle -----------------------------------------------------------

  void _onAuthChanged() {
    if (_auth.signedIn) {
      _attachDirty();
      // Don't await — the orchestrator lives outside the widget tree and the
      // initial reconcile shouldn't block sign-in.
      unawaited(_scheduleInitialSync());
    } else {
      _detachDirty();
      _drive.resetCache();
      _pendingDirty.clear();
      _initialReconcileDone = false;
    }
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
    final manifest = await _drive.pullManifest();
    if (manifest == null) {
      // Fresh Drive — bulk push every container.
      await syncNow();
    } else {
      // Phase 2.1 will do a per-list LWW merge here. For now the local copy
      // is authoritative on the active device; just push current state so
      // remote stays at-or-newer-than the most recent local edit.
      await syncNow();
    }
  }

  // --- Push pipeline -------------------------------------------------------

  Future<void> _flush() async {
    if (_running || !_auth.signedIn) return;
    if (_pendingDirty.isEmpty) return;
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
