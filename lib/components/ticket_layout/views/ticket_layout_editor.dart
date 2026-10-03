import 'dart:convert';
import '../../fonts/font_family_picker.dart';
import '../../fonts/ticket_font_catalog.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _themeKey = GlobalKey();
  BuildContext get editorContext => _themeKey.currentContext ?? context;
  final canvas = GlobalKey<TicketLayoutCanvasState>();
  bool additiveSelection = false;
  bool editBackground = false,
      pan = false,
      wholePage = false,
      pdfBusy = false,
      imageBusy = false;
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
          context: editorContext,
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
          context: editorContext,
          builder: (c) => Dialog.fullscreen(
              child: Scaffold(
                  appBar:
                      AppBar(title: Text(TicketLayoutStrings.pdf), actions: [
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
            context: editorContext,
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
    final original = controller.document;
    final previousWholePage = wholePage;
    setState(() => wholePage = true);
    controller.beginGesture();
    final next = await showDialog<TicketTemplate>(
        context: editorContext,
        builder: (_) => TicketDimensionsDialog(
            document: original,
            type: widget.type,
            onPreview: (candidate) {
              controller.previewDocument(candidate);
              setState(() {});
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) canvas.currentState?.fit();
              });
            }));
    if (mounted) {
      wholePage = previousWholePage;
      if (next == null) {
        controller.cancelGesture();
      } else {
        controller.previewDocument(next);
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
          context: editorContext,
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  minLeadingWidth: 28,
                  horizontalTitleGap: 8,
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

  Widget fontPicker() => FutureBuilder<List<Map<String, dynamic>>>(
        future: fontCatalog,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final entries = snapshot.data!;
          final font = resources.fontFor(controller.document);
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: FontFamilyPicker(
              label: TicketLayoutStrings.templateFont,
              value: font.family,
              families: entries.map((f) => f['family'] as String).toList(),
              extraFamilies: entries
                  .where((f) => f['source'] == 'bundled')
                  .map((f) => f['family'] as String)
                  .toList(),
              canReset: controller.document.fontId != null,
              enabled: !imageBusy && !fontBusy,
              onSelected: (family) => selectFont(
                family == null
                    ? null
                    : entries.firstWhere((f) => f['family'] == family),
              ),
            ),
          );
        },
      );

  Widget? elementFontControl() {
    final element = controller.selection;
    if (element == null || ['qr', 'logo'].contains(element.binding))
      return null;
    final enabled = !imageBusy && !fontBusy && !element.locked;
    final family = resources
        .fontFor(controller.document, element)
        .family
        .replaceFirst(' (legacy)', '');
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            icon: const Icon(Icons.font_download_outlined, size: 18),
            label: Text(
              element.fontId == null
                  ? TicketLayoutStrings.fontForText
                  : '${TicketLayoutStrings.fontFamily}: $family',
            ),
            onPressed: enabled
                ? () async {
                    final entries = await fontCatalog;
                    if (!mounted) return;
                    await FontFamilyPicker.showChoices(
                      context,
                      title: TicketLayoutStrings.fontForText,
                      value: element.fontId == null
                          ? null
                          : resources
                              .fontFor(controller.document, element)
                              .family,
                      families:
                          entries.map((f) => f['family'] as String).toList(),
                      extraFamilies: entries
                          .where((f) => f['source'] == 'bundled')
                          .map((f) => f['family'] as String)
                          .toList(),
                      onSelected: (family) => selectFont(
                        family == null
                            ? null
                            : entries.firstWhere((f) => f['family'] == family),
                        elementId: element.id,
                      ),
                    );
                  }
                : null,
          ),
        ),
        if (element.fontId != null)
          IconButton(
            tooltip: TicketLayoutStrings.inheritFont,
            onPressed:
                enabled ? () => selectFont(null, elementId: element.id) : null,
            icon: const Icon(Icons.restore),
          ),
      ],
    );
  }

  Widget panel({bool includeElements = true}) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ListTile(
                title: Text(TicketLayoutStrings.canvasSize),
                subtitle: Text(
                    '${(controller.document.area.width * 25.4 / 72).toStringAsFixed(1)} × ${(controller.document.area.height * 25.4 / 72).toStringAsFixed(1)} mm · ${controller.document.fitPageToTicket ? TicketLayoutStrings.paperTicket : controller.document.page == const Size(595.28, 841.89) ? TicketLayoutStrings.paperA4 : TicketLayoutStrings.paperOriginal}'),
                trailing: const Icon(Icons.tune),
                onTap: imageBusy ? null : editDimensions)),
        ListenableBuilder(
            listenable: controller, builder: (context, _) => fontPicker()),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider()),
        if (includeElements) elements(),
        ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TicketLayoutProperties(
                controller: controller,
                fontControl: elementFontControl(),
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
        if (background?.isNotEmpty ?? false)
          OutlinedButton.icon(
              icon: const Icon(Icons.crop),
              label: Text(TicketLayoutStrings.positionImage),
              onPressed: imageBusy
                  ? null
                  : () {
                      setState(() {
                        editBackground = true;
                        pan = false;
                      });
                      controller.select(null);
                      if (MediaQuery.sizeOf(context).width < 900) {
                        Navigator.pop(context);
                      }
                    }),
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
  Widget backgroundTools() => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final doc = controller.document;
        final artwork = resources.artworks[controller.artworkKey];
        final image = artwork != null ? artwork.image : resources.background;
        void fitImage(bool cover) {
          if (image == null) return;
          final sx = doc.area.width / image.width,
              sy = doc.area.height / image.height;
          final scale = cover ? (sx > sy ? sx / sy : sy / sx) : 1.0;
          controller.changeBackground(scale, Offset.zero);
        }

        return Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(TicketLayoutStrings.dragImage),
                  TextButton(
                      onPressed: () => fitImage(false),
                      child: Text(TicketLayoutStrings.containImage)),
                  TextButton(
                      onPressed: () => fitImage(true),
                      child: Text(TicketLayoutStrings.coverImage)),
                  TextButton(
                      onPressed: () => controller.changeBackground(
                          doc.backgroundScale, Offset.zero),
                      child: Text(TicketLayoutStrings.centerImage)),
                  FilledButton(
                      onPressed: () => setState(() => editBackground = false),
                      child: Text(TicketLayoutStrings.doneImage)),
                ]));
      });

  Future<void> showMobilePanel(int tab) => showModalBottomSheet<void>(
      context: editorContext,
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
  Widget build(BuildContext context) => Theme(
      data: _editorTheme(Theme.of(context)),
      child: Builder(key: _themeKey, builder: _buildEditor));

  ThemeData _editorTheme(ThemeData inherited) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff334b70),
      brightness: inherited.brightness,
    );
    final palette = inherited.brightness == Brightness.dark
        ? colors
        : colors.copyWith(
            primary: const Color(0xff334b70),
            onPrimary: Colors.white,
            surface: Colors.white,
            surfaceContainerHighest: const Color(0xffeef0f3),
            outlineVariant: const Color(0xffdfe3e9),
            onSurface: const Color(0xff202a38),
            onSurfaceVariant: const Color(0xff637083),
          );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    final buttons = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      shape: WidgetStatePropertyAll(shape),
      iconSize: const WidgetStatePropertyAll(20),
      textStyle: WidgetStatePropertyAll(inherited.textTheme.labelLarge
          ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: palette,
      textTheme: inherited.textTheme
          .apply(bodyColor: palette.onSurface, displayColor: palette.onSurface),
      scaffoldBackgroundColor: palette.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 64,
        titleTextStyle: inherited.textTheme.titleLarge?.copyWith(
            color: palette.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(size: 20, color: palette.onSurfaceVariant),
      iconButtonTheme: IconButtonThemeData(
          style: buttons.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? palette.primaryContainer
                : null),
        foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.onSurface.withValues(alpha: .3)
                : states.contains(WidgetState.selected)
                    ? palette.primary
                    : palette.onSurfaceVariant),
      )),
      textButtonTheme: TextButtonThemeData(style: buttons),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: buttons.copyWith(
              side: WidgetStatePropertyAll(
                  BorderSide(color: palette.outlineVariant)))),
      filledButtonTheme: FilledButtonThemeData(style: buttons),
      segmentedButtonTheme: SegmentedButtonThemeData(
          style: buttons.copyWith(
              side: WidgetStatePropertyAll(
                  BorderSide(color: palette.outlineVariant)))),
      dividerTheme:
          DividerThemeData(color: palette.outlineVariant, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: palette.onSurfaceVariant,
        selectedColor: palette.primary,
        selectedTileColor: palette.primaryContainer.withValues(alpha: .5),
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.outlineVariant)),
      ),
      sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7)),
    );
  }

  Widget _toolToggle(String label, IconData icon, bool selected,
          ValueChanged<bool> onChanged) =>
      Builder(builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return Semantics(
            toggled: selected,
            child: TextButton.icon(
                style: TextButton.styleFrom(
                    backgroundColor: selected ? colors.primaryContainer : null,
                    foregroundColor: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant),
                onPressed: () => onChanged(!selected),
                icon: Icon(selected ? Icons.check : icon, size: 18),
                label: Text(label)));
      });

  Widget _toolDivider() =>
      const SizedBox(height: 24, child: VerticalDivider(width: 20));

  Widget _sidebar(String title, Widget child, double width) => Container(
      width: width,
      decoration: BoxDecoration(
        border: Border.symmetric(
            vertical: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: child),
      ]));

  Widget _buildEditor(BuildContext context) => Focus(
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
                  if (MediaQuery.sizeOf(context).width >= 900) ...[
                    if (resources.presets.length > 1)
                      OutlinedButton.icon(
                          onPressed: imageBusy ? null : chooseStyle,
                          icon: const Icon(Icons.dashboard_customize_outlined),
                          label: Text(TicketLayoutStrings.styles)),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                        onPressed:
                            pdfBusy || imageBusy || fontBusy ? null : preview,
                        icon: pdfBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(TicketLayoutStrings.pdf)),
                    const SizedBox(width: 12),
                  ],
                  Center(
                    child: FilledButton.icon(
                        onPressed: imageBusy || fontBusy ? null : apply,
                        icon: const Icon(Icons.check),
                        label: Text(TicketLayoutStrings.apply)),
                  ),
                  const SizedBox(width: 16)
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
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                            border: Border.symmetric(
                                horizontal: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant))),
                        child: Wrap(
                            spacing: 4,
                            runSpacing: 8,
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
                              _toolDivider(),
                              IconButton(
                                  tooltip: TicketLayoutStrings.select,
                                  isSelected: !pan && !additiveSelection,
                                  onPressed: () => setState(() {
                                        pan = false;
                                        additiveSelection = false;
                                      }),
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
                              _toolDivider(),
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
                              _toolToggle(
                                  TicketLayoutStrings.page,
                                  Icons.crop_portrait,
                                  wholePage,
                                  (v) => setState(() => wholePage = v)),
                              _toolDivider(),
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
                                              BorderRadius.circular(8),
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
                              _toolToggle(
                                  TicketLayoutStrings.grid,
                                  Icons.grid_4x4,
                                  grid,
                                  (v) => setState(() => grid = v)),
                              _toolToggle(
                                  TicketLayoutStrings.snap,
                                  Icons.vertical_align_center,
                                  snap,
                                  (v) => setState(() => snap = v)),
                            ])),
                  ListenableBuilder(
                      listenable: controller,
                      builder: (c, _) => Column(children: [
                            if (pdfSignature != null &&
                                pdfSignature != signature)
                              Text(TicketLayoutStrings.pdfStale),
                            Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Text(TicketLayoutStrings.savedLater,
                                    style:
                                        Theme.of(context).textTheme.bodySmall))
                          ])),
                  if (editBackground) backgroundTools(),
                  Expanded(child: LayoutBuilder(builder: (c, constraints) {
                    final narrow = constraints.maxWidth < 900;
                    final view = TicketLayoutCanvas(
                        key: canvas,
                        controller: controller,
                        resources: resources,
                        data: resources.scenarios[scenario]!,
                        transform: transform,
                        pan: pan,
                        editBackground: editBackground,
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
                            _sidebar(
                                TicketLayoutStrings.elements,
                                SingleChildScrollView(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: elements())),
                                200),
                            Expanded(child: view),
                            _sidebar(TicketLayoutStrings.properties,
                                panel(includeElements: false), 280)
                          ]);
                  })),
                ])),
          )));
}
