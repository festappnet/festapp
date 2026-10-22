import 'dart:async';
import '../images/image_control_client.dart';
import 'package:fstapp/app_config.dart';
import 'ticket_preview_assets.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:fstapp/data_services/rights_service.dart';

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
    this.id,
    this.family,
    this.weight,
    this.metrics,
    this.loaderName,
  );
}

class TicketLayoutArtwork {
  final String? label, background;
  final ui.Image? image;
  TicketLayoutArtwork({
    required this.label,
    required this.background,
    required this.image,
  });
}

class TicketProductType {
  final int id;
  final String title;
  final List<Map<String, dynamic>> forms;
  final bool offered, admission, hasVisibleProducts, referenced;
  final Map<String, dynamic>? example;
  const TicketProductType(
    this.id,
    this.title,
    this.offered,
    this.example, {
    this.admission = false,
    this.hasVisibleProducts = false,
    bool? referenced,
    this.forms = const [],
  }) : referenced = referenced ?? offered;
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
            .toList(),
      );
  bool get eligible => referenced;
}

class TicketLayoutResources {
  final TicketTemplate template, preset;
  final String? identity;
  bool get isValid => !_disposed && (identity == null || identity == TicketLayoutService.identityKey());
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
  final Future<void> Function(TicketLayoutResources, String)? loadStyle;
  final Future<void> Function(TicketLayoutResources, TicketTemplate)? loadFonts;
  final Map<String,Future<void>> _templateFonts = {};
  Future<void> prepareTemplate(TicketTemplate t) {
    if(!isValid) return Future.error(StateError('Ticket context changed'));
    final key=jsonEncode(t.toJson());
    return _templateFonts.putIfAbsent(key,() async {
      try {await loadFonts?.call(this,t);} catch (_) {_templateFonts.remove(key); rethrow;}
    });
  }
  final Map<String, Future<void>> _styles = {};
  bool _disposed = false;
  Future<void> prepareStyle(String key) => _styles.putIfAbsent(key, () async {
        try {
          await loadStyle?.call(this, key);
        } catch (_) {
          _styles.remove(key);
          rethrow;
        }
      });
  TicketLayoutResources clone() => TicketLayoutResources(
        template: template,
        identity: identity,
        preset: preset,
        presets: presets,
        loadStyle: loadStyle,
        loadFonts: loadFonts,
        scenarios: scenarios,
        metrics: metrics,
        fonts: fonts,
        catalog: catalog,
        catalogError: catalogError,
        missingBackground: missingBackground,
        background: background?.clone(),
        logo: logo?.clone(),
        qrSize: qrSize,
        qrModules: qrModules,
        artworks: {
          for (final e in artworks.entries)
            e.key: TicketLayoutArtwork(
              label: e.value.label,
              background: e.value.background,
              image: e.value.image?.clone(),
            ),
        },
      );
  final Map<String, Map<String, String?>> scenarios;
  final TicketFontMetrics metrics;
  final Map<String, TicketFontResource> fonts;
  TicketFontResource fontFor(TicketTemplate t, [TicketElement? e]) {
    final id = e?.fontId ?? t.fontId ?? legacyTicketFontIds[t.font]!;
    if (fonts.containsKey(id)) return fonts[id]!;
    if (fonts.isNotEmpty || t.fontId != null || e?.fontId != null)
      throw StateError('Font resource missing');
    return TicketFontResource(
      id,
      'Futura PT',
      400,
      metrics,
      'TicketFont_${id.split(':').last}',
    );
  }

  TicketFontMetrics metricsFor(TicketTemplate t, [TicketElement? e]) =>
      fontFor(t, e).metrics;
  ui.Image? background;
  ui.Image? logo;
  final int qrSize;
  final List<int> qrModules;
  TicketLayoutResources({
    required this.template,
    this.identity,
    List<TicketProductType> catalog = const [],
    this.catalogError = false,
    required this.preset,
    this.presets = const {},
    this.loadStyle,
    this.loadFonts,
    Map<String, TicketLayoutArtwork> artworks = const {},
    this.initialArtworkKey,
    required this.scenarios,
    required this.metrics,
    Map<String, TicketFontResource> fonts = const {},
    this.background,
    this.missingBackground = false,
    this.logo,
    required this.qrSize,
    required this.qrModules,
  }) : artworks = Map.of(artworks), fonts = Map.of(fonts) {
    this.catalog = catalog;
  }
  Map<String, String?> previewBindings(
    TicketTemplate template,
    String scenario,
  ) {
    final base = Map<String, String?>.of(scenarios[scenario]!);
    final selected = <int, Map<String, dynamic>>{};
    final admissions = catalog
        .where((t) => t.admission && t.example != null)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (admissions.isNotEmpty)
      selected[admissions.first.example!['id']] = admissions.first.example!;
    if (scenario != 'missing')
      for (final e in template.elements.where(
        (e) => e.binding == 'productType',
      )) {
        final example = _catalogIndex[e.productTypeId]?.example;
        if (example != null) selected[example['id']] = example;
      }
    final currencies = selected.values.map((e) => e['currency_code']).toSet();
    base['price'] = null;
    if (selected.isNotEmpty &&
        currencies.length == 1 &&
        selected.values.every(
          (e) =>
              e['price'] is num &&
              (e['price'] as num).isFinite &&
              (e['price'] as num) >= 0 &&
              e['currency_code'] is String &&
              RegExp(r'^[A-Z]{3}$').hasMatch(e['currency_code'] as String) &&
              e['currency_symbol'] is String,
        )) {
      final total = selected.values.fold<int>(
            0,
            (sum, e) => sum + ((e['price'] as num) * 100).round(),
          ) /
          100;
      final currency = currencies.single as String;
      base['price'] = 'Cena: ' +
          NumberFormat.currency(
            locale: 'cs_CZ',
            name: currency,
            symbol: selected.values.first['currency_symbol'] as String,
            decimalDigits: 0,
          ).format(total);
    }
    return base;
  }

  Map<String, String?> previewData(TicketTemplate template, String scenario) {
    final cache = _previewCache[template] ??= {};
    final cached = cache[scenario];
    if (cached?.revision == _catalogRevision) return cached!.data;
    final base = previewBindings(template, scenario);
    final data = {
      for (final e in template.elements)
        e.id: e.binding == 'text'
            ? e.text
            : e.binding == 'productType'
                ? scenario == 'missing'
                    ? null
                    : _productText(
                        e.label!,
                        _catalogIndex[e.productTypeId]?.example?['value']
                            as String?,
                      )
                : base[e.binding],
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
    if (_disposed) return;
    _disposed = true;
    background?.dispose();
    logo?.dispose();
    background = null;
    logo = null;
    for (final artwork in artworks.values) {
      artwork.image?.dispose();
    }
    artworks.clear();
    fonts.clear();
  }
}

/// Text-only context for an unsaved occasion; resource identity stays separate.
class TicketPreviewOccasion {
  final String title;
  final DateTime? startTime, endTime;
  final String? placeName;
  const TicketPreviewOccasion({
    required this.title,
    this.startTime,
    this.endTime,
    this.placeName,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'start_time': startTime?.toUtc().toIso8601String(),
        'end_time': endTime?.toUtc().toIso8601String(),
        'data': {'place_name': placeName},
      };
}

class TicketLayoutService {
  final String? setupDraftId;
  final int? setupUnitId, setupRevision;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? transport;
  final Future<String?> Function(String) _readPreference;
  final Future<void> Function(String, String) _writePreference;
  TicketLayoutService({
    this.transport,
    this.setupDraftId,
    this.setupUnitId,
    this.setupRevision,
    Future<String?> Function(String)? readPreference,
    Future<void> Function(String, String)? writePreference,
  })  : _readPreference = readPreference ?? ((key) => StorageHelper.get(key)),
        _writePreference =
            writePreference ?? ((key, value) => StorageHelper.set(key, value));

  TicketLayoutService forSetupDraft(String draftId, int unitId, {int? revision}) =>
      TicketLayoutService(
        setupDraftId: draftId,
        setupUnitId: unitId,
        setupRevision: revision,
        transport: transport,
        readPreference: _readPreference,
        writePreference: _writePreference,
      );

  TicketLayoutService withPreviewOccasion(TicketPreviewOccasion occasion) =>
      TicketLayoutService(
        setupDraftId: setupDraftId,
        setupUnitId: setupUnitId,
        setupRevision: setupRevision,
        readPreference: _readPreference,
        writePreference: _writePreference,
        transport: (body) => _request({
          ...body,
          if (body['readOnly'] != true &&
              (body['mode'] == 'resolve' || body['mode'] == 'pdf'))
            'previewOccasion': occasion.toJson(),
        }),
      );

  static final Map<String, Future<TicketFontResource>> _fonts = {};
  // Public build assets can share registrations across identities. Private
  // resources are never reused without another authorized font request.
  static int _scopeGeneration = 0;
  static String? _scopeSnapshot;
  static bool _watchingRights = false;
  static Object? _observedAuth;
  static StreamSubscription<AuthState>? _authScope;
  static String _snapshot() {
    String? userId;
    try {userId=Supabase.instance.client.auth.currentUser?.id;}
    catch (_) {userId=RightsService.currentUser()?.id;}
    return jsonEncode([AppConfig.organization,userId,RightsService.currentOccasionId(),
      RightsService.currentUnit()?.id,RightsService.occasionLinkModelNotifier.value?.capabilities]);
  }
  static void _observeScope() {
    final next=_snapshot();
    if(next != _scopeSnapshot) {_scopeSnapshot=next;_scopeGeneration++;}
  }
  static String identityKey() {
    if(!_watchingRights) {
      _watchingRights=true;
      RightsService.occasionLinkModelNotifier.addListener(_observeScope);
    }
    try {
      final auth=Supabase.instance.client.auth;
      if(!identical(auth,_observedAuth)) {
        _authScope?.cancel();_observedAuth=auth;_scopeGeneration++;
        _authScope=auth.onAuthStateChange.listen((state) {
          if(state.event==AuthChangeEvent.signedOut) _scopeGeneration++;
          _observeScope();
        });
      }
    }catch (_) {} // Unit fixtures need no Supabase initialization.
    _observeScope();
    return '$_scopeGeneration:$_scopeSnapshot';
  }

  static Future<TicketFontResource> _register(Map j) async {
    final bytes = base64Decode(j['font']);
    final hash = sha256.convert(bytes).toString();
    final id = j['id'] as String;
    if (!id.endsWith(':$hash')) throw const FormatException('Font integrity');
    final name = 'TicketFont_$hash';
    final loader = FontLoader(name)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return TicketFontResource(
      id,
      j['family'],
      j['weight'],
      TicketFontMetrics.fromJson(j['metrics']),
      name,
    );
  }

  static Future<TicketFontResource> _cache(
    String id,
    Future<Map> Function() load,
  ) {
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

  Future<TicketFontResource> font(int occasionId, String id) async {
    final builtins = (await TicketPreviewAssets.shared.manifest)['fonts'] as Map;
    if(builtins.containsKey(id) && _fonts.containsKey(id)) return _fonts[id]!;
    final local = await TicketPreviewAssets.shared.font(id);
    if (local != null) return _cache(id, () async => local);
    final identity = identityKey();
    final reply = await _request({
      'occasionId': occasionId,
      'mode': 'font',
      'fontProtocol': 2,
      'fontId': id,
    });
    if (identity != identityKey()) throw StateError('Ticket context changed');
    return _register(reply);
  }

  Future<TicketFontResource> fontForSetupDraft(String draftId, String id) =>
      forSetupDraft(draftId, setupUnitId ?? 0).font(0, id);

  Future<Map<String, dynamic>> layoutTextBatch(
    Map<String, dynamic> batch, {
    int? occasionId,
    String? setupDraftId,
  }) =>
      _request({
        if (occasionId != null) 'occasionId': occasionId,
        if (setupDraftId != null) 'setupDraftId': setupDraftId,
        'mode': 'layout-text',
        'resourceProtocol': 2,
        'batch': batch,
      });

  Future<bool> openTemplatePickerOnce(
    int occasionId,
    String userId, {
    required bool configured,
  }) async {
    final key = 'ticket-editor-opened:$userId:${setupDraftId ?? occasionId}';
    final opened = await _readPreference(key) == 'true';
    if (!opened) await _writePreference(key, 'true');
    return !configured && !opened;
  }

  Future<String?> uploadBackground(Uint8List bytes, int occasionId) =>
      DbImages.uploadImage(
        bytes,
        setupDraftId == null ? occasionId : null,
        setupUnitId,
        profile: ImageUploadProfile.ticketBackground,
      );

  Future<List<TicketProductType>> catalog(int occasionId) async {
    final j = await _request({
      'occasionId': occasionId,
      'mode': 'catalog',
      'fontProtocol': 2,
    });
    return (j['catalog'] as List)
        .map((v) => TicketProductType.fromJson(v))
        .toList();
  }

  Future<TicketLayoutResources> resolve(
    int occasionId,
    String type,
    Map<String, dynamic>? layout,
    String? background, {
    bool borrowResourcesOnly = false,
    bool readOnly = false,
  }) async {
    if (layout != null) validateTicketLayout(layout);
    final identity = identityKey();
    final j = await _context({
      'fontProtocol': 2,
      'occasionId': occasionId,
      'type': type,
      'mode': 'resolve',
      'resourceProtocol': 3,
      if (readOnly) 'readOnly': true,
      if (!readOnly) 'borrowResourcesOnly': borrowResourcesOnly,
      if (!readOnly && layout != null) 'layout': layout,
      if (!readOnly) 'background': background,
    });
    if (j['resourceProtocol'] != 3)
      throw const FormatException('Unsupported ticket resource protocol');
    if (identity != identityKey()) throw StateError('Ticket context changed');
    final manifest = await TicketPreviewAssets.shared.manifest;
    final fonts = <String, TicketFontResource>{};
    for (final id in (j['fontIds'] as List).cast<String>()) {
      fonts[id] = await font(occasionId, id);
    }
    ui.Image? bg, logo;
    try {
      bg = await _image(j['backgroundUrl'], allowMissing: !readOnly);
      logo = await _image(j['logoUrl']);
      if (identity != identityKey()) throw StateError('Ticket context changed');
      final scenarios = (j['scenarios'] as Map).map(
        (k, v) => MapEntry(k as String, (v as Map).cast<String, String?>()),
      );
      final code = QrCode.fromData(
        data: scenarios['normal']!['qr']!,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qr = QrImage(code);
      final template = TicketTemplate.fromJson(j['template']);
      final presets = (manifest['presets'] as Map).map(
        (k,v) {
          final raw=copyTicketJson((v as Map).cast<String,dynamic>());
          if(['classic','compact','event'].contains(k) && j['galleryColor'] != null) {
            for(final e in (raw['elements'] as List).cast<Map>()) {
              if(e['binding'] != 'qr') e['style']['color']=j['galleryColor'];
            }
          }
          return MapEntry(k as String,TicketTemplate.fromJson(raw));
        },
      );
      final urls = manifest['backgrounds'] as Map;
      Future<void> loadFonts(TicketLayoutResources r, TicketTemplate t) async {
          for (final id in {
            t.fontId ?? legacyTicketFontIds[t.font]!,
            ...t.elements
                .where((e) => e.visible && !['qr', 'logo'].contains(e.binding))
                .map(
                  (e) => e.fontId ?? t.fontId ?? legacyTicketFontIds[t.font]!,
                ),
          }) {
            if (!r.fonts.containsKey(id)) {
              final loaded=await font(occasionId,id);
              if(!r.isValid) throw StateError('Ticket context changed');
              r.fonts[id]=loaded;
            }
          }
      }
      return TicketLayoutResources(
        template: template,
        identity: identity,
        preset: TicketTemplate.fromJson(j['preset']),
        presets: readOnly ? const {} : presets,
        artworks: readOnly
            ? {}
            : {
                for (final key in presets.keys)
                  key: TicketLayoutArtwork(
                    label: null,
                    background: urls.containsKey(key)
                        ? urls[key]
                        : key.startsWith('portrait')
                            ? null
                            : j['backgroundUrl'],
                    image: null,
                  ),
              },
        loadFonts: loadFonts,
        loadStyle: (r, key) async {
          final t = r.presets[key]!;
          await r.prepareTemplate(t);
          final current = r.artworks[key]!;
          if (current.image != null || current.background == null) return;
          final image = current.background == j['backgroundUrl']
              ? r.background?.clone()
              : await _image(current.background);
          if (r._disposed || identity != identityKey()) {
            image?.dispose();
            throw StateError('Ticket context changed');
          }
          r.artworks[key] = TicketLayoutArtwork(
            label: current.label,
            background: current.background,
            image: image,
          );
        },
        scenarios: scenarios,
        fonts: fonts,
        metrics: fonts[template.fontId ?? legacyTicketFontIds[template.font]]!
            .metrics,
        missingBackground: j['backgroundUrl'] != null && bg == null,
        background: bg,
        logo: logo,
        catalogError: j['catalogError'] == true,
        catalog: (j['catalog'] as List? ?? [])
            .map((v) => TicketProductType.fromJson(v))
            .toList(),
        qrSize: qr.moduleCount,
        qrModules: [
          for (var row = 0; row < qr.moduleCount; row++)
            for (var col = 0; col < qr.moduleCount; col++)
              qr.isDark(row, col) ? 1 : 0,
        ],
      );
    } catch (_) {
      bg?.dispose();
      logo?.dispose();
      rethrow;
    }
  }

  Future<ui.Image?> _image(String? url, {bool allowMissing = false}) async {
    try {
    if (url == null) return null;
    final local = await TicketPreviewAssets.shared.image(url);
    if(local != null) return local;
    final bytes = await DbImages.downloadImage(url);
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    } on ImageDownloadException catch(e) {
      if(allowMissing && [404,410].contains(e.status)) return null;
      rethrow;
    }
  }

  Future<({Uint8List bytes, List<String> warnings})> preview(
    int occasionId,
    String type,
    Map<String, dynamic> layout,
    String scenario,
    String? background,
  ) async {
    final j = await _request({
      'occasionId': occasionId,
      'type': type,
      'mode': 'pdf',
      'fontProtocol': 2,
      'layout': layout,
      'scenario': scenario,
      'background': background,
    });
    return (
      bytes: base64Decode(j['file']),
      warnings: (j['warnings'] as List).cast<String>(),
    );
  }

  final _contexts = <String,Future<Map<String,dynamic>>>{};
  Future<Map<String,dynamic>> _context(Map<String,dynamic> body) {
    final key=jsonEncode([identityKey(),RightsService.currentOccasion()?.aggregateVersion,setupRevision,body]);
    return _contexts.putIfAbsent(key,()=>_request(body).whenComplete((){_contexts.remove(key);}));
  }
  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    if (setupDraftId != null) {
      body = {...body, 'setupDraftId': setupDraftId}
        ..remove('occasionId')
        ..remove('borrowResourcesOnly');
    }
    if (transport != null) return transport!(body);
    final response = await Supabase.instance.client.functions.invoke(
      'preview-ticket-layout',
      body: body,
    );
    if (response.status != 200 || response.data is! Map) {
      throw StateError('Ticket layout request failed');
    }
    return (response.data as Map).cast<String, dynamic>();
  }
}
