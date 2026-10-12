import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A bounded decoded preview, not a JPEG/PNG encoder. Uploads retain the source
/// bytes and receive their final processing from the image Worker.
class HtmlImagePreview extends StatelessWidget {
  const HtmlImagePreview(this.bytes, {this.fit, super.key});
  static const maxDecodeEdge = 1200;
  final Uint8List bytes;
  final BoxFit? fit;
  @override
  Widget build(BuildContext context) => Image(
    image: ResizeImage(MemoryImage(bytes),
      width: maxDecodeEdge, height: maxDecodeEdge, policy: ResizeImagePolicy.fit),
    fit: fit,
  );
}
