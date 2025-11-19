import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_theme.dart';

enum ArchiveClearDuration { oneDay, threeDays, oneWeek, never }

class SettingsNotifier extends ChangeNotifier {
  final SharedPreferences _prefs;
  List<CustomTheme> _themes = [];
  late CustomTheme _currentTheme;
  late ThemeMode _themeMode;
  late ArchiveClearDuration _archiveClearDuration;
  late double _taskHeight;
  late int _animationSpeed;
  List<Color> _savedColors = [];

  SettingsNotifier(this._prefs) {
    _loadSettings();
  }
  
  List<CustomTheme> get themes => _themes;
  CustomTheme get currentTheme => _currentTheme;
  ThemeMode get themeMode => _themeMode;
  ArchiveClearDuration get archiveClearDuration => _archiveClearDuration;
  double get taskHeight => _taskHeight;
  int get animationSpeed => _animationSpeed;
  List<Color> get savedColors => _savedColors;

  void _loadSettings() {
    _themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];
    _archiveClearDuration = ArchiveClearDuration.values[_prefs.getInt('archiveClearDuration') ?? ArchiveClearDuration.oneWeek.index];
    // --- FIX: Change default taskHeight to represent a scaling factor (1.0 = normal height) ---
    _taskHeight = _prefs.getDouble('taskHeight') ?? 1.0;
    _animationSpeed = _prefs.getInt('animationSpeed') ?? 450;
    
    final colorsJson = _prefs.getStringList('savedColors') ?? [];
    _savedColors = colorsJson.map((hex) => Color(int.parse(hex))).toList();
    _loadThemes();
  }

  void _loadThemes() {
    final List<CustomTheme> defaultThemes = _createDefaultThemes();
    final themesJson = _prefs.getString('customThemes');
    
    List<CustomTheme> savedThemes = [];
    if (themesJson != null) {
      final decoded = jsonDecode(themesJson) as List;
      savedThemes = decoded.map((themeJson) => CustomTheme.fromJson(themeJson)).toList();
    }

    final Map<String, CustomTheme> themeMap = { for (var theme in defaultThemes) theme.id : theme };
    for (var savedTheme in savedThemes) {
         themeMap[savedTheme.id] = savedTheme;
    }

    _themes = themeMap.values.toList();
    
    final currentThemeId = _prefs.getString('currentThemeId') ?? _themes.first.id;
    _currentTheme = _themes.firstWhere((t) => t.id == currentThemeId, orElse: () {
      final fallbackTheme = _themes.first;
      _prefs.setString('currentThemeId', fallbackTheme.id);
      return fallbackTheme;
    });
  }
  
  CustomTheme createNewThemeTemplate() {
    return CustomTheme(
      id: '',
      name: 'New Theme',
      primaryColor: Colors.blueGrey,
      secondaryColor: Colors.amber.shade700,
      taskBackgroundColor: Colors.blueGrey.shade600,
      inputAreaColor: Colors.blueGrey.shade700,
      taskTextColor: Colors.black87,
      strikethroughColor: Colors.black54,
    );
  }

  Future<void> _saveThemes() async {
    final themesJson = jsonEncode(_themes.map((theme) => theme.toJson()).toList());
    await _prefs.setString('customThemes', themesJson);
    notifyListeners();
  }

  void setCurrentTheme(String themeId) {
    _currentTheme = _themes.firstWhere((t) => t.id == themeId);
    _prefs.setString('currentThemeId', themeId);
    notifyListeners();
  }

  void addTheme(CustomTheme theme) {
    _themes.add(theme);
    _saveThemes();
  }

  void updateTheme(CustomTheme theme) {
    final index = _themes.indexWhere((t) => t.id == theme.id);
    if (index != -1) {
      _themes[index] = theme;
      if (_currentTheme.id == theme.id) {
        _currentTheme = theme;
      }
      _saveThemes();
    }
  }

  void deleteTheme(String themeId) {
    if (_themes.length <= 1) return;
    
    _themes.removeWhere((t) => t.id == themeId);
    if (_currentTheme.id == themeId) {
      setCurrentTheme(_themes.first.id);
    }
    _saveThemes();
  }
  
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }
  
  void setArchiveClearDuration(ArchiveClearDuration duration) {
    _archiveClearDuration = duration;
    _prefs.setInt('archiveClearDuration', duration.index);
    notifyListeners();
  }
  
  void setTaskHeight(double height) {
    _taskHeight = height;
    _prefs.setDouble('taskHeight', height);
    notifyListeners();
  }

  void setAnimationSpeed(double speed) {
    _animationSpeed = speed.toInt();
    _prefs.setInt('animationSpeed', _animationSpeed);
    notifyListeners();
  }
  
  void addSavedColor(Color color) {
    if (!_savedColors.contains(color)) {
      _savedColors.add(color);
      _saveColors();
      notifyListeners();
    }
  }

  void removeSavedColor(Color color) {
    _savedColors.remove(color);
    _saveColors();
    notifyListeners();
  }

  void updateSavedColorsOrder(List<Color> newOrder) {
    _savedColors = newOrder;
    _saveColors();
    notifyListeners();
  }

  Future<void> _saveColors() async {
    final colorHexes = _savedColors.map((c) => c.value.toString()).toList();
    await _prefs.setStringList('savedColors', colorHexes);
  }
}

List<CustomTheme> _createDefaultThemes() {
  return [
    CustomTheme(
      id: 'default',
      name: 'Default',
      primaryColor: Colors.blueGrey,
      secondaryColor: Colors.amber.shade700,
      taskBackgroundColor: Colors.blueGrey.shade600,
      inputAreaColor: Colors.blueGrey.shade700,
      taskTextColor: Colors.black87,
      strikethroughColor: Colors.black54,
    ),
  ];
}