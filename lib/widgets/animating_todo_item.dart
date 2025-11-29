import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../providers/settings_notifier.dart';
import 'strikethrough_painter.dart';

class AnimatingTodoItem extends StatefulWidget {
  final Task task;
  final bool hasReminder;
  final VoidCallback onAnimationEnd;

  const AnimatingTodoItem({
    super.key,
    required this.task,
    required this.hasReminder,
    required this.onAnimationEnd,
  });

  @override
  State<AnimatingTodoItem> createState() => _AnimatingTodoItemState();
}

class _AnimatingTodoItemState extends State<AnimatingTodoItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _strikeAnimation;
  late Animation<double> _foldUpAnimation;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsNotifier>(context, listen: false);
    final animationSpeed = settings.animationSpeed;

    _controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: animationSpeed));

    _strikeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.7, curve: Curves.easeOut)),
    );

    _foldUpAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.1, 1.0, curve: Curves.easeOut)),
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
    final hasReminder = widget.hasReminder;

    // --- FIX: MATCH STANDARDIZED HEIGHT ---
    // Matching the 72.0 base height used in TodoItem
    const double standardBaseHeight = 72.0;
    final double calculatedHeight = standardBaseHeight * settings.taskHeight;

    return SizeTransition(
      sizeFactor: _foldUpAnimation,
      axis: Axis.vertical,
      axisAlignment: -1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: customTheme.taskBackgroundColor,
            child: Container(
              height: calculatedHeight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      // Vertically center content in the standardized box
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Text(
                              widget.task.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _strikeAnimation,
                              builder: (context, child) => CustomPaint(
                                painter: StrikethroughPainter(
                                    progress: _strikeAnimation.value,
                                    color: customTheme.strikethroughColor),
                                child: const SizedBox(
                                    width: double.infinity, height: 20),
                              ),
                            ),
                          ],
                        ),
                        if (hasReminder) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: customTheme.secondaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Reminder completed',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  color: customTheme.secondaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          hasReminder
                              ? Icons.notifications_off
                              : Icons.notifications_none,
                          size: 20,
                        ),
                        color: hasReminder
                            ? theme.colorScheme.error
                            : theme.iconTheme.color?.withOpacity(0.6),
                        tooltip: hasReminder
                            ? 'Remove reminder'
                            : 'Set reminder',
                        onPressed: null,
                      ),
                      Icon(
                        Icons.drag_handle,
                        color: theme.iconTheme.color?.withOpacity(0.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor, thickness: 1),
        ],
      ),
    );
  }
}