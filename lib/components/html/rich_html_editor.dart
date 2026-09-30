import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

import 'html_editor_document.dart';
import 'html_strings.dart';
import 'html_view.dart';
import 'rich_html_editor_controller.dart';
import 'rich_html_editor_dialog.dart';

class RichHtmlEditor extends StatefulWidget {
  const RichHtmlEditor(
      {required this.controller,
      this.enabled = true,
      this.fullscreen = false,
      super.key});
  final RichHtmlEditorController controller;
  final bool enabled;
  final bool fullscreen;
  @override
  State<RichHtmlEditor> createState() => _RichHtmlEditorState();
}

class _RichHtmlEditorState extends State<RichHtmlEditor> {
  SuperEditorIosControlsControllerWithNativePaste? _ios;
  Editor? _configuredEditor;
  late final SuperEditorAndroidControlsController _android;
  RichHtmlEditorController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    if (kIsWeb) ClipboardEvents.instance?.registerPasteEventListener(_webPaste);
    controller.addListener(_controllerChanged);
    _android = SuperEditorAndroidControlsController(
        toolbarBuilder: (context, key, focalPoint) =>
            AndroidTextEditingFloatingToolbar(
              floatingToolbarKey: key,
              focalPoint: focalPoint,
              onCutPressed: () {
                controller.operations.cut();
                _android.hideToolbar();
              },
              onCopyPressed: () {
                controller.operations.copy();
                _android.hideToolbar();
              },
              onPastePressed: () {
                _async(controller.paste);
                _android.hideToolbar();
              },
              onSelectAllPressed: () {
                controller.operations.selectAll();
                _android.hideToolbar();
              },
            ));
    _configureIos();
  }

  void _webPaste(ClipboardReadEvent event) {
    if (!widget.enabled || !controller.focusNode.hasFocus) return;
    _async(() => controller.pasteEvent(event));
  }

  void _controllerChanged() {
    if (_configuredEditor != controller.editor) {
      _configureIos();
      setState(() {});
    }
  }

  void _configureIos() {
    _ios?.dispose();
    _configuredEditor = controller.editor;
    _ios = SuperEditorIosControlsControllerWithNativePaste(
        editor: controller.editor,
        documentLayoutResolver: () =>
            controller.layoutKey.currentState as DocumentLayout,
        customPasteDataInserter: (_, reader) async {
          await ExceptionHandler.guardVoid(context, futureFunction: () async {
            await controller.pasteReader(reader);
          }, defaultErrorMessage: HtmlStrings.importFailed);
          return true; // Never fall through to the package's lossy Markdown path.
        });
  }

  @override
  void didUpdateWidget(RichHtmlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      controller.addListener(_controllerChanged);
    }
    if (oldWidget.controller != controller ||
        _configuredEditor != controller.editor) _configureIos();
  }

  @override
  void dispose() {
    if (kIsWeb)
      ClipboardEvents.instance?.unregisterPasteEventListener(_webPaste);
    controller.removeListener(_controllerChanged);
    _ios?.dispose();
    _android.dispose();
    super.dispose();
  }

  Future<void> _image() async {
    final selection = controller.editor.composer.selection;
    final revision = controller.revision;
    final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'],
        withData: true);
    if (selected == null || !mounted) return;
    final bytes = selected.files.single.bytes;
    if (bytes == null) throw StateError('Image bytes are unavailable');
    if (controller.revision != revision)
      throw StateError('The document changed during image selection');
    if (selection != null)
      controller.editor.execute([
        ChangeSelectionRequest(selection, SelectionChangeType.placeCaret,
            SelectionReason.userInteraction)
      ]);
    await controller.insertImage(bytes);
  }

  Future<void> _link() async {
    final selection = controller.editor.composer.selection;
    final text = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(HtmlStrings.link),
                content: TextField(
                    controller: text,
                    autofocus: true,
                    keyboardType: TextInputType.url),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(CommonStrings.storno)),
                  TextButton(
                      onPressed: () => Navigator.pop(context, text.text.trim()),
                      child: Text(CommonStrings.save)),
                ]));
    text.dispose();
    if (value == null || !mounted) return;
    final uri = Uri.tryParse(value);
    if (uri == null || !{'https', 'http', 'mailto', 'tel'}.contains(uri.scheme))
      throw StateError('Invalid link URL');
    if (selection != null)
      controller.editor.execute([
        ChangeSelectionRequest(selection, SelectionChangeType.placeCaret,
            SelectionReason.userInteraction)
      ]);
    controller.toggle(LinkAttribution(value));
  }

  Future<void> _imageUrl() async {
    final selection = controller.editor.composer.selection;
    final revision = controller.revision;
    final text = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(HtmlStrings.imageUrl),
                content: TextField(
                    controller: text,
                    autofocus: true,
                    keyboardType: TextInputType.url),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(CommonStrings.storno)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, text.text.trim()),
                      child: Text(CommonStrings.save))
                ]));
    text.dispose();
    if (value == null || !mounted) return;
    if (revision != controller.revision)
      throw StateError('The document changed during image selection');
    if (selection != null)
      controller.editor.execute([
        ChangeSelectionRequest(selection, SelectionChangeType.placeCaret,
            SelectionReason.userInteraction)
      ]);
    await controller.insertImageSource(value);
  }

  void _block(Attribution type) {
    final id = controller.editor.composer.selection?.extent.nodeId;
    if (id != null &&
        controller.editor.document.getNodeById(id) is ParagraphNode)
      controller.editor.execute(
          [ChangeParagraphBlockTypeRequest(nodeId: id, blockType: type)]);
  }

  void _align(TextAlign alignment) {
    final id = controller.editor.composer.selection?.extent.nodeId;
    if (id != null &&
        controller.editor.document.getNodeById(id) is ParagraphNode)
      controller.editor.execute(
          [ChangeParagraphAlignmentRequest(nodeId: id, alignment: alignment)]);
  }

  void _list(ListItemType type) {
    final id = controller.editor.composer.selection?.extent.nodeId;
    final node = id == null ? null : controller.editor.document.getNodeById(id);
    if (node is TextNode)
      controller.operations.convertToListItem(type, node.text);
  }

  void _indent(bool increase) {
    final id = controller.editor.composer.selection?.extent.nodeId;
    if (id == null ||
        controller.editor.document.getNodeById(id) is! ListItemNode) return;
    final index = controller.editor.document.getNodeIndexById(id);
    if (increase &&
        (index == 0 ||
            controller.editor.document.getNodeAt(index - 1) is! ListItemNode))
      return;
    controller.editor.execute([
      increase
          ? IndentListItemRequest(nodeId: id)
          : UnIndentListItemRequest(nodeId: id)
    ]);
  }

  Widget _tool(IconData icon, String label, VoidCallback action,
      {bool available = true, Attribution? attribution}) {
    final node = controller.editor.composer.selection?.extent;
    final documentNode = node == null
        ? null
        : controller.editor.document.getNodeById(node.nodeId);
    final active = attribution != null &&
        documentNode is TextNode &&
        documentNode.text.length > 0 &&
        node!.nodePosition is TextNodePosition &&
        documentNode.text.hasAttributionAt(
            ((node.nodePosition as TextNodePosition).offset - 1)
                .clamp(0, documentNode.text.length - 1),
            attribution: attribution);
    return IconButton(
        tooltip: label,
        icon: Icon(icon),
        color: active ? Theme.of(context).colorScheme.primary : null,
        onPressed: widget.enabled && available
            ? () {
                action();
                controller.focusNode.requestFocus();
              }
            : null);
  }

  void _async(Future<void> Function() action) =>
      ExceptionHandler.guardVoid(context,
          futureFunction: action,
          defaultErrorMessage: HtmlStrings.importFailed);

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled)
      return HtmlView(
          html: controller.html,
          imageBytesResolver: controller.media.previewBytes);
    return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Flex(
              direction: widget.fullscreen ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                    width: widget.fullscreen ? 56 : null,
                    child: SingleChildScrollView(
                        scrollDirection:
                            widget.fullscreen ? Axis.vertical : Axis.horizontal,
                        child: Flex(
                            direction: widget.fullscreen
                                ? Axis.vertical
                                : Axis.horizontal,
                            children: [
                              _tool(Icons.format_bold, HtmlStrings.bold,
                                  () => controller.toggle(boldAttribution),
                                  attribution: boldAttribution),
                              _tool(Icons.format_italic, HtmlStrings.italic,
                                  () => controller.toggle(italicsAttribution),
                                  attribution: italicsAttribution),
                              _tool(
                                  Icons.format_underlined,
                                  HtmlStrings.underline,
                                  () => controller.toggle(underlineAttribution),
                                  attribution: underlineAttribution),
                              _tool(
                                  Icons.format_strikethrough,
                                  HtmlStrings.strike,
                                  () => controller
                                      .toggle(strikethroughAttribution),
                                  attribution: strikethroughAttribution),
                              _tool(Icons.link, HtmlStrings.link,
                                  () => _async(_link)),
                              _tool(Icons.image_outlined, HtmlStrings.image,
                                  () => _async(_image),
                                  available: controller.owner.canImport),
                              _tool(Icons.content_paste, HtmlStrings.paste,
                                  () => _async(controller.paste)),
                              _tool(Icons.undo, HtmlStrings.undo,
                                  controller.undo),
                              _tool(Icons.redo, HtmlStrings.redo,
                                  controller.redo),
                              PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz),
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'imageUrl':
                                        _async(_imageUrl);
                                      case 'h2':
                                        _block(header2Attribution);
                                      case 'h3':
                                        _block(header3Attribution);
                                      case 'ol':
                                        _list(ListItemType.ordered);
                                      case 'ul':
                                        _list(ListItemType.unordered);
                                      case 'in':
                                        _indent(true);
                                      case 'out':
                                        _indent(false);
                                      case 'left':
                                        _align(TextAlign.left);
                                      case 'center':
                                        _align(TextAlign.center);
                                      case 'right':
                                        _align(TextAlign.right);
                                    }
                                    controller.focusNode.requestFocus();
                                  },
                                  itemBuilder: (_) => [
                                        if (controller.owner.canImport)
                                          PopupMenuItem(
                                              value: 'imageUrl',
                                              child:
                                                  Text(HtmlStrings.imageUrl)),
                                        for (final item in [
                                          ('h2', HtmlStrings.heading2),
                                          ('h3', HtmlStrings.heading3),
                                          ('ol', HtmlStrings.orderedList),
                                          ('ul', HtmlStrings.bulletList),
                                          ('in', HtmlStrings.indent),
                                          ('out', HtmlStrings.outdent),
                                          ('left', HtmlStrings.alignLeft),
                                          ('center', HtmlStrings.alignCenter),
                                          ('right', HtmlStrings.alignRight)
                                        ])
                                          PopupMenuItem(
                                              value: item.$1,
                                              child: Text(item.$2)),
                                      ]),
                            ]))),
                _documentViewport(ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 180),
                    child: SuperEditorAndroidControlsScope(
                        controller: _android,
                        child: SuperEditorIosControlsScope(
                            controller: _ios!,
                            child: CustomScrollView(
                                shrinkWrap: !widget.fullscreen,
                                physics: widget.fullscreen
                                    ? null
                                    : const NeverScrollableScrollPhysics(),
                                slivers: [
                                  SuperEditor(
                                    editor: controller.editor,
                                    autofocus: widget.fullscreen,
                                    focusNode: controller.focusNode,
                                    documentLayoutKey: controller.layoutKey,
                                    shrinkWrap: true,
                                    log: null,
                                    selectionPolicies:
                                        const SuperEditorSelectionPolicies(
                                            clearSelectionWhenEditorLosesFocus:
                                                false,
                                            clearSelectionWhenImeConnectionCloses:
                                                false),
                                    stylesheet: defaultStylesheet.copyWith(
                                        inlineTextStyler: htmlInlineTextStyler,
                                        documentPadding:
                                            const EdgeInsets.all(8),
                                        addRulesAfter: [
                                          StyleRule(
                                              BlockSelector.all,
                                              (doc, node) => {
                                                    Styles.textStyle:
                                                        htmlBlockTextStyler(
                                                            node,
                                                            Theme.of(context)
                                                                .textTheme
                                                                .bodyLarge!
                                                                .copyWith(
                                                                    height: 1.4,
                                                                    fontSize: switch (
                                                                        node.getMetadataValue(
                                                                            'blockType')) {
                                                                      final type
                                                                          when type ==
                                                                              header1Attribution =>
                                                                        30,
                                                                      final type
                                                                          when type ==
                                                                              header2Attribution =>
                                                                        24,
                                                                      final type
                                                                          when type ==
                                                                              header3Attribution =>
                                                                        20,
                                                                      _ => null,
                                                                    },
                                                                    fontFamily: node.getMetadataValue('blockType') ==
                                                                            const NamedAttribution('pre')
                                                                        ? 'monospace'
                                                                        : null)),
                                                    Styles.padding:
                                                        const CascadingPadding
                                                            .symmetric(
                                                            horizontal: 0),
                                                  })
                                        ]),
                                    componentBuilders: [
                                      _DraftImageBuilder(controller),
                                      _PreservedBuilder(
                                          controller, _editPreserved),
                                      ...defaultComponentBuilders
                                    ],
                                    keyboardActions: [
                                      if (!kIsWeb) _pasteShortcut,
                                      ...defaultImeKeyboardActions.where(
                                          (action) =>
                                              action != pasteWhenCmdVIsPressed)
                                    ],
                                  )
                                ]))))),
              ],
            ));
  }

  Widget _documentViewport(Widget document) =>
      widget.fullscreen ? Expanded(child: document) : document;

  ExecutionInstruction _pasteShortcut(
      {required SuperEditorContext editContext, required KeyEvent keyEvent}) {
    if (keyEvent is KeyDownEvent &&
        keyEvent.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _async(controller.paste);
      return ExecutionInstruction.haltExecution;
    }
    return ExecutionInstruction.continueExecution;
  }

  Future<void> _editPreserved(PreservedHtmlNode node) async {
    final html = await RichHtmlEditorDialog.show(context,
        initialHtml: node.html,
        owner: controller.owner,
        profile: controller.profile,
        media: controller.media);
    if (html != null && mounted) {
      controller.editor.execute([
        ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: PreservedHtmlNode(id: node.id, html: html))
      ]);
    }
  }
}

class _DraftImageBuilder extends ImageComponentBuilder {
  _DraftImageBuilder(this.controller);
  final RichHtmlEditorController controller;
  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel model) {
    if (model is! ImageComponentViewModel) return null;
    return ImageComponent(
        componentKey: context.componentKey,
        imageUrl: model.imageUrl,
        expectedSize: model.expectedSize,
        selection:
            model.selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
        selectionColor: model.selectionColor,
        opacity: model.opacity,
        imageBuilder: (_, source) {
          final bytes = controller.media.previewBytes(source);
          if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain);
          if (source.startsWith('data:image/'))
            return Image.memory(UriData.parse(source).contentAsBytes(),
                fit: BoxFit.contain);
          if (source.isEmpty) return const Icon(Icons.broken_image_outlined);
          if (controller.owner.canImport &&
              !controller.isOriginalImageSource(source))
            return _AuthorizedImagePreview(
                source: source, controller: controller);
          if (!{'http', 'https'}.contains(Uri.tryParse(source)?.scheme))
            return const Icon(Icons.broken_image_outlined);
          return CachedNetworkImage(
              imageUrl: source,
              imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined));
        });
  }
}

class _AuthorizedImagePreview extends StatefulWidget {
  const _AuthorizedImagePreview(
      {required this.source, required this.controller});
  final String source;
  final RichHtmlEditorController controller;
  @override
  State<_AuthorizedImagePreview> createState() =>
      _AuthorizedImagePreviewState();
}

class _AuthorizedImagePreviewState extends State<_AuthorizedImagePreview> {
  late Future<Uint8List> _bytes;
  void _load() {
    _bytes = widget.controller.media
        .previewSource(widget.source, widget.controller.owner);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AuthorizedImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.controller != widget.controller) _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Tooltip(
              message: HtmlStrings.importFailed,
              child: const Icon(Icons.broken_image_outlined));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return Image.memory(snapshot.data!, fit: BoxFit.contain);
      });
}

class _PreservedBuilder implements ComponentBuilder {
  _PreservedBuilder(this.controller, this.edit);
  final RichHtmlEditorController controller;
  final Future<void> Function(PreservedHtmlNode) edit;
  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
          Document document, DocumentNode node) =>
      node is PreservedHtmlNode
          ? HorizontalRuleComponentViewModel(
              nodeId: node.id, caretColor: Colors.transparent)
          : null;
  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel model) {
    final node = controller.editor.document.getNodeById(model.nodeId);
    if (node is! PreservedHtmlNode) return null;
    return BoxComponent(
        key: context.componentKey,
        child: Column(children: [
          HtmlView(
              html: node.html,
              imageBytesResolver: controller.media.previewBytes),
          TextButton.icon(
              onPressed: () => edit(node),
              icon: const Icon(Icons.edit),
              label: Text(CommonStrings.edit)),
        ]));
  }
}
