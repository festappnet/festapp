import 'dart:typed_data';

/// Reads encoded dimensions without allocating a raster decoder.
/// This validates framing, not image content; the codec must still validate it.
({int width, int height}) readRasterDimensions(Uint8List bytes) {
  Never malformed() => throw const FormatException('Invalid image header');
  void need(int offset, int length, [int? end]) {
    if (offset < 0 || length < 0 || offset + length > (end ?? bytes.length)) {
      malformed();
    }
  }

  int be16(int p) => (bytes[p] << 8) | bytes[p + 1];
  int le16(int p) => bytes[p] | (bytes[p + 1] << 8);
  int le24(int p) => le16(p) | (bytes[p + 2] << 16);
  int le32(int p) => le24(p) + bytes[p + 3] * 0x1000000;
  int be32(int p) =>
      bytes[p] * 0x1000000 +
      (bytes[p + 1] << 16) +
      (bytes[p + 2] << 8) +
      bytes[p + 3];
  bool matches(int p, List<int> signature) =>
      p + signature.length <= bytes.length &&
      Iterable<int>.generate(
        signature.length,
      ).every((i) => bytes[p + i] == signature[i]);
  ({int width, int height}) dimensions(int width, int height) {
    if (width <= 0 || height <= 0) malformed();
    return (width: width, height: height);
  }

  if (matches(0, [137, 80, 78, 71, 13, 10, 26, 10])) {
    need(0, 33); // Signature, complete IHDR data and CRC.
    if (be32(8) != 13 || !matches(12, [73, 72, 68, 82])) malformed();
    final width = be32(16), height = be32(20);
    if (width > 0x7fffffff || height > 0x7fffffff) malformed();
    return dimensions(width, height);
  }

  if (matches(0, [255, 216])) {
    var p = 2;
    for (var segments = 0; segments < 4096; segments++) {
      need(p, 2);
      if (bytes[p++] != 255) malformed();
      while (p < bytes.length && bytes[p] == 255) {
        p++;
      }
      need(p, 1);
      final marker = bytes[p++];
      // A size header must precede scan data/end of image.
      if (marker == 0 || marker == 0xd8 || marker == 0xd9 || marker == 0xda) {
        malformed();
      }
      if (marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      need(p, 2);
      final length = be16(p);
      if (length < 2) malformed();
      need(p, length);
      final sof =
          marker >= 0xc0 &&
          marker <= 0xcf &&
          marker != 0xc4 &&
          marker != 0xc8 &&
          marker != 0xcc;
      if (sof) {
        if (length < 8) malformed();
        final components = bytes[p + 7];
        if (components == 0 || length != 8 + 3 * components) malformed();
        return dimensions(be16(p + 5), be16(p + 3));
      }
      p += length;
    }
    malformed();
  }

  if (matches(0, [82, 73, 70, 70])) {
    need(0, 12);
    if (!matches(8, [87, 69, 66, 80])) malformed();
    final end = le32(4) + 8;
    if (end < 12 || end > bytes.length) malformed();
    var p = 12;
    for (var chunks = 0; chunks < 4096 && p < end; chunks++) {
      need(p, 8, end);
      final length = le32(p + 4), data = p + 8;
      need(data, length + (length & 1), end);
      if (matches(p, [86, 80, 56, 88])) {
        // VP8X
        if (length != 10) malformed();
        return dimensions(le24(data + 4) + 1, le24(data + 7) + 1);
      }
      if (matches(p, [86, 80, 56, 76])) {
        // VP8L
        if (length < 5 || bytes[data] != 0x2f || bytes[data + 4] >> 5 != 0) {
          malformed();
        }
        final width = 1 + bytes[data + 1] + ((bytes[data + 2] & 0x3f) << 8);
        final height =
            1 +
            (bytes[data + 2] >> 6) +
            (bytes[data + 3] << 2) +
            ((bytes[data + 4] & 15) << 10);
        return dimensions(width, height);
      }
      if (matches(p, [86, 80, 56, 32])) {
        // VP8 key frame
        if (length < 10 ||
            (bytes[data] & 1) != 0 ||
            !matches(data + 3, [0x9d, 1, 0x2a])) {
          malformed();
        }
        return dimensions(le16(data + 6) & 0x3fff, le16(data + 8) & 0x3fff);
      }
      p = data + length + (length & 1);
    }
    malformed();
  }
  throw const FormatException('Only PNG, JPEG and WebP images are supported');
}
