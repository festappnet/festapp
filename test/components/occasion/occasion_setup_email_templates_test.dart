import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:super_editor/super_editor.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_email_templates.dart';
import 'package:fstapp/components/email_templates/views/email_template_card.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/components/email_templates/views/email_templates_settings_page.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import '../../support/fixtures/root_supabase_fixture.dart';

const codes = [
  'TICKET_ORDER_CONFIRMATION',
  'TICKET_ORDER_PAYMENT_DONE',
  'TICKET_ORDER_REMINDER',
  'TICKET_ORDER_STORNO',
  'TICKET_ORDER_UPDATE'
];
Map<String, dynamic> catalog(Map<String, dynamic> draft) => {
      'emailScope': {
        'unit': {'id': 1, 'title': 'Unit'},
        'organization': {'id': 3, 'title': 'Org'}
      },
      'authoringContext': {'senderAddress': 'sender@example.invalid'},
      'previewContext': {'title': 'My event', 'products': []},
      'emailTemplates': [
        for (final code in codes)
          {
            'code': code,
            'customized':
                (draft['emailTemplateOverrides'] as Map?)?.containsKey(code) ??
                    false,
            'template': {
              'code': code,
              'subject': 'Subject',
              'html': '<p>Body</p>',
              'unit': 1,
              ...?((draft['emailTemplateOverrides'] as Map?)?[code] as Map?)
            },
          }
      ],
    };
void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  setUpAll(() async {
    backend = await RootSupabaseFixture.open(
        (request) => http.Response('{}', 200, request: request));
  });
  tearDownAll(() async => backend.dispose());
  for (final size in [const Size(320, 800), const Size(1200, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all five email cards fit $size at scale $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final translations =
            jsonDecode(File('assets/translations/cs.json').readAsStringSync());
        await WidgetEnvironmentFixture(
                locale: const Locale('cs'), translations: translations)
            .pumpWidget(
                tester,
                MaterialApp(
                    home: MediaQuery(
                        data: MediaQueryData(
                            size: size, textScaler: TextScaler.linear(scale)),
                        child: Scaffold(
                            body: SingleChildScrollView(
                                child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: OccasionSetupEmailTemplates(
                                        draft: {},
                                        loadPreview: (draft) async =>
                                            catalog(draft),
                                        onChanged: (_) {})))))));
        await tester.pumpAndSettle();
        expect(find.byType(EmailTemplateCard), findsNWidgets(5));
        expect(tester.takeException(), isNull);
        for (final element in find.byType(EmailTemplateCard).evaluate()) {
          final box = element.renderObject! as RenderBox;
          final point = box.localToGlobal(Offset.zero);
          expect(point.dx + box.size.width, lessThanOrEqualTo(size.width));
        }
      });
    }
  }
  testWidgets(
      'editing saves only a draft override and never updates the unit template',
      (tester) async {
    final translations =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync());
    final draft = <String, dynamic>{};
    final patches = <Map<String, dynamic>>[];
    await WidgetEnvironmentFixture(
            locale: const Locale('cs'), translations: translations)
        .pumpWidget(
            tester,
            MaterialApp(
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: OccasionSetupEmailTemplates(
                            draft: draft,
                            loadPreview: (value) async => catalog(draft),
                            onChanged: (patch) {
                              draft.addAll(patch);
                              patches.add(patch);
                            })))));
    await tester.pumpAndSettle();
    final card =
        tester.widget<EmailTemplateCard>(find.byType(EmailTemplateCard).first);
    card.onEdit();
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    expect(find.text(EmailTemplatesStrings.resetToDefault), findsNothing);
    final subject = tester
        .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
        .first
        .controller;
    final node = subject.editor.document.first as TextNode;
    subject.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id, nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Edited ',
          attributions: {})
    ]);
    await tester.pump();
    await tester.tap(find.text('Uložit'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsNothing);
    expect(patches, hasLength(1));
    expect((draft['emailTemplateOverrides'] as Map)[codes.first]['subject'],
        'Edited Subject');
    expect(
        backend.requests.where((r) =>
            r.url.path.contains('update_email_template') ||
            r.url.path.contains('delete_entity_email_template')),
        isEmpty);
  });
}
