// Repetition cadence for recurring reminders. null on a Task = one-shot.
enum RepeatInterval {
  daily,
  weekly,
  monthly;

  String get label {
    switch (this) {
      case RepeatInterval.daily:
        return 'Daily';
      case RepeatInterval.weekly:
        return 'Weekly';
      case RepeatInterval.monthly:
        return 'Monthly';
    }
  }

  // Approximate next-occurrence offset used by NotificationService.
  // Monthly uses 30 days; month-boundary drift is acceptable for reminder cadence.
  Duration get duration {
    switch (this) {
      case RepeatInterval.daily:
        return const Duration(days: 1);
      case RepeatInterval.weekly:
        return const Duration(days: 7);
      case RepeatInterval.monthly:
        return const Duration(days: 30);
    }
  }

  static RepeatInterval? fromName(String? name) {
    if (name == null) return null;
    for (final v in RepeatInterval.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
