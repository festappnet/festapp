import 'package:flutter/material.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_strings.dart';

class TicketDimensionsDialog extends StatefulWidget {
  final TicketTemplate document;
  final String type;
  final ValueChanged<TicketTemplate>? onPreview;
  const TicketDimensionsDialog(
      {super.key, required this.document, required this.type, this.onPreview});
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
  late final margin = TextEditingController(
      text: (widget.document.pageMargin / pointsPerMm).toStringAsFixed(1));
  late double? preciseMargin = widget.document.pageMargin;
  void marginEdited(String _) {
    setState(() {
      preciseMargin = null;
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
    margin.dispose();
    super.dispose();
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
    if (w * pointsPerMm > 842 || h * pointsPerMm > 842) {
      setState(() => error = TicketLayoutStrings.canvasTooLarge);
      return null;
    }
    final m = preciseMargin ??
        (double.tryParse(margin.text.replaceAll(',', '.')) ?? double.nan) *
            pointsPerMm;
    if (ticketPaper && (!m.isFinite || m < 0 || m > 72)) {
      setState(() => error = TicketLayoutStrings.invalidMargin);
      return null;
    }
    var candidate = widget.document.resizeArea(preciseSize ??
        Size(
            width.text ==
                    (widget.document.area.width / pointsPerMm)
                        .toStringAsFixed(1)
                ? widget.document.area.width
                : w * pointsPerMm,
            height.text ==
                    (widget.document.area.height / pointsPerMm)
                        .toStringAsFixed(1)
                ? widget.document.area.height
                : h * pointsPerMm));
    if (ticketPaper || paperChanged || (!legacyPaper && preciseSize == null)) {
      candidate = candidate.withPaper(ticketPaper, margin: ticketPaper ? m : 0);
    }
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
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(TicketLayoutStrings.designSize,
                        style: Theme.of(context).textTheme.titleMedium)),
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
                Text(TicketLayoutStrings.designSizeHint),
                const Divider(height: 32),
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
                        if (ticketPaper &&
                            !widget.document.fitPageToTicket &&
                            margin.text == '0.0') {
                          margin.text = '3.0';
                          preciseMargin = 3 * pointsPerMm;
                        }
                        error = null;
                      });
                      preview();
                    }),
                const SizedBox(height: 16),
                if (ticketPaper) ...[
                  TextField(
                      controller: margin,
                      onChanged: marginEdited,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: TicketLayoutStrings.marginMm,
                          helperText: TicketLayoutStrings.marginHint,
                          helperMaxLines: 3)),
                  const SizedBox(height: 12),
                  Text(TicketLayoutStrings.ticketPdfHint),
                ] else
                  Text(legacyPaper && !paperChanged
                      ? TicketLayoutStrings.originalPaperHint
                      : TicketLayoutStrings.canvasHint),
                const SizedBox(height: 12),
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
