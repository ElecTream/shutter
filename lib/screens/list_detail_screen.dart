import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/haptics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

import '../models/archived_task.dart';
import '../models/custom_theme.dart';
import '../models/repeat_interval.dart';
import '../models/task.dart';
import '../models/list.dart';
import '../providers/settings_notifier.dart';
import '../services/notification_service.dart';
import '../utils/app_themes.dart';
import '../widgets/advanced_color_picker.dart';
import '../widgets/icon_picker_sheet.dart';
import '../widgets/move_to_sheet.dart';
import '../widgets/preset_picker_sheet.dart';
import '../widgets/repeat_picker_sheet.dart';
import '../widgets/task_list_editor.dart';
import 'archive_screen.dart';
import 'theme_editor_screen.dart';

// Wraps a nullable parentId so the reparent dialog can distinguish "user
// picked 'Top level'" (parentId = null) from "user dismissed" (result = null).
class _ReparentChoice {
  final String? parentId;
  const _ReparentChoice(this.parentId);
}

class ListDetailScreen extends StatefulWidget {
  final TaskList list;
  const ListDetailScreen({super.key, required this.list});
  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen>
    with WidgetsBindingObserver {
  final List<Task> _todos = [];
  final List<ArchivedTask> _archivedTodos = [];
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Set<String> _completingTaskIds = <String>{};

  // --- EDIT MODE STATE ---
  bool _isEditMode = false;
  Task? _taskBeingEdited;
  final TextEditingController _editTextController = TextEditingController();

  final NotificationService _notificationService = NotificationService();
  // FIX: Change stream subscription type to Map<String, String>
  StreamSubscription<Map<String, String>>? _completionSubscription;
  
  // Persistence keys based on List ID
  late String _todosKey;
  late String _archivedTodosKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _todosKey = 'todos_${widget.list.id}';
    _archivedTodosKey = 'archivedTodos_${widget.list.id}';
    _loadData();
    _initializeNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Covers the killed-app case: background handler wrote to SharedPreferences,
      // reload pulls the updated state now that we're back in foreground.
      _loadData();
    }
  }
  
  @override
  void didUpdateWidget(covariant ListDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Important: Update persistence keys if the list ID changes (though it shouldn't for this screen)
    if (widget.list.id != oldWidget.list.id) {
      _todosKey = 'todos_${widget.list.id}';
      _archivedTodosKey = 'archivedTodos_${widget.list.id}';
      _loadData();
    }
    // Listen for name changes to update the screen title immediately
    if (widget.list.name != oldWidget.list.name) {
      setState(() {});
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.init();
      // FIX: Update listener to expect and handle Map<String, String>
      _completionSubscription =
          _notificationService.taskCompletedStream.listen((data) {
        // Recurring completions advanced the reminder in the bg isolate;
        // the fg just needs to pick up the updated task row from disk —
        // archiving would be wrong.
        if (data['recurring'] == 'true') {
          if (data['listId'] == widget.list.id) _loadData();
          return;
        }
        _completeTaskFromNotification(data['taskId']!, data['listId']!);
      });
    } catch (e) {
      debugPrint('Failed to init notifications: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _focusNode.dispose();
    _editTextController.dispose();
    _completionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();

    // Use list-specific keys
    final todosData = prefs.getStringList(_todosKey) ?? [];
    final archivedData = prefs.getStringList(_archivedTodosKey) ?? [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final List<ArchivedTask> loadedArchived = archivedData
        .map((jsonData) => ArchivedTask.fromJson(json.decode(jsonData)))
        .toList();

    bool archiveWasModified = false;
    final archiveClearDuration = settings.archiveClearDuration;
    if (archiveClearDuration != ArchiveClearDuration.never) {
      final durationMap = {
        ArchiveClearDuration.oneDay: const Duration(days: 1),
        ArchiveClearDuration.threeDays: const Duration(days: 3),
        ArchiveClearDuration.oneWeek: const Duration(days: 7),
      };

      final clearThreshold =
          now - (durationMap[archiveClearDuration]?.inMilliseconds ?? 0);
      final originalCount = loadedArchived.length;
      loadedArchived
          .removeWhere((task) => task.archivedAtTimestamp < clearThreshold);
      archiveWasModified = originalCount != loadedArchived.length;
    }

    setState(() {
      _todos.clear();
      _archivedTodos.clear();
      _todos.addAll(todosData.map(
          (jsonString) => Task.fromJson(json.decode(jsonString))));
      _archivedTodos.addAll(loadedArchived);
    });

    if (archiveWasModified) {
      _saveData();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> todosJson =
        _todos.map((task) => json.encode(task.toJson())).toList();
    await prefs.setStringList(_todosKey, todosJson);
    final List<String> archivedJson = _archivedTodos
        .map((task) => json.encode(task.toJson()))
        .toList();
    await prefs.setStringList(_archivedTodosKey, archivedJson);
  }

  void _addTodo() {
    if (_textController.text.trim().isNotEmpty) {
      Haptics.light();
      setState(() {
        _todos.insert(
            0, Task.createNew(text: _textController.text.trim()));
      });
      _textController.clear();
      _saveData();
      _focusNode.requestFocus();
    }
  }

  void _onAnimationEnd(String taskId) {
    if (mounted) {
      setState(() {
        _todos.removeWhere((task) => task.id == taskId);
        _completingTaskIds.remove(taskId);
      });
      _saveData();
    }
  }

  /// Called when user taps a task tile.
  ///
  /// Recurring tasks (`repeat != null`) advance their reminder by one cadence
  /// and stay active — matches the background "Mark Complete" path so users
  /// see the same behavior whether the notification fired or they tapped
  /// in-app.
  ///
  /// One-shot tasks archive + play strike-through; `_onAnimationEnd` removes
  /// the active row once the animation finishes.
  void _completeTask(Task task) {
    if (_isEditMode) return;

    Haptics.light();

    if (task.repeat != null) {
      final nextFire = DateTime.now().add(task.repeat!.duration);
      _handleTaskReminder(task, nextFire, repeat: task.repeat);
      return;
    }

    if (task.reminderDateTime != null) {
      _notificationService.cancelNotification(
          NotificationService.generateNotificationId(task.id));
    }

    final newArchivedTask = ArchivedTask.createNew(
      text: task.text,
      originId: widget.list.id,
      originNameSnapshot: widget.list.name,
      originColorSnapshot: widget.list.color,
    );

    setState(() {
      _completingTaskIds.add(task.id);
      _archivedTodos.insert(0, newArchivedTask);
    });

    _saveData();
  }

  Future<void> _promptMoveTask(Task task) async {
    if (_isEditMode) return;
    final picked = await showMoveToSheet(
      context,
      excludeContainerId: widget.list.id,
    );
    if (picked == null || !mounted) return;
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    await settings.moveTask(
      task,
      fromContainerId: widget.list.id,
      toContainerId: picked,
    );
    if (mounted) await _loadData();
  }

  void _reorderTasks(int oldIndex, int newIndex) {
    setState(() {
      final item = _todos.removeAt(oldIndex);
      _todos.insert(newIndex, item);
    });
    _saveData();
  }

  // FIX: Updated to handle both taskId and listId, and only complete if the task belongs to this list
	void _completeTaskFromNotification(String taskId, String listId) {
    // Only proceed if the notification is for the currently viewed list
    if (listId != widget.list.id) return;
    
	  final index = _todos.indexWhere((task) => task.id == taskId);
	  if (index != -1 && mounted) {
		final taskToComplete = _todos[index];

		if (_completingTaskIds.contains(taskToComplete.id)) return;

		final newArchivedTask = ArchivedTask.createNew(
		  text: taskToComplete.text,
		  originId: widget.list.id,
		  originNameSnapshot: widget.list.name,
		  originColorSnapshot: widget.list.color,
		);

		setState(() {
		  _completingTaskIds.add(taskToComplete.id);
		  _archivedTodos.insert(0, newArchivedTask);
		});

		if (taskToComplete.reminderDateTime != null) {
		  _notificationService.cancelNotification(
			  NotificationService.generateNotificationId(taskToComplete.id));
		}
	  }
	}

  void _updateTask(Task updatedTask) {
    final index = _todos.indexWhere((task) => task.id == updatedTask.id);
    if (index != -1) {
      setState(() {
        _todos[index] = updatedTask;
      });
      _saveData();
    }
  }

  Future<void> _handleTaskReminder(
    Task task,
    DateTime? newReminderDateTime, {
    RepeatInterval? repeat,
  }) async {
    if (_isEditMode) return;

    final notificationId = NotificationService.generateNotificationId(task.id);

    await _notificationService.cancelNotification(notificationId);

    // Update the stored task BEFORE scheduling so the bg isolate, when
    // Mark Complete fires, reads the correct `repeat` field off prefs.
    final updated = task.copyWith(
      reminderDateTime: newReminderDateTime,
      repeat: newReminderDateTime == null ? null : repeat,
    );
    _updateTask(updated);

    if (newReminderDateTime != null) {
      await _notificationService.scheduleNotification(
        task: updated,
        scheduledTime: newReminderDateTime,
        listId: widget.list.id,
      );
    }
  }

  Future<void> _showDateTimePicker(Task task) async {
    if (_isEditMode) return;

    Haptics.selection();
    await _notificationService.requestPermission();
    if (!mounted) return;

    final now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: task.reminderDateTime ?? now,
      firstDate: now,
      lastDate: DateTime(2101),
    );

    if (pickedDate == null || !mounted) return;

    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    TimeOfDay initialTime;

    if (pickedDate.year == now.year &&
        pickedDate.month == now.month &&
        pickedDate.day == now.day) {
      initialTime = TimeOfDay.fromDateTime(now.add(const Duration(minutes: 1)));
    } else if (task.reminderDateTime != null) {
      initialTime = TimeOfDay.fromDateTime(task.reminderDateTime!);
    } else {
      initialTime = settings.defaultReminderTime;
    }

    if (!mounted) return;
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime == null) return;

    final newReminderDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (newReminderDateTime.isBefore(DateTime.now())) {
      return;
    }

    if (!mounted) return;
    // Offer a Repeats step so one-shot stays the default (Never) but users
    // who want a recurring reminder can pick a cadence in the same flow.
    final repeatResult = await showRepeatPickerSheet(
      context,
      current: task.repeat,
    );
    if (!mounted) return;
    // Dismissal preserves whatever the task already had; explicit pick wins.
    final RepeatInterval? chosenRepeat =
        repeatResult == null ? task.repeat : repeatResult.interval;

    Haptics.light();
    await _handleTaskReminder(task, newReminderDateTime, repeat: chosenRepeat);
  }

  void _clearReminder(Task task) async {
    if (_isEditMode) return;

    Haptics.selection();
    await _handleTaskReminder(task, null);
  }

  void _restoreTodo(ArchivedTask restoredTask) {
    Haptics.light();
    setState(() {
      _archivedTodos.remove(restoredTask);
      _todos.add(Task.createNew(text: restoredTask.text));
    });
    _saveData();
  }

  void _clearArchive() {
    Haptics.medium();
    setState(() {
      _archivedTodos.clear();
    });
    _saveData();
  }

  // --- EDIT MODE FUNCTIONS ---
  void _enterEditMode() {
    Haptics.medium();
    setState(() {
      _isEditMode = true;
    });
  }

  void _exitEditMode() {
    Haptics.light();
    setState(() {
      _isEditMode = false;
      _taskBeingEdited = null;
    });
    _focusNode.unfocus();
  }

  void _startEditingTask(Task task) {
    Haptics.selection();
    setState(() {
      _taskBeingEdited = task;
      _editTextController.text = task.text;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  void _saveTaskEdit() {
    if (_taskBeingEdited != null &&
        _editTextController.text.trim().isNotEmpty) {
      Haptics.light();
      final updatedTask = _taskBeingEdited!
          .copyWith(text: _editTextController.text.trim());
      _updateTask(updatedTask);

      if (updatedTask.reminderDateTime != null) {
        _handleTaskReminder(updatedTask, updatedTask.reminderDateTime);
      }
    }
    setState(() {
      _taskBeingEdited = null;
    });
    _focusNode.unfocus();
  }

  void _cancelTaskEdit() {
    Haptics.selection();
    setState(() {
      _taskBeingEdited = null;
    });
    _focusNode.unfocus();
  }

  void _navigateToArchive() async {
    Haptics.selection();
    _focusNode.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => ArchiveScreen(
              archivedTodos: _archivedTodos,
              onRestore: (task) => _restoreTodo(task),
              onClear: _clearArchive,
            )));
  }
  
  // Back button navigates back to the list selection screen
  void _navigateBackToLists() {
    Haptics.selection();
    Navigator.of(context).pop();
  }

  // --- List customization --------------------------------------------------

  // Resolves the latest TaskList from the provider. The widget's `list` is the
  // snapshot taken when this screen was pushed; subsequent edits (rename, color
  // change, icon pick) are only reflected on the provider side, so the screen
  // must reread on every build to keep the AppBar in sync.
  TaskList _currentList(SettingsNotifier settings) {
    return settings.taskLists.firstWhere(
      (l) => l.id == widget.list.id,
      orElse: () => widget.list,
    );
  }

  Future<void> _promptRenameList() async {
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    final controller = TextEditingController(text: current.name);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename list'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            labelText: 'List name',
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty && result != current.name) {
      settings.updateTaskList(current.copyWith(name: result));
    }
  }

  Future<void> _promptChangeColor() async {
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    final theme = Theme.of(context);
    final initial = current.color != null
        ? Color(current.color!)
        : theme.colorScheme.primary;
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => AdvancedColorPicker(
        initialColor: initial,
        onAddSavedColor: settings.addSavedColor,
        onRemoveSavedColor: settings.removeSavedColor,
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      settings.updateTaskList(current.copyWith(color: picked.toARGB32()));
    }
  }

  Future<void> _promptChangeIcon() async {
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    final result = await showIconPickerSheet(context);
    if (!mounted || result == null) return;
    // IconPickerResult: exactly-one-of / both-null to clear.
    settings.updateTaskList(current.copyWith(
      iconEmoji: result.emoji,
      iconCodePoint: result.codePoint?.toString(),
    ));
  }

  Future<void> _promptDeleteList() async {
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    final descendants = settings.descendantsOf(current.id);
    final taskCount = settings.activeTaskCountFor(current.id, deep: true);
    final parts = <String>[];
    if (descendants.isNotEmpty) {
      parts.add('${descendants.length} sub-list${descendants.length == 1 ? '' : 's'}');
    }
    if (taskCount > 0) {
      parts.add('$taskCount active task${taskCount == 1 ? '' : 's'}');
    }
    final detail = parts.isEmpty
        ? 'Completed items stay in the archive.'
        : '${parts.join(' and ')} will be removed. Completed items stay in the archive.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${current.name}"?'),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    Haptics.medium();
    await settings.cascadeDeleteList(current.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _promptCreateSubList() async {
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('New sub-list under "${current.name}"'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'List name'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    Haptics.light();
    settings.addTaskList(
      TaskList.createNew(name: name, parentId: current.id),
    );
  }

  Future<void> _promptReparent() async {
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    // Eligible destinations: Root (null) + every list that isn't this list or
    // one of its descendants — reparenting into own subtree would cycle.
    final banned = settings.descendantsOf(current.id).map((l) => l.id).toSet()
      ..add(current.id);
    final candidates =
        settings.taskLists.where((l) => !banned.contains(l.id)).toList();

    final selected = await showDialog<_ReparentChoice>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Move under…'),
        children: [
          SimpleDialogOption(
            child: const Text('Top level (no parent)'),
            onPressed: () =>
                Navigator.of(context).pop(const _ReparentChoice(null)),
          ),
          const Divider(height: 1),
          for (final c in candidates)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(_ReparentChoice(c.id)),
              child: Text(c.name),
            ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No other lists available.'),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.parentId == current.parentId) return;
    Haptics.light();
    settings.reparentList(current.id, selected.parentId);
  }

  void _navigateToSubList(TaskList child) {
    Haptics.selection();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListDetailScreen(list: child)),
    );
  }

  Future<void> _openAppearanceEditor() async {
    Haptics.selection();
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    final picked = await PresetPickerSheet.show(
      context,
      globalThemes: settings.themes,
      currentOverride: current.themeOverride,
    );
    if (picked == null || !mounted) return;
    picked.isDeletable = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ThemeEditorScreen(theme: picked, listId: current.id),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _resetAppearance() async {
    Haptics.selection();
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final current = _currentList(settings);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reset appearance?'),
        content: Text(
          '"${current.name}" will go back to using the global theme.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    settings.updateListTheme(current.id, null);
  }

  @override
  Widget build(BuildContext context) {
    final outerBrightness = Theme.of(context).brightness;
    final settings = Provider.of<SettingsNotifier>(context);
    final current = _currentList(settings);
    final customTheme = settings.effectiveThemeFor(current);
    final backgroundImage = customTheme.backgroundImagePath;
    final hasOverride = current.themeOverride != null;

    return Theme(
      data: buildThemeData(outerBrightness, customTheme),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return _buildScaffold(
            context,
            theme: theme,
            settings: settings,
            current: current,
            customTheme: customTheme,
            backgroundImage: backgroundImage,
            hasOverride: hasOverride,
          );
        },
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required ThemeData theme,
    required SettingsNotifier settings,
    required TaskList current,
    required CustomTheme customTheme,
    required String? backgroundImage,
    required bool hasOverride,
  }) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: buildListIcon(
                emoji: current.iconEmoji,
                codePoint: current.iconCodePoint,
                color: theme.appBarTheme.foregroundColor ??
                    theme.iconTheme.color ??
                    Colors.white,
                size: 22,
              ),
            ),
            Expanded(
              child: Text(
                current.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBackToLists),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.edit_off : Icons.edit_outlined),
            tooltip: _isEditMode ? 'Exit edit mode' : 'Edit tasks',
            onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Archive',
            onPressed: _navigateToArchive,
          ),
          PopupMenuButton<String>(
            tooltip: 'List options',
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  _promptRenameList();
                  break;
                case 'color':
                  _promptChangeColor();
                  break;
                case 'icon':
                  _promptChangeIcon();
                  break;
                case 'appearance':
                  _openAppearanceEditor();
                  break;
                case 'reset_appearance':
                  _resetAppearance();
                  break;
                case 'sublist':
                  _promptCreateSubList();
                  break;
                case 'reparent':
                  _promptReparent();
                  break;
                case 'delete':
                  _promptDeleteList();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rename'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'color',
                child: ListTile(
                  leading: Icon(Icons.color_lens_outlined),
                  title: Text('Change icon color'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'icon',
                child: ListTile(
                  leading: Icon(Icons.emoji_emotions_outlined),
                  title: Text('Change icon'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'appearance',
                child: ListTile(
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Customize theme'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (hasOverride)
                const PopupMenuItem(
                  value: 'reset_appearance',
                  child: ListTile(
                    leading: Icon(Icons.format_color_reset_outlined),
                    title: Text('Reset theme'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'sublist',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder_outlined),
                  title: Text('Add sub-list'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'reparent',
                child: ListTile(
                  leading: Icon(Icons.drive_file_move_outlined),
                  title: Text('Move list'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                  title: Text('Delete list',
                      style: TextStyle(color: theme.colorScheme.error)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_focusNode.hasFocus) {
            _focusNode.unfocus();
          }
        },
        behavior: HitTestBehavior.translucent,
        child: Container(
          decoration: backgroundImage != null && File(backgroundImage).existsSync()
              ? BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(File(backgroundImage)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.1), BlendMode.darken),
                  ),
                )
              : null,
          child: Column(
            children: [
              _SubListStrip(
                parentId: widget.list.id,
                themeOverride: customTheme,
                onTap: _navigateToSubList,
                onAddSubList: _promptCreateSubList,
              ),
              Expanded(
                child: _todos.isEmpty && _completingTaskIds.isEmpty
                    ? Center(
                        child: Text(
                          'Tap the text box below to add your first task.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.hintColor.withValues(alpha: 0.8),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : TaskListEditor(
                        keyPrefix: 'list-${widget.list.id}',
                        controller: TaskListEditorController(
                          tasks: _todos,
                          completingTaskIds: _completingTaskIds,
                          isEditMode: _isEditMode,
                          taskBeingEdited: _taskBeingEdited,
                          editTextController: _editTextController,
                          focusNode: _focusNode,
                          onCompleteTask: _completeTask,
                          onSetReminder: _showDateTimePicker,
                          onClearReminder: _clearReminder,
                          onReorder: _reorderTasks,
                          onStartEditing: _startEditingTask,
                          onSaveEdit: _saveTaskEdit,
                          onCancelEdit: _cancelTaskEdit,
                          onAnimationEnd: _onAnimationEnd,
                          onLongPress: _promptMoveTask,
                          themeOverride: hasOverride ? customTheme : null,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomSheet: TaskInputField(
        controller: _textController,
        focusNode: _focusNode,
        onSubmit: _addTodo,
        customTheme: customTheme,
      ),
    );
  }
}

/// Horizontal strip of a list's direct children, plus a trailing "+" tile to
/// add another. Collapses to just the "+" tile when the parent has no kids
/// so the strip never eats vertical space unnecessarily. Listens to
/// SettingsNotifier directly so renames/adds/deletes refresh live.
class _SubListStrip extends StatelessWidget {
  final String parentId;
  final void Function(TaskList) onTap;
  final VoidCallback onAddSubList;
  final CustomTheme? themeOverride;

  const _SubListStrip({
    required this.parentId,
    required this.onTap,
    required this.onAddSubList,
    this.themeOverride,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsNotifier>(context);
    final theme = Theme.of(context);
    final children = settings.childrenOf(parentId);
    final customTheme = themeOverride ?? settings.currentTheme;

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == children.length) {
            return _SubListChip(
              label: 'Add',
              icon: const Icon(Icons.add, size: 18),
              accent: customTheme.secondaryColor,
              background: customTheme.taskBackgroundColor,
              dashed: true,
              onTap: onAddSubList,
            );
          }
          final child = children[index];
          final accent = child.color != null
              ? Color(child.color!)
              : customTheme.secondaryColor;
          final count =
              settings.activeTaskCountFor(child.id, deep: true);
          return _SubListChip(
            label: child.name,
            icon: buildListIcon(
              emoji: child.iconEmoji,
              codePoint: child.iconCodePoint,
              color: accent,
              size: 18,
            ),
            accent: accent,
            background: customTheme.taskBackgroundColor,
            badgeCount: count,
            onTap: () => onTap(child),
          );
        },
      ),
    );
  }
}

class _SubListChip extends StatelessWidget {
  final String label;
  final Widget icon;
  final Color accent;
  final Color background;
  final int? badgeCount;
  final bool dashed;
  final VoidCallback onTap;

  const _SubListChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.background,
    this.badgeCount,
    this.dashed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 90, maxWidth: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: dashed ? 0.6 : 0.4),
              width: dashed ? 1.2 : 1,
              style: dashed ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (badgeCount != null && badgeCount! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}