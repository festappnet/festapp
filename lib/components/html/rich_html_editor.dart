import 'package:fstapp/widgets/app_dialog.dart';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

import 'html_editor_document.dart';
import 'template_authoring.dart';
import 'html_image_preview.dart';
import 'html_strings.dart';
import 'html_text_style.dart';
import 'html_view.dart';
import 'rich_html_editor_controller.dart';

class RichHtmlEditor extends StatefulWidget {
  const RichHtmlEditor(
      {required this.controller,
      this.enabled = true,
      this.fullscreen = false,
      this.textStyle,
      this.onCancel,
      this.toolbarActions,
      super.key});
  final RichHtmlEditorController controller;
  final bool enabled;
  final bool fullscreen;
  final TextStyle? textStyle;
  final Widget? toolbarActions;

  /// When supplied, the enclosing edit session owns Escape cancellation.
  final VoidCallback? onCancel;
  @override
  State<RichHtmlEditor> createState() => _RichHtmlEditorState();
}

class _RichHtmlEditorState extends State<RichHtmlEditor> {
  bool get _sideToolbar =>
      widget.fullscreen && MediaQuery.sizeOf(context).width >= 600;
  double _documentWidth = 600;
  final _selectionLinks = SelectionLayerLinks();
  final _mentionOverlay = OverlayPortalController();
  bool _explicitChooser = false;
  bool _consumeEscapeUp = false;
  int _activeResult = 0;
  String _lastQuery = '';
  String _explicitQuery = '';
  DocumentSelection? _insertionSelection;
  int? _insertionRevision;
  List<TemplateAuthoringEntry> _results = [];
  final _menuScroll = ScrollController();
  bool get _menuOpen => _explicitChooser || controller.composingTag != null;
  void _mentionsChanged() {
    if (!mounted) return;
    final query = _explicitChooser
        ? _explicitQuery
        : controller.composingTag?.tag.raw.substring(1) ?? '';
    if (query != _lastQuery || !_mentionOverlay.isShowing) {
      _lastQuery = query;
      _activeResult = 0;
      _results =
          controller.authoring?.search(query, controller.templateUsage) ?? [];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_menuOpen) {
        _mentionOverlay.show();
      } else {
        _mentionOverlay.hide();
      }
      setState(() {});
    });
  }

  void _closeMentions() {
    _explicitChooser = false;
    controller.cancelTemplateQuery();
    _mentionOverlay.hide();
  }

  void _choose(TemplateAuthoringEntry entry) {
    if (!entry.repeatable && (controller.templateUsage[entry.code] ?? 0) > 0) return;
    final tag = controller.composingTag;
    final revision = controller.revision;
    if (controller.insertTemplateToken(entry.code,
        expectedTag: tag,
        expectedRevision: _explicitChooser ? _insertionRevision : revision,
        replacement: _explicitChooser ? _insertionSelection : null)) {
      _closeMentions();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.focusNode.requestFocus();
      });
    }
  }

  void _openMentions() {
    final selection = controller.editor.composer.selection;
    if (selection == null ||
        selection.base.nodePosition is! TextNodePosition ||
        selection.extent.nodePosition is! TextNodePosition) {
      final document = controller.editor.document;
      final node = document.whereType<TextNode>().lastOrNull ??
          (selection == null
              ? null
              : document.getNodeById(selection.extent.nodeId)) ??
          document.lastOrNull;
      if (node == null) return;
      controller.editor.execute([
        ChangeSelectionRequest(
            DocumentSelection.collapsed(
                position: DocumentPosition(
                    nodeId: node.id,
                    nodePosition: node is TextNode
                        ? node.endPosition
                        : selection?.extent.nodePosition ?? node.endPosition)),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction)
      ]);
    }
    _insertionSelection = controller.editor.composer.selection;
    _insertionRevision = controller.revision;
    _explicitChooser = true;
    _explicitQuery = '';
    controller.focusNode.requestFocus();
    _mentionsChanged();
  }

  bool _isSelectedToken(String code) {
    final selection = controller.editor.composer.selection;
    if (selection == null || selection.isCollapsed || selection.base.nodeId != selection.extent.nodeId) return false;
    final node = controller.editor.document.getNodeById(selection.extent.nodeId);
    final base = selection.base.nodePosition;
    final extent = selection.extent.nodePosition;
    if (node is! TextNode || base is! TextNodePosition || extent is! TextNodePosition) return false;
    final start = base.offset < extent.offset ? base.offset : extent.offset;
    final end = base.offset > extent.offset ? base.offset : extent.offset;
    return node.text.placeholders.entries.any((entry) => entry.key >= start && entry.key < end &&
      entry.value is TemplateTokenPlaceholder && (entry.value as TemplateTokenPlaceholder).code == code);
  }

  Widget _mentionMenu(BuildContext context) {
    final provider = controller.authoring!;
    final width = (MediaQuery.sizeOf(context).width - 24).clamp(0.0, 380.0);
    return Positioned(
        left: 0,
        top: 0,
        child: Follower.withOffset(
            link: _selectionLinks.caretLink,
            leaderAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 8),
            boundary: const SafeAreaFollowerBoundary(),
            showWhenUnlinked: false,
            child: SuperEditorPopover(
                popoverFocusNode: _popoverFocus,
                editorFocusNode: controller.focusNode,
                child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                        width: width,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: (MediaQuery.sizeOf(context).height -
                                      MediaQuery.viewInsetsOf(context).bottom) *
                                  .45),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            if (_explicitChooser)
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Focus(
                                      onKeyEvent: (_, event) {
                                        if (event.logicalKey ==
                                            LogicalKeyboardKey.escape) {
                                          if (event is KeyDownEvent) {
                                            _closeMentions();
                                            controller.focusNode.requestFocus();
                                          }
                                          return KeyEventResult.handled;
                                        }
                                        if (event is KeyDownEvent &&
                                            {
                                              LogicalKeyboardKey.arrowDown,
                                              LogicalKeyboardKey.arrowUp
                                            }.contains(event.logicalKey) &&
                                            _results.isNotEmpty) {
                                          setState(() => _activeResult =
                                              (_activeResult +
                                                      (event.logicalKey ==
                                                              LogicalKeyboardKey
                                                                  .arrowDown
                                                          ? 1
                                                          : -1)) %
                                                  _results.length);
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: TextField(
                                          autofocus: true,
                                          decoration: InputDecoration(
                                              labelText: provider.insertLabel,
                                              prefixIcon:
                                                  const Icon(Icons.search)),
                                          onChanged: (value) {
                                            _explicitQuery = value;
                                            _mentionsChanged();
                                          },
                                          onSubmitted: (_) {
                                            if (_results.isNotEmpty)
                                              _choose(_results[_activeResult]);
                                          }))),
                            Flexible(
                                child: Semantics(
                                    liveRegion: true,
                                    label:
                                        '${provider.insertLabel}: ${_results.length}',
                                    child: _results.isEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Text(provider.emptyLabel))
                                        : ListView.builder(
                                            controller: _menuScroll,
                                            shrinkWrap: true,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            itemCount: _results.length,
                                            itemBuilder: (_, index) {
                                              final entry = _results[index];
                                              final count =
                                                  controller.templateUsage[
                                                          entry.code] ??
                                                      0;
                                              final usedBlock =
                                                  !entry.repeatable && count > 0;
                                              final previous = index == 0
                                                  ? null
                                                  : _results[index - 1];
                                              final heading = _lastQuery
                                                      .isEmpty &&
                                                  (index == 0 ||
                                                      usedBlock &&
                                                          !(!previous!.repeatable &&
                                                              (controller.templateUsage[
                                                                          previous
                                                                              .code] ??
                                                                      0) >
                                                                  0));
                                              return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    if (heading)
                                                      Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .fromLTRB(
                                                                  16, 8, 16, 4),
                                                          child: Text(
                                                              usedBlock
                                                                  ? provider
                                                                      .usedBlocksLabel
                                                                  : provider
                                                                      .recommendedLabel,
                                                              style: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .labelMedium)),
                                                    ListTile(
                                                        dense: true,
                                                        visualDensity: const VisualDensity(vertical: -1),
                                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                                        enabled: !usedBlock,
                                                        selected: index ==
                                                            _activeResult,
                                                        title: Text(entry.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                                                        subtitle: Text(
                                                            [
                                                              if (usedBlock) provider.uniqueUsedLabel else entry.example,
                                                              if (count > 0 && !usedBlock)
                                                                '${provider.usedLabel} ($count)'
                                                            ]
                                                                .where((s) => s
                                                                    .isNotEmpty)
                                                                .join(' · '),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis),
                                                        onTap: usedBlock ? null : () => _choose(entry)),
                                                  ]);
                                            }))),
                          ]),
                        ))))));
  }

  ExecutionInstruction _authoringKeys(
      {required SuperEditorContext editContext, required KeyEvent keyEvent}) {
    final key = keyEvent.logicalKey;
    if (_consumeEscapeUp && key == LogicalKeyboardKey.escape) {
      if (keyEvent is KeyUpEvent) _consumeEscapeUp = false;
      return ExecutionInstruction.haltExecution;
    }
    if (_menuOpen) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.tab) {
        if (keyEvent is KeyDownEvent) {
          _consumeEscapeUp = key == LogicalKeyboardKey.escape;
          _closeMentions();
        }
        return key == LogicalKeyboardKey.tab
            ? ExecutionInstruction.continueExecution
            : ExecutionInstruction.haltExecution;
      }
      if ({
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.enter
      }.contains(key)) {
        if (keyEvent is KeyDownEvent && _results.isNotEmpty) {
          if (key == LogicalKeyboardKey.enter) {
            _choose(_results[_activeResult]);
          } else {
            setState(() => _activeResult = (_activeResult +
                    (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
                _results.length);
            if (_menuScroll.hasClients)
              _menuScroll.animateTo(
                  (_activeResult * 72.0)
                      .clamp(0.0, _menuScroll.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOut);
          }
        }
        return ExecutionInstruction.haltExecution;
      }
    }
    if (controller.authoring?.singleLine == true &&
        key == LogicalKeyboardKey.enter)
      return ExecutionInstruction.haltExecution;
    if (keyEvent is KeyDownEvent &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      if (key == LogicalKeyboardKey.keyZ) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          controller.redo();
        } else {
          controller.undo();
        }
        return ExecutionInstruction.haltExecution;
      }
      if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX) {
        _async(() => controller.copy(cut: key == LogicalKeyboardKey.keyX));
        return ExecutionInstruction.haltExecution;
      }
    }
    return ExecutionInstruction.continueExecution;
  }

  final _selectionToolbar = OverlayPortalController();
  final _popoverFocus = FocusNode();
  SuperEditorIosControlsControllerWithNativePaste? _ios;
  Editor? _configuredEditor;
  late final SuperEditorAndroidControlsController _android;
  RichHtmlEditorController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    if (kIsWeb) ClipboardEvents.instance?.registerPasteEventListener(_webPaste);
    controller.addListener(_controllerChanged);
    controller.authoringChanges.addListener(_mentionsChanged);
    controller.focusNode.addListener(_selectionChanged);
    _android = SuperEditorAndroidControlsController(
        toolbarBuilder: (context, key, focalPoint) =>
            AndroidTextEditingFloatingToolbar(
              floatingToolbarKey: key,
              focalPoint: focalPoint,
              onCutPressed: () {
                _async(() => controller.copy(cut: true));
                _android.hideToolbar();
              },
              onCopyPressed: () {
                _async(controller.copy);
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
    _configuredEditor?.composer.selectionNotifier
        .removeListener(_selectionChanged);
    _ios?.dispose();
    _configuredEditor = controller.editor;
    controller.editor.composer.selectionNotifier.addListener(_selectionChanged);
    _ios = _TemplateIosControls(controller,
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

  void _selectionChanged() {
    controller.authoring?.selectionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selection = controller.editor.composer.selection;
      final desktop = kIsWeb ||
          !{TargetPlatform.android, TargetPlatform.iOS}
              .contains(defaultTargetPlatform);
      final show = widget.enabled &&
          desktop &&
          controller.focusNode.hasFocus &&
          selection != null &&
          !selection.isCollapsed &&
          selection.base.nodePosition is TextNodePosition &&
          selection.extent.nodePosition is TextNodePosition;
      if (show && !_selectionToolbar.isShowing) {
        _selectionToolbar.show();
      }
      if (!show && _selectionToolbar.isShowing) {
        _selectionToolbar.hide();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _floatingToolbar(BuildContext context) => Positioned(
      left: 0,
      top: 0,
      child: Follower.withOffset(
          link: _selectionLinks.expandedSelectionBoundsLink,
          leaderAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -8),
          boundary: const SafeAreaFollowerBoundary(),
          showWhenUnlinked: false,
          child: SuperEditorPopover(
              popoverFocusNode: _popoverFocus,
              editorFocusNode: controller.focusNode,
              child: Material(
                  key: const ValueKey('html-selection-toolbar'),
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedBuilder(
                      animation: Listenable.merge([
                        controller,
                        controller.editor.composer.selectionNotifier
                      ]),
                      builder: (context, _) =>
                          Row(mainAxisSize: MainAxisSize.min, children: [
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
                                () =>
                                    controller.toggle(strikethroughAttribution),
                                attribution: strikethroughAttribution),
                            _tool(Icons.link, HtmlStrings.link,
                                () => _async(_link)),
                          ]))))));

  @override
  void didUpdateWidget(RichHtmlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      oldWidget.controller.authoringChanges.removeListener(_mentionsChanged);
      controller.authoringChanges.addListener(_mentionsChanged);
      oldWidget.controller.focusNode.removeListener(_selectionChanged);
      controller.addListener(_controllerChanged);
      controller.focusNode.addListener(_selectionChanged);
    }
    if (oldWidget.controller != controller ||
        _configuredEditor != controller.editor) _configureIos();
    _selectionChanged();
  }

  @override
  void dispose() {
    if (kIsWeb)
      ClipboardEvents.instance?.unregisterPasteEventListener(_webPaste);
    controller.removeListener(_controllerChanged);
    controller.authoringChanges.removeListener(_mentionsChanged);
    _menuScroll.dispose();
    controller.focusNode.removeListener(_selectionChanged);
    _configuredEditor?.composer.selectionNotifier
        .removeListener(_selectionChanged);
    _popoverFocus.dispose();
    _ios?.dispose();
    _android.dispose();
    super.dispose();
  }

  Future<void> _image() async {
    final selection = controller.editor.composer.selection;
    final revision = controller.revision;
    final selected = await FilePicker.pickFiles(
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
        builder: (context) => AppAlertDialog(
                onClose: () => Navigator.pop(context),
                title: Text(HtmlStrings.link),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: text,
                      autofocus: true,
                      keyboardType: TextInputType.url),
                  if (controller.authoring != null)
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: controller.authoring!.insertLabel),
                        items: controller.authoring!
                            .search('', const {})
                            .where((entry) => entry.url)
                            .map((entry) => DropdownMenuItem(
                                value: entry.code, child: Text(entry.label)))
                            .toList(),
                        onChanged: (code) {
                          if (code != null)
                            text.text = TemplateTokenPlaceholder(code).source;
                        }),
                ]),
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
    final variable = controller.authoring?.search('', const {}).any((entry) =>
            entry.url &&
            TemplateTokenPlaceholder(entry.code).source == value) ??
        false;
    if (!variable &&
        (uri == null ||
            !{'https', 'http', 'mailto', 'tel'}.contains(uri.scheme)))
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
        builder: (context) => AppAlertDialog(
                onClose: () => Navigator.pop(context),
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
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.toolbarActions != null) widget.toolbarActions!,
        HtmlView(
            html: controller.html,
            embeddedBlock: controller.embeddedBlock,
            imageBytesResolver: controller.media.previewBytes),
      ]);
    return LayoutBuilder(builder: (context, constraints) {
      _documentWidth = constraints.maxWidth;
      return OverlayPortal(
          controller: _mentionOverlay,
          overlayChildBuilder: _mentionMenu,
          child: OverlayPortal(
              controller: _selectionToolbar,
              overlayChildBuilder: _floatingToolbar,
              child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => Flex(
                        mainAxisSize: MainAxisSize.min,
                        direction:
                            _sideToolbar ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (controller.authoring?.singleLine != true)
                            _toolbarLayout(SizedBox(
                                width: _sideToolbar ? 56 : null,
                                child: SingleChildScrollView(
                                    scrollDirection: _sideToolbar
                                        ? Axis.vertical
                                        : Axis.horizontal,
                                    child: Flex(
                                        direction: _sideToolbar
                                            ? Axis.vertical
                                            : Axis.horizontal,
                                        children: [
                                          if (controller.authoring != null)
                                            IconButton(
                                                tooltip: controller.authoring!.insertLabel,
                                                onPressed: _openMentions,
                                                icon: const Icon(Icons.alternate_email)),
                                          _tool(
                                              Icons.format_bold,
                                              HtmlStrings.bold,
                                              () => controller
                                                  .toggle(boldAttribution),
                                              attribution: boldAttribution),
                                          _tool(
                                              Icons.format_italic,
                                              HtmlStrings.italic,
                                              () => controller
                                                  .toggle(italicsAttribution),
                                              attribution: italicsAttribution),
                                          _tool(
                                              Icons.format_underlined,
                                              HtmlStrings.underline,
                                              () => controller
                                                  .toggle(underlineAttribution),
                                              attribution:
                                                  underlineAttribution),
                                          _tool(
                                              Icons.format_strikethrough,
                                              HtmlStrings.strike,
                                              () => controller.toggle(
                                                  strikethroughAttribution),
                                              attribution:
                                                  strikethroughAttribution),
                                          _tool(Icons.link, HtmlStrings.link,
                                              () => _async(_link)),
                                          _tool(
                                              Icons.image_outlined,
                                              HtmlStrings.image,
                                              () => _async(_image),
                                              available:
                                                  controller.owner.canImport),
                                          _tool(
                                              Icons.content_paste,
                                              HtmlStrings.paste,
                                              () => _async(controller.paste)),
                                          _tool(Icons.undo, HtmlStrings.undo,
                                              controller.undo),
                                          _tool(Icons.redo, HtmlStrings.redo,
                                              controller.redo),
                                          PopupMenuButton<String>(
                                              icon:
                                                  const Icon(Icons.more_horiz),
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
                                                    _list(
                                                        ListItemType.unordered);
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
                                                controller.focusNode
                                                    .requestFocus();
                                              },
                                              itemBuilder: (_) => [
                                                    if (controller
                                                        .owner.canImport)
                                                      PopupMenuItem(
                                                          value: 'imageUrl',
                                                          child: Text(
                                                              HtmlStrings
                                                                  .imageUrl)),
                                                    for (final item in [
                                                      (
                                                        'h2',
                                                        HtmlStrings.heading2
                                                      ),
                                                      (
                                                        'h3',
                                                        HtmlStrings.heading3
                                                      ),
                                                      (
                                                        'ol',
                                                        HtmlStrings.orderedList
                                                      ),
                                                      (
                                                        'ul',
                                                        HtmlStrings.bulletList
                                                      ),
                                                      (
                                                        'in',
                                                        HtmlStrings.indent
                                                      ),
                                                      (
                                                        'out',
                                                        HtmlStrings.outdent
                                                      ),
                                                      (
                                                        'left',
                                                        HtmlStrings.alignLeft
                                                      ),
                                                      (
                                                        'center',
                                                        HtmlStrings.alignCenter
                                                      ),
                                                      (
                                                        'right',
                                                        HtmlStrings.alignRight
                                                      )
                                                    ])
                                                      PopupMenuItem(
                                                          value: item.$1,
                                                          child: Text(item.$2)),
                                                  ]),
                                        ])))),
                          if (controller.hasUnsupportedTokens &&
                              !widget.fullscreen)
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                    controller.authoring!.unsupportedLabel,
                                    style:
                                        Theme.of(context).textTheme.bodySmall)),
                          _documentViewport(ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight:
                                      controller.authoring?.singleLine == true
                                          ? 0
                                          : 180),
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
                                            if (controller.authoring != null)
                                              SliverToBoxAdapter(child: controller.authoring!.header(context) ?? const SizedBox.shrink()),
                                            SuperEditor(
                                              editor: controller.editor,
                                              inputRole:
                                                  'html-${identityHashCode(controller)}',
                                              imeConfiguration:
                                                  SuperEditorImeConfiguration(
                                                      keyboardActionButton:
                                                          controller.authoring
                                                                      ?.singleLine ==
                                                                  true
                                                              ? TextInputAction
                                                                  .done
                                                              : TextInputAction
                                                                  .newline),
                                              selectionLayerLinks:
                                                  _selectionLinks,
                                              documentOverlayBuilders: [
                                                for (final overlay
                                                    in defaultSuperEditorDocumentOverlayBuilders)
                                                  if (overlay
                                                      is DefaultCaretOverlayBuilder)
                                                    DefaultCaretOverlayBuilder(
                                                      caretStyle: overlay
                                                          .caretStyle
                                                          .copyWith(
                                                        color: Theme.of(context)
                                                                    .brightness ==
                                                                Brightness.dark
                                                            ? Colors.white
                                                            : Colors.black,
                                                      ),
                                                    )
                                                  else
                                                    overlay,
                                              ],
                                              contentTapDelegateFactories: [
                                                if (controller.authoring != null)
                                                  (_) => _TemplateInlineTapDelegate(controller),
                                                superEditorLaunchLinkTapHandlerFactory,
                                              ],
                                              autofocus: widget.fullscreen,
                                              focusNode: controller.focusNode,
                                              documentLayoutKey:
                                                  controller.layoutKey,
                                              shrinkWrap: true,
                                              log: null,
                                              selectionPolicies:
                                                  const SuperEditorSelectionPolicies(
                                                      clearSelectionWhenEditorLosesFocus:
                                                          false,
                                                      clearSelectionWhenImeConnectionCloses:
                                                          false),
                                              stylesheet:
                                                  defaultStylesheet.copyWith(
                                                      rules: controller.authoring?.singleLine == true ? const [] : null,
                                                      inlineWidgetBuilders: [
                                                        (context, style,
                                                            value) {
                                                          if (value
                                                              is! TemplateTokenPlaceholder)
                                                            return null;
                                                          final provider =
                                                              controller
                                                                  .authoring!;
                                                          final entry =
                                                              provider.entry(
                                                                  value.code);
                                                          final label =
                                                              entry?.label ??
                                                                  value.code;
                                                          if (entry?.rich ==
                                                                  true &&
                                                              !provider
                                                                  .singleLine) {
                                                            return SizedBox(
                                                                width: (_documentWidth -
                                                                        32)
                                                                    .clamp(80.0,
                                                                        680.0),
                                                                child: _TemplateComponent(
                                                                    selected: _isSelectedToken(value.code),
                                                                    occurrence: () => _templateOccurrence(controller, value.code, value),
                                                                    provider:
                                                                        provider,
                                                                    code: value
                                                                        .code));
                                                          }
                                                          final sample = entry
                                                                      ?.example
                                                                      .isNotEmpty ==
                                                                  true
                                                              ? entry!.example
                                                              : label;
                                                          final colors =
                                                              Theme.of(context)
                                                                  .colorScheme;
                                                          return Tooltip(
                                                              message:
                                                                  '$label\n${entry?.description ?? ''}\n${value.source}',
                                                              child: Semantics(
                                                                  label:
                                                                      '${provider.tokenLabel}: $label, $sample',
                                                                  excludeSemantics:
                                                                      true,
                                                                  child: Container(
                                                                      constraints: BoxConstraints(
                                                                          maxWidth: (_documentWidth - 72).clamp(80.0,
                                                                              600.0)),
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                          horizontal:
                                                                              5,
                                                                          vertical:
                                                                              2),
                                                                      decoration: BoxDecoration(
                                                                          color: colors
                                                                              .primaryContainer
                                                                              .withValues(alpha: .45),
                                                                          border: Border.all(color: colors.primary.withValues(alpha: .5)),
                                                                          borderRadius: BorderRadius.circular(4)),
                                                                      child: Text(sample, maxLines: provider.singleLine ? 1 : null, overflow: provider.singleLine ? TextOverflow.ellipsis : null, textScaler: TextScaler.noScaling, style: style.copyWith(color: colors.onSurface)))));
                                                        }
                                                      ],
                                                      inlineTextStyler:
                                                          htmlInlineTextStyler,
                                                      documentPadding: controller.authoring?.singleLine == true
                                                          ? const EdgeInsets.symmetric(vertical: 8)
                                                          : const EdgeInsets.all(8),
                                                      addRulesAfter: [
                                                        StyleRule(
                                                            BlockSelector.all,
                                                            (doc, node) => {
                                                                  if (controller
                                                                          .authoring
                                                                          ?.singleLine ==
                                                                      true)
                                                                    Styles.maxWidth:
                                                                        double
                                                                            .infinity,
                                                                  Styles.textStyle:
                                                                      htmlBlockTextStyler(
                                                                          node,
                                                                          (widget.textStyle ?? controller.authoring?.textStyle?.copyWith(color: htmlTextStyle(context).color) ?? htmlTextStyle(context))
                                                                              .copyWith(
                                                                            fontSize: (widget.textStyle ?? controller.authoring?.textStyle?.copyWith(color: htmlTextStyle(context).color) ?? htmlTextStyle(context)).fontSize! *
                                                                                switch (node.getMetadataValue('blockType')) {
                                                                                  final type when type == header1Attribution => 2.0,
                                                                                  final type when type == header2Attribution => 1.5,
                                                                                  final type when type == header3Attribution => 1.17,
                                                                                  _ => 1.0,
                                                                                },
                                                                            fontFamily: node.getMetadataValue('blockType') == const NamedAttribution('pre')
                                                                                ? 'monospace'
                                                                                : null,
                                                                          )),
                                                                  Styles
                                                                      .padding: controller
                                                                              .authoring !=
                                                                          null
                                                                      ? CascadingPadding.symmetric(
                                                                          horizontal:
                                                                              0,
                                                                          vertical: controller.authoring!.singleLine || node is TemplateTokenBlock
                                                                              ? 0
                                                                              : 8)
                                                                      : const CascadingPadding
                                                                          .symmetric(
                                                                          horizontal:
                                                                              0),
                                                                })
                                                      ]),
                                              componentBuilders: [
                                                _TemplateBlockBuilder(
                                                    controller),
                                                _DraftImageBuilder(controller),
                                                _PreservedBuilder(controller),
                                                ...defaultComponentBuilders
                                              ],
                                              keyboardActions: [
                                                if (controller.authoring !=
                                                    null)
                                                  _authoringKeys,
                                                if (widget.onCancel != null)
                                                  _cancelShortcut,
                                                if (!kIsWeb) _pasteShortcut,
                                                ...defaultImeKeyboardActions
                                                    .where((action) =>
                                                        action !=
                                                        pasteWhenCmdVIsPressed)
                                              ],
                                            ),
                                            if (controller.authoring != null)
                                              SliverToBoxAdapter(
                                                  child: controller.authoring!
                                                          .footer(context) ??
                                                      const SizedBox.shrink()),
                                          ]))))),
                        ],
                      ))));
    });
  }

  Widget _toolbarLayout(Widget tools) {
    final actions = widget.toolbarActions;
    if (actions == null || widget.fullscreen) return tools;
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 400) {
        return Row(children: [
          Expanded(child: tools),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth - 48),
            child: actions,
          ),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [actions, tools],
      );
    });
  }

  Widget _documentViewport(Widget document) {
    if (controller.authoring?.singleLine == true) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: document),
        IconButton(
            tooltip: controller.authoring!.insertLabel,
            onPressed: _openMentions,
            style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
            icon: const Icon(Icons.alternate_email, size: 20)),
      ]));
    }
    return widget.fullscreen ? Expanded(child: document) : document;
  }

  ExecutionInstruction _cancelShortcut(
      {required SuperEditorContext editContext, required KeyEvent keyEvent}) {
    if (keyEvent.logicalKey == LogicalKeyboardKey.escape) {
      if (keyEvent is KeyDownEvent) widget.onCancel?.call();
      return ExecutionInstruction.haltExecution;
    }
    return ExecutionInstruction.continueExecution;
  }

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
          if (bytes != null)
            return HtmlImagePreview(bytes, fit: BoxFit.contain);
          if (source.startsWith('data:image/'))
            return HtmlImagePreview(UriData.parse(source).contentAsBytes(),
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
        return HtmlImagePreview(snapshot.data!, fit: BoxFit.contain);
      });
}

class _PreservedBuilder implements ComponentBuilder {
  _PreservedBuilder(this.controller);
  final RichHtmlEditorController controller;
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
    final block = controller.embeddedBlock;
    if (block != null && block.matches(node.html)) {
      return BoxComponent(
        key: context.componentKey,
        child: AnimatedBuilder(
            animation: controller,
            builder: (buildContext, _) {
              return Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(
                    tooltip: HtmlStrings.moveUp,
                    onPressed: controller.canMoveBlock(node.id, -1)
                        ? () => controller.moveBlock(node.id, -1)
                        : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: HtmlStrings.moveDown,
                    onPressed: controller.canMoveBlock(node.id, 1)
                        ? () => controller.moveBlock(node.id, 1)
                        : null,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ]),
                block.builder(buildContext),
              ]);
            }),
      );
    }
    return BoxComponent(
        key: context.componentKey,
        child: HtmlView(
            html: node.html,
            imageBytesResolver: controller.media.previewBytes));
  }
}

/// Text components ignore child gestures; use the editor's native tap boundary.
class _TemplateInlineTapDelegate extends ContentTapDelegate {
  _TemplateInlineTapDelegate(this.controller);
  final RichHtmlEditorController controller;
  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final position = details.documentLayout.getDocumentPositionAtOffset(details.layoutOffset);
    final node = position == null ? null : controller.editor.document.getNodeById(position.nodeId);
    if (node is! TextNode) return TapHandlingInstruction.continueHandling;
    for (final entry in node.text.placeholders.entries) {
      final token = entry.value;
      if (token is! TemplateTokenPlaceholder || controller.authoring?.entry(token.code)?.rich != true) continue;
      final base = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: entry.key));
      final extent = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: entry.key + 1));
      final bounds = details.documentLayout.getRectForSelection(base, extent);
      if (bounds?.contains(details.layoutOffset) != true) continue;
      controller.focusNode.requestFocus();
      controller.editor.execute([
        ChangeSelectionRequest(DocumentSelection(base: base, extent: extent),
            SelectionChangeType.placeCaret, SelectionReason.userInteraction),
      ]);
      return TapHandlingInstruction.halt;
    }
    return TapHandlingInstruction.continueHandling;
  }
}

// Occurrence is document identity/order, never widget build order.
int _templateOccurrence(RichHtmlEditorController controller, String code, Object target) {
  var occurrence = 0;
  for (final node in controller.editor.document) {
    if (target is DocumentNode && node.id == target.id) return occurrence;
    if (node is TemplateTokenBlock && node.code == code) occurrence++;
    if (node is TextNode) {
      final placeholders = node.text.placeholders.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in placeholders) {
        final value = entry.value;
        if (identical(value, target)) return occurrence;
        if (value is TemplateTokenPlaceholder && value.code == code) occurrence++;
      }
    }
  }
  return occurrence;
}

class _TemplateBlockBuilder extends ComponentBuilder {
  _TemplateBlockBuilder(this.controller);
  final RichHtmlEditorController controller;
  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
          Document document, DocumentNode node) =>
      node is TemplateTokenBlock
          ? HorizontalRuleComponentViewModel(
              nodeId: node.id, caretColor: Colors.transparent)
          : null;
  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context,
      SingleColumnLayoutComponentViewModel model) {
    final node = controller.editor.document.getNodeById(model.nodeId);
    if (node is! TemplateTokenBlock) return null;
    final provider = controller.authoring!;
    return BoxComponent(
        key: context.componentKey,
        child: _TemplateComponent(
            provider: provider,
            code: node.code,
            occurrence: () => _templateOccurrence(controller, node.code, node),
            selected: (model as HorizontalRuleComponentViewModel).selection != null,
            onSelect: () {
              controller.focusNode.requestFocus();
              controller.editor.execute([
                ChangeSelectionRequest(
                    DocumentSelection(
                      base: DocumentPosition(nodeId: node.id, nodePosition: node.beginningPosition),
                      extent: DocumentPosition(nodeId: node.id, nodePosition: node.endPosition),
                    ),
                    SelectionChangeType.placeCaret,
                    SelectionReason.userInteraction),
              ]);
            },
            onDelete: () => controller.editor
                .execute([DeleteNodeRequest(nodeId: node.id)])));
  }
}

/// Atomic document object: identity stays in the editor, content is only a sample.
class _TemplateComponent extends StatefulWidget {
  const _TemplateComponent({required this.provider, required this.code,
    this.selected = false, this.onSelect, this.onDelete, this.occurrence});
  final TemplateAuthoringProvider provider;
  final ValueGetter<int>? occurrence;
  final String code;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onDelete;
  @override
  State<_TemplateComponent> createState() => _TemplateComponentState();
}

class _TemplateComponentState extends State<_TemplateComponent> {
  bool _hovered = false;
  bool _focused = false;
  final _focus = FocusNode();
  @override
  void dispose() { _focus.dispose(); super.dispose(); }
  void _showInfo() {
    final entry = widget.provider.entry(widget.code);
    showDialog<void>(context: context, builder: (context) => AppAlertDialog(
      title: Text(entry?.label ?? widget.code),
      content: Text('${entry?.description ?? ''}\n\n${widget.provider.sampleLabel} · {{${widget.code}}}'),
      onClose: () => Navigator.pop(context)));
  }
  @override
  Widget build(BuildContext context) {
    final entry = widget.provider.entry(widget.code);
    final colors = Theme.of(context).colorScheme;
    final selected = _focused || widget.selected;
    final active = _hovered || selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(focusNode: _focus,
        onFocusChange: (value) => setState(() => _focused = value),
        child: Semantics(label: '${entry?.label ?? widget.code}. ${entry?.description ?? ''}',
          onLongPress: _showInfo,
          child: GestureDetector(behavior: HitTestBehavior.translucent,
            onTap: widget.onSelect ?? _focus.requestFocus,
            child: Stack(children: [
              widget.provider.preview(context, widget.code, occurrence: widget.occurrence) ?? Text(widget.provider.sampleLabel),
              if (active) Positioned.fill(child: IgnorePointer(child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(
                  color: selected ? colors.primary : colors.primary.withValues(alpha: .7),
                  width: selected ? 2 : 1.5))))),
              if (active) Positioned(top: 0, right: 0,
                child: Material(color: colors.surfaceContainerHigh, elevation: 2,
                  borderRadius: BorderRadius.circular(6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: '${entry?.label ?? widget.code}: ${entry?.description ?? ''}',
                      onPressed: _showInfo, icon: const Icon(Icons.info_outline, size: 18)),
                    if (widget.onDelete != null) IconButton(
                      tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                      onPressed: widget.onDelete, icon: const Icon(Icons.close, size: 18)),
                  ]))),
            ])))));
  }
}

class _TemplateIosControls
    extends SuperEditorIosControlsControllerWithNativePaste {
  _TemplateIosControls(this.owner,
      {required super.editor,
      required super.documentLayoutResolver,
      super.customPasteDataInserter});
  final RichHtmlEditorController owner;
  @override
  DocumentFloatingToolbarBuilder? get toolbarBuilder => owner.authoring == null
      ? super.toolbarBuilder
      : (context, key, point) => IOSTextEditingFloatingToolbar(
          floatingToolbarKey: key,
          focalPoint: point,
          onCopyPressed: () {
            owner.copy();
            hideToolbar();
          },
          onCutPressed: () {
            owner.copy(cut: true);
            hideToolbar();
          },
          onPastePressed: () {
            onUserRequestedPaste();
            hideToolbar();
          });
}
