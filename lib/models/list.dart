import 'package:uuid/uuid.dart';
import 'custom_theme.dart';

// Sentinel so copyWith can distinguish "not passed" from "passed null".
class _Unset {
  const _Unset();
}
const _unset = _Unset();

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
  }) : updatedAt = updatedAt ?? createdAtTimestamp;

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
      };

  factory TaskList.fromJson(Map<String, dynamic> json) {
    final themeJson = json['themeOverride'];
    CustomTheme? override;
    if (themeJson is Map) {
      override = CustomTheme.fromJson(Map<String, dynamic>.from(themeJson));
    }
    final created = json['createdAtTimestamp'] as int;
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
    );
  }
}
