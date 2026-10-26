/// Public input contract of the shared image Worker. Output compression is
/// selected by purpose on the server and is independent of preview decoding.
abstract final class ImageUploadLimits {
  static const maxInputBytes = 20000000;
  static const maxPixels = 40000000;
  static const maxBase64Characters = ((maxInputBytes + 2) ~/ 3) * 4;
}
