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
  final bool isDeletable;

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
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'primaryColor': primaryColor.value,
        'secondaryColor': secondaryColor.value,
        'taskBackgroundColor': taskBackgroundColor.value,
        'inputAreaColor': inputAreaColor.value,
        'taskTextColor': taskTextColor.value,
        'strikethroughColor': strikethroughColor.value,
        'backgroundImagePath': backgroundImagePath,
        'isDeletable': isDeletable,
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
    );
  }

  CustomTheme copy() {
    return CustomTheme.fromJson(toJson());
  }
}

