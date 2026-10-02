import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard_demo/image_component.dart';

void main() {
  testWidgets(
    'editor renders remote images through Festapp web byte loader and data images from memory',
    (tester) async {
      const remote =
          'https://a.img.festapp.net/images/643/information-image.png';
      final bytes = File('web/favicon.png').readAsBytesSync();
      final editor = createDefaultDocumentEditor(
        document: MutableDocument(
          nodes: [
            ImageNode(id: 'remote', imageUrl: remote),
            ImageNode(
              id: 'embedded',
              imageUrl: 'data:image/png;base64,${base64Encode(bytes)}',
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuperEditor(
              editor: editor,
              componentBuilders: [
                const EditorImageComponentBuilder(),
                ...defaultComponentBuilders,
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final images = tester.widgetList<Image>(find.byType(Image));
      final remoteProvider = images
          .map((image) => image.image)
          .whereType<CachedNetworkImageProvider>()
          .single;
      expect(remoteProvider.url, remote);
      expect(
        remoteProvider.imageRenderMethodForWeb,
        ImageRenderMethodForWeb.HttpGet,
      );
      final embeddedProvider = images
          .map((image) => image.image)
          .whereType<MemoryImage>()
          .single;
      expect(embeddedProvider.bytes, bytes);
      await tester.pumpWidget(const SizedBox.shrink());
      editor.dispose();
    },
  );
}
