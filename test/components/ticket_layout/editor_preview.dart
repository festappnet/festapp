// The actual editor with local fixtures. No production connection or writes.
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_layout_editor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final fixture = jsonDecode(
      (await http.get(Uri.base.resolve('fixtures/ticket_layout/resolve.json')))
          .body) as Map;
  fixture['historical'] = jsonDecode((await http.get(
          Uri.base.resolve('fixtures/ticket_layout/historical/catalog.json')))
      .body);
  final resolved = await previewRequest(
      {'occasionId': 1, 'mode': 'resolve', 'type': 'wide', 'background': null});
  for (final key in ['scenarios', 'metrics', 'qrMatrix']) {
    fixture[key] = resolved[key];
  }
  await (FontLoader('TicketLayoutFont')
        ..addFont(rootBundle.load('fonts/Futura PT Book.ttf')))
      .load();
  runApp(EasyLocalization(
      supportedLocales: const [Locale('cs'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('cs'),
      child: Builder(
          builder: (context) => MaterialApp(
              theme: ThemeData(fontFamily: 'TicketLayoutFont'),
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: _Preview(fixture: fixture)))));
}

Future<Map<String, dynamic>> previewRequest(Map<String, dynamic> body) async {
  final background = body['background'] as String?;
  final response = await http.post(Uri.base.resolve('api/ticket-preview'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer local-preview'
      },
      body: jsonEncode({
        ...body,
        'background': background == null
            ? null
            : 'https://img.festapp.net/__local_preview__/${Uri.encodeComponent(background)}'
      }));
  final result = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200) {
    throw StateError(result['error'] ?? 'PDF preview failed');
  }
  if (result.containsKey('backgroundUrl')) result['backgroundUrl'] = background;
  return result;
}

class _PreviewService extends TicketLayoutService {
  final List catalog;
  _PreviewService(this.catalog) : super(transport: previewRequest);
  @override
  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background) async {
    final result = await super.resolve(occasionId, type, layout, background);
    if (type != 'wide') return result;
    try {
      for (final key in ['compact', 'event']) {
        result.presets.remove(key);
        result.artworks.remove(key)?.image?.dispose();
      }
      for (final raw in catalog) {
        final item = raw as Map;
        ui.Image? image;
        final path = item['image'] == null
            ? null
            : 'fixtures/ticket_layout/historical/${item['image']}';
        if (path != null) {
          final response = await http.get(Uri.base.resolve(path));
          if (response.statusCode != 200) {
            throw StateError('Missing background');
          }
          final codec = await ui.instantiateImageCodec(response.bodyBytes);
          try {
            image = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        }
        result.artworks.remove(item['id'])?.image?.dispose();
        result.artworks[item['id']] = TicketLayoutArtwork(
            label: item['label'], background: path, image: image);
        result.presets[item['id']] = TicketTemplate.fromJson(item['template']);
      }
      return result;
    } catch (_) {
      result.dispose();
      rethrow;
    }
  }

  @override
  Future<String?> uploadBackground(Uint8List bytes, int occasionId) async {
    final response = await http.post(Uri.base.resolve('api/ticket-background'),
        headers: {'Content-Type': 'application/octet-stream'}, body: bytes);
    if (response.statusCode != 200) {
      throw StateError('Obrázek se nepodařilo nahrát.');
    }
    return (jsonDecode(response.body) as Map)['background'] as String;
  }
}

class _Preview extends StatefulWidget {
  final Map fixture;
  const _Preview({required this.fixture});
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final drafts = <String, TicketTemplate>{};
  String selectedArtwork = 'cream';
  String? uploadedBackground;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        edit(Uri.base.queryParameters['type'] == 'named' ? 'named' : 'wide'));
  }

  Future<ui.Image> loadImage(String path) async {
    final response = await http.get(Uri.base.resolve(path));
    if (response.statusCode != 200) {
      throw StateError('Obrázek se nepodařilo načíst.');
    }
    final codec = await ui.instantiateImageCodec(response.bodyBytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> edit(String type) async {
    if (busy) return;
    setState(() => busy = true);
    final f = widget.fixture;
    final artworks = <String, TicketLayoutArtwork>{};
    TicketLayoutResources? resources;
    try {
      final presets = <String, TicketTemplate>{};
      if (type == 'wide') {
        for (final raw in f['historical'] as List) {
          final item = raw as Map;
          final key = item['id'] as String;
          final path = item['image'] == null
              ? null
              : 'fixtures/ticket_layout/historical/${item['image']}';
          artworks[key] = TicketLayoutArtwork(
              label: item['label'],
              background: path,
              image: path == null ? null : await loadImage(path));
          presets[key] = TicketTemplate.fromJson(item['template']);
        }
      } else {
        final choices = await previewRequest({
          'occasionId': 1,
          'mode': 'resolve',
          'type': type,
          'background': null
        });
        presets.addAll((choices['presets'] as Map).map((key, value) =>
            MapEntry(key as String, TicketTemplate.fromJson(value))));
      }
      if (type == 'wide' && uploadedBackground != null) {
        artworks['uploaded'] = TicketLayoutArtwork(
            label: 'Vlastní pozadí',
            background: uploadedBackground,
            image: await loadImage(uploadedBackground!));
        presets['uploaded'] = drafts[type]!;
        selectedArtwork = 'uploaded';
      }
      final initialKey = type == 'wide' ? selectedArtwork : 'classic';
      resources = TicketLayoutResources(
          template: drafts[type] ?? presets[initialKey]!,
          preset: presets[initialKey]!,
          presets: presets,
          artworks: artworks,
          initialArtworkKey: type == 'wide' ? initialKey : null,
          scenarios: (f['scenarios'] as Map).map((key, value) =>
              MapEntry(key as String, (value as Map).cast<String, String?>())),
          metrics: TicketFontMetrics.fromJson(f['metrics']),
          qrSize: f['qrMatrix']['size'],
          qrModules: (f['qrMatrix']['data'] as List).cast<int>());
      if (!mounted) {
        resources.dispose();
        return;
      }
      final result = await showDialog<TicketLayoutResult>(
          context: context,
          useSafeArea: false,
          builder: (_) => Dialog.fullscreen(
              child: TicketLayoutEditor(
                  showTemplatePicker: !drafts.containsKey(type),
                  occasionId: 1,
                  type: type,
                  background: artworks[initialKey]?.background,
                  resources: resources!,
                  service:
                      _PreviewService(widget.fixture['historical'] as List))));
      // The editor owns/disposes resources once mounted.
      if (result != null) {
        drafts[type] = result.template;
        if (type == 'wide') {
          final choice = artworks.entries
              .where((entry) => entry.value.background == result.background)
              .firstOrNull;
          selectedArtwork = choice?.key ?? 'cream';
          uploadedBackground = choice == null || choice.key == 'uploaded'
              ? result.background
              : null;
        }
      }
    } catch (error) {
      if (resources == null) {
        for (final artwork in artworks.values) {
          artwork.image?.dispose();
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Editor vstupenek')),
      body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        FilledButton(
            onPressed: busy ? null : () => edit('wide'),
            child: const Text('Otevřít editor vstupenky')),
        const SizedBox(height: 16),
        TextButton(
            onPressed: busy ? null : () => edit('named'),
            child: const Text('Jmenná vstupenka')),
        const SizedBox(height: 24),
        const Text('Předlohy vyberete uvnitř editoru přes Šablony vstupenek.'),
        const Text(
            'Lokální ukázka. Původní názvy a data jsou součástí obrázků.'),
      ])));
}
