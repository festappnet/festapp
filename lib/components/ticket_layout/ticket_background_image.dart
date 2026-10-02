import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Print artwork policy. The upload Worker receives these same bounds so it
/// stores the prepared bytes without a second, lower-quality transformation.
class TicketBackgroundImage {
  static const maxEdge = 3200;
  static const maxBytes = 8 * 1024 * 1024;
  static const jpegQuality = 92;

  static Future<Uint8List> prepare(Uint8List bytes) => compute(_prepare, bytes);

  static Uint8List _prepare(Uint8List bytes) {
    if (bytes.length < 16 || bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('Invalid or oversized ticket background');
    }
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 40000000) {
      throw const FormatException('Invalid or oversized ticket background');
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException('Invalid ticket background');
    }
    final jpeg = bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216;
    final png = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80;
    final orientation = decoded.exif.imageIfd.orientation;
    final edge = math.max(decoded.width, decoded.height);
    if ((jpeg || png) && edge <= maxEdge && bytes.length <= maxBytes &&
        (orientation == null || orientation == 1)) {
      return bytes;
    }
    var image = img.bakeOrientation(decoded);
    int targetEdge = math.min(maxEdge, math.max(image.width, image.height));
    while (true) {
      if (math.max(image.width, image.height) > targetEdge) {
        image = img.copyResize(image,
            width: image.width >= image.height ? targetEdge : null,
            height: image.height > image.width ? targetEdge : null,
            interpolation: img.Interpolation.average);
      }
      final output = Uint8List.fromList(jpeg
          ? img.encodeJpg(image, quality: jpegQuality)
          : img.encodePng(image));
      if (output.length <= maxBytes) return output;
      // Keep PNG transparency and lossless encoding. Reduce dimensions only if
      // the image would exceed the upload/PDF resource budget, never JPEG quality.
      targetEdge = (targetEdge * math.sqrt(maxBytes / output.length) * .95).floor();
      if (targetEdge < 1) throw const FormatException('Ticket background too large');
    }
  }
}
