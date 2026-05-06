import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/auth_notifier.dart';
import 'providers/settings_notifier.dart';
import 'screens/todo_screen.dart';
import 'services/notification_service.dart';
import 'services/sync_orchestrator.dart';
import 'utils/app_themes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize critical services
  final prefs = await SharedPreferences.getInstance();
  final notificationService = NotificationService();

  try {
    await notificationService.init();
  } catch (e) {
    debugPrint(
        'Notification service init failed, continuing without notifications: $e');
  }

  final settingsNotifier = SettingsNotifier(prefs);
  final authNotifier = AuthNotifier();
  // Sync orchestrator lives outside the widget tree — it must outlive any
  // particular screen so dirty events queued mid-rebuild aren't dropped.
  final orchestrator = SyncOrchestrator(settingsNotifier, authNotifier);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsNotifier>.value(value: settingsNotifier),
        ChangeNotifierProvider<AuthNotifier>.value(value: authNotifier),
        Provider<SyncOrchestrator>.value(value: orchestrator),
      ],
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
          theme:
              buildThemeData(Brightness.light, settingsNotifier.currentTheme),
          darkTheme:
              buildThemeData(Brightness.dark, settingsNotifier.currentTheme),
          themeMode: settingsNotifier.themeMode,
          home: const TodoScreen(),
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(settingsNotifier.textScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
