import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../ticket_layout_strings.dart';

class TicketCanvasColorDialog extends StatefulWidget {
  final String value;
  const TicketCanvasColorDialog({super.key, required this.value});
  @override
  State<TicketCanvasColorDialog> createState() =>
      _TicketCanvasColorDialogState();
}

class _TicketCanvasColorDialogState extends State<TicketCanvasColorDialog> {
  late bool transparent = widget.value == 'transparent';
  late Color color =
      Color(int.parse('ff${transparent ? 'FFFFFF' : widget.value}', radix: 16));
  late final hex =
      TextEditingController(text: transparent ? 'FFFFFF' : widget.value);
  bool get valid => RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(hex.text);
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
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(TicketLayoutStrings.transparent),
                        value: transparent,
                        onChanged: (v) => setState(() => transparent = v)),
                    if (transparent)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(TicketLayoutStrings.transparentHint))
                    else ...[
                      ColorPicker(
                          pickerColor: color,
                          enableAlpha: false,
                          labelTypes: const [],
                          portraitOnly: true,
                          pickerAreaHeightPercent: .7,
                          onColorChanged: (value) => setState(() {
                                color = value;
                                hex.text = (value.toARGB32() & 0xffffff)
                                    .toRadixString(16)
                                    .padLeft(6, '0')
                                    .toUpperCase();
                              })),
                      TextField(
                          controller: hex,
                          maxLength: 6,
                          decoration: const InputDecoration(
                              labelText: 'HEX', prefixText: '#'),
                          onChanged: (_) => setState(() {
                                if (valid)
                                  color = Color(
                                      int.parse('ff${hex.text}', radix: 16));
                              })),
                    ]
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(TicketLayoutStrings.cancel)),
            FilledButton(
                onPressed: transparent || valid
                    ? () => Navigator.pop(context,
                        transparent ? 'transparent' : hex.text.toUpperCase())
                    : null,
                child: Text(TicketLayoutStrings.apply))
          ]);
}
