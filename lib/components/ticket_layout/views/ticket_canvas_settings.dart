import 'package:flutter/material.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_controller.dart';
import '../ticket_layout_strings.dart';

/// Persistent settings beside the live canvas; never covers the paper preview.
class TicketCanvasSettings extends StatefulWidget {
  final TicketLayoutController controller;
  final Size? backgroundImage;
  final ValueChanged<String> onEditElement;
  final VoidCallback onPaperChanged;
  const TicketCanvasSettings(
      {super.key,
      required this.controller,
      this.backgroundImage,
      required this.onEditElement,
      required this.onPaperChanged});
  @override
  State<TicketCanvasSettings> createState() => _TicketCanvasSettingsState();
}

class _TicketCanvasSettingsState extends State<TicketCanvasSettings> {
  static const units = 72 / 25.4;
  final width = TextEditingController(),
      height = TextEditingController(),
      margin = TextEditingController();
  final widthFocus = FocusNode(),
      heightFocus = FocusNode(),
      marginFocus = FocusNode();
  String? error;
  TicketTemplate get document => widget.controller.document;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(refresh);
    refresh();
    if (document.fitPageToTicket &&
        !document.appearance.containsKey('pageMargin')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          changePaper(true, marginValue: TicketTemplate.defaultPageMargin);
      });
    }
    widthFocus.addListener(() {
      if (!widthFocus.hasFocus) resize(true);
    });
    heightFocus.addListener(() {
      if (!heightFocus.hasFocus) resize(false);
    });
    marginFocus.addListener(() {
      if (!marginFocus.hasFocus) changeMargin();
    });
  }

  void refresh() {
    if (!widthFocus.hasFocus)
      width.text = (document.area.width / units).toStringAsFixed(1);
    if (!heightFocus.hasFocus)
      height.text = (document.area.height / units).toStringAsFixed(1);
    if (!marginFocus.hasFocus)
      margin.text = (document.pageMargin / units).toStringAsFixed(1);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(refresh);
    widthFocus.dispose();
    heightFocus.dispose();
    marginFocus.dispose();
    width.dispose();
    height.dispose();
    margin.dispose();
    super.dispose();
  }

  void resize(bool horizontal) {
    final field = horizontal ? width : height;
    final value = double.tryParse(field.text.replaceAll(',', '.'));
    final old = horizontal ? document.area.width : document.area.height;
    if (field.text == (old / units).toStringAsFixed(1)) return;
    if (value == null || !value.isFinite || value <= 0) {
      setState(() => error = TicketLayoutStrings.invalidCanvas);
      return;
    }
    setState(() => error = null);
    widget.controller.beginGesture();
    widget.controller.resizeCanvas(
        horizontal
            ? Offset(value * units - old, 0)
            : Offset(0, value * units - old),
        handle: horizontal ? 0 : 1,
        snap: false,
        backgroundImage: widget.backgroundImage);
    widget.controller.endGesture();
    final actual = horizontal ? document.area.width : document.area.height;
    field.text = (actual / units).toStringAsFixed(1);
    if ((actual - value * units).abs() > .1 &&
        widget.controller.canvasBlockers.isEmpty) {
      setState(() => error = value * units < 60
          ? TicketLayoutStrings.canvasTooSmall
          : TicketLayoutStrings.canvasTooLarge);
    }
  }

  void changePaper(bool ticket, {double? marginValue}) {
    final next = document.withPaper(ticket,
        margin: ticket
            ? marginValue ??
                (document.fitPageToTicket && document.appearance.containsKey('pageMargin')
                    ? document.pageMargin
                    : TicketTemplate.defaultPageMargin)
            : 0);
    if (next.validate('wide').isNotEmpty) {
      setState(() => error = TicketLayoutStrings.canvasTooLarge);
      return;
    }
    setState(() => error = null);
    widget.controller.replace(next);
    widget.onPaperChanged();
  }

  void changeMargin() {
    final value = double.tryParse(margin.text.replaceAll(',', '.'));
    if (margin.text == (document.pageMargin / units).toStringAsFixed(1)) return;
    if (value == null || !value.isFinite || value < 0 || value > 25.4) {
      setState(() => error = TicketLayoutStrings.invalidMargin);
      return;
    }
    changePaper(true, marginValue: value * units);
  }

  Widget field(TextEditingController value, FocusNode focus, String label,
          VoidCallback submit) =>
      TextField(
          controller: value,
          focusNode: focus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          onTapOutside: (_) => focus.unfocus(),
          decoration: InputDecoration(
              labelText: label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 18)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockers = document.elements
        .where((e) => widget.controller.canvasBlockers.contains(e.id));
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(TicketLayoutStrings.designSize,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: field(width, widthFocus, TicketLayoutStrings.widthMm,
                    () => resize(true))),
            const SizedBox(width: 16),
            Expanded(
                child: field(height, heightFocus, TicketLayoutStrings.heightMm,
                    () => resize(false)))
          ]),
          const SizedBox(height: 12),
          Text(TicketLayoutStrings.dimensionInputHint,
              style: theme.textTheme.bodySmall),
          if (blockers.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(TicketLayoutStrings.canvasBlocked,
                style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            for (final e in blockers)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                      onPressed: () => widget.onEditElement(e.id),
                      icon: const Icon(Icons.open_with, size: 18),
                      label: Text(TicketLayoutStrings.editBlockingElement(
                          TicketLayoutStrings.binding(e.binding))))),
          ],
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!,
                    style: TextStyle(color: theme.colorScheme.error))),
          if (widget.controller.canvasHidden.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    '${TicketLayoutStrings.canvasHidden}: ${document.elements.where((e) => widget.controller.canvasHidden.contains(e.id)).map((e) => TicketLayoutStrings.binding(e.binding)).join(', ')}',
                    style: theme.textTheme.bodySmall)),
          const Divider(height: 32),
          Text(TicketLayoutStrings.paperFormat,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
              key: ValueKey(
                  'paper-${document.fitPageToTicket}-${document.page}'),
              initialValue: document.fitPageToTicket
                  ? 'ticket'
                  : document.page == const Size(595.28, 841.89)
                      ? 'a4'
                      : 'original',
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                if (!document.fitPageToTicket &&
                    document.page != const Size(595.28, 841.89))
                  DropdownMenuItem(
                      value: 'original',
                      child: Text(TicketLayoutStrings.paperOriginal)),
                DropdownMenuItem(
                    value: 'a4', child: Text(TicketLayoutStrings.paperA4)),
                DropdownMenuItem(
                    value: 'ticket',
                    child: Text(TicketLayoutStrings.paperTicket)),
              ],
              onChanged: (v) {
                if (v != null && v != 'original') changePaper(v == 'ticket');
              }),
          const SizedBox(height: 20),
          if (document.fitPageToTicket) ...[
            field(margin, marginFocus, TicketLayoutStrings.marginMm,
                changeMargin),
            const SizedBox(height: 12),
            Text(TicketLayoutStrings.marginHint,
                style: theme.textTheme.bodySmall),
          ] else
            Text(
                document.page == const Size(595.28, 841.89)
                    ? TicketLayoutStrings.canvasHint
                    : TicketLayoutStrings.originalPaperHint,
                style: theme.textTheme.bodySmall),
        ]));
  }
}
