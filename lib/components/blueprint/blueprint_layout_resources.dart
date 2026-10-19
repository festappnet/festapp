import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../fonts/ticket_font_catalog.dart';
import '../ticket_layout/ticket_layout_service.dart';

/// Reuses Ticket Editor's catalog, authorized resolver and immutable font IDs.
class BlueprintLayoutFontProvider implements LayoutFontProvider {
  BlueprintLayoutFontProvider._(this.occasionId, this.catalog, this._service,
      {this.setupDraftId});
  final int? occasionId;
  final String? setupDraftId;
  @override
  final List<Map<String, dynamic>> catalog;
  final TicketLayoutService _service;
  String characters = '';
  static Future<BlueprintLayoutFontProvider> load(int occasionId,
          {TicketLayoutService? service}) async =>
      BlueprintLayoutFontProvider._(occasionId, await TicketFontCatalog.load(),
          service ?? TicketLayoutService());
  static Future<BlueprintLayoutFontProvider> forSetupDraft(String draftId,
          {TicketLayoutService? service}) async =>
      BlueprintLayoutFontProvider._(null, await TicketFontCatalog.load(),
          service ?? TicketLayoutService(),
          setupDraftId: draftId);
  @override
  Future<Map<String, dynamic>> resolve(String fontId) {
    // Repeated seat labels do not consume the endpoint's unique-glyph envelope.
    final needed = String.fromCharCodes(characters.runes.toSet());
    return setupDraftId == null
        ? _service.layoutFont(occasionId!, fontId, characters: needed)
        : _service.layoutFontForSetupDraft(setupDraftId!, fontId,
            characters: needed);
  }
}

/// Resolves the existing image service's verified public manifests. Decoded
/// images are transient renderer resources, never part of a persisted document.
class BlueprintLayoutAssetResolver {
  BlueprintLayoutAssetResolver({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  final _images = <String, ui.Image>{};
  final _pending = <String, Future<ui.Image>>{};
  bool _disposed = false;

  Future<Map<String, dynamic>> resolve(Map<String, dynamic> resources) async {
    if (_disposed) throw StateError('asset_resolver_disposed');
    final images = <String, dynamic>{};
    for (final entry in (resources['assets'] as Map? ?? const {}).entries) {
      final ref = entry.key as String;
      final asset = Map<String, dynamic>.from(entry.value as Map);
      final hash = asset['hash'];
      final width = asset['width'], height = asset['height'];
      final length = asset['byteLength'];
      if (hash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
          !const ['image/png', 'image/jpeg', 'image/webp']
              .contains(asset['mimeType']) ||
          width is! int ||
          height is! int ||
          width < 1 ||
          height < 1 ||
          width * height > 40000000 ||
          length is! int ||
          length < 1 ||
          length > 20000000 ||
          (ref.startsWith('image:') && ref != 'image:$hash')) {
        throw const FormatException('invalid_asset_manifest');
      }
      final image = _images[hash] ?? await (_pending[hash] ??= _decode(asset));
      if (_disposed) throw StateError('asset_resolver_disposed');
      if (image.width != width || image.height != height) {
        throw const FormatException('asset_dimensions_mismatch');
      }
      images[ref] = image;
    }
    return {...resources, 'images': images};
  }

  Future<ui.Image> _decode(Map<String, dynamic> asset) async {
    final hash = asset['hash'] as String;
    try {
      final uri = Uri.parse(asset['url'] as String);
      if (uri.scheme != 'https' && uri.scheme != 'http') {
        throw const FormatException('invalid_asset_url');
      }
      final response = await _client.send(http.Request('GET', uri));
      if (response.statusCode != 200) throw StateError('asset_load_failed');
      final length = asset['byteLength'] as int;
      if ((response.contentLength ?? 0) > length) {
        throw const FormatException('asset_size_limit');
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (buffer.length + chunk.length > length) {
          throw const FormatException('asset_size_limit');
        }
        buffer.add(chunk);
      }
      final bytes = buffer.takeBytes();
      if (bytes.length != length) {
        throw const FormatException('asset_length_mismatch');
      }
      if (sha256.convert(bytes).toString() != hash) {
        throw const FormatException('asset_hash_mismatch');
      }
      final codec = await ui.instantiateImageCodec(bytes);
      ui.Image image;
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (_disposed) {
        image.dispose();
        throw StateError('asset_resolver_disposed');
      }
      if (image.width != asset['width'] || image.height != asset['height']) {
        image.dispose();
        throw const FormatException('asset_dimensions_mismatch');
      }
      return _images[hash] = image;
    } finally {
      _pending.remove(hash);
    }
  }

  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}
