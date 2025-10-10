import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/custom_theme.dart';
import '../providers/settings_notifier.dart';
import '../widgets/advanced_color_picker.dart';

class ThemeEditorScreen extends StatefulWidget {
  final CustomTheme theme;
  const ThemeEditorScreen({super.key, required this.theme});

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late CustomTheme _editableTheme;

  @override
  void initState() {
    super.initState();
    _editableTheme = widget.theme.copy();
  }

  void _saveChanges() {
    final themeNotifier = Provider.of<SettingsNotifier>(context, listen: false);
    if (themeNotifier.themes.any((t) => t.id == _editableTheme.id)) {
      themeNotifier.updateTheme(_editableTheme);
    } else {
      themeNotifier.addTheme(_editableTheme);
    }
  }
  
  @override
  void dispose() {
    _saveChanges();
    super.dispose();
  }

  void _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _editableTheme.backgroundImagePath = pickedFile.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit "${_editableTheme.name}"'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              _saveChanges();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            initialValue: _editableTheme.name,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(labelText: 'Theme Name', border: OutlineInputBorder()),
            onChanged: (value) => _editableTheme.name = value,
          ),
          const SizedBox(height: 20),

          _buildColorPickerRow('Title Bar Color', _editableTheme.primaryColor, (color) => setState(() => _editableTheme.primaryColor = color)),
          _buildColorPickerRow('Accent Color', _editableTheme.secondaryColor, (color) => setState(() => _editableTheme.secondaryColor = color)),
          _buildColorPickerRow('Task Text Color', _editableTheme.taskTextColor, (color) => setState(() => _editableTheme.taskTextColor = color)),
          _buildColorPickerRow('Task Background Color', _editableTheme.taskBackgroundColor, (color) => setState(() => _editableTheme.taskBackgroundColor = color)),
          _buildColorPickerRow('Strikethrough Color', _editableTheme.strikethroughColor, (color) => setState(() => _editableTheme.strikethroughColor = color)),
          _buildColorPickerRow('Add Task Background Color', _editableTheme.inputAreaColor, (color) => setState(() => _editableTheme.inputAreaColor = color)),

          const Divider(height: 40),
          ListTile(
            title: const Text('Background Image'),
            subtitle: Text(_editableTheme.backgroundImagePath ?? 'None selected'),
            trailing: (_editableTheme.backgroundImagePath != null && _editableTheme.backgroundImagePath!.isNotEmpty)
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _editableTheme.backgroundImagePath = null))
              : null,
            onTap: _pickImage,
          ),
        ],
      ),
    );
  }

  Widget _buildColorPickerRow(String title, Color customColor, ValueChanged<Color> onCustomColorChanged) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(title, style: theme.textTheme.bodyMedium),
      trailing: GestureDetector(
        onTap: () async {
          final Color? pickedColor = await showDialog<Color>(
            context: context,
            builder: (context) => AdvancedColorPicker(initialColor: customColor),
          );
          if (pickedColor != null) {
            onCustomColorChanged(pickedColor);
          }
        },
        child: CircleAvatar(
          backgroundColor: customColor,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.dividerColor, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

