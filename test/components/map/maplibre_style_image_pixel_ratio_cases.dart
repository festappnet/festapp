import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';

void main() {
  testWidgets('widget images preserve the physical-to-logical pixel ratio', (
    tester,
  ) async {
    final style = _RecordingStyle();
    await tester.runAsync(
      () => style.addImageFromWidget(
        id: 'map-icon',
        widget: const SizedBox(
          width: 10,
          height: 8,
          child: ColoredBox(color: Color(0xFF123456)),
        ),
        logicalSize: const Size(10, 8),
        imageSize: const Size(30, 24),
      ),
    );

    expect(style.imageSize, const Size(30, 24));
    expect(style.pixelRatio, 3);
  });
}

class _RecordingStyle extends StyleController {
  Size? imageSize;
  double? pixelRatio;

  @override
  Future<void> addImageFromUiImage({
    required String id,
    required ui.Image image,
    double pixelRatio = 1,
    StyleImageOptions options = const StyleImageOptions(),
  }) async {
    imageSize = Size(image.width.toDouble(), image.height.toDouble());
    this.pixelRatio = pixelRatio;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
