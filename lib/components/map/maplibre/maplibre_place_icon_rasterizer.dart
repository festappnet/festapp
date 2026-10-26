import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

/// Decodes an SVG into a ready raster before it enters MapLibre's offscreen
/// widget. Slow devices therefore cannot capture the SvgPicture placeholder.
abstract final class MapLibrePlaceIconRasterizer {
  static const ui.Size logicalSize = ui.Size(19, 19);

  static Future<ui.Image> rasterize(
    String svg, {
    required double pixelRatio,
  }) async {
    final pixelSize = ui.Size(
      logicalSize.width * pixelRatio,
      logicalSize.height * pixelRatio,
    );
    final pictureInfo = await vg.loadPicture(SvgStringLoader(svg), null);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      _paintSvg(canvas, pictureInfo, pixelSize);
      final picture = recorder.endRecording();
      try {
        return picture.toImage(
          pixelSize.width.round(),
          pixelSize.height.round(),
        );
      } finally {
        picture.dispose();
      }
    } finally {
      pictureInfo.picture.dispose();
    }
  }

  static void _paintSvg(
    ui.Canvas canvas,
    PictureInfo pictureInfo,
    ui.Size pixelSize,
  ) {
    final sourceSize = pictureInfo.size;
    if (sourceSize.isEmpty) return;
    final scale = (pixelSize.width / sourceSize.width)
        .clamp(0.0, pixelSize.height / sourceSize.height);
    final width = sourceSize.width * scale;
    final height = sourceSize.height * scale;
    final dx = (pixelSize.width - width) / 2;
    final dy = (pixelSize.height - height) / 2;
    canvas
      ..translate(dx, dy)
      ..scale(scale, scale)
      ..drawPicture(pictureInfo.picture);
  }
}
