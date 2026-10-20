import 'dart:math';
import 'model.dart';

/// One bounded, non-interactive path consumed identically by both renderers.
/// Density adapts to canvas size; an enormous plan never allocates a texture.
Map<String, dynamic>? floorSceneItem(VenueLayoutDocument document) {
  final c = document.canvas, style = c['floorStyle'] ?? 'plain';
  if (style == 'plain' || document.background != null) return null;
  final width = (c['width'] as num).toDouble(),
      height = (c['height'] as num).toDouble();
  var dx = style == 'wood'
      ? 128.0
      : style == 'carpet'
      ? 64.0
      : 96.0;
  var dy = style == 'wood' ? 48.0 : dx;
  while ((width / dx).ceil() * (height / dy).ceil() > 384) {
    dx *= 2;
    dy *= 2;
  }
  final path = <List<dynamic>>[];
  void line(double x1, double y1, double x2, double y2) {
    path.add(['M', quantize(x1), quantize(y1)]);
    path.add(['L', quantize(x2), quantize(y2)]);
  }

  if (style == 'wood') {
    for (var row = 0; row * dy < height; row++) {
      final y = row * dy;
      if (row > 0) line(.5, y, width - .5, y);
      for (var x = row.isEven ? dx : dx / 2; x < width - .5; x += dx) {
        line(x, max(.5, y), x, min(height - .5, y + dy));
      }
    }
  } else if (style == 'tile') {
    for (var x = dx; x < width - .5; x += dx) {
      line(x, .5, x, height - .5);
    }
    for (var y = dy; y < height - .5; y += dy) {
      line(.5, y, width - .5, y);
    }
  } else {
    for (var y = dy / 2; y < height - 3; y += dy) {
      for (var x = dx / 2; x < width - 3; x += dx) {
        final stitch = min(dx, dy) * .09;
        line(x - stitch, y - stitch, x + stitch, y + stitch);
        line(x - stitch, y + stitch, x + stitch, y - stitch);
      }
    }
  }
  if (path.isEmpty) return null;
  final rgb = int.parse('${c['fill']}'.substring(1, 7), radix: 16);
  final dark =
      ((rgb >> 16) * .2126 + ((rgb >> 8) & 255) * .7152 + (rgb & 255) * .0722) <
      100;
  return {
    'id': 'canvas:floor',
    'kind': 'floor',
    'renderBand': 0,
    'paintOrder': [-2, 0],
    'matrix': [1.0, 0.0, 0.0, 1.0, c['x'], c['y']],
    'path': path,
    'fill': '#00000000',
    'stroke': dark
        ? '#FFFFFF66'
        : style == 'wood'
        ? '#8B623F66'
        : style == 'tile'
        ? '#47556959'
        : '#47556966',
    // Floor grain is a screen-space hairline in both renderers.
    'strokeWidth': style == 'carpet' ? .85 : 1.0,
  };
}
