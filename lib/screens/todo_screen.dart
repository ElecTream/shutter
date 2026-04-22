import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/haptics.dart';

import '../models/custom_theme.dart';
import '../models/list.dart';
import '../models/repeat_interval.dart';
import '../models/task.dart';
import '../providers/settings_notifier.dart';
import '../services/notification_service.dart';
import '../widgets/icon_picker_sheet.dart';
import '../widgets/move_to_sheet.dart';
import '../widgets/repeat_picker_sheet.dart';
import '../widgets/task_list_editor.dart';
import 'archive_screen.dart';
import 'list_detail_screen.dart';
import 'settings_screen.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen>
    with WidgetsBindingObserver {
  // --- Root task editor state ---
  final TextEditingController _taskTextController = TextEditingController();
  final FocusNode _taskFocusNode = FocusNode();
  final TextEditingController _editTextController = TextEditingController();
  final Set<String> _completingTaskIds = <String>{};
  bool _isEditMode = false;
  Task? _taskBeingEdited;

  // --- Inline list-rename state (edit mode) ---
  String? _listBeingEditedId;
  final TextEditingController _listEditController = TextEditingController();
  final FocusNode _listFocusNode = FocusNode();

  // --- Notifications ---
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<Map<String, String>>? _completionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The background isolate may have archived a root task while we were
      // away; pull fresh state from disk.
      Provider.of<SettingsNotifier>(context, listen: false)
          .reloadRootFromDisk();
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.init();
      _completionSubscription =
          _notificationService.taskCompletedStream.listen((data) {
        if (!mounted) return;
        if (data['listId'] == 'root') {
          Provider.of<SettingsNotifier>(context, listen: false)
              .reloadRootFromDisk();
        }
      });
    } catch (e) {
      debugPrint('Failed to init notifications on home: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taskTextController.dispose();
    _taskFocusNode.dispose();
    _editTextController.dispose();
    _listEditController.dispose();
    _listFocusNode.dispose();
    _completionSubscription?.cancel();
    super.dispose();
  }

  // --- Navigation -----------------------------------------------------------

  void _navigateToList(TaskList list) {
    Haptics.selection();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListDetailScreen(list: list)),
    );
  }

  void _navigateToSettings() {
    Haptics.selection();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _navigateToGlobalArchive() async {
    Haptics.selection();
    _taskFocusNode.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ArchiveScreen.global(),
      ),
    );
  }

  // --- Root task actions ----------------------------------------------------

  void _addRootTask() {
    final text = _taskTextController.text.trim();
    if (text.isEmpty) return;
    Haptics.light();
    Provider.of<SettingsNotifier>(context, listen: false)
        .addRootTask(Task.createNew(text: text));
    _taskTextController.clear();
    _taskFocusNode.requestFocus();
  }

  void _tapRootTask(Task task) {
    if (_isEditMode) return;
    Haptics.light();
    final settings = Provider.of<SettingsNotifier>(context, listen: false);

    // Recurring tasks advance; they don't archive. Mirrors the bg isolate.
    if (task.repeat != null) {
      final nextFire = DateTime.now().add(task.repeat!.duration);
      _handleRootReminder(task, nextFire, repeat: task.repeat);
      return;
    }

    if (task.reminderDateTime != null) {
      _notificationService.cancelNotification(
        NotificationService.generateNotificationId(task.id),
      );
    }
    settings.archiveRootSnapshot(task);
    setState(() => _completingTaskIds.add(task.id));
  }

  void _onRootAnimationEnd(String taskId) {
    if (!mounted) return;
    Provider.of<SettingsNotifier>(context, listen: false)
        .removeRootTask(taskId);
    setState(() => _completingTaskIds.remove(taskId));
  }

  Future<void> _handleRootReminder(
    Task task,
    DateTime? newDt, {
    RepeatInterval? repeat,
  }) async {
    if (_isEditMode) return;
    final notificationId = NotificationService.generateNotificationId(task.id);
    await _notificationService.cancelNotification(notificationId);

    // Write updated task first so the bg isolate reads the right `repeat`
    // field when Mark Complete fires from a killed app.
    final updated = task.copyWith(
      reminderDateTime: newDt,
      repeat: newDt == null ? null : repeat,
    );
    if (!mounted) return;
    Provider.of<SettingsNotifier>(context, listen: false)
        .updateRootTask(updated);

    if (newDt != null) {
      await _notificationService.scheduleNotification(
        task: updated,
        scheduledTime: newDt,
        listId: 'root',
      );
    }
  }

  Future<void> _showRootDateTimePicker(Task task) async {
    if (_isEditMode) return;
    Haptics.selection();
    await _notificationService.requestPermission();
    if (!mounted) return;

    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: task.reminderDateTime ?? now,
      firstDate: now,
      lastDate: DateTime(2101),
    );
    if (pickedDate == null || !mounted) return;

    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final TimeOfDay initialTime;
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
    final pickedTime =
        await showTimePicker(context: context, initialTime: initialTime);
    if (pickedTime == null) return;

    final newDt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
        pickedTime.hour, pickedTime.minute);
    if (newDt.isBefore(DateTime.now())) return;

    if (!mounted) return;
    final repeatResult =
        await showRepeatPickerSheet(context, current: task.repeat);
    if (!mounted) return;
    final RepeatInterval? chosenRepeat =
        repeatResult == null ? task.repeat : repeatResult.interval;

    Haptics.light();
    await _handleRootReminder(task, newDt, repeat: chosenRepeat);
  }

  void _clearRootReminder(Task task) async {
    if (_isEditMode) return;
    Haptics.selection();
    await _handleRootReminder(task, null);
  }

  // --- Edit mode (root tasks) ---------------------------------------------

  void _enterEditMode() {
    Haptics.medium();
    setState(() => _isEditMode = true);
  }

  void _exitEditMode() {
    Haptics.light();
    setState(() {
      _isEditMode = false;
      _taskBeingEdited = null;
      _listBeingEditedId = null;
    });
    _taskFocusNode.unfocus();
    _listFocusNode.unfocus();
  }

  // --- Inline list rename (edit mode) --------------------------------------

  void _startEditingList(TaskList list) {
    Haptics.selection();
    setState(() {
      _listBeingEditedId = list.id;
      _listEditController.text = list.name;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) FocusScope.of(context).requestFocus(_listFocusNode);
    });
  }

  void _saveListEdit(TaskList list) {
    final newName = _listEditController.text.trim();
    if (newName.isNotEmpty && newName != list.name) {
      Haptics.light();
      Provider.of<SettingsNotifier>(context, listen: false)
          .updateTaskList(list.copyWith(name: newName));
    }
    setState(() => _listBeingEditedId = null);
    _listFocusNode.unfocus();
  }

  void _cancelListEdit() {
    Haptics.selection();
    setState(() => _listBeingEditedId = null);
    _listFocusNode.unfocus();
  }

  void _startEditingTask(Task task) {
    Haptics.selection();
    setState(() {
      _taskBeingEdited = task;
      _editTextController.text = task.text;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) FocusScope.of(context).requestFocus(_taskFocusNode);
    });
  }

  void _saveTaskEdit() {
    final edited = _taskBeingEdited;
    final newText = _editTextController.text.trim();
    if (edited != null && newText.isNotEmpty) {
      Haptics.light();
      final updated = edited.copyWith(
        text: newText,
        reminderDateTime: edited.reminderDateTime,
        repeat: edited.repeat,
      );
      Provider.of<SettingsNotifier>(context, listen: false)
          .updateRootTask(updated);
      if (updated.reminderDateTime != null) {
        _handleRootReminder(
          updated,
          updated.reminderDateTime,
          repeat: updated.repeat,
        );
      }
    }
    setState(() => _taskBeingEdited = null);
    _taskFocusNode.unfocus();
  }

  void _cancelTaskEdit() {
    Haptics.selection();
    setState(() => _taskBeingEdited = null);
    _taskFocusNode.unfocus();
  }

  // --- List actions --------------------------------------------------------

  // Creates a new list via a name dialog. Rename/color/icon/delete live on
  // the list detail's overflow menu so there's one canonical place to manage
  // a list.
  Future<void> _createNewList() async {
    Haptics.selection();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New list'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    Haptics.light();
    final newList = TaskList.createNew(name: name);
    Provider.of<SettingsNotifier>(context, listen: false).addTaskList(newList);
  }

  // --- Section toggles -----------------------------------------------------

  void _toggleTasksGroup() {
    final s = Provider.of<SettingsNotifier>(context, listen: false);
    s.setTasksGroupExpanded(!s.tasksGroupExpanded);
  }

  void _toggleListsGroup() {
    final s = Provider.of<SettingsNotifier>(context, listen: false);
    s.setListsGroupExpanded(!s.listsGroupExpanded);
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsNotifier>(context);
    final theme = Theme.of(context);
    final customTheme = settings.currentTheme;
    final backgroundImage = customTheme.backgroundImagePath;

    final bool showBottomInput = settings.tasksGroupExpanded;

    final slivers = <Widget>[];
    final tasksSlivers = _buildTasksSectionSlivers(settings, theme, customTheme);
    final listsSlivers = _buildListsSectionSlivers(settings, theme, customTheme);
    if (settings.tasksGroupFirst) {
      slivers.addAll(tasksSlivers);
      slivers.addAll(listsSlivers);
    } else {
      slivers.addAll(listsSlivers);
      slivers.addAll(tasksSlivers);
    }
    // Bottom padding so the last item isn't hidden by the input bar.
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Shutter'),
        leading: IconButton(
          icon: const Icon(Icons.palette_outlined),
          tooltip: 'Settings',
          onPressed: _navigateToSettings,
        ),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.edit_off : Icons.edit_outlined),
            tooltip: _isEditMode ? 'Exit edit mode' : 'Edit tasks',
            onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'All Archive',
            onPressed: _navigateToGlobalArchive,
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add new list',
            onPressed: _createNewList,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_taskFocusNode.hasFocus) _taskFocusNode.unfocus();
        },
        child: Container(
          decoration: backgroundImage != null &&
                  File(backgroundImage).existsSync()
              ? BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(File(backgroundImage)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.1),
                      BlendMode.darken,
                    ),
                  ),
                )
              : null,
          child: CustomScrollView(slivers: slivers),
        ),
      ),
      bottomSheet: showBottomInput
          ? TaskInputField(
              controller: _taskTextController,
              focusNode: _taskFocusNode,
              onSubmit: _addRootTask,
              customTheme: customTheme,
              hintText: 'Add a task to Root...',
            )
          : null,
    );
  }

  // --- Tasks section -------------------------------------------------------

  List<Widget> _buildTasksSectionSlivers(
    SettingsNotifier settings,
    ThemeData theme,
    CustomTheme customTheme,
  ) {
    final rootTasks = settings.rootTasks;
    final expanded = settings.tasksGroupExpanded;
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _SectionHeader(
          label: 'Tasks',
          count: rootTasks.length,
          expanded: expanded,
          onTap: _toggleTasksGroup,
          theme: theme,
          customTheme: customTheme,
        ),
      ),
    ];
    if (!expanded) return slivers;

    if (rootTasks.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Text(
            'No root tasks yet. Use the input below to add one.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: customTheme.taskTextColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ));
      return slivers;
    }

    slivers.add(
      TaskListEditorSliver(
        keyPrefix: 'root',
        controller: TaskListEditorController(
          tasks: rootTasks,
          completingTaskIds: _completingTaskIds,
          isEditMode: _isEditMode,
          taskBeingEdited: _taskBeingEdited,
          editTextController: _editTextController,
          focusNode: _taskFocusNode,
          onCompleteTask: _tapRootTask,
          onSetReminder: _showRootDateTimePicker,
          onClearReminder: _clearRootReminder,
          onReorder: (o, n) =>
              Provider.of<SettingsNotifier>(context, listen: false)
                  .reorderRootTasks(o, n),
          onStartEditing: _startEditingTask,
          onSaveEdit: _saveTaskEdit,
          onCancelEdit: _cancelTaskEdit,
          onAnimationEnd: _onRootAnimationEnd,
          onLongPress: _promptMoveRootTask,
        ),
      ),
    );
    return slivers;
  }

  Future<void> _promptMoveRootTask(Task task) async {
    final picked = await showMoveToSheet(
      context,
      excludeContainerId: 'root',
    );
    if (picked == null || !mounted) return;
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    await settings.moveTask(
      task,
      fromContainerId: 'root',
      toContainerId: picked,
    );
  }

  // --- Lists section -------------------------------------------------------

  List<Widget> _buildListsSectionSlivers(
    SettingsNotifier settings,
    ThemeData theme,
    CustomTheme customTheme,
  ) {
    // Only top-level lists surface on home; sub-lists live inside their
    // parent's detail screen.
    final lists = settings.childrenOf(null);
    final expanded = settings.listsGroupExpanded;
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _SectionHeader(
          label: 'Lists',
          count: lists.length,
          expanded: expanded,
          onTap: _toggleListsGroup,
          theme: theme,
          customTheme: customTheme,
        ),
      ),
    ];
    if (!expanded) return slivers;

    if (lists.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Text(
            'No lists yet. Use the + button in the app bar to create one.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: customTheme.taskTextColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ));
      return slivers;
    }

    const double standardBaseHeight = 72.0;
    final double calculatedHeight = standardBaseHeight * settings.taskHeight;
    const double contentHeight = 25.0;
    final double verticalPadding =
        ((calculatedHeight - contentHeight) / 2).clamp(10.0, 36.0);

    slivers.add(
      SliverReorderableList(
        itemCount: lists.length,
        onReorderStart: (_) => Haptics.medium(),
        onReorder: (oldIndex, newIndex) {
          Haptics.light();
          Provider.of<SettingsNotifier>(context, listen: false)
              .reorderListsWithin(null, oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final list = lists[index];
          return _buildListTile(
            list,
            index,
            theme,
            customTheme,
            calculatedHeight,
            verticalPadding,
          );
        },
      ),
    );
    return slivers;
  }

  Widget _buildListTile(
    TaskList list,
    int index,
    ThemeData theme,
    CustomTheme customTheme,
    double calculatedHeight,
    double verticalPadding,
  ) {
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final Color accent = list.color != null
        ? Color(list.color!)
        : customTheme.secondaryColor;
    // Direct count only — rollups caused cross-list confusion (a parent's
    // badge would inflate with its descendants' tasks, looking like the
    // wrong list held them).
    final int count = settings.activeTaskCountFor(list.id, deep: false);
    final bool isBeingEdited = _listBeingEditedId == list.id;

    return Column(
      key: ValueKey('list-${list.id}'),
      children: [
        Material(
          color: customTheme.taskBackgroundColor,
          child: InkWell(
            onTap: isBeingEdited
                ? null
                : (_isEditMode
                    ? () => _startEditingList(list)
                    : () => _navigateToList(list)),
            child: Container(
              height: calculatedHeight,
              padding: EdgeInsets.symmetric(
                  horizontal: 20, vertical: verticalPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Colored accent bar so the list's color is visible even
                  // without picking a Material icon.
                  Container(
                    width: 4,
                    height: 28,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: buildListIcon(
                      emoji: list.iconEmoji,
                      codePoint: list.iconCodePoint,
                      color: accent,
                      size: 24,
                    ),
                  ),
                  Expanded(
                    child: isBeingEdited
                        ? TextField(
                            controller: _listEditController,
                            focusNode: _listFocusNode,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => _saveListEdit(list),
                          )
                        : Text(
                            list.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: customTheme.taskTextColor,
                            ),
                          ),
                  ),
                  if (isBeingEdited)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, size: 20),
                          color: customTheme.secondaryColor,
                          tooltip: 'Save changes',
                          onPressed: () => _saveListEdit(list),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          color: theme.colorScheme.error,
                          tooltip: 'Cancel editing',
                          onPressed: _cancelListEdit,
                        ),
                      ],
                    )
                  else if (_isEditMode)
                    IconButton(
                      icon: Icon(Icons.edit,
                          size: 20, color: theme.iconTheme.color),
                      tooltip: 'Rename list',
                      onPressed: () => _startEditingList(list),
                    )
                  else ...[
                    if (count > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.drag_handle,
                          color: theme.hintColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: theme.dividerColor, thickness: 1),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool expanded;
  final VoidCallback onTap;
  final ThemeData theme;
  final CustomTheme customTheme;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.expanded,
    required this.onTap,
    required this.theme,
    required this.customTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: customTheme.inputAreaColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                color: customTheme.secondaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: customTheme.taskTextColor,
                  shadows: const [
                    Shadow(
                      color: Color(0x66000000),
                      offset: Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '($count)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: customTheme.taskTextColor.withValues(alpha: 0.65),
                  shadows: const [
                    Shadow(
                      color: Color(0x66000000),
                      offset: Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
