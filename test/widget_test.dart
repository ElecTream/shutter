import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shutter/main.dart';
import 'package:shutter/providers/settings_notifier.dart';

void main() {
  testWidgets('ShutterApp smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsNotifier(prefs),
        child: const ShutterApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
