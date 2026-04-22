import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shutter/models/archived_task.dart';
import 'package:shutter/models/repeat_interval.dart' as model;
import 'package:shutter/models/task.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const String _actionMarkComplete = 'MARK_COMPLETED';

const String _channelId = 'shutter_reminders_v2';
const String _channelName = 'Task Reminders';
const String _channelDescription = 'Reminders for your tasks';

/// Shared AndroidNotificationDetails used by both foreground and background
/// scheduling paths. Keeping this at top level means the background isolate
/// can schedule follow-up reminders without touching the NotificationService
/// singleton (which isn't available in the bg isolate).
NotificationDetails _sharedNotificationDetails() {
  return const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('ding'),
      enableVibration: true,
      icon: 'ic_stat_reminder',
      actions: [
        AndroidNotificationAction(
          _actionMarkComplete,
          'Mark Complete',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    ),
  );
}

/// Name used to register the foreground isolate's ReceivePort so the
/// background isolate can find and message it via IsolateNameServer.
const String kTaskCompletedPort = 'shutter_task_completed';

class _OriginSnapshot {
  final String name;
  final int? color;
  const _OriginSnapshot(this.name, this.color);
}

// Reads `taskLists` JSON from prefs and returns the origin snapshot for the
// given containerId ("root" or a list UUID). Falls back to sensible defaults
// when the list is missing or prefs are empty — safe for background isolate
// use where we can't rely on in-memory state.
_OriginSnapshot _lookupOrigin(SharedPreferences prefs, String containerId) {
  if (containerId == 'root') return const _OriginSnapshot('Root', null);
  final raw = prefs.getString('taskLists');
  if (raw == null) return _OriginSnapshot(containerId, null);
  try {
    final decoded = json.decode(raw) as List;
    for (final entry in decoded) {
      final map = entry as Map<String, dynamic>;
      if (map['id'] == containerId) {
        return _OriginSnapshot(
          map['name'] as String? ?? containerId,
          map['color'] as int?,
        );
      }
    }
  } catch (_) {
    // Fall through to default.
  }
  return _OriginSnapshot(containerId, null);
}

/// Background isolate handler — called when the app is in background/killed
/// and the user taps "Mark Complete" on a notification.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (r.actionId == _actionMarkComplete && r.payload != null) {
    await _handleMarkComplete(r.payload!, r.id);
  }
}

/// Persists the completion to SharedPreferences and notifies the foreground
/// isolate (if it's running) via IsolateNameServer.
///
/// Recurring tasks (repeat != null) are NOT archived on Mark Complete — their
/// reminderDateTime is advanced by `repeat.duration` and a fresh notification
/// is scheduled so the cadence continues even while the app is killed.
Future<void> _handleMarkComplete(String payload, int? notificationId) async {
  try {
    final decoded = json.decode(payload);
    final String taskId = decoded['id'] as String;
    final String taskText = decoded['text'] as String;
    final String listId = decoded['listId'] as String;

    final todosKey = 'todos_$listId';
    final archivedKey = 'archivedTodos_$listId';

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final List<Task> todos = (prefs.getStringList(todosKey) ?? [])
        .map((s) => Task.fromJson(json.decode(s)))
        .toList();

    final taskIndex = todos.indexWhere((t) => t.id == taskId);
    final Task? existing = taskIndex == -1 ? null : todos[taskIndex];
    final model.RepeatInterval? repeat = existing?.repeat;

    if (repeat != null && existing != null) {
      // Recurring path: advance the reminder, keep the task active, schedule
      // the next notification from this isolate.
      final nextFire = DateTime.now().add(repeat.duration);
      final advanced = Task(
        id: existing.id,
        text: existing.text,
        reminderDateTime: nextFire,
        repeat: repeat,
      );
      todos[taskIndex] = advanced;
      await prefs.setStringList(
          todosKey, todos.map((t) => json.encode(t.toJson())).toList());

      await _scheduleReminderFromIsolate(
        task: advanced,
        scheduledTime: nextFire,
        listId: listId,
      );

      final SendPort? fgPort =
          IsolateNameServer.lookupPortByName(kTaskCompletedPort);
      fgPort?.send({
        'taskId': taskId,
        'listId': listId,
        'recurring': 'true',
      });
      return;
    }

    // One-shot path: remove from active, archive.
    final List<ArchivedTask> archived =
        (prefs.getStringList(archivedKey) ?? [])
            .map((s) => ArchivedTask.fromJson(json.decode(s)))
            .toList();

    if (taskIndex != -1) {
      todos.removeAt(taskIndex);
      await prefs.setStringList(
          todosKey, todos.map((t) => json.encode(t.toJson())).toList());
    }

    final alreadyArchived = archived.any((t) =>
        t.text == taskText &&
        (DateTime.now().millisecondsSinceEpoch - t.archivedAtTimestamp).abs() <
            5000);
    if (!alreadyArchived) {
      final origin = _lookupOrigin(prefs, listId);
      archived.insert(
          0,
          ArchivedTask.createNew(
            text: taskText,
            originId: listId,
            originNameSnapshot: origin.name,
            originColorSnapshot: origin.color,
          ));
      await prefs.setStringList(
          archivedKey, archived.map((t) => json.encode(t.toJson())).toList());
    }

    // Notify the foreground isolate immediately if the app is running.
    // IsolateNameServer lets a background isolate look up a SendPort that the
    // main isolate registered — this is the only safe cross-isolate channel
    // in Flutter without platform channels.
    final SendPort? foregroundPort =
        IsolateNameServer.lookupPortByName(kTaskCompletedPort);
    foregroundPort?.send({'taskId': taskId, 'listId': listId});
  } catch (e, st) {
    debugPrint('_handleMarkComplete error: $e\n$st');
  }
}

/// Schedules a reminder from any isolate. The plugin needs its own init in
/// the background isolate; the Android channel is already created on-device
/// so init is cheap and idempotent. Timezone data must be initialized here
/// too since the bg isolate doesn't share state with the main isolate.
Future<void> _scheduleReminderFromIsolate({
  required Task task,
  required DateTime scheduledTime,
  required String listId,
}) async {
  try {
    tz.initializeTimeZones();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'),
      ),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final payload = json.encode({
      'id': task.id,
      'text': task.text,
      'listId': listId,
    });
    final scheduled = tz.TZDateTime.from(scheduledTime.toUtc(), tz.UTC);

    await plugin.zonedSchedule(
      NotificationService.generateNotificationId(task.id),
      task.text,
      '',
      scheduled,
      _sharedNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  } catch (e, st) {
    debugPrint('_scheduleReminderFromIsolate error: $e\n$st');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // ReceivePort that lives in the main (foreground) isolate.
  // Background isolate finds it via IsolateNameServer and sends task completion
  // events here regardless of whether the app is foreground, background, or
  // was just resumed from a killed state.
  ReceivePort? _receivePort;
  final StreamController<Map<String, String>> _completedStream =
      StreamController.broadcast();
  Stream<Map<String, String>> get taskCompletedStream =>
      _completedStream.stream;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      tz.initializeTimeZones();

      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_reminder'),
        ),
        onDidReceiveNotificationResponse: _onForegroundResponse,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('ding'),
            enableVibration: true,
          ));

      _setupIsolatePort();
      _isInitialized = true;
    } catch (e) {
      debugPrint('NotificationService.init error: $e');
      rethrow;
    }
  }

  /// Registers a ReceivePort in the main isolate and wires it to the stream.
  /// Any isolate (including background notification handlers) can find this
  /// port by name and send completion events to it.
  void _setupIsolatePort() {
    _receivePort?.close();
    IsolateNameServer.removePortNameMapping(kTaskCompletedPort);

    _receivePort = ReceivePort();
    IsolateNameServer.registerPortWithName(
        _receivePort!.sendPort, kTaskCompletedPort);

    _receivePort!.listen((message) {
      if (message is Map) {
        final taskId = message['taskId'] as String?;
        final listId = message['listId'] as String?;
        if (taskId != null && listId != null) {
          _completedStream.add({'taskId': taskId, 'listId': listId});
        }
      }
    });
  }

  /// Request POST_NOTIFICATIONS permission on Android 13+.
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Called when the app is in the foreground and user taps the notification
  /// body (not an action button). Action buttons with showsUserInterface:false
  /// always route to notificationTapBackground regardless of app state.
  void _onForegroundResponse(NotificationResponse r) {
    if (r.payload == null) return;
    try {
      json.decode(r.payload!);
      // Notification body tap while foreground — complete if user tapped body
      if (r.actionId == null) return;
    } catch (e) {
      debugPrint('_onForegroundResponse payload error: $e');
    }
  }

  Future<void> scheduleNotification({
    required Task task,
    required DateTime scheduledTime,
    required String listId,
  }) async {
    if (!_isInitialized) return;

    final payload = json.encode({
      'id': task.id,
      'text': task.text,
      'listId': listId,
    });

    final scheduled = tz.TZDateTime.from(scheduledTime.toUtc(), tz.UTC);

    try {
      await _plugin.zonedSchedule(
        generateNotificationId(task.id),
        task.text,
        '',
        scheduled,
        _sharedNotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      debugPrint('scheduleNotification error: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('cancelNotification error: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('cancelAllNotifications error: $e');
    }
  }

  static int generateNotificationId(String taskId) {
    return taskId.hashCode.abs() % 2147483647;
  }

  void dispose() {
    _receivePort?.close();
    IsolateNameServer.removePortNameMapping(kTaskCompletedPort);
    _completedStream.close();
  }
}
