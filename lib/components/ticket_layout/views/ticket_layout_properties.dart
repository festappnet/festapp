import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../ticket_layout_controller.dart';
import '../models/ticket_layout.dart';
import '../ticket_text.dart';
import '../ticket_layout_strings.dart';

class TicketLayoutProperties extends StatelessWidget {
  final TicketLayoutController controller;
  final TicketTemplate? defaults;
  final ui.Image? backgroundImage;
  final TicketFontMetrics? metrics;
  final Map<String, String?>? data;
  const TicketLayoutProperties(
      {super.key,
      required this.controller,
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
                            ? TicketLayoutStrings.qrColors
                            : TicketLayoutStrings.color),
                        subtitle: Text(e.binding == 'qr'
                            ? '${TicketLayoutStrings.qrForeground}: #${e.color.toUpperCase()}\n${TicketLayoutStrings.qrBackground}: #${controller.document.qrAppearance['background'] ?? 'FFFFFF'}'
                            : '#${e.color.toUpperCase()}'),
                        trailing: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                                color:
                                    Color(int.parse('ff${e.binding == 'qr' ? controller.document.qrAppearance['background'] ?? 'FFFFFF' : e.color}', radix: 16)),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey)),
                            child: e.binding == 'qr' ? Icon(Icons.qr_code_2, color: Color(int.parse('ff${e.color}', radix: 16))) : null),
                        onTap: e.locked
                            ? null
                            : () async {
                                final color = await showDialog<({String foreground, String background})>(
                                    context: context,
                                    builder: (_) =>
                                        _TicketColorDialog(element: e, usedColors: controller.document.elements.map((e) => e.color).toSet().toList(), backgroundImage: backgroundImage, background: controller.document.qrAppearance['background'] as String? ?? 'FFFFFF'));
                                if (!context.mounted || color == null) return;
                                if (e.binding == 'qr') {
                                  if (color.foreground != e.color || color.background != (controller.document.qrAppearance['background'] ?? 'FFFFFF')) {
                                    controller.replace(controller.document.withQrColors(color.foreground, color.background));
                                  }
                                } else if (color.foreground != e.color) {
                                  controller.change(e.copyWith(color: color.foreground));
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
  final String background;
  final List<String> usedColors;
  final ui.Image? backgroundImage;
  const _TicketColorDialog({required this.element, required this.background, required this.usedColors, this.backgroundImage});
  @override
  State<_TicketColorDialog> createState() => _TicketColorDialogState();
}

class _TicketColorDialogState extends State<_TicketColorDialog> {
  late Color foreground = Color(int.parse('ff${widget.element.color}', radix: 16));
  late Color background = Color(int.parse('ff${widget.background}', radix: 16));
  bool editingBackground = false;
  List<String> imageColors = [];
  @override
  void initState() {
    super.initState();
    extractImageColors();
  }

  Future<void> extractImageColors() async {
    final image = widget.backgroundImage;
    if (image == null) return;
    // Sample a tiny raster, never read the full-resolution artwork into Dart.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 32, 32), Paint());
    final picture = recorder.endRecording();
    final sample = await picture.toImage(32, 32);
    picture.dispose();
    final bytes = await sample.toByteData(format: ui.ImageByteFormat.rawRgba);
    sample.dispose();
    if (bytes == null || !mounted) return;
    final counts = <int, int>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 3) < 128) continue;
      final rgb = ((bytes.getUint8(i) ~/ 32 * 32) << 16) |
          ((bytes.getUint8(i + 1) ~/ 32 * 32) << 8) |
          (bytes.getUint8(i + 2) ~/ 32 * 32);
      counts[rgb] = (counts[rgb] ?? 0) + 1;
    }
    final ranked = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    setState(() => imageColors = ranked.take(5).map((v) => v.toRadixString(16).padLeft(6, '0').toUpperCase()).toList());
  }

  Widget swatches(String label, Iterable<String> colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Wrap(spacing: 8, runSpacing: 8, children: colors.map((v) => v.toUpperCase()).toSet().map((v) =>
        IconButton(
          tooltip: '#$v',
          onPressed: () { focus.unfocus(); pick(Color(int.parse('ff$v', radix: 16))); },
          // IconButton.style is ignored by Material 2, used by the app.
          // Paint the swatch itself so both themes show the actual color.
          iconSize: 32,
          icon: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: Color(int.parse('ff$v', radix: 16)),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey),
            ),
            child: value == v ? Icon(Icons.check, size: 22,
              color: Color(int.parse('ff$v', radix: 16)).computeLuminance() > .5
                  ? Colors.black : Colors.white) : null,
          ),
        )).toList()),
      const SizedBox(height: 12),
    ]);

  bool get isQr => widget.element.binding == 'qr';
  Color get color => editingBackground ? background : foreground;
  String colorHex(Color value) => value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  bool get readable => ticketQrColorReadable(colorHex(foreground), colorHex(background));
  void selectBackground(bool selected) => setState(() {
    focus.unfocus(); editingBackground = selected; hex.text = value;
  });
  void swapColors() => setState(() {
    focus.unfocus(); final previous = foreground; foreground = background; background = previous; hex.text = value;
  });
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

  void pick(Color c, {bool fromHex = false}) => setState(() {
        if (editingBackground) { background = c; } else { foreground = c; }
        if (!fromHex) {
          hex.text = value;
        }
      });
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.element.binding == 'qr'
              ? TicketLayoutStrings.qrColors
              : TicketLayoutStrings.color),
          content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (isQr) ...[
                  Container(padding: const EdgeInsets.all(8), color: background,
                    child: Icon(Icons.qr_code_2, size: 56, color: foreground)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(TicketLayoutStrings.qrForeground)),
                        ButtonSegment(value: true, label: Text(TicketLayoutStrings.qrBackground)),
                      ],
                      selected: {editingBackground},
                      onSelectionChanged: (value) => selectBackground(value.single))),
                    IconButton(onPressed: swapColors, tooltip: TicketLayoutStrings.swapColors,
                      icon: const Icon(Icons.swap_horiz)),
                  ]),
                  const SizedBox(height: 8),
                  Text(TicketLayoutStrings.qrBackgroundHint),
                  const SizedBox(height: 12),
                ],
                swatches(TicketLayoutStrings.usedColors, widget.usedColors),
                if (imageColors.isNotEmpty) swatches(TicketLayoutStrings.imageColors, imageColors),
                swatches(TicketLayoutStrings.basicColors, ticketQrColors),
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
                          pick(Color(int.parse('ff$v', radix: 16)), fromHex: true);
                        } else {
                          setState(() {});
                        }
                      }),
                if (isQr && !readable)
                  Text(TicketLayoutStrings.qrContrast,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(TicketLayoutStrings.cancel)),
            FilledButton(
                onPressed: !RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(hex.text) ||
                    isQr && !readable
                    ? null : () => Navigator.pop(context, (foreground: colorHex(foreground), background: colorHex(background))),
                child: Text(TicketLayoutStrings.apply)),
          ]);
}
