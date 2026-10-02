import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/ticket_layout/ticket_image_palette.dart';

void main() {
  Uint8List pixels(List<(int, List<int>)> groups) => Uint8List.fromList([
        for (final (count, rgba) in groups)
          for (var i = 0; i < count; i++) ...rgba,
      ]);
  test('preserves exact solid color and ignores transparent pixels', () {
    expect(
        ticketImagePalette(pixels([
          (100, [35, 67, 91, 255]),
          (500, [255, 0, 0, 0])
        ])),
        ['23435B']);
    expect(ticketImagePalette(Uint8List(0)), isEmpty);
  });
  test('selects a meaningful accent over repeated similar neutral shades', () {
    final data = pixels([
      (400, [220, 220, 220, 255]),
      (300, [225, 225, 225, 255]),
      (200, [230, 230, 230, 255]),
      (99, [180, 30, 50, 255]),
      (1, [0, 255, 0, 255])
    ]);
    final palette = ticketImagePalette(data);
    expect(palette, ['E3E3E3', 'B41E32']);
    expect(ticketImagePalette(data), palette);
    expect(ticketImagePalette(data, limit: 1), ['E3E3E3']);
  });
}
