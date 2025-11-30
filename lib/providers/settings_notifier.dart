import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_theme.dart';
import '../models/list.dart'; // NEW

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
  
  // NEW: List management
  List<TaskList> _taskLists = [];
  TaskList? _currentList; // Optional: May be used for tracking the last viewed list

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
  // NEW: Getters for lists
  List<TaskList> get taskLists => _taskLists;
  TaskList? get currentList => _currentList;

  void _loadSettings() {
    _themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];
    _archiveClearDuration = ArchiveClearDuration.values[_prefs.getInt('archiveClearDuration') ?? ArchiveClearDuration.oneWeek.index];
    _taskHeight = _prefs.getDouble('taskHeight') ?? 1.0;
    _animationSpeed = _prefs.getInt('animationSpeed') ?? 450;
    
    final colorsJson = _prefs.getStringList('savedColors') ?? [];
    _savedColors = colorsJson.map((hex) => Color(int.parse(hex))).toList();
    _loadThemes();
    _loadTaskLists(); // NEW: Load lists
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

  // NEW: List management persistence
  void _loadTaskLists() {
    final listsJson = _prefs.getString('taskLists');
    if (listsJson != null) {
      final decoded = jsonDecode(listsJson) as List;
      _taskLists = decoded.map((listJson) => TaskList.fromJson(listJson)).toList();
    } else {
      // Create a default list if none exist
      final defaultList = TaskList.createNew(name: 'My Tasks');
      _taskLists = [defaultList];
    }
  }

  Future<void> _saveTaskLists() async {
    final listsJson = jsonEncode(_taskLists.map((list) => list.toJson()).toList());
    await _prefs.setString('taskLists', listsJson);
    notifyListeners();
  }

  void addTaskList(TaskList list) {
    _taskLists.insert(0, list);
    _saveTaskLists();
  }

  void updateTaskList(TaskList list) {
    final index = _taskLists.indexWhere((t) => t.id == list.id);
    if (index != -1) {
      _taskLists[index] = list;
      _saveTaskLists();
    }
  }

  Future<void> deleteTaskList(String listId) async {
    if (_taskLists.length <= 1) return; // Prevent deleting the last list

    _taskLists.removeWhere((t) => t.id == listId);
    await _saveTaskLists();
    
    // Also delete all related data (tasks and archives)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('todos_$listId');
    await prefs.remove('archivedTodos_$listId');
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
        isDeletable: false, // Default theme should not be deletable
      ),
    ];
  }

  CustomTheme createNewThemeTemplate() {
    return _createDefaultThemes().first.copy()
      ..name = 'New Theme'
      ..isDeletable = true;
  }

  Future<void> _saveThemes() async {
    final themesToSave = _themes.where((t) => t.isDeletable || t.id != 'default').toList();
    final themesJson = jsonEncode(themesToSave.map((theme) => theme.toJson()).toList());
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
    final themeToDelete = _themes.firstWhere((t) => t.id == themeId);
    if (_themes.length <= 1 || !themeToDelete.isDeletable) return;
    
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
    if (!_savedColors.contains(color) && _savedColors.length < 10) {
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