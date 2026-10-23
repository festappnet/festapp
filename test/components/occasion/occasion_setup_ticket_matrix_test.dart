import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_ticket_gallery.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_controller.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';
import 'package:fstapp/components/ticket_layout/ticket_preview_assets.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_layout_canvas.dart';

void main() {
  WidgetEnvironmentFixture.register();
  final environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>);
  final manifest = jsonDecode(
      File('supabase/functions/_shared/ticket-assets/preview-manifest.json')
          .readAsStringSync()) as Map;
  final templates = (manifest['presets'] as Map)
      .map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v)));
  test(
      'all original designs, named variants and both silk modes remain available',
      () {
    expect(templates.length, 15);
    expect(
        templates.keys,
        containsAll([
          'concert_stub',
          'ball_silk',
          'portrait',
          'festival_badge',
          'silk_light',
          'silk_dark'
        ]));
    expect(templates.keys, isNot(contains('classic')));
    expect(templates.keys, isNot(contains('compact')));
    expect(templates.keys, isNot(contains('event')));
    for (final template in templates.values) {
      expect(
          (template['elements'] as List)
              .where((e) => e['binding'] == 'price' && e['visible']),
          hasLength(1));
    }
    for (final vector in manifest['themeColorVectors']) {
      final appearance = OccasionSetupAppearance.presets
          .singleWhere((p) => p['id'] == vector[0]);
      expect(
          OccasionSetupAppearance.themeColor(vector[1], appearance), vector[2],
          reason: '$vector');
    }
    for (final appearance in OccasionSetupAppearance.presets) {
      for (final entry in templates.entries) {
        final styled = OccasionSetupAppearance.styledTemplate(
            entry.value, appearance,
            decorated: true, composition: entry.key);
        validateTicketLayout({
          'schemaVersion': 3,
          'templates': {'wide': styled, 'named': styled}
        });
        expect((styled['elements'] as List).map((e) => e['box']),
            (entry.value['elements'] as List).map((e) => e['box']));
      }
    }
  });
  test('every styled background exists in the bundled asset manifest', () {
    for (final appearance in OccasionSetupAppearance.presets) {
      for (final key in templates.keys) {
        final background =
            OccasionSetupAppearance.ticketBackground(key, appearance) ??
                manifest['backgrounds'][key];
        if (background != null) {
          expect(
              (manifest['artwork'] as Map).containsKey(background) ||
                  background.contains('/palette-'),
              isTrue,
              reason: '$key/${appearance['id']}: $background');
        }
      }
    }
  });
  test(
      'repeated style changes use the chosen original and preserve its composition',
      () {
    final source = templates['concert_stub']!;
    final draft = <String, dynamic>{
      'formDraft': {'data': {}},
      'ticketTemplateId': 'concert_stub',
      'ticketTemplateSource': source,
      'ticketDraft': {
        'code': 'ticket',
        'layout': {
          'schemaVersion': 3,
          'templates': {'wide': source}
        }
      }
    };
    for (final appearance in OccasionSetupAppearance.presets) {
      OccasionSetupAppearance.apply(draft, Map.of(appearance));
      final expected = OccasionSetupAppearance.styledTemplate(
          source, appearance,
          decorated: true, composition: 'concert_stub');
      expect(draft['ticketDraft']['layout']['templates']['wide'], expected);
      expect(draft['ticketDraft']['background'],
          OccasionSetupAppearance.ticketBackground('concert_stub', appearance));
    }
  });
  testWidgets(
      'all palette sources retain their colors through selection and PDF parity',
      (tester) async {
    final proofPath = Platform.environment['TICKET_CUSTOM_ARTWORK_EVIDENCE'];
    final proofs = proofPath == null
        ? <dynamic>[
            {'key': 'concert_stub', 'primary': '198A61', 'secondary': 'DE5734'}
          ]
        : jsonDecode(File(proofPath).readAsStringSync()) as List;
    for (final proof in proofs) {
      final appearance = {
        ...OccasionSetupAppearance.presets.first,
        'id': 'custom',
        'primary': proof['primary'],
        'secondary': proof['secondary'],
        'gradient': true
      };
      final url =
          OccasionSetupAppearance.ticketBackground(proof['key'], appearance)!;
      final image =
          await tester.runAsync(() => TicketPreviewAssets.shared.image(url));
      expect(image, isNotNull);
      if (proofPath != null) {
        expect(url, proof['url']);
        expect([image!.width, image.height], [proof['width'], proof['height']]);
        final rgba = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba));
        expect(
            sha256
                .convert(rgba!.buffer
                    .asUint8List(rgba.offsetInBytes, rgba.lengthInBytes))
                .toString(),
            proof['rgbaSha']);
      }
      image!.dispose();
      final draft = <String, dynamic>{
        'formDraft': {'data': {}},
        'ticketTemplateId': proof['key'],
        'ticketTemplateSource': templates[proof['key']],
        'ticketDraft': {
          'layout': {
            'schemaVersion': 3,
            'templates': {'wide': templates[proof['key']]}
          }
        }
      };
      OccasionSetupAppearance.apply(draft, appearance);
      expect(draft['ticketDraft']['background'], url);
    }
  });
  testWidgets(
      'full catalog canvas evidence uses actual prices and the same templates as PDFs',
      (tester) async {
    final path = Platform.environment['TICKET_CATALOG_EVIDENCE'];
    if (path == null) return;
    await tester.runAsync(() async {
      final scenes =
          jsonDecode(File('$path/contexts.json').readAsStringSync()) as List;
      for (final scene in scenes) {
        final appearance = OccasionSetupAppearance.presets
            .singleWhere((p) => p['id'] == scene['style']);
        final expected = TicketTemplate.fromJson(scene['reply']['template']);
        final actual = TicketTemplate.fromJson(
            OccasionSetupAppearance.styledTemplate(scene['source'], appearance,
                decorated: true, composition: scene['key']));
        expect(actual.toJson(), expected.toJson(), reason: scene['name']);
        final r = await TicketLayoutService(
                transport: (_) async =>
                    Map<String, dynamic>.from(scene['reply']))
            .resolve(7, 'wide', null, null);
        final bindings = r.previewData(r.template, 'normal');
        for (final title
            in r.template.elements.where((e) => e.binding == 'occasionTitle')) {
          final actualTitle = bindings[title.id]!;
          final fit = fitTicketText(
              actualTitle, title, r.metricsFor(r.template, title));
          expect(fit.overflow, isFalse);
          expect(fit.lines.join(' '),
              actualTitle.replaceAll(RegExp(r'\s+'), ' ').trim(),
              reason: scene['name']);
          const longWord = 'NejkrásnějšíSlavnostníVečerVNašemKulturnímDomě';
          final longFit =
              fitTicketText(longWord, title, r.metricsFor(r.template, title));
          expect(longFit.lines, [longWord], reason: scene['name']);
          expect(longFit.overflow, isFalse);
        }

        final price =
            r.template.elements.singleWhere((e) => e.binding == 'price');
        expect(bindings[price.id], contains('350'));
        final c = TicketLayoutController(r.template),
            recorder = ui.PictureRecorder();
        TicketLayoutPainter(c, r, bindings)
            .paint(Canvas(recorder), r.template.page);
        final picture = recorder.endRecording(),
            image = await picture.toImage(
                r.template.page.width.ceil(), r.template.page.height.ceil());
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$path/${scene['name']}-canvas.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        c.dispose();
        r.dispose();
      }
      expect(scenes.length,
          templates.length * OccasionSetupAppearance.presets.length);
    });
  });
  testWidgets(
      'gallery exposes full collection, named filter and both silk variants',
      (tester) async {
    OccasionSetupTicketChoice? choice;
    final fixture = jsonDecode(
        File('test/fixtures/ticket_layout/resolve.json').readAsStringSync());
    final r = await tester.runAsync(() => TicketLayoutService(
        transport: (_) async => {
              'resourceProtocol': 3,
              'template': templates['concert_stub'],
              'preset': templates['concert_stub'],
              'fontIds': [templates['concert_stub']!['fontId']],
              'scenarios': fixture['scenarios'],
              'catalog': [],
              'backgroundUrl': null,
              'logoUrl': null,
            }).resolve(7, 'wide', null, null));
    // Resolve the selected shared font before mounting, as the setup owner does.
    await tester.runAsync(() => r!.prepareTemplate(TicketTemplate.fromJson(
        OccasionSetupAppearance.styledTemplate(
            templates['concert_stub']!, OccasionSetupAppearance.presets[1],
            decorated: true, composition: 'concert_stub'))));
    final artwork = <String, TicketLayoutArtwork>{};
    await tester.runAsync(() async {
      for (final key in templates.keys) {
        final background = OccasionSetupAppearance.ticketBackground(
                key, OccasionSetupAppearance.presets[1]) ??
            r!.artworks[key]?.background;
        artwork[key] = TicketLayoutArtwork(
            label: null,
            background: background,
            image: background == null
                ? null
                : await TicketPreviewAssets.shared.image(background));
      }
    });
    final ready = TicketLayoutResources(
        template: r!.template,
        preset: r.preset,
        presets: r.presets,
        metrics: r.metrics,
        fonts: r.fonts,
        scenarios: r.scenarios,
        catalog: r.catalog,
        qrSize: r.qrSize,
        qrModules: r.qrModules,
        artworks: artwork);
    r.dispose();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: OccasionSetupTicketGallery(
          appearance: Map.of(OccasionSetupAppearance.presets[1]),
          loadResources: () async => ready,
          onSelected: (selected) => choice = selected,
        )))));
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pumpAndSettle();
    }

    await settle();
    expect(find.text('Všechny (15)'), findsOneWidget);
    for (final key in templates.keys) {
      expect(
          find.byKey(ValueKey('setup-ticket-template-$key')), findsOneWidget);
    }
    expect(find.text('Další'), findsNothing);
    expect(find.text('Předchozí'), findsNothing);
    for (final key in ['silk_light', 'silk_dark']) {
      expect(ready.artworks[key]!.image, isNotNull,
          reason: '$key must contain actual silk artwork');
    }
    final concert =
        find.byKey(const ValueKey('setup-ticket-template-concert_stub'));
    await tester.ensureVisible(concert);
    await tester.tap(concert);
    expect(choice!.key, 'concert_stub');
    expect(choice!.source,
        TicketTemplate.fromJson(templates['concert_stub']!).toJson());
    expect(
        choice!.background,
        OccasionSetupAppearance.ticketBackground(
            'concert_stub', OccasionSetupAppearance.presets[1]));
    await tester.ensureVisible(find.text('Se jménem'));
    await tester.tap(find.text('Se jménem'));
    await settle();
    expect(find.byKey(const ValueKey('setup-ticket-template-club_panorama')),
        findsNothing);
    await tester.ensureVisible(find.text('Hedvábí'));
    await tester.tap(find.text('Hedvábí'));
    await settle();
    expect(find.byKey(const ValueKey('setup-ticket-template-silk_light')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('setup-ticket-template-silk_dark')),
        findsOneWidget);
    expect(
        find.textContaining('Šablonu si můžete dále upravit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await environment.pumpWidget(tester, const SizedBox());
  });
}
