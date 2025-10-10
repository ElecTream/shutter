import 'package:flutter/material.dart';
import 'package:shutter/models/custom_theme.dart';

ThemeData buildThemeData(Brightness brightness, CustomTheme theme) {
  final isDark = brightness == Brightness.dark;
  
  final effectiveTheme = theme;

  final scaffoldBg = isDark ? const Color(0xFF121212) : const Color(0xFFF7F9FC);
  final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
  final appTextColor = isDark ? const Color(0xDEFFFFFF) : Colors.black87;
  final hintColor = appTextColor.withOpacity(0.6);

  final appBarBrightness = ThemeData.estimateBrightnessForColor(effectiveTheme.primaryColor);
  final appBarForegroundColor = appBarBrightness == Brightness.dark ? Colors.white : Colors.black;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: effectiveTheme.primaryColor,
    brightness: brightness,
  );

  return ThemeData.from(colorScheme: colorScheme, useMaterial3: true).copyWith(
    primaryColor: effectiveTheme.primaryColor,
    scaffoldBackgroundColor: scaffoldBg,
    appBarTheme: AppBarTheme(
      backgroundColor: effectiveTheme.primaryColor,
      foregroundColor: appBarForegroundColor,
      elevation: 2,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.bold, color: appBarForegroundColor),
    ),
    cardColor: cardBg,
    dividerColor: isDark ? Colors.white12 : Colors.grey[200],
    iconTheme: IconThemeData(color: effectiveTheme.secondaryColor),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: effectiveTheme.taskTextColor),
      bodyMedium: TextStyle(color: appTextColor),
      titleMedium: TextStyle(color: hintColor),
      labelLarge: TextStyle(color: appTextColor),
    ).apply(
      fontFamily: 'Inter',
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F2F5),
      hintStyle: TextStyle(color: hintColor),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: effectiveTheme.secondaryColor, width: 2),
      ),
    ),
  );
}

