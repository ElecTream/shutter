import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/haptics.dart';

import '../models/list.dart';
import '../providers/settings_notifier.dart';
import 'icon_picker_sheet.dart';

/// Shows the move-to bottom sheet. Resolves to the picked container id
/// ('root' or a list UUID), or null if the user dismissed without picking.
///
/// `excludeContainerId` is the task's current container — rendered as
/// disabled in the tree so the user can't pick it and no-op the move. For a
/// sub-tree move we also want to hide the list itself from its own
/// descendants, but tasks don't nest, so just the single id suffices.
Future<String?> showMoveToSheet(
  BuildContext context, {
  required String excludeContainerId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoveToSheet(excludeContainerId: excludeContainerId),
  );
}

class _MoveToSheet extends StatefulWidget {
  final String excludeContainerId;
  const _MoveToSheet({required this.excludeContainerId});

  @override
  State<_MoveToSheet> createState() => _MoveToSheetState();
}

class _MoveToSheetState extends State<_MoveToSheet> {
  String _query = '';

  /// Flattens all lists into a depth-indexed sequence by walking the tree
  /// depth-first from each top-level root. Depth is only used for visual
  /// indentation; sort order comes from `childrenOf`.
  List<_LeveledList> _flatten(SettingsNotifier settings) {
    final result = <_LeveledList>[];
    void walk(String? parentId, int depth) {
      for (final l in settings.childrenOf(parentId)) {
        result.add(_LeveledList(list: l, depth: depth));
        walk(l.id, depth + 1);
      }
    }
    walk(null, 0);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context);
    final all = _flatten(settings);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final filtered = _query.isEmpty
        ? all
        : all
            .where((e) =>
                e.list.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    // Root shows only when not filtered out (empty query or "root" matches).
    final showRoot =
        _query.isEmpty || 'root'.contains(_query.toLowerCase());

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Move to…', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search lists',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (showRoot)
                    _DestinationTile(
                      label: 'Root',
                      depth: 0,
                      icon: const Icon(Icons.inbox_outlined),
                      accent: theme.colorScheme.primary,
                      disabled: widget.excludeContainerId == 'root',
                      onTap: () => Navigator.of(context).pop('root'),
                    ),
                  ...filtered.map((e) {
                    final accent = e.list.color != null
                        ? Color(e.list.color!)
                        : theme.colorScheme.primary;
                    return _DestinationTile(
                      label: e.list.name,
                      depth: e.depth + 1,
                      icon: buildListIcon(
                        emoji: e.list.iconEmoji,
                        codePoint: e.list.iconCodePoint,
                        color: accent,
                        size: 20,
                      ),
                      accent: accent,
                      disabled: widget.excludeContainerId == e.list.id,
                      onTap: () => Navigator.of(context).pop(e.list.id),
                    );
                  }),
                  if (!showRoot && filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No lists match "$_query"',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeveledList {
  final TaskList list;
  final int depth;
  const _LeveledList({required this.list, required this.depth});
}

class _DestinationTile extends StatelessWidget {
  final String label;
  final int depth;
  final Widget icon;
  final Color accent;
  final bool disabled;
  final VoidCallback onTap;

  const _DestinationTile({
    required this.label,
    required this.depth,
    required this.icon,
    required this.accent,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: disabled
          ? null
          : () {
              Haptics.selection();
              onTap();
            },
      enabled: !disabled,
      contentPadding: EdgeInsets.only(left: 16 + depth * 20.0, right: 16),
      leading: icon,
      title: Text(label, overflow: TextOverflow.ellipsis),
      subtitle: disabled ? const Text('Current location') : null,
      trailing: disabled
          ? Icon(Icons.check, color: theme.hintColor)
          : Icon(Icons.chevron_right, color: accent),
    );
  }
}
