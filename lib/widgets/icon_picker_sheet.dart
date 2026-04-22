import 'package:flutter/material.dart';
import '../utils/haptics.dart';

/// Result returned by [showIconPickerSheet]. Exactly one of [emoji] and
/// [codePoint] is non-null on a successful pick; both null means the user
/// cleared the icon. Sheet returning `null` means the user dismissed without
/// picking — callers should preserve the existing icon in that case.
class IconPickerResult {
  final String? emoji;
  final int? codePoint;
  const IconPickerResult({this.emoji, this.codePoint});

  bool get isCleared => emoji == null && codePoint == null;
}

/// Curated set of Material icons useful for list categorization. Limited on
/// purpose — users almost never want the full 2k-icon set here, and keeping
/// the sheet scannable matters more than exhaustiveness.
const List<IconData> _curatedIcons = [
  Icons.folder_outlined,
  Icons.star_outline,
  Icons.favorite_border,
  Icons.home_outlined,
  Icons.work_outline,
  Icons.school_outlined,
  Icons.shopping_cart_outlined,
  Icons.restaurant_outlined,
  Icons.fitness_center_outlined,
  Icons.sports_esports_outlined,
  Icons.directions_run,
  Icons.self_improvement_outlined,
  Icons.flight_outlined,
  Icons.directions_car_outlined,
  Icons.pets_outlined,
  Icons.local_florist_outlined,
  Icons.book_outlined,
  Icons.music_note_outlined,
  Icons.movie_outlined,
  Icons.palette_outlined,
  Icons.camera_alt_outlined,
  Icons.celebration_outlined,
  Icons.cake_outlined,
  Icons.coffee_outlined,
  Icons.local_bar_outlined,
  Icons.health_and_safety_outlined,
  Icons.medical_services_outlined,
  Icons.medication_outlined,
  Icons.attach_money,
  Icons.account_balance_wallet_outlined,
  Icons.receipt_long_outlined,
  Icons.laptop_mac_outlined,
  Icons.code,
  Icons.build_outlined,
  Icons.eco_outlined,
  Icons.light_mode_outlined,
  Icons.bedtime_outlined,
  Icons.water_drop_outlined,
  Icons.flag_outlined,
  Icons.lightbulb_outline,
];

/// Quick-access emojis shown above the free-text field. Ordered loosely by
/// expected task-list usage (productivity/organization first).
const List<String> _quickEmojis = [
  '📋', '✅', '📝', '📅', '⏰', '🎯', '🔥', '⭐',
  '❤️', '💼', '🏠', '🛒', '🍽️', '🏋️', '🎮', '📚',
  '🎵', '🎬', '💡', '💰', '🚗', '✈️', '🐾', '🌱',
];

// Codepoint → IconData lookup built once from the curated list. Because every
// entry is a literal `Icons.X` reference, Flutter's icon tree-shaker keeps
// only the curated glyphs. A dynamic `IconData(parsed, fontFamily: ...)` would
// defeat tree-shaking (the analyzer can't know which glyphs are reachable), so
// we resolve stored codepoints through this table instead.
final Map<int, IconData> _iconByCodePoint = {
  for (final i in _curatedIcons) i.codePoint: i,
};

/// Renders a list's current icon as a widget. `emoji` wins if both are set
/// (shouldn't happen in practice — model enforces one-of, but defensive). If
/// neither is set, falls back to the folder outline so every list tile has a
/// visual anchor.
Widget buildListIcon({
  String? emoji,
  String? codePoint,
  required Color color,
  double size = 22,
}) {
  if (emoji != null && emoji.isNotEmpty) {
    return Text(emoji, style: TextStyle(fontSize: size));
  }
  if (codePoint != null && codePoint.isNotEmpty) {
    final int? parsed = int.tryParse(codePoint);
    final icon = parsed != null ? _iconByCodePoint[parsed] : null;
    if (icon != null) {
      return Icon(icon, size: size, color: color);
    }
  }
  return Icon(Icons.folder_outlined, size: size, color: color);
}

Future<IconPickerResult?> showIconPickerSheet(BuildContext context) {
  return showModalBottomSheet<IconPickerResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _IconPickerSheet(),
  );
}

class _IconPickerSheet extends StatefulWidget {
  const _IconPickerSheet();

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _emojiController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _pickEmoji(String emoji) {
    Haptics.light();
    Navigator.of(context).pop(IconPickerResult(emoji: emoji));
  }

  void _pickIcon(IconData icon) {
    Haptics.light();
    Navigator.of(context).pop(IconPickerResult(codePoint: icon.codePoint));
  }

  void _clear() {
    Haptics.selection();
    Navigator.of(context).pop(const IconPickerResult());
  }

  void _submitCustomEmoji() {
    final raw = _emojiController.text.trim();
    if (raw.isEmpty) return;
    // Use whatever the user typed. Takes the leading grapheme only so pasted
    // multi-emoji strings ("🔥🔥") render as a single slot — cheap
    // approximation; good enough for a picker.
    final leading = raw.characters.isEmpty ? raw : raw.characters.first;
    _pickEmoji(leading);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Emoji'),
                Tab(text: 'Icon'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEmojiTab(theme),
                  _buildIconTab(theme),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear icon'),
                      onPressed: _clear,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 12),
          TextField(
            controller: _emojiController,
            style: const TextStyle(fontSize: 24),
            decoration: InputDecoration(
              hintText: 'Type or paste any emoji…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                onPressed: _submitCustomEmoji,
              ),
            ),
            onSubmitted: (_) => _submitCustomEmoji(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Quick picks', style: theme.textTheme.labelLarge),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _quickEmojis.length,
              itemBuilder: (_, i) {
                final emoji = _quickEmojis[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickEmoji(emoji),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _curatedIcons.length,
        itemBuilder: (_, i) {
          final icon = _curatedIcons[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pickIcon(icon),
            child: Center(
              child: Icon(icon, size: 28, color: theme.iconTheme.color),
            ),
          );
        },
      ),
    );
  }
}
