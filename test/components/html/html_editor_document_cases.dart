import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_editor_document.dart';
import 'package:html/parser.dart' as parser;
import 'package:super_editor/super_editor.dart';

String fixture(String name) =>
    File('test/components/html/fixtures/$name.html').readAsStringSync();

void main() {
  test('CSS font emphasis becomes editable semantics on load and save', () async {
    final controller = RichHtmlEditorController(
      initialHtml: '<p style="font:italic bold 18px Arial;color:red">Text</p>',
      owner: const HtmlMediaOwner.none(),
    );
    addTearDown(controller.dispose);
    final node = controller.editor.document.first as TextNode;
    expect(node.text.getAllAttributionsAt(0), containsAll([boldAttribution, italicsAttribution]));
    expect(controller.hasUserChanges, isFalse);
    final saved = await controller.prepareForSave();
    expect(saved, controller.html);
    expect(parser.parseFragment(saved).querySelector('p strong em')!.text, 'Text');
    expect(saved, isNot(contains('Arial')));
  });
  test('standalone HTML links retain editor attribution, style and target', () {
    const url = 'https://docs.google.com/spreadsheets/d/carpool/edit';
    const html =
        '<p>Spolujízda:</p>'
        '<a href="$url">Tabulka spolujízdy</a>.';
    final codec = HtmlEditorDocument(html);
    final node = codec.document.whereType<TextNode>().singleWhere(
      (node) => node.text.toPlainText().contains('Tabulka spolujízdy'),
    );
    final attributes = node.text.getAllAttributionsAt(0);
    expect(attributes.whereType<LinkAttribution>().single.plainTextUri, url);
    final style = htmlInlineTextStyler(
      attributes,
      const TextStyle(color: Colors.black),
    );
    expect(style.decoration, TextDecoration.underline);
    expect(style.color, isNot(Colors.black));
    expect(codec.encode(), html);
    final editor = createDefaultDocumentEditor(document: codec.document);
    addTearDown(editor.dispose);
    editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: node.id,
          nodePosition: const TextNodePosition(offset: 8),
        ),
        textToInsert: 'nové ',
        attributions: attributes,
      ),
    ]);
    final saved = parser.parseFragment(codec.encode());
    expect(saved.querySelectorAll('a'), hasLength(1));
    expect(saved.querySelector('a')!.attributes['href'], url);
    expect(saved.querySelector('a')!.text, 'Tabulka nové spolujízdy');
  });

  test(
    'rich-only source formatting is projected without changing stored HTML',
    () {
      for (final source in [
        '{{fullOrder}}',
        '\n  {{fullOrder}}\n',
        '\n{{balanceReasoning}}\n{{fullOrder}}\n',
      ]) {
        final codec = HtmlEditorDocument(
          '$source<p>Signature</p>',
          tokenCodes: {'fullOrder', 'balanceReasoning'},
          blockCodes: {'fullOrder', 'balanceReasoning'},
        );
        expect(codec.encode(), '$source<p>Signature</p>');
        expect(codec.isUnchanged, isTrue);
        for (final node in codec.document.whereType<TextNode>()) {
          expect(node.text.toPlainText(), isNot(contains('\n')));
        }
      }
    },
  );

  test('projection retains meaningful text, NBSP, explicit breaks and preserved whitespace', () {
    for (final source in [
      '{{fullOrder}}&nbsp;\n',
      '{{fullOrder}} meaningful\n',
      '<p>{{fullOrder}}<br></p>',
      '<pre>{{fullOrder}}\n</pre>',
      '<div style="white-space:pre-wrap">{{fullOrder}}\n</div>',
    ]) {
      final codec = HtmlEditorDocument(
        '$source<p>Signature</p>',
        tokenCodes: {'fullOrder'},
        blockCodes: {'fullOrder'},
      );
      expect(
        codec.document.whereType<TextNode>().first.text.toPlainText(),
        contains('\n'),
      );
      expect(codec.encode(), '$source<p>Signature</p>');
    }
  });

  test('moving live blocks respects retained HTML table boundaries', () {
    const html =
        '<table><tr><td><p>Cell</p></td></tr></table>'
        '<div class="html-editor-block form-countdown"></div><p>After</p>';
    final controller = RichHtmlEditorController(
      initialHtml: html,
      owner: const HtmlMediaOwner.none(),
    );
    addTearDown(controller.dispose);
    final block = controller.editor.document
        .whereType<PreservedHtmlNode>()
        .single;
    expect(controller.canMoveBlock(block.id, -1), isFalse);
    controller.moveBlock(block.id, -1);
    expect(controller.html, html);
    expect(controller.canMoveBlock(block.id, 1), isTrue);
    controller.moveBlock(block.id, 1);
    expect(
      controller.html,
      contains('<p>After</p><div class="html-editor-block'),
    );
  });

  test('live block moves between text and survives editing, save and undo', () {
    const slot = '<div class="html-editor-block form-countdown"></div>';
    const html = '<p>Before</p>$slot<p>After</p>';
    final controller = RichHtmlEditorController(
      initialHtml: html,
      owner: const HtmlMediaOwner.none(),
    );
    addTearDown(controller.dispose);
    final block = controller.editor.document
        .whereType<PreservedHtmlNode>()
        .single;
    controller.editor.execute([MoveNodeRequest(nodeId: block.id, newIndex: 2)]);
    expect(controller.html, '<p>Before</p><p>After</p>$slot');
    controller.undo();
    expect(controller.html, html);
    final after = controller.editor.document.last as TextNode;
    controller.editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: after.id,
          nodePosition: TextNodePosition(offset: after.text.length),
        ),
        textToInsert: ' edited',
        attributions: {},
      ),
    ]);
    final saved = controller.html;
    expect(saved, '<p>Before</p>$slot<p>After edited</p>');
    final reloaded = HtmlEditorDocument(saved);
    expect(reloaded.document.whereType<PreservedHtmlNode>(), hasLength(1));
    expect(reloaded.encode(), saved);
  });

  for (final name in [
    'app_content',
    'song_content',
    'email_body',
    'full_document',
    'images',
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
      document: codec.document,
      isHistoryEnabled: true,
    );
    addTearDown(editor.dispose);
    final node = editor.document.whereType<TextNode>().singleWhere(
      (n) => n.text.toPlainText().contains('{{name}}'),
    );
    final offset = node.text.toPlainText().indexOf('{{name}}') + 2;
    editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: offset),
        ),
        textToInsert: 'recipient_',
        attributions: node.text.getAllAttributionsAt(offset),
      ),
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
          document: codec.document,
          isHistoryEnabled: true,
        );
        addTearDown(editor.dispose);
        final node = editor.document.whereType<TextNode>().first;
        editor.execute([
          InsertTextRequest(
            documentPosition: DocumentPosition(
              nodeId: node.id,
              nodePosition: const TextNodePosition(offset: 0),
            ),
            textToInsert: 'Nový ',
            attributions: {},
          ),
        ]);
        final source = parser.parseFragment(fixture(name));
        final result = parser.parseFragment(codec.encode());
        for (final selector in ['pre', 'ol', 'img', 'span']) {
          if (source.querySelector(selector) == null) continue;
          expect(
            result.querySelector(selector)!.outerHtml,
            source.querySelector(selector)!.outerHtml,
          );
        }
      }
    },
  );
  test('formatting, heading and alignment commands export semantic HTML', () {
    final codec = HtmlEditorDocument('<p>Český text</p>');
    final editor = createDefaultDocumentEditor(
      document: codec.document,
      isHistoryEnabled: true,
    );
    addTearDown(editor.dispose);
    final node = editor.document.first as TextNode;
    editor.execute([
      AddTextAttributionsRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
          end: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 5),
          ),
        ),
        attributions: {boldAttribution},
      ),
      ChangeParagraphBlockTypeRequest(
        nodeId: node.id,
        blockType: header2Attribution,
      ),
      ChangeParagraphAlignmentRequest(
        nodeId: node.id,
        alignment: TextAlign.center,
      ),
    ]);
    final root = parser.parseFragment(codec.encode());
    expect(
      root.querySelector('h2')!.attributes['style'],
      contains('text-align:center'),
    );
    expect(root.querySelector('strong')!.text, 'Český');
  });
  test('preformatted edits keep literal spaces and newlines', () {
    const html = '<pre>C    G\n  Žluťoučký\n\nposlední</pre>';
    final codec = HtmlEditorDocument(html);
    final editor = createDefaultDocumentEditor(
      document: codec.document,
      isHistoryEnabled: true,
    );
    addTearDown(editor.dispose);
    editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: editor.document.first.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
        textToInsert: 'Am  ',
        attributions: {},
      ),
    ]);
    expect(
      parser.parseFragment(codec.encode()).querySelector('pre')!.text,
      'Am  C    G\n  Žluťoučký\n\nposlední',
    );
    expect(codec.encode(), isNot(contains('<br>')));
  });
  test('list indentation and list type commands preserve siblings', () {
    final codec = HtmlEditorDocument(
      '<ul><li>One</li><li>Two</li><li>Three</li></ul>',
    );
    final editor = createDefaultDocumentEditor(
      document: codec.document,
      isHistoryEnabled: true,
    );
    addTearDown(editor.dispose);
    final node = editor.document.elementAt(1);
    editor.execute([IndentListItemRequest(nodeId: node.id)]);
    var parsed = parser.parseFragment(codec.encode());
    expect(parsed.querySelector('ul > li > ul > li')!.text, 'Two');
    expect(parsed.querySelectorAll('li').map((e) => e.text), contains('Three'));
    editor.undo();
    expect(codec.encode(), '<ul><li>One</li><li>Two</li><li>Three</li></ul>');
    editor.execute([
      ChangeListItemTypeRequest(nodeId: node.id, newType: ListItemType.ordered),
    ]);
    parsed = parser.parseFragment(codec.encode());
    expect(parsed.querySelector('ol > li')!.text, 'Two');
    expect(parsed.querySelectorAll('ul > li').map((e) => e.text), [
      'One',
      'Three',
    ]);
  });
  test(
    'complex HTML paste keeps the complete editable layout through undo',
    () async {
      final controller = RichHtmlEditorController(
        initialHtml: '<p>Before</p>',
        owner: const HtmlMediaOwner.none(),
        profile: HtmlContentProfile.emailContent,
      );
      addTearDown(controller.dispose);
      final id = controller.editor.document.first.id;
      controller.editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: id,
              nodePosition: const TextNodePosition(offset: 6),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      await controller.pasteHtml(fixture('email_body'));
      final parsed = parser.parseFragment(controller.html);
      expect(parsed.querySelectorAll('table'), hasLength(2));
      expect(parsed.querySelectorAll('th'), hasLength(2));
      expect(parsed.querySelector('a')!.attributes['href'], '{{resetLink}}');
      expect(
        controller.editor.document.whereType<PreservedHtmlNode>(),
        hasLength(1),
      );
      controller.undo();
      expect(controller.html, '<p>Before</p>');
      controller.redo();
      expect(controller.html, contains('{{name}}'));
    },
  );
  test('app policy strips imported styles and preserves email or song CSS', () {
    const html =
        '<p><span style="color:#aabbcc;font-family:Arial">www.example.com</span></p>';
    for (final profile in HtmlContentProfile.values) {
      final controller = RichHtmlEditorController(
        initialHtml: html,
        owner: const HtmlMediaOwner.none(),
        profile: profile,
      );
      addTearDown(controller.dispose);
      final baseline = controller.html;
      if (profile == HtmlContentProfile.appContent) {
        expect(baseline, isNot(contains('color:')));
        expect(baseline, isNot(contains('Arial')));
      } else {
        expect(baseline, html);
      }
      final node = controller.editor.document.first as TextNode;
      controller.editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: node.id,
            nodePosition: TextNodePosition(offset: node.text.length),
          ),
          textToInsert: ' ',
          attributions: {},
        ),
      ]);
      if (profile == HtmlContentProfile.appContent) {
        expect(controller.html, contains('href="https://www.example.com"'));
        expect(controller.html, isNot(contains('color:#aabbcc')));
      } else {
        expect(controller.html, contains('color:#aabbcc'));
        expect(controller.html, isNot(contains('<a')));
      }
      controller.undo();
      expect(controller.html, baseline);
    }
  });
  test('editing direct table cells retains th/td and all cell attributes', () {
    final codec = HtmlEditorDocument(
      '<table><tr><th scope="col">Heading</th><td colspan="2">{{name}}</td></tr></table>',
    );
    final editor = createDefaultDocumentEditor(
      document: codec.document,
      isHistoryEnabled: true,
    );
    addTearDown(editor.dispose);
    for (final node in editor.document.whereType<TextNode>().toList()) {
      editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
          textToInsert: 'New ',
          attributions: {},
        ),
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
        document: codec.document,
        isHistoryEnabled: true,
      );
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
    },
  );
}
