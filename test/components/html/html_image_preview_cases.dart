import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_image_preview.dart';
import 'package:image/image.dart' as image;

void main() {
  testWidgets(
      'large local preview is decoded at bounded size without changing upload bytes',
      (tester) async {
    final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 3000, height: 2000)));
    final copy = Uint8List.fromList(bytes);
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final preview = HtmlImagePreview(bytes);
    await tester.runAsync(() async {
      // Resolve before mounting so browser codec callbacks run outside FakeAsync.
      final provider = (preview.build(context) as Image).image;
      final result = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((info, _) => result.complete(info),
          onError: (error, stack) => result.completeError(error, stack));
      stream.addListener(listener);
      final info = await result.future.timeout(const Duration(seconds: 15));
      expect((info.image.width, info.image.height), (1200, 800));
      stream.removeListener(listener);
      info.dispose();
    });
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: preview));
    expect(find.byType(Image), findsOneWidget);
    expect(bytes, copy);
    await tester.pumpWidget(const SizedBox());
  });
}
