import 'package:uuid/uuid.dart';
import 'custom_theme.dart';

// Sentinel so copyWith can distinguish "not passed" from "passed null".
class _Unset {
  const _Unset();
}
const _unset = _Unset();

/// Where a list's task data lives.
///
/// `local` — SharedPreferences only. No cloud component.
/// `drive` — Drive-backed JSON in the user's own Drive (Phase 2 + 2.1 sync).
/// `firestore` — owner-shared list in Firestore. Realtime, multi-collaborator.
///
/// Local and drive are interchangeable for write semantics; the difference is
/// whether the orchestrator pushes/pulls. Firestore is the only branch that
/// fundamentally changes how the screen reads + writes data.
enum ListStorage {
  local,
  drive,
  firestore;

  static ListStorage fromName(String? name) {
    if (name == null) return ListStorage.local;
    for (final v in ListStorage.values) {
      if (v.name == name) return v;
    }
    return ListStorage.local;
  }
}

// Represents a named list of tasks. Lists can nest via parentId (null = top-level).
class TaskList {
  final String id;
  String name;
  final int createdAtTimestamp;
  String? parentId;
  int? color;            // ARGB int; null = use theme accent at render time.
  String? iconEmoji;     // Mutually exclusive with iconCodePoint.
  String? iconCodePoint; // Material icon codepoint stored as string.
  int sortOrder;         // Ordering within the same parent.
  CustomTheme? themeOverride; // null = inherit global theme.
  // Last-write-wins timestamp consumed by the sync layer. Every copyWith
  // advances it. Backfilled from createdAtTimestamp by migration v3.
  final int updatedAt;
  // Where this list's data is stored. Defaults to local; flips to firestore
  // when the list is shared. See [ListStorage].
  final ListStorage storage;
  // Firebase UID of the list's owner — only meaningful when storage is
  // firestore. Null otherwise.
  final String? ownerUid;
  // Firebase UIDs of collaborators (excluding owner). Only meaningful for
  // firestore-backed lists. Mutated by sharing/kick flows in Phase 4.
  final List<String> collaboratorUids;

  TaskList({
    required this.id,
    required this.name,
    required this.createdAtTimestamp,
    this.parentId,
    this.color,
    this.iconEmoji,
    this.iconCodePoint,
    this.sortOrder = 0,
    this.themeOverride,
    int? updatedAt,
    this.storage = ListStorage.local,
    this.ownerUid,
    List<String>? collaboratorUids,
  })  : updatedAt = updatedAt ?? createdAtTimestamp,
        collaboratorUids =
            List.unmodifiable(collaboratorUids ?? const <String>[]);

  factory TaskList.createNew({
    required String name,
    String? parentId,
    int? color,
    String? iconEmoji,
    String? iconCodePoint,
    int sortOrder = 0,
    CustomTheme? themeOverride,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return TaskList(
      id: const Uuid().v4(),
      name: name,
      createdAtTimestamp: now,
      parentId: parentId,
      color: color,
      iconEmoji: iconEmoji,
      iconCodePoint: iconCodePoint,
      sortOrder: sortOrder,
      themeOverride: themeOverride,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAtTimestamp': createdAtTimestamp,
        'parentId': parentId,
        'color': color,
        'iconEmoji': iconEmoji,
        'iconCodePoint': iconCodePoint,
        'sortOrder': sortOrder,
        'themeOverride': themeOverride?.toJson(),
        'updatedAt': updatedAt,
        'storage': storage.name,
        'ownerUid': ownerUid,
        'collaboratorUids': collaboratorUids,
      };

  factory TaskList.fromJson(Map<String, dynamic> json) {
    final themeJson = json['themeOverride'];
    CustomTheme? override;
    if (themeJson is Map) {
      override = CustomTheme.fromJson(Map<String, dynamic>.from(themeJson));
    }
    final created = json['createdAtTimestamp'] as int;
    final collabRaw = json['collaboratorUids'];
    final collab = collabRaw is List
        ? collabRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return TaskList(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAtTimestamp: created,
      parentId: json['parentId'] as String?,
      color: json['color'] as int?,
      iconEmoji: json['iconEmoji'] as String?,
      iconCodePoint: json['iconCodePoint'] as String?,
      sortOrder: (json['sortOrder'] as int?) ?? 0,
      themeOverride: override,
      updatedAt: (json['updatedAt'] as int?) ?? created,
      storage: ListStorage.fromName(json['storage'] as String?),
      ownerUid: json['ownerUid'] as String?,
      collaboratorUids: collab,
    );
  }

  TaskList copyWith({
    String? name,
    Object? parentId = _unset,
    Object? color = _unset,
    Object? iconEmoji = _unset,
    Object? iconCodePoint = _unset,
    int? sortOrder,
    Object? themeOverride = _unset,
    int? updatedAt,
    ListStorage? storage,
    Object? ownerUid = _unset,
    List<String>? collaboratorUids,
  }) {
    return TaskList(
      id: id,
      name: name ?? this.name,
      createdAtTimestamp: createdAtTimestamp,
      parentId: identical(parentId, _unset) ? this.parentId : parentId as String?,
      color: identical(color, _unset) ? this.color : color as int?,
      iconEmoji: identical(iconEmoji, _unset) ? this.iconEmoji : iconEmoji as String?,
      iconCodePoint: identical(iconCodePoint, _unset)
          ? this.iconCodePoint
          : iconCodePoint as String?,
      sortOrder: sortOrder ?? this.sortOrder,
      themeOverride: identical(themeOverride, _unset)
          ? this.themeOverride
          : themeOverride as CustomTheme?,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      storage: storage ?? this.storage,
      ownerUid:
          identical(ownerUid, _unset) ? this.ownerUid : ownerUid as String?,
      collaboratorUids: collaboratorUids ?? this.collaboratorUids,
    );
  }
}
