import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../fonts/ticket_font_catalog.dart';
import '../ticket_layout/ticket_layout_service.dart';

/// Commit only decoded images whose verified manifests still belong to this
/// session. The caller guards controller/session liveness after awaiting I/O.
/// Uploads resolve only their new manifest and may add it atomically with bytes.
/// The resolver retains ownership of every ui.Image, including rejected ones.
bool commitBlueprintImages(VenueLayoutController controller,
    {required Map<String, dynamic> requestedResources,
    required Map<String, dynamic> resolvedResources,
    bool addAssets = false}) {
  final current = controller.resources;
  final assets = <String, dynamic>{...current['assets'] as Map? ?? {}};
  final images = <String, dynamic>{...current['images'] as Map? ?? {}};
  final resolvedAssets = resolvedResources['assets'] as Map? ?? const {};
  final resolvedImages = resolvedResources['images'] as Map? ?? const {};
  const equality = DeepCollectionEquality();
  for (final entry
      in (requestedResources['assets'] as Map? ?? const {}).entries) {
    final ref = entry.key as String;
    if (!equality.equals(entry.value, resolvedAssets[ref]) ||
        !resolvedImages.containsKey(ref)) continue;
    if (addAssets &&
        assets.containsKey(ref) &&
        !equality.equals(entry.value, assets[ref])) return false;
    if (!assets.containsKey(ref) && addAssets) {
      assets[ref] = entry.value;
    }
    if (equality.equals(entry.value, assets[ref])) {
      images[ref] = resolvedImages[ref];
    }
  }
  if (assets.isEmpty && images.isEmpty && current.isEmpty) return true;
  return controller.setResources({
    'protocol': 2,
    'fontFamilies': const <String, dynamic>{},
    'textLayouts': const <String, dynamic>{},
    ...current,
    'assets': assets,
    'images': images,
  });
}

/// Prepared text is an immutable contribution, not a replacement for resources
/// that may have arrived while shaping. Frozen save payloads remain untouched.
bool commitBlueprintTextResources(
    VenueLayoutController controller, Map<String, dynamic> preparedResources) {
  final current = controller.resources;
  return controller.setResources({
    ...current,
    'protocol': 2,
    for (final key in ['fontFamilies', 'textLayouts', 'numberSymbols'])
      key: {
        ...current[key] as Map? ?? {},
        ...preparedResources[key] as Map? ?? {},
      },
  });
}

/// Blueprint uses the shared immutable font registry and whole-text service.
/// The Ticket editor retains its independent character-outline API.
class BlueprintTextResources {
  BlueprintTextResources._(this.occasionId, this._service,
      {this.setupDraftId, required this.families});
  final int? occasionId;
  final String? setupDraftId;
  final TicketLayoutService _service;
  final List<Map<String, dynamic>> families;
  Future<Map<String, dynamic>> prepareTextBatch(Map<String, dynamic> batch) =>
      _service.layoutTextBatch(batch,
          occasionId: occasionId, setupDraftId: setupDraftId);
  Future<TicketFontResource> loadFace(String id) => setupDraftId == null
      ? _service.font(occasionId!, id)
      : _service.fontForSetupDraft(setupDraftId!, id);
  static Future<BlueprintTextResources> load(int occasionId,
          {TicketLayoutService? service}) async =>
      BlueprintTextResources._(occasionId, service ?? TicketLayoutService(),
          families: await TicketFontCatalog.loadFamilies());
  static Future<BlueprintTextResources> forSetupDraft(String draftId,
          {TicketLayoutService? service}) async =>
      BlueprintTextResources._(null, service ?? TicketLayoutService(),
          setupDraftId: draftId,
          families: await TicketFontCatalog.loadFamilies());
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
