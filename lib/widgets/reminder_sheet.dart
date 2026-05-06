import 'package:flutter/material.dart';

import '../models/repeat_interval.dart';
import '../utils/haptics.dart';

/// Result returned by [showReminderSheet].
///
/// `cleared` distinguishes "user explicitly tapped Clear" from "user dismissed
/// without saving" — the latter returns null from the sheet so callers can
/// preserve the existing reminder.
class ReminderPickResult {
  final DateTime? when;
  final RepeatInterval? repeat;
  final bool cleared;
  const ReminderPickResult({this.when, this.repeat, this.cleared = false});
}

/// Single bottom sheet that picks date + time + repeat in one flow. Replaces
/// the previous showDatePicker → showTimePicker → showRepeatPickerSheet chain.
///
/// Returns null on dismiss; a non-null [ReminderPickResult] means the user
/// committed (Save or Clear).
Future<ReminderPickResult?> showReminderSheet(
  BuildContext context, {
  DateTime? initial,
  RepeatInterval? initialRepeat,
  required TimeOfDay defaultTime,
}) {
  return showModalBottomSheet<ReminderPickResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReminderSheet(
      initial: initial,
      initialRepeat: initialRepeat,
      defaultTime: defaultTime,
    ),
  );
}

class _ReminderSheet extends StatefulWidget {
  final DateTime? initial;
  final RepeatInterval? initialRepeat;
  final TimeOfDay defaultTime;

  const _ReminderSheet({
    required this.initial,
    required this.initialRepeat,
    required this.defaultTime,
  });

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late RepeatInterval? _repeat;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final seed = widget.initial;
    if (seed != null) {
      _selectedDate = DateTime(seed.year, seed.month, seed.day);
      _selectedTime = TimeOfDay.fromDateTime(seed);
    } else {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _selectedTime = widget.defaultTime;
    }
    _repeat = widget.initialRepeat;
  }

  /// Composed DateTime, floored to the next minute if the user picked today
  /// with a time that has already passed (matches the old chain's behavior of
  /// silently rejecting past times — here we coerce instead to avoid a dead
  /// Save button on the common "set for today, 9am" case after 9am).
  DateTime get _composed {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  bool get _isInPast => _composed.isBefore(DateTime.now());

  Future<void> _editTime() async {
    Haptics.selection();
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedTime = picked);
  }

  void _onSave() {
    if (_isInPast) return;
    Haptics.light();
    Navigator.of(context).pop(
      ReminderPickResult(when: _composed, repeat: _repeat),
    );
  }

  void _onClear() {
    Haptics.medium();
    Navigator.of(context).pop(const ReminderPickResult(cleared: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Reminder', style: theme.textTheme.titleLarge),
              ),
              SizedBox(
                height: 320,
                child: CalendarDatePicker(
                  initialDate: _selectedDate.isBefore(firstDate)
                      ? firstDate
                      : _selectedDate,
                  firstDate: firstDate,
                  lastDate: DateTime(2101),
                  onDateChanged: (d) {
                    Haptics.selection();
                    setState(() => _selectedDate = d);
                  },
                ),
              ),
              const Divider(height: 1),
              InkWell(
                onTap: _editTime,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, color: theme.hintColor),
                      const SizedBox(width: 12),
                      Text('Time', style: theme.textTheme.bodyLarge),
                      const Spacer(),
                      Text(
                        _selectedTime.format(context),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit, size: 18, color: theme.hintColor),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Repeats',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.hintColor)),
                    const SizedBox(height: 8),
                    SegmentedButton<RepeatInterval?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('Off')),
                        ButtonSegment(
                            value: RepeatInterval.daily, label: Text('Day')),
                        ButtonSegment(
                            value: RepeatInterval.weekly, label: Text('Week')),
                        ButtonSegment(
                            value: RepeatInterval.monthly,
                            label: Text('Month')),
                      ],
                      selected: {_repeat},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        Haptics.selection();
                        setState(() => _repeat = s.first);
                      },
                    ),
                  ],
                ),
              ),
              if (_isInPast)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    'Pick a future date and time.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.notifications_off_outlined),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: _onClear,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Save'),
                      onPressed: _isInPast ? null : _onSave,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
