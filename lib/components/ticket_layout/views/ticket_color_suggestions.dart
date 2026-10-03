import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/ticket_layout.dart';
import '../ticket_image_palette.dart';
import '../ticket_layout_strings.dart';

class TicketColorSuggestions extends StatefulWidget {
  final List<String> usedColors;
  final ui.Image? image;
  final String selected;
  final ValueChanged<Color> onSelect;
  const TicketColorSuggestions(
      {super.key,
      required this.usedColors,
      this.image,
      required this.selected,
      required this.onSelect});
  @override
  State<TicketColorSuggestions> createState() => _TicketColorSuggestionsState();
}

class _TicketColorSuggestionsState extends State<TicketColorSuggestions> {
  List<String> imageColors = [];
  @override
  void initState() {
    super.initState();
    extract();
  }

  Future<void> extract() async {
    final image = widget.image;
    if (image == null) return;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 96, 96),
        Paint());
    final picture = recorder.endRecording();
    final sample = await picture.toImage(96, 96);
    picture.dispose();
    final bytes = await sample.toByteData(format: ui.ImageByteFormat.rawRgba);
    sample.dispose();
    if (bytes == null || !mounted) return;
    setState(() => imageColors = ticketArtworkSuggestions(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)));
  }

  Widget row(String label, Iterable<String> values) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
                spacing: 8,
                children: values
                    .where((v) => RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(v))
                    .map((v) => v.toUpperCase())
                    .toSet()
                    .map((v) {
                  final color = Color(int.parse('ff$v', radix: 16));
                  return IconButton(
                      tooltip: '#$v',
                      onPressed: () => widget.onSelect(color),
                      iconSize: 32,
                      icon: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey)),
                          child: widget.selected.toUpperCase() == v
                              ? Icon(Icons.check,
                                  size: 22,
                                  color: color.computeLuminance() > .5
                                      ? Colors.black
                                      : Colors.white)
                              : null));
                }).toList())),
        const SizedBox(height: 8)
      ]);
  @override
  Widget build(BuildContext context) => Column(children: [
        row(TicketLayoutStrings.usedColors, widget.usedColors),
        if (imageColors.isNotEmpty)
          row(TicketLayoutStrings.imageColors, imageColors),
        row(TicketLayoutStrings.basicColors, ticketQrColors)
      ]);
}
