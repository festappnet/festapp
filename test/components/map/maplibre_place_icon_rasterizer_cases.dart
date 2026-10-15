import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/maplibre/maplibre_place_icon_rasterizer.dart';

void main() {
  test('SVG raster is complete at Retina resolution before registration',
      () async {
    final image = await MapLibrePlaceIconRasterizer.rasterize(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">'
      '<rect x="0" y="0" width="20" height="20" fill="#fff"/>'
      '</svg>',
      pixelRatio: 3,
    );
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = rgba!.buffer.asUint8List();
    final centerAlpha = pixels[(28 * image.width + 28) * 4 + 3];

    expect(image.width, 57);
    expect(image.height, 57);
    expect(centerAlpha, 255);
    image.dispose();
  });
}
