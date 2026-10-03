import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_strings.dart';

class TicketDimensionsDialog extends StatefulWidget {
  final TicketTemplate document;
  final String type;
  final TicketTemplate defaults;
  final ui.Image? image;
  final ValueChanged<TicketTemplate>? onPreview;
  const TicketDimensionsDialog(
      {super.key,
      required this.document,
      required this.type,
      required this.defaults,
      this.image,
      this.onPreview});
  @override
  State<TicketDimensionsDialog> createState() => _TicketDimensionsDialogState();
}

class _TicketDimensionsDialogState extends State<TicketDimensionsDialog> {
  static const pointsPerMm = 72 / 25.4;
  late final width = TextEditingController(
      text: (widget.document.area.width / pointsPerMm).toStringAsFixed(1));
  late final height = TextEditingController(
      text: (widget.document.area.height / pointsPerMm).toStringAsFixed(1));
  late Size? preciseSize = widget.document.area.size;
  late bool ticketPaper = widget.document.fitPageToTicket;
  bool paperChanged = false;
  bool get legacyPaper =>
      !widget.document.fitPageToTicket &&
      widget.document.page != const Size(595.28, 841.89);
  String? error;
  void setDimensions(Size size) {
    width.text = (size.width / pointsPerMm).toStringAsFixed(1);
    height.text = (size.height / pointsPerMm).toStringAsFixed(1);
    setState(() {
      preciseSize = size;
      error = null;
    });
    preview();
  }

  void edited(String _) {
    setState(() {
      preciseSize = null;
      error = null;
    });
    preview();
  }

  void preview() {
    final candidate = validated();
    if (candidate != null) widget.onPreview?.call(candidate);
  }

  @override
  void dispose() {
    width.dispose();
    height.dispose();
    super.dispose();
  }

  void fromImage() {
    final image = widget.image!;
    final current =
        paperChanged ? widget.document.withPaper(ticketPaper) : widget.document;
    var w = (double.tryParse(width.text.replaceAll(',', '.')) ??
            current.area.width / pointsPerMm) *
        pointsPerMm;
    if (!w.isFinite) w = current.area.width;
    w = w.clamp(1,
        current.fitPageToTicket ? 842 : current.page.width - current.area.left);
    var h = w * image.height / image.width;
    final maxHeight = current.fitPageToTicket
        ? 842.0
        : current.page.height - current.area.top;
    if (h > maxHeight) {
      h = maxHeight;
      w = h * image.width / image.height;
    }
    setDimensions(Size(w, h));
  }

  TicketTemplate? validated() {
    final w = double.tryParse(width.text.replaceAll(',', '.'));
    final h = double.tryParse(height.text.replaceAll(',', '.'));
    if (w == null ||
        h == null ||
        !w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0) {
      setState(() => error = TicketLayoutStrings.invalidCanvas);
      return null;
    }
    final base =
        paperChanged ? widget.document.withPaper(ticketPaper) : widget.document;
    final candidate =
        base.resizeArea(preciseSize ?? Size(w * pointsPerMm, h * pointsPerMm));
    final errors = candidate.validate(widget.type);
    if (errors.isNotEmpty) {
      setState(() => error = errors.contains('geometry')
          ? TicketLayoutStrings.canvasTooLarge
          : TicketLayoutStrings.canvasTooSmall);
      return null;
    }
    return candidate;
  }

  void apply() {
    final candidate = validated();
    if (candidate != null) Navigator.pop(context, candidate);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(TicketLayoutStrings.canvasSize),
          content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(TicketLayoutStrings.paperFormat),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                    segments: [
                      if (legacyPaper)
                        ButtonSegment(
                            value: 'original',
                            label: Text(TicketLayoutStrings.paperOriginal)),
                      ButtonSegment(
                          value: 'a4',
                          label: Text(TicketLayoutStrings.paperA4)),
                      ButtonSegment(
                          value: 'ticket',
                          label: Text(TicketLayoutStrings.paperTicket)),
                    ],
                    selected: {
                      legacyPaper && !paperChanged
                          ? 'original'
                          : ticketPaper
                              ? 'ticket'
                              : 'a4'
                    },
                    onSelectionChanged: (values) {
                      setState(() {
                        ticketPaper = values.single == 'ticket';
                        paperChanged = values.single != 'original';
                      });
                      preview();
                    }),
                const SizedBox(height: 16),
                TextField(
                    controller: width,
                    onChanged: edited,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: TicketLayoutStrings.widthMm)),
                TextField(
                    controller: height,
                    onChanged: edited,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: TicketLayoutStrings.heightMm)),
                const SizedBox(height: 12),
                Text(ticketPaper
                    ? TicketLayoutStrings.ticketPdfHint
                    : TicketLayoutStrings.canvasHint),
                TextButton(
                    onPressed: () => setDimensions(widget.defaults.area.size),
                    child: Text(TicketLayoutStrings.defaultDimensions)),
                if (widget.image != null)
                  TextButton(
                      onPressed: fromImage,
                      child: Text(TicketLayoutStrings.fromImage)),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(TicketLayoutStrings.cancel)),
            FilledButton(
                onPressed: apply, child: Text(TicketLayoutStrings.apply)),
          ]);
}
