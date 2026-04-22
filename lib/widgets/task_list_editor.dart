import 'package:flutter/material.dart';
import '../utils/haptics.dart';

import '../models/custom_theme.dart';
import '../models/task.dart';
import 'animating_todo_item.dart';
import 'todo_item.dart';

/// Bundles the shared callbacks + UI state every task-list editor needs.
/// Both the sliver variant (home Tasks section) and the full-screen variant
/// (list detail) render identically through a single internal item builder —
/// so any future change to item layout, edit mode, or animation lives in one
/// place.
class TaskListEditorController {
  final List<Task> tasks;
  final Set<String> completingTaskIds;
  final bool isEditMode;
  final Task? taskBeingEdited;
  final TextEditingController editTextController;
  final FocusNode focusNode;

  final void Function(Task task) onCompleteTask;
  final Future<void> Function(Task task) onSetReminder;
  final void Function(Task task) onClearReminder;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(Task task) onStartEditing;
  final VoidCallback onSaveEdit;
  final VoidCallback onCancelEdit;
  final void Function(String taskId) onAnimationEnd;
  final void Function(Task task)? onLongPress;

  /// If set, both the completion-animation and static item render with this
  /// theme instead of the app-wide global theme.
  final CustomTheme? themeOverride;

  const TaskListEditorController({
    required this.tasks,
    required this.completingTaskIds,
    required this.isEditMode,
    required this.taskBeingEdited,
    required this.editTextController,
    required this.focusNode,
    required this.onCompleteTask,
    required this.onSetReminder,
    required this.onClearReminder,
    required this.onReorder,
    required this.onStartEditing,
    required this.onSaveEdit,
    required this.onCancelEdit,
    required this.onAnimationEnd,
    this.onLongPress,
    this.themeOverride,
  });

  Widget buildItem(BuildContext context, int index, {String keyPrefix = 'task'}) {
    final task = tasks[index];
    if (completingTaskIds.contains(task.id)) {
      return AnimatingTodoItem(
        key: ValueKey('$keyPrefix-anim-${task.id}'),
        task: task,
        hasReminder: task.reminderDateTime != null,
        onAnimationEnd: () => onAnimationEnd(task.id),
        themeOverride: themeOverride,
      );
    }
    final isBeingEdited = taskBeingEdited?.id == task.id;
    return TodoItem(
      key: ValueKey('$keyPrefix-${task.id}'),
      task: task,
      index: index,
      onTapped: () => onCompleteTask(task),
      onSetReminder: () => onSetReminder(task),
      onClearReminder:
          task.reminderDateTime != null ? () => onClearReminder(task) : null,
      onLongPress:
          onLongPress != null ? () => onLongPress!(task) : null,
      isEditMode: isEditMode,
      isBeingEdited: isBeingEdited,
      onStartEditing: () => onStartEditing(task),
      onSaveEdit: onSaveEdit,
      onCancelEdit: onCancelEdit,
      editTextController: editTextController,
      focusNode: focusNode,
      themeOverride: themeOverride,
    );
  }
}

/// Sliver-based editor for use inside CustomScrollView (home Tasks section).
/// Produces a single SliverReorderableList. Host owns scroll context.
class TaskListEditorSliver extends StatelessWidget {
  final TaskListEditorController controller;
  final String keyPrefix;

  const TaskListEditorSliver({
    super.key,
    required this.controller,
    this.keyPrefix = 'task',
  });

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: controller.tasks.length,
      onReorderStart: (_) => Haptics.medium(),
      onReorder: (oldIndex, newIndex) {
        if (controller.isEditMode) return;
        Haptics.light();
        controller.onReorder(oldIndex, newIndex);
      },
      itemBuilder: (context, index) =>
          controller.buildItem(context, index, keyPrefix: keyPrefix),
    );
  }
}

/// Full-screen editor used by ListDetailScreen. Swaps between a reorderable
/// list (normal mode) and a flat list (edit mode) — drag-reorder is disabled
/// while the user is editing task text.
class TaskListEditor extends StatelessWidget {
  final TaskListEditorController controller;
  final EdgeInsets padding;
  final String keyPrefix;

  const TaskListEditor({
    super.key,
    required this.controller,
    this.padding = const EdgeInsets.only(bottom: 80),
    this.keyPrefix = 'task',
  });

  @override
  Widget build(BuildContext context) {
    if (controller.isEditMode) {
      return ListView.builder(
        padding: padding,
        itemCount: controller.tasks.length,
        itemBuilder: (context, index) {
          if (index >= controller.tasks.length) return const SizedBox.shrink();
          return controller.buildItem(context, index, keyPrefix: keyPrefix);
        },
      );
    }
    return ReorderableListView.builder(
      padding: padding,
      buildDefaultDragHandles: false,
      itemCount: controller.tasks.length,
      onReorderStart: (_) => Haptics.medium(),
      onReorder: (oldIndex, newIndex) {
        Haptics.light();
        if (newIndex > oldIndex) newIndex -= 1;
        controller.onReorder(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        if (index >= controller.tasks.length) return const SizedBox.shrink();
        return controller.buildItem(context, index, keyPrefix: keyPrefix);
      },
    );
  }
}

/// Shared bottom input field for adding a new task. Respects keyboard inset
/// + safe area, matches the themed outline used across screens.
class TaskInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final CustomTheme customTheme;
  final String hintText;

  const TaskInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.customTheme,
    this.hintText = 'Add a new task...',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final double safeAreaBottom = MediaQuery.of(context).padding.bottom;
    const double verticalBuffer = 12.0;
    final double bottomPadding = keyboardHeight > 0
        ? keyboardHeight + verticalBuffer
        : safeAreaBottom + verticalBuffer;

    return Material(
      color: customTheme.inputAreaColor,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: verticalBuffer,
          bottom: bottomPadding,
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: theme.textTheme.bodyMedium,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: hintText,
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
