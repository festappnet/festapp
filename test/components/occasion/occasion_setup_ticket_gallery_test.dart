import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/fonts/ticket_font_ids.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_template_gallery.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class GalleryService extends TicketLayoutService {
  bool fail = false;
  int calls = 0;
  @override
  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background,
      {bool borrowResourcesOnly = false, bool readOnly = false}) async {
    calls++;
    if (fail) throw StateError('offline');
    final j = jsonDecode(
            File('test/fixtures/ticket_layout/resolve.json').readAsStringSync())
        as Map;
    final metrics = TicketFontMetrics.fromJson(j['metrics']);
    final template = TicketTemplate.fromJson(j['template']);
    return TicketLayoutResources(
        template: layout?['templates']?[type] == null
            ? template
            : TicketTemplate.fromJson(layout!['templates'][type]),
        preset: template,
        presets: (j['presets'] as Map)
            .map((k, v) => MapEntry(k as String, TicketTemplate.fromJson(v))),
        artworks: {},
        scenarios: (j['scenarios'] as Map).map((k, v) =>
            MapEntry(k as String, (v as Map).cast<String, String?>())),
        metrics: metrics,
        fonts: legacyTicketFontIds.map((k, id) =>
            MapEntry(id, TicketFontResource(id, k, 400, metrics, 'test-$k'))),
        qrSize: j['qrMatrix']['size'],
        qrModules: (j['qrMatrix']['data'] as List).cast<int>());
  }
}

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });

  testWidgets(
      'all choices use event colors and font; selection persists and survives reopening',
      (tester) async {
    final feature = TicketFeature(code: 'ticket', isEnabled: true);
    var changes = 0;
    final style = Map.of(OccasionSetupAppearance.presets[1]);
    Widget settings() => Scaffold(
        body: SingleChildScrollView(
            child: EditorDraftScope(
                onChanged: () => changes++,
                child: TicketSettings(
                    feature: feature,
                    occasionId: 0,
                    service: GalleryService(),
                    showTemplateGallery: true,
                    styleTemplate: (t) {
                      final json = t.toJson();
                      OccasionSetupAppearance.styleTicketTemplate(json, style);
                      return TicketTemplate.fromJson(json);
                    }))));
    await environment.pumpWidget(tester, settings());
    await tester.pumpAndSettle();
    expect(changes, 0, reason: 'Loading previews must not dirty the draft');
    final gallery = tester
        .widget<TicketTemplateGallery>(find.byType(TicketTemplateGallery));
    expect(gallery.resources.presets.length, greaterThan(1));
    for (final entry in gallery.resources.presets.entries) {
      expect(
          find.byKey(ValueKey('ticket-template-${entry.key}')), findsOneWidget);
      expect(entry.value.canvasGradient, ['14284B', 'A87F28']);
      expect(entry.value.fontId, legacyTicketFontIds['robotoSlab']);
      expect(entry.value.elements.every((e) => e.fontId == null), isTrue);
      expect(gallery.resources.artworks[entry.key]?.background, isNull);
    }
    final key = gallery.resources.presets.keys.last;
    final choice = find.byKey(ValueKey('ticket-template-$key'));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    final saved = TicketTemplate.fromJson(feature.layout!['templates']['wide']);
    expect(saved.toJson(), gallery.resources.presets[key]!.toJson());
    expect(feature.ticketBackground, isNull);
    expect(changes, 1);
    await tester.pumpWidget(const SizedBox());
    await environment.pumpWidget(tester, settings());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TicketTemplateGallery>(find.byType(TicketTemplateGallery))
            .selected!
            .toJson(),
        saved.toJson());
    tester.view.physicalSize = const Size(375, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(feature.layout!['templates']['wide'], saved.toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed preview can be retried to reveal the gallery',
      (tester) async {
    final service = GalleryService()..fail = true;
    await environment.pumpWidget(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: TicketSettings(
                    feature: TicketFeature(code: 'ticket', isEnabled: true),
                    occasionId: 0,
                    service: service,
                    showTemplateGallery: true))));
    await tester.pumpAndSettle();
    expect(find.byType(TicketTemplateGallery), findsNothing);
    service.fail = false;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.byType(TicketTemplateGallery), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'inline avoids PDF resources and switching back restores saved design',
      (tester) async {
    final service = GalleryService()..fail = true;
    final feature = TicketFeature(
        code: 'ticket',
        isEnabled: true,
        deliveryMode: TicketDeliveryMode.inlineQr);
    await environment.pumpWidget(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: TicketSettings(
                    feature: feature,
                    occasionId: 0,
                    service: service,
                    showTemplateGallery: true))));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.byType(TicketTemplateGallery), findsNothing);
    expect(find.text('Upravit PDF pro tisk'), findsOneWidget);
    service.fail = false;
    final pdf =
        find.widgetWithText(RadioListTile<TicketDeliveryMode>, 'PDF v příloze');
    await tester.ensureVisible(pdf);
    await tester.tap(pdf);
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.byType(TicketTemplateGallery), findsOneWidget);
  });
}
