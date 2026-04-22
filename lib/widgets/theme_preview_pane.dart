import 'dart:io';
import 'package:flutter/material.dart';
import '../models/custom_theme.dart';

/// Stateless preview of a [CustomTheme] — renders a mini app-bar, three
/// sample task tiles (including one strikethrough), and an input area using
/// exactly the colors the theme defines. Used by the theme editor for live
/// feedback and by the list-theme screen to audition a theme.
class ThemePreviewPane extends StatelessWidget {
  final CustomTheme theme;
  final double height;

  const ThemePreviewPane({
    super.key,
    required this.theme,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    final bgImage = theme.backgroundImagePath;
    final hasBg = bgImage != null && bgImage.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.primaryColor,
          image: hasBg
              ? DecorationImage(
                  image: FileImage(File(bgImage)),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.2),
                    BlendMode.darken,
                  ),
                )
              : null,
        ),
        child: Column(
          children: [
            _MiniAppBar(theme: theme),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Column(
                  children: [
                    _TaskRow(theme: theme, text: 'Write up design doc'),
                    const SizedBox(height: 6),
                    _TaskRow(
                      theme: theme,
                      text: 'Reply to pending PRs',
                      done: true,
                    ),
                    const SizedBox(height: 6),
                    _TaskRow(theme: theme, text: 'Take out the trash'),
                  ],
                ),
              ),
            ),
            _InputArea(theme: theme),
          ],
        ),
      ),
    );
  }
}

class _MiniAppBar extends StatelessWidget {
  final CustomTheme theme;
  const _MiniAppBar({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.primaryColor,
        border: Border(
          bottom: BorderSide(
            color: theme.secondaryColor.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.menu, color: theme.taskTextColor, size: 18),
          const SizedBox(width: 10),
          Text(
            theme.name,
            style: TextStyle(
              color: theme.taskTextColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Icon(Icons.more_vert, color: theme.taskTextColor, size: 18),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final CustomTheme theme;
  final String text;
  final bool done;
  const _TaskRow({required this.theme, required this.text, this.done = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.taskBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: done
                ? theme.secondaryColor
                : theme.taskTextColor.withValues(alpha: 0.5),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.taskTextColor,
                fontSize: 13,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: theme.strikethroughColor,
                decorationThickness: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputArea extends StatelessWidget {
  final CustomTheme theme;
  const _InputArea({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: theme.inputAreaColor),
      child: Row(
        children: [
          Icon(Icons.add, color: theme.secondaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add a task...',
              style: TextStyle(
                color: theme.taskTextColor.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
