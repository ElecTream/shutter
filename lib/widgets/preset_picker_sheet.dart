import 'package:flutter/material.dart';
import '../models/custom_theme.dart';
import '../utils/haptics.dart';
import '../utils/theme_presets.dart';

/// Bottom sheet used to seed a new theme or a list-scope override. Returns a
/// fresh [CustomTheme] ready to edit — either a cloned global theme, a cloned
/// preset, a "continue current" clone of an existing override, or a blank
/// template. Returns null if the user dismissed the sheet.
class PresetPickerSheet extends StatelessWidget {
  final List<CustomTheme> globalThemes;
  final CustomTheme? currentOverride;

  const PresetPickerSheet({
    super.key,
    this.globalThemes = const [],
    this.currentOverride,
  });

  static Future<CustomTheme?> show(
    BuildContext context, {
    List<CustomTheme> globalThemes = const [],
    CustomTheme? currentOverride,
  }) {
    return showModalBottomSheet<CustomTheme>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PresetPickerSheet(
        globalThemes: globalThemes,
        currentOverride: currentOverride,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCurrent = currentOverride != null;
    final hasGlobals = globalThemes.isNotEmpty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pick a starting palette',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Start from one of your themes, a preset, or blank. You can tweak every color after.',
              style: theme.textTheme.bodySmall,
            ),
            if (hasCurrent || hasGlobals) ...[
              const SizedBox(height: 16),
              Text(
                'Your themes',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (hasCurrent)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _ExistingThemeTile(
                          theme: currentOverride!,
                          label: 'Continue current',
                          onTap: () {
                            Haptics.selection();
                            Navigator.of(context)
                                .pop(currentOverride!.copy());
                          },
                        ),
                      ),
                    ...globalThemes.map((t) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _ExistingThemeTile(
                            theme: t,
                            label: t.name,
                            onTap: () {
                              Haptics.selection();
                              Navigator.of(context).pop(t.copy());
                            },
                          ),
                        )),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Presets',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: [
                _BlankTile(onTap: () {
                  Haptics.selection();
                  Navigator.of(context).pop(ThemePresets.blank());
                }),
                ...ThemePresets.all.map((preset) {
                  return _PresetTile(
                    preset: preset,
                    onTap: () {
                      Haptics.selection();
                      Navigator.of(context).pop(preset.build());
                    },
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExistingThemeTile extends StatelessWidget {
  final CustomTheme theme;
  final String label;
  final VoidCallback onTap;
  const _ExistingThemeTile({
    required this.theme,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: Material(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                Text(
                  label,
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
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final ThemePreset preset;
  final VoidCallback onTap;
  const _PresetTile({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final built = preset.build();
    final theme = Theme.of(context);
    return Material(
      color: built.primaryColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _Swatch(color: built.secondaryColor),
                  const SizedBox(width: 4),
                  _Swatch(color: built.taskBackgroundColor),
                  const SizedBox(width: 4),
                  _Swatch(color: built.inputAreaColor),
                ],
              ),
              Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: built.taskTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlankTile extends StatelessWidget {
  final VoidCallback onTap;
  const _BlankTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.add_circle_outline,
                  color: theme.colorScheme.onSurfaceVariant),
              Text(
                'Blank',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
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
