import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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

  // Firebase init is optional — without flutterfire configure / a present
  // google-services.json, this throws and we fall back to local + Drive only.
  // FirestoreListService and the FirebaseAuth bridge guard on Firebase.apps
  // before doing anything, so silent failure is safe.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint(
        'Firebase init skipped (Firestore features disabled until flutterfire configure runs): $e');
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

class ShutterApp extends StatefulWidget {
  const ShutterApp({super.key});

  @override
  State<ShutterApp> createState() => _ShutterAppState();
}

class _ShutterAppState extends State<ShutterApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume → kick a sync so a second device's edits made while we were
    // backgrounded get pulled in. The orchestrator self-debounces and
    // no-ops when signed out, so it's safe to fire blindly.
    if (state == AppLifecycleState.resumed) {
      final orchestrator = context.read<SyncOrchestrator>();
      unawaited(orchestrator.syncNow());
    }
  }

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
