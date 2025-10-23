import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Global callback for alarm notifications - must be top-level
@pragma('vm:entry-point')
void _showScheduledNotification(int id, Map<String, dynamic> params) async {
  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // Minimal initialization for background isolate
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('ic_stat_reminder'), // Use custom icon
  );

  try {
    await notificationsPlugin.initialize(settings);
    
    await notificationsPlugin.show(
      id,
      params['title'] ?? 'Task Reminder',
      params['body'] ?? 'Reminder',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'shutter_reminders',
          'Task Reminders',
          channelDescription: 'Reminders for your tasks',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: 'ic_stat_reminder', // Custom notification icon
        ),
      ),
    );
    
    print('📱 Background notification shown: ${params['title']}');
  } catch (e) {
    print('❌ Background notification error: $e');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _channelId = 'shutter_reminders';
  static const String _channelName = 'Task Reminders';
  static const String _channelDescription = 'Reminders for your tasks';

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    try {
      // Initialize services
      await AndroidAlarmManager.initialize();
      tz.initializeTimeZones();
      
      // Setup notifications with custom icon
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'), // Custom icon here
      );

      await _notificationsPlugin.initialize(settings);
      await _createNotificationChannel();
      
      _isInitialized = true;
      print('✅ Notification service initialized successfully');
    } catch (e) {
      print('❌ Notification service initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (!_isInitialized) {
      print('⚠️ Notification service not initialized');
      return false;
    }

    final now = DateTime.now();
    final delay = scheduledTime.difference(now);
    
    // Validate scheduled time
    if (delay <= Duration.zero) {
      print('⏰ Scheduled time is in the past: $scheduledTime');
      return false;
    }

    try {
      final scheduled = await AndroidAlarmManager.oneShot(
        delay,
        id,
        _showScheduledNotification,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        params: {'title': title, 'body': body},
      );
      
      if (scheduled) {
        print('✅ Scheduled notification for $scheduledTime (ID: $id)');
        return true;
      } else {
        print('❌ Failed to schedule notification');
        return false;
      }
    } catch (e) {
      print('❌ Schedule error: $e');
      return false;
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await AndroidAlarmManager.cancel(id);
      await _notificationsPlugin.cancel(id);
      print('🗑️ Cancelled notification ID: $id');
    } catch (e) {
      print('❌ Error cancelling notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      print('🗑️ Cancelled all notifications');
    } catch (e) {
      print('❌ Error cancelling all notifications: $e');
    }
  }

  /// Generate a consistent notification ID from task ID
  static int generateNotificationId(String taskId) {
    return taskId.hashCode.abs() % 100000;
  }
}