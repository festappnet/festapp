import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/fonts/ticket_font_ids.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_ticket_gallery.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';

void main() {
  testWidgets('mounting gallery may notify the parent save state safely',
      (tester) async {
    final fixture = jsonDecode(
            File('test/fixtures/ticket_layout/resolve.json').readAsStringSync())
        as Map;
    final template = TicketTemplate.fromJson(fixture['template']);
    final metrics = TicketFontMetrics.fromJson(fixture['metrics']);
    var status = 'pending';
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, update) => Scaffold(
                  body: Column(children: [
                    Text(status),
                    Expanded(
                        child: SingleChildScrollView(
                            child: OccasionSetupTicketGallery(
                      appearance: Map.of(OccasionSetupAppearance.presets.first),
                      loadResources: () async {
                        update(() => status = 'saved');
                        return TicketLayoutResources(
                            template: template,
                            preset: template,
                            presets: {'first': template},
                            metrics: metrics,
                            fonts: legacyTicketFontIds.map((name, id) =>
                                MapEntry(
                                    id,
                                    TicketFontResource(
                                        id, name, 400, metrics, 'TestFont'))),
                            scenarios: (fixture['scenarios'] as Map).map(
                                (k, v) => MapEntry(k as String,
                                    (v as Map).cast<String, String?>())),
                            qrSize: fixture['qrMatrix']['size'],
                            qrModules: (fixture['qrMatrix']['data'] as List)
                                .cast<int>());
                      },
                      onSelected: (_) {},
                    )))
                  ]),
                ))));
    await tester.pumpAndSettle();
    expect(find.text('saved'), findsOneWidget);
    expect(find.text('Zkusit znovu'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'gallery retries and keeps actual custom ticket distinct from replacement presets',
      (tester) async {
    final fixture = jsonDecode(
            File('test/fixtures/ticket_layout/resolve.json').readAsStringSync())
        as Map;
    final template = TicketTemplate.fromJson(fixture['template']);
    final metrics = TicketFontMetrics.fromJson(fixture['metrics']);
    var attempts = 0;
    OccasionSetupTicketChoice? choice;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: OccasionSetupTicketGallery(
      appearance: Map.of(OccasionSetupAppearance.presets[1]),
      currentTemplate: template.toJson(),
      loadResources: () async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
        return TicketLayoutResources(
            template: template,
            preset: template,
            presets: {'first': template, 'second': template},
            metrics: metrics,
            fonts: legacyTicketFontIds.map((name, id) => MapEntry(
                id, TicketFontResource(id, name, 400, metrics, 'TestFont'))),
            scenarios: (fixture['scenarios'] as Map).map((k, v) =>
                MapEntry(k as String, (v as Map).cast<String, String?>())),
            qrSize: fixture['qrMatrix']['size'],
            qrModules: (fixture['qrMatrix']['data'] as List).cast<int>());
      },
      onSelected: (entry) => choice = entry,
    )))));
    await tester.pumpAndSettle();
    expect(
        find.text('Náhledy vstupenek se nepodařilo načíst.'), findsOneWidget);
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final current = find.byKey(const ValueKey('setup-ticket-template-current'));
    await tester.ensureVisible(current);
    await tester.tap(current);
    expect(choice, isNull);
    final first = find.byKey(const ValueKey('setup-ticket-template-first'));
    await tester.ensureVisible(first);
    await tester.tap(first);
    expect(choice!.key, 'first');
    expect(choice!.value['canvasGradient'], ['14284B', 'A87F28']);
    expect(choice!.value['fontId'], legacyTicketFontIds['robotoSlab']);
    expect(choice!.value['elements'], isNotEmpty);
    expect(attempts, 2);
  });
}
