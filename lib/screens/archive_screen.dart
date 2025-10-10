import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shutter/models/archived_task.dart';
import 'package:shutter/providers/settings_notifier.dart';

class ArchiveScreen extends StatefulWidget {
  final List<ArchivedTask> archivedTodos;
  final Function(ArchivedTask) onRestore;
  final VoidCallback onClear;
  final double taskHeight;

  const ArchiveScreen({
    super.key,
    required this.archivedTodos,
    required this.onRestore,
    required this.onClear,
    required this.taskHeight,
  });

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  // --- FIX: A local, mutable copy of the list to ensure the UI updates instantly ---
  late List<ArchivedTask> _localArchivedTodos;

  @override
  void initState() {
    super.initState();
    // Initialize the local list with the data passed from the TodoScreen
    _localArchivedTodos = List.from(widget.archivedTodos);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived Tasks'),
        actions: [
          // --- FIX: Check the local list to decide if the button should be shown ---
          if (_localArchivedTodos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: 'Clear Archive Manually',
              onPressed: () {
                HapticFeedback.mediumImpact();
                // Call the original onClear callback to update the main screen's state
                widget.onClear();
                // Also clear the local list and update this screen's UI instantly
                setState(() {
                  _localArchivedTodos.clear();
                });
              },
            ),
        ],
      ),
      // --- FIX: Check the local list to show the empty message ---
      body: _localArchivedTodos.isEmpty
          ? Center(child: Text('The archive is empty.', style: theme.textTheme.bodyMedium?.copyWith(fontSize: 18)))
          : ListView.builder(
              // --- FIX: Use the local list's length ---
              itemCount: _localArchivedTodos.length,
              itemBuilder: (context, index) {
                // --- FIX: Get the task from the local list ---
                final archivedTask = _localArchivedTodos[index];
                return Column(
                  children: [
                    Material(
                      color: theme.cardColor.withOpacity(0.7),
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          // Call the callback to restore the task on the main screen
                          widget.onRestore(archivedTask);
                          // --- FIX: Remove the task from the local list and update UI ---
                          setState(() {
                            _localArchivedTodos.removeAt(index);
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: settings.taskHeight,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  archivedTask.text,
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: (theme.textTheme.bodyMedium?.color ?? Colors.black).withOpacity(0.6),
                                    decoration: TextDecoration.lineThrough,
                                  ),
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
              },
            ),
    );
  }
}

