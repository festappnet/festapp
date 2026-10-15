import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_media_service.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:image/image.dart' as image;
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';
import 'package:html/parser.dart' as parser;

class HtmlClipboardItem implements ClipboardDataReader {
  HtmlClipboardItem(this.html);
  final String html;
  @override
  bool canProvide(DataFormat format) =>
      format == Formats.htmlText ||
      format == Formats.png ||
      format == Formats.plainText;
  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async =>
      html as T;
  // Bitmap must not be read when this same clipboard item supplies HTML.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected clipboard operation ${invocation.memberName}');
}

Uint8List png(int red) {
  final pixel = image.Image(width: 1, height: 1)
    ..setPixelRgba(0, 0, red, 0, 0, 255);
  return Uint8List.fromList(image.encodePng(pixel));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'rich clipboard preserves text and all images and avoids duplicate bitmap representations',
      () async {
    var uploads = 0;
    final media = HtmlMediaDraft(upload: (_, scope) async {
      expect(scope, const HtmlMediaOwner.unit(3));
      uploads++;
      return 'https://assets.test/$uploads.png';
    });
    final controller = RichHtmlEditorController(
        initialHtml: '<p>Before</p>',
        owner: const HtmlMediaOwner.unit(3),
        media: media);
    addTearDown(controller.dispose);
    addTearDown(media.dispose);
    final a = 'data:image/png;base64,${base64Encode(png(10))}';
    final b = 'data:image/png;base64,${base64Encode(png(20))}';
    await controller.pasteReader(ClipboardReader([
      HtmlClipboardItem(
          '<p>First <strong>bold</strong></p><img src="$a" alt="First">'),
      HtmlClipboardItem('<p>Second</p><img src="$b" alt="Second">'),
    ]));
    expect(uploads, 0);
    final root = parser.parseFragment(controller.html);
    expect(root.querySelector('strong')!.text, 'bold');
    expect(root.querySelectorAll('img').map((e) => e.attributes['alt']),
        ['First', 'Second']);
    expect(root.text, contains('First bold'));
    expect(root.text, contains('Second'));
    final saved = await controller.prepareForSave();
    expect(uploads, 2);
    expect(saved, isNot(contains('html-draft.invalid')));
    expect(saved, isNot(contains('data:image')));
  });
  test('late external paste cannot overwrite a concurrently edited document',
      () async {
    final response = Completer<Uint8List>();
    final media = HtmlMediaDraft(
        owns: (_, __) async => false, fetch: (_, __) => response.future);
    final controller = RichHtmlEditorController(
        owner: const HtmlMediaOwner.occasion(12), media: media);
    addTearDown(controller.dispose);
    addTearDown(media.dispose);
    final paste =
        controller.pasteHtml('<img src="https://external.test/photo.png">');
    final expectation = expectLater(paste, throwsStateError);
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: controller.editor.document.first.id,
              nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Keep this',
          attributions: {})
    ]);
    response.complete(png(10));
    await expectation;
    expect(controller.html, '<p>Keep this</p>');
  });
  test(
      'bitmap insertion works in a selected list item and remains a draft until save',
      () async {
    var uploads = 0;
    final media = HtmlMediaDraft(upload: (_, __) async {
      uploads++;
      return 'https://assets.test/list.png';
    });
    final controller = RichHtmlEditorController(
        initialHtml: '<ul><li>Item</li></ul>',
        owner: const HtmlMediaOwner.occasion(12),
        media: media);
    addTearDown(controller.dispose);
    addTearDown(media.dispose);
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: controller.editor.document.first.id,
                  nodePosition: const TextNodePosition(offset: 2))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    await controller.insertImage(png(10));
    expect(controller.editor.document.whereType<ImageNode>(), hasLength(1));
    expect(uploads, 0);
    expect(controller.html, contains('<img'));
    controller.undo();
    expect(controller.html, '<ul><li>Item</li></ul>');
  });
}
