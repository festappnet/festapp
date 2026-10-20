import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'editor_image_palette.dart';
import 'editor_dialog.dart';

/// RGB plus unquantized opacity. Only RGBA serialization rounds alpha to a byte.
@immutable
class EditorColorValue {
  EditorColorValue({required String hex, this.opacity = 1})
    : hex = hex.replaceFirst(RegExp(r'^#'), '').toUpperCase() {
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(this.hex)) {
      throw FormatException('Expected six RGB hex digits', hex);
    }
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw ArgumentError.value(
        opacity,
        'opacity',
        'Must be finite and in 0-1',
      );
    }
  }
  factory EditorColorValue.fromRgba(String rgba) {
    if (!RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(rgba)) {
      throw FormatException('Expected #RRGGBBAA', rgba);
    }
    return EditorColorValue(
      hex: rgba.substring(1, 7),
      opacity: int.parse(rgba.substring(7), radix: 16) / 255,
    );
  }
  final String hex;
  final double opacity;
  Color get color =>
      Color(int.parse('FF$hex', radix: 16)).withValues(alpha: opacity);
  String get rgba =>
      '#$hex${(opacity * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

@immutable
class EditorColorResult {
  const EditorColorResult({required this.primary, this.secondary});
  final EditorColorValue primary;
  final EditorColorValue? secondary;
}

class EditorColorSwatch extends StatelessWidget {
  const EditorColorSwatch({
    super.key,
    required this.value,
    this.selected = false,
    this.size = 28,
  });
  final EditorColorValue value;
  final bool selected;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _SwatchPainter(
        value.color,
        selected
            ? Theme.of(context).colorScheme.primary
            : const Color(0xff98a2b3),
        selected,
      ),
    ),
  );
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.color, this.border, this.selected);
  final Color color, border;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(5),
    );
    canvas.save();
    canvas.clipRRect(shape);
    for (var y = 0.0; y < size.height; y += 7) {
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 7, 7),
          Paint()
            ..color = ((x / 7).floor() + (y / 7).floor()).isEven
                ? Colors.white
                : const Color(0xffdfe4eb),
        );
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    canvas.restore();
    canvas.drawRRect(
      shape.deflate(selected ? 1.5 : .5),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.border != border ||
      oldDelegate.selected != selected;
}

/// A draft-only single or paired color editor. Cancel returns null; hosts decide
/// whether and how to restore any optional live preview.
class EditorColorDialog extends StatefulWidget {
  const EditorColorDialog({
    super.key,
    required this.value,
    this.secondaryValue,
    this.title = 'Choose color',
    this.primaryLabel = 'Foreground',
    this.secondaryLabel = 'Background',
    this.usedColors = const [],
    this.image,
    this.enableOpacity = true,
    this.translate,
    this.validator,
    this.previewBuilder,
    this.onPreview,
    this.dialogBuilder,
    this.basicColors,
  });
  final EditorColorValue value;
  final EditorColorValue? secondaryValue;
  final String title, primaryLabel, secondaryLabel;
  final List<String> usedColors;
  final ui.Image? image;
  final bool enableOpacity;
  final String Function(String)? translate;
  final String? Function(EditorColorResult)? validator;
  final Widget Function(BuildContext, EditorColorResult)? previewBuilder;
  final ValueChanged<EditorColorResult>? onPreview;
  final Widget Function(BuildContext, AlertDialog)? dialogBuilder;
  final List<String>? basicColors;
  @override
  State<EditorColorDialog> createState() => _EditorColorDialogState();
}

class _EditorColorDialogState extends State<EditorColorDialog> {
  late EditorColorValue _primary = widget.value;
  late EditorColorValue? _secondary = widget.secondaryValue;
  late final _hex = TextEditingController(text: _primary.hex);
  bool _secondaryActive = false;
  List<String> _artwork = const [];
  String? _inputError;
  EditorColorValue get _active => _secondaryActive ? _secondary! : _primary;
  EditorColorResult get _result =>
      EditorColorResult(primary: _primary, secondary: _secondary);
  String tr(String text) => widget.translate?.call(text) ?? text;
  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  Future<void> _loadArtwork() async {
    final image = widget.image;
    if (image == null) return;
    ui.Image? sample;
    ui.Picture? picture;
    try {
      final scale = math.min(1.0, 96 / math.max(image.width, image.height));
      final width = math.max(1, (image.width * scale).round());
      final height = math.max(1, (image.height * scale).round());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.low,
      );
      picture = recorder.endRecording();
      sample = await picture.toImage(width, height);
      final data = await sample.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null && mounted) {
        setState(
          () => _artwork = editorArtworkSuggestions(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        );
      }
    } catch (_) {
      /* Optional artwork never blocks manual color selection. */
    } finally {
      sample?.dispose();
      picture?.dispose();
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _change(EditorColorValue value, {bool updateText = true}) {
    setState(() {
      if (_secondaryActive) {
        _secondary = value;
      } else {
        _primary = value;
      }
      _inputError = null;
      if (updateText) _hex.text = value.hex;
    });
    widget.onPreview?.call(_result);
  }

  Widget _palette(String title, List<String> values) {
    final colors = values
        .map((v) => v.replaceFirst('#', '').toUpperCase())
        .where((v) => RegExp(r'^[0-9A-F]{6}$').hasMatch(v))
        .toSet();
    if (colors.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(title), style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 6,
              children: [
                for (final hex in colors)
                  Tooltip(
                    message: '#$hex',
                    child: Semantics(
                      label: '${tr('Set color')} #$hex',
                      button: true,
                      child: InkWell(
                        key: ValueKey('editor-color-$title-$hex'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _change(
                          EditorColorValue(hex: hex, opacity: _active.opacity),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: EditorColorSwatch(
                            value: EditorColorValue(hex: hex),
                            selected: hex == _active.hex,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _inputError ?? widget.validator?.call(_result);
    final dialog = AlertDialog(
      title: Text(tr(widget.title)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _palette('Used colors', widget.usedColors),
              _palette('From artwork', _artwork),
              _palette(
                'Basic colors',
                widget.basicColors ??
                    const [
                      '182230',
                      '667085',
                      'CBD5E1',
                      'FFFFFF',
                      '2563EB',
                      '0F766E',
                      '16A34A',
                      'F59E0B',
                      'DC2626',
                      'DB2777',
                      '7C3AED',
                      '000000',
                    ],
              ),

              if (_secondary != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text(tr(widget.primaryLabel)),
                          avatar: EditorColorSwatch(value: _primary, size: 18),
                          selected: !_secondaryActive,
                          onSelected: (_) => setState(() {
                            _secondaryActive = false;
                            _hex.text = _active.hex;
                            _inputError = null;
                          }),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Swap colors'),
                        onPressed: () {
                          setState(() {
                            final previous = _primary;
                            _primary = _secondary!;
                            _secondary = previous;
                            _hex.text = _active.hex;
                            _inputError = null;
                          });
                          widget.onPreview?.call(_result);
                        },
                        icon: const Icon(Icons.swap_horiz),
                      ),
                      Expanded(
                        child: ChoiceChip(
                          label: Text(tr(widget.secondaryLabel)),
                          avatar: EditorColorSwatch(
                            value: _secondary!,
                            size: 18,
                          ),
                          selected: _secondaryActive,
                          onSelected: (_) => setState(() {
                            _secondaryActive = true;
                            _hex.text = _active.hex;
                            _inputError = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) => ColorPicker(
                  key: ValueKey(_secondaryActive),
                  pickerColor: _active.color,
                  onColorChanged: (color) => _change(
                    EditorColorValue(
                      hex: color
                          .toARGB32()
                          .toRadixString(16)
                          .padLeft(8, '0')
                          .substring(2),
                      opacity: _active.opacity,
                    ),
                  ),
                  enableAlpha: false,
                  portraitOnly: true,
                  labelTypes: const [],
                  displayThumbColor: true,
                  colorPickerWidth: constraints.maxWidth,
                  pickerAreaHeightPercent: .48,
                  pickerAreaBorderRadius: BorderRadius.circular(6),
                ),
              ),
              TextField(
                controller: _hex,
                decoration: InputDecoration(
                  labelText: tr('RGB hex'),
                  prefixText: '#',
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(8),
                    child: EditorColorSwatch(value: _active),
                  ),
                ),
                onSubmitted: (_) {
                  if (_inputError == null &&
                      widget.validator?.call(_result) == null) {
                    Navigator.pop(context, _result);
                  }
                },
                onChanged: (value) {
                  try {
                    _change(
                      EditorColorValue(hex: value, opacity: _active.opacity),
                      updateText: false,
                    );
                  } on FormatException {
                    setState(
                      () => _inputError = tr('Enter six RGB hex digits.'),
                    );
                  }
                },
              ),
              if (widget.enableOpacity) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text(tr('Opacity'))),
                    Text('${(_active.opacity * 100).round()}%'),
                  ],
                ),
                Slider(
                  value: _active.opacity,
                  label: '${(_active.opacity * 100).round()}%',
                  onChanged: (value) => _change(
                    EditorColorValue(hex: _active.hex, opacity: value),
                  ),
                ),
              ],
              if (widget.previewBuilder != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: widget.previewBuilder!(context, _result),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: error == null
              ? () => Navigator.pop(context, _result)
              : null,
          child: Text(tr('Apply')),
        ),
      ],
    );
    return widget.dialogBuilder?.call(context, dialog) ??
        EditorDialogDismissal(child: dialog);
  }
}
