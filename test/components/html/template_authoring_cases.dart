import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_editor_document.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/template_authoring.dart';
import 'package:super_editor/super_editor.dart';

class TestTemplateProvider extends TemplateAuthoringProvider {
  @override
  Set<String> get codes => {'name', 'fullOrder', 'resetLink'};
  @override
  String get helper => 'Type @';
  @override
  String get insertLabel => 'Insert';
  @override
  String get emptyLabel => 'No result';
  @override
  String get usedLabel => 'Used';
  @override
  String get sampleLabel => 'Sample';
  @override
  String get tokenLabel => 'Variable';
  @override
  TemplateAuthoringEntry? entry(String code) => codes.contains(code)
      ? TemplateAuthoringEntry(
          code: code, label: code, block: code == 'fullOrder')
      : null;
  @override
  List<TemplateAuthoringEntry> search(String query, Map<String, int> usage) =>
      codes.map((c) => entry(c)!).toList();
  @override
  bool canTrigger(String text, int offset,
          {bool inLink = false, bool inCode = false, bool composing = false}) =>
      !inLink &&
      !inCode &&
      !composing &&
      (offset == 0 || text[offset - 1] == ' ');
  @override
  bool canInsert(String text, int offset,
          {bool inLink = false, bool inCode = false, bool composing = false}) =>
      !inLink && !inCode && !composing;
}

void main() {
  test(
      'tokens preserve table href, mixed formatting, unknown content and no-op',
      () {
    const source =
        '<table><tr><td><p>Hello <b>{{na</b>me}} and {{unknown}}</p><p>{{fullOrder}}</p><a href="{{resetLink}}">Open</a></td></tr></table>';
    final codec =
        HtmlEditorDocument(source, tokenCodes: TestTemplateProvider().codes);
    expect(codec.encode(), source);
    expect(codec.isUnchanged, isTrue);
    final node = codec.document.whereType<TextNode>().first;
    expect(node.text.placeholders.values.single,
        const TemplateTokenPlaceholder('name'));
    final editor = createDefaultDocumentEditor(
        document: codec.document, isHistoryEnabled: true);
    addTearDown(editor.dispose);
    editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id, nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Hi ',
          attributions: {})
    ]);
    expect(codec.encode(), contains('{{name}}'));
    expect(codec.encode(), contains('href="{{resetLink}}"'));
    expect(codec.encode(), contains('{{unknown}}'));
    expect(codec.encode(), isNot(contains('\uFFFC')));
    editor.undo();
    expect(codec.encode(), source);
  });
  test(
      'block insertion splits surrounding text and clipboard/paste stay canonical',
      () async {
    final controller = RichHtmlEditorController(
        initialHtml: '<p>Before after</p>',
        owner: const HtmlMediaOwner.none(),
        authoring: TestTemplateProvider());
    addTearDown(controller.dispose);
    final node = controller.editor.document.first as TextNode;
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 7))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    expect(controller.insertTemplateToken('fullOrder'), isTrue);
    expect(controller.editor.document.whereType<TemplateTokenBlock>(),
        hasLength(1));
    expect(controller.html, contains('{{fullOrder}}'));
    expect(controller.html, contains('Before '));
    expect(controller.html, contains('after'));
    expect(controller.html, isNot(contains('html-editor')));
    controller.undo();
    expect(controller.html, '<p>Before after</p>');
    await controller.pasteHtml('<p>{{name}} and {{fullOrder}}</p>');
    expect(controller.html, contains('{{name}}'));
    expect(controller.html, contains('{{fullOrder}}'));
    expect(controller.html, isNot(contains('\uFFFC')));
  });
  test(
      'typed native action query inserts with one undo and rejects stale revisions',
      () {
    final controller = RichHtmlEditorController(
        initialHtml: '<p></p>',
        owner: const HtmlMediaOwner.none(),
        authoring: TestTemplateProvider());
    addTearDown(controller.dispose);
    final node = controller.editor.document.first as TextNode;
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 0))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    for (final char in '@name'.split('')) {
      controller.editor.execute([
        InsertTextRequest(
            documentPosition: controller.editor.composer.selection!.extent,
            textToInsert: char,
            attributions: {})
      ]);
    }
    final tag = controller.composingTag!;
    expect(
        controller.insertTemplateToken('name',
            expectedTag: tag, expectedRevision: controller.revision - 1),
        isFalse);
    expect(
        controller.insertTemplateToken('name',
            expectedTag: tag, expectedRevision: controller.revision),
        isTrue);
    expect(controller.plainText, '{{name}}');
    controller.undo();
    expect(controller.plainText, '@name');
  });
  test('query replacement is one undo and clipboard exports canonical identity',
      () {
    final controller = RichHtmlEditorController(
        initialHtml: '<p>Hello @na</p>',
        owner: const HtmlMediaOwner.none(),
        authoring: TestTemplateProvider());
    addTearDown(controller.dispose);
    final node = controller.editor.document.first as TextNode;
    expect(
        controller.insertTemplateToken('name',
            expectedTag: IndexedTag(Tag('@', 'na'), node.id, 6),
            expectedRevision: 0),
        isTrue);
    expect(controller.html, '<p>Hello {{name}}</p>');
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection(
              base: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 6)),
              extent: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 7))),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction)
    ]);
    expect(controller.selectedTemplateContent(),
        (text: '{{name}}', html: '<p>{{name}}</p>'));
    controller.undo();
    expect(controller.html, '<p>Hello @na</p>');
    controller.redo();
    expect(controller.html, '<p>Hello {{name}}</p>');
  });
}
