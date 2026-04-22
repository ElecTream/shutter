import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/custom_theme.dart';
import '../providers/settings_notifier.dart';
import '../utils/app_info.dart';
import '../utils/haptics.dart';
import '../widgets/preset_picker_sheet.dart';
import 'theme_editor_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>();
    final accent = settings.currentTheme.secondaryColor;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _AppearanceCard(settings: settings, accent: accent),
            const SizedBox(height: 12),
            _BehaviorCard(settings: settings, accent: accent),
            const SizedBox(height: 12),
            _ThemesCard(settings: settings, accent: accent),
            const SizedBox(height: 12),
            _DataCard(settings: settings, accent: accent),
            const SizedBox(height: 12),
            const _AboutCard(),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  const _SectionCard({
    required this.title,
    required this.children,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  final SettingsNotifier settings;
  final Color accent;
  const _AppearanceCard({required this.settings, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Appearance',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Theme mode', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.devices_outlined),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) {
                  Haptics.selection();
                  settings.setThemeMode(s.first);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: accent.withValues(alpha: 0.2),
                  selectedForegroundColor: accent,
                  foregroundColor: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        _SliderRow(
          label: 'Task box height',
          value: settings.taskHeight,
          min: 0.7,
          max: 1.5,
          divisions: 8,
          leading: const Icon(Icons.unfold_less),
          trailing: const Icon(Icons.unfold_more),
          valueLabel: '${(settings.taskHeight * 100).toStringAsFixed(0)}%',
          accent: accent,
          onChanged: settings.setTaskHeight,
        ),
        const Divider(height: 1),
        _SliderRow(
          label: 'Text scale',
          value: settings.textScale,
          min: 0.85,
          max: 1.30,
          divisions: 9,
          leading: const Icon(Icons.text_decrease),
          trailing: const Icon(Icons.text_increase),
          valueLabel: '${(settings.textScale * 100).toStringAsFixed(0)}%',
          accent: accent,
          onChanged: settings.setTextScale,
        ),
      ],
    );
  }
}

class _BehaviorCard extends StatelessWidget {
  final SettingsNotifier settings;
  final Color accent;
  const _BehaviorCard({required this.settings, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = settings.defaultReminderTime;
    final timeLabel = MaterialLocalizations.of(context).formatTimeOfDay(t);
    return _SectionCard(
      title: 'Behavior',
      children: [
        _SliderRow(
          label: 'Completion animation speed',
          value: settings.animationSpeed.toDouble(),
          min: 100,
          max: 1000,
          divisions: 18,
          leading: const Icon(Icons.fast_forward),
          trailing: const Icon(Icons.slow_motion_video),
          valueLabel: '${settings.animationSpeed}ms',
          accent: accent,
          onChanged: settings.setAnimationSpeed,
        ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('Haptics'),
          subtitle: Text(
            'Vibration feedback on interactions',
            style: theme.textTheme.bodySmall,
          ),
          value: settings.hapticsEnabled,
          activeThumbColor: accent,
          onChanged: (v) {
            if (v) Haptics.selection();
            settings.setHapticsEnabled(v);
          },
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('Default reminder time'),
          subtitle: Text(
            'Pre-filled when setting a new reminder',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Text(
            timeLabel,
            style: theme.textTheme.titleSmall?.copyWith(color: accent),
          ),
          onTap: () async {
            Haptics.selection();
            final picked = await showTimePicker(
              context: context,
              initialTime: settings.defaultReminderTime,
            );
            if (picked != null) {
              settings.setDefaultReminderTime(picked);
            }
          },
        ),
      ],
    );
  }
}

class _ThemesCard extends StatefulWidget {
  final SettingsNotifier settings;
  final Color accent;
  const _ThemesCard({required this.settings, required this.accent});

  @override
  State<_ThemesCard> createState() => _ThemesCardState();
}

class _ThemesCardState extends State<_ThemesCard> {
  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final accent = widget.accent;
    final theme = Theme.of(context);
    final customListsWithTheme =
        settings.taskLists.where((l) => l.themeOverride != null).length;
    final totalLists = settings.taskLists.length;

    return _SectionCard(
      title: 'Themes',
      actions: [
        IconButton(
          icon: Icon(Icons.add, color: accent),
          tooltip: 'Add new theme',
          onPressed: () => _createNewTheme(context, settings),
        ),
      ],
      children: [
        SizedBox(
          height: 112,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: settings.themes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final t = settings.themes[index];
              final isActive = t.id == settings.currentTheme.id;
              return _ThemeTile(
                theme: t,
                isActive: isActive,
                accent: accent,
                onTap: () {
                  Haptics.selection();
                  settings.setCurrentTheme(t.id);
                },
                onEdit: () {
                  Haptics.selection();
                  Navigator.of(context)
                      .push(MaterialPageRoute(
                        builder: (_) => ThemeEditorScreen(theme: t.copy()),
                      ))
                      .then((_) => setState(() {}));
                },
                onDelete: t.isDeletable && settings.themes.length > 1
                    ? () => _confirmDeleteTheme(context, settings, t.id, t.name)
                    : null,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(Icons.palette_outlined, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'List themes',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '$customListsWithTheme of $totalLists customized',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Open any list and use "Customize appearance" to give it its own look.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _createNewTheme(
      BuildContext context, SettingsNotifier settings) async {
    Haptics.light();
    final picked = await PresetPickerSheet.show(
      context,
      globalThemes: settings.themes,
    );
    if (picked == null) return;
    picked.id = const Uuid().v4();
    picked.isDeletable = true;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ThemeEditorScreen(theme: picked)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteTheme(BuildContext context,
      SettingsNotifier settings, String id, String name) async {
    Haptics.selection();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('This theme will be removed. Any list using it will revert to the global theme.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      Haptics.medium();
      settings.deleteTheme(id);
    }
  }
}

class _ThemeTile extends StatelessWidget {
  final CustomTheme theme;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _ThemeTile({
    required this.theme,
    required this.isActive,
    required this.accent,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    return SizedBox(
      width: 140,
      child: Material(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 34, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Swatch(color: theme.secondaryColor),
                          const SizedBox(width: 4),
                          _Swatch(color: theme.taskBackgroundColor),
                          const SizedBox(width: 4),
                          _Swatch(color: theme.inputAreaColor),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        theme.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: materialTheme.textTheme.bodyMedium?.copyWith(
                          color: theme.taskTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (onDelete != null)
                Positioned(
                  top: 2,
                  left: 2,
                  child: _TinyIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete theme',
                    color: theme.taskTextColor,
                    onPressed: onDelete!,
                  ),
                ),
              Positioned(
                top: 2,
                right: 2,
                child: _TinyIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit theme',
                  color: theme.taskTextColor,
                  onPressed: onEdit,
                ),
              ),
              if (isActive)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;
  const _TinyIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      onPressed: onPressed,
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  const _Swatch({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  final SettingsNotifier settings;
  final Color accent;
  const _DataCard({required this.settings, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Data',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Archive clear duration', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SegmentedButton<ArchiveClearDuration>(
                segments: const [
                  ButtonSegment(value: ArchiveClearDuration.oneDay, label: Text('1D')),
                  ButtonSegment(value: ArchiveClearDuration.threeDays, label: Text('3D')),
                  ButtonSegment(value: ArchiveClearDuration.oneWeek, label: Text('1W')),
                  ButtonSegment(value: ArchiveClearDuration.never, label: Text('Never')),
                ],
                selected: {settings.archiveClearDuration},
                onSelectionChanged: (s) {
                  Haptics.selection();
                  settings.setArchiveClearDuration(s.first);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: accent.withValues(alpha: 0.2),
                  selectedForegroundColor: accent,
                  foregroundColor: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.upload_outlined, color: accent),
          title: const Text('Export data'),
          subtitle: const Text('Copy a JSON snapshot to clipboard'),
          onTap: () => _export(context),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.download_outlined, color: accent),
          title: const Text('Import data'),
          subtitle: const Text('Replace everything with a saved JSON snapshot'),
          onTap: () => _import(context),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined,
              color: theme.colorScheme.error),
          title: Text(
            'Wipe all data',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: const Text('Erase every list, task, theme, and setting'),
          onTap: () => _wipe(context),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    Haptics.selection();
    final blob = settings.exportAllDataJson();
    await Clipboard.setData(ClipboardData(text: blob));
    if (!context.mounted) return;
    final bytes = blob.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${_fmtBytes(bytes)} to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    Haptics.selection();
    final controller = TextEditingController();
    final submitted = await showDialog<String?>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Import data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste an exported JSON snapshot. This replaces ALL current data.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"schema": 2, ...}',
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
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
          'Every list, task, archive entry, theme, and setting will be overwritten. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await settings.importAllDataJson(submitted);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Data imported successfully'
            : 'Import failed: invalid or unsupported JSON'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _wipe(BuildContext context) async {
    Haptics.selection();
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Wipe all data?'),
        content: const Text(
          'Every list, task, archive entry, theme, and setting will be erased. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (firstOk != true) return;
    if (!context.mounted) return;

    final secondOk = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Are you absolutely sure?'),
        content: const Text('This is the last confirmation before every byte of app data is deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Keep my data'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Wipe everything'),
          ),
        ],
      ),
    );
    if (secondOk != true) return;

    Haptics.heavy();
    await settings.wipeAllData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All data wiped'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'About',
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Shutter'),
          subtitle: Text(
            'Version ${AppInfo.version}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('A simple daily planner'),
          subtitle: Text(
            'Built with Flutter',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Widget leading;
  final Widget trailing;
  final String valueLabel;
  final Color accent;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.leading,
    required this.trailing,
    required this.valueLabel,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                valueLabel,
                style: theme.textTheme.bodySmall?.copyWith(color: accent),
              ),
            ],
          ),
          Row(
            children: [
              leading,
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: valueLabel,
                  activeColor: accent,
                  inactiveColor: accent.withValues(alpha: 0.3),
                  onChanged: (v) {
                    Haptics.selection();
                    onChanged(v);
                  },
                ),
              ),
              trailing,
            ],
          ),
        ],
      ),
    );
  }
}
