import 'dart:convert';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import '../fonts/ticket_font_ids.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/ticket_layout.dart';
import '../images/db_images.dart';
import 'ticket_text.dart';
import 'ticket_background_image.dart';

class TicketFontResource {
  final String id, family, loaderName;
  final int weight;
  final TicketFontMetrics metrics;
  TicketFontResource(
      this.id, this.family, this.weight, this.metrics, this.loaderName);
}

class TicketLayoutArtwork {
  final String? label, background;
  final ui.Image? image;
  TicketLayoutArtwork(
      {required this.label, required this.background, required this.image});
}

class TicketLayoutResources {
  final TicketTemplate template, preset;
  final bool missingBackground;
  final Map<String, TicketLayoutArtwork> artworks;
  final String? initialArtworkKey;
  final Map<String, TicketTemplate> presets;
  final Map<String, Map<String, String?>> scenarios;
  final TicketFontMetrics metrics;
  final Map<String, TicketFontResource> fonts;
  TicketFontResource fontFor(TicketTemplate t, [TicketElement? e]) {
    final id = e?.fontId ?? t.fontId ?? legacyTicketFontIds[t.font]!;
    if (fonts.containsKey(id)) return fonts[id]!;
    if (fonts.isNotEmpty || t.fontId != null || e?.fontId != null)
      throw StateError('Font resource missing');
    return TicketFontResource(
        id, 'Futura PT', 400, metrics, 'TicketFont_${id.split(':').last}');
  }

  TicketFontMetrics metricsFor(TicketTemplate t, [TicketElement? e]) =>
      fontFor(t, e).metrics;
  ui.Image? background;
  final ui.Image? logo;
  final int qrSize;
  final List<int> qrModules;
  TicketLayoutResources(
      {required this.template,
      required this.preset,
      this.presets = const {},
      this.artworks = const {},
      this.initialArtworkKey,
      required this.scenarios,
      required this.metrics,
      Map<String, TicketFontResource> fonts = const {},
      this.background,
      this.missingBackground = false,
      this.logo,
      required this.qrSize,
      required this.qrModules})
      : fonts = Map.of(fonts);
  void dispose() {
    background?.dispose();
    logo?.dispose();
    for (final artwork in artworks.values) {
      artwork.image?.dispose();
    }
  }
}

class TicketLayoutService {
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? transport;
  final Future<String?> Function(String) _readPreference;
  final Future<void> Function(String, String) _writePreference;
  TicketLayoutService(
      {this.transport,
      Future<String?> Function(String)? readPreference,
      Future<void> Function(String, String)? writePreference})
      : _readPreference = readPreference ?? ((key) => StorageHelper.get(key)),
        _writePreference =
            writePreference ?? ((key, value) => StorageHelper.set(key, value));

  static final Map<String, Future<TicketFontResource>> _fonts = {};
  static Future<TicketFontResource> _register(Map j) async {
    final bytes = base64Decode(j['font']);
    final hash = sha256.convert(bytes).toString();
    final id = j['id'] as String;
    if (!id.endsWith(':$hash')) throw const FormatException('Font integrity');
    final name = 'TicketFont_$hash';
    final loader = FontLoader(name)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return TicketFontResource(id, j['family'], j['weight'],
        TicketFontMetrics.fromJson(j['metrics']), name);
  }

  static Future<TicketFontResource> _cache(
      String id, Future<Map> Function() load) {
    return _fonts.putIfAbsent(id, () async {
      try {
        final reply = await load();
        if (reply['id'] != id) {
          throw const FormatException('Font identity mismatch');
        }
        return await _register(reply);
      } catch (_) {
        _fonts.remove(id);
        rethrow;
      }
    });
  }

  Future<TicketFontResource> font(int occasionId, String id) => _cache(
      id,
      () => _request({
            'occasionId': occasionId,
            'mode': 'font',
            'fontProtocol': 2,
            'fontId': id
          }));
  Future<bool> openTemplatePickerOnce(int occasionId, String userId,
      {required bool configured}) async {
    final key = 'ticket-editor-opened:$userId:$occasionId';
    final opened = await _readPreference(key) == 'true';
    if (!opened) await _writePreference(key, 'true');
    return !configured && !opened;
  }

  Future<String?> uploadBackground(Uint8List bytes, int occasionId) =>
      DbImages.uploadImage(bytes, occasionId, null,
          maxEdge: TicketBackgroundImage.maxEdge,
          maxBytes: TicketBackgroundImage.maxBytes,
          quality: TicketBackgroundImage.jpegQuality);

  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background) async {
    if (layout != null) validateTicketLayout(layout);
    final j = await _request({
      'fontProtocol': 2,
      'occasionId': occasionId,
      'type': type,
      'mode': 'resolve',
      if (layout != null) 'layout': layout,
      'background': background
    });
    if (layout?['schemaVersion'] == 2 && j['fonts'] == null)
      throw const FormatException('Unsupported font protocol');
    final fonts = <String, TicketFontResource>{};
    final replies = j['fonts'] as Map?;
    if (replies != null)
      for (final entry in replies.entries) {
        // Closed enum reply belongs exclusively to the old v1 endpoint boundary.
        final raw = (entry.value as Map).cast<String, dynamic>();
        final id = raw['id'] ?? legacyTicketFontIds[entry.key];
        if (id == null) throw const FormatException('Unknown font reply');
        raw['id'] = id;
        raw['family'] ??= raw['label'];
        raw['weight'] ??= 400;
        fonts[id] = await _cache(id, () async => raw);
      }
    ui.Image? bg, logo;
    Future<ui.Image?> decode(String? b) async {
      if (b == null) return null;
      final codec = await ui.instantiateImageCodec(base64Decode(b));
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }

    try {
      bg = await decode(j['background']);
      logo = await decode(j['logo']);
      final presetValues = (j['presets'] as Map? ?? {}).cast<String, dynamic>();
      final overrides = (j['presetBackgrounds'] as Map? ?? {});
      final artworks = <String, TicketLayoutArtwork>{};
      if (overrides.isNotEmpty) {
        for (final key in presetValues.keys) {
          final blank = overrides.containsKey(key) && overrides[key] == null;
          artworks[key] = TicketLayoutArtwork(
              label: null,
              background: blank ? null : j['backgroundUrl'] as String?,
              image: blank ? null : bg?.clone());
        }
      }
      return TicketLayoutResources(
          artworks: artworks,
          template: TicketTemplate.fromJson(j['template']),
          preset: TicketTemplate.fromJson(j['preset']),
          presets: (j['presets'] as Map? ?? {})
              .map((k, v) => MapEntry(k as String, TicketTemplate.fromJson(v))),
          scenarios: (j['scenarios'] as Map).map((k, v) =>
              MapEntry(k as String, (v as Map).cast<String, String?>())),
          metrics: TicketFontMetrics.fromJson(j['metrics']),
          fonts: fonts,
          background: bg,
          missingBackground: j['missingBackground'] == true,
          logo: logo,
          qrSize: j['qrMatrix']['size'],
          qrModules: (j['qrMatrix']['data'] as List).cast<int>());
    } catch (_) {
      bg?.dispose();
      logo?.dispose();
      rethrow;
    }
  }

  Future<({Uint8List bytes, List<String> warnings})> preview(
      int occasionId,
      String type,
      Map<String, dynamic> layout,
      String scenario,
      String? background) async {
    final j = await _request({
      'occasionId': occasionId,
      'type': type,
      'mode': 'pdf',
      'fontProtocol': 2,
      'layout': layout,
      'scenario': scenario,
      'background': background
    });
    return (
      bytes: base64Decode(j['file']),
      warnings: (j['warnings'] as List).cast<String>()
    );
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    if (transport != null) return transport!(body);
    final response = await Supabase.instance.client.functions
        .invoke('preview-ticket-layout', body: body);
    if (response.status != 200 || response.data is! Map) {
      throw StateError('Ticket layout request failed');
    }
    return (response.data as Map).cast<String, dynamic>();
  }
}
