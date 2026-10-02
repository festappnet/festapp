import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../ticket_layout_controller.dart';
import '../models/ticket_layout.dart';
import '../ticket_text.dart';
import '../ticket_layout_strings.dart';

class TicketLayoutProperties extends StatelessWidget {
  final TicketLayoutController controller;
  final TicketTemplate? defaults;
  final TicketFontMetrics? metrics;
  final Map<String, String?>? data;
  const TicketLayoutProperties(
      {super.key,
      required this.controller,
      this.metrics,
      this.data,
      this.defaults});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final e = controller.selection;
        if (controller.selectedIds.length > 1) {
          return Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${TicketLayoutStrings.selectedElements}: ${controller.selectedIds.length}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(TicketLayoutStrings.groupMoveHint),
            ]));
        }
        if (e == null) return const SizedBox.shrink();
        final text = !['qr', 'logo'].contains(e.binding);
        var overflow = false;
        if (text && metrics != null && data?[e.binding] != null) {
          try {
            final fit = fitTicketText(data![e.binding]!, e, metrics!);
            overflow = fit.overflow || fit.replaced;
          } on FormatException {
            overflow = true;
          }
        }
        final original = defaults?.elements
            .where((item) => item.binding == e.binding)
            .firstOrNull;
        void resetFont() {
          if (!e.locked && original != null) {
            controller.change(e.copyWith(
                fontSize: original.fontSize.clamp(e.minFontSize, 72)));
          }
        }

        return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (overflow)
                    Text(TicketLayoutStrings.overflow,
                        style: const TextStyle(color: Colors.orange)),
                  Text(TicketLayoutStrings.binding(e.binding),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (text) ...[
                    const SizedBox(height: 12),
                    Text(TicketLayoutStrings.textStyle),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      multiSelectionEnabled: true, emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 'bold', tooltip: TicketLayoutStrings.bold,
                            icon: const Icon(Icons.format_bold)),
                        ButtonSegment(value: 'italic', tooltip: TicketLayoutStrings.italic,
                            icon: const Icon(Icons.format_italic)),
                        ButtonSegment(value: 'underline', tooltip: TicketLayoutStrings.underline,
                            icon: const Icon(Icons.format_underlined)),
                      ],
                      selected: {if (e.bold) 'bold', if (e.italic) 'italic', if (e.underline) 'underline'},
                      onSelectionChanged: e.locked ? null : (values) => controller.change(e.copyWith(
                        bold: values.contains('bold'), italic: values.contains('italic'),
                        underline: values.contains('underline')))),
                    const SizedBox(height: 12),
                    Text(TicketLayoutStrings.align),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                              value: 'left',
                              tooltip: TicketLayoutStrings.left,
                              icon: const Icon(Icons.format_align_left)),
                          ButtonSegment(
                              value: 'center',
                              tooltip: TicketLayoutStrings.center,
                              icon: const Icon(Icons.format_align_center)),
                          ButtonSegment(
                              value: 'right',
                              tooltip: TicketLayoutStrings.right,
                              icon: const Icon(Icons.format_align_right)),
                        ],
                        selected: {e.align},
                        onSelectionChanged: e.locked
                            ? null
                            : (values) => controller
                                .change(e.copyWith(align: values.single))),
                    const SizedBox(height: 8),
                  ],
                  if (text || e.binding == 'qr')
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.binding == 'qr'
                            ? TicketLayoutStrings.qrColor
                            : TicketLayoutStrings.color),
                        subtitle: Text('#${e.color.toUpperCase()}'),
                        trailing: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                                color:
                                    Color(int.parse('ff${e.color}', radix: 16)),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey))),
                        onTap: e.locked
                            ? null
                            : () async {
                                final color = await showDialog<String>(
                                    context: context,
                                    builder: (_) =>
                                        _TicketColorDialog(element: e));
                                if (context.mounted &&
                                    color != null &&
                                    color != e.color) {
                                  controller.change(e.copyWith(color: color));
                                }
                              }),
                  if (text) ...[
                    Text(
                        '${TicketLayoutStrings.fontSize}: ${e.fontSize.toStringAsFixed(1)} pt'),
                    Tooltip(
                        message: TicketLayoutStrings.resetSlider,
                        child: GestureDetector(
                            onDoubleTap: e.locked ? null : resetFont,
                            child: Slider(
                                value: e.fontSize,
                                min: e.minFontSize,
                                max: 72,
                                onChangeStart: (_) => controller.beginGesture(),
                                onChangeEnd: (_) => controller.endGesture(),
                                onChanged: e.locked
                                    ? null
                                    : (v) => controller
                                        .change(e.copyWith(fontSize: v))))),
                    const SizedBox(height: 12),
                    Text('${TicketLayoutStrings.maxLines}: ${e.maxLines}'),
                    Tooltip(
                        message: TicketLayoutStrings.resetSlider,
                        child: GestureDetector(
                            onDoubleTap: e.locked || original == null
                                ? null
                                : () => controller.change(
                                    e.copyWith(maxLines: original.maxLines)),
                            child: Slider(
                                value: e.maxLines.toDouble(),
                                min: 1,
                                max: 12,
                                divisions: 11,
                                onChangeStart: (_) => controller.beginGesture(),
                                onChangeEnd: (_) => controller.endGesture(),
                                onChanged: e.locked
                                    ? null
                                    : (v) => controller.change(
                                        e.copyWith(maxLines: v.round()))))),
                  ],
                  const Divider(),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(TicketLayoutStrings.visible),
                      value: e.visible,
                      onChanged: ['qr', 'ticketSymbol'].contains(e.binding)
                          ? null
                          : (v) => controller.change(e.copyWith(visible: v))),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(TicketLayoutStrings.locked),
                      value: e.locked,
                      onChanged: (v) =>
                          controller.change(e.copyWith(locked: v))),
                ]));
      });
}

class _TicketColorDialog extends StatefulWidget {
  final TicketElement element;
  const _TicketColorDialog({required this.element});
  @override
  State<_TicketColorDialog> createState() => _TicketColorDialogState();
}

class _TicketColorDialogState extends State<_TicketColorDialog> {
  late Color color = Color(int.parse('ff${widget.element.color}', radix: 16));
  late final hex =
      TextEditingController(text: widget.element.color.toUpperCase());
  final focus = FocusNode();
  String get value => color
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();
  @override
  void dispose() {
    hex.dispose();
    focus.dispose();
    super.dispose();
  }

  void pick(Color c) => setState(() {
        color = c;
        if (!focus.hasFocus) {
          hex.text = value;
        }
      });
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.element.binding == 'qr'
              ? TicketLayoutStrings.qrColor
              : TicketLayoutStrings.color),
          content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (widget.element.binding == 'qr')
                  BlockPicker(
                      pickerColor: color,
                      availableColors: ticketQrColors
                          .map((v) => Color(int.parse('ff$v', radix: 16)))
                          .toList(),
                      onColorChanged: pick)
                else ...[
                  ColorPicker(
                      pickerColor: color,
                      enableAlpha: false,
                      labelTypes: const [],
                      portraitOnly: true,
                      pickerAreaHeightPercent: .8,
                      onColorChanged: pick),
                  TextField(
                      controller: hex,
                      focusNode: focus,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          prefixText: '#', labelText: 'HEX'),
                      onChanged: (v) {
                        if (RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(v)) {
                          pick(Color(int.parse('ff$v', radix: 16)));
                        }
                      }),
                ],
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(TicketLayoutStrings.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, value),
                child: Text(TicketLayoutStrings.apply)),
          ]);
}
