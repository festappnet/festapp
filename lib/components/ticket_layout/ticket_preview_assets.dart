import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'ticket_theme_color.dart';

/// Generated from the PDF renderer's sources. Only immutable public assets
/// belong here; user resources always go through their authorized transport.
class TicketPreviewAssets {
  static const root = 'supabase/functions/_shared/ticket-assets/';
  final AssetBundle bundle;
  Future<Map<String, dynamic>>? _manifest;
  TicketPreviewAssets({AssetBundle? bundle}) : bundle = bundle ?? rootBundle;
  static final shared = TicketPreviewAssets();

  Future<Map<String, dynamic>> get manifest => _manifest ??= _read();
  Future<Map<String, dynamic>> _read() async {
    final raw =
        (await bundle.loadString('${root}preview-manifest.json')).trim();
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final payload = '${raw.substring(0, raw.lastIndexOf(',"sha256":'))}}';
    if (value['schema'] != 1 ||
        value['generator'] != 1 ||
        sha256.convert(utf8.encode(payload)).toString() != value['sha256']) {
      throw const FormatException('Preview manifest integrity');
    }
    return value;
  }

  Future<Uint8List> bytes(Map entry) async {
    final file = entry['file'] as String;
    if (!RegExp(r'^(?:gallery-fonts/|backgrounds/)?[a-zA-Z0-9.-]+$')
        .hasMatch(file)) {
      throw const FormatException('Preview asset path');
    }
    final data = await bundle.load('$root$file');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != entry['byteLength'] ||
        sha256.convert(bytes).toString() != entry['sha256']) {
      throw const FormatException('Preview asset integrity');
    }
    return bytes;
  }

  Future<Map?> font(String id) async {
    final entry = (await manifest)['fonts'][id] as Map?;
    if (entry == null) return null;
    return {...entry, 'id': id, 'font': base64Encode(await bytes(entry))};
  }

  Future<Uint8List?> artwork(String url) async {
    final entry = (await manifest)['artwork'][url] as Map?;
    return entry == null ? null : bytes(entry);
  }

  final _decoded = <String, ui.Image>{};
  final _decoding = <String, Future<void>>{};
  int _decodedBytes = 0;
  static const _imageBudget = 24 * 1024 * 1024;

  /// The cache owns one handle; each session owns and disposes its clone.
  /// Eviction therefore never invalidates a canvas already using the image.
  Future<ui.Image?> image(String url) async {
    if ((await manifest)['artwork'][url] == null && _palette(url) == null)
      return null;
    while (true) {
      final hit = _decoded.remove(url);
      if (hit != null) {
        _decoded[url] = hit;
        return hit.clone();
      }
      await _decoding.putIfAbsent(
          url,
          () => _decode(url).whenComplete(() {
                _decoding.remove(url);
              }));
    }
  }

  RegExpMatch? _palette(String url) => RegExp(
          r'^https://img\.festapp\.net/ticket-presets/v1/palette-([A-Fa-f0-9]{6})-([A-Fa-f0-9]{6})-([a-z_]{1,32})-v([12])\.png' +
              r'$')
      .firstMatch(url);
  Future<void> _decode(String url) async {
    final custom = _palette(url);
    final source =
        custom == null ? url : (await manifest)['backgrounds'][custom.group(3)];
    if (source == null) throw const FormatException('Palette artwork source');
    final data = await artwork(source);
    final codec = await ui.instantiateImageCodec(data!);
    late ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    if (custom != null) {
      try {
        final raw = (await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba))!;
        final pixels =
            raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
        final roles = (await manifest)['artworkRoles'][custom.group(3)] as Map?;
        if (custom.group(4) == '2' && roles == null)
          throw const FormatException('Artwork roles');
        final colors = <int, int>{};
        for (var i = 0; i < pixels.length; i += 4) {
          final rgb = (pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2];
          final target = colors.putIfAbsent(
              rgb,
              () => int.parse(
                  custom.group(4) == '2'
                      ? ticketArtworkColor(
                          rgb.toRadixString(16).padLeft(6, '0'),
                          custom.group(1)!,
                          custom.group(2)!,
                          roles!)
                      : ticketThemeColor(rgb.toRadixString(16).padLeft(6, '0'),
                          custom.group(1)!, custom.group(2)!),
                  radix: 16));
          pixels[i] = target >> 16;
          pixels[i + 1] = (target >> 8) & 255;
          pixels[i + 2] = target & 255;
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
        final descriptor = ui.ImageDescriptor.raw(buffer,
            width: image.width,
            height: image.height,
            pixelFormat: ui.PixelFormat.rgba8888);
        try {
          final recolored = await descriptor.instantiateCodec();
          try {
            final replacement = (await recolored.getNextFrame()).image;
            image.dispose();
            image = replacement;
          } finally {
            recolored.dispose();
          }
        } finally {
          descriptor.dispose();
          buffer.dispose();
        }
      } catch (_) {
        image.dispose();
        rethrow;
      }
    }
    final size = image.width * image.height * 4;
    if (size > _imageBudget) {
      image.dispose();
      throw const FormatException('Preview image limit');
    }
    while (_decoded.isNotEmpty &&
        (_decoded.length >= 16 || _decodedBytes + size > _imageBudget)) {
      final key = _decoded.keys.first;
      final previous = _decoded.remove(key)!;
      _decodedBytes -= previous.width * previous.height * 4;
      previous.dispose();
    }
    _decoded[url] = image;
    _decodedBytes += size;
  }
}
