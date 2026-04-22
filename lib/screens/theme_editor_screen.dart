import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/custom_theme.dart';
import '../providers/settings_notifier.dart';
import '../utils/haptics.dart';
import '../widgets/advanced_color_picker.dart';
import '../widgets/theme_preview_pane.dart';

/// Edits a [CustomTheme] in memory. On dispose, the edited theme is written
/// back through [SettingsNotifier] — either as a global theme (default), or
/// as a list-scope override when [listId] is supplied.
class ThemeEditorScreen extends StatefulWidget {
  final CustomTheme theme;

  /// When non-null, the edited theme is saved as the theme override for the
  /// given list instead of being added to the global theme collection.
  final String? listId;

  const ThemeEditorScreen({super.key, required this.theme, this.listId});

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late CustomTheme _editableTheme;
  bool _saved = false;

  bool get _isListMode => widget.listId != null;

  @override
  void initState() {
    super.initState();
    _editableTheme = widget.theme.copy();
  }

  @override
  void dispose() {
    _persist();
    super.dispose();
  }

  void _persist() {
    if (_saved) return;
    _saved = true;
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    if (_isListMode) {
      settings.updateListTheme(widget.listId!, _editableTheme);
      return;
    }
    if (_editableTheme.id != 'default') {
      _editableTheme.isDeletable = true;
    }
    if (settings.themes.any((t) => t.id == _editableTheme.id)) {
      settings.updateTheme(_editableTheme);
    } else {
      settings.addTheme(_editableTheme);
    }
  }

  Future<void> _pickImage() async {
    Haptics.selection();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _editableTheme.backgroundImagePath = pickedFile.path);
    }
  }

  Future<void> _exportJson() async {
    Haptics.selection();
    final encoded =
        const JsonEncoder.withIndent('  ').convert(_editableTheme.toJson());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Theme JSON'),
        content: SingleChildScrollView(
          child: SelectableText(
            encoded,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: encoded));
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(
                  content: Text('Theme copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importJson() async {
    Haptics.selection();
    final controller = TextEditingController();
    final submitted = await showDialog<String?>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Import theme JSON'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Paste a theme JSON to overwrite the current colors.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"id": "...", "name": "...", ...}',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.paste, size: 18),
              label: const Text('Paste from clipboard'),
              onPressed: () async {
                final clip = await Clipboard.getData('text/plain');
                if (clip?.text != null) controller.text = clip!.text!;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (submitted == null || submitted.trim().isEmpty) return;
    if (!mounted) return;

    try {
      final decoded = jsonDecode(submitted);
      if (decoded is! Map) throw const FormatException('not a JSON object');
      final imported = CustomTheme.fromJson(Map<String, dynamic>.from(decoded));
      setState(() {
        _editableTheme = imported
          ..id = _editableTheme.id
          ..isDeletable = _editableTheme.isDeletable;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Theme imported'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isListMode
        ? 'List appearance'
        : 'Edit "${_editableTheme.name}"';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save and close',
            onPressed: () {
              _persist();
              Navigator.of(context).pop();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') _exportJson();
              if (v == 'import') _importJson();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.upload_outlined),
                  title: Text('Export JSON'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('Import JSON'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ThemePreviewPane(theme: _editableTheme),
          const SizedBox(height: 20),
          if (!_isListMode) ...[
            TextFormField(
              initialValue: _editableTheme.name,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: const InputDecoration(
                labelText: 'Theme Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _editableTheme.name = value);
              },
            ),
            const SizedBox(height: 20),
          ],

          _buildColorPickerRow(
              'Title Bar Color',
              _editableTheme.primaryColor,
              (c) => setState(() => _editableTheme.primaryColor = c)),
          _buildColorPickerRow(
              'Accent Color',
              _editableTheme.secondaryColor,
              (c) => setState(() => _editableTheme.secondaryColor = c)),
          _buildColorPickerRow(
              'Task Text Color',
              _editableTheme.taskTextColor,
              (c) => setState(() => _editableTheme.taskTextColor = c)),
          _buildColorPickerRow(
              'Task Background Color',
              _editableTheme.taskBackgroundColor,
              (c) => setState(() => _editableTheme.taskBackgroundColor = c)),
          _buildColorPickerRow(
              'Strikethrough Color',
              _editableTheme.strikethroughColor,
              (c) => setState(() => _editableTheme.strikethroughColor = c)),
          _buildColorPickerRow(
              'Add Task Background Color',
              _editableTheme.inputAreaColor,
              (c) => setState(() => _editableTheme.inputAreaColor = c)),

          const Divider(height: 40),

          ListTile(
            title: const Text('Background Image'),
            subtitle: Text(_editableTheme.backgroundImagePath ?? 'None selected'),
            trailing: (_editableTheme.backgroundImagePath != null &&
                    _editableTheme.backgroundImagePath!.isNotEmpty)
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      Haptics.selection();
                      setState(
                          () => _editableTheme.backgroundImagePath = null);
                    },
                  )
                : null,
            onTap: _pickImage,
          ),
        ],
      ),
    );
  }

  Widget _buildColorPickerRow(
      String title, Color customColor, ValueChanged<Color> onCustomColorChanged) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context, listen: false);

    return ListTile(
      title: Text(title, style: theme.textTheme.bodyMedium),
      trailing: GestureDetector(
        onTap: () async {
          Haptics.selection();
          final Color? pickedColor = await showDialog<Color>(
            context: context,
            builder: (context) => AdvancedColorPicker(
              initialColor: customColor,
              onAddSavedColor: settings.addSavedColor,
              onRemoveSavedColor: settings.removeSavedColor,
            ),
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
