import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_editor_document.dart';
import 'package:html/parser.dart' as parser;
import 'package:super_editor/super_editor.dart';

String fixture(String name) =>
    File('test/components/html/fixtures/$name.html').readAsStringSync();

void main() {
  for (final name in [
    'app_content',
    'song_content',
    'email_body',
    'full_document',
    'images'
  ]) {
    test('$name: Super Editor no-op retains exact HTML', () {
      final codec = HtmlEditorDocument(fixture(name));
      expect(codec.encode(), fixture(name));
      expect(codec.document, isNotEmpty);
    });
  }
  test('email body can edit a variable inside its layout and undo exactly', () {
    final codec = HtmlEditorDocument(fixture('email_body'));
    final editor = createDefaultDocumentEditor(
        document: codec.document, isHistoryEnabled: true);
    addTearDown(editor.dispose);
    final node = editor.document
        .whereType<TextNode>()
        .singleWhere((n) => n.text.toPlainText().contains('{{name}}'));
    final offset = node.text.toPlainText().indexOf('{{name}}') + 2;
    editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id, nodePosition: TextNodePosition(offset: offset)),
          textToInsert: 'recipient_',
          attributions: node.text.getAllAttributionsAt(offset))
    ]);
    final output = codec.encode();
    final parsed = parser.parseFragment(output);
    expect(parsed.querySelector('strong')!.text, '{{recipient_name}}');
    expect(parsed.querySelectorAll('table'), hasLength(2));
    expect(parsed.querySelectorAll('th'), hasLength(2));
    expect(parsed.querySelector('a')!.attributes['href'], '{{resetLink}}');
    expect(parsed.querySelector('td[rowspan]')!.attributes['rowspan'], '2');
    editor.undo();
    expect(codec.encode(), fixture('email_body'));
    editor.redo();
    expect(codec.encode(), output);
  });
  test(
      'neighbor edits retain song whitespace, list nesting and image attributes',
      () {
    for (final name in ['song_content', 'app_content', 'images']) {
      final codec = HtmlEditorDocument(fixture(name));
      final editor = createDefaultDocumentEditor(
          document: codec.document, isHistoryEnabled: true);
      addTearDown(editor.dispose);
      final node = editor.document.whereType<TextNode>().first;
      editor.execute([
        InsertTextRequest(
            documentPosition: DocumentPosition(
                nodeId: node.id,
                nodePosition: const TextNodePosition(offset: 0)),
            textToInsert: 'Nový ',
            attributions: {})
      ]);
      final source = parser.parseFragment(fixture(name));
      final result = parser.parseFragment(codec.encode());
      for (final selector in ['pre', 'ol', 'img', 'span']) {
        if (source.querySelector(selector) == null) continue;
        expect(result.querySelector(selector)!.outerHtml,
            source.querySelector(selector)!.outerHtml);
      }
    }
  });
  test('formatting, heading and alignment commands export semantic HTML', () {
    final codec = HtmlEditorDocument('<p>Český text</p>');
    final editor = createDefaultDocumentEditor(
        document: codec.document, isHistoryEnabled: true);
    addTearDown(editor.dispose);
    final node = editor.document.first as TextNode;
    editor.execute([
      AddTextAttributionsRequest(
          documentRange: DocumentRange(
              start: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 0)),
              end: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 5))),
          attributions: {boldAttribution}),
      ChangeParagraphBlockTypeRequest(
          nodeId: node.id, blockType: header2Attribution),
      ChangeParagraphAlignmentRequest(
          nodeId: node.id, alignment: TextAlign.center),
    ]);
    final root = parser.parseFragment(codec.encode());
    expect(root.querySelector('h2')!.attributes['style'],
        contains('text-align:center'));
    expect(root.querySelector('strong')!.text, 'Český');
  });
  test('preformatted edits keep literal spaces and newlines', () {
    const html = '<pre>C    G\n  Žluťoučký\n\nposlední</pre>';
    final codec = HtmlEditorDocument(html);
    final editor = createDefaultDocumentEditor(
        document: codec.document, isHistoryEnabled: true);
    addTearDown(editor.dispose);
    editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: editor.document.first.id,
              nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Am  ',
          attributions: {})
    ]);
    expect(parser.parseFragment(codec.encode()).querySelector('pre')!.text,
        'Am  C    G\n  Žluťoučký\n\nposlední');
    expect(codec.encode(), isNot(contains('<br>')));
  });
  test('list indentation and list type commands preserve siblings', () {
    final codec =
        HtmlEditorDocument('<ul><li>One</li><li>Two</li><li>Three</li></ul>');
    final editor = createDefaultDocumentEditor(
        document: codec.document, isHistoryEnabled: true);
    addTearDown(editor.dispose);
    final node = editor.document.elementAt(1);
    editor.execute([IndentListItemRequest(nodeId: node.id)]);
    var parsed = parser.parseFragment(codec.encode());
    expect(parsed.querySelector('ul > li > ul > li')!.text, 'Two');
    expect(parsed.querySelectorAll('li').map((e) => e.text), contains('Three'));
    editor.undo();
    expect(codec.encode(), '<ul><li>One</li><li>Two</li><li>Three</li></ul>');
    editor.execute([
      ChangeListItemTypeRequest(nodeId: node.id, newType: ListItemType.ordered)
    ]);
    parsed = parser.parseFragment(codec.encode());
    expect(parsed.querySelector('ol > li')!.text, 'Two');
    expect(parsed.querySelectorAll('ul > li').map((e) => e.text),
        ['One', 'Three']);
  });
  test('complex HTML paste keeps the complete editable layout through undo',
      () async {
    final controller = RichHtmlEditorController(
        initialHtml: '<p>Before</p>',
        owner: const HtmlMediaOwner.none(),
        profile: HtmlContentProfile.emailContent);
    addTearDown(controller.dispose);
    final id = controller.editor.document.first.id;
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: id, nodePosition: const TextNodePosition(offset: 6))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    await controller.pasteHtml(fixture('email_body'));
    final parsed = parser.parseFragment(controller.html);
    expect(parsed.querySelectorAll('table'), hasLength(2));
    expect(parsed.querySelectorAll('th'), hasLength(2));
    expect(parsed.querySelector('a')!.attributes['href'], '{{resetLink}}');
    expect(controller.editor.document.whereType<PreservedHtmlNode>(),
        hasLength(1));
    controller.undo();
    expect(controller.html, '<p>Before</p>');
    controller.redo();
    expect(controller.html, contains('{{name}}'));
  });
  test('app policy is dirty only and does not rewrite email or song CSS', () {
    const html = '<p><span style="color:#aabbcc">www.example.com</span></p>';
    for (final profile in HtmlContentProfile.values) {
      final controller = RichHtmlEditorController(
          initialHtml: html,
          owner: const HtmlMediaOwner.none(),
          profile: profile);
      addTearDown(controller.dispose);
      expect(controller.html, html);
      final node = controller.editor.document.first as TextNode;
      controller.editor.execute([
        InsertTextRequest(
            documentPosition: DocumentPosition(
                nodeId: node.id,
                nodePosition: TextNodePosition(offset: node.text.length)),
            textToInsert: ' ',
            attributions: {})
      ]);
      if (profile == HtmlContentProfile.appContent) {
        expect(controller.html, contains('href="https://www.example.com"'));
        expect(controller.html, isNot(contains('color:#aabbcc')));
      } else {
        expect(controller.html, contains('color:#aabbcc'));
        expect(controller.html, isNot(contains('<a')));
      }
      controller.undo();
      expect(controller.html, html);
    }
  });
  test('editing direct table cells retains th/td and all cell attributes', () {
    final codec = HtmlEditorDocument(
        '<table><tr><th scope="col">Heading</th><td colspan="2">{{name}}</td></tr></table>');
    final editor = createDefaultDocumentEditor(
        document: codec.document, isHistoryEnabled: true);
    addTearDown(editor.dispose);
    for (final node in editor.document.whereType<TextNode>().toList()) {
      editor.execute([
        InsertTextRequest(
            documentPosition: DocumentPosition(
                nodeId: node.id,
                nodePosition: const TextNodePosition(offset: 0)),
            textToInsert: 'New ',
            attributions: {})
      ]);
    }
    final root = parser.parseFragment(codec.encode());
    expect(root.querySelector('th')!.text, 'New Heading');
    expect(root.querySelector('th')!.attributes['scope'], 'col');
    expect(root.querySelector('td')!.text, 'New {{name}}');
    expect(root.querySelector('td')!.attributes['colspan'], '2');
  });
  test(
      'moving and deleting retained blocks exports their actual order and undo',
      () {
    const html = '<p>One</p><hr><p>Two</p>';
    final codec = HtmlEditorDocument(html);
    final editor = createDefaultDocumentEditor(
        document: codec.document, isHistoryEnabled: true);
    addTearDown(editor.dispose);
    final rule = editor.document.whereType<HorizontalRuleNode>().single;
    editor.execute([MoveNodeRequest(nodeId: rule.id, newIndex: 0)]);
    expect(codec.encode(), startsWith('<hr>'));
    editor.undo();
    expect(codec.encode(), html);
    editor.execute([DeleteNodeRequest(nodeId: rule.id)]);
    expect(codec.encode(), '<p>One</p><p>Two</p>');
    editor.undo();
    expect(codec.encode(), html);
  });
}
