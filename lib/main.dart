import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/settings_notifier.dart';
import 'screens/todo_screen.dart';
import 'utils/app_themes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
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

