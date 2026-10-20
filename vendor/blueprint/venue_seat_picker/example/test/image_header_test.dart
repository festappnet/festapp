import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker_example/demo/image_header.dart';

Uint8List png(int width, int height) {
  final result = Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    ...List.filled(8, 0),
    8,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
  ByteData.sublistView(result)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return result;
}

Uint8List webp(String chunk, List<int> data) {
  final result = Uint8List.fromList([
    ...'RIFF'.codeUnits,
    0,
    0,
    0,
    0,
    ...'WEBP'.codeUnits,
    ...chunk.codeUnits,
    0,
    0,
    0,
    0,
    ...data,
    if (data.length.isOdd) 0,
  ]);
  ByteData.sublistView(result)
    ..setUint32(4, result.length - 8, Endian.little)
    ..setUint32(16, data.length, Endian.little);
  return result;
}

void main() {
  final jpeg = Uint8List.fromList([
    255, 216,
    255, 224, 0, 4, 0, 0, // Bounded application metadata.
    255, 192, 0, 11, 8, 0, 24, 0, 32, 1, 1, 0x11, 0,
  ]);
  final samples = <String, Uint8List>{
    'PNG': png(32, 24),
    'JPEG': jpeg,
    'WebP VP8': webp('VP8 ', [0, 0, 0, 0x9d, 1, 0x2a, 32, 0, 24, 0]),
    'WebP VP8L': webp('VP8L', [0x2f, 31, 0xc0, 5, 0]),
    'WebP VP8X': webp('VP8X', [0, 0, 0, 0, 31, 0, 0, 23, 0, 0]),
  };
  for (final entry in samples.entries) {
    test('${entry.key} encoded dimensions', () {
      expect(readRasterDimensions(entry.value), (width: 32, height: 24));
    });
    test('${entry.key} truncation never reads outside header', () {
      for (var length = 0; length < entry.value.length; length++) {
        expect(
          () => readRasterDimensions(
            Uint8List.sublistView(entry.value, 0, length),
          ),
          throwsFormatException,
          reason: 'prefix length $length',
        );
      }
    });
  }
  test('rejects invalid dimensions and malformed framing', () {
    final zeroJpeg = Uint8List.fromList(jpeg)..[16] = 0;
    final largeSegment = Uint8List.fromList(jpeg)..[4] = 255;
    final largeChunk = Uint8List.fromList(samples['WebP VP8']!)..[19] = 127;
    final largeRiff = Uint8List.fromList(samples['WebP VP8']!)..[7] = 127;
    final wrongIhdr = png(32, 24)..[11] = 255;
    final badLosslessVersion = webp('VP8L', [0x2f, 31, 0xc0, 5, 0x20]);
    for (final bytes in [
      png(0, 24),
      png(32, 0),
      png(0x80000000, 24),
      zeroJpeg,
      largeSegment,
      largeChunk,
      largeRiff,
      wrongIhdr,
      badLosslessVersion,
      webp('VP8 ', [0, 0, 0, 0x9d, 1, 0x2a, 0, 0, 24, 0]),
      Uint8List.fromList('GIF89a'.codeUnits),
    ]) {
      expect(() => readRasterDimensions(bytes), throwsFormatException);
    }
  });
  test(
    'large valid dimensions remain available to caller pixel-budget check',
    () {
      expect(readRasterDimensions(png(10000, 10000)), (
        width: 10000,
        height: 10000,
      ));
      expect(
        readRasterDimensions(
          webp('VP8X', [0, 0, 0, 0, 255, 255, 255, 255, 255, 255]),
        ),
        (width: 16777216, height: 16777216),
      );
    },
  );
}
