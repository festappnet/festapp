import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import '../ticket_layout_strings.dart';
import 'ticket_color_suggestions.dart';

typedef TicketCanvasColor = ({String color, double opacity});

/// Domain adapter only. Shared controls preserve the unquantized opacity.
class TicketCanvasColorDialog extends StatelessWidget {
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
  Widget build(BuildContext context) => EditorColorDialog(
        value: EditorColorValue(
            hex: value == 'transparent' ? 'FFFFFF' : value,
            opacity: value == 'transparent' ? 0 : opacity),
        title: TicketLayoutStrings.canvasColor,
        usedColors: usedColors,
        image: image,
        translate: (label) => ticketEditorColorLabel(context, label),
        onPreview: (result) => onPreview?.call(
            (color: result.primary.hex, opacity: result.primary.opacity)),
      );
}
