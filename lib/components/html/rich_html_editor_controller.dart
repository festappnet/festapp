import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';
import 'package:html/parser.dart' as html_parser;

import 'html_editor_document.dart';
import 'html_document_codec.dart';
import 'html_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'html_media_service.dart';

export 'html_media_service.dart' show HtmlMediaOwner, HtmlContentProfile;

/// One edit session. Domain callers exchange HTML, never document nodes.
class RichHtmlEditorController extends ChangeNotifier {
  RichHtmlEditorController(
      {String? initialHtml,
      required this.owner,
      this.profile = HtmlContentProfile.appContent,
      HtmlMediaDraft? media})
      : originalHtml = initialHtml ?? '',
        media = media ?? HtmlMediaDraft(),
        _ownsMedia = media == null {
    _load(initialHtml);
  }
  final HtmlMediaOwner owner;
  final HtmlContentProfile profile;
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
  bool get isDirty => !_codec.isUnchanged || _baselineHtml != originalHtml;
  bool get isEmpty => editor.document.every(
      (node) => node is TextNode && node.text.toPlainText().trim().isEmpty);
  CommonEditorOperations get operations => CommonEditorOperations(
      document: editor.document,
      editor: editor,
      composer: editor.composer,
      documentLayoutResolver: () => layoutKey.currentState as DocumentLayout);

  void _load(String? value) {
    _codec = HtmlEditorDocument(value);
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
    editor.document.removeListener(_changed);
    editor.dispose();
    _cachedHtml = null;
    _load(html);
    revision++;
    notifyListeners();
  }

  Future<String> prepareForSave({BuildContext? context}) async {
    if (context != null &&
        !await confirmHtmlUploadRetry(context, media, html: html))
      throw StateError('Image retry cancelled');
    return media.prepareHtml(html, originalHtml, owner);
  }

  void toggle(Attribution attribution) =>
      operations.toggleAttributionsOnSelection({attribution});
  void undo() => editor.undo();
  void redo() => editor.redo();

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
    final imported = await media.importHtml(html, owner);
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
          final imported = await media.importHtml(value, owner);
          imageSources.addAll(HtmlDocumentCodec.decode(imported)
              .imageSlots
              .map((image) => image.source)
              .whereType<String>());
          nodes.addAll(_pasteContent(imported));
          continue;
        }
      }
      var imageRead = false;
      for (final format in [
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
    final fragment = html_parser.parseFragment(html);
    final complex = fragment.querySelector(
            'table,ul,ol,pre,img,hr,blockquote,h1,h2,h3,h4,h5,h6,p[style],p[class],div[style]') !=
        null;
    if (complex)
      return [PreservedHtmlNode(id: Editor.createNodeId(), html: html)];
    final incoming = HtmlEditorDocument(html);
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
    editor.document.removeListener(_changed);
    editor.dispose();
    focusNode.dispose();
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
  bool get hasDraft =>
      _applied.isNotEmpty || _dirty.values.any((read) => read());
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
      required HtmlMediaOwner owner}) {
    _bindings.putIfAbsent(
        identity, () => _HtmlBinding(read, write, owner, read() ?? ''));
  }

  Future<void> prepareWhere(bool Function(HtmlFieldIdentity) accepts) async {
    for (final entry in _bindings.entries.toList()) {
      if (!accepts(entry.key)) continue;
      final binding = entry.value;
      final html = binding.read();
      if (html == null) continue;
      binding.write(await prepare(html, binding.owner,
          originalHtml: _originals[html] ?? binding.original));
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
      {String? originalHtml}) async {
    final context = _saveContext;
    if (context != null &&
        !await confirmHtmlUploadRetry(context, media, html: html))
      throw StateError('Image retry cancelled');
    return media.prepareHtml(
        html, originalHtml ?? _originals[html] ?? html, owner);
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
  Widget build(BuildContext context) => AnimatedBuilder(
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
          child: widget.child));
}

Future<bool> confirmHtmlDiscard(
    BuildContext context, HtmlSaveCoordinator coordinator) async {
  if (!coordinator.hasDraft) return true;
  return await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(HtmlStrings.discardDraft), actions: [
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
      builder: (context) =>
          AlertDialog(content: Text(HtmlStrings.unknownUpload), actions: [
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
  _HtmlBinding(this.read, this.write, this.owner, this.original);
  final String? Function() read;
  final void Function(String) write;
  final HtmlMediaOwner owner;
  final String original;
}
