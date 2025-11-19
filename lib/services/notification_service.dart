import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shutter/models/archived_task.dart';
import 'package:shutter/models/task.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Payload key for the action
const String _actionMarkCompleted = 'MARK_COMPLETED';

/// Top-level handler for notification actions when the app is terminated.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  if (notificationResponse.actionId == _actionMarkCompleted &&
      notificationResponse.payload != null) {
    await _handleMarkCompletedAction(notificationResponse.payload!);
  }
}

/// Shared handler for mark completed action
Future<void> _handleMarkCompletedAction(String payload) async {
  try {
    final decodedPayload = json.decode(payload);
    final String taskId = decodedPayload['id'];
    final String taskText = decodedPayload['text'];

    final prefs = await SharedPreferences.getInstance();

    final todosData = prefs.getStringList('todos') ?? [];
    final archivedData = prefs.getStringList('archivedTodos') ?? [];

    final List<Task> todos = todosData
        .map((jsonString) => Task.fromJson(json.decode(jsonString)))
        .toList();
    final List<ArchivedTask> archivedTodos = archivedData
        .map((jsonData) => ArchivedTask.fromJson(json.decode(jsonData)))
        .toList();

    final taskIndex = todos.indexWhere((task) => task.id == taskId);
    bool wasCompleted = false;

    if (taskIndex != -1) {
      todos.removeAt(taskIndex);
      wasCompleted = true;
    }

    final newArchivedTask = ArchivedTask(
      text: taskText,
      archivedAtTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    archivedTodos.insert(0, newArchivedTask);

    if (wasCompleted) {
      final List<String> todosJson =
          todos.map((task) => json.encode(task.toJson())).toList();
      await prefs.setStringList('todos', todosJson);
    }

    final List<String> archivedJson =
        archivedTodos.map((task) => json.encode(task.toJson())).toList();
    await prefs.setStringList('archivedTodos', archivedJson);
  } catch (e) {
    // Handle error
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _channelId = 'shutter_reminders';
  static const String _channelName = 'Task Reminders';
  static const String _channelDescription = 'Reminders for your tasks';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  final StreamController<String> _taskCompletedStreamController =
      StreamController.broadcast();
  Stream<String> get taskCompletedStream => _taskCompletedStreamController.stream;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Los_Angeles'));

      const androidSettings = AndroidInitializationSettings('ic_stat_reminder');
      const settings = InitializationSettings(android: androidSettings);

      await _notificationsPlugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
          _handleNotificationResponse(notificationResponse);
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      await _createNotificationChannel();
      _isInitialized = true;
    } catch (e) {
      rethrow;
    }
  }

  void _handleNotificationResponse(NotificationResponse notificationResponse) {
    if (notificationResponse.actionId == _actionMarkCompleted &&
        notificationResponse.payload != null) {
      // Notify UI first
      try {
        final payload = json.decode(notificationResponse.payload!);
        final String taskId = payload['id'];
        _taskCompletedStreamController.add(taskId);
      } catch (e) {
        // Handle error
      }
      
      // Then update data in background
      _handleMarkCompletedAction(notificationResponse.payload!);
    }
  }

  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('ding'),
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> scheduleNotification({
    required Task task,
    required DateTime scheduledTime,
  }) async {
    if (!_isInitialized) {
      return;
    }

    final payload = json.encode({
      'id': task.id,
      'text': task.text,
    });

    try {
      await _notificationsPlugin.zonedSchedule(
        generateNotificationId(task.id),
        task.text,
        '',
        tz.TZDateTime.from(scheduledTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('ding'),
            enableVibration: true,
            icon: 'ic_stat_reminder',
            actions: [
              const AndroidNotificationAction(
                _actionMarkCompleted,
                'Mark Completed',
                showsUserInterface: false,
              ),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      // Handle scheduling error
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
    } catch (e) {
      // Silent fail for release
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      // Silent fail for release
    }
  }

  static int generateNotificationId(String taskId) {
    return taskId.hashCode.abs() % 100000;
  }

  void dispose() {
    _taskCompletedStreamController.close();
  }
}