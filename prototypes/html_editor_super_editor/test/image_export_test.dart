import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:super_editor_clipboard_demo/html_export.dart';

void main() {
  test(
    'bitmap inserted at caret survives HTML export with its original bytes',
    () {
      final editor = createDefaultDocumentEditor(
        document: MutableDocument(
          nodes: [ParagraphNode(id: 'start', text: AttributedText())],
        ),
      );
      addTearDown(editor.dispose);
      editor.execute([
        const ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'start',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1sAAAAASUVORK5CYII=',
      );
      editor.execute([
        InsertNodeAtCaretRequest(
          node: BitmapImageNode(
            id: 'image',
            imageData: bytes,
            altText: 'Foto "A" & B',
          ),
        ),
      ]);
      final html = exportEditorHtml(editor.document);
      expect(
        html,
        contains('src="data:image/png;base64,${base64Encode(bytes)}"'),
      );
      expect(html, contains('alt="Foto &quot;A&quot; &amp; B"'));
    },
  );

  test(
    'HTML containing text and an image retains both during paste and export',
    () {
      final editor = createDefaultDocumentEditor(
        document: MutableDocument(
          nodes: [ParagraphNode(id: 'start', text: AttributedText())],
        ),
      );
      addTearDown(editor.dispose);
      editor.execute([
        const ChangeSelectionRequest(
          DocumentSelection.collapsed(
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
        '<p>Před obrázkem</p><img src="https://example.com/photo.png"><p>Za obrázkem</p>',
      );
      final html = exportEditorHtml(editor.document);
      expect(html, contains('Před obrázkem'));
      expect(html, contains('<img src="https://example.com/photo.png">'));
      expect(html, contains('Za obrázkem'));
    },
  );
}
