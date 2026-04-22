import 'package:flutter/material.dart';

class CustomTheme {
  String id;
  String name;
  Color primaryColor;
  Color secondaryColor;
  Color taskBackgroundColor;
  Color inputAreaColor;
  Color taskTextColor;
  Color strikethroughColor;
  String? backgroundImagePath;
  bool isDeletable;
  int version;
  String? presetId;

  CustomTheme({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.taskBackgroundColor,
    required this.inputAreaColor,
    required this.taskTextColor,
    required this.strikethroughColor,
    this.backgroundImagePath,
    this.isDeletable = true,
    this.version = 1,
    this.presetId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'primaryColor': primaryColor.toARGB32(),
        'secondaryColor': secondaryColor.toARGB32(),
        'taskBackgroundColor': taskBackgroundColor.toARGB32(),
        'inputAreaColor': inputAreaColor.toARGB32(),
        'taskTextColor': taskTextColor.toARGB32(),
        'strikethroughColor': strikethroughColor.toARGB32(),
        'backgroundImagePath': backgroundImagePath,
        'isDeletable': isDeletable,
        'version': version,
        'presetId': presetId,
      };

  factory CustomTheme.fromJson(Map<String, dynamic> json) {
    Color getColor(String key, Color defaultColor) {
      return json[key] != null ? Color(json[key]) : defaultColor;
    }

    return CustomTheme(
      id: json['id'],
      name: json['name'],
      primaryColor: getColor('primaryColor', Colors.blueGrey),
      secondaryColor: getColor('secondaryColor', Colors.amber.shade700),
      taskBackgroundColor: getColor('taskBackgroundColor', Colors.blueGrey.shade600),
      inputAreaColor: getColor('inputAreaColor', Colors.blueGrey.shade700),
      taskTextColor: getColor('taskTextColor', Colors.black87),
      strikethroughColor: getColor('strikethroughColor', Colors.black54),
      backgroundImagePath: json['backgroundImagePath'],
      isDeletable: json['isDeletable'] ?? true,
      version: (json['version'] as int?) ?? 1,
      presetId: json['presetId'] as String?,
    );
  }

  CustomTheme copy() {
    return CustomTheme.fromJson(toJson());
  }

  @override
  String toString() {
    return 'CustomTheme(id: $id, name: $name, primaryColor: ${primaryColor.toARGB32().toRadixString(16)}, isDeletable: $isDeletable)';
  }
}
