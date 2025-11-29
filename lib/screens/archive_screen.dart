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
  late List<ArchivedTask> _localArchivedTodos;

  @override
  void initState() {
    super.initState();
    _localArchivedTodos = List.from(widget.archivedTodos);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context, listen: false);

    // --- FIX: Update to match standardized height (72.0 base) ---
    final double calculatedHeight = 72.0 * settings.taskHeight;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived Tasks'),
        actions: [
          if (_localArchivedTodos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: 'Clear Archive Manually',
              onPressed: () {
                HapticFeedback.mediumImpact();
                widget.onClear();
                setState(() {
                  _localArchivedTodos.clear();
                });
              },
            ),
        ],
      ),
      body: _localArchivedTodos.isEmpty
          ? Center(child: Text('The archive is empty.', style: theme.textTheme.bodyMedium?.copyWith(fontSize: 18)))
          : ListView.builder(
              itemCount: _localArchivedTodos.length,
              itemBuilder: (context, index) {
                final archivedTask = _localArchivedTodos[index];
                return Column(
                  children: [
                    Material(
                      color: theme.cardColor.withOpacity(0.7),
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onRestore(archivedTask);
                          setState(() {
                            _localArchivedTodos.removeAt(index);
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            // Center vertically within the calculated height
                            vertical: (calculatedHeight > 24) ? (calculatedHeight - 24) / 2 : 0, 
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