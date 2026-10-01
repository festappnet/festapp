import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/ticket_layout.dart';
import '../images/db_images.dart';
import 'ticket_text.dart';

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
  TicketLayoutService({this.transport});
  Future<String?> uploadBackground(Uint8List bytes, int occasionId) =>
      DbImages.uploadImage(bytes, occasionId, null);

  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background) async {
    final j = await _request({
      'occasionId': occasionId,
      'type': type,
      'mode': 'resolve',
      if (layout != null) 'layout': layout,
      'background': background
    });
    final loader = FontLoader('TicketLayoutFont')
      ..addFont(Future.value(ByteData.sublistView(base64Decode(j['font']))));
    await loader.load();
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
