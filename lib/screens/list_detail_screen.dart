import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'dart:io';

import '../models/archived_task.dart';
import '../models/task.dart';
import '../models/custom_theme.dart';
import '../models/list.dart';
import '../providers/settings_notifier.dart';
import '../services/notification_service.dart';
import '../widgets/animating_todo_item.dart';
import '../widgets/todo_item.dart';
import 'archive_screen.dart';
import 'settings_screen.dart'; // Still used for navigation

class ListDetailScreen extends StatefulWidget {
  final TaskList list;
  const ListDetailScreen({super.key, required this.list});
  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  final List<Task> _todos = [];
  final List<ArchivedTask> _archivedTodos = [];
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = new FocusNode(); 
  final List<String> _completingTaskIds = [];

  // --- EDIT MODE STATE ---
  bool _isEditMode = false;
  Task? _taskBeingEdited;
  final TextEditingController _editTextController = TextEditingController();
  String _originalText = '';

  final NotificationService _notificationService = NotificationService();
  // FIX: Change stream subscription type to Map<String, String>
  StreamSubscription<Map<String, String>>? _completionSubscription;
  
  // Persistence keys based on List ID
  late String _todosKey;
  late String _archivedTodosKey;

  @override
  void initState() {
    super.initState();
    _todosKey = 'todos_${widget.list.id}';
    _archivedTodosKey = 'archivedTodos_${widget.list.id}';
    _loadData();
    _initializeNotifications();
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
      _completionSubscription = _notificationService.taskCompletedStream
          .listen((data) => _completeTaskFromNotification(data['taskId']!, data['listId']!));
    } catch (e) {
      print('Failed to init notifications: $e');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _editTextController.dispose();
    _completionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = Provider.of<SettingsNotifier>(context, listen: false);

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
      HapticFeedback.lightImpact();
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

  /// This is called when a user taps "complete" in the UI.
  void _completeTodo(int index) {
    if (_isEditMode) return;

    HapticFeedback.lightImpact();
    final taskToComplete = _todos[index];

    if (taskToComplete.reminderDateTime != null) {
      _notificationService.cancelNotification(
          NotificationService.generateNotificationId(taskToComplete.id));
    }

    final newArchivedTask = ArchivedTask(
      text: taskToComplete.text,
      archivedAtTimestamp: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      _completingTaskIds.add(taskToComplete.id);
      _archivedTodos.insert(0, newArchivedTask);
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

		final newArchivedTask = ArchivedTask(
		  text: taskToComplete.text,
		  archivedAtTimestamp: DateTime.now().millisecondsSinceEpoch,
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
      Task task, DateTime? newReminderDateTime) async {
    if (_isEditMode) return;

    final notificationId = NotificationService.generateNotificationId(task.id);

    await _notificationService.cancelNotification(notificationId);

    if (newReminderDateTime != null) {
      // FIX: Provide the required listId
      await _notificationService.scheduleNotification(
        task: task,
        scheduledTime: newReminderDateTime,
        listId: widget.list.id,
      );
    }

    _updateTask(task.copyWith(reminderDateTime: newReminderDateTime));
  }

  Future<void> _showDateTimePicker(Task task) async {
    if (_isEditMode) return;

    HapticFeedback.selectionClick();

    final now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: task.reminderDateTime ?? now,
      firstDate: now,
      lastDate: DateTime(2101),
    );

    if (pickedDate == null || !mounted) return;

    TimeOfDay initialTime;

    if (pickedDate.year == now.year &&
        pickedDate.month == now.month &&
        pickedDate.day == now.day) {
      initialTime = TimeOfDay.fromDateTime(now.add(const Duration(minutes: 1)));
    } else {
      initialTime = TimeOfDay.fromDateTime(task.reminderDateTime ?? now);
    }

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

    HapticFeedback.lightImpact();
    await _handleTaskReminder(task, newReminderDateTime);
  }

  void _clearReminder(Task task) async {
    if (_isEditMode) return;

    HapticFeedback.selectionClick();
    await _handleTaskReminder(task, null);
  }

  void _restoreTodo(ArchivedTask restoredTask) {
    HapticFeedback.lightImpact();
    setState(() {
      _archivedTodos.remove(restoredTask);
      _todos.add(Task.createNew(text: restoredTask.text));
    });
    _saveData();
  }

  void _clearArchive() {
    HapticFeedback.mediumImpact();
    setState(() {
      _archivedTodos.clear();
    });
    _saveData();
  }

  // --- EDIT MODE FUNCTIONS ---
  void _enterEditMode() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isEditMode = true;
    });
  }

  void _exitEditMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isEditMode = false;
      _taskBeingEdited = null;
    });
    _focusNode.unfocus();
  }

  void _startEditingTask(Task task) {
    HapticFeedback.selectionClick();
    setState(() {
      _taskBeingEdited = task;
      _originalText = task.text;
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
      HapticFeedback.lightImpact();
      final updatedTask = _taskBeingEdited!
          .copyWith(text: _editTextController.text.trim());
      _updateTask(updatedTask);

      if (updatedTask.reminderDateTime != null) {
        _handleTaskReminder(updatedTask, updatedTask.reminderDateTime);
      }
    }
    setState(() {
      _taskBeingEdited = null;
      _originalText = '';
    });
    _focusNode.unfocus();
  }

  void _cancelTaskEdit() {
    HapticFeedback.selectionClick();
    setState(() {
      _taskBeingEdited = null;
      _originalText = '';
    });
    _focusNode.unfocus();
  }

  void _navigateToArchive() async {
    HapticFeedback.selectionClick();
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
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context);
    final customTheme = settings.currentTheme;
    final backgroundImage = customTheme.backgroundImagePath;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // Show the list name
        title: Text(widget.list.name),
        // Back button replaces the settings button
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBackToLists),
        actions: [
          _isEditMode
              ? IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Exit EditMode',
                  onPressed: _exitEditMode,
                )
              : IconButton(
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: _navigateToArchive,
                  onLongPress: _enterEditMode,
                  tooltip: 'Tap for Archive, Long Press for Edit Mode',
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
                        Colors.black.withOpacity(0.1), BlendMode.darken),
                  ),
                )
              : null,
          child: _todos.isEmpty && _completingTaskIds.isEmpty 
              ? Center(
                  child: Text(
                    'Tap the text box below to add your first task.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor.withOpacity(0.8),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : _isEditMode
                  ? _buildEditModeListView() 
                  : _buildNormalListView(),
        ),
      ),
      bottomSheet: _buildInputField(theme, customTheme),
    );
  }

  Widget _buildNormalListView() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 80), 
      buildDefaultDragHandles: false,
      itemCount: _todos.length,
      itemBuilder: (context, index) {
        if (index >= _todos.length) return const SizedBox.shrink();
        
        final task = _todos[index];

        if (_completingTaskIds.contains(task.id)) {
          return AnimatingTodoItem(
            key: ValueKey(task.id),
            task: task,
            hasReminder: task.reminderDateTime != null,
            onAnimationEnd: () => _onAnimationEnd(task.id),
          );
        }

        final isBeingEdited = _taskBeingEdited?.id == task.id;

        return TodoItem(
          key: ValueKey(task.id),
          task: task,
          index: index,
          onTapped: () => _completeTodo(index),
          onSetReminder: () => _showDateTimePicker(task),
          onClearReminder:
              task.reminderDateTime != null ? () => _clearReminder(task) : null,
          isEditMode: _isEditMode,
          isBeingEdited: isBeingEdited,
          onStartEditing: () => _startEditingTask(task),
          onSaveEdit: _saveTaskEdit,
          onCancelEdit: _cancelTaskEdit,
          editTextController: _editTextController,
          focusNode: _focusNode,
        );
      },
      onReorderStart: (index) {
        HapticFeedback.mediumImpact();
      },
      onReorder: (oldIndex, newIndex) {
        HapticFeedback.lightImpact();
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _todos.removeAt(oldIndex);
          _todos.insert(newIndex, item);
        });
        _saveData();
      },
    );
  }

  Widget _buildEditModeListView() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _todos.length,
      itemBuilder: (context, index) {
        if (index >= _todos.length) return const SizedBox.shrink();
        
        final task = _todos[index];

        if (_completingTaskIds.contains(task.id)) {
          return AnimatingTodoItem(
            key: ValueKey(task.id),
            task: task,
            hasReminder: task.reminderDateTime != null,
            onAnimationEnd: () => _onAnimationEnd(task.id),
          );
        }

        final isBeingEdited = _taskBeingEdited?.id == task.id;

        return TodoItem(
          key: ValueKey(task.id),
          task: task,
          index: index,
          onTapped: () {}, // Tap does nothing in edit mode unless editing starts
          onSetReminder: () => _showDateTimePicker(task),
          onClearReminder:
              task.reminderDateTime != null ? () => _clearReminder(task) : null,
          isEditMode: _isEditMode,
          isBeingEdited: isBeingEdited,
          onStartEditing: () => _startEditingTask(task),
          onSaveEdit: _saveTaskEdit,
          onCancelEdit: _cancelTaskEdit,
          editTextController: _editTextController,
          focusNode: _focusNode,
        );
      },
    );
  }

  Widget _buildInputField(ThemeData theme, CustomTheme customTheme) {
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final double safeAreaBottom = MediaQuery.of(context).padding.bottom;
    
    const double verticalBuffer = 12.0;

    final double bottomPadding = keyboardHeight > 0 
        ? keyboardHeight + verticalBuffer 
        : safeAreaBottom + verticalBuffer;

    const double topPadding = verticalBuffer; 

    return Material(
      color: customTheme.inputAreaColor,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: topPadding, 
          bottom: bottomPadding,
        ),
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          style: theme.textTheme.bodyMedium,
          onSubmitted: (_) => _addTodo(),
          decoration: InputDecoration(
            hintText: 'Add a new task...',
            
            filled: true,
            fillColor: theme.cardColor, 

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.hintColor,
            ),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24), 
              borderSide: BorderSide(
                color: customTheme.secondaryColor, 
                width: 1.0,
              ),
            ),
            
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(
                color: customTheme.secondaryColor, 
                width: 2.0,
              ),
            ),
            
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24), 
              borderSide: BorderSide(
                color: customTheme.secondaryColor,
                width: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}