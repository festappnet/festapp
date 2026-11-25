import 'dart:typed_data';

import 'package:image/image.dart' show WebPDecoder;

import '../../services/import_file.dart';
import 'image_file_format.dart';
import 'image_upload_limits.dart';

/// Client-side checks before decoding a preview or sending an upload.
abstract final class ImageUploadInput {
  static Future<Uint8List> readFile(ImportFile file) async {
    ImageUploadLimits.checkByteLength(await file.length());
    final bytes = await file.readAsBytes();
    ImageUploadLimits.checkByteLength(bytes.length);
    return bytes;
  }

  /// Inspect encoded bytes without allocating the raster. SVG has no raster
  /// dimensions and is validated by the Worker as part of its Blueprint profile.
  static ({ImageFileFormat format, (int, int)? dimensions}) inspect(
    Uint8List bytes, {
    bool allowSvg = false,
  }) {
    ImageUploadLimits.checkByteLength(bytes.length);
    final format = ImageFileFormat.detect(bytes, allowSvg: allowSvg);
    if (format == ImageFileFormat.svg) {
      return (format: format, dimensions: null);
    }
    final dimensions = _rasterDimensions(bytes, format);
    ImageUploadLimits.checkDimensions(dimensions.$1, dimensions.$2);
    return (format: format, dimensions: dimensions);
  }
}

(int, int) _rasterDimensions(Uint8List bytes, ImageFileFormat format) {
  final data = ByteData.sublistView(bytes);
  final dimensions = switch (format) {
    ImageFileFormat.png =>
      // The first chunk is IHDR, with a 13-byte payload and a 4-byte CRC.
      bytes.length >= 33 &&
              data.getUint32(8) == 13 &&
              data.getUint32(12) == 0x49484452
          ? (data.getUint32(16), data.getUint32(20))
          : null,
    ImageFileFormat.jpeg => _jpegDimensions(data),
    ImageFileFormat.gif =>
      bytes.length >= 13
          ? (data.getUint16(6, Endian.little), data.getUint16(8, Endian.little))
          : null,
    ImageFileFormat.webp => _webpDimensions(bytes),
    ImageFileFormat.svg => null,
  };
  if (dimensions == null) {
    throw const FormatException('Invalid image dimensions');
  }
  return dimensions;
}

(int, int)? _webpDimensions(Uint8List bytes) {
  try {
    final info = WebPDecoder().startDecode(bytes);
    return info == null ? null : (info.width, info.height);
  } on RangeError {
    return null;
  }
}

(int, int)? _jpegDimensions(ByteData data) {
  final length = data.lengthInBytes;
  var offset = 2; // Skip the start-of-image marker.
  while (offset < length && data.getUint8(offset) == 0xff) {
    offset++;
    // A marker may have extra 0xff fill bytes before its marker code.
    while (offset < length && data.getUint8(offset) == 0xff) {
      offset++;
    }
    if (offset == length) return null;
    final marker = data.getUint8(offset++);
    if (marker == 0xda || marker == 0xd9) return null; // Scan or end of image.
    if (marker == 0x01) continue; // Standalone TEM marker.
    if (offset + 2 > length) return null;
    final segmentLength = data.getUint16(offset);
    if (segmentLength < 2 || offset + segmentLength > length) return null;

    // Start-of-frame markers carry height and width after sample precision.
    const frameMarkers = {
      0xc0,
      0xc1,
      0xc2,
      0xc3,
      0xc5,
      0xc6,
      0xc7,
      0xc9,
      0xca,
      0xcb,
      0xcd,
      0xce,
      0xcf,
    };
    if (frameMarkers.contains(marker)) {
      if (segmentLength < 8) return null;
      return (data.getUint16(offset + 5), data.getUint16(offset + 3));
    }
    offset += segmentLength;
  }
  return null;
}
