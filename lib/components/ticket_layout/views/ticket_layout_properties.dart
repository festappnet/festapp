import 'package:venue_seat_picker/editor_ui.dart';
import 'ticket_color_suggestions.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../ticket_layout_controller.dart';
import '../models/ticket_layout.dart';
import '../ticket_text.dart';
import '../ticket_layout_strings.dart';

class TicketLayoutProperties extends StatelessWidget {
  final TicketLayoutController controller;
  final Widget? fontControl, productControl;
  final TicketTemplate? defaults;
  final ui.Image? backgroundImage;
  final TicketFontMetrics? metrics;
  final Map<String, String?>? data;
  const TicketLayoutProperties(
      {super.key,
      required this.controller,
      this.fontControl,
      this.productControl,
      this.metrics,
      this.backgroundImage,
      this.data,
      this.defaults});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final e = controller.selection;
        if (controller.selectedIds.length > 1) {
          return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${TicketLayoutStrings.selectedElements}: ${controller.selectedIds.length}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(TicketLayoutStrings.groupMoveHint),
                  ]));
        }
        if (e == null) return const SizedBox.shrink();
        final text = !['qr', 'logo'].contains(e.binding);
        var overflow = false;
        if (text && metrics != null && data?[e.id] != null) {
          try {
            final fit = fitTicketText(data![e.id]!, e, metrics!);
            overflow = fit.overflow || fit.replaced;
          } on FormatException {
            overflow = true;
          }
        }
        final original = defaults?.elements
                .where((item) =>
                    item.id == e.id ||
                    (e.binding != 'productType' && item.binding == e.binding))
                .firstOrNull ??
            (e.binding == 'productType'
                ? TicketElement(
                    id: e.id,
                    binding: 'productType',
                    productTypeId: e.productTypeId,
                    label: e.label,
                    box: e.box,
                    fontSize: 12,
                    maxLines: 3)
                : null);
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
                  if (productControl != null) productControl!,
                  if (text) ...[
                    if (fontControl != null) fontControl!,
                    const SizedBox(height: 12),
                    Text(TicketLayoutStrings.textStyle),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                        multiSelectionEnabled: true,
                        emptySelectionAllowed: true,
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                              value: 'bold',
                              tooltip: TicketLayoutStrings.bold,
                              icon: const Icon(Icons.format_bold)),
                          ButtonSegment(
                              value: 'italic',
                              tooltip: TicketLayoutStrings.italic,
                              icon: const Icon(Icons.format_italic)),
                          ButtonSegment(
                              value: 'underline',
                              tooltip: TicketLayoutStrings.underline,
                              icon: const Icon(Icons.format_underlined)),
                        ],
                        selected: {
                          if (e.bold) 'bold',
                          if (e.italic) 'italic',
                          if (e.underline) 'underline'
                        },
                        onSelectionChanged: e.locked
                            ? null
                            : (values) => controller.change(e.copyWith(
                                bold: values.contains('bold'),
                                italic: values.contains('italic'),
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
                            ? TicketLayoutStrings.qrColors
                            : TicketLayoutStrings.color),
                        subtitle: Text(e.binding == 'qr'
                            ? '${TicketLayoutStrings.qrForeground}: #${e.color.toUpperCase()}\n${TicketLayoutStrings.qrBackground}: #${controller.document.qrAppearance['background'] ?? 'FFFFFF'}'
                            : '#${e.color.toUpperCase()}'),
                        trailing: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                                color: Color(int.parse(
                                    'ff${e.binding == 'qr' ? controller.document.qrAppearance['background'] ?? 'FFFFFF' : e.color}',
                                    radix: 16)),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey)),
                            child: e.binding == 'qr'
                                ? Icon(Icons.qr_code_2,
                                    color: Color(
                                        int.parse('ff${e.color}', radix: 16)))
                                : null),
                        onTap: e.locked
                            ? null
                            : () async {
                                final original = controller.document;
                                controller.beginGesture();
                                final color = await showDialog<EditorColorResult>(
                                    context: context,
                                    builder: (_) => _TicketColorDialog(
                                        element: e,
                                        usedColors: [
                                          ...original.elements
                                              .map((e) => e.color),
                                          original.canvasColor
                                        ],
                                        backgroundImage: backgroundImage,
                                        background:
                                            original.qrAppearance['background']
                                                    as String? ??
                                                'FFFFFF',
                                        onPreview: (foreground, background) =>
                                            controller.previewDocument(e.binding ==
                                                    'qr'
                                                ? original.withQrColors(
                                                    foreground, background)
                                                : original.replace(e.copyWith(
                                                    color: foreground)))));
                                if (color == null) {
                                  controller.cancelGesture();
                                } else {
                                  controller.previewDocument(e.binding == 'qr'
                                      ? original.withQrColors(color.primary.hex,
                                          color.secondary!.hex)
                                      : original.replace(e.copyWith(
                                          color: color.primary.hex)));
                                  controller.endGesture();
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

/// The ticket adapter supplies QR rules; every color control is shared.
class _TicketColorDialog extends StatelessWidget {
  final TicketElement element;
  final String background;
  final List<String> usedColors;
  final ui.Image? backgroundImage;
  final void Function(String foreground, String background)? onPreview;
  const _TicketColorDialog(
      {required this.element,
      required this.background,
      required this.usedColors,
      this.backgroundImage,
      this.onPreview});

  @override
  Widget build(BuildContext context) {
    final isQr = element.binding == 'qr';
    return EditorColorDialog(
      value: EditorColorValue(hex: element.color),
      secondaryValue: isQr ? EditorColorValue(hex: background) : null,
      title: isQr ? TicketLayoutStrings.qrColors : TicketLayoutStrings.color,
      primaryLabel: TicketLayoutStrings.qrForeground,
      secondaryLabel: TicketLayoutStrings.qrBackground,
      usedColors: usedColors,
      image: backgroundImage,
      enableOpacity: false,
      translate: (label) => ticketEditorColorLabel(context, label),
      validator: isQr
          ? (result) =>
              ticketQrColorReadable(result.primary.hex, result.secondary!.hex)
                  ? null
                  : TicketLayoutStrings.qrContrast
          : null,
      previewBuilder: isQr
          ? (context, result) => Column(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    color: result.secondary!.color,
                    child: Icon(Icons.qr_code_2,
                        size: 56, color: result.primary.color)),
                const SizedBox(height: 8),
                Text(TicketLayoutStrings.qrBackgroundHint),
              ])
          : null,
      onPreview: (result) => onPreview?.call(
          result.primary.hex, result.secondary?.hex ?? background),
    );
  }
}

class TicketProductLabelInput extends StatefulWidget {
  final TicketLayoutController controller;
  final TicketElement element;
  const TicketProductLabelInput(
      {super.key, required this.controller, required this.element});
  @override
  State<TicketProductLabelInput> createState() =>
      _TicketProductLabelInputState();
}

class _TicketProductLabelInputState extends State<TicketProductLabelInput> {
  late final text = TextEditingController(text: widget.element.label);
  late final focus = FocusNode()..addListener(_focusChanged);
  void _focusChanged() {
    if (focus.hasFocus)
      widget.controller.beginGesture();
    else
      widget.controller.endGesture();
  }

  @override
  void didUpdateWidget(covariant TicketProductLabelInput old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && text.text != widget.element.label)
      text.text = widget.element.label ?? '';
  }

  @override
  void dispose() {
    focus.removeListener(_focusChanged);
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
      controller: text,
      focusNode: focus,
      enabled: !widget.element.locked,
      maxLength: 120,
      decoration: InputDecoration(
          labelText: TicketLayoutStrings.productLabel,
          helperText: TicketLayoutStrings.labelHint),
      onChanged: (value) {
        widget.controller.beginGesture();
        widget.controller.change(widget.element.copyWith(label: value.trim()));
      },
      onSubmitted: (_) => focus.unfocus(),
      onTapOutside: (_) => focus.unfocus());
}
