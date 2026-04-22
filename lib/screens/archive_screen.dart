import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/haptics.dart';
import 'package:provider/provider.dart';

import '../models/archived_task.dart';
import '../providers/settings_notifier.dart';

/// Archive view. Two modes:
/// - Per-container: caller owns the list + callbacks. Used from list detail.
/// - Global: pulls from `SettingsNotifier.globalArchive()` and spans every
///   origin (including deleted lists). Opened from the home app bar.
class ArchiveScreen extends StatefulWidget {
  final bool global;

  // Per-container fields — unused in global mode.
  final List<ArchivedTask>? archivedTodos;
  final Function(ArchivedTask)? onRestore;
  final VoidCallback? onClear;

  const ArchiveScreen({
    super.key,
    required this.archivedTodos,
    required this.onRestore,
    required this.onClear,
  }) : global = false;

  const ArchiveScreen.global({super.key})
      : global = true,
        archivedTodos = null,
        onRestore = null,
        onClear = null;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

// Filter dropdown value. `_FilterAll` / `_FilterDeleted` are sentinel
// containerIds; 'root' and list UUIDs map to real origins.
const String _filterAll = '__all__';
const String _filterDeleted = '__deleted__';

class _ArchiveScreenState extends State<ArchiveScreen> {
  // Per-container mode mirrors the list into local state so optimistic removes
  // on restore feel instant without waiting for the Provider round-trip.
  late List<ArchivedTask> _localArchivedTodos;

  // Global-mode filter.
  String _filter = _filterAll;

  @override
  void initState() {
    super.initState();
    _localArchivedTodos =
        widget.global ? <ArchivedTask>[] : List.from(widget.archivedTodos!);
  }

  @override
  Widget build(BuildContext context) {
    return widget.global ? _buildGlobal(context) : _buildPerContainer(context);
  }

  // --- Per-container mode -------------------------------------------------

  Widget _buildPerContainer(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context);
    final double calculatedHeight = 72.0 * settings.taskHeight;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Archived Tasks'),
        actions: [
          if (_localArchivedTodos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: 'Clear archive',
              onPressed: () {
                Haptics.medium();
                widget.onClear!();
                setState(() => _localArchivedTodos.clear());
              },
            ),
        ],
      ),
      body: _localArchivedTodos.isEmpty
          ? Center(
              child: Text(
                'The archive is empty.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: _localArchivedTodos.length,
              itemBuilder: (context, index) {
                final entry = _localArchivedTodos[index];
                return _ArchiveRow(
                  entry: entry,
                  height: calculatedHeight,
                  showOriginChip: false,
                  originDeleted: false,
                  onTap: () {
                    Haptics.light();
                    widget.onRestore!(entry);
                    setState(() => _localArchivedTodos.removeAt(index));
                  },
                  onLongPress: null,
                );
              },
            ),
    );
  }

  // --- Global mode --------------------------------------------------------

  Widget _buildGlobal(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context);
    final double calculatedHeight = 72.0 * settings.taskHeight;

    final all = settings.globalArchive();
    final filtered = _applyFilter(all, settings);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('All Archive'),
        actions: [
          if (all.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: 'Clear archive',
              onPressed: () => _confirmClearGlobal(context, settings),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(context, settings, all),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      all.isEmpty
                          ? 'The archive is empty.'
                          : 'No entries match this filter.',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final originDeleted = entry.originId != 'root' &&
                          !settings.listExists(entry.originId);
                      return _ArchiveRow(
                        entry: entry,
                        height: calculatedHeight,
                        showOriginChip: true,
                        originDeleted: originDeleted,
                        onTap: originDeleted
                            ? null
                            : () async {
                                Haptics.light();
                                await settings
                                    .restoreGlobalArchiveEntry(entry);
                              },
                        onLongPress: originDeleted
                            ? () => _confirmRestoreToRoot(
                                context, settings, entry)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<ArchivedTask> _applyFilter(
    List<ArchivedTask> all,
    SettingsNotifier settings,
  ) {
    switch (_filter) {
      case _filterAll:
        return all;
      case _filterDeleted:
        return all
            .where((e) =>
                e.originId != 'root' && !settings.listExists(e.originId))
            .toList();
      default:
        return all.where((e) => e.originId == _filter).toList();
    }
  }

  Widget _buildFilterBar(
    BuildContext context,
    SettingsNotifier settings,
    List<ArchivedTask> all,
  ) {
    final theme = Theme.of(context);
    final existingLists = settings.taskLists;

    // Only show "Deleted lists" if any deleted-origin entries exist — otherwise
    // the option is dead weight.
    final hasDeletedEntries = all.any(
      (e) => e.originId != 'root' && !settings.listExists(e.originId),
    );

    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: _filterAll, child: Text('All origins')),
      const DropdownMenuItem(value: 'root', child: Text('Root')),
      ...existingLists.map(
        (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
      ),
      if (hasDeletedEntries)
        const DropdownMenuItem(
          value: _filterDeleted,
          child: Text('Deleted lists'),
        ),
    ];

    // If the current filter targets a list that no longer exists (e.g. the
    // user deleted it while on this screen), reset to All silently.
    final validValues = items.map((i) => i.value).toSet();
    if (!validValues.contains(_filter)) {
      _filter = _filterAll;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 20, color: theme.hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _filter,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              items: items,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _filter = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearGlobal(
    BuildContext context,
    SettingsNotifier settings,
  ) async {
    Haptics.medium();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all archive?'),
        content: const Text(
          'This removes every archived task across every list and root. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await settings.clearGlobalArchive();
    }
  }

  Future<void> _confirmRestoreToRoot(
    BuildContext context,
    SettingsNotifier settings,
    ArchivedTask entry,
  ) async {
    Haptics.selection();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore to Root?'),
        content: Text(
          'Origin list "${entry.originNameSnapshot}" was deleted. '
          'Restore this task to Root instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await settings.restoreGlobalArchiveEntry(entry, overrideTargetId: 'root');
    }
  }
}

/// Single row in either archive mode. Keeps presentation in one place so the
/// per-container view never drifts from the global one.
class _ArchiveRow extends StatelessWidget {
  final ArchivedTask entry;
  final double height;
  final bool showOriginChip;
  final bool originDeleted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ArchiveRow({
    required this.entry,
    required this.height,
    required this.showOriginChip,
    required this.originDeleted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor =
        (theme.textTheme.bodyMedium?.color ?? Colors.black).withValues(alpha: 0.6);

    return Column(
      children: [
        Material(
          color: theme.cardColor.withValues(alpha: 0.7),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              constraints: BoxConstraints(minHeight: height),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.text,
                          style: TextStyle(
                            fontSize: 17,
                            color: textColor,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (showOriginChip) ...[
                              _OriginChip(
                                entry: entry,
                                deleted: originDeleted,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _relativeTime(entry.archivedAtTimestamp),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    originDeleted ? Icons.restore_outlined : Icons.restore,
                    color: originDeleted ? theme.disabledColor : theme.hintColor,
                    size: 22,
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

class _OriginChip extends StatelessWidget {
  final ArchivedTask entry;
  final bool deleted;

  const _OriginChip({required this.entry, required this.deleted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = deleted
        ? theme.disabledColor
        : (entry.originColorSnapshot != null
            ? Color(entry.originColorSnapshot!)
            : theme.colorScheme.primary);
    final label = deleted
        ? 'Deleted: ${entry.originNameSnapshot}'
        : entry.originNameSnapshot;
    final fg = ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: deleted ? 0.45 : 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Small-footprint relative timestamp. Switches to absolute date beyond a week
/// so stale entries stay legible without sprawling strings.
String _relativeTime(int millisSinceEpoch) {
  final now = DateTime.now();
  final then = DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch);
  final diff = now.difference(then);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.MMMd().format(then);
}

