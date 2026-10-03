import 'dart:convert';
import '../../fonts/font_family_picker.dart';
import '../../fonts/ticket_font_catalog.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import 'package:fstapp/components/images/image_area.dart';
import '../ticket_background_image.dart';
import 'package:fstapp/services/exception_handler.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_controller.dart';
import '../ticket_layout_service.dart';
import '../ticket_layout_strings.dart';
import '../ticket_text.dart';
import 'ticket_layout_canvas.dart';
import 'ticket_layout_properties.dart';
import 'ticket_pdf_document.dart';
import 'ticket_dimensions_dialog.dart';

class TicketLayoutResult {
  final TicketTemplate template;
  final String? background;
  const TicketLayoutResult(this.template, this.background);
}

class TicketLayoutEditor extends StatefulWidget {
  final int occasionId;
  final String type;
  final Map<String, dynamic>? layout;
  final String? background;
  final TicketLayoutResources resources;
  final TicketLayoutService service;
  final bool showTemplatePicker;
  const TicketLayoutEditor(
      {super.key,
      required this.occasionId,
      required this.type,
      required this.resources,
      required this.service,
      this.showTemplatePicker = false,
      this.layout,
      this.background});
  @override
  State<TicketLayoutEditor> createState() => _TicketLayoutEditorState();
}

class _TicketLayoutEditorState extends State<TicketLayoutEditor> {
  late final controller = TicketLayoutController(widget.resources.template,
      artworkKey: widget.resources.initialArtworkKey);
  late TicketLayoutResources resources = widget.resources;
  late String? _background = widget.background;
  String? get background {
    final artwork = resources.artworks[controller.artworkKey];
    return artwork != null ? artwork.background : _background;
  }

  set background(String? value) => _background = value;
  final transform = TransformationController();
  final canvas = GlobalKey<TicketLayoutCanvasState>();
  bool additiveSelection = false;
  bool pan = false, wholePage = false, pdfBusy = false, imageBusy = false;
  int fontGeneration = 0;
  bool fontBusy = false;
  late final fontCatalog = TicketFontCatalog.load();
  bool snap = true, grid = false;
  late TicketTemplate _propertyDefaults = resources.preset;
  TicketTemplate get propertyDefaults =>
      resources.presets[controller.artworkKey] ?? _propertyDefaults;
  set propertyDefaults(TicketTemplate value) => _propertyDefaults = value;
  String scenario = 'normal';
  String? pdfSignature;
  int imageRevision = 0;
  String get signature => jsonEncode(
      [controller.document.toJson(), background, scenario, imageRevision]);
  bool get dirty => controller.dirty || background != widget.background;
  String? _lastArtworkKey;
  @override
  void initState() {
    super.initState();
    _lastArtworkKey = controller.artworkKey;
    controller.addListener(_refreshArtwork);
    if (widget.showTemplatePicker) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) chooseStyle();
      });
    }
  }

  void _refreshArtwork() {
    if (_lastArtworkKey == controller.artworkKey) return;
    setState(() => _lastArtworkKey = controller.artworkKey);
  }

  @override
  void dispose() {
    fontGeneration++;
    controller.dispose();
    transform.dispose();
    resources.dispose();
    super.dispose();
  }

  KeyEventResult _historyKey(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyUpEvent ||
        keyboard.isAltPressed ||
        !(keyboard.isControlPressed || keyboard.isMetaPressed)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.keyZ && key != LogicalKeyboardKey.keyY) {
      return KeyEventResult.ignored;
    }
    // Let text fields keep their own editing history, including when empty.
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    if (!imageBusy && event is KeyDownEvent) {
      key == LogicalKeyboardKey.keyY || keyboard.isShiftPressed
          ? controller.redo()
          : controller.undo();
    }
    return KeyEventResult.handled;
  }

  Map<String, dynamic> get draftLayout => upgradeTicketLayout({
        'schemaVersion': 1,
        'templates': {
          ...?(widget.layout?['templates'] as Map?),
          widget.type: controller.document.toJson()
        }
      });
  Future<void> cancel() async {
    fontGeneration++;
    if (mounted) setState(() => fontBusy = false);
    if (dirty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (c) =>
              AlertDialog(title: Text(TicketLayoutStrings.discard), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(TicketLayoutStrings.cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(TicketLayoutStrings.discard))
              ]));
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  void apply() {
    if (fontBusy) return;
    final errors = controller.document.validate(widget.type);
    final symbol = controller.document.elements
        .firstWhere((e) => e.binding == 'ticketSymbol');
    try {
      validateTicketLayout(draftLayout);
      fitTicketText('XXXX9W9W9W', symbol,
          resources.metricsFor(controller.document, symbol));
    } on FormatException {
      errors.add('ticketSymbol');
    }
    if (errors.isNotEmpty) {
      controller.select(errors.firstWhere(
          (id) => controller.document.elements.any((e) => e.id == id),
          orElse: () => symbol.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(TicketLayoutStrings.invalid)));
      return;
    }
    Navigator.pop(context, TicketLayoutResult(controller.document, background));
  }

  Future<void> preview() async {
    if (pdfBusy || imageBusy || fontBusy) return;
    final captured = signature;
    final layout = draftLayout;
    setState(() => pdfBusy = true);
    await ExceptionHandler.guard(context, futureFunction: () async {
      final result = await widget.service.preview(
          widget.occasionId, widget.type, layout, scenario, background);
      if (!mounted || signature != captured) return;
      await showDialog<void>(
          context: context,
          builder: (c) => Dialog.fullscreen(
              child: Scaffold(
                  appBar:
                      AppBar(title: Text(TicketLayoutStrings.pdf), actions: [
                    TextButton.icon(
                        onPressed: () => FileSaver.instance.saveFile(
                            name: 'ticket_layout_sample',
                            bytes: result.bytes,
                            mimeType: MimeType.pdf),
                        icon: const Icon(Icons.download),
                        label: Text(TicketLayoutStrings.downloadPdf)),
                    IconButton(
                        tooltip: TicketLayoutStrings.cancel,
                        onPressed: () => Navigator.pop(c),
                        icon: const Icon(Icons.close)),
                  ]),
                  body: Column(children: [
                    if (result.warnings.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                              '${TicketLayoutStrings.overflow}: ${result.warnings.map(TicketLayoutStrings.binding).join(', ')}')),
                    Expanded(child: TicketPdfDocument(bytes: result.bytes)),
                  ]))));
      if (mounted) setState(() => pdfSignature = captured);
    });
    if (mounted) setState(() => pdfBusy = false);
  }

  Future<String?> upload(dynamic file) async {
    if (imageBusy) return null;
    setState(() => imageBusy = true);
    String? uploaded;
    ui.Image? previousImage;
    bool staged = false, committed = false;
    await ExceptionHandler.guard(context, futureFunction: () async {
      final bytes =
          await TicketBackgroundImage.prepare(await file.readAsBytes());
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      final artwork = resources.artworks[controller.artworkKey];
      final currentImage =
          artwork != null ? artwork.image : resources.background;
      final ratioChanged = currentImage == null ||
          (currentImage.width / currentImage.height -
                      image.width / image.height)
                  .abs() >
              .01;
      previousImage = resources.background;
      staged = true;
      resources.background = image;
      imageRevision++;
      setState(() {});
      uploaded =
          await widget.service.uploadBackground(bytes, widget.occasionId);
      if (!mounted) return;
      final resolved = await widget.service
          .resolve(widget.occasionId, widget.type, draftLayout, uploaded);
      if (!mounted) {
        resolved.dispose();
        return;
      }
      final old = resources;
      setState(() {
        resolved.fonts.addAll(resources.fonts);
        resources = resolved;
        background = uploaded;
      });
      old.dispose();
      previousImage?.dispose();
      committed = true;
      controller.replace(controller.document, artworkKey: 'classic');
      if (ratioChanged) {
        final reset = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    content: Text(TicketLayoutStrings.aspectChange),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(TicketLayoutStrings.keep)),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(TicketLayoutStrings.reset))
                    ]));
        if (reset == true && mounted) controller.replace(resources.preset);
      }
    });
    if (staged && !committed) {
      if (mounted) {
        resources.background?.dispose();
        resources.background = previousImage;
      } else {
        previousImage?.dispose();
      }
    }
    if (mounted) setState(() => imageBusy = false);
    return committed ? uploaded : null;
  }

  Future<void> removeBackground() async {
    if (imageBusy) return;
    setState(() => imageBusy = true);
    await ExceptionHandler.guard(context, futureFunction: () async {
      final resolved = await widget.service
          .resolve(widget.occasionId, widget.type, draftLayout, null);
      if (!mounted) {
        resolved.dispose();
        return;
      }
      final old = resources;
      setState(() {
        resolved.fonts.addAll(resources.fonts);
        resources = resolved;
        background = null;
        imageRevision++;
      });
      old.dispose();
    });
    if (mounted) setState(() => imageBusy = false);
  }

  Future<void> editDimensions() async {
    final artwork = resources.artworks[controller.artworkKey];
    final original = controller.document;
    controller.beginGesture();
    final next = await showDialog<TicketTemplate>(
        context: context,
        builder: (_) => TicketDimensionsDialog(
            document: original,
            defaults: propertyDefaults,
            type: widget.type,
            image: artwork != null ? artwork.image : resources.background,
            onPreview: (size) {
              controller.previewResize(size);
              setState(() {});
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) canvas.currentState?.fit();
              });
            }));
    if (mounted) {
      if (next == null) {
        controller.cancelGesture();
      } else {
        controller.previewResize(next.area.size);
        controller.endGesture();
      }
      setState(() {});
      WidgetsBinding.instance
          .addPostFrameCallback((_) => canvas.currentState?.fit());
    }
  }

  Future<void> chooseStyle() async {
    final presets = resources.presets.isEmpty
        ? {'classic': resources.preset}
        : resources.presets;
    final previews = presets.map((key, value) => MapEntry(
        key,
        TicketLayoutController(value,
            artworkKey: resources.artworks.containsKey(key) ? key : null)));
    String? selected;
    try {
      selected = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(TicketLayoutStrings.styles),
                  content: SizedBox(
                      width: 960,
                      height: math.min(
                          620, MediaQuery.sizeOf(context).height * .75),
                      child: GridView.extent(
                          maxCrossAxisExtent:
                              MediaQuery.sizeOf(context).width < 600
                                  ? 500
                                  : 360,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.05,
                          children: previews.entries
                              .map((entry) => Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                      onTap: () =>
                                          Navigator.pop(context, entry.key),
                                      child: Column(children: [
                                        Expanded(
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: FittedBox(
                                                    child: CustomPaint(
                                                        size:
                                                            entry.value.document
                                                                .area.size,
                                                        painter:
                                                            TicketLayoutPainter(
                                                                entry.value,
                                                                resources,
                                                                resources
                                                                        .scenarios[
                                                                    scenario]!,
                                                                cropToTicket:
                                                                    true))))),
                                        Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Text(
                                                resources.artworks[entry.key]
                                                        ?.label ??
                                                    TicketLayoutStrings.binding(
                                                        'style_${entry.key}'),
                                                textAlign: TextAlign.center))
                                      ]))))
                              .toList())),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(TicketLayoutStrings.cancel))
                  ]));
    } finally {
      for (final controller in previews.values) {
        controller.dispose();
      }
    }
    if (selected != null && mounted) {
      setState(() => propertyDefaults = presets[selected!]!);
      controller.replace(presets[selected]!,
          artworkKey:
              resources.artworks.containsKey(selected) ? selected : null);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => canvas.currentState?.fit());
    }
  }

  Widget elements({VoidCallback? onSelected}) => ListenableBuilder(
      listenable: controller,
      builder: (c, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: controller.document.elements
              .map((e) => ListTile(
                  dense: true,
                  selected: controller.selectedIds.contains(e.id),
                  title: Text(TicketLayoutStrings.binding(e.binding)),
                  leading: Semantics(
                      toggled: e.visible,
                      child: IconButton(
                          tooltip: TicketLayoutStrings.visible,
                          icon: Icon(e.visible
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: ['qr', 'ticketSymbol'].contains(e.binding)
                              ? null
                              : () => controller
                                  .change(e.copyWith(visible: !e.visible)))),
                  trailing: e.locked ? const Icon(Icons.lock, size: 16) : null,
                  onTap: () {
                    controller.select(e.id, additive: additiveSelection);
                    onSelected?.call();
                  }))
              .toList()));
  Future<void> selectFont(Map<String, dynamic>? asset,
      {String? elementId}) async {
    final generation = ++fontGeneration;
    setState(() => fontBusy = true);
    try {
      final id = asset?['id'] as String?;
      final loaded =
          id == null ? null : await widget.service.font(widget.occasionId, id);
      if (!mounted || generation != fontGeneration) return;
      if (loaded != null) resources.fonts[loaded.id] = loaded;
      final document = controller.document;
      if (elementId == null) {
        controller.replace(document.withFont(id));
      } else {
        final element = document.elements.firstWhere((e) => e.id == elementId);
        if (element.locked) return;
        controller.change(element.copyWith(fontId: id, resetFont: id == null));
      }
    } finally {
      if (mounted && generation == fontGeneration) {
        setState(() => fontBusy = false);
      }
    }
  }

  Widget fontPicker({TicketElement? element}) => FutureBuilder<
          List<Map<String, dynamic>>>(
      future: fontCatalog,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final entries = snapshot.data!;
        final id = element?.fontId ??
            (element == null ? controller.document.fontId : null);
        final effective = element == null
            ? controller.document.fontId
            : element.fontId ?? controller.document.fontId;
        final font = effective == null
            ? resources.fonts.values.firstWhere((f) => f.family == 'Futura PT')
            : resources.fonts[effective];
        const sample = 'Příliš žluťoučký kůň, Ľščťžýáíé, 0123456789 Kč €';
        final glyphs = sample.runes.map(String.fromCharCode);
        final missing = font != null &&
            glyphs.any((c) => !font.metrics.advances.containsKey(c));
        final previewText = glyphs
            .map((c) => font?.metrics.advances.containsKey(c) == true ? c : '?')
            .join();
        return Padding(
            padding: const EdgeInsets.all(12),
            child: FontFamilyPicker(
                value: id == null ? null : font?.family,
                families: entries.map((f) => f['family'] as String).toList(),
                extraFamilies: const ['Futura PT', 'Roboto Slab', 'Russo One'],
                enabled: !imageBusy && !(element?.locked ?? false),
                preview: font == null
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text('${font.family} ${font.weight}'),
                            Text(previewText,
                                style: TextStyle(fontFamily: font.loaderName)),
                            if (missing)
                              Text(TicketLayoutStrings.missingGlyphs,
                                  style: const TextStyle(color: Colors.orange))
                          ]),
                onSelected: (family) => selectFont(
                    family == null
                        ? null
                        : entries.firstWhere((f) => f['family'] == family),
                    elementId: element?.id)));
      });
  Widget panel({bool includeElements = true}) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ListTile(
                title: Text(TicketLayoutStrings.canvasSize),
                subtitle: Text(
                    '${(controller.document.area.width * 25.4 / 72).toStringAsFixed(1)} × ${(controller.document.area.height * 25.4 / 72).toStringAsFixed(1)} mm'),
                trailing: const Icon(Icons.tune),
                onTap: imageBusy ? null : editDimensions)),
        ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(children: [
                  Text(TicketLayoutStrings.templateFont),
                  fontPicker(),
                  if (controller.selection != null &&
                      !['qr', 'logo']
                          .contains(controller.selection!.binding)) ...[
                    Text(TicketLayoutStrings.elementFont),
                    fontPicker(element: controller.selection!)
                  ]
                ])),
        if (includeElements) elements(),
        ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TicketLayoutProperties(
                controller: controller,
                defaults: propertyDefaults,
                backgroundImage:
                    resources.artworks.containsKey(controller.artworkKey)
                        ? resources.artworks[controller.artworkKey]!.image
                        : resources.background,
                metrics: resources.metricsFor(
                    controller.document, controller.selection),
                data: resources.scenarios[scenario])),
        Padding(
            padding: const EdgeInsets.all(12),
            child: ImageArea(
                imageUrl: background,
                hint: TicketLayoutStrings.background,
                enabled: !imageBusy,
                onFileSelected: upload,
                onRemove: removeBackground)),
        TextButton(
            onPressed: imageBusy
                ? null
                : () {
                    final preset = resources.presets[controller.artworkKey] ??
                        resources.preset;
                    setState(() => propertyDefaults = preset);
                    controller.replace(preset);
                  },
            child: Text(TicketLayoutStrings.reset))
      ]));
  Future<void> showMobilePanel(int tab) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Focus(
          autofocus: true,
          onKeyEvent: _historyKey,
          child: DefaultTabController(
              initialIndex: tab,
              length: 2,
              child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .72,
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: TabBar(tabs: [
                        Tab(text: TicketLayoutStrings.elements),
                        Tab(text: TicketLayoutStrings.properties),
                      ])),
                      IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close)),
                    ]),
                    Expanded(
                        child: TabBarView(
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                          Builder(
                              builder: (tabContext) => SingleChildScrollView(
                                  child: elements(
                                      onSelected: () =>
                                          DefaultTabController.of(tabContext)
                                              .animateTo(1)))),
                          panel(includeElements: false),
                        ])),
                  ])))));

  Widget mobileToolbar() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Row(children: [
                  IconButton(
                      tooltip: TicketLayoutStrings.undo,
                      onPressed: controller.canUndo ? controller.undo : null,
                      icon: const Icon(Icons.undo)),
                  IconButton(
                      tooltip: TicketLayoutStrings.redo,
                      onPressed: controller.canRedo ? controller.redo : null,
                      icon: const Icon(Icons.redo)),
                ])),
        if (resources.presets.length > 1)
          Expanded(
              child: TextButton(
                  onPressed: imageBusy ? null : chooseStyle,
                  child: Text(TicketLayoutStrings.styles))),
        IconButton(
            tooltip: TicketLayoutStrings.pdf,
            onPressed: pdfBusy || imageBusy || fontBusy ? null : preview,
            icon: pdfBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined)),
        IconButton(
            tooltip: TicketLayoutStrings.fit,
            onPressed: () => canvas.currentState?.fit(),
            icon: const Icon(Icons.fit_screen)),
        PopupMenuButton<String>(
            tooltip: TicketLayoutStrings.viewOptions,
            onSelected: (value) => setState(() {
                  switch (value) {
                    case 'multi':
                      additiveSelection = !additiveSelection;
                      pan = false;
                    case 'pan':
                      pan = !pan;
                    case 'page':
                      wholePage = !wholePage;
                    case 'grid':
                      grid = !grid;
                    case 'snap':
                      snap = !snap;
                    case 'zoomIn':
                      canvas.currentState?.zoomAt(1.2);
                    case 'zoomOut':
                      canvas.currentState?.zoomAt(1 / 1.2);
                    default:
                      scenario = value;
                  }
                }),
            itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                      value: 'multi',
                      checked: additiveSelection,
                      child: Text(TicketLayoutStrings.multiSelect)),
                  CheckedPopupMenuItem(
                      value: 'pan',
                      checked: pan,
                      child: Text(TicketLayoutStrings.pan)),
                  CheckedPopupMenuItem(
                      value: 'page',
                      checked: wholePage,
                      child: Text(TicketLayoutStrings.page)),
                  CheckedPopupMenuItem(
                      value: 'grid',
                      checked: grid,
                      child: Text(TicketLayoutStrings.grid)),
                  CheckedPopupMenuItem(
                      value: 'snap',
                      checked: snap,
                      child: Text(TicketLayoutStrings.snap)),
                  PopupMenuItem(
                      value: 'zoomIn', child: Text(TicketLayoutStrings.zoomIn)),
                  PopupMenuItem(
                      value: 'zoomOut',
                      child: Text(TicketLayoutStrings.zoomOut)),
                  const PopupMenuDivider(),
                  for (final s in ['normal', 'long', 'missing'])
                    CheckedPopupMenuItem(
                        value: s,
                        checked: scenario == s,
                        child: Text(TicketLayoutStrings.binding(s))),
                ]),
      ]));

  @override
  Widget build(BuildContext context) => Focus(
      autofocus: true,
      onKeyEvent: _historyKey,
      child: PopScope(
          canPop: false,
          child: Scaffold(
            appBar: AppBar(
                leading: IconButton(
                    tooltip: TicketLayoutStrings.cancel,
                    onPressed: cancel,
                    icon: const Icon(Icons.close)),
                title: Text(TicketLayoutStrings.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  Center(
                    child: TextButton.icon(
                        onPressed: imageBusy || fontBusy ? null : apply,
                        icon: const Icon(Icons.check),
                        label: Text(TicketLayoutStrings.apply)),
                  ),
                  const SizedBox(width: 8)
                ]),
            body: SafeArea(
                top: false,
                child: Column(children: [
                  if (resources.missingBackground &&
                      (background?.isNotEmpty ?? false))
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(TicketLayoutStrings.missingBackground)),
                  if (MediaQuery.sizeOf(context).width < 900)
                    mobileToolbar()
                  else
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ListenableBuilder(
                                  listenable: controller,
                                  builder: (c, _) => Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                                tooltip:
                                                    TicketLayoutStrings.undo,
                                                onPressed: controller.canUndo
                                                    ? controller.undo
                                                    : null,
                                                icon: const Icon(Icons.undo)),
                                            IconButton(
                                                tooltip:
                                                    TicketLayoutStrings.redo,
                                                onPressed: controller.canRedo
                                                    ? controller.redo
                                                    : null,
                                                icon: const Icon(Icons.redo))
                                          ])),
                              IconButton(
                                  tooltip: TicketLayoutStrings.select,
                                  isSelected: !pan,
                                  onPressed: () => setState(() => pan = false),
                                  icon: const Icon(Icons.near_me_outlined)),
                              IconButton(
                                  tooltip: TicketLayoutStrings.multiSelect,
                                  isSelected: additiveSelection,
                                  onPressed: () => setState(() {
                                        additiveSelection = !additiveSelection;
                                        pan = false;
                                      }),
                                  icon: const Icon(Icons.select_all)),
                              IconButton(
                                  tooltip: TicketLayoutStrings.pan,
                                  isSelected: pan,
                                  onPressed: () => setState(() => pan = true),
                                  icon: const Icon(Icons.pan_tool_outlined)),
                              IconButton(
                                  tooltip: TicketLayoutStrings.zoomOut,
                                  onPressed: () =>
                                      canvas.currentState?.zoomAt(1 / 1.2),
                                  icon: const Icon(Icons.remove)),
                              SizedBox(
                                  width: 64 *
                                      MediaQuery.textScalerOf(context).scale(1),
                                  child: ValueListenableBuilder(
                                      valueListenable: transform,
                                      builder: (c, m, _) => Text(
                                          '${(math.sqrt(math.pow(m.entry(0, 0), 2) + math.pow(m.entry(1, 0), 2)) * 100).round()}%',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontFeatures: [
                                            ui.FontFeature.tabularFigures()
                                          ])))),
                              IconButton(
                                  tooltip: TicketLayoutStrings.zoomIn,
                                  onPressed: () =>
                                      canvas.currentState?.zoomAt(1.2),
                                  icon: const Icon(Icons.add)),
                              TextButton(
                                  onPressed: () => canvas.currentState?.fit(),
                                  child: Text(TicketLayoutStrings.fit)),
                              FilterChip(
                                  label: Text(TicketLayoutStrings.page),
                                  selected: wholePage,
                                  onSelected: (v) =>
                                      setState(() => wholePage = v)),
                              PopupMenuButton<String>(
                                  tooltip: TicketLayoutStrings.sampleData,
                                  initialValue: scenario,
                                  onSelected: (s) =>
                                      setState(() => scenario = s),
                                  itemBuilder: (_) => [
                                        'normal',
                                        'long',
                                        'missing'
                                      ]
                                          .map((s) => CheckedPopupMenuItem(
                                              value: s,
                                              checked: scenario == s,
                                              child: Text(
                                                  TicketLayoutStrings.binding(
                                                      s))))
                                          .toList(),
                                  child: DecoratedBox(
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant)),
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.person_outline,
                                                    size: 18),
                                                const SizedBox(width: 6),
                                                Text(
                                                    TicketLayoutStrings.binding(
                                                        scenario),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelLarge),
                                                const SizedBox(width: 4),
                                                const Icon(Icons.expand_more,
                                                    size: 18),
                                              ])))),
                              FilterChip(
                                  label: Text(TicketLayoutStrings.grid),
                                  selected: grid,
                                  onSelected: (v) => setState(() => grid = v)),
                              FilterChip(
                                  label: Text(TicketLayoutStrings.snap),
                                  selected: snap,
                                  onSelected: (v) => setState(() => snap = v)),
                              if (resources.presets.length > 1)
                                OutlinedButton.icon(
                                    onPressed: imageBusy ? null : chooseStyle,
                                    icon: const Icon(
                                        Icons.dashboard_customize_outlined),
                                    label: Text(TicketLayoutStrings.styles)),
                              OutlinedButton.icon(
                                  onPressed: pdfBusy || imageBusy || fontBusy
                                      ? null
                                      : preview,
                                  icon: pdfBusy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(
                                          Icons.picture_as_pdf_outlined),
                                  label: Text(TicketLayoutStrings.pdf)),
                            ])),
                  ListenableBuilder(
                      listenable: controller,
                      builder: (c, _) => Column(children: [
                            if (pdfSignature != null &&
                                pdfSignature != signature)
                              Text(TicketLayoutStrings.pdfStale),
                            Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(TicketLayoutStrings.savedLater,
                                    style:
                                        Theme.of(context).textTheme.bodySmall))
                          ])),
                  Expanded(child: LayoutBuilder(builder: (c, constraints) {
                    final narrow = constraints.maxWidth < 900;
                    final view = TicketLayoutCanvas(
                        key: canvas,
                        controller: controller,
                        resources: resources,
                        data: resources.scenarios[scenario]!,
                        transform: transform,
                        pan: pan,
                        additiveSelection: additiveSelection,
                        wholePage: wholePage,
                        snap: snap,
                        grid: grid);
                    return narrow
                        ? Column(children: [
                            Expanded(child: view),
                            Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Expanded(
                                      child: OutlinedButton.icon(
                                          onPressed: () => showMobilePanel(0),
                                          icon:
                                              const Icon(Icons.layers_outlined),
                                          label: Text(
                                              TicketLayoutStrings.elements))),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: FilledButton.tonalIcon(
                                          onPressed: () => showMobilePanel(1),
                                          icon: const Icon(Icons.tune),
                                          label: Text(
                                              TicketLayoutStrings.properties))),
                                ]))
                          ])
                        : Row(children: [
                            SizedBox(
                                width: 200,
                                child:
                                    SingleChildScrollView(child: elements())),
                            Expanded(child: view),
                            SizedBox(
                                width: 260,
                                child: panel(includeElements: false))
                          ]);
                  })),
                ])),
          )));
}
