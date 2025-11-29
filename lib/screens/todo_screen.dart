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
import '../providers/settings_notifier.dart';
import '../services/notification_service.dart';
import '../widgets/animating_todo_item.dart';
import '../widgets/todo_item.dart';
import 'archive_screen.dart';
import 'settings_screen.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
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
  StreamSubscription<String>? _completionSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initializeNotifications();
    // Removed the notification permission prompt logic from here
  }

  // Removed _requestNotificationPermissions() method

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.init();
      // Listen for task completions that happen from notifications
      // while the app is running.
      _completionSubscription = _notificationService.taskCompletedStream
          .listen(_completeTaskFromNotification);
      print('Notifications initialized and stream listening');
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
    // _notificationService.dispose(); // Don't dispose singleton
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = Provider.of<SettingsNotifier>(context, listen: false);

    final todosData = prefs.getStringList('todos') ?? [];
    final archivedData = prefs.getStringList('archivedTodos') ?? [];

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
    await prefs.setStringList('todos', todosJson);
    final List<String> archivedJson = _archivedTodos
        .map((task) => json.encode(task.toJson()))
        .toList();
    await prefs.setStringList('archivedTodos', archivedJson);
  }

  void _addTodo() {
    if (_textController.text.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _todos.insert(
            0, Task(id: const Uuid().v4(), text: _textController.text.trim()));
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
    // Don't complete tasks in edit mode
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

	void _completeTaskFromNotification(String taskId) {
	  final index = _todos.indexWhere((task) => task.id == taskId);
	  if (index != -1 && mounted) {
		final taskToComplete = _todos[index];

		// Check if it's already being completed
		if (_completingTaskIds.contains(taskToComplete.id)) return;

		final newArchivedTask = ArchivedTask(
		  text: taskToComplete.text,
		  archivedAtTimestamp: DateTime.now().millisecondsSinceEpoch,
		);

		setState(() {
		  _completingTaskIds.add(taskToComplete.id);
		  _archivedTodos.insert(0, newArchivedTask);
		});

		// Cancel any reminder for this task
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
    // Don't set reminders in edit mode
    if (_isEditMode) return;

    final notificationId = NotificationService.generateNotificationId(task.id);

    // Cancel existing reminder first
    await _notificationService.cancelNotification(notificationId);

    // Schedule new reminder if time is provided
    if (newReminderDateTime != null) {
      // Use the new scheduleNotification method
      await _notificationService.scheduleNotification(
        task: task,
        scheduledTime: newReminderDateTime,
      );
    }

    _updateTask(task.copyWith(reminderDateTime: newReminderDateTime));
  }

  Future<void> _showDateTimePicker(Task task) async {
    // Don't show date picker in edit mode
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

    // Determine the initial time and minimum time for the time picker
    TimeOfDay initialTime;

    // If selected date is today, restrict times to future times only
    if (pickedDate.year == now.year &&
        pickedDate.month == now.month &&
        pickedDate.day == now.day) {
      // Set initial time to current time or later
      initialTime = TimeOfDay.fromDateTime(now.add(const Duration(minutes: 1)));
    } else {
      // For future dates, any time is allowed
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

    // Final validation to ensure the time is in the future
    if (newReminderDateTime.isBefore(DateTime.now())) {
      // Optionally show a message to the user
      return;
    }

    HapticFeedback.lightImpact();
    await _handleTaskReminder(task, newReminderDateTime);
  }

  void _clearReminder(Task task) async {
    // Don't clear reminders in edit mode
    if (_isEditMode) return;

    HapticFeedback.selectionClick();
    await _handleTaskReminder(task, null);
  }

  void _restoreTodo(ArchivedTask restoredTask) {
    HapticFeedback.lightImpact();
    setState(() {
      _archivedTodos.remove(restoredTask);
      _todos.add(Task(id: const Uuid().v4(), text: restoredTask.text));
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
    // Focus on the text field after a short delay to ensure it's built
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

      // If the task had a reminder, we need to reschedule it with the new text
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

    final settings = Provider.of<SettingsNotifier>(context, listen: false);

    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => ArchiveScreen(
              archivedTodos: _archivedTodos,
              onRestore: (task) => _restoreTodo(task),
              onClear: _clearArchive,
              taskHeight: settings.taskHeight,
            )));
  }

  void _navigateToSettings() async {
    HapticFeedback.selectionClick();
    _focusNode.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
        title: const Text('Shutter'),
        leading: IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: _navigateToSettings),
        actions: [
          // Show edit icon when in edit mode, archive icon otherwise
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
      // FIX: Wrap body in GestureDetector to handle deselecting the input box
      body: GestureDetector(
        onTap: () {
          // Dismiss keyboard and deselect input field when tapping empty space
          if (_focusNode.hasFocus) {
            _focusNode.unfocus();
          }
        },
        // Use Behavior.translucent to ensure clicks on empty space are caught
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
          child: _isEditMode
              ? _buildEditModeListView() 
              : _buildNormalListView(),
        ),
      ),
      bottomSheet: _buildInputField(theme, customTheme),
    );
  }

  Widget _buildNormalListView() {
    return ReorderableListView.builder(
      // FIX: Padding adjusted for the consistent, smaller input box height
      padding: const EdgeInsets.only(bottom: 80), 
      buildDefaultDragHandles: false, // Use custom drag handles only
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
      // FIX: Padding adjusted for the consistent, smaller input box height
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
    );
  }

  Widget _buildInputField(ThemeData theme, CustomTheme customTheme) {
    // Get safe area and keyboard values explicitly to standardize spacing
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final double safeAreaBottom = MediaQuery.of(context).padding.bottom;
    
    // FIX: Consistent vertical buffer used everywhere (Halved from 24.0)
    const double verticalBuffer = 12.0;

    // Standardized bottom padding:
    // When keyboard is open: uses keyboard height + 12px buffer
    // When keyboard is closed: uses safe area + 12px buffer (visually centered)
    final double bottomPadding = keyboardHeight > 0 
        ? keyboardHeight + verticalBuffer 
        : safeAreaBottom + verticalBuffer;

    // FIX: Top padding matches the safe bottom buffer (12.0)
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

            // Inactive border - Solid color, 1.0 width
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24), 
              borderSide: BorderSide(
                color: customTheme.secondaryColor, 
                width: 1.0,
              ),
            ),
            
            // Active border - Solid color, 2.0 width
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(
                color: customTheme.secondaryColor, 
                width: 2.0,
              ),
            ),
            
            // Fallback border (Solid 1.0)
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