import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import '../fonts/ticket_font_ids.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/ticket_layout.dart';
import '../images/db_images.dart';
import 'ticket_text.dart';

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

class TicketProductType {
  final int id;
  final String title;
  final List<Map<String, dynamic>> forms;
  final bool offered, admission, hasVisibleProducts, referenced;
  final Map<String, dynamic>? example;
  const TicketProductType(this.id, this.title, this.offered, this.example,
      {this.admission = false,
      this.hasVisibleProducts = false,
      bool? referenced,
      this.forms = const []})
      : referenced = referenced ?? offered;
  factory TicketProductType.fromJson(Map j) => TicketProductType(
      j['id'],
      j['title'],
      j['offered'] == true,
      (j['example'] as Map?)?.cast<String, dynamic>(),
      admission: j['admission'] == true,
      hasVisibleProducts: j['hasVisibleProducts'] == true,
      referenced: j['referenced'] == true,
      forms: (j['forms'] as List? ?? [])
          .map((v) => (v as Map).cast<String, dynamic>())
          .toList());
  bool get eligible => referenced;
}

class TicketLayoutResources {
  final TicketTemplate template, preset;
  List<TicketProductType> _catalog = const [];
  Map<int, TicketProductType> _catalogIndex = const {};
  int _catalogRevision = 0;
  final _previewCache =
      Expando<Map<String, ({int revision, Map<String, String?> data})>>();
  List<TicketProductType> get catalog => _catalog;
  set catalog(List<TicketProductType> value) {
    _catalog = value;
    _catalogIndex = {for (final t in value) t.id: t};
    _catalogRevision++;
  }

  bool catalogError;
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
      List<TicketProductType> catalog = const [],
      this.catalogError = false,
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
      : fonts = Map.of(fonts) {
    this.catalog = catalog;
  }
  Map<String, String?> previewData(TicketTemplate template, String scenario) {
    final cache = _previewCache[template] ??= {};
    final cached = cache[scenario];
    if (cached?.revision == _catalogRevision) return cached!.data;
    final base = Map<String, String?>.of(scenarios[scenario]!);
    final selected = <int, Map<String, dynamic>>{};
    final admissions = catalog
        .where((t) => t.admission && t.example != null)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (admissions.isNotEmpty)
      selected[admissions.first.example!['id']] = admissions.first.example!;
    if (scenario != 'missing')
      for (final e
          in template.elements.where((e) => e.binding == 'productType')) {
        final example = _catalogIndex[e.productTypeId]?.example;
        if (example != null) selected[example['id']] = example;
      }
    final currencies = selected.values.map((e) => e['currency_code']).toSet();
    base['price'] = null;
    if (selected.isNotEmpty &&
        currencies.length == 1 &&
        selected.values.every((e) =>
            e['price'] is num &&
            (e['price'] as num).isFinite &&
            (e['price'] as num) >= 0 &&
            e['currency_code'] is String &&
            RegExp(r'^[A-Z]{3}$').hasMatch(e['currency_code'] as String) &&
            e['currency_symbol'] is String)) {
      final total = selected.values.fold<int>(
              0, (sum, e) => sum + ((e['price'] as num) * 100).round()) /
          100;
      final currency = currencies.single as String;
      base['price'] = 'Cena: ' +
          NumberFormat.currency(
                  locale: 'cs_CZ',
                  name: currency,
                  symbol: selected.values.first['currency_symbol'] as String,
                  decimalDigits: 0)
              .format(total);
    }
    final data = {
      for (final e in template.elements)
        e.id: e.binding == 'productType'
            ? scenario == 'missing'
                ? null
                : _productText(
                    e.label!,
                    _catalogIndex[e.productTypeId]?.example?['value']
                        as String?)
            : base[e.binding]
    };
    cache[scenario] = (revision: _catalogRevision, data: data);
    return data;
  }

  String? _productText(String label, String? value) => value == null
      ? null
      : label.trim().isEmpty
          ? value
          : '${label.trim()}: $value';
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
          profile: ImageUploadProfile.ticketBackground);

  Future<List<TicketProductType>> catalog(int occasionId) async {
    final j = await _request(
        {'occasionId': occasionId, 'mode': 'catalog', 'fontProtocol': 2});
    return (j['catalog'] as List)
        .map((v) => TicketProductType.fromJson(v))
        .toList();
  }

  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background,
      {bool borrowResourcesOnly = false, bool readOnly = false}) async {
    if (layout != null) validateTicketLayout(layout);
    final j = await _request({
      'fontProtocol': 2,
      'occasionId': occasionId,
      'type': type,
      'mode': 'resolve',
      if (readOnly) 'readOnly': true,
      if (!readOnly) 'borrowResourcesOnly': borrowResourcesOnly,
      if (!readOnly && layout != null) 'layout': layout,
      if (!readOnly) 'background': background
    });
    if (layout?['schemaVersion'] == 3 && j['fonts'] == null)
      throw const FormatException('Unsupported font protocol');
    final fonts = <String, TicketFontResource>{};
    final replies = j['fonts'] as Map?;
    if (replies != null)
      for (final entry in replies.entries) {
        final raw = (entry.value as Map).cast<String, dynamic>();
        final id = raw['id'];
        if (id is! String || id != entry.key)
          throw const FormatException('Font identity mismatch');
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
          catalogError: j['catalogError'] == true,
          catalog: (j['catalog'] as List? ?? [])
              .map((v) => TicketProductType.fromJson(v))
              .toList(),
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
