import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/custom_theme.dart';

class ThemePreset {
  final String id;
  final String name;
  final CustomTheme Function() build;
  const ThemePreset({required this.id, required this.name, required this.build});
}

class ThemePresets {
  ThemePresets._();

  static final List<ThemePreset> all = [
    ThemePreset(
      id: 'preset_midnight',
      name: 'Midnight',
      build: () => _make(
        presetId: 'preset_midnight',
        name: 'Midnight',
        primary: const Color(0xFF0F1729),
        secondary: const Color(0xFF8AB4F8),
        taskBg: const Color(0xFF1C2744),
        inputBg: const Color(0xFF111A33),
        taskText: const Color(0xFFE8EEFB),
        strike: const Color(0xFF8FA0C2),
      ),
    ),
    ThemePreset(
      id: 'preset_paper',
      name: 'Paper',
      build: () => _make(
        presetId: 'preset_paper',
        name: 'Paper',
        primary: const Color(0xFFFAF6EE),
        secondary: const Color(0xFFB35C00),
        taskBg: const Color(0xFFFFFDF7),
        inputBg: const Color(0xFFF2EADA),
        taskText: const Color(0xFF2A2620),
        strike: const Color(0xFF8A8374),
      ),
    ),
    ThemePreset(
      id: 'preset_forest',
      name: 'Forest',
      build: () => _make(
        presetId: 'preset_forest',
        name: 'Forest',
        primary: const Color(0xFF1B3A2B),
        secondary: const Color(0xFFA7C957),
        taskBg: const Color(0xFF285140),
        inputBg: const Color(0xFF17302A),
        taskText: const Color(0xFFE7F0DF),
        strike: const Color(0xFF8FAA8A),
      ),
    ),
    ThemePreset(
      id: 'preset_sunset',
      name: 'Sunset',
      build: () => _make(
        presetId: 'preset_sunset',
        name: 'Sunset',
        primary: const Color(0xFFEB5E28),
        secondary: const Color(0xFFFFD166),
        taskBg: const Color(0xFFFF8E5E),
        inputBg: const Color(0xFFC94A1F),
        taskText: const Color(0xFF3B1D10),
        strike: const Color(0xFF7A3A22),
      ),
    ),
    ThemePreset(
      id: 'preset_ocean',
      name: 'Ocean',
      build: () => _make(
        presetId: 'preset_ocean',
        name: 'Ocean',
        primary: const Color(0xFF003E52),
        secondary: const Color(0xFF48CAE4),
        taskBg: const Color(0xFF005973),
        inputBg: const Color(0xFF00303F),
        taskText: const Color(0xFFE1F6FF),
        strike: const Color(0xFF8AC0CE),
      ),
    ),
    ThemePreset(
      id: 'preset_mono',
      name: 'Mono',
      build: () => _make(
        presetId: 'preset_mono',
        name: 'Mono',
        primary: const Color(0xFF111111),
        secondary: const Color(0xFFFFFFFF),
        taskBg: const Color(0xFF1E1E1E),
        inputBg: const Color(0xFF050505),
        taskText: const Color(0xFFEDEDED),
        strike: const Color(0xFF888888),
      ),
    ),
    ThemePreset(
      id: 'preset_rosewater',
      name: 'Rosewater',
      build: () => _make(
        presetId: 'preset_rosewater',
        name: 'Rosewater',
        primary: const Color(0xFFF7D6D0),
        secondary: const Color(0xFFB4336A),
        taskBg: const Color(0xFFFBE3DE),
        inputBg: const Color(0xFFEEBFB7),
        taskText: const Color(0xFF442028),
        strike: const Color(0xFF9B6C71),
      ),
    ),
    ThemePreset(
      id: 'preset_graphite',
      name: 'Graphite',
      build: () => _make(
        presetId: 'preset_graphite',
        name: 'Graphite',
        primary: const Color(0xFF2B2D30),
        secondary: const Color(0xFFE0AA3E),
        taskBg: const Color(0xFF3A3D42),
        inputBg: const Color(0xFF212326),
        taskText: const Color(0xFFE8E8EA),
        strike: const Color(0xFF9AA0A6),
      ),
    ),
  ];

  static CustomTheme _make({
    required String presetId,
    required String name,
    required Color primary,
    required Color secondary,
    required Color taskBg,
    required Color inputBg,
    required Color taskText,
    required Color strike,
  }) {
    return CustomTheme(
      id: const Uuid().v4(),
      name: name,
      primaryColor: primary,
      secondaryColor: secondary,
      taskBackgroundColor: taskBg,
      inputAreaColor: inputBg,
      taskTextColor: taskText,
      strikethroughColor: strike,
      isDeletable: true,
      version: 1,
      presetId: presetId,
    );
  }

  /// Blank template: starts from the current default palette but flagged as a
  /// fresh, deletable, user-owned theme with no presetId.
  static CustomTheme blank() {
    return CustomTheme(
      id: const Uuid().v4(),
      name: 'New Theme',
      primaryColor: Colors.blueGrey,
      secondaryColor: Colors.amber.shade700,
      taskBackgroundColor: Colors.blueGrey.shade600,
      inputAreaColor: Colors.blueGrey.shade700,
      taskTextColor: Colors.black87,
      strikethroughColor: Colors.black54,
      isDeletable: true,
      version: 1,
    );
  }
}
