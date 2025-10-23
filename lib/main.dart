import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/settings_notifier.dart';
import 'screens/todo_screen.dart';
import 'utils/app_themes.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize critical services
  final prefs = await SharedPreferences.getInstance();
  final notificationService = NotificationService();
  
  try {
    await notificationService.init();
  } catch (e) {
    print('Notification service init failed, continuing without notifications: $e');
  }
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => SettingsNotifier(prefs),
      child: const ShutterApp(),
    ),
  );
}

class ShutterApp extends StatelessWidget {
  const ShutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsNotifier>(
      builder: (context, settingsNotifier, child) {
        return MaterialApp(
          title: 'Shutter',
          theme: buildThemeData(Brightness.light, settingsNotifier.currentTheme),
          darkTheme: buildThemeData(Brightness.dark, settingsNotifier.currentTheme),
          themeMode: settingsNotifier.themeMode,
          home: const TodoScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}