import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

void main() {
  test('HTML paste preserves formatting, drops color, and promotes the first table row', () {
    final editor = createDefaultDocumentEditor(
      document: MutableDocument(
        nodes: [ParagraphNode(id: 'start', text: AttributedText())],
      ),
    );
    addTearDown(editor.dispose);
    editor.execute([
      ChangeSelectionRequest(
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'start',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    editor.pasteHtml(
      editor,
      '<h2>Nadpis testu</h2>'
      '<p><strong>Tučně</strong> a <em>kurzíva</em> '
      '<a href="https://example.com">Odkaz</a> '
      '<span style="color:#ff0000">Červeně</span></p>'
      '<ul><li>První bod</li><li>Druhý bod</li></ul>'
      '<table><tr><td>A1</td><td>B1</td></tr><tr><td>A2</td><td>B2</td></tr></table>',
    );
    final html = editor.document.toHtml();
    print('HTML result: $html');
    expect(html, contains('<h2>'));
    expect(html, contains('<strong>Tučně</strong>'));
    expect(html, contains('<i>kurzíva</i>'));
    expect(html, contains('href="https://example.com"'));
    expect(html, contains('<li>'));
    expect(html, contains('Červeně'));
    expect(html, isNot(contains('#ff0000')));
    expect(html, contains('<table>'));
    expect(html, contains('<thead>'));
    expect(html, contains('<th style="text-align:center">A1</th>'));
    expect(html, contains('<td>A2</td>'));
    for (final cell in ['A1', 'B1', 'A2', 'B2']) {
      expect(html, contains(cell));
    }
  });
}
