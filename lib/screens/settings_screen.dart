import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shutter/models/custom_theme.dart';
import 'package:shutter/providers/settings_notifier.dart';
import 'package:shutter/screens/theme_editor_screen.dart';
import 'package:uuid/uuid.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _themeIdPendingDeletion;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsNotifier>(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              final newThemeTemplate = settings.createNewThemeTemplate()
                ..id = const Uuid().v4();
              
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ThemeEditorScreen(
                  theme: newThemeTemplate,
                ),
              )).then((_) => setState(() {}));
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingRow(
            'Appearance',
            SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ButtonSegment<ThemeMode>(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.devices_outlined)),
              ],
              selected: <ThemeMode>{settings.themeMode},
              onSelectionChanged: (Set<ThemeMode> newSelection) => settings.setThemeMode(newSelection.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: settings.currentTheme.secondaryColor.withOpacity(0.2),
                selectedForegroundColor: settings.currentTheme.secondaryColor,
                foregroundColor: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
          const Divider(height: 1),
          
          _buildSettingRow(
            'Archive will be cleared after',
            SegmentedButton<ArchiveClearDuration>(
              segments: const <ButtonSegment<ArchiveClearDuration>>[
                ButtonSegment<ArchiveClearDuration>(value: ArchiveClearDuration.oneDay, label: Text('1D')),
                ButtonSegment<ArchiveClearDuration>(value: ArchiveClearDuration.threeDays, label: Text('3D')),
                ButtonSegment<ArchiveClearDuration>(value: ArchiveClearDuration.oneWeek, label: Text('1W')),
                ButtonSegment<ArchiveClearDuration>(value: ArchiveClearDuration.never, label: Text('Never')),
              ],
              selected: <ArchiveClearDuration>{settings.archiveClearDuration},
              onSelectionChanged: (Set<ArchiveClearDuration> newSelection) => settings.setArchiveClearDuration(newSelection.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: settings.currentTheme.secondaryColor.withOpacity(0.2),
                selectedForegroundColor: settings.currentTheme.secondaryColor,
                foregroundColor: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
          const Divider(height: 1),

          _buildSettingRow(
            'Task box height',
            Row(
              children: [
                const Icon(Icons.unfold_less),
                Expanded(
                  child: Slider(
                    value: settings.taskHeight,
                    min: 14.0,
                    max: 32.0,
                    divisions: 6,
                    label: '${settings.taskHeight.toStringAsFixed(0)}px',
                    onChanged: (double value) => settings.setTaskHeight(value),
                    activeColor: settings.currentTheme.secondaryColor,
                    inactiveColor: settings.currentTheme.secondaryColor.withOpacity(0.3),
                  ),
                ),
                const Icon(Icons.unfold_more),
              ],
            ),
          ),
          const Divider(height: 1),

          _buildSettingRow(
            'Completion animation speed',
            Row(
              children: [
                const Icon(Icons.arrow_upward),
                Expanded(
                  child: Slider(
                    value: settings.animationSpeed.toDouble(),
                    min: 100.0,
                    max: 1000.0,
                    divisions: 18,
                    label: '${settings.animationSpeed}ms',
                    onChanged: (double value) => settings.setAnimationSpeed(value),
                    activeColor: settings.currentTheme.secondaryColor,
                    inactiveColor: settings.currentTheme.secondaryColor.withOpacity(0.3),
                  ),
                ),
                const Icon(Icons.arrow_downward),
              ],
            ),
          ),
          const Divider(height: 1),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
            child: Text(
              'Color Themes',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: settings.themes.length,
              itemBuilder: (context, index) {
                final themeItem = settings.themes[index];
                final bool isSelected = themeItem.id == settings.currentTheme.id;
                final bool isPendingDeletion = _themeIdPendingDeletion == themeItem.id;

                return ListTile(
                  title: Text(
                    themeItem.name,
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  leading: CircleAvatar(backgroundColor: themeItem.primaryColor),
                  trailing: isPendingDeletion
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: Icon(Icons.check, color: settings.currentTheme.secondaryColor),
                          onPressed: () {
                            settings.deleteTheme(themeItem.id);
                            setState(() => _themeIdPendingDeletion = null);
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: theme.colorScheme.error),
                          onPressed: () => setState(() => _themeIdPendingDeletion = null),
                        ),
                      ])
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: settings.currentTheme.secondaryColor),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ThemeEditorScreen(theme: themeItem.copy()),
                          )).then((_) => setState(() {})),
                        ),
                        if (settings.themes.length > 1)
                          IconButton(
                            icon: Icon(Icons.delete, color: settings.currentTheme.secondaryColor),
                            onPressed: () => setState(() => _themeIdPendingDeletion = themeItem.id),
                          ),
                      ]),
                  onTap: () => settings.setCurrentTheme(themeItem.id),
                  selected: isSelected,
                  selectedTileColor: themeItem.primaryColor.withOpacity(0.2),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String title, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          control,
        ],
      ),
    );
  }
}

