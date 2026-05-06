import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'auth_service.dart';

/// Drive layout under the user's own Drive (drive.file scope only):
///
///   Shutter/                              [app folder, single per account]
///     manifest.json                       [taskLists metadata + scalar prefs]
///     container_root.json                 [root tasks + archive snapshot]
///     container_<listUuid>.json           [per-list tasks + archive snapshot]
///
/// Every file lives at the *folder root* — Drive doesn't enforce uniqueness
/// by name, so we always look up by `appProperties.shutterId` to recover from
/// rename collisions or stale folder layouts. The first call to
/// [bootstrapFolder] creates the folder if missing and caches its ID.
class DriveSyncService {
  static const String _folderName = 'Shutter';
  static const String _shutterIdKey = 'shutterId';
  static const String _manifestId = '__manifest__';

  final AuthService _auth;
  String? _folderId;

  DriveSyncService(this._auth);

  Future<drive.DriveApi?> _api() async {
    final client = await _auth.driveClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  /// Resolves the Shutter folder's ID, creating it if necessary. Caches
  /// in-memory; survives the lifetime of the service instance.
  Future<String?> bootstrapFolder() async {
    if (_folderId != null) return _folderId;
    final api = await _api();
    if (api == null) return null;

    try {
      final res = await api.files.list(
        q: "name='$_folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      final files = res.files ?? const <drive.File>[];
      if (files.isNotEmpty) {
        _folderId = files.first.id;
        return _folderId;
      }
      final created = await api.files.create(
        drive.File()
          ..name = _folderName
          ..mimeType = 'application/vnd.google-apps.folder',
        $fields: 'id',
      );
      _folderId = created.id;
      return _folderId;
    } catch (e) {
      debugPrint('DriveSyncService.bootstrapFolder failed: $e');
      return null;
    }
  }

  /// Looks up a Shutter-tagged file by logical ID inside the app folder.
  /// Returns null if the file doesn't exist yet.
  Future<drive.File?> _findByShutterId(drive.DriveApi api, String shutterId,
      String folderId) async {
    final res = await api.files.list(
      q: "'$folderId' in parents and trashed=false and "
          "appProperties has { key='$_shutterIdKey' and value='$shutterId' }",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime, appProperties)',
    );
    final files = res.files ?? const <drive.File>[];
    return files.isEmpty ? null : files.first;
  }

  /// Pulls the manifest JSON or null if absent.
  Future<Map<String, dynamic>?> pullManifest() async {
    final folderId = await bootstrapFolder();
    final api = await _api();
    if (folderId == null || api == null) return null;
    try {
      final f = await _findByShutterId(api, _manifestId, folderId);
      if (f == null) return null;
      return await _downloadJson(api, f.id!);
    } catch (e) {
      debugPrint('DriveSyncService.pullManifest failed: $e');
      return null;
    }
  }

  /// Writes the manifest JSON, creating or overwriting the existing file.
  Future<bool> pushManifest(Map<String, dynamic> manifest) async {
    return _writeJson(_manifestId, 'manifest.json', manifest);
  }

  /// Pulls a per-container JSON or null if absent. [containerId] is 'root' or
  /// a list UUID.
  Future<Map<String, dynamic>?> pullContainer(String containerId) async {
    final folderId = await bootstrapFolder();
    final api = await _api();
    if (folderId == null || api == null) return null;
    try {
      final f =
          await _findByShutterId(api, 'container_$containerId', folderId);
      if (f == null) return null;
      return await _downloadJson(api, f.id!);
    } catch (e) {
      debugPrint('DriveSyncService.pullContainer($containerId) failed: $e');
      return null;
    }
  }

  /// Writes a per-container JSON.
  Future<bool> pushContainer(
      String containerId, Map<String, dynamic> body) async {
    return _writeJson(
      'container_$containerId',
      'container_$containerId.json',
      body,
    );
  }

  /// Deletes a per-container file (used when a list is deleted locally).
  Future<bool> deleteContainer(String containerId) async {
    final folderId = await bootstrapFolder();
    final api = await _api();
    if (folderId == null || api == null) return false;
    try {
      final f =
          await _findByShutterId(api, 'container_$containerId', folderId);
      if (f == null) return true; // already gone
      await api.files.delete(f.id!);
      return true;
    } catch (e) {
      debugPrint('DriveSyncService.deleteContainer($containerId) failed: $e');
      return false;
    }
  }

  // --- internals -----------------------------------------------------------

  Future<bool> _writeJson(
      String shutterId, String displayName, Map<String, dynamic> body) async {
    final folderId = await bootstrapFolder();
    final api = await _api();
    if (folderId == null || api == null) return false;
    try {
      final encoded = utf8.encode(jsonEncode(body));
      final media = drive.Media(
        Stream<List<int>>.fromIterable([encoded]),
        encoded.length,
        contentType: 'application/json',
      );

      final existing = await _findByShutterId(api, shutterId, folderId);
      if (existing == null) {
        await api.files.create(
          drive.File()
            ..name = displayName
            ..parents = [folderId]
            ..appProperties = {_shutterIdKey: shutterId},
          uploadMedia: media,
        );
      } else {
        // Names can drift if user renames the file in Drive UI — we don't
        // overwrite the name on update, only the body.
        await api.files.update(drive.File(), existing.id!, uploadMedia: media);
      }
      return true;
    } catch (e) {
      debugPrint('DriveSyncService._writeJson($shutterId) failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> _downloadJson(
      drive.DriveApi api, String fileId) async {
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    final text = utf8.decode(bytes);
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Drops the cached folder ID so the next call to bootstrapFolder re-resolves.
  /// Used on sign-out to avoid mixing folder IDs across accounts.
  void resetCache() {
    _folderId = null;
  }
}
