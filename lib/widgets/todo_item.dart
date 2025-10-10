import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../providers/settings_notifier.dart';

class TodoItem extends StatelessWidget {
  final Task task;
  final int index;
  final VoidCallback onTapped;

  const TodoItem({
    super.key,
    required this.task,
    required this.index,
    required this.onTapped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final customTheme = settings.currentTheme;

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
                    child: Text(
                      task.text,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17),
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
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

