import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_notifier.dart';

class SavedColorsView extends StatefulWidget {
  final ValueChanged<Color> onColorSelected;
  final Function(bool) onDragUpdate;

  const SavedColorsView({
    super.key,
    required this.onColorSelected,
    required this.onDragUpdate,
  });

  @override
  State<SavedColorsView> createState() => _SavedColorsViewState();
}

class _SavedColorsViewState extends State<SavedColorsView> {
  // This local list is the single source of truth FOR THE ANIMATION.
  // It is updated in real-time during a drag.
  List<Color> _localColors = [];
  Color? _draggedColor;

  @override
  void initState() {
    super.initState();
    // Initialize the local list from the provider on first build.
    _localColors = List.from(context.read<SettingsNotifier>().savedColors);
  }
  
  // This is the key to keeping the local state in sync with the provider.
  // It listens for changes (like a color being added/deleted) and updates the
  // local animation list, but only when a drag is NOT in progress.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draggedColor == null) {
      _localColors = List.from(context.watch<SettingsNotifier>().savedColors);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsNotifier>();
    final theme = Theme.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      const double itemSize = 50.0;
      const double itemSpacing = 10.0;
      final int crossAxisCount = (constraints.maxWidth / (itemSize + itemSpacing)).floor().clamp(1, 10);
      
      final int itemCount = _localColors.length;
      final rowCount = itemCount > 0 ? ((itemCount - 1) / crossAxisCount).floor() + 1 : 1;
      final calculatedHeight = rowCount * (itemSize + itemSpacing) + itemSpacing;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: calculatedHeight.clamp(itemSize + itemSpacing * 2, 300.0),
        child: _localColors.isEmpty
            ? const Center(child: Text('You have no saved colors.'))
            : DragTarget<Color>(
                builder: (context, candidateData, rejectedData) {
                  return Stack(
                    children: List.generate(_localColors.length, (index) {
                      final color = _localColors[index];
                      
                      final col = index % crossAxisCount;
                      final row = (index / crossAxisCount).floor();
                      final left = col * (itemSize + itemSpacing);
                      final top = row * (itemSize + itemSpacing);

                      // The dragged color is rendered on top by the Draggable's feedback widget.
                      // Here, we leave its space empty by making it transparent.
                      final isDraggingThis = color == _draggedColor;

                      return AnimatedPositioned(
                        // CRITICAL FIX: Add a unique key to each item. This is essential
                        // for Flutter's animation system to correctly track which item is which
                        // when the list is reordered, preventing the "blinking" ghost image.
                        key: ValueKey(color),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        left: left,
                        top: top,
                        child: AnimatedOpacity(
                          // By setting the duration to zero, the item disappears and
                          // reappears instantly, removing the "ghost" effect.
                          duration: Duration.zero,
                          opacity: isDraggingThis ? 0.0 : 1.0,
                          child: _buildDraggableColor(settings, theme, color),
                        ),
                      );
                    }),
                  );
                },
                onMove: (details) {
                  if (_draggedColor == null) return;
                  
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final localPos = box.globalToLocal(details.offset);
                  final col = (localPos.dx / (itemSize + itemSpacing)).round().clamp(0, crossAxisCount - 1);
                  final row = (localPos.dy / (itemSize + itemSpacing)).floor();
                  final newIndex = (row * crossAxisCount + col).clamp(0, _localColors.length - 1);
                  
                  final oldIndex = _localColors.indexOf(_draggedColor!);
                  if (oldIndex != -1 && oldIndex != newIndex) {
                    setState(() {
                      // STEP 1: Update the LOCAL LIST in real-time to drive the animation.
                      final item = _localColors.removeAt(oldIndex);
                      _localColors.insert(newIndex, item);
                    });
                  }
                },
              ),
      );
    });
  }

  Widget _buildDraggableColor(SettingsNotifier settings, ThemeData theme, Color color) {
    // This widget is the visible circle in the grid.
    final colorCircle = GestureDetector(
      onTap: () => widget.onColorSelected(color),
      child: _buildColorCircle(color, theme),
    );

    return Draggable<Color>(
      data: color,
      onDragStarted: () {
        HapticFeedback.lightImpact();
        setState(() => _draggedColor = color);
        widget.onDragUpdate(true);
      },
      onDragEnd: (details) {
        // --- FIX: Only update the color order if the drop was NOT accepted ---
        // by a DragTarget (like the DeleteDropZone). This prevents the old list
        // from being saved after a color has been successfully deleted.
        if (!details.wasAccepted && _draggedColor != null) {
          settings.updateSavedColorsOrder(List.from(_localColors));
        }
        
        // Reset local drag state regardless of where the drop happened.
        if (mounted) {
          setState(() {
            _draggedColor = null;
          });
          widget.onDragUpdate(false);
        }
      },
      feedback: _buildColorCircle(color, theme, isDragging: true),
      
      // GHOSTING FIX: By default, Draggable leaves an empty space where the
      // child was. This conflicts with our AnimatedOpacity, which is trying to
      // fade the child out smoothly. By setting childWhenDragging to be the same
      // as the child, we let the AnimatedOpacity handle the hiding animation
      // without the Draggable suddenly removing it, which caused the flicker.
      childWhenDragging: colorCircle,

      // The child is what's visible in the grid before a drag starts.
      child: colorCircle,
    );
  }

  Widget _buildColorCircle(Color color, ThemeData theme, {bool isDragging = false}) {
    final circle = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: theme.dividerColor, width: 1),
        boxShadow: isDragging
            ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)]
            : [],
      ),
    );

    // When dragging, we wrap the circle in a Material widget. This prevents
    // the default Draggable behavior, which can sometimes apply unwanted
    // transparency or styling, ensuring our dragged item is solid.
    if (isDragging) {
      return Material(
        color: Colors.transparent,
        child: circle,
      );
    }

    return circle;
  }
}

