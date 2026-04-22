import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/archived_task.dart';
import '../models/custom_theme.dart';
import '../models/list.dart';
import '../models/task.dart';
import '../utils/haptics.dart';

enum ArchiveClearDuration { oneDay, threeDays, oneWeek, never }

class SettingsNotifier extends ChangeNotifier {
  final SharedPreferences _prefs;
  List<CustomTheme> _themes = [];
  late CustomTheme _currentTheme;
  late ThemeMode _themeMode;
  late ArchiveClearDuration _archiveClearDuration;
  late double _taskHeight;
  late int _animationSpeed;
  late double _textScale;
  late bool _hapticsEnabled;
  late int _defaultReminderHour;
  late int _defaultReminderMinute;
  List<Color> _savedColors = [];
  
  // NEW: List management. Internal list is kept insertion-ordered; the public
  // getter sorts by sortOrder so the UI always renders in drag-reorder order.
  List<TaskList> _taskLists = [];
  TaskList? _currentList; // Optional: May be used for tracking the last viewed list

  // Root-container state — tasks/archive that live outside any list.
  // Persisted under the same key scheme used by lists: todos_root / archivedTodos_root.
  final List<Task> _rootTasks = [];
  final List<ArchivedTask> _rootArchive = [];

  // Home-screen section state (collapsible Tasks + Lists groups).
  bool _tasksGroupExpanded = true;
  bool _listsGroupExpanded = true;
  bool _tasksGroupFirst = true;

  SettingsNotifier(this._prefs) {
    _runMigrations();
    _loadSettings();
  }

  // One-shot, idempotent migration gated by `migrationVersion`. Runs synchronously
  // using SharedPreferences' cached reads; writes are fire-and-forget (same
  // pattern as the rest of this class). On any failure the version gate is left
  // unset so migration retries on next launch.
  void _runMigrations() {
    final version = _prefs.getInt('migrationVersion') ?? 0;
    if (version >= 2) return;

    try {
      _runV1Migration(version);
      _runV2Migration(version);
      _prefs.setInt('migrationVersion', 2);
    } catch (e) {
      debugPrint('SettingsNotifier migration failed: $e');
    }
  }

  // Additive: seed new preference keys introduced in v2 if absent. No schema
  // transforms — every new model field has a safe default on decode.
  void _runV2Migration(int fromVersion) {
    if (fromVersion >= 2) return;
    if (!_prefs.containsKey('textScale')) {
      _prefs.setDouble('textScale', 1.0);
    }
    if (!_prefs.containsKey('hapticsEnabled')) {
      _prefs.setBool('hapticsEnabled', true);
    }
    if (!_prefs.containsKey('defaultReminderHour')) {
      _prefs.setInt('defaultReminderHour', 9);
    }
    if (!_prefs.containsKey('defaultReminderMinute')) {
      _prefs.setInt('defaultReminderMinute', 0);
    }
  }

  void _runV1Migration(int fromVersion) {
    if (fromVersion >= 1) return;
    // 1. Promote legacy flat keys (pre-lists era) to the root container.
    final legacyTodos = _prefs.getStringList('todos');
    if (legacyTodos != null && !_prefs.containsKey('todos_root')) {
      _prefs.setStringList('todos_root', legacyTodos);
      _prefs.remove('todos');
    }
    final legacyArchive = _prefs.getStringList('archivedTodos');
    if (legacyArchive != null && !_prefs.containsKey('archivedTodos_root')) {
      _prefs.setStringList('archivedTodos_root', legacyArchive);
      _prefs.remove('archivedTodos');
    }

    // 2. Backfill TaskList records: assign sortOrder by load order if missing.
    //    Other new fields (parentId, color, icon*) decode to null and need
    //    no explicit backfill. Also build lookup maps used in step 3.
    final Map<String, String> nameByListId = {};
    final Map<String, int?> colorByListId = {};
    final listsJson = _prefs.getString('taskLists');
    if (listsJson != null) {
      final decoded = jsonDecode(listsJson) as List;
      bool changed = false;
      for (int i = 0; i < decoded.length; i++) {
        final map = Map<String, dynamic>.from(decoded[i] as Map);
        if (!map.containsKey('sortOrder')) {
          map['sortOrder'] = i;
          changed = true;
        }
        decoded[i] = map;
        nameByListId[map['id'] as String] = map['name'] as String;
        colorByListId[map['id'] as String] = map['color'] as int?;
      }
      if (changed) {
        _prefs.setString('taskLists', jsonEncode(decoded));
      }
    }

    // 3. Backfill archive entries with id + origin snapshots.
    const uuid = Uuid();
    for (final key in _prefs.getKeys().toList()) {
      if (!key.startsWith('archivedTodos_')) continue;
      final originId = key.substring('archivedTodos_'.length);
      final raw = _prefs.getStringList(key);
      if (raw == null) continue;

      bool changed = false;
      final rebuilt = <String>[];
      for (final entryJson in raw) {
        Map<String, dynamic> map;
        try {
          map = Map<String, dynamic>.from(jsonDecode(entryJson) as Map);
        } catch (_) {
          rebuilt.add(entryJson);
          continue;
        }
        if (!map.containsKey('id')) {
          map['id'] = uuid.v4();
          changed = true;
        }
        if (!map.containsKey('originId')) {
          map['originId'] = originId;
          changed = true;
        }
        if (!map.containsKey('originNameSnapshot')) {
          map['originNameSnapshot'] = nameByListId[originId] ??
              (originId == 'root' ? 'Root' : 'Unknown');
          changed = true;
        }
        if (!map.containsKey('originColorSnapshot')) {
          map['originColorSnapshot'] = colorByListId[originId];
          changed = true;
        }
        rebuilt.add(jsonEncode(map));
      }
      if (changed) {
        _prefs.setStringList(key, rebuilt);
      }
    }
  }

  List<CustomTheme> get themes => _themes;
  CustomTheme get currentTheme => _currentTheme;
  ThemeMode get themeMode => _themeMode;
  ArchiveClearDuration get archiveClearDuration => _archiveClearDuration;
  double get taskHeight => _taskHeight;
  int get animationSpeed => _animationSpeed;
  double get textScale => _textScale;
  bool get hapticsEnabled => _hapticsEnabled;
  int get defaultReminderHour => _defaultReminderHour;
  int get defaultReminderMinute => _defaultReminderMinute;
  TimeOfDay get defaultReminderTime =>
      TimeOfDay(hour: _defaultReminderHour, minute: _defaultReminderMinute);
  List<Color> get savedColors => _savedColors;
  // NEW: Getters for lists
  List<TaskList> get taskLists {
    final sorted = [..._taskLists];
    sorted.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      return a.createdAtTimestamp.compareTo(b.createdAtTimestamp);
    });
    return List.unmodifiable(sorted);
  }
  TaskList? get currentList => _currentList;
  // Root-container getters (unmodifiable to prevent external mutation).
  List<Task> get rootTasks => List.unmodifiable(_rootTasks);
  List<ArchivedTask> get rootArchive => List.unmodifiable(_rootArchive);
  bool get tasksGroupExpanded => _tasksGroupExpanded;
  bool get listsGroupExpanded => _listsGroupExpanded;
  bool get tasksGroupFirst => _tasksGroupFirst;

  void _loadSettings() {
    _themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];
    _archiveClearDuration = ArchiveClearDuration.values[_prefs.getInt('archiveClearDuration') ?? ArchiveClearDuration.oneWeek.index];
    _taskHeight = _prefs.getDouble('taskHeight') ?? 1.0;
    _animationSpeed = _prefs.getInt('animationSpeed') ?? 450;
    _textScale = _prefs.getDouble('textScale') ?? 1.0;
    _hapticsEnabled = _prefs.getBool('hapticsEnabled') ?? true;
    _defaultReminderHour = _prefs.getInt('defaultReminderHour') ?? 9;
    _defaultReminderMinute = _prefs.getInt('defaultReminderMinute') ?? 0;
    Haptics.enabled = _hapticsEnabled;

    final colorsJson = _prefs.getStringList('savedColors') ?? [];
    _savedColors = colorsJson.map((hex) => Color(int.parse(hex))).toList();
    _loadThemes();
    _loadTaskLists();
    _loadRootTasks();
    _loadRootArchive();
    _loadSectionState();
  }

  void _loadThemes() {
    final List<CustomTheme> defaultThemes = _createDefaultThemes();
    final themesJson = _prefs.getString('customThemes');
    
    List<CustomTheme> savedThemes = [];
    if (themesJson != null) {
      final decoded = jsonDecode(themesJson) as List;
      savedThemes = decoded.map((themeJson) => CustomTheme.fromJson(themeJson)).toList();
    }

    final Map<String, CustomTheme> themeMap = { for (var theme in defaultThemes) theme.id : theme };
    for (var savedTheme in savedThemes) {
         themeMap[savedTheme.id] = savedTheme;
    }

    _themes = themeMap.values.toList();
    
    final currentThemeId = _prefs.getString('currentThemeId') ?? _themes.first.id;
    _currentTheme = _themes.firstWhere((t) => t.id == currentThemeId, orElse: () {
      final fallbackTheme = _themes.first;
      _prefs.setString('currentThemeId', fallbackTheme.id);
      return fallbackTheme;
    });
  }

  // NEW: List management persistence
  void _loadTaskLists() {
    final listsJson = _prefs.getString('taskLists');
    if (listsJson != null) {
      final decoded = jsonDecode(listsJson) as List;
      _taskLists = decoded.map((listJson) => TaskList.fromJson(listJson)).toList();
    } else {
      _taskLists = [];
    }
  }

  void _loadRootTasks() {
    final data = _prefs.getStringList('todos_root') ?? const [];
    _rootTasks
      ..clear()
      ..addAll(data.map((s) => Task.fromJson(jsonDecode(s) as Map<String, dynamic>)));
  }

  void _loadRootArchive() {
    final data = _prefs.getStringList('archivedTodos_root') ?? const [];
    final loaded = data
        .map((s) => ArchivedTask.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    _pruneArchive(loaded);
    _rootArchive
      ..clear()
      ..addAll(loaded);
  }

  void _pruneArchive(List<ArchivedTask> archive) {
    if (_archiveClearDuration == ArchiveClearDuration.never) return;
    final durationMs = const {
          ArchiveClearDuration.oneDay: Duration(days: 1),
          ArchiveClearDuration.threeDays: Duration(days: 3),
          ArchiveClearDuration.oneWeek: Duration(days: 7),
        }[_archiveClearDuration]!
        .inMilliseconds;
    final threshold = DateTime.now().millisecondsSinceEpoch - durationMs;
    archive.removeWhere((t) => t.archivedAtTimestamp < threshold);
  }

  void _loadSectionState() {
    _tasksGroupExpanded = _prefs.getBool('tasksGroupExpanded') ?? true;
    _listsGroupExpanded = _prefs.getBool('listsGroupExpanded') ?? true;
    _tasksGroupFirst = _prefs.getBool('tasksGroupFirst') ?? true;
  }

  Future<void> _saveRootTasks() async {
    final data = _rootTasks.map((t) => jsonEncode(t.toJson())).toList();
    await _prefs.setStringList('todos_root', data);
    notifyListeners();
  }

  Future<void> _saveRootArchive() async {
    final data = _rootArchive.map((t) => jsonEncode(t.toJson())).toList();
    await _prefs.setStringList('archivedTodos_root', data);
    notifyListeners();
  }

  // --- Root task CRUD -------------------------------------------------------

  void addRootTask(Task task) {
    _rootTasks.insert(0, task);
    _saveRootTasks();
  }

  void updateRootTask(Task task) {
    final i = _rootTasks.indexWhere((t) => t.id == task.id);
    if (i == -1) return;
    _rootTasks[i] = task;
    _saveRootTasks();
  }

  void reorderRootTasks(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _rootTasks.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final t = _rootTasks.removeAt(oldIndex);
    _rootTasks.insert(newIndex.clamp(0, _rootTasks.length), t);
    _saveRootTasks();
  }

  // Inserts an archive entry for the given task without touching the active list.
  // Paired with removeRootTask for completion animation: the caller adds the
  // snapshot on tap, then removes the active task when the animation ends.
  // Dedupes against an identical-text entry archived within the last 5s to
  // guard against racing with the background-isolate "Mark Complete" path.
  void archiveRootSnapshot(Task task) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final already = _rootArchive.any((a) =>
        a.text == task.text && (nowMs - a.archivedAtTimestamp).abs() < 5000);
    if (already) return;
    _rootArchive.insert(
      0,
      ArchivedTask.createNew(
        text: task.text,
        originId: 'root',
        originNameSnapshot: 'Root',
      ),
    );
    _saveRootArchive();
  }

  void removeRootTask(String taskId) {
    final before = _rootTasks.length;
    _rootTasks.removeWhere((t) => t.id == taskId);
    if (_rootTasks.length != before) _saveRootTasks();
  }

  void restoreRootArchivedTask(ArchivedTask entry) {
    final removed = _rootArchive.remove(entry);
    if (!removed) return;
    _rootTasks.add(Task.createNew(text: entry.text));
    _saveRootTasks();
    _saveRootArchive();
  }

  void clearRootArchive() {
    if (_rootArchive.isEmpty) return;
    _rootArchive.clear();
    _saveRootArchive();
  }

  // Reloads root state from SharedPreferences. Used when the background isolate
  // has written to todos_root / archivedTodos_root (Mark Complete from a killed
  // app) and the foreground needs to pick up those changes.
  Future<void> reloadRootFromDisk() async {
    await _prefs.reload();
    _loadRootTasks();
    _loadRootArchive();
    notifyListeners();
  }

  // --- Section toggles ------------------------------------------------------

  void setTasksGroupExpanded(bool v) {
    if (_tasksGroupExpanded == v) return;
    _tasksGroupExpanded = v;
    _prefs.setBool('tasksGroupExpanded', v);
    notifyListeners();
  }

  void setListsGroupExpanded(bool v) {
    if (_listsGroupExpanded == v) return;
    _listsGroupExpanded = v;
    _prefs.setBool('listsGroupExpanded', v);
    notifyListeners();
  }

  void setTasksGroupFirst(bool v) {
    if (_tasksGroupFirst == v) return;
    _tasksGroupFirst = v;
    _prefs.setBool('tasksGroupFirst', v);
    notifyListeners();
  }

  Future<void> _saveTaskLists() async {
    final listsJson = jsonEncode(_taskLists.map((list) => list.toJson()).toList());
    await _prefs.setString('taskLists', listsJson);
    notifyListeners();
  }

  void addTaskList(TaskList list) {
    // Assign sortOrder at the tail so new lists appear after existing ones.
    final maxOrder = _taskLists.isEmpty
        ? -1
        : _taskLists
            .map((l) => l.sortOrder)
            .reduce((a, b) => a > b ? a : b);
    final positioned = list.copyWith(sortOrder: maxOrder + 1);
    _taskLists.add(positioned);
    _saveTaskLists();
  }

  void updateTaskList(TaskList list) {
    final index = _taskLists.indexWhere((t) => t.id == list.id);
    if (index != -1) {
      _taskLists[index] = list;
      _saveTaskLists();
    }
  }

  /// Reorders lists within a single parent scope. `parentId` = null targets
  /// top-level lists; a list UUID targets that list's direct children.
  /// Rewrites each sibling's sortOrder so gaps and duplicates from earlier
  /// bugs/migrations heal on every reorder.
  void reorderListsWithin(String? parentId, int oldIndex, int newIndex) {
    final siblings = childrenOf(parentId);
    if (oldIndex < 0 || oldIndex >= siblings.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, siblings.length - 1);
    final moved = siblings.removeAt(oldIndex);
    siblings.insert(newIndex, moved);
    for (int i = 0; i < siblings.length; i++) {
      final idx = _taskLists.indexWhere((l) => l.id == siblings[i].id);
      if (idx != -1) _taskLists[idx] = _taskLists[idx].copyWith(sortOrder: i);
    }
    _saveTaskLists();
  }

  Future<void> deleteTaskList(String listId) async {
    // Root tasks cover the "has somewhere to put things" case, so lists are
    // optional — no last-list guard needed. NOTE: this only removes the list's
    // active tasks; `archivedTodos_$listId` is left in place so the (future)
    // global archive can surface provenance for deleted lists.
    _taskLists.removeWhere((t) => t.id == listId);
    await _saveTaskLists();
    await _prefs.remove('todos_$listId');
  }

  // --- Nested lists --------------------------------------------------------

  /// Direct children of `parentId`. Pass `null` for top-level lists.
  List<TaskList> childrenOf(String? parentId) {
    final matches =
        _taskLists.where((l) => l.parentId == parentId).toList();
    matches.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      return a.createdAtTimestamp.compareTo(b.createdAtTimestamp);
    });
    return matches;
  }

  /// All descendants of `listId` — iterative BFS, cycle-safe via visited set.
  /// Returns the TaskList records (not ids) so callers can act on them
  /// directly. Excludes `listId` itself.
  List<TaskList> descendantsOf(String listId) {
    final result = <TaskList>[];
    final visited = <String>{listId};
    final queue = <String>[listId];
    final byParent = <String?, List<TaskList>>{};
    for (final l in _taskLists) {
      byParent.putIfAbsent(l.parentId, () => []).add(l);
    }
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final kids = byParent[current] ?? const <TaskList>[];
      for (final k in kids) {
        if (visited.add(k.id)) {
          result.add(k);
          queue.add(k.id);
        }
      }
    }
    return result;
  }

  /// Counts active (non-archived) tasks for a list. When `deep` is true,
  /// rolls up all descendants as well. Uses cached prefs reads — no disk I/O.
  int activeTaskCountFor(String listId, {bool deep = true}) {
    int count(String id) => (_prefs.getStringList('todos_$id') ?? const []).length;
    if (!deep) return count(listId);
    var total = count(listId);
    for (final d in descendantsOf(listId)) {
      total += count(d.id);
    }
    return total;
  }

  /// Moves `listId` under `newParentId` (null = top-level). Rejects moves that
  /// would create a cycle (into own subtree) or orphan the list. Resets the
  /// list's sortOrder to the tail of the new parent to avoid collisions.
  void reparentList(String listId, String? newParentId) {
    if (listId == newParentId) return;
    final idx = _taskLists.indexWhere((l) => l.id == listId);
    if (idx == -1) return;

    if (newParentId != null) {
      final targetExists = _taskLists.any((l) => l.id == newParentId);
      if (!targetExists) return;
      // Reject reparent into own subtree — would create a cycle.
      final banned = descendantsOf(listId).map((l) => l.id).toSet();
      if (banned.contains(newParentId)) return;
    }

    // Tail sortOrder among the new parent's existing children.
    final siblings = childrenOf(newParentId);
    final tail = siblings.isEmpty
        ? 0
        : siblings.map((l) => l.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    _taskLists[idx] = _taskLists[idx]
        .copyWith(parentId: newParentId, sortOrder: tail);
    _saveTaskLists();
  }

  /// Moves `task` from one container to another. `fromContainerId` /
  /// `toContainerId` are either 'root' or a list UUID. Writes the target
  /// first so a failure on the source write leaves both endpoints with the
  /// task (a dupe is preferable to a loss) and then rolls back the target.
  /// Reloads in-memory root state if either endpoint is 'root'.
  Future<void> moveTask(
    Task task, {
    required String fromContainerId,
    required String toContainerId,
  }) async {
    if (fromContainerId == toContainerId) return;

    String keyFor(String id) => id == 'root' ? 'todos_root' : 'todos_$id';
    final fromKey = keyFor(fromContainerId);
    final toKey = keyFor(toContainerId);

    final fromRaw = _prefs.getStringList(fromKey) ?? const <String>[];
    final toRaw = _prefs.getStringList(toKey) ?? const <String>[];

    final filteredFrom = fromRaw.where((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return m['id'] != task.id;
      } catch (_) {
        return true;
      }
    }).toList();
    if (filteredFrom.length == fromRaw.length) {
      // Task not found in source — nothing to move.
      return;
    }

    final encoded = jsonEncode(task.toJson());
    final newTo = [encoded, ...toRaw];

    await _prefs.setStringList(toKey, newTo);
    try {
      await _prefs.setStringList(fromKey, filteredFrom);
    } catch (e) {
      // Roll back the target so we don't end up with both a stale source AND
      // a duplicate at the destination.
      await _prefs.setStringList(toKey, toRaw);
      debugPrint('moveTask source write failed, rolled back target: $e');
      rethrow;
    }

    if (fromContainerId == 'root' || toContainerId == 'root') {
      _loadRootTasks();
    }
    notifyListeners();
  }

  /// Returns true if a list with the given id still exists (non-deleted).
  bool listExists(String listId) => _taskLists.any((l) => l.id == listId);

  TaskList? taskListById(String id) {
    final idx = _taskLists.indexWhere((l) => l.id == id);
    return idx == -1 ? null : _taskLists[idx];
  }

  /// Aggregates every `archivedTodos_*` key into a single list, sorted by
  /// `archivedAtTimestamp` desc. Entries whose origin list has been deleted
  /// are retained — the UI distinguishes them via [listExists].
  List<ArchivedTask> globalArchive() {
    final all = <ArchivedTask>[];
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith('archivedTodos_')) continue;
      final raw = _prefs.getStringList(key) ?? const <String>[];
      for (final s in raw) {
        try {
          all.add(ArchivedTask.fromJson(jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {
          // Tolerate a single bad row — skip it rather than blowing the view.
        }
      }
    }
    all.sort((a, b) => b.archivedAtTimestamp.compareTo(a.archivedAtTimestamp));
    return all;
  }

  /// Restores [entry] to a container. If [overrideTargetId] is provided the
  /// task is inserted there (used for "Restore to Root" when the origin list
  /// was deleted); otherwise it returns to its origin. The archive row is
  /// removed from whichever `archivedTodos_*` key held it.
  Future<void> restoreGlobalArchiveEntry(
    ArchivedTask entry, {
    String? overrideTargetId,
  }) async {
    final sourceKey = 'archivedTodos_${entry.originId}';
    final targetContainerId = overrideTargetId ?? entry.originId;

    // Strip the archive row.
    final raw = _prefs.getStringList(sourceKey) ?? const <String>[];
    final filtered = raw.where((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return m['id'] != entry.id;
      } catch (_) {
        return true;
      }
    }).toList();
    if (filtered.length != raw.length) {
      await _prefs.setStringList(sourceKey, filtered);
    }

    // Insert a fresh active task at the target container.
    final targetKey = targetContainerId == 'root'
        ? 'todos_root'
        : 'todos_$targetContainerId';
    final targetRaw = _prefs.getStringList(targetKey) ?? const <String>[];
    final restored = Task.createNew(text: entry.text);
    final newTarget = [jsonEncode(restored.toJson()), ...targetRaw];
    await _prefs.setStringList(targetKey, newTarget);

    if (entry.originId == 'root' || targetContainerId == 'root') {
      _loadRootTasks();
      _loadRootArchive();
    }
    notifyListeners();
  }

  /// Wipes every `archivedTodos_*` key. Mirrors the behavior of per-container
  /// clear but spans all origins (including deleted-list leftovers).
  Future<void> clearGlobalArchive() async {
    final keys =
        _prefs.getKeys().where((k) => k.startsWith('archivedTodos_')).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
    _rootArchive.clear();
    notifyListeners();
  }

  /// Deletes `listId` AND every descendant list, wiping each one's active
  /// tasks. `archivedTodos_$id` keys are intentionally preserved so completed
  /// items survive in the (future) global archive view as "Deleted: {name}".
  Future<void> cascadeDeleteList(String listId) async {
    final ids = <String>[listId, ...descendantsOf(listId).map((l) => l.id)];
    _taskLists.removeWhere((l) => ids.contains(l.id));
    await _saveTaskLists();
    for (final id in ids) {
      await _prefs.remove('todos_$id');
    }
  }
  
  List<CustomTheme> _createDefaultThemes() {
    return [
      CustomTheme(
        id: 'default',
        name: 'Default',
        primaryColor: Colors.blueGrey,
        secondaryColor: Colors.amber.shade700,
        taskBackgroundColor: Colors.blueGrey.shade600,
        inputAreaColor: Colors.blueGrey.shade700,
        taskTextColor: Colors.black87,
        strikethroughColor: Colors.black54,
        isDeletable: false, // Default theme should not be deletable
      ),
    ];
  }

  CustomTheme createNewThemeTemplate() {
    return _createDefaultThemes().first.copy()
      ..name = 'New Theme'
      ..isDeletable = true;
  }

  Future<void> _saveThemes() async {
    final themesToSave = _themes.where((t) => t.isDeletable || t.id != 'default').toList();
    final themesJson = jsonEncode(themesToSave.map((theme) => theme.toJson()).toList());
    await _prefs.setString('customThemes', themesJson);
    notifyListeners();
  }

  void setCurrentTheme(String themeId) {
    _currentTheme = _themes.firstWhere((t) => t.id == themeId);
    _prefs.setString('currentThemeId', themeId);
    notifyListeners();
  }

  void addTheme(CustomTheme theme) {
    _themes.add(theme);
    _saveThemes();
  }

  void updateTheme(CustomTheme theme) {
    final index = _themes.indexWhere((t) => t.id == theme.id);
    if (index != -1) {
      _themes[index] = theme;
      if (_currentTheme.id == theme.id) {
        _currentTheme = theme;
      }
      _saveThemes();
    }
  }

  void deleteTheme(String themeId) {
    final themeToDelete = _themes.firstWhere((t) => t.id == themeId);
    if (_themes.length <= 1 || !themeToDelete.isDeletable) return;
    
    _themes.removeWhere((t) => t.id == themeId);
    if (_currentTheme.id == themeId) {
      setCurrentTheme(_themes.first.id);
    }
    _saveThemes();
  }
  
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }
  
  void setArchiveClearDuration(ArchiveClearDuration duration) {
    _archiveClearDuration = duration;
    _prefs.setInt('archiveClearDuration', duration.index);
    notifyListeners();
  }
  
  void setTaskHeight(double height) {
    _taskHeight = height;
    _prefs.setDouble('taskHeight', height);
    notifyListeners();
  }

  void setAnimationSpeed(double speed) {
    _animationSpeed = speed.toInt();
    _prefs.setInt('animationSpeed', _animationSpeed);
    notifyListeners();
  }

  void setTextScale(double scale) {
    final clamped = scale.clamp(0.75, 1.40);
    if ((clamped - _textScale).abs() < 0.001) return;
    _textScale = clamped;
    _prefs.setDouble('textScale', clamped);
    notifyListeners();
  }

  void setHapticsEnabled(bool enabled) {
    if (_hapticsEnabled == enabled) return;
    _hapticsEnabled = enabled;
    Haptics.enabled = enabled;
    _prefs.setBool('hapticsEnabled', enabled);
    notifyListeners();
  }

  void setDefaultReminderTime(TimeOfDay time) {
    if (_defaultReminderHour == time.hour && _defaultReminderMinute == time.minute) return;
    _defaultReminderHour = time.hour;
    _defaultReminderMinute = time.minute;
    _prefs.setInt('defaultReminderHour', time.hour);
    _prefs.setInt('defaultReminderMinute', time.minute);
    notifyListeners();
  }

  /// Resolves the effective theme for a given list. A list's themeOverride,
  /// if set, fully replaces the global theme within that list's scope. Pass
  /// null (root / settings / home) to always get the global theme.
  CustomTheme effectiveThemeFor(TaskList? list) =>
      list?.themeOverride ?? _currentTheme;

  /// Writes a full theme override onto a list. Pass null to clear back to the
  /// global theme.
  void updateListTheme(String listId, CustomTheme? override) {
    final idx = _taskLists.indexWhere((l) => l.id == listId);
    if (idx == -1) return;
    _taskLists[idx] = _taskLists[idx].copyWith(themeOverride: override);
    _saveTaskLists();
  }
  
  void addSavedColor(Color color) {
    if (!_savedColors.contains(color) && _savedColors.length < 10) {
      _savedColors.add(color);
      _saveColors();
      notifyListeners();
    }
  }

  void removeSavedColor(Color color) {
    _savedColors.remove(color);
    _saveColors();
    notifyListeners();
  }

  void updateSavedColorsOrder(List<Color> newOrder) {
    _savedColors = newOrder;
    _saveColors();
    notifyListeners();
  }

  Future<void> _saveColors() async {
    final colorHexes = _savedColors.map((c) => c.toARGB32().toString()).toList();
    await _prefs.setStringList('savedColors', colorHexes);
  }

  // --- Data export / import / wipe -----------------------------------------

  // Singleton keys this app owns. Per-list todos_{id} / archivedTodos_{id} keys
  // are walked dynamically in export/wipe.
  static const List<String> _scalarKeys = <String>[
    'themeMode',
    'archiveClearDuration',
    'taskHeight',
    'animationSpeed',
    'textScale',
    'hapticsEnabled',
    'defaultReminderHour',
    'defaultReminderMinute',
    'currentThemeId',
    'customThemes',
    'taskLists',
    'savedColors',
    'tasksGroupExpanded',
    'listsGroupExpanded',
    'tasksGroupFirst',
    'migrationVersion',
  ];

  /// Dumps every app-owned SharedPreferences key to a portable JSON string.
  /// Typed under `prefs` as `{key: value}` with native types (string, int,
  /// double, bool, List<String>). The reader re-applies them with the matching
  /// setter.
  String exportAllDataJson() {
    final prefs = <String, Object?>{};
    for (final key in _scalarKeys) {
      if (!_prefs.containsKey(key)) continue;
      prefs[key] = _prefs.get(key);
    }
    for (final key in _prefs.getKeys()) {
      if (key.startsWith('todos_') || key.startsWith('archivedTodos_')) {
        prefs[key] = _prefs.getStringList(key);
      }
    }
    final blob = <String, Object?>{
      'schema': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'prefs': prefs,
    };
    return const JsonEncoder.withIndent('  ').convert(blob);
  }

  /// Validates and replaces all app data from a previously exported JSON
  /// string. Returns true on success, false on validation failure (caller
  /// should surface a message). On success, reloads in-memory state.
  Future<bool> importAllDataJson(String raw) async {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      return false;
    }
    if (parsed is! Map) return false;
    final schema = parsed['schema'];
    if (schema != 2) return false;
    final prefsBlob = parsed['prefs'];
    if (prefsBlob is! Map) return false;

    await _wipeKnownKeys();

    for (final entry in prefsBlob.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value == null) continue;
      if (value is bool) {
        await _prefs.setBool(key, value);
      } else if (value is int) {
        await _prefs.setInt(key, value);
      } else if (value is double) {
        await _prefs.setDouble(key, value);
      } else if (value is String) {
        await _prefs.setString(key, value);
      } else if (value is List) {
        await _prefs.setStringList(
            key, value.map((e) => e.toString()).toList());
      }
    }

    _loadSettings();
    notifyListeners();
    return true;
  }

  /// Clears every app-owned SharedPreferences key and reseeds defaults. The
  /// default theme is regenerated, task lists and root containers start empty,
  /// and new-install defaults are applied to scalar settings.
  Future<void> wipeAllData() async {
    await _wipeKnownKeys();
    _loadSettings();
    notifyListeners();
  }

  Future<void> _wipeKnownKeys() async {
    for (final key in _scalarKeys) {
      await _prefs.remove(key);
    }
    final dynamicKeys = _prefs
        .getKeys()
        .where((k) => k.startsWith('todos_') || k.startsWith('archivedTodos_'))
        .toList();
    for (final key in dynamicKeys) {
      await _prefs.remove(key);
    }
  }
}