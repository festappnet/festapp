import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../ticket_layout_strings.dart';
import 'ticket_color_suggestions.dart';

typedef TicketCanvasColor = ({String color, double opacity});

class TicketCanvasColorDialog extends StatefulWidget {
  final String value;
  final double opacity;
  final List<String> usedColors;
  final ui.Image? image;
  final ValueChanged<TicketCanvasColor>? onPreview;
  const TicketCanvasColorDialog(
      {super.key,
      required this.value,
      this.opacity = 1,
      this.usedColors = const [],
      this.image,
      this.onPreview});
  @override
  State<TicketCanvasColorDialog> createState() =>
      _TicketCanvasColorDialogState();
}

class _TicketCanvasColorDialogState extends State<TicketCanvasColorDialog> {
  late double opacity = widget.value == 'transparent' ? 0 : widget.opacity;
  late Color color = Color(int.parse(
      'ff${widget.value == 'transparent' ? 'FFFFFF' : widget.value}',
      radix: 16));
  late final hex = TextEditingController(
      text: widget.value == 'transparent' ? 'FFFFFF' : widget.value);
  bool get valid => RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(hex.text);
  TicketCanvasColor get value =>
      (color: hex.text.toUpperCase(), opacity: opacity);
  void preview() {
    if (valid) widget.onPreview?.call(value);
  }

  void pick(Color next) => setState(() {
        color = next;
        hex.text = (next.toARGB32() & 0xffffff)
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase();
        preview();
      });
  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(TicketLayoutStrings.canvasColor),
          content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    TicketColorSuggestions(
                        usedColors: widget.usedColors,
                        image: widget.image,
                        selected: hex.text,
                        onSelect: pick),
                    ColorPicker(
                        pickerColor: color,
                        enableAlpha: false,
                        labelTypes: const [],
                        portraitOnly: true,
                        pickerAreaHeightPercent: .7,
                        onColorChanged: pick),
                    TextField(
                        controller: hex,
                        maxLength: 6,
                        decoration: const InputDecoration(
                            labelText: 'HEX', prefixText: '#'),
                        onChanged: (_) => setState(() {
                              if (valid) {
                                color = Color(
                                    int.parse('ff${hex.text}', radix: 16));
                                preview();
                              }
                            })),
                    Text(
                        '${TicketLayoutStrings.transparency}: ${((1 - opacity) * 100).round()} %'),
                    Slider(
                        value: 1 - opacity,
                        min: 0,
                        max: 1,
                        divisions: 100,
                        label: '${((1 - opacity) * 100).round()} %',
                        onChanged: (v) => setState(() {
                              opacity = 1 - v;
                              preview();
                            })),
                    Text(TicketLayoutStrings.transparentHint,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(TicketLayoutStrings.cancel)),
            FilledButton(
                onPressed: valid ? () => Navigator.pop(context, value) : null,
                child: Text(TicketLayoutStrings.apply))
          ]);
}
