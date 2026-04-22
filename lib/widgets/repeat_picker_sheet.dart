import 'package:flutter/material.dart';
import '../utils/haptics.dart';

import '../models/repeat_interval.dart';

/// Result returned by [showRepeatPickerSheet].
///
/// A non-null sheet result is always a deliberate choice by the user.
/// `interval == null` means the user explicitly picked "Never" (one-shot).
/// The sheet returning `null` means the user dismissed — callers should
/// preserve whatever repeat value was already on the task.
class RepeatPickResult {
  final RepeatInterval? interval;
  const RepeatPickResult(this.interval);
}

Future<RepeatPickResult?> showRepeatPickerSheet(
  BuildContext context, {
  RepeatInterval? current,
}) {
  return showModalBottomSheet<RepeatPickResult>(
    context: context,
    isScrollControlled: false,
    showDragHandle: true,
    builder: (_) => _RepeatPickerSheet(current: current),
  );
}

class _RepeatPickerSheet extends StatelessWidget {
  final RepeatInterval? current;
  const _RepeatPickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget tile(String label, RepeatInterval? value) {
      final selected = current == value;
      return ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? theme.colorScheme.primary : theme.hintColor,
        ),
        title: Text(label),
        onTap: () {
          Haptics.selection();
          Navigator.of(context).pop(RepeatPickResult(value));
        },
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Repeats', style: theme.textTheme.titleLarge),
            ),
          ),
          tile('Never', null),
          tile(RepeatInterval.daily.label, RepeatInterval.daily),
          tile(RepeatInterval.weekly.label, RepeatInterval.weekly),
          tile(RepeatInterval.monthly.label, RepeatInterval.monthly),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
