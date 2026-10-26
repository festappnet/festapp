import 'package:fstapp/widgets/app_dialog.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart'
    show VenueLayoutLocalizations;
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
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
        void finishSliderGesture() {
          controller.endGesture();
          // A dismissed dialog can leave focus outside the editor. Sliders do
          // not claim keyboard focus on pointer input, so restore history keys.
          Focus.maybeOf(context)?.requestFocus();
        }

        void resetFont() {
          if (!e.locked && original != null) {
            controller.change(e.copyWith(
                fontSize: original.fontSize.clamp(e.minFontSize, 72)));
            finishSliderGesture();
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
                  if (productControl == null)
                    Text(TicketLayoutStrings.binding(e.binding),
                        style: Theme.of(context).textTheme.titleMedium),
                  if (productControl != null) productControl!,
                  if (['text', 'footer'].contains(e.binding)) ...[
                    TicketFreeTextInput(
                        key: ValueKey('text-${e.id}'),
                        controller: controller,
                        element: e,
                        value: e.text ?? data?[e.id] ?? ''),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            onPressed: e.locked
                                ? null
                                : () => controller.removeTextField(e),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(TicketLayoutStrings.removeText))),
                  ],
                  if (text) ...[
                    if (fontControl != null) fontControl!,
                    const SizedBox(height: 12),
                    Text(TicketLayoutStrings.textStyle),
                    const SizedBox(height: 6),
                    EditorTextStyleControl(
                        translate: (value) => switch (value) {
                              'Bold' => TicketLayoutStrings.bold,
                              'Italic' => TicketLayoutStrings.italic,
                              'Underline' => TicketLayoutStrings.underline,
                              _ => value
                            },
                        selected: {
                          if (e.bold) 'bold',
                          if (e.italic) 'italic',
                          if (e.underline) 'underline'
                        },
                        onChanged: e.locked
                            ? null
                            : (values) => controller.change(e.copyWith(
                                bold: values.contains('bold'),
                                italic: values.contains('italic'),
                                underline: values.contains('underline')))),
                    const SizedBox(height: 12),
                    Text(TicketLayoutStrings.align),
                    const SizedBox(height: 6),
                    EditorTextAlignmentControl(
                        value: e.align,
                        translate: (value) => switch (value) {
                              'Left' => TicketLayoutStrings.left,
                              'Center' => TicketLayoutStrings.center,
                              'Right' => TicketLayoutStrings.right,
                              _ => value
                            },
                        onChanged: e.locked
                            ? null
                            : (value) =>
                                controller.change(e.copyWith(align: value))),
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
                                final choice = await showDialog<EditorColorResult>(
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
                                final color = choice == null
                                    ? null
                                    : (
                                        foreground: choice.primary.hex,
                                        background:
                                            choice.secondary?.hex ?? 'FFFFFF'
                                      );
                                if (color == null) {
                                  controller.cancelGesture();
                                } else {
                                  controller.previewDocument(e.binding == 'qr'
                                      ? original.withQrColors(
                                          color.foreground, color.background)
                                      : original.replace(
                                          e.copyWith(color: color.foreground)));
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
                                onChangeEnd: (_) => finishSliderGesture(),
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
                                : () {
                                    controller.change(e.copyWith(
                                        maxLines: original.maxLines));
                                    finishSliderGesture();
                                  },
                            child: Slider(
                                value: e.maxLines.toDouble(),
                                min: 1,
                                max: 12,
                                divisions: 11,
                                onChangeStart: (_) => controller.beginGesture(),
                                onChangeEnd: (_) => finishSliderGesture(),
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

/// Ticket-specific QR policy around the shared editor color control.
class _TicketColorDialog extends StatelessWidget {
  const _TicketColorDialog(
      {required this.element,
      required this.background,
      required this.usedColors,
      this.backgroundImage,
      this.onPreview});
  final TicketElement element;
  final String background;
  final List<String> usedColors;
  final ui.Image? backgroundImage;
  final void Function(String foreground, String background)? onPreview;
  @override
  Widget build(BuildContext context) {
    final qr = element.binding == 'qr';
    return EditorColorDialog(
      value: EditorColorValue(hex: element.color),
      secondaryValue: qr ? EditorColorValue(hex: background) : null,
      title: qr ? TicketLayoutStrings.qrColors : TicketLayoutStrings.color,
      translate: (value) => switch (value) {
        'Cancel' => TicketLayoutStrings.cancel,
        'Apply' => TicketLayoutStrings.apply,
        'Used colors' => TicketLayoutStrings.usedColors,
        'From artwork' => TicketLayoutStrings.imageColors,
        'Basic colors' => TicketLayoutStrings.basicColors,
        'Foreground' => TicketLayoutStrings.qrForeground,
        'Background' => TicketLayoutStrings.qrBackground,
        'Swap colors' => TicketLayoutStrings.swapColors,
        _ => VenueLayoutLocalizations.of(context).text(value)
      },
      dialogBuilder: (context, dialog) => AppAlertDialog(
          title: dialog.title,
          content: dialog.content,
          actions: dialog.actions),
      basicColors: ticketQrColors,
      usedColors: usedColors,
      image: backgroundImage,
      enableOpacity: false,
      validator: qr
          ? (result) =>
              ticketQrColorReadable(result.primary.hex, result.secondary!.hex)
                  ? null
                  : TicketLayoutStrings.qrContrast
          : null,
      onPreview: (result) => onPreview?.call(
          result.primary.hex, result.secondary?.hex ?? background),
      previewBuilder: qr
          ? (context, result) => Container(
              padding: const EdgeInsets.all(12),
              color: result.secondary!.color,
              child:
                  Icon(Icons.qr_code_2, size: 56, color: result.primary.color))
          : null,
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
  late int historyRevision = widget.controller.historyRevision;
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
    if ((!focus.hasFocus ||
            historyRevision != widget.controller.historyRevision) &&
        text.text != widget.element.label) {
      text.text = widget.element.label ?? '';
    }
    historyRevision = widget.controller.historyRevision;
  }

  @override
  void dispose() {
    focus.removeListener(_focusChanged);
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
              controller: text,
              style: Theme.of(context).textTheme.bodyLarge,
              focusNode: focus,
              enabled: !widget.element.locked,
              maxLength: 120,
              buildCounter: (context,
                      {required currentLength,
                      required isFocused,
                      required maxLength}) =>
                  currentLength >= 100
                      ? Text('$currentLength/$maxLength',
                          style: Theme.of(context).textTheme.bodySmall)
                      : null,
              decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.all(12),
                  labelText: TicketLayoutStrings.productLabel),
              onChanged: (value) {
                widget.controller.beginGesture();
                widget.controller
                    .change(widget.element.copyWith(label: value.trim()));
              },
              onSubmitted: (_) => focus.unfocus(),
              onTapOutside: (_) => focus.unfocus()),
          const SizedBox(height: 8),
          Text(TicketLayoutStrings.labelHint,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class TicketFreeTextInput extends StatefulWidget {
  final TicketLayoutController controller;
  final TicketElement element;
  final String value;
  const TicketFreeTextInput(
      {super.key,
      required this.controller,
      required this.element,
      required this.value});
  @override
  State<TicketFreeTextInput> createState() => _TicketFreeTextInputState();
}

class _TicketFreeTextInputState extends State<TicketFreeTextInput> {
  late final text = TextEditingController(text: widget.value);
  late final focus = FocusNode()..addListener(_focusChanged);
  void _focusChanged() {
    if (!focus.hasFocus) widget.controller.endGesture();
  }

  @override
  void didUpdateWidget(covariant TicketFreeTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (text.text != widget.value) {
      text.value = TextEditingValue(
          text: widget.value,
          selection: TextSelection.collapsed(offset: widget.value.length));
    }
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
      key: const ValueKey('ticket-free-text'),
      controller: text,
      focusNode: focus,
      enabled: !widget.element.locked,
      minLines: 2,
      maxLines: 5,
      maxLength: 2000,
      decoration: InputDecoration(labelText: TicketLayoutStrings.textContent),
      onChanged: (value) {
        widget.controller.beginGesture();
        widget.controller
            .change(widget.element.copyWith(binding: 'text', text: value));
      },
      onTapOutside: (_) => focus.unfocus());
}
