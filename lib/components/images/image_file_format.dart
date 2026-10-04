import 'dart:typed_data';

/// Formats accepted by the image upload contract, recognized from bytes.
enum ImageFileFormat {
  png('image/png', 'png'),
  jpeg('image/jpeg', 'jpg'),
  gif('image/gif', 'gif'),
  webp('image/webp', 'webp');

  const ImageFileFormat(this.mime, this.extension);
  final String mime;
  final String extension;

  static ImageFileFormat detect(Uint8List bytes) {
    bool matches(int offset, List<int> signature) =>
        bytes.length >= offset + signature.length &&
        signature.indexed
            .every((entry) => bytes[offset + entry.$1] == entry.$2);
    if (matches(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
      return png;
    if (matches(0, [0xff, 0xd8, 0xff])) return jpeg;
    if (matches(0, [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
        matches(0, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) return gif;
    if (matches(0, [0x52, 0x49, 0x46, 0x46]) &&
        matches(8, [0x57, 0x45, 0x42, 0x50])) return webp;
    throw FormatException('Unsupported or unrecognized image bytes');
  }
}
