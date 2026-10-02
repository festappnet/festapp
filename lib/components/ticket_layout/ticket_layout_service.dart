import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/ticket_layout.dart';
import '../images/db_images.dart';
import 'ticket_text.dart';
import 'ticket_background_image.dart';

class TicketLayoutArtwork {
  final String? label, background;
  final ui.Image? image;
  TicketLayoutArtwork(
      {required this.label, required this.background, required this.image});
}

class TicketLayoutResources {
  final TicketTemplate template, preset;
  final Map<String, TicketLayoutArtwork> artworks;
  final String? initialArtworkKey;
  final Map<String, TicketTemplate> presets;
  final Map<String, Map<String, String?>> scenarios;
  final TicketFontMetrics metrics;
  final Map<String, TicketFontMetrics> fonts;
  final Map<String, String> fontLabels;
  TicketFontMetrics metricsFor(TicketTemplate template) => fonts[template.font] ?? metrics;
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
      this.fonts = const {}, this.fontLabels = const {},
      this.background,
      this.logo,
      required this.qrSize,
      required this.qrModules});
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
  TicketLayoutService({this.transport,
      Future<String?> Function(String)? readPreference,
      Future<void> Function(String, String)? writePreference})
      : _readPreference = readPreference ?? ((key) => StorageHelper.get(key)),
        _writePreference = writePreference ?? ((key, value) => StorageHelper.set(key, value));

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
    final j = await _request({
      'occasionId': occasionId,
      'type': type,
      'mode': 'resolve',
      if (layout != null) 'layout': layout,
      'background': background
    });
    final fonts = (j['fonts'] as Map? ?? {j['template']['font'] ?? 'futura': {'font': j['font'], 'metrics': j['metrics'], 'label': 'Futura PT'}});
    for (final entry in fonts.entries) {
      final loader = FontLoader('TicketLayoutFont-${entry.key}')
        ..addFont(Future.value(ByteData.sublistView(base64Decode(entry.value['font']))));
      await loader.load();
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
          fonts: fonts.map((key, value) => MapEntry(key as String, TicketFontMetrics.fromJson(value['metrics']))),
          fontLabels: fonts.map((key, value) => MapEntry(key as String, value['label'] as String)),
          background: bg,
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
