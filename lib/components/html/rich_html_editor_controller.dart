import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';
import 'package:html/parser.dart' as html_parser;

import 'html_editor_document.dart';
import 'html_embedded_block.dart';
import 'template_authoring.dart';
import 'html_document_codec.dart';
import 'html_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'html_media_service.dart';

export 'html_media_service.dart' show HtmlMediaOwner, HtmlContentProfile;

/// One edit session. Domain callers exchange HTML, never document nodes.
class RichHtmlEditorController extends ChangeNotifier {
  RichHtmlEditorController(
      {String? initialHtml,
      this.embeddedBlock,
      required this.owner,
      this.profile = HtmlContentProfile.appContent,
      HtmlMediaDraft? media,
      this.authoring})
      : originalHtml = initialHtml ?? '',
        media = media ?? HtmlMediaDraft(),
        _ownsMedia = media == null {
    _load(initialHtml);
  }
  final HtmlMediaOwner owner;
  final HtmlEmbeddedBlock? embeddedBlock;
  final HtmlContentProfile profile;
  final TemplateAuthoringProvider? authoring;
  ActionTagsPlugin? _tags;
  final _tagReactions = <EditReaction>[];
  IndexedTag? get composingTag => _validTag;
  IndexedTag? _validTag;
  final authoringChanges = ChangeNotifier();
  void refreshAuthoringPresentation() => authoringChanges.notifyListeners();
  static final _tagRule = TagRule(trigger: '@', excludedCharacters: {
    ' ',
    '\n',
    '\r',
    '\t',
    '.',
    ',',
    ';',
    ':',
    '!',
    '?'
  });
  String originalHtml;
  final HtmlMediaDraft media;
  final bool _ownsMedia;
  late HtmlEditorDocument _codec;
  late String _baselineHtml;
  late Editor editor;
  final focusNode = FocusNode();
  final layoutKey = GlobalKey();
  int revision = 0;
  int _generation = 0;
  bool _disposed = false;
  String? _cachedHtml;
  late Set<String> _originalImageSources;

  bool isOriginalImageSource(String source) =>
      _originalImageSources.contains(source);

  String get html => _cachedHtml ??= _codec.isUnchanged
      ? _codec.encode()
      : applyHtmlContentProfile(_codec.encode(), profile);
  bool get hasUserChanges => !_codec.isUnchanged;
  bool get isDirty => !_codec.isUnchanged || _baselineHtml != originalHtml;
  bool get isEmpty => editor.document.every(
      (node) => node is TextNode && node.text.toPlainText().trim().isEmpty);
  CommonEditorOperations get operations => CommonEditorOperations(
      document: editor.document,
      editor: editor,
      composer: editor.composer,
      documentLayoutResolver: () => layoutKey.currentState as DocumentLayout);

  void _load(String? value) {
    _codec = HtmlEditorDocument(normalizeHtmlContentStyles(value ?? '', profile),
        tokenCodes: authoring?.codes ?? const {},
        blockCodes: authoring?.codes
                .where((c) => authoring!.entry(c)?.block == true)
                .toSet() ??
            const {});
    _originalImageSources = HtmlDocumentCodec.decode(value)
        .imageSlots
        .map((image) => image.source ?? image.attributes['data-src'])
        .whereType<String>()
        .toSet();
    _baselineHtml = _codec.encode();
    editor = createDefaultDocumentEditor(
        document: _codec.document, isHistoryEnabled: true);
    // HTML profiles own link normalization. Markdown prefixes, smart dashes
    // and bare image URL reactions must not rewrite songs or email templates.
    editor.reactionPipeline.removeWhere(
        (reaction) => reaction is! UpdateComposerTextStylesReaction);
    if (authoring != null) {
      _tags = ActionTagsPlugin(tagRule: _tagRule)..attach(editor);
      // Native tag decoration belongs to the same undo item as typing/insertion.
      // Keep the upstream reaction intact; only schedule it before history closes.
      for (var i = 0; i < editor.reactionPipeline.length; i++) {
        final reaction = editor.reactionPipeline[i];
        if (reaction is ActionTagComposingReaction) {
          final atomic = _AtomicActionTagReaction(reaction);
          _tagReactions.add(atomic);
          editor.reactionPipeline[i] = atomic;
        }
      }
      _tags!.composingActionTag.addListener(_tagChanged);
    }
    if (authoring?.singleLine == true)
      editor.requestHandlers.insert(0, (editor, request) {
        if (request is SplitParagraphRequest) return _IgnoreSubjectNewline();
        if (request is ChangeSelectionRequest &&
            request.newSelection != null &&
            editor.document.getNodeById(request.newSelection!.extent.nodeId) ==
                null) return _IgnoreSubjectNewline();
        if (request is InsertTextRequest)
          return InsertTextCommand(
              documentPosition: request.documentPosition,
              textToInsert:
                  request.textToInsert.replaceAll(RegExp(r'[\r\n]+'), ' '),
              attributions: {},
              createdAt: request.createdAt);
        if (request is InsertAttributedTextRequest)
          return InsertAttributedTextCommand(
              documentPosition: request.documentPosition,
              textToInsert: tokenizeTemplateText(
                  AttributedText(templatePlainText(request.textToInsert)
                      .replaceAll(RegExp(r'[\r\n]+'), ' ')),
                  authoring!.codes),
              createdAt: request.createdAt);
        return null;
      });
    editor.document.addListener(_changed);
  }

  void _changed(DocumentChangeLog _) {
    revision++;
    _cachedHtml = null;
    notifyListeners();
  }

  void reset(String html) {
    _generation++;
    originalHtml = html;
    _detachTags();
    editor.document.removeListener(_changed);
    editor.dispose();
    _cachedHtml = null;
    _load(html);
    revision++;
    notifyListeners();
  }

  void _detachTags() {
    editor.reactionPipeline.removeWhere(_tagReactions.contains);
    _tagReactions.clear();
    _tags?.composingActionTag.removeListener(_tagChanged);
    _tags?.detach(editor);
    _tags?.dispose();
    _tags = null;
    _validTag = null;
  }

  void _tagChanged() {
    final tag = _tags?.composingActionTag.value;
    final node = tag == null ? null : editor.document.getNodeById(tag.nodeId);
    _validTag = null;
    if (tag != null && node is TextNode) {
      final attrs = node.text.getAllAttributionsAt(tag.startOffset);
      if (authoring!.canTrigger(node.text.toPlainText(), tag.startOffset,
          inLink: attrs.any((a) => a is LinkAttribution),
          inCode: attrs.contains(codeAttribution),
          composing: editor.composer.composingRegion.value != null)) {
        _validTag = tag;
      } else {
        // Clear before publishing UI state; cancelling through the editor is
        // deferred because this listener can run inside its reaction pipeline.
        _tags!.composingActionTag.value = null;
        final generation = _generation;
        scheduleMicrotask(() {
          if (!_disposed &&
              generation == _generation &&
              _validTag == null &&
              _tags?.composingActionTag.value == null)
            editor.execute([CancelComposingActionTagRequest(_tagRule)]);
        });
      }
    }
    authoringChanges.notifyListeners();
  }

  void cancelTemplateQuery() {
    editor.execute([CancelComposingActionTagRequest(_tagRule)]);
    _validTag = null;
    authoringChanges.notifyListeners();
  }

  String get plainText => editor.document
      .whereType<TextNode>()
      .map((node) => templatePlainText(node.text))
      .join(authoring?.singleLine == true ? ' ' : '\n');

  bool get hasUnsupportedTokens {
    if (authoring == null) return false;
    final pattern = RegExp(r'\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}');
    final value = plainText;
    return pattern
            .allMatches(value)
            .any((m) => !authoring!.supports(m.group(1)!)) ||
        value.replaceAll(pattern, '').contains('{{');
  }

  Map<String, int> get templateUsage {
    final counts = <String, int>{};
    for (final block in editor.document.whereType<TemplateTokenBlock>()) {
      counts.update(block.code, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final node in editor.document.whereType<TextNode>()) {
      for (final token in node.text.placeholders.values
          .whereType<TemplateTokenPlaceholder>()) {
        counts.update(token.code, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  /// Range and revision are checked again immediately before one history batch.
  bool insertTemplateToken(String code,
      {IndexedTag? expectedTag,
      int? expectedRevision,
      DocumentSelection? replacement,
      String? expectedText}) {
    final entry = authoring?.entry(code);
    if (entry == null ||
        !entry.repeatable && (templateUsage[code] ?? 0) > 0 ||
        !authoring!.search('', const {}).any((e) => e.code == code) ||
        expectedRevision != null && revision != expectedRevision) return false;
    var selection = replacement ?? editor.composer.selection;
    if (expectedTag != null) {
      final node = editor.document.getNodeById(expectedTag.nodeId);
      if (node is! TextNode ||
          expectedTag.endOffset > node.text.length ||
          node.text
                  .toPlainText()
                  .substring(expectedTag.startOffset, expectedTag.endOffset) !=
              expectedTag.tag.raw) return false;
      selection =
          DocumentSelection(base: expectedTag.start, extent: expectedTag.end);
    }
    // A loaded template may contain only atomic blocks. Opening the chooser
    // keeps that document intact; choosing an entry creates its actual node.
    final anchor = selection == null
        ? null
        : editor.document.getNodeById(selection.extent.nodeId);
    if (anchor is TemplateTokenBlock &&
        selection!.isCollapsed &&
        selection.extent.nodePosition is UpstreamDownstreamNodePosition &&
        expectedTag == null &&
        expectedText == null &&
        !authoring!.singleLine) {
      if (!authoring!.canInsert('', 0,
          composing: editor.composer.composingRegion.value != null))
        return false;
      final position =
          selection.extent.nodePosition as UpstreamDownstreamNodePosition;
      final index = editor.document.getNodeIndexById(anchor.id) +
          (position.affinity == TextAffinity.downstream ? 1 : 0);
      final DocumentNode inserted = authoring!.entry(code)!.block
          ? TemplateTokenBlock(id: Editor.createNodeId(), code: code)
          : ParagraphNode(
              id: Editor.createNodeId(),
              text: tokenizeTemplateText(AttributedText('{{$code}}'), {code}));
      editor.execute([
        InsertNodeAtIndexRequest(nodeIndex: index, newNode: inserted),
        ChangeSelectionRequest(
            DocumentSelection.collapsed(
                position: DocumentPosition(
                    nodeId: inserted.id, nodePosition: inserted.endPosition)),
            SelectionChangeType.insertContent,
            SelectionReason.userInteraction),
      ]);
      focusNode.requestFocus();
      return true;
    }
    if (selection == null ||
        selection.base.nodeId != selection.extent.nodeId ||
        selection.base.nodePosition is! TextNodePosition ||
        selection.extent.nodePosition is! TextNodePosition) return false;
    final node = editor.document.getNodeById(selection.base.nodeId);
    if (node is! TextNode) return false;
    final a = (selection.base.nodePosition as TextNodePosition).offset;
    final b = (selection.extent.nodePosition as TextNodePosition).offset;
    final start = a < b ? a : b;
    final end = a > b ? a : b;
    if (start < 0 || end > node.text.length) return false;
    final attrs = node.text.isEmpty
        ? <Attribution>{}
        : node.text.getAllAttributionsAt(start.clamp(0, node.text.length - 1));
    if (expectedText != null &&
        node.text.toPlainText().substring(start, end) != expectedText)
      return false;
    if (expectedTag == null &&
        !authoring!.canInsert(node.text.toPlainText(), start,
            inLink: attrs.any((a) => a is LinkAttribution),
            inCode: attrs.contains(codeAttribution),
            composing: editor.composer.composingRegion.value != null))
      return false;
    if (expectedTag != null &&
        !authoring!.canTrigger(node.text.toPlainText(), start,
            inLink: attrs.any((a) => a is LinkAttribution),
            inCode: attrs.contains(codeAttribution),
            composing: editor.composer.composingRegion.value != null))
      return false;
    final position = DocumentPosition(
        nodeId: node.id, nodePosition: TextNodePosition(offset: start));
    // The native reaction must clear its range before structured paste can
    // remove that paragraph. This changes decorations, not saved content.
    if (expectedTag != null) {
      editor.execute([CancelComposingActionTagRequest(_tagRule)]);
    }
    editor.execute([
      if (!selection.isCollapsed)
        DeleteContentRequest(documentRange: selection),
      ChangeSelectionRequest(DocumentSelection.collapsed(position: position),
          SelectionChangeType.placeCaret, SelectionReason.userInteraction),
      if (authoring!.entry(code)!.block)
        PasteStructuredContentEditorRequest(
            content: MutableDocument(nodes: [
              TemplateTokenBlock(id: Editor.createNodeId(), code: code),
              ParagraphNode(id: Editor.createNodeId(), text: AttributedText())
            ]),
            pastePosition: position)
      else
        InsertInlinePlaceholderAtCaretRequest(TemplateTokenPlaceholder(code)),
      CancelComposingActionTagRequest(_tagRule),
    ]);
    focusNode.requestFocus();
    return true;
  }

  ({String text, String html})? selectedTemplateContent() {
    final selection = editor.composer.selection;
    if (selection == null || selection.isCollapsed) return null;
    final range =
        editor.document.getRangeBetween(selection.base, selection.extent);
    final text = <String>[];
    final html = <String>[];
    final nodes = editor.document.getNodesInside(range.start, range.end);
    for (final node in nodes) {
      if (node is TemplateTokenBlock) {
        final source = TemplateTokenPlaceholder(node.code).source;
        text.add(source);
        html.add(source);
      }
      if (node is TextNode) {
        final start = node.id == range.start.nodeId
            ? (range.start.nodePosition as TextNodePosition).offset
            : 0;
        final end = node.id == range.end.nodeId
            ? (range.end.nodePosition as TextNodePosition).offset
            : node.text.length;
        final selected = node.text.copyText(start, end);
        text.add(templatePlainText(selected));
        html.add('<p>${templateInlineHtml(selected)}</p>');
      }
    }
    return (text: text.join('\n'), html: html.join());
  }

  Future<void> copy({bool cut = false}) async {
    if (authoring == null) {
      if (cut) {
        operations.cut();
      } else {
        operations.copy();
      }
      return;
    }
    final selected = selectedTemplateContent();
    if (selected == null) return;
    final selection = editor.composer.selection!;
    final version = revision;
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    await clipboard.write([
      DataWriterItem()
        ..add(Formats.plainText(selected.text))
        ..add(Formats.htmlText(selected.html))
    ]);
    if (cut && version == revision) {
      editor.execute([DeleteContentRequest(documentRange: selection)]);
    }
  }

  Future<String> prepareForSave({BuildContext? context}) async {
    if (context != null &&
        !await confirmHtmlUploadRetry(context, media, html: html))
      throw StateError('Image retry cancelled');
    return media.prepareHtml(html, originalHtml, owner);
  }

  /// Editing any part of a link updates its full span, including mixed styles.
  ({DocumentSelection selection, String? url})? get linkEditingTarget {
    final selection = editor.composer.selection;
    if (selection == null) return null;
    final fallback = (selection: selection, url: null as String?);
    if (selection.base.nodeId != selection.extent.nodeId) return fallback;
    final node = editor.document.getNodeById(selection.base.nodeId);
    final base = selection.base.nodePosition;
    final extent = selection.extent.nodePosition;
    if (node is! TextNode ||
        base is! TextNodePosition ||
        extent is! TextNodePosition ||
        node.text.isEmpty) return fallback;
    final start = base.offset < extent.offset ? base.offset : extent.offset;
    final end = base.offset > extent.offset ? base.offset : extent.offset;
    var offset = start;
    LinkAttribution? link;
    if (selection.isCollapsed) {
      if (offset < node.text.length) {
        link = node.text
            .getAllAttributionsAt(offset)
            .whereType<LinkAttribution>()
            .firstOrNull;
      }
      if (link == null && offset > 0) {
        offset--;
        link = node.text
            .getAllAttributionsAt(offset)
            .whereType<LinkAttribution>()
            .firstOrNull;
      }
    } else {
      link = node.text
          .getAllAttributionsThroughout(SpanRange(start, end - 1))
          .whereType<LinkAttribution>()
          .firstOrNull;
    }
    if (link == null) return fallback;
    final span = node.text.getAttributedRange({link}, offset);
    return (
      selection: DocumentSelection(
          base: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: span.start)),
          extent: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: span.end + 1))),
      url: link.plainTextUri,
    );
  }

  /// Replace link attributes in one undo step; other formatting stays intact.
  void setLink(DocumentSelection selection, String? url) {
    final range = DocumentRange(start: selection.base, end: selection.extent);
    final links = <Attribution>{
      for (final node in editor.document.getNodesInside(range.start, range.end))
        if (node is TextNode)
          for (final span in node.text.getAttributionSpansByFilter(
              (attribution) => attribution is LinkAttribution))
            span.attribution,
    };
    editor.execute([
      ChangeSelectionRequest(selection, SelectionChangeType.placeCaret,
          SelectionReason.userInteraction),
      if (selection.isCollapsed && url != null)
        InsertTextRequest(
            documentPosition: selection.extent,
            textToInsert: url,
            attributions: {LinkAttribution(url)})
      else ...[
        if (links.isNotEmpty)
          RemoveTextAttributionsRequest(
              documentRange: range, attributions: links),
        if (url != null)
          AddTextAttributionsRequest(
              documentRange: range, attributions: {LinkAttribution(url)}),
      ],
    ]);
  }

  void toggle(Attribution attribution) =>
      operations.toggleAttributionsOnSelection({attribution});
  bool canMoveBlock(String nodeId, int offset) => _codec.canMoveNode(
      nodeId, editor.document.getNodeIndexById(nodeId) + offset);

  void moveBlock(String nodeId, int offset) {
    if (!canMoveBlock(nodeId, offset)) return;
    editor.execute([
      MoveNodeRequest(
          nodeId: nodeId,
          newIndex: editor.document.getNodeIndexById(nodeId) + offset)
    ]);
  }

  void undo() {
    if (authoring == null) {
      editor.undo();
      return;
    }
    final before = html;
    var remaining = editor.history.length;
    do {
      editor.undo();
    } while (--remaining > 0 && html == before);
  }

  void redo() {
    if (authoring == null) {
      editor.redo();
      return;
    }
    final before = html;
    var remaining = editor.future.length;
    do {
      editor.redo();
    } while (--remaining > 0 && html == before);
  }

  Future<void> insertImage(Uint8List bytes) async {
    final selection = editor.composer.selection;
    final generation = _generation;
    final version = revision;
    final source = await media.addBytes(bytes, owner);
    _checkPending(generation, version);
    _restoreSelection(selection);
    _pasteDocument(MutableDocument(
        nodes: [ImageNode(id: Editor.createNodeId(), imageUrl: source)]));
  }

  Future<void> insertImageSource(String url) async {
    final selection = editor.composer.selection;
    final generation = _generation;
    final version = revision;
    final source = await media.importSource(url, owner);
    _checkPending(generation, version);
    _restoreSelection(selection);
    _pasteDocument(MutableDocument(
        nodes: [ImageNode(id: Editor.createNodeId(), imageUrl: source)]));
  }

  Future<void> paste() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null)
      throw StateError('Clipboard unavailable; choose an image or paste a URL');
    final selection = editor.composer.selection;
    final generation = _generation;
    final version = revision;
    final reader = await clipboard.read();
    await pasteReader(reader,
        selection: selection, generation: generation, version: version);
  }

  /// The same import boundary for system HTML and other explicit HTML inputs.
  Future<void> pasteHtml(String html) async {
    final selection = editor.composer.selection;
    final generation = _generation;
    final version = revision;
    final imported = authoring?.singleLine == true
        ? html
        : await media.importHtml(html, owner);
    _checkPending(generation, version);
    _restoreSelection(selection);
    _pasteHtml(imported);
  }

  Future<void> pasteEvent(ClipboardReadEvent event) async {
    final selection = editor.composer.selection;
    final generation = _generation;
    final version = revision;
    final reader = await event.getClipboardReader();
    await pasteReader(reader,
        selection: selection, generation: generation, version: version);
  }

  Future<bool> pasteReader(ClipboardReader reader,
      {DocumentSelection? selection, int? generation, int? version}) async {
    selection ??= editor.composer.selection;
    generation ??= _generation;
    version ??= revision;
    final nodes = <DocumentNode>[];
    final imageSources = <String>{};
    for (final item in reader.items) {
      // A rich item can expose both HTML and a bitmap of the same content.
      if (item.canProvide(Formats.htmlText)) {
        final value = await item.readValue(Formats.htmlText);
        if (value != null && value.isNotEmpty) {
          final imported = authoring?.singleLine == true
              ? value
              : await media.importHtml(value, owner);
          imageSources.addAll(HtmlDocumentCodec.decode(imported)
              .imageSlots
              .map((image) => image.source)
              .whereType<String>());
          nodes.addAll(_pasteContent(imported));
          continue;
        }
      }
      var imageRead = false;
      for (final format in authoring?.singleLine == true
          ? <SimpleFileFormat>[]
          : [
              Formats.png,
              Formats.jpeg,
              Formats.webp,
              Formats.gif,
              Formats.heic
            ]) {
        if (!item.canProvide(format)) continue;
        final completion = Completer<Uint8List>();
        final progress = item.getFile(format, (file) async {
          try {
            completion.complete(await file.readAll());
          } catch (error, stack) {
            completion.completeError(error, stack);
          }
        }, onError: (error) {
          if (!completion.isCompleted) completion.completeError(error);
        });
        if (progress == null)
          throw StateError('Clipboard image is unavailable');
        final source = await media.addBytes(await completion.future, owner);
        if (imageSources.add(source))
          nodes.add(ImageNode(id: Editor.createNodeId(), imageUrl: source));
        imageRead = true;
        break;
      }
      if (!imageRead && item.canProvide(Formats.plainText)) {
        final text = await item.readValue(Formats.plainText);
        if (text != null && text.isNotEmpty)
          nodes.addAll(_pasteContent(
              '<p>${htmlEscape.convert(text).replaceAll('\n', '<br>')}</p>'));
      }
    }
    if (nodes.isEmpty)
      throw StateError('Clipboard contains no supported text or image');
    _checkPending(generation, version);
    _restoreSelection(selection);
    _pasteDocument(MutableDocument(nodes: nodes));
    return true;
  }

  Iterable<DocumentNode> _pasteContent(String html) {
    html = normalizeHtmlContentStyles(html, profile);
    if (authoring?.singleLine == true) {
      final fragment = html_parser.parseFragment(html);
      for (final br in fragment.querySelectorAll('br')) {
        br.replaceWith(html_parser.parseFragment(' ').nodes.first);
      }
      final text = (fragment.text ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ');
      return [
        ParagraphNode(
            id: Editor.createNodeId(),
            text: tokenizeTemplateText(AttributedText(text), authoring!.codes))
      ];
    }
    final fragment = html_parser.parseFragment(html);
    final complex = fragment.querySelector(
            'table,ul,ol,pre,img,hr,blockquote,h1,h2,h3,h4,h5,h6,p[style],p[class],div[style]') !=
        null;
    if (complex && authoring == null)
      return [PreservedHtmlNode(id: Editor.createNodeId(), html: html)];
    final incoming = HtmlEditorDocument(html,
        tokenCodes: authoring?.codes ?? const {},
        blockCodes: authoring?.codes
                .where((c) => authoring!.entry(c)?.block == true)
                .toSet() ??
            const {});
    _codec.adoptFragment(incoming);
    return incoming.document;
  }

  void _pasteHtml(String html) =>
      _pasteDocument(MutableDocument(nodes: _pasteContent(html).toList()));

  void _pasteDocument(MutableDocument content) {
    final selection = editor.composer.selection;
    if (selection == null) return;
    final position = selection.isCollapsed
        ? selection.extent
        : CommonEditorOperations.getDocumentPositionAfterExpandedDeletion(
            document: editor.document, selection: selection);
    if (position == null) throw StateError('Cannot resolve paste position');
    editor.execute([
      if (!selection.isCollapsed)
        DeleteContentRequest(documentRange: selection),
      PasteStructuredContentEditorRequest(
          content: content, pastePosition: position),
    ]);
  }

  void _restoreSelection(DocumentSelection? selection) {
    final resolved = selection ??
        DocumentSelection.collapsed(
            position: DocumentPosition(
                nodeId: editor.document.last.id,
                nodePosition: editor.document.last.endPosition));
    editor.execute([
      ChangeSelectionRequest(resolved, SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
  }

  void _checkPending(int generation, int version) {
    if (_disposed || generation != _generation || revision != version) {
      throw StateError(
          'The document changed during paste; paste again at the desired position');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _detachTags();
    editor.document.removeListener(_changed);
    editor.dispose();
    focusNode.dispose();
    authoringChanges.dispose();
    if (_ownsMedia) media.dispose();
    super.dispose();
  }
}

/// Parent-owned media and active-field registry. Field Apply never uploads.
class HtmlSaveCoordinator extends ChangeNotifier {
  HtmlSaveCoordinator({HtmlMediaDraft? media})
      : media = media ?? HtmlMediaDraft();
  final HtmlMediaDraft media;
  final _active = <Object, void Function()>{};
  final _dirty = <Object, bool Function()>{};
  final _accepted = <Object, void Function()>{};
  final _applied = <RichHtmlEditorController>{};
  bool _disposed = false;
  bool get hasActiveDraft => _dirty.values.any((read) => read());
  bool get hasDraft => _applied.isNotEmpty || hasActiveDraft;
  bool _notificationScheduled = false;
  void draftChanged() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notificationScheduled) return;
      _notificationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        draftChanged();
      });
    } else {
      notifyListeners();
    }
  }

  final _originals = <String, String>{};
  void recordValue(RichHtmlEditorController controller) {
    _originals[controller.html] = controller.originalHtml;
    if (controller.isDirty) _applied.add(controller);
    draftChanged();
  }

  void markSaved({RichHtmlEditorController? controller}) {
    if (controller != null) {
      _applied.remove(controller);
    } else {
      _applied.clear();
      for (final accept in _accepted.values.toList()) {
        accept();
      }
    }
    draftChanged();
  }

  final _bindings = <HtmlFieldIdentity, _HtmlBinding>{};
  void registerValue(HtmlFieldIdentity identity,
      {required String? Function() read,
      required void Function(String) write,
      required HtmlMediaOwner owner,
      HtmlContentProfile profile = HtmlContentProfile.appContent}) {
    _bindings.putIfAbsent(
        identity, () => _HtmlBinding(read, write, owner, read() ?? '', profile));
  }

  Future<void> prepareWhere(bool Function(HtmlFieldIdentity) accepts) async {
    for (final entry in _bindings.entries.toList()) {
      if (!accepts(entry.key)) continue;
      final binding = entry.value;
      final html = binding.read();
      if (html == null) continue;
      binding.write(await prepare(html, binding.owner,
          originalHtml: _originals[html] ?? binding.original,
          profile: binding.profile));
    }
  }

  void clearBindings() => _bindings.clear();
  Future<void>? _saving;
  void registerActive(Object key, void Function() flush,
      {bool Function()? isDirty, void Function()? acceptSave}) {
    _active[key] = flush;
    if (isDirty != null) _dirty[key] = isDirty;
    if (acceptSave != null) _accepted[key] = acceptSave;
    draftChanged();
  }

  void unregisterActive(Object key) {
    _active.remove(key);
    _dirty.remove(key);
    _accepted.remove(key);
    draftChanged();
  }

  void flush() {
    for (final callback in _active.values.toList()) {
      callback();
    }
  }

  BuildContext? _saveContext;
  Future<String> prepare(String html, HtmlMediaOwner owner,
      {String? originalHtml,
      HtmlContentProfile profile = HtmlContentProfile.appContent}) async {
    final context = _saveContext;
    if (context != null &&
        !await confirmHtmlUploadRetry(context, media, html: html))
      throw StateError('Image retry cancelled');
    return media.prepareHtml(
        normalizeHtmlContentStyles(html, profile),
        originalHtml ?? _originals[html] ?? html, owner);
  }

  Future<void> save(Future<void> Function() writer, {BuildContext? context}) {
    if (_saving != null) return _saving!;
    final completion = Completer<void>();
    _saving = completion.future;
    _saveContext = context;
    () async {
      try {
        flush();
        await writer();
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _saving = null;
        _saveContext = null;
      }
    }();
    return completion.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _active.clear();
    _dirty.clear();
    _accepted.clear();
    _applied.clear();
    _originals.clear();
    _bindings.clear();
    media.dispose();
    super.dispose();
  }
}

class HtmlEditingScope extends InheritedWidget {
  HtmlEditingScope(
      {required this.coordinator, required Widget child, super.key})
      : super(
            child: _HtmlDraftBoundary(coordinator: coordinator, child: child));
  final HtmlSaveCoordinator coordinator;
  static HtmlSaveCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HtmlEditingScope>()
      ?.coordinator;
  @override
  bool updateShouldNotify(HtmlEditingScope oldWidget) =>
      coordinator != oldWidget.coordinator;
}

class _HtmlDraftBoundary extends StatefulWidget {
  const _HtmlDraftBoundary({required this.coordinator, required this.child});
  final HtmlSaveCoordinator coordinator;
  final Widget child;
  @override
  State<_HtmlDraftBoundary> createState() => _HtmlDraftBoundaryState();
}

class _HtmlDraftBoundaryState extends State<_HtmlDraftBoundary> {
  bool _asking = false;
  @override
  Widget build(BuildContext context) => NavigationDraftBoundary(
      isDirty: () => widget.coordinator.hasDraft,
      confirm: () => confirmHtmlDiscard(context, widget.coordinator),
      child: AnimatedBuilder(
          animation: widget.coordinator,
          builder: (context, _) => PopScope(
              canPop: !widget.coordinator.hasDraft,
              onPopInvokedWithResult: (didPop, _) async {
                if (didPop || _asking) return;
                _asking = true;
                final discard =
                    await confirmHtmlDiscard(context, widget.coordinator);
                _asking = false;
                if (discard == true && context.mounted) Navigator.pop(context);
              },
              child: widget.child)));
}

Future<bool> confirmHtmlDiscard(
    BuildContext context, HtmlSaveCoordinator coordinator) async {
  if (!coordinator.hasDraft) return true;
  return await showDialog<bool>(
          context: context,
          builder: (context) => AppAlertDialog(
                  onClose: () => Navigator.pop(context, false),
                  title: Text(HtmlStrings.discardDraft),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(CommonStrings.storno)),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(CommonStrings.ok)),
                  ])) ==
      true;
}

Future<bool> confirmHtmlUploadRetry(BuildContext context, HtmlMediaDraft media,
    {String? html}) async {
  if (html == null
      ? !media.hasUnknownUploads
      : !media.hasUnknownUploadsIn(html)) return true;
  final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
              onClose: () => Navigator.pop(context, false),
              content: Text(HtmlStrings.unknownUpload),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(CommonStrings.storno)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(HtmlStrings.retryUpload)),
              ]));
  if (retry == true) media.allowExplicitUnknownRetry();
  return retry == true;
}

class HtmlFieldIdentity {
  const HtmlFieldIdentity(this.entity, this.field);
  final Object entity;
  final String field;
  @override
  bool operator ==(Object other) =>
      other is HtmlFieldIdentity &&
      other.entity == entity &&
      other.field == field;
  @override
  int get hashCode => Object.hash(entity, field);
}

class _HtmlBinding {
  _HtmlBinding(this.read, this.write, this.owner, this.original, this.profile);
  final String? Function() read;
  final void Function(String) write;
  final HtmlMediaOwner owner;
  final String original;
  final HtmlContentProfile profile;
}

class _IgnoreSubjectNewline extends EditCommand {
  @override
  void execute(EditContext context, CommandExecutor executor) {}
}

class _AtomicActionTagReaction extends EditReaction {
  _AtomicActionTagReaction(this.native);
  final EditReaction native;
  @override
  void modifyContent(EditContext context, RequestDispatcher dispatcher,
      List<EditEvent> changes) {
    native.modifyContent(context, dispatcher, changes);
    native.react(context, dispatcher, changes);
  }
}
