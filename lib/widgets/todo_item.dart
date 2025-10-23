import 'package:flutter/material.dart';
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

  const TodoItem({
    super.key,
    required this.task,
    required this.index,
    required this.onTapped,
    required this.onSetReminder,
    this.onClearReminder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final customTheme = settings.currentTheme;
    final hasReminder = task.reminderDateTime != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: customTheme.taskBackgroundColor,
          child: InkWell(
            onTap: onTapped,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: settings.taskHeight,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (hasReminder) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: customTheme.secondaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat.MMMd().add_jm().format(task.reminderDateTime!),
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
                  if (hasReminder)
                    IconButton(
                      icon: const Icon(Icons.notifications_off, size: 20),
                      color: theme.colorScheme.error,
                      tooltip: 'Clear reminder',
                      onPressed: onClearReminder,
                    ),
                  IconButton(
                    icon: Icon(
                      hasReminder ? Icons.notifications_active : Icons.notifications_none,
                      size: 20,
                    ),
                    color: hasReminder ? customTheme.secondaryColor : theme.iconTheme.color?.withOpacity(0.6),
                    tooltip: hasReminder ? 'Change reminder' : 'Set reminder',
                    onPressed: onSetReminder,
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle,
                      color: theme.iconTheme.color?.withOpacity(0.5),
                    ),
                  ),
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