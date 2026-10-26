import 'dart:convert';
import 'dart:typed_data';

/// Optional image rendered behind a venue's seat grid.
sealed class VenueBackdrop {
  const VenueBackdrop();

  factory VenueBackdrop.parse(String source) {
    final trimmed = source.trim();
    if (trimmed.startsWith('<svg')) return SvgVenueBackdrop(trimmed);
    if (trimmed.startsWith('data:image/')) {
      final data = UriData.parse(trimmed);
      if (data.mimeType == 'image/svg+xml') {
        return SvgVenueBackdrop(utf8.decode(data.contentAsBytes()));
      }
      return MemoryVenueBackdrop(
        Uint8List.fromList(data.contentAsBytes()),
        mimeType: data.mimeType,
      );
    }
    return NetworkVenueBackdrop(trimmed);
  }

  String get source;
}

class SvgVenueBackdrop extends VenueBackdrop {
  const SvgVenueBackdrop(this.source);
  @override
  final String source;
}

class NetworkVenueBackdrop extends VenueBackdrop {
  const NetworkVenueBackdrop(this.source);
  @override
  final String source;
}

/// An image kept in memory, suitable for local file selection and previews.
class MemoryVenueBackdrop extends VenueBackdrop {
  MemoryVenueBackdrop(Uint8List bytes, {this.mimeType = 'image/png'})
    : _bytes = Uint8List.fromList(bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Must not be empty');
    }
    if (!mimeType.startsWith('image/')) {
      throw ArgumentError.value(mimeType, 'mimeType', 'Must be an image MIME');
    }
    if (mimeType == 'image/svg+xml') {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'Use SvgVenueBackdrop for SVG content',
      );
    }
  }

  final Uint8List _bytes;
  final String mimeType;
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String get source => UriData.fromBytes(_bytes, mimeType: mimeType).toString();
}
