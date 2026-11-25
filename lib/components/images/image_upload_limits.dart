/// Public input contract of the shared image Worker. Output compression is
/// selected by purpose on the server and is independent of preview decoding.
abstract final class ImageUploadLimits {
  static const maxInputBytes = 20000000;
  static const maxPixels = 40000000;
  static const maxBase64Characters = ((maxInputBytes + 2) ~/ 3) * 4;

  static void checkByteLength(int length) {
    if (length > maxInputBytes) {
      throw const ImageUploadLimitExceeded('Image exceeds 20 MB');
    }
  }

  static void checkDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw const FormatException('Invalid image dimensions');
    }
    if (width > maxPixels ~/ height) {
      throw const ImageUploadLimitExceeded('Image exceeds 40 MP');
    }
  }
}

class ImageUploadLimitExceeded extends FormatException {
  const ImageUploadLimitExceeded(super.message);
}
