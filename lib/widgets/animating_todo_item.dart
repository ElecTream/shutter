import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_notifier.dart';
import 'strikethrough_painter.dart';

class AnimatingTodoItem extends StatefulWidget {
  final String text;
  final VoidCallback onAnimationEnd;

  const AnimatingTodoItem({
    super.key,
    required this.text,
    required this.onAnimationEnd,
  });

  @override
  State<AnimatingTodoItem> createState() => _AnimatingTodoItemState();
}

class _AnimatingTodoItemState extends State<AnimatingTodoItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _strikeAnimation;
  late Animation<double> _foldUpAnimation;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final animationSpeed = settings.animationSpeed;

    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: animationSpeed));

    _strikeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeIn)),
    );
    
    _foldUpAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)),
    );

    _controller.forward().whenComplete(() {
      if (mounted) {
        widget.onAnimationEnd();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final customTheme = settings.currentTheme;

    return FadeTransition(
      opacity: _foldUpAnimation,
      child: SizeTransition(
        sizeFactor: _foldUpAnimation,
        axisAlignment: -1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              // --- FIX: Removed incorrect .toColor() call ---
              color: customTheme.taskBackgroundColor,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: settings.taskHeight),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Text(widget.text, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17)),
                    AnimatedBuilder(
                      animation: _strikeAnimation,
                      // --- FIX: Removed incorrect .toColor() call ---
                      builder: (context, child) => CustomPaint(
                        painter: StrikethroughPainter(progress: _strikeAnimation.value, color: customTheme.strikethroughColor),
                        child: const SizedBox(width: double.infinity, height: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: theme.dividerColor, thickness: 1),
          ],
        ),
      ),
    );
  }
}

