import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/list.dart';
import '../models/custom_theme.dart';
import '../providers/settings_notifier.dart';
import 'list_detail_screen.dart';
import 'settings_screen.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  // Local state for editing the name of a list
  TaskList? _listBeingEdited;
  final TextEditingController _listEditController = TextEditingController();
  final FocusNode _listEditFocusNode = FocusNode();
  String? _listIdPendingDeletion;

  @override
  void dispose() {
    _listEditController.dispose();
    _listEditFocusNode.dispose();
    super.dispose();
  }

  void _navigateToList(TaskList list) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListDetailScreen(list: list),
    ));
  }

  void _navigateToSettings() async {
    HapticFeedback.selectionClick();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _createNewList() {
    HapticFeedback.lightImpact();
    // Create a temporary list model to start the editing flow
    final newList = TaskList.createNew(name: 'New List');
    _listEditController.text = newList.name;
    
    // Immediately add to notifier to assign an ID and show it in the UI
    Provider.of<SettingsNotifier>(context, listen: false).addTaskList(newList);

    // Start editing the new list's name
    setState(() {
      _listBeingEdited = newList;
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(_listEditFocusNode);
      }
    });
  }

  void _saveListEdit() {
    if (_listBeingEdited != null && _listEditController.text.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      final settings = Provider.of<SettingsNotifier>(context, listen: false);
      
      final updatedList = _listBeingEdited!.copyWith(name: _listEditController.text.trim());
      settings.updateTaskList(updatedList);
    }
    _exitListEditMode();
  }

  void _exitListEditMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _listBeingEdited = null;
      _listIdPendingDeletion = null;
    });
    _listEditFocusNode.unfocus();
  }

  void _promptDeleteList(String listId) {
    HapticFeedback.selectionClick();
    setState(() {
      _listIdPendingDeletion = listId;
    });
  }

  void _confirmDeleteList(String listId) {
    HapticFeedback.mediumImpact();
    Provider.of<SettingsNotifier>(context, listen: false).deleteTaskList(listId);
    setState(() {
      _listIdPendingDeletion = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsNotifier>(context);
    final theme = Theme.of(context);
    final customTheme = settings.currentTheme;
    final backgroundImage = customTheme.backgroundImagePath;
    
    // 1. Calculate the standard task height for list items
    const double standardBaseHeight = 72.0;
    final double calculatedHeight = standardBaseHeight * settings.taskHeight;
    // Calculate content padding to center the list tile vertically (similar to TodoItem)
    const double contentHeight = 25.0; // Rough estimate for single line text height + margin
    final double verticalPadding = ((calculatedHeight - contentHeight) / 2).clamp(10.0, 36.0);

    final bool isListBeingEdited = _listBeingEdited != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shutter'),
        leading: IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: _navigateToSettings),
        actions: [
          // Archive icon is replaced by the "Add List" button on the main screen
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add new list',
            onPressed: isListBeingEdited ? null : _createNewList,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: _exitListEditMode, // Tapping background cancels editing
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
          child: ListView.builder(
            itemCount: settings.taskLists.length,
            itemBuilder: (context, index) {
              final list = settings.taskLists[index];
              final isBeingEdited = _listBeingEdited?.id == list.id;
              final isPendingDeletion = _listIdPendingDeletion == list.id;
              final isLastList = settings.taskLists.length == 1;

              return Column(
                children: [
                  Material(
                    color: customTheme.taskBackgroundColor,
                    child: InkWell(
                      onTap: isBeingEdited || isPendingDeletion ? null : () => _navigateToList(list),
                      child: Container(
                        // 2. Apply the calculated height and padding to the list item
                        height: calculatedHeight,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: verticalPadding),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 3. Leading Icon
                            Padding(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: Icon(
                                Icons.folder_outlined,
                                color: customTheme.secondaryColor,
                                size: 24,
                              ),
                            ),
                            
                            // 4. Title (Editable or Text)
                            Expanded(
                              child: isBeingEdited
                                  ? TextField(
                                      controller: _listEditController,
                                      focusNode: _listEditFocusNode,
                                      onSubmitted: (_) => _saveListEdit(),
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    )
                                  : Text(
                                      list.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                            ),
                            
                            // 5. Trailing Action Buttons
                            isPendingDeletion
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Confirm Delete
                                      IconButton(
                                        icon: Icon(Icons.check, color: theme.colorScheme.error),
                                        tooltip: 'Confirm Delete',
                                        onPressed: () => _confirmDeleteList(list.id),
                                      ),
                                      // Cancel Delete
                                      IconButton(
                                        icon: Icon(Icons.close, color: customTheme.secondaryColor),
                                        tooltip: 'Cancel Delete',
                                        onPressed: _exitListEditMode,
                                      ),
                                    ],
                                  )
                                : isBeingEdited
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Save Edit
                                          IconButton(
                                            icon: Icon(Icons.check, color: customTheme.secondaryColor),
                                            tooltip: 'Save Name',
                                            onPressed: _saveListEdit,
                                          ),
                                          // Cancel Edit
                                          IconButton(
                                            icon: Icon(Icons.close, color: theme.colorScheme.error),
                                            tooltip: 'Cancel Edit',
                                            onPressed: _exitListEditMode,
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Edit Button
                                          IconButton(
                                            icon: Icon(Icons.edit, color: theme.iconTheme.color),
                                            tooltip: 'Edit List Name',
                                            onPressed: () {
                                              _listEditController.text = list.name;
                                              setState(() => _listBeingEdited = list);
                                              Future.delayed(Duration.zero, () => _listEditFocusNode.requestFocus());
                                            },
                                          ),
                                          // Delete Button (disabled for the last list)
                                          if (!isLastList)
                                            IconButton(
                                              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                                              tooltip: 'Delete List',
                                              onPressed: () => _promptDeleteList(list.id),
                                            ),
                                        ],
                                      ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: theme.dividerColor, thickness: 1),
                ],
              );
            },
          ),
        ),
      ),
      bottomSheet: isListBeingEdited 
        ? null 
        : _buildTaskInput(theme, customTheme), 
    );
  }

  Widget _buildTaskInput(ThemeData theme, CustomTheme customTheme) {
    // Re-purposing the old input field to add tasks directly to the first list.
    final List<TaskList> lists = Provider.of<SettingsNotifier>(context).taskLists;
    if (lists.isEmpty) return const SizedBox.shrink();

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
          controller: _listEditController, // Using the list edit controller for simplicity
          focusNode: _listEditFocusNode, // Using the list edit focus node
          style: theme.textTheme.bodyMedium,
          onSubmitted: (_) {
            if (lists.isNotEmpty) {
               _navigateToList(lists.first);
            }
          },
          decoration: InputDecoration(
            hintText: 'Select a list above to add a task...',
            
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
          readOnly: true, // Make it read-only on the main screen. The user taps to navigate.
          onTap: () {
            if (lists.isNotEmpty) {
               _navigateToList(lists.first);
            }
          },
        ),
      ),
    );
  }
}