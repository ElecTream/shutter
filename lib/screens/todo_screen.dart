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
  final FocusNode _focusNode = FocusNode();
  bool _isComposing = false;
  final List<String> _completingTaskIds = [];
  
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadData();
    _initializeNotifications();
    _textController.addListener(() {
      final isComposing = _textController.text.trim().isNotEmpty;
      if (_isComposing != isComposing) setState(() => _isComposing = isComposing);
    });
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.init();
      print('Notifications initialized');
    } catch (e) {
      print('Failed to init notifications: $e');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
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
      
      final clearThreshold = now - (durationMap[archiveClearDuration]?.inMilliseconds ?? 0);
      final originalCount = loadedArchived.length;
      loadedArchived.removeWhere((task) => task.archivedAtTimestamp < clearThreshold);
      archiveWasModified = originalCount != loadedArchived.length;
    }

    setState(() {
      _todos.clear();
      _archivedTodos.clear();
      _todos.addAll(todosData.map((jsonString) => Task.fromJson(json.decode(jsonString))));
      _archivedTodos.addAll(loadedArchived);
    });

    if (archiveWasModified) {
      _saveData();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> todosJson = _todos.map((task) => json.encode(task.toJson())).toList();
    await prefs.setStringList('todos', todosJson);
    final List<String> archivedJson = _archivedTodos.map((task) => json.encode(task.toJson())).toList();
    await prefs.setStringList('archivedTodos', archivedJson);
  }

  void _addTodo() {
    if (_textController.text.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _todos.insert(0, Task(id: const Uuid().v4(), text: _textController.text.trim()));
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

  void _completeTodo(int index) {
    HapticFeedback.lightImpact();
    final taskToComplete = _todos[index];
    
    if (taskToComplete.reminderDateTime != null) {
      _notificationService.cancelNotification(
        NotificationService.generateNotificationId(taskToComplete.id)
      );
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

  void _updateTask(Task updatedTask) {
    final index = _todos.indexWhere((task) => task.id == updatedTask.id);
    if (index != -1) {
      setState(() {
        _todos[index] = updatedTask;
      });
      _saveData();
    }
  }

  Future<void> _handleTaskReminder(Task task, DateTime? newReminderDateTime) async {
    final notificationId = NotificationService.generateNotificationId(task.id);
    
    // Cancel existing reminder first
    await _notificationService.cancelNotification(notificationId);
    
    // Schedule new reminder if time is provided
    if (newReminderDateTime != null) {
      await _notificationService.scheduleNotification(
        id: notificationId,
        title: 'Task Reminder',
        body: task.text,
        scheduledTime: newReminderDateTime,
      );
    }
    
    _updateTask(task.copyWith(reminderDateTime: newReminderDateTime));
  }
  
  Future<void> _showDateTimePicker(Task task) async {
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
      return;
    }

    await _handleTaskReminder(task, newReminderDateTime);
  }

  void _clearReminder(Task task) async {
    await _handleTaskReminder(task, null);
  }
  
  void _restoreTodo(ArchivedTask restoredTask) {
    setState(() {
      _archivedTodos.remove(restoredTask);
      _todos.add(Task(id: const Uuid().v4(), text: restoredTask.text));
    });
    _saveData();
  }

  void _clearArchive() {
    setState(() {
      _archivedTodos.clear();
    });
    _saveData();
  }
  
  void _navigateToArchive() async {
    _focusNode.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    
    final settings = Provider.of<SettingsNotifier>(context, listen: false);

    Navigator.of(context).push(MaterialPageRoute(builder: (context) => ArchiveScreen(
      archivedTodos: _archivedTodos,
      onRestore: (task) => _restoreTodo(task),
      onClear: _clearArchive,
      taskHeight: settings.taskHeight,
    )));
  }

  void _navigateToSettings() async {
    _focusNode.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
          onPressed: _navigateToSettings
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined), 
            onPressed: _navigateToArchive
          ),
        ],
      ),
      body: Container(
        decoration: backgroundImage != null && File(backgroundImage).existsSync()
          ? BoxDecoration(
              image: DecorationImage(
                image: FileImage(File(backgroundImage)), 
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.1), 
                  BlendMode.darken
                ),
              ),
            )
          : null,
        child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: _todos.length,
            itemBuilder: (context, index) {
              final task = _todos[index];

              if (_completingTaskIds.contains(task.id)) {
                return AnimatingTodoItem(
                  key: ValueKey(task.id),
                  text: task.text,
                  onAnimationEnd: () => _onAnimationEnd(task.id),
                );
              }
              
              return TodoItem(
                key: ValueKey(task.id),
                task: task,
                index: index,
                onTapped: () => _completeTodo(index),
                onSetReminder: () => _showDateTimePicker(task),
                onClearReminder: task.reminderDateTime != null 
                    ? () => _clearReminder(task)
                    : null,
              );
            },
            onReorder: (oldIndex, newIndex) {
              HapticFeedback.selectionClick();
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _todos.removeAt(oldIndex);
                _todos.insert(newIndex, item);
              });
              _saveData();
            },
          ),
      ),
      bottomSheet: _buildInputField(theme, customTheme),
    );
  }
  
  Widget _buildInputField(ThemeData theme, CustomTheme customTheme) {
    return Material(
      color: customTheme.inputAreaColor,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 8,
        ),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  style: theme.textTheme.bodyMedium,
                  onSubmitted: (_) => _addTodo(),
                  decoration: InputDecoration(
                    hintText: 'Add a new task...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation, 
                child: child,
              ),
              child: _isComposing
                  ? Container(
                      decoration: BoxDecoration(
                        color: customTheme.secondaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: customTheme.secondaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: _addTodo,
                        icon: const Icon(Icons.add, color: Colors.white),
                        splashRadius: 24,
                      ),
                    )
                  : const SizedBox(width: 48, height: 48),
            ),
          ]),
        ),
      ),
    );
  }
}