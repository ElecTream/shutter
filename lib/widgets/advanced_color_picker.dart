import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_notifier.dart';
import 'delete_drop_zone.dart';
import 'saved_colors_view.dart';

// A custom painter for the checkerboard background, used for the Alpha slider.
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rectSize = size.height / 2;
    for (int i = 0; i * rectSize < size.width; i++) {
      for (int j = 0; j * rectSize < size.height; j++) {
        paint.color = (i + j) % 2 == 0 ? Colors.white : Colors.grey[300]!;
        canvas.drawRect(Rect.fromLTWH(i * rectSize, j * rectSize, rectSize, rectSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// A custom thumb shape that is semi-transparent with a high-contrast border.
class _CustomThumbShape extends RoundSliderThumbShape {
  final Color thumbColor;
  final Color borderColor;

  const _CustomThumbShape({
    this.thumbColor = Colors.white,
    this.borderColor = Colors.black,
    super.enabledThumbRadius = 12.0,
  });

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint thumbPaint = Paint()..color = thumbColor.withOpacity(0.5);
    canvas.drawCircle(center, enabledThumbRadius, thumbPaint);
    final Paint borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, enabledThumbRadius, borderPaint);
  }
}

class AdvancedColorPicker extends StatefulWidget {
  final Color initialColor;
  const AdvancedColorPicker({super.key, required this.initialColor});

  @override
  State<AdvancedColorPicker> createState() => _AdvancedColorPickerState();
}

class _AdvancedColorPickerState extends State<AdvancedColorPicker> {
  late HSVColor _hsvColor;
  late TextEditingController _rController, _gController, _bController, _aController;
  bool _isPaletteView = false;
  bool _isDraggingInPalette = false;

  @override
  void initState() {
    super.initState();
    _updateColor(widget.initialColor);
  }

  void _updateColor(Color color, {bool updateHsv = true}) {
    if (updateHsv) _hsvColor = HSVColor.fromColor(color);
    _rController = TextEditingController(text: color.red.toString());
    _gController = TextEditingController(text: color.green.toString());
    _bController = TextEditingController(text: color.blue.toString());
    _aController = TextEditingController(text: color.alpha.toString());
  }

  void _onColorChanged(HSVColor newColor) {
    setState(() {
      _hsvColor = newColor;
      final color = _hsvColor.toColor();
      _rController.text = color.red.toString();
      _gController.text = color.green.toString();
      _bController.text = color.blue.toString();
      _aController.text = color.alpha.toString();
    });
  }

  void _onRgbaChanged() {
    final r = int.tryParse(_rController.text) ?? 0;
    final g = int.tryParse(_gController.text) ?? 0;
    final b = int.tryParse(_bController.text) ?? 0;
    final a = int.tryParse(_aController.text) ?? 0;
    final newColor = Color.fromARGB(a.clamp(0, 255), r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    setState(() => _hsvColor = HSVColor.fromColor(newColor));
  }
  
  void _onPaletteDragUpdate(bool isDragging) {
    if (_isDraggingInPalette != isDragging) {
      setState(() => _isDraggingInPalette = isDragging);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color;
    final currentColor = _hsvColor.toColor();
    final settings = context.read<SettingsNotifier>();

    return AlertDialog(
      title: Text('Select a Color', textAlign: TextAlign.center, style: TextStyle(color: textColor)),
      actionsAlignment: MainAxisAlignment.center,
      content: SizedBox(
        width: 450,
        child: AnimatedSwitcher(
          duration: Duration.zero,
          child: _isPaletteView
              ? _buildPaletteView(settings)
              : _buildPickerView(currentColor, theme),
        ),
      ),
      actions: [
        if (!_isPaletteView)
          TextButton(
            onPressed: () {
              settings.addSavedColor(currentColor);
              HapticFeedback.lightImpact();
            },
            child: const Text('Save Color'),
          ),
        TextButton(
          style: ButtonStyle(
            splashFactory: NoSplash.splashFactory,
            foregroundColor: MaterialStateProperty.all(theme.colorScheme.primary),
            overlayColor: MaterialStateProperty.all(Colors.transparent),
          ),
          onPressed: () => setState(() => _isPaletteView = !_isPaletteView),
          child: Text(_isPaletteView ? 'Color Picker' : 'My Colors'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(currentColor),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildPickerView(Color currentColor, ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('picker'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: currentColor,
              shape: BoxShape.circle,
              border: Border.all(color: theme.dividerColor, width: 2),
            ),
          ),
          const SizedBox(height: 20),
          _buildSlider('Hue', _hsvColor.hue, 360, (v) => _onColorChanged(_hsvColor.withHue(v)), _buildHueTrack()),
          _buildSlider('Saturation', _hsvColor.saturation, 1, (v) => _onColorChanged(_hsvColor.withSaturation(v)), _buildSaturationTrack()),
          _buildSlider('Brightness', _hsvColor.value, 1, (v) => _onColorChanged(_hsvColor.withValue(v)), _buildValueTrack()),
          _buildSlider('Transparency', _hsvColor.alpha, 1, (v) => _onColorChanged(_hsvColor.withAlpha(v)), _buildAlphaTrack()),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildRgbaInput('R', _rController, theme),
              _buildRgbaInput('G', _gController, theme),
              _buildRgbaInput('B', _bController, theme),
              _buildRgbaInput('A', _aController, theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteView(SettingsNotifier settings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SavedColorsView(
          key: const ValueKey('palette'),
          onColorSelected: (color) {
            HapticFeedback.lightImpact();
            setState(() {
              _updateColor(color);
              _isPaletteView = false;
            });
          },
          onDragUpdate: _onPaletteDragUpdate,
        ),
        DeleteDropZone(
          isDragInProgress: _isDraggingInPalette,
          onColorDropped: (color) {
            HapticFeedback.mediumImpact();
            settings.removeSavedColor(color);
            // This callback ensures the drag state is reset after deletion.
            _onPaletteDragUpdate(false);
          },
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double max, ValueChanged<double> onChanged, Widget track) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final thumbFillColor = isDark ? Colors.white : Colors.grey.shade800;
    final thumbBorderColor = isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.5);

    return Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 16),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 20,
              thumbShape: _CustomThumbShape(thumbColor: thumbFillColor, borderColor: thumbBorderColor),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              trackShape: const RoundedRectSliderTrackShape(),
              overlayColor: thumbFillColor.withOpacity(0.2),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(height: 20, child: track)),
                Slider(
                  value: value, max: max, onChanged: onChanged,
                  activeColor: Colors.transparent, inactiveColor: Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRgbaInput(String label, TextEditingController controller, ThemeData theme) {
    return SizedBox(
      width: 60,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _onRgbaChanged(),
      ),
    );
  }

  Widget _buildHueTrack() => Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000)])));
  Widget _buildSaturationTrack() => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [HSVColor.fromAHSV(1, _hsvColor.hue, 0, _hsvColor.value).toColor(), HSVColor.fromAHSV(1, _hsvColor.hue, 1, _hsvColor.value).toColor()])));
  Widget _buildValueTrack() => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [HSVColor.fromAHSV(1, _hsvColor.hue, _hsvColor.saturation, 0).toColor(), HSVColor.fromAHSV(1, _hsvColor.hue, _hsvColor.saturation, 1).toColor()])));
  Widget _buildAlphaTrack() => CustomPaint(painter: _CheckerboardPainter(), child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_hsvColor.toColor().withOpacity(0), _hsvColor.toColor().withOpacity(1)]))));
}

