import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../providers/settings_notifier.dart';

class TodoItem extends StatelessWidget {
  final Task task;
  final int index;
  final VoidCallback onTapped;
  final VoidCallback onSetReminder;
  final VoidCallback? onClearReminder;

  // Edit mode properties
  final bool isEditMode;
  final bool isBeingEdited;
  final VoidCallback? onStartEditing;
  final VoidCallback? onSaveEdit;
  final VoidCallback? onCancelEdit;
  final TextEditingController? editTextController;
  final FocusNode? focusNode;

  const TodoItem({
    super.key,
    required this.task,
    required this.index,
    required this.onTapped,
    required this.onSetReminder,
    this.onClearReminder,
    // Edit mode parameters with defaults
    this.isEditMode = false,
    this.isBeingEdited = false,
    this.onStartEditing,
    this.onSaveEdit,
    this.onCancelEdit,
    this.editTextController,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final customTheme = settings.currentTheme;
    final hasReminder = task.reminderDateTime != null;

    // --- STANDARDIZED HEIGHT ---
    const double standardBaseHeight = 72.0; 
    final double calculatedHeight = standardBaseHeight * settings.taskHeight;

    // Determine the vertical padding needed to center the content within the calculated height
    final double contentHeight = hasReminder ? 40.0 : 25.0; // Estimate: Task text line height is ~20, reminder is ~14.
    final double verticalPadding = ((calculatedHeight - contentHeight) / 2).clamp(10.0, 36.0);


    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: customTheme.taskBackgroundColor,
          child: InkWell(
            onTap:
                isBeingEdited ? null : (isEditMode ? onStartEditing : onTapped),
            child: Container(
              height: calculatedHeight, 
              // Removed vertical padding here, letting the inner Row handle vertical centering
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center, // Center the children of this main Row
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isBeingEdited)
                          TextField(
                            controller: editTextController,
                            focusNode: focusNode,
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
                          )
                        else
                          Text(
                            task.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (hasReminder && !isBeingEdited) ...[
                          const SizedBox(height: 2), 
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: customTheme.secondaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat.MMMd()
                                    .add_jm()
                                    .format(task.reminderDateTime!),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  color: customTheme.secondaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // --- Trailing Icons (Corrected Alignment) ---
                  if (isBeingEdited)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, size: 20),
                          color: customTheme.secondaryColor,
                          tooltip: 'Save changes',
                          onPressed: onSaveEdit,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          color: theme.colorScheme.error,
                          tooltip: 'Cancel editing',
                          onPressed: onCancelEdit,
                        ),
                      ],
                    )
                  else if (!isEditMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            hasReminder
                                ? Icons.notifications_off
                                : Icons.notifications_none,
                            size: 20,
                          ),
                          onPressed:
                              hasReminder ? onClearReminder : onSetReminder,
                          tooltip: hasReminder ? 'Clear reminder' : 'Set reminder',
                        ),
                        // Drag handle is wrapped in ReorderableDragStartListener
                        ReorderableDragStartListener(
                          index: index,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {}, 
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Icon(
                                    Icons.drag_handle,
                                    size: 20,
                                    color: theme.iconTheme.color?.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else // Edit mode but not editing this specific task
                    // Show a simple edit button that starts editing
                    IconButton(
                        icon: Icon(Icons.edit, size: 20, color: theme.iconTheme.color),
                        onPressed: onStartEditing,
                    )
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