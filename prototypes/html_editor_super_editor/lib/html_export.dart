import 'dart:convert';

import 'package:mime/mime.dart';
import 'package:super_editor/super_editor.dart';

import 'imported_images.dart';

// The clipboard package inserts BitmapImageNode, which the default HTML
// serializers silently skip. Keep the bytes in this local prototype's output.
String exportEditorHtml(Document document) => document.toHtml(
  nodeSerializers: [
    _localImageToHtml,
    _bitmapImageToHtml,
    ...defaultNodeHtmlSerializerChain,
  ],
  skipUnknownNodes: false,
);

String? _localImageToHtml(
  Document document,
  DocumentNode node,
  NodeSelection? selection,
  InlineHtmlSerializerChain inlineSerializers,
) {
  if (node is! ImageNode || node.imageUrl != sampleImageUrl) return null;
  final source = const HtmlEscape(HtmlEscapeMode.attribute)
      .convert(localImageSource(node.imageUrl));
  return '<img src="$source">';
}

String? _bitmapImageToHtml(
  Document document,
  DocumentNode node,
  NodeSelection? selection,
  InlineHtmlSerializerChain inlineSerializers,
) {
  if (node is! BitmapImageNode) return null;
  final mime = lookupMimeType('', headerBytes: node.imageData);
  if (mime == null || !mime.startsWith('image/')) {
    throw StateError('Nelze rozpoznat formát vloženého obrázku.');
  }
  final alt = const HtmlEscape(HtmlEscapeMode.attribute).convert(node.altText);
  return '<img src="data:$mime;base64,${base64Encode(node.imageData)}" alt="$alt">';
}
