import 'package:flutter/material.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_strings.dart';

class TicketDimensionsDialog extends StatefulWidget {
  final TicketTemplate document;
  final String type;
  final Size? backgroundImage;
  final ValueChanged<TicketTemplate>? onPreview;
  const TicketDimensionsDialog(
      {super.key,
      required this.document,
      required this.type,
      this.onPreview,
      this.backgroundImage});
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
  late double? preciseMargin =
      widget.document.appearance.containsKey('pageMargin')
          ? widget.document.pageMargin
          : TicketTemplate.defaultPageMargin;
  late final margin = TextEditingController(
      text: (preciseMargin! / pointsPerMm).toStringAsFixed(1));

  @override
  void initState() {
    super.initState();
    if (ticketPaper && !widget.document.appearance.containsKey('pageMargin')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) preview();
      });
    }
  }

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
    preview(reportErrors: false);
  }

  void preview({bool reportErrors = true}) {
    final candidate = validated(reportErrors: reportErrors);
    if (candidate != null) widget.onPreview?.call(candidate);
  }

  @override
  void dispose() {
    width.dispose();
    height.dispose();
    margin.dispose();
    super.dispose();
  }

  TicketTemplate? validated({bool reportErrors = true}) {
    void report(String message) {
      if (reportErrors) setState(() => error = message);
    }

    final w = double.tryParse(width.text.replaceAll(',', '.'));
    final h = double.tryParse(height.text.replaceAll(',', '.'));
    if (w == null ||
        h == null ||
        !w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0) {
      report(TicketLayoutStrings.invalidCanvas);
      return null;
    }
    if (w * pointsPerMm > 842 || h * pointsPerMm > 842) {
      report(TicketLayoutStrings.canvasTooLarge);
      return null;
    }
    final m = preciseMargin ??
        (double.tryParse(margin.text.replaceAll(',', '.')) ?? double.nan) *
            pointsPerMm;
    if (ticketPaper && (!m.isFinite || m < 0 || m > 72)) {
      report(TicketLayoutStrings.invalidMargin);
      return null;
    }
    final size = preciseSize ??
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
                : h * pointsPerMm);
    final blockers = widget.document.elements.where((e) =>
        ['qr', 'ticketSymbol'].contains(e.binding) &&
        (e.box.right > size.width || e.box.bottom > size.height));
    if (blockers.isNotEmpty) {
      report(
          '${TicketLayoutStrings.canvasBlocked}: ${blockers.map((e) => TicketLayoutStrings.binding(e.binding)).join(', ')}');
      return null;
    }
    if (size.width < 60 || size.height < 60) {
      report(TicketLayoutStrings.canvasTooSmall);
      return null;
    }
    var candidate = widget.document
        .resizeCanvasArea(size, backgroundImage: widget.backgroundImage);
    if (ticketPaper || paperChanged || (!legacyPaper && preciseSize == null)) {
      candidate = candidate.withPaper(ticketPaper, margin: ticketPaper ? m : 0);
    }
    final errors = candidate.validate(widget.type);
    if (errors.isNotEmpty) {
      report(errors.contains('geometry')
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

  Widget numberField(TextEditingController controller, String label,
          ValueChanged<String> onChanged) =>
      TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final widthField = numberField(width, TicketLayoutStrings.widthMm, edited);
    final heightField =
        numberField(height, TicketLayoutStrings.heightMm, edited);
    Widget section(String title) => Text(title,
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600));
    Widget hint(String text) => Text(text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    return AlertDialog(
        title: Text(TicketLayoutStrings.canvasSize,
            style: theme.textTheme.headlineSmall),
        content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  section(TicketLayoutStrings.designSize),
                  const SizedBox(height: 20),
                  if (compact) ...[
                    widthField,
                    const SizedBox(height: 20),
                    heightField,
                  ] else
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: widthField),
                          const SizedBox(width: 16),
                          Expanded(child: heightField),
                        ]),
                  const SizedBox(height: 12),
                  hint(TicketLayoutStrings.designSizeHint),
                  const Divider(height: 40),
                  section(TicketLayoutStrings.paperFormat),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                      showSelectedIcon: false,
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
                          error = null;
                        });
                        preview();
                      }),
                  const SizedBox(height: 24),
                  if (ticketPaper) ...[
                    numberField(
                        margin, TicketLayoutStrings.marginMm, marginEdited),
                    const SizedBox(height: 12),
                    hint(TicketLayoutStrings.marginHint),
                  ] else
                    hint(legacyPaper && !paperChanged
                        ? TicketLayoutStrings.originalPaperHint
                        : TicketLayoutStrings.canvasHint),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ],
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(TicketLayoutStrings.cancel)),
          FilledButton(
              onPressed: apply, child: Text(TicketLayoutStrings.apply)),
        ]);
  }
}
