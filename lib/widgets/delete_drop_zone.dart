import 'package:flutter/material.dart';

class DeleteDropZone extends StatefulWidget {
  final bool isDragInProgress;
  final Function(Color) onColorDropped;

  const DeleteDropZone({
    super.key,
    required this.isDragInProgress,
    required this.onColorDropped,
  });

  @override
  State<DeleteDropZone> createState() => _DeleteDropZoneState();
}

class _DeleteDropZoneState extends State<DeleteDropZone> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // --- FIX: Get the foreground color from the AppBar theme to match the title bar text ---
    final appBarForegroundColor = theme.appBarTheme.foregroundColor ??
        (theme.brightness == Brightness.dark ? Colors.white : Colors.black);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.isDragInProgress ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !widget.isDragInProgress,
        child: DragTarget<Color>(
          builder: (context, candidateData, rejectedData) {
            // --- FIX: Use AnimatedContainer for smooth color and border transitions ---
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 100,
              margin: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                // --- FIX: Add a subtle background color on hover ---
                color: _isDragOver ? Colors.red.withOpacity(0.1) : Colors.transparent,
                // --- FIX: Add a visible, theme-aware border for the hitbox ---
                border: Border.all(
                  color: _isDragOver
                      ? Colors.red.shade400
                      : appBarForegroundColor.withOpacity(0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: AnimatedScale(
                  scale: _isDragOver ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.delete_outline,
                    size: _isDragOver ? 42.0 : 36.0,
                    // --- FIX: Update icon colors to be theme-aware ---
                    color: _isDragOver ? Colors.red.shade600 : appBarForegroundColor,
                  ),
                ),
              ),
            );
          },
          onWillAcceptWithDetails: (details) {
            setState(() {
              _isDragOver = true;
            });
            return true;
          },
          onAcceptWithDetails: (details) {
            widget.onColorDropped(details.data);
            setState(() {
              _isDragOver = false;
            });
          },
          onLeave: (data) {
            setState(() {
              _isDragOver = false;
            });
          },
        ),
      ),
    );
  }
}

